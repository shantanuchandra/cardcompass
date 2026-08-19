import { assertEquals, assertRejects } from "@std/assert";
import {
  customerActionHandlers,
  handleCustomerDetail,
  handleCustomerDisable,
  handleCustomerSearch,
} from "./customers.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";
import { handleAdminOperator } from "./index.ts";

const ACTOR = "00000000-0000-4000-8000-000000000001";
const USER = "00000000-0000-4000-8000-000000000002";
const REQUEST = "00000000-0000-4000-8000-000000000003";
const UPDATED = "2026-08-19T10:00:00Z";

function context(db: unknown, authAdmin?: unknown): AdminActionContext {
  return { actor: { id: ACTOR }, requestId: null, db, authAdmin } as never;
}

function query(result: unknown, calls: unknown[]) {
  const chain: Record<string, unknown> = {};
  for (const method of ["select", "eq", "ilike", "order", "range", "limit"]) {
    chain[method] = (...args: unknown[]) => {
      calls.push([method, ...args]);
      return method === "range" || method === "limit"
        ? Promise.resolve(result)
        : chain;
    };
  }
  return chain;
}

Deno.test("customer search rejects short fragments and unknown keys before querying", async () => {
  for (
    const body of [
      { action: "customer-search", query: "ab", request_id: REQUEST },
      {
        action: "customer-search",
        query: "alice",
        request_id: REQUEST,
        raw_sql: "select *",
      },
    ]
  ) {
    const error = await assertRejects(
      () =>
        handleCustomerSearch(
          body,
          context({
            from: () => {
              throw Error("queried");
            },
          }),
        ),
      AdminHttpError,
    );
    assertEquals(error.code, "invalid_request");
  }
});

Deno.test("customer search uses an exact UUID or escaped normalized email fragment, caps 25, and orders deterministically", async () => {
  for (
    const [input, expectedFilter] of [
      [USER, ["eq", "id", USER]],
      ["  AL%_Ice  ", ["ilike", "email", "%al\\%\\_ice%"]],
    ] as const
  ) {
    const calls: unknown[] = [];
    const db = {
      rpc: (_name: string, _args: unknown) =>
        Promise.resolve({ data: REQUEST, error: null }),
      from: (table: string) => {
        assertEquals(table, "users");
        return query({
          data: [{
            id: USER,
            email: "Alice@Example.COM",
            created_at: UPDATED,
            updated_at: UPDATED,
            is_active: true,
          }],
          error: null,
        }, calls);
      },
    };
    const output = await handleCustomerSearch(
      {
        action: "customer-search",
        query: input,
        limit: 999,
        request_id: REQUEST,
      },
      context(db),
    );
    assertEquals(
      calls.some((call) =>
        JSON.stringify(call) === JSON.stringify(expectedFilter)
      ),
      true,
    );
    assertEquals(calls.slice(-3), [
      ["order", "email", { ascending: true }],
      ["order", "id", { ascending: true }],
      ["range", 0, 24],
    ]);
    assertEquals(output, {
      items: [{
        id: USER,
        email: "alice@example.com",
        created_at: UPDATED,
        last_activity_at: UPDATED,
        is_active: true,
      }],
    });
  }
});

