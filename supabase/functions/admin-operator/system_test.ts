import { assertEquals, assertRejects } from "@std/assert";
import {
  handleSystemControl,
  handleSystemJobs,
  handleSystemMutation,
  handleSystemStatus,
  systemActionHandlers,
} from "./system.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

type Call = { kind: string; name: string; args: unknown };

function context(options: {
  rows?: Record<string, unknown[]>;
  errors?: Record<string, { message: string }>;
  rpcError?: { message: string } | null;
  calls?: Call[];
} = {}): AdminActionContext {
  const calls = options.calls ?? [];
  return {
    actor: { id: "00000000-0000-4000-8000-000000000001" },
    requestId: null,
    db: {
      from(table: string) {
        calls.push({ kind: "from", name: table, args: null });
        const query: Record<string, (...args: unknown[]) => unknown> = {};
        for (const method of ["select", "eq", "order"]) {
          query[method] = (...args: unknown[]) => {
            calls.push({ kind: method, name: table, args });
            return query;
          };
        }
        query.range = (...args: unknown[]) => {
          calls.push({ kind: "range", name: table, args });
          return Promise.resolve({
            data: options.rows?.[table] ?? [],
            error: options.errors?.[table] ?? null,
          });
        };
        return query as never;
      },
      rpc(name, args) {
        calls.push({ kind: "rpc", name, args });
        return Promise.resolve({
          data: name === "admin_set_runtime_control"
            ? {
              control_key: "benefit_enrichment_scheduled",
              is_paused: true,
              reason: "maintenance",
              updated_at: "2026-08-19T12:01:00Z",
              secret: "drop",
            }
            : {
              job_id: "00000000-0000-4000-8000-000000000010",
              resulting_status: "queued",
              provider: "drop",
            },
          error: options.rpcError ?? null,
        });
      },
    },
  };
}

Deno.test("system status isolates a failed source and returns exact bounded DTOs", async () => {
  const output = await handleSystemStatus(
    { action: "system-status" },
    context({
      errors: { card_discovery_jobs: { message: "password=secret" } },
      rows: {
        card_catalog_enrichment_jobs: [
          {
            status: "queued",
            updated_at: "2026-08-19T11:00:00Z",
            result_summary: { raw: "drop" },
          },
          { status: "processing", updated_at: "2026-08-19T11:01:00Z" },
          { status: "completed", updated_at: "2026-08-19T11:02:00Z" },
          { status: "failed", updated_at: "2026-08-19T11:03:00Z" },
          { status: "quarantined", updated_at: "2026-08-19T11:04:00Z" },
        ],
        admin_runtime_controls: [{
          control_key: "benefit_enrichment_scheduled",
          is_paused: true,
          reason: "maintenance",
          updated_at: "2026-08-19T12:00:00Z",
          updated_by: "drop",
        }],
      },
    }),
  );
  assertEquals(output, {
    pipelines: [{
      key: "benefit_enrichment",
      status: "paused",
      queued: 1,
      running: 1,
      failed: 1,
      quarantined: 1,
      last_success_at: "2026-08-19T11:02:00Z",
      source_error: null,
    }, {
      key: "card_discovery",
      status: "unknown",
      queued: 0,
      running: 0,
      failed: 0,
      quarantined: 0,
      last_success_at: null,
      source_error: "source_unavailable",
    }],
    controls: [{
      control_key: "benefit_enrichment_scheduled",
      is_paused: true,
      reason: "maintenance",
      updated_at: "2026-08-19T12:00:00Z",
    }],
  });
});

Deno.test("system jobs validates filters, orders ties and uses lookahead pagination", async () => {
  const calls: Call[] = [];
  const output = await handleSystemJobs(
    {
      action: "system-jobs",
      family: "benefit_enrichment",
      status: "failed",
      page: 2,
      limit: 2,
      target_id: "00000000-0000-4000-8000-000000000010",
    },
    context({
      calls,
      rows: {
        card_catalog_enrichment_jobs: [
          {
            id: "b",
            status: "failed",
            failure_category: "provider_timeout",
            attempt_count: 2,
            next_retry_at: null,
            updated_at: "2026-08-19T10:00:00Z",
            result: "drop",
          },
          {
            id: "a",
            status: "failed",
            failure_category: "x".repeat(100),
            attempt_count: 1,
            next_retry_at: null,
            updated_at: "2026-08-19T10:00:00Z",
          },
          {
            id: "overflow",
            status: "failed",
            attempt_count: 0,
            updated_at: "2026-08-19T09:00:00Z",
          },
        ],
      },
    }),
  );
  assertEquals(output.items.map((item) => item.id), ["b", "a"]);
  assertEquals(output.has_more, true);
  assertEquals(Object.keys(output.items[0]).sort(), [
    "attempt_count",
    "failure_category",
    "family",
    "id",
    "next_retry_at",
    "status",
    "updated_at",
  ]);
  assertEquals(
    calls.filter((call) => call.kind === "order").map((call) => call.args),
    [["updated_at", { ascending: false }], ["id", { ascending: false }]],
  );
  assertEquals(calls.find((call) => call.kind === "range")?.args, [2, 4]);
});

