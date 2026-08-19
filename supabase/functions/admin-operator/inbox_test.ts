import { assertEquals, assertRejects } from "@std/assert";
import {
  feedbackInboxItem,
  handleInboxList,
  type InboxItem,
  loadBenefitInbox,
  loadIdentityInbox,
  loadSystemInbox,
  rankInboxItems,
} from "./inbox.ts";

Deno.test("pending high feedback becomes a high inbox item without auto-close", () => {
  assertEquals(
    feedbackInboxItem({
      id: "20000000-0000-4000-8000-000000000001",
      feature_key: "card_data",
      triage_status: "triaged",
      triage_result: { severity: "high" },
      review_status: "pending",
      created_at: "2026-08-19T11:00:00Z",
    }, NOW),
    {
      id: "feedback:20000000-0000-4000-8000-000000000001",
      type: "feedback_review",
      severity: "high",
      title: "Review card data feedback",
      explanation: "User feedback is waiting for human review.",
      source_status: "pending",
      age_seconds: 3600,
      destination: {
        section: "feedback",
        feedback_id: "20000000-0000-4000-8000-000000000001",
      },
    },
  );
});
import { type AdminActionContext, AdminHttpError } from "./types.ts";
import { actionHandlers } from "./router.ts";

const NOW = Date.parse("2026-08-19T12:00:00Z");

function item(
  id: string,
  severity: InboxItem["severity"],
  age: number,
): InboxItem {
  return {
    id,
    type: "card_identity_review",
    severity,
    title: "Review card identity proposal",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: age,
    destination: { section: "cardData", lane: "identity", target_id: id },
  };
}

type QueryCall = { table: string; method: string; args: unknown[] };

function queryResult(
  table: string,
  rows: unknown[],
  error:
    | { message: string }
    | null
    | ((statuses: unknown[] | null) => { message: string } | null),
  calls: QueryCall[],
  countValue: unknown | ((equals: Map<unknown, unknown>) => unknown) = 0,
  countRows?: unknown[],
) {
  let statuses: unknown[] | null = null;
  let head = false;
  const equals = new Map<unknown, unknown>();
  let orFilter: string | null = null;
  const query = {
    select: (
      ...args: unknown[]
    ) => {
      calls.push({ table, method: "select", args });
      head = Boolean((args[1] as { head?: unknown } | undefined)?.head);
      return query;
    },
    eq: (
      ...args: unknown[]
    ) => {
      calls.push({ table, method: "eq", args });
      equals.set(args[0], args[1]);
      return query;
    },
    neq: (
      ...args: unknown[]
    ) => (calls.push({ table, method: "neq", args }), query),
    in: (...args: unknown[]) => {
      calls.push({ table, method: "in", args });
      if (args[0] === "status" && Array.isArray(args[1])) statuses = args[1];
      return query;
    },
    order: (
      ...args: unknown[]
    ) => (calls.push({ table, method: "order", args }), query),
    or: (...args: unknown[]) => {
      calls.push({ table, method: "or", args });
      orFilter = typeof args[0] === "string" ? args[0] : null;
      return query;
    },
    range: (...args: unknown[]) => {
      calls.push({ table, method: "range", args });
      const filtered = statuses === null ? rows : rows.filter((value) => {
        const status = value && typeof value === "object"
          ? (value as Record<string, unknown>).status
          : null;
        return statuses!.includes(status);
      });
      return Promise.resolve({
        data: filtered,
        count: head && countRows !== undefined
          ? countRows.filter((value) => {
            const row = value as Record<string, unknown>;
            if (
              [...equals].some(([key, expected]) =>
                row[String(key)] !== expected
              )
            ) return false;
            const cutoff = orFilter?.match(
              /next_retry_at\.lte\.([^,]+)/,
            )?.[1];
            return row.next_retry_at == null ||
              (cutoff !== undefined &&
                typeof row.next_retry_at === "string" &&
                Date.parse(row.next_retry_at) <= Date.parse(cutoff));
          }).length
          : head
          ? typeof countValue === "function" ? countValue(equals) : countValue
          : null,
        error: typeof error === "function" ? error(statuses) : error,
      });
    },
  };
  return query;
}

