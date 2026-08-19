import { assertEquals, assertRejects } from "@std/assert";
import {
  handleSystemControl,
  handleSystemJobs,
  handleSystemMutation,
  handleSystemStatus,
  SAFE_SYSTEM_FAILURE_CATEGORIES,
  systemActionHandlers,
} from "./system.ts";
import { BENEFIT_FAILURE_CATEGORIES } from "../benefit-enrichment-batch/batch_policy.ts";
import { CARD_DISCOVERY_REASON_CODES } from "../_shared/card_discovery.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

type Call = { kind: string; name: string; args: unknown };

function context(options: {
  rows?: Record<string, unknown[]>;
  counts?: Record<string, unknown>;
  errors?: Record<string, { message: string }>;
  rpcError?: { message: string } | null;
  rpcData?: Record<string, unknown>;
  calls?: Call[];
} = {}): AdminActionContext {
  const calls = options.calls ?? [];
  return {
    actor: { id: "00000000-0000-4000-8000-000000000001" },
    requestId: null,
    db: {
      from(table: string) {
        calls.push({ kind: "from", name: table, args: null });
        let selectedStatus: unknown = null;
        let head = false;
        const query: Record<string, (...args: unknown[]) => unknown> = {};
        for (const method of ["select", "eq", "order"]) {
          query[method] = (...args: unknown[]) => {
            calls.push({ kind: method, name: table, args });
            if (method === "select") {
              head =
                (args[1] as Record<string, unknown> | undefined)?.head === true;
            }
            if (method === "eq" && args[0] === "status") {
              selectedStatus = args[1];
            }
            return query;
          };
        }
        query.range = (...args: unknown[]) => {
          calls.push({ kind: "range", name: table, args });
          const rows = (options.rows?.[table] ?? []).filter((value) => {
            const row = value as Record<string, unknown>;
            return selectedStatus == null || row.status === selectedStatus;
          }).sort((left, right) =>
            String((right as Record<string, unknown>).updated_at ?? "")
              .localeCompare(
                String((left as Record<string, unknown>).updated_at ?? ""),
              )
          );
          return Promise.resolve({
            data: rows,
            error: options.errors?.[table] ?? null,
          });
        };
        query.then = (resolve: unknown) => {
          const rows = options.rows?.[table] ?? [];
          const derived =
            rows.filter((value) =>
              (value as Record<string, unknown>).status === selectedStatus
            ).length;
          return Promise.resolve({
            data: head ? null : rows,
            count: options.counts?.[`${table}:${selectedStatus}`] ?? derived,
            error: options.errors?.[table] ?? null,
          }).then(resolve as (value: unknown) => unknown);
        };
        return query as never;
      },
      rpc(name, args) {
        calls.push({ kind: "rpc", name, args });
        return Promise.resolve({
          data: options.rpcData?.[name] ??
            (name === "admin_set_runtime_control"
              ? {
                control_key: "benefit_enrichment_scheduled",
                is_paused: true,
                reason: "maintenance",
                updated_at: "2026-08-19T12:01:00Z",
                secret: "drop",
              }
              : {
                job_id: "00000000-0000-4000-8000-000000000010",
                resulting_status: "quarantined",
                provider: "drop",
              }),
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
    control_source_error: null,
  });
});

Deno.test("system status uses exact counts beyond row limits and exact latest success", async () => {
  const output = await handleSystemStatus(
    { action: "system-status" },
    context({
      counts: {
        "card_catalog_enrichment_jobs:queued": 1_501,
        "card_catalog_enrichment_jobs:processing": 7,
        "card_catalog_enrichment_jobs:failed": 1,
        "card_catalog_enrichment_jobs:quarantined": 2,
        "card_discovery_jobs:queued": 2_501,
        "card_discovery_jobs:discovering": 3,
        "card_discovery_jobs:failed": 4,
      },
      rows: {
        card_catalog_enrichment_jobs: [
          { status: "completed", updated_at: "2026-08-18T00:00:00Z" },
          { status: "completed", updated_at: "2026-08-19T00:00:00Z" },
        ],
        card_discovery_jobs: [{
          status: "resolved",
          updated_at: "2026-08-17T00:00:00Z",
        }],
        admin_runtime_controls: [{
          control_key: "benefit_enrichment_scheduled",
          is_paused: false,
          reason: "normal run",
          updated_at: "2026-08-19T12:00:00Z",
        }],
      },
    }),
  );
  assertEquals(output.pipelines[0], {
    key: "benefit_enrichment",
    status: "degraded",
    queued: 1501,
    running: 7,
    failed: 1,
    quarantined: 2,
    last_success_at: "2026-08-19T00:00:00Z",
    source_error: null,
  });
  assertEquals(output.pipelines[1].queued, 2501);
  assertEquals(output.pipelines[1].last_success_at, "2026-08-17T00:00:00Z");
});

Deno.test("system status fails closed when exact counts or the named control are unavailable", async () => {
  const malformedCount = await handleSystemStatus(
    { action: "system-status" },
    context({
      counts: { "card_catalog_enrichment_jobs:failed": "1001" },
      rows: {
        admin_runtime_controls: [{
          control_key: "benefit_enrichment_scheduled",
          is_paused: false,
          reason: "normal run",
          updated_at: "2026-08-19T12:00:00Z",
        }],
      },
    }),
  );
  assertEquals(malformedCount.pipelines[0].status, "unknown");
  assertEquals(malformedCount.pipelines[0].source_error, "source_unavailable");

  for (
    const controlRows of [[], [{
      control_key: "benefit_enrichment_scheduled",
      is_paused: "false",
      updated_at: "2026-08-19T12:00:00Z",
    }]]
  ) {
    const output = await handleSystemStatus(
      { action: "system-status" },
      context({ rows: { admin_runtime_controls: controlRows } }),
    );
    assertEquals(output.pipelines[0].status, "unknown");
    assertEquals(output.pipelines[0].source_error, "source_unavailable");
    assertEquals(output.controls, []);
    assertEquals(output.control_source_error, "source_unavailable");
  }
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
    operation: "quarantine",
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
      resulting_status: "quarantined",
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
  await handleSystemMutation(
    {
      action: "system-quarantine",
      operation: "unquarantine",
      family: "benefit_enrichment",
      status: "quarantined",
      target_id: "00000000-0000-4000-8000-000000000010",
      request_id: "00000000-0000-4000-8000-000000000021",
      observed_updated_at: "2026-08-19T12:00:00Z",
    },
    context({
      calls: unquarantineCalls,
      rpcData: {
        admin_card_data_action: {
          job_id: "00000000-0000-4000-8000-000000000010",
          resulting_status: "queued",
        },
      },
    }),
  );
  assertEquals(
    (unquarantineCalls.find((call) => call.kind === "rpc")?.args as Record<
      string,
      unknown
    >)._operation,
    "unquarantine",
  );
});

Deno.test("router mutation bodies enforce one exact action contract", async () => {
  const base = {
    family: "benefit_enrichment",
    status: "failed",
    target_id: "00000000-0000-4000-8000-000000000010",
    request_id: "00000000-0000-4000-8000-000000000020",
    observed_updated_at: "2026-08-19T12:00:00Z",
  };
  const retry = systemActionHandlers["system-retry"];
  const quarantine = systemActionHandlers["system-quarantine"];
  assertEquals(
    await retry(
      { action: "system-retry", ...base },
      context({
        rpcData: {
          admin_card_data_action: {
            job_id: base.target_id,
            resulting_status: "queued",
          },
        },
      }),
    ),
    { result: { job_id: base.target_id, resulting_status: "queued" } },
  );
  await assertRejects(
    () =>
      retry({ action: "system-retry", operation: "retry", ...base }, context()),
    AdminHttpError,
    "invalid_request",
  );
  await assertRejects(
    () =>
      retry({ action: "system-retry", operation: null, ...base }, context()),
    AdminHttpError,
    "invalid_request",
  );
  await assertRejects(
    () =>
      quarantine(
        { action: "system-quarantine", ...base, reason: "bad source" },
        context(),
      ),
    AdminHttpError,
    "invalid_request",
  );
  assertEquals(
    await quarantine({
      action: "system-quarantine",
      operation: "quarantine",
      ...base,
      reason: "bad source",
    }, context()),
    { result: { job_id: base.target_id, resulting_status: "quarantined" } },
  );
});

Deno.test("system failure vocabulary covers every canonical producer code", () => {
  const exposed = new Set(SAFE_SYSTEM_FAILURE_CATEGORIES);
  for (
    const code of [
      ...BENEFIT_FAILURE_CATEGORIES,
      ...CARD_DISCOVERY_REASON_CODES,
    ]
  ) {
    assertEquals(exposed.has(code), true, `missing producer code: ${code}`);
  }
});

Deno.test("system jobs map unsafe failure details to a stable category", async () => {
  const adversarial = [
    "postgres://operator:secret@db.internal/jobs",
    "https://provider.invalid/result?token=secret",
    "SQLSTATE 23505 duplicate key provider payload",
    "sk-live-secret-value",
  ];
  for (const failure_category of adversarial) {
    const output = await handleSystemJobs(
      { action: "system-jobs", family: "card_discovery" },
      context({
        rows: {
          card_discovery_jobs: [{
            id: "safe-id",
            status: "failed",
            failure_category,
            attempt_count: 1,
            next_retry_at: null,
            updated_at: "2026-08-19T10:00:00Z",
          }],
        },
      }),
    );
    assertEquals(output.items[0].failure_category, "unknown_failure");
    assertEquals(JSON.stringify(output).includes("secret"), false);
    assertEquals(JSON.stringify(output).includes("provider.invalid"), false);
  }
});

Deno.test("system rejects mismatched or malformed mutation receipts", async () => {
  const request = {
    action: "system-retry",
    family: "benefit_enrichment",
    status: "failed",
    target_id: "00000000-0000-4000-8000-000000000010",
    request_id: "00000000-0000-4000-8000-000000000020",
    observed_updated_at: "2026-08-19T12:00:00Z",
  };
  for (
    const receipt of [null, {}, {
      job_id: "00000000-0000-4000-8000-000000000099",
      resulting_status: "queued",
    }, { job_id: request.target_id, resulting_status: "completed" }]
  ) {
    await assertRejects(
      () =>
        handleSystemMutation(
          request,
          context({ rpcData: { admin_card_data_action: receipt } }),
        ),
      AdminHttpError,
      "request_failed",
    );
  }
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

Deno.test("system rejects control receipts that do not match requested key, state, reason and version shape", async () => {
  const request = {
    action: "system-control",
    control_key: "benefit_enrichment_scheduled",
    is_paused: true,
    request_id: "00000000-0000-4000-8000-000000000020",
    observed_updated_at: "2026-08-19T12:00:00Z",
    reason: "maintenance",
  };
  for (
    const receipt of [
      {
        control_key: "other",
        is_paused: true,
        reason: "maintenance",
        updated_at: "2026-08-19T12:01:00Z",
      },
      {
        control_key: request.control_key,
        is_paused: false,
        reason: "maintenance",
        updated_at: "2026-08-19T12:01:00Z",
      },
      {
        control_key: request.control_key,
        is_paused: true,
        reason: "other",
        updated_at: "2026-08-19T12:01:00Z",
      },
      {
        control_key: request.control_key,
        is_paused: true,
        reason: "maintenance",
        updated_at: "invalid",
      },
      {
        control_key: request.control_key,
        is_paused: true,
        reason: "maintenance",
        updated_at: request.observed_updated_at,
      },
    ]
  ) {
    await assertRejects(
      () =>
        handleSystemControl(
          request,
          context({ rpcData: { admin_set_runtime_control: receipt } }),
        ),
      AdminHttpError,
      "request_failed",
    );
  }
});

Deno.test("system registry is frozen, null-prototype and rejects inherited entries", () => {
  assertEquals(Object.isFrozen(systemActionHandlers), true);
  assertEquals(Object.getPrototypeOf(systemActionHandlers), null);
  assertEquals(Object.hasOwn(systemActionHandlers, "constructor"), false);
});