Deno.test("customer detail audits before every data source and presents only bounded metadata", async () => {
  const events: string[] = [];
  const db = {
    rpc: (name: string, args: unknown) => {
      events.push(`rpc:${name}`);
      assertEquals(name, "record_admin_read");
      assertEquals((args as any)._target_id, USER);
      return Promise.resolve({ data: null, error: null });
    },
    from: (table: string) => {
      events.push(`from:${table}`);
      const data: Record<string, unknown[]> = {
        users: [{
          id: USER,
          email: "USER@Example.com",
          created_at: UPDATED,
          updated_at: UPDATED,
          is_active: true,
        }],
        user_cards: [],
        statements: [],
        emails: [],
        admin_customer_operation_requests: [{
          status: "failed",
          safe_failure_category: "gmail_unavailable",
          updated_at: UPDATED,
        }],
        account_deletion_requests: [{
          status: "verified",
          updated_at: UPDATED,
        }],
      };
      const result =
        table === "user_cards" || table === "statements" || table === "emails"
          ? {
            data: [],
            count: table === "user_cards" ? 2 : table === "statements" ? 3 : 4,
            error: null,
          }
          : { data: data[table], error: null };
      return query(result, []);
    },
  };
  const authAdmin = {
    getUserById: (id: string) => {
      events.push("auth:getUserById");
      assertEquals(id, USER);
      return Promise.resolve({
        data: {
          user: {
            identities: [{
              provider: "google",
              identity_data: { access_token: "forbidden" },
            }],
          },
        },
        error: null,
      });
    },
  };
  const output = await handleCustomerDetail(
    { action: "customer-detail", target_id: USER, request_id: REQUEST },
    context(db, authAdmin),
  );
  assertEquals(events[0], "rpc:record_admin_read");
  assertEquals(output, {
    customer: {
      id: USER,
      email: "user@example.com",
      created_at: UPDATED,
      last_activity_at: UPDATED,
      is_active: true,
      gmail_connected: true,
      gmail_last_status: "failed",
      gmail_last_failure_category: "gmail_unavailable",
      gmail_last_updated_at: UPDATED,
      owned_card_count: 2,
      statement_count: 3,
      processed_statement_count: 3,
      email_count: 4,
      processed_email_count: 4,
      latest_statement_at: null,
      latest_email_at: null,
      deletion_status: "verified",
      deletion_updated_at: UPDATED,
    },
  });
  const serialized = JSON.stringify(output);
  for (
    const forbidden of [
      "access_token",
      "identity_data",
      "subject",
      "sender",
      "body",
      "transaction",
    ]
  ) {
    assertEquals(serialized.includes(forbidden), false);
  }
});

Deno.test("customer detail fails closed when read audit fails and does not touch data or Auth", async () => {
  let reads = 0;
  const error = await assertRejects(() =>
    handleCustomerDetail(
      { action: "customer-detail", target_id: USER, request_id: REQUEST },
      context({
        rpc: () =>
          Promise.resolve({ data: null, error: { message: "secret SQL" } }),
        from: () => {
          reads += 1;
        },
      }, {
        getUserById: () => {
          reads += 1;
        },
      }),
    ), AdminHttpError);
  assertEquals(error.code, "request_failed");
  assertEquals(reads, 0);
});

Deno.test("disable applies audited database containment before Auth ban and validates its receipt", async () => {
  const events: string[] = [];
  const db = {
    rpc: (name: string, args: any) => {
      events.push(`db:${name}`);
      assertEquals(args._action, "disable_account");
      return Promise.resolve({
        data: { user_id: USER, is_active: false },
        error: null,
      });
    },
  };
  const authAdmin = {
    updateUserById: (id: string, attributes: unknown) => {
      events.push("auth:ban");
      assertEquals([id, attributes], [USER, { ban_duration: "876000h" }]);
      return Promise.resolve({ data: {}, error: null });
    },
  };
  const output = await handleCustomerDisable({
    action: "customer-disable",
    target_id: USER,
    confirmation_user_id: USER,
    request_id: REQUEST,
    observed_updated_at: UPDATED,
    reason: "suspected compromise",
  }, context(db, authAdmin));
  assertEquals(events, ["db:admin_customer_action", "auth:ban"]);
  assertEquals(output, {
    result: { user_id: USER, is_active: false, auth_banned: true },
  });
});