Deno.test("system jobs rejects unknown families, statuses and extra keys", async () => {
  for (
    const body of [
      { action: "system-jobs", family: "emails" },
      {
        action: "system-jobs",
        family: "card_discovery",
        status: "quarantined",
      },
      { action: "system-jobs", family: "benefit_enrichment", raw: true },
    ]
  ) {
    await assertRejects(
      () => handleSystemJobs(body, context()),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("system mutations enforce supported family/status and exact audited RPC arguments", async () => {
  const calls: Call[] = [];
  const result = await handleSystemMutation({
    action: "system-quarantine",
    family: "benefit_enrichment",
    status: "failed",
    target_id: "00000000-0000-4000-8000-000000000010",
    request_id: "00000000-0000-4000-8000-000000000020",
    observed_updated_at: "2026-08-19T12:00:00Z",
    reason: "bad source",
  }, context({ calls }));
  assertEquals(result, {
    result: {
      job_id: "00000000-0000-4000-8000-000000000010",
      resulting_status: "queued",
    },
  });
  assertEquals(calls.find((call) => call.kind === "rpc"), {
    kind: "rpc",
    name: "admin_card_data_action",
    args: {
      _actor_id: "00000000-0000-4000-8000-000000000001",
      _request_id: "00000000-0000-4000-8000-000000000020",
      _lane: "benefit",
      _operation: "quarantine",
      _target_id: "00000000-0000-4000-8000-000000000010",
      _staging_id: null,
      _payload: {},
      _reason: "bad source",
      _observed_updated_at: "2026-08-19T12:00:00Z",
    },
  });
  await assertRejects(
    () =>
      handleSystemMutation({
        action: "system-retry",
        family: "card_discovery",
        status: "failed",
        target_id: "00000000-0000-4000-8000-000000000010",
        request_id: "00000000-0000-4000-8000-000000000020",
        observed_updated_at: "2026-08-19T12:00:00Z",
      }, context()),
    AdminHttpError,
    "invalid_request",
  );
  const unquarantineCalls: Call[] = [];
  await handleSystemMutation({
    action: "system-quarantine",
    operation: "unquarantine",
    family: "benefit_enrichment",
    status: "quarantined",
    target_id: "00000000-0000-4000-8000-000000000010",
    request_id: "00000000-0000-4000-8000-000000000021",
    observed_updated_at: "2026-08-19T12:00:00Z",
  }, context({ calls: unquarantineCalls }));
  assertEquals(
    (unquarantineCalls.find((call) => call.kind === "rpc")?.args as Record<
      string,
      unknown
    >)._operation,
    "unquarantine",
  );
});

Deno.test("system control accepts one key and delegates exact versioned arguments", async () => {
  const calls: Call[] = [];
  const output = await handleSystemControl({
    action: "system-control",
    control_key: "benefit_enrichment_scheduled",
    is_paused: true,
    request_id: "00000000-0000-4000-8000-000000000020",
    observed_updated_at: "2026-08-19T12:00:00Z",
    reason: "maintenance",
  }, context({ calls }));
  assertEquals(output, {
    result: {
      control_key: "benefit_enrichment_scheduled",
      is_paused: true,
      reason: "maintenance",
      updated_at: "2026-08-19T12:01:00Z",
    },
  });
  assertEquals(calls.find((call) => call.kind === "rpc")?.args, {
    _actor_id: "00000000-0000-4000-8000-000000000001",
    _request_id: "00000000-0000-4000-8000-000000000020",
    _control_key: "benefit_enrichment_scheduled",
    _is_paused: true,
    _reason: "maintenance",
    _observed_updated_at: "2026-08-19T12:00:00Z",
  });
});

Deno.test("system maps database errors without leaking details", async () => {
  for (
    const [message, code] of [
      ["request_id_collision DETAIL secret", "state_conflict"],
      ["not_found relation secret", "not_found"],
      ["driver password secret", "request_failed"],
    ]
  ) {
    await assertRejects(
      () =>
        handleSystemControl({
          action: "system-control",
          control_key: "benefit_enrichment_scheduled",
          is_paused: false,
          request_id: "00000000-0000-4000-8000-000000000020",
          observed_updated_at: "2026-08-19T12:00:00Z",
          reason: "resume now",
        }, context({ rpcError: { message } })),
      AdminHttpError,
      code,
    );
  }
});

Deno.test("system registry is frozen, null-prototype and rejects inherited entries", () => {
  assertEquals(Object.isFrozen(systemActionHandlers), true);
  assertEquals(Object.getPrototypeOf(systemActionHandlers), null);
  assertEquals(Object.hasOwn(systemActionHandlers, "constructor"), false);
});