function context(options: {
  identity?: unknown[];
  benefit?: unknown[];
  identityError?: { message: string } | null;
  benefitError?: { message: string } | null;
  benefitHighError?: { message: string } | null;
  benefitRoutineError?: { message: string } | null;
  calls?: QueryCall[];
  control?: unknown[];
  queuedCount?: unknown;
  failedCount?: unknown;
  queuedRows?: unknown[];
  systemError?: { message: string } | null;
} = {}): AdminActionContext {
  const calls = options.calls ?? [];
  return {
    actor: { id: "admin" },
    requestId: null,
    db: {
      from(table: string) {
        calls.push({ table, method: "from", args: [] });
        if (table === "admin_runtime_controls") {
          return queryResult(
            table,
            options.control ?? [{
              control_key: "benefit_enrichment_scheduled",
              is_paused: false,
              updated_at: "2026-08-19T11:30:00Z",
            }],
            options.systemError ?? null,
            calls,
          ) as never;
        }
        return queryResult(
          table,
          table === "card_catalog_review_queue"
            ? options.identity ?? []
            : options.benefit ?? [],
          table === "card_catalog_review_queue"
            ? options.identityError ?? null
            : (statuses) => {
              if (statuses === null) return options.systemError ?? null;
              if (options.benefitError) return options.benefitError;
              return statuses?.includes("staged")
                ? options.benefitRoutineError ?? null
                : options.benefitHighError ?? null;
            },
          calls,
          table === "card_catalog_enrichment_jobs"
            ? (equals: Map<unknown, unknown>) =>
              equals.get("status") === "failed"
                ? options.failedCount ?? 0
                : options.queuedCount ?? 0
            : 0,
          table === "card_catalog_enrichment_jobs"
            ? options.queuedRows
            : undefined,
        ) as never;
      },
      rpc: () => Promise.resolve({ data: null, error: null }),
    },
  };
}

Deno.test("paused benefit pipeline with queued work creates one critical System control item", async () => {
  const output = await loadSystemInbox(
    context({
      control: [{
        control_key: "benefit_enrichment_scheduled",
        is_paused: true,
        updated_at: "2026-08-19T11:30:00Z",
      }],
      queuedCount: 17,
    }),
    NOW,
  );

  assertEquals(output, [{
    id: "system:benefit_enrichment_scheduled:paused",
    type: "paused_pipeline",
    severity: "critical",
    title: "Scheduled benefit enrichment is paused",
    explanation:
      "17 queued benefit enrichment jobs are waiting while scheduled processing is paused.",
    source_status: "paused",
    age_seconds: 1800,
    destination: {
      section: "system",
      control_key: "benefit_enrichment_scheduled",
    },
  }]);
});