Deno.test("disable preserves containment receipt and returns auth_ban_pending on every replayed ban failure", async () => {
  let databaseCalls = 0;
  let banCalls = 0;
  const args = {
    action: "customer-disable",
    target_id: USER,
    confirmation_user_id: USER,
    request_id: REQUEST,
    observed_updated_at: UPDATED,
    reason: "abuse containment",
  };
  const ctx = context({
    rpc: () => {
      databaseCalls++;
      return Promise.resolve({
        data: { user_id: USER, is_active: false },
        error: null,
      });
    },
  }, {
    updateUserById: () => {
      banCalls++;
      return Promise.resolve({
        data: {},
        error: { message: "raw provider secret" },
      });
    },
  });
  for (let attempt = 1; attempt <= 2; attempt++) {
    const error = await assertRejects(
      () => handleCustomerDisable(args, ctx),
      AdminHttpError,
    );
    assertEquals(error.code, "auth_ban_pending");
  }
  assertEquals([databaseCalls, banCalls], [2, 2]);
});

Deno.test("customer action registry is frozen, null-prototype, and complete", () => {
  assertEquals(Object.getPrototypeOf(customerActionHandlers), null);
  assertEquals(Object.isFrozen(customerActionHandlers), true);
  assertEquals(Object.keys(customerActionHandlers).sort(), [
    "customer-deletion-status",
    "customer-detail",
    "customer-disable",
    "customer-retry",
    "customer-search",
  ]);
});

Deno.test("router executes customer retry and deletion handlers with canonical receipts", async () => {
  const calls: any[] = [];
  const db = {
    rpc: (name: string, args: any) => {
      calls.push([name, args]);
      return Promise.resolve({
        data: args._action === "request_gmail_sync"
          ? { request_id: REQUEST, status: "queued" }
          : { user_id: USER, status: "scheduled", updated_at: UPDATED },
        error: null,
      });
    },
  };
  const cases = [
    [
      {
        action: "customer-retry",
        target_id: USER,
        request_id: REQUEST,
        observed_updated_at: UPDATED,
      },
      { result: { request_id: REQUEST, status: "queued" } },
    ],
    [
      {
        action: "customer-deletion-status",
        target_id: USER,
        request_id: REQUEST,
        observed_updated_at: UPDATED,
        status: "scheduled",
        reason: "verified request",
      },
      { result: { user_id: USER, status: "scheduled", updated_at: UPDATED } },
    ],
  ] as const;
  for (const [body, expected] of cases) {
    const response = await handleAdminOperator(
      new Request("http://local", {
        method: "POST",
        body: JSON.stringify(body),
      }),
      { authorize: () => Promise.resolve({ id: ACTOR }), db: db as never },
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), expected);
  }
  assertEquals(calls.map((entry) => entry[1]._action), [
    "request_gmail_sync",
    "set_deletion_status",
  ]);
});

Deno.test("router maps validation and raw dependency failures to stable non-leaking codes", async () => {
  const cases = [
    [
      {
        action: "customer-disable",
        target_id: USER,
        confirmation_user_id: ACTOR,
        request_id: REQUEST,
        observed_updated_at: UPDATED,
        reason: "compromise",
      },
      {},
      "invalid_request",
      400,
    ],
    [
      {
        action: "customer-deletion-status",
        target_id: USER,
        request_id: REQUEST,
        observed_updated_at: UPDATED,
        status: "deleted",
        reason: "bad",
      },
      {},
      "invalid_request",
      400,
    ],
    [
      {
        action: "customer-retry",
        target_id: USER,
        request_id: REQUEST,
        observed_updated_at: UPDATED,
      },
      {
        rpc: () =>
          Promise.resolve({
            data: null,
            error: { message: "SQL token=secret" },
          }),
      },
      "request_failed",
      500,
    ],
  ] as const;
  for (const [body, db, code, status] of cases) {
    const response = await handleAdminOperator(
      new Request("http://local", {
        method: "POST",
        body: JSON.stringify(body),
      }),
      { authorize: () => Promise.resolve({ id: ACTOR }), db: db as never },
    );
    assertEquals(response.status, status);
    const payload = await response.json();
    assertEquals(payload, { error: code });
    assertEquals(JSON.stringify(payload).includes("secret"), false);
  }
});