Deno.test("System count query mirrors the scheduled worker population", async () => {
  const calls: QueryCall[] = [];
  await loadSystemInbox(context({ queuedCount: 1, calls }), NOW);
  assertEquals(
    calls.filter((call) => call.table === "card_catalog_enrichment_jobs"),
    [{
      table: "card_catalog_enrichment_jobs",
      method: "from",
      args: [],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "select",
      args: ["id", { count: "exact", head: true }],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["run_mode", "scheduled"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["parser_version", "benefits-v5"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["status", "queued"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "or",
      args: [
        "next_retry_at.is.null,next_retry_at.lte.2026-08-19T12:00:00.000Z",
      ],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "range",
      args: [0, 0],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "from",
      args: [],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "select",
      args: ["id", { count: "exact", head: true }],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["run_mode", "scheduled"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["parser_version", "benefits-v5"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "eq",
      args: ["status", "failed"],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "or",
      args: [
        "next_retry_at.is.null,next_retry_at.lte.2026-08-19T12:00:00.000Z",
      ],
    }, {
      table: "card_catalog_enrichment_jobs",
      method: "range",
      args: [0, 0],
    }],
  );
});

Deno.test("only failed scheduler-eligible work triggers the paused alert", async () => {
  const output = await loadSystemInbox(
    context({
      control: [{
        control_key: "benefit_enrichment_scheduled",
        is_paused: true,
        updated_at: "2026-08-19T11:30:00Z",
      }],
      queuedCount: 0,
      failedCount: 3,
    }),
    NOW,
  );
  assertEquals(output.length, 1);
  assertEquals(
    output[0].explanation,
    "3 queued benefit enrichment jobs are waiting while scheduled processing is paused.",
  );
});

Deno.test("a malformed failed count fails the entire System inbox source", async () => {
  await assertRejects(
    () => loadSystemInbox(context({ failedCount: Number.NaN }), NOW),
    Error,
    "source_unavailable",
  );
});

Deno.test("pilot manual legacy and deferred queued rows neither trigger nor inflate the alert", async () => {
  const control = [{
    control_key: "benefit_enrichment_scheduled",
    is_paused: true,
    updated_at: "2026-08-19T11:30:00Z",
  }];
  const unrelated = [
    {
      status: "queued",
      run_mode: "pilot",
      parser_version: "benefits-v5",
      next_retry_at: null,
    },
    {
      status: "queued",
      run_mode: "manual",
      parser_version: "benefits-v5",
      next_retry_at: null,
    },
    {
      status: "queued",
      run_mode: "scheduled",
      parser_version: "benefits-v4",
      next_retry_at: null,
    },
    {
      status: "queued",
      run_mode: "scheduled",
      parser_version: "benefits-v5",
      next_retry_at: "2026-08-20T00:00:00Z",
    },
    {
      status: "failed",
      run_mode: "scheduled",
      parser_version: "benefits-v5",
      next_retry_at: "2026-08-20T00:00:00Z",
    },
  ];
  assertEquals(
    await loadSystemInbox(context({ control, queuedRows: unrelated }), NOW),
    [],
  );

  const output = await loadSystemInbox(
    context({
      control,
      queuedRows: [
        ...unrelated,
        {
          status: "queued",
          run_mode: "scheduled",
          parser_version: "benefits-v5",
          next_retry_at: "2026-08-19T11:00:00Z",
        },
        {
          status: "failed",
          run_mode: "scheduled",
          parser_version: "benefits-v5",
          next_retry_at: null,
        },
      ],
    }),
    NOW,
  );
  assertEquals(output.length, 1);
  assertEquals(
    output[0].explanation,
    "2 queued benefit enrichment jobs are waiting while scheduled processing is paused.",
  );
});

Deno.test("System inbox omits paused empty and unpaused pipelines", async () => {
  assertEquals(
    await loadSystemInbox(
      context({
        control: [{
          control_key: "benefit_enrichment_scheduled",
          is_paused: true,
          updated_at: "2026-08-19T11:30:00Z",
        }],
        queuedCount: 0,
      }),
      NOW,
    ),
    [],
  );
  assertEquals(
    await loadSystemInbox(
      context({
        control: [{
          control_key: "benefit_enrichment_scheduled",
          is_paused: false,
          updated_at: "2026-08-19T11:30:00Z",
        }],
        queuedCount: 17,
      }),
      NOW,
    ),
    [],
  );
});

Deno.test("System inbox source failure is stable and does not hide other items", async () => {
  const output = await handleInboxList(
    { action: "inbox-list" },
    context({
      identity: [{ id: "identity", status: "pending", created_at: "bad" }],
      control: [{ control_key: "wrong", is_paused: true }],
      queuedCount: "17",
    }),
  );
  assertEquals(output.items.map((entry) => entry.id), [
    "card-identity:identity",
  ]);
  assertEquals(output.partial_failures, ["system_operations"]);
});

Deno.test("inbox ranks severity, then oldest age, then stable id without mutating input", () => {
  const input = [
    item("pending-benefit", "normal", 100),
    item("failed-job", "high", 20),
    item("blocked", "critical", 5),
    item("b", "high", 60),
    item("a", "high", 60),
    item("c", "high", 120),
  ];

  assertEquals(rankInboxItems(input).map((entry) => entry.id), [
    "blocked",
    "c",
    "a",
    "b",
    "failed-job",
    "pending-benefit",
  ]);
  assertEquals(input.map((entry) => entry.id), [
    "pending-benefit",
    "failed-job",
    "blocked",
    "b",
    "a",
    "c",
  ]);
});

Deno.test("identity adapter returns exact safe pending-review DTOs and safe ages", async () => {
  const output = await loadIdentityInbox(
    context({
      identity: [{
        id: "identity-1",
        status: "pending",
        created_at: "2026-08-19T11:59:00Z",
        card_discovery_jobs: {
          issuer: " Issuer\u0000 Bank ",
          proposed_product: " Premier   Card ",
        },
        source_evidence: { raw_body: "secret" },
        proposed_fields: { card_name: "must not leak" },
      }, {
        id: "identity-2",
        status: "pending",
        created_at: "malformed",
        provider_response: "secret",
      }],
    }),
    100,
    NOW,
  );

  assertEquals(output, [{
    id: "card-identity:identity-1",
    type: "card_identity_review",
    severity: "normal",
    title: "Review card identity",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: 60,
    destination: {
      section: "cardData",
      lane: "identity",
      target_id: "identity-1",
    },
  }, {
    id: "card-identity:identity-2",
    type: "card_identity_review",
    severity: "normal",
    title: "Review card identity",
    explanation: "A pending card identity proposal needs review.",
    source_status: "pending",
    age_seconds: 0,
    destination: {
      section: "cardData",
      lane: "identity",
      target_id: "identity-2",
    },
  }]);
});

Deno.test("benefit adapter maps actionable statuses to exact safe DTOs", async () => {
  const output = await loadBenefitInbox(
    context({
      benefit: [
        {
          id: "review",
          status: "review_required",
          created_at: "2026-08-19T11:58:00Z",
          card_catalog: { bank: "Issuer", card_name: "Premier" },
          raw_body: "secret",
        },
        {
          id: "failed",
          status: "failed",
          created_at: "2026-08-19T11:57:00Z",
          card_catalog: { bank: "Issuer", card_name: "Travel" },
        },
        {
          id: "quarantined",
          status: "quarantined",
          created_at: "2026-08-19T11:56:00Z",
          card_catalog: { bank: "", card_name: "\u0001" },
        },
        {
          id: "staged",
          status: "staged",
          created_at: "2026-08-19T11:55:00Z",
          card_catalog: { bank: "Issuer", card_name: "Cashback" },
        },
      ],
    }),
    100,
    NOW,
  );

  assertEquals(
    output.map(({ id, source_status, severity, title, explanation }) => ({
      id,
      source_status,
      severity,
      title,
      explanation,
    })),
    [{
      id: "benefit-enrichment:review",
      source_status: "review_required",
      severity: "high",
      title: "Review benefits: Issuer — Premier",
      explanation: "A benefit proposal needs operator review.",
    }, {
      id: "benefit-enrichment:failed",
      source_status: "failed",
      severity: "high",
      title: "Recover benefits: Issuer — Travel",
      explanation: "Benefit enrichment failed and needs recovery.",
    }, {
      id: "benefit-enrichment:quarantined",
      source_status: "quarantined",
      severity: "high",
      title: "Review quarantined benefits",
      explanation: "A quarantined benefit job needs operator review.",
    }, {
      id: "benefit-enrichment:staged",
      source_status: "staged",
      severity: "normal",
      title: "Review benefits: Issuer — Cashback",
      explanation: "A staged benefit proposal is ready for review.",
    }],
  );
  assertEquals(
    output.every((entry) =>
      entry.destination.section === "cardData" &&
      entry.destination.lane === "benefit" &&
      Object.keys(entry).length === 8
    ),
    true,
  );
});

Deno.test("benefit failures cannot be starved by more than 100 staged rows", async () => {
  const benefit = [
    ...Array.from({ length: 140 }, (_, index) => ({
      id: `staged-${index.toString().padStart(3, "0")}`,
      status: "staged",
      created_at: "2026-08-18T00:00:00Z",
    })),
    {
      id: "failed-newer",
      status: "failed",
      created_at: "2026-08-19T11:59:59Z",
    },
  ];

  const output = await handleInboxList(
    { action: "inbox-list" },
    context({ benefit }),
  );

  assertEquals(output.items.length, 100);
  assertEquals(output.items[0].id, "benefit-enrichment:failed-newer");
  assertEquals(output.items[0].severity, "high");
});

Deno.test("source queries use deterministic created-at then id ordering before bounded ranges", async () => {
  const calls: QueryCall[] = [];
  await handleInboxList({ action: "inbox-list" }, context({ calls }));

  for (
    const table of ["card_catalog_review_queue", "card_catalog_enrichment_jobs"]
  ) {
    const tableCalls = calls.filter((call) => call.table === table);
    const ranges = tableCalls.filter((call) => call.method === "range");
    assertEquals(ranges.length, table === "card_catalog_review_queue" ? 1 : 4);
    finalTierRanges:
    for (const range of ranges) {
      const beforeRange = tableCalls.slice(0, tableCalls.indexOf(range));
      const latestSelect = beforeRange.findLast((call) =>
        call.method === "select"
      );
      if (
        (latestSelect?.args[1] as { head?: unknown } | undefined)?.head === true
      ) {
        assertEquals(range.args, [0, 0]);
        continue finalTierRanges;
      }
      assertEquals(beforeRange.slice(-2), [{
        table,
        method: "order",
        args: ["created_at", { ascending: true }],
      }, {
        table,
        method: "order",
        args: ["id", { ascending: true }],
      }]);
      assertEquals(range.args, [0, 99]);
    }
  }
});

Deno.test("inbox caps the merged ranked result at 100 items", async () => {
  const identity = Array.from({ length: 100 }, (_, index) => ({
    id: `identity-${index.toString().padStart(3, "0")}`,
    status: "pending",
    created_at: "2026-08-19T11:59:00Z",
  }));
  const benefit = Array.from({ length: 100 }, (_, index) => ({
    id: `benefit-${index.toString().padStart(3, "0")}`,
    status: "failed",
    created_at: "2026-08-19T11:59:00Z",
  }));
  const output = await handleInboxList(
    { action: "inbox-list" },
    context({ identity, benefit }),
  );

  assertEquals(output.items.length, 100);
  assertEquals(output.items.every((entry) => entry.severity === "high"), true);
  assertEquals(output.partial_failures, []);
});

Deno.test("inbox isolates each failed source and reports stable public names", async () => {
  const identityFailure = await handleInboxList(
    { action: "inbox-list" },
    context({
      identityError: { message: "password=secret" },
      benefit: [{ id: "benefit", status: "staged", created_at: "bad" }],
    }),
  );
  assertEquals(identityFailure.items.length, 1);
  assertEquals(identityFailure.partial_failures, ["card_identity"]);

  const benefitFailure = await handleInboxList(
    { action: "inbox-list" },
    context({
      identity: [{ id: "identity", status: "pending", created_at: "bad" }],
      benefitError: { message: "raw query detail" },
    }),
  );
  assertEquals(benefitFailure.items.length, 1);
  assertEquals(benefitFailure.partial_failures, ["benefit_enrichment"]);

  const both = await handleInboxList(
    { action: "inbox-list" },
    context({
      identityError: { message: "identity secret" },
      benefitError: { message: "benefit secret" },
    }),
  );
  assertEquals(both.items, []);
  assertEquals(both.partial_failures, ["card_identity", "benefit_enrichment"]);
  assertEquals(JSON.stringify(both).includes("secret"), false);

  const routineOnlyFailure = await handleInboxList(
    { action: "inbox-list" },
    context({
      benefit: [
        { id: "failed-kept", status: "failed", created_at: "bad" },
        { id: "staged-dropped", status: "staged", created_at: "bad" },
      ],
      benefitRoutineError: { message: "routine query detail" },
    }),
  );
  assertEquals(routineOnlyFailure.items.map((entry) => entry.id), [
    "benefit-enrichment:failed-kept",
  ]);
  assertEquals(routineOnlyFailure.partial_failures, ["benefit_enrichment"]);
});

Deno.test("inbox rejects non-allowlisted input and router registration is immutable and prototype-safe", async () => {
  await assertRejects(
    () => handleInboxList({ action: "inbox-list", table: "users" }, context()),
    AdminHttpError,
    "invalid_request",
  );
  assertEquals(Object.isFrozen(actionHandlers), true);
  assertEquals(Object.hasOwn(actionHandlers, "inbox-list"), true);
  assertEquals(Object.hasOwn(actionHandlers, "constructor"), false);
  assertEquals(Object.getPrototypeOf(actionHandlers), null);
});
