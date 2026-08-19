import { assertEquals, assertRejects } from "@std/assert";
import {
  handleEvalConfigList,
  handleEvalRunAction,
  handleEvalRunDetail,
  handleEvalRunList,
} from "./evals.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";
import { createEvalScheduler } from "./index.ts";
import { validateAiEvalRunnerReceipt } from "../_shared/ai_eval_runner_receipt.ts";

const actor = "00000000-0000-4000-8000-000000000001";
const runId = "00000000-0000-4000-8000-000000000010";
const requestId = "00000000-0000-4000-8000-000000000020";

function context(options: {
  rows?: Record<string, unknown[]>;
  rpc?: Record<string, unknown>;
  calls?: string[];
  schedule?: (id: string) => void;
} = {}): AdminActionContext {
  const calls = options.calls ?? [];
  return {
    actor: { id: actor },
    requestId: null,
    scheduleEvalRun: async (id) => options.schedule?.(id),
    db: {
      from(table: string) {
        calls.push(`from:${table}`);
        const query: any = {};
        for (const method of ["select", "eq", "order"]) {
          query[method] = () => query;
        }
        query.range = () =>
          Promise.resolve({
            data: options.rows?.[table] ?? [],
            count: (options.rows?.[table] ?? []).length,
            error: null,
          });
        return query;
      },
      rpc(name, args) {
        calls.push(`rpc:${name}:${JSON.stringify(args)}`);
        return Promise.resolve({
          data: options.rpc?.[name] ?? null,
          error: null,
        });
      },
    },
  };
}

Deno.test("eval config list exposes only frozen safe metadata and current dataset", async () => {
  const output = await handleEvalConfigList(
    { action: "eval-config-list" },
    context({
      rows: { ai_eval_cases: [{ approved_in_dataset_version: 12 }] },
    }),
  );
  assertEquals(output.dataset_version, 12);
  assertEquals(output.configs.length, 3);
  assertEquals(
    output.configs[2].task_scope,
    "fixed_selection_explanation_and_arithmetic",
  );
  assertEquals(output.configs[2].scope_note, "Does not evaluate ranking.");
  assertEquals(Object.hasOwn(output.configs[0], "prompt"), false);
});

Deno.test("eval start validates bounds, exact receipt, and schedules only after durable create", async () => {
  const calls: string[] = [];
  const scheduled: string[] = [];
  const output = await handleEvalRunAction(
    {
      action: "eval-run-action",
      operation: "start",
      request_id: requestId,
      dataset_version: 12,
      baseline_config_key: "captured-production-v1",
      candidate_config_key: "gemini-3.6-flash-statement-v1",
      judge_config_key: "gemini-3.6-flash-blind-judge-v1",
      maximum_case_count: 10,
      cost_ceiling_usd: 0.2,
      latency_ceiling_ms: 5000,
    },
    context({
      calls,
      schedule: (id) => scheduled.push(id),
      rpc: {
        admin_create_ai_eval_run: {
          run_id: runId,
          status: "queued",
          case_count: 7,
        },
      },
    }),
  );
  assertEquals(output, {
    result: { run_id: runId, status: "queued", case_count: 7 },
  });
  assertEquals(scheduled, [runId]);
  assertEquals(calls[0].startsWith("rpc:admin_create_ai_eval_run"), true);

  await assertRejects(
    () =>
      handleEvalRunAction({
        action: "eval-run-action",
        operation: "start",
        request_id: requestId,
        dataset_version: 12,
        baseline_config_key: "captured-production-v1",
        candidate_config_key: "gemini-3.6-flash-statement-v1",
        judge_config_key: "gemini-3.6-flash-blind-judge-v1",
        maximum_case_count: 101,
        cost_ceiling_usd: 0.2,
        latency_ceiling_ms: 5000,
      }, context()),
    AdminHttpError,
    "invalid_request",
  );
});

Deno.test("eval start returns the receipt when background scheduling fails", async () => {
  const output = await handleEvalRunAction(
    {
      action: "eval-run-action",
      operation: "start",
      request_id: requestId,
      dataset_version: 12,
      baseline_config_key: "captured-production-v1",
      candidate_config_key: "gemini-3.6-flash-card-data-v1",
      judge_config_key: "gemini-3.6-flash-blind-judge-v1",
      maximum_case_count: 4,
      cost_ceiling_usd: 0.2,
      latency_ceiling_ms: 5000,
    },
    context({
      schedule: () => {
        throw new Error("transport secret");
      },
      rpc: {
        admin_create_ai_eval_run: {
          run_id: runId,
          status: "queued",
          case_count: 4,
        },
      },
    }),
  );
  assertEquals(output, {
    result: { run_id: runId, status: "queued", case_count: 4 },
  });
});

Deno.test("eval start response-loss replay returns a completed durable receipt without rescheduling", async () => {
  const scheduled: string[] = [];
  const output = await handleEvalRunAction(
    {
      action: "eval-run-action",
      operation: "start",
      request_id: requestId,
      dataset_version: 12,
      baseline_config_key: "captured-production-v1",
      candidate_config_key: "gemini-3.6-flash-statement-v1",
      judge_config_key: "gemini-3.6-flash-blind-judge-v1",
      maximum_case_count: 4,
      cost_ceiling_usd: 0.1,
      latency_ceiling_ms: 5000,
    },
    context({
      schedule: (id) => scheduled.push(id),
      rpc: {
        admin_create_ai_eval_run: {
          run_id: runId,
          status: "completed",
          case_count: 4,
        },
      },
    }),
  );
  assertEquals(output, {
    result: { run_id: runId, status: "completed", case_count: 4 },
  });
  assertEquals(scheduled, []);
});

Deno.test("eval list is bounded, filtered and never returns manifests", async () => {
  const output = await handleEvalRunList(
    { action: "eval-run-list", page: 1, limit: 20, status: "completed" },
    context({
      rows: {
        ai_eval_runs: [{
          id: runId,
          dataset_version: 12,
          baseline_config_key: "captured-production-v1",
          candidate_config_key: "gemini-3.6-flash-statement-v1",
          judge_config_key: "gemini-3.6-flash-blind-judge-v1",
          status: "completed",
          maximum_case_count: 10,
          cost_ceiling_usd: "0.2",
          latency_ceiling_ms: 5000,
          aggregate_metrics: { case_count: 7, regressions: 0, raw: "drop" },
          token_usage: { candidate_input: 8 },
          estimated_cost_usd: "0.01",
          safe_failure_category: null,
          created_at: "2026-08-19T10:00:00Z",
          started_at: null,
          completed_at: "2026-08-19T10:02:00Z",
          updated_at: "2026-08-19T10:02:00Z",
          case_manifest: [{ secret: true }],
        }],
      },
    }),
  );
  assertEquals(output.total, 1);
  assertEquals(Object.hasOwn(output.items[0], "case_manifest"), false);
  assertEquals(Object.hasOwn(output.items[0].aggregate_metrics, "raw"), false);
});

Deno.test("eval detail audits before reads and returns safe decision evidence", async () => {
  const calls: string[] = [];
  const output = await handleEvalRunDetail(
    { action: "eval-run-detail", run_id: runId, request_id: requestId },
    context({
      calls,
      rpc: { record_admin_read: "audit-id" },
      rows: {
        ai_eval_runs: [{
          id: runId,
          dataset_version: 12,
          baseline_config_key: "captured-production-v1",
          candidate_config_key: "gemini-3.6-flash-statement-v1",
          judge_config_key: "gemini-3.6-flash-blind-judge-v1",
          status: "completed",
          maximum_case_count: 2,
          cost_ceiling_usd: "0.2",
          latency_ceiling_ms: 5000,
          aggregate_metrics: {
            case_count: 2,
            succeeded: 2,
            failed: 0,
            missing: 0,
            regressions: 0,
            severe_regressions: 0,
            failure_categories: {},
          },
          token_usage: {
            baseline_input: 0,
            baseline_output: 0,
            candidate_input: 10,
            candidate_output: 4,
          },
          estimated_cost_usd: "0.01",
          safe_failure_category: null,
          created_at: "2026-08-19T10:00:00Z",
          started_at: "2026-08-19T10:00:01Z",
          completed_at: "2026-08-19T10:02:00Z",
          updated_at: "2026-08-19T10:02:00Z",
        }],
        ai_eval_results: [
          {
            case_id: "00000000-0000-4000-8000-000000000011",
            case_revision: 1,
            feature_key: "statement_processing",
            deterministic_assertions: [{
              baselinePassed: false,
              candidatePassed: true,
            }],
            judge_verdict: {},
            requires_review: false,
            regression: false,
            severe_regression: false,
            baseline_latency_ms: 10,
            candidate_latency_ms: 20,
            baseline_input_tokens: 0,
            baseline_output_tokens: 0,
            candidate_input_tokens: 5,
            candidate_output_tokens: 2,
            estimated_cost_usd: "0.005",
            execution_status: "succeeded",
            safe_failure_category: null,
            attempt_count: 1,
            updated_at: "2026-08-19T10:01:00Z",
            baseline_output: { secret: true },
          },
          {
            case_id: "00000000-0000-4000-8000-000000000012",
            case_revision: 1,
            feature_key: "statement_processing",
            deterministic_assertions: [{
              baselinePassed: true,
              candidatePassed: true,
            }],
            judge_verdict: {},
            requires_review: false,
            regression: false,
            severe_regression: false,
            baseline_latency_ms: 10,
            candidate_latency_ms: 30,
            baseline_input_tokens: 0,
            baseline_output_tokens: 0,
            candidate_input_tokens: 5,
            candidate_output_tokens: 2,
            estimated_cost_usd: "0.005",
            execution_status: "succeeded",
            safe_failure_category: null,
            attempt_count: 1,
            updated_at: "2026-08-19T10:01:01Z",
          },
        ],
      },
    }),
  );
  assertEquals(calls[0].startsWith("rpc:record_admin_read"), true);
  assertEquals(output.decision.status, "candidate_supported");
  assertEquals(output.metrics.baseline_pass_rate, 0.5);
  assertEquals(output.metrics.candidate_pass_rate, 1);
  assertEquals(output.results.page, 1);
  assertEquals(output.results.total, 2);
  assertEquals(
    Object.hasOwn(output.results.items[0], "baseline_output"),
    false,
  );
});

function decisionRun(overrides: Record<string, unknown> = {}) {
  return {
    id: runId,
    dataset_version: 12,
    baseline_config_key: "captured-production-v1",
    candidate_config_key: "gemini-3.6-flash-recommendation-v1",
    judge_config_key: "gemini-3.6-flash-blind-judge-v1",
    status: "completed",
    maximum_case_count: 1,
    cost_ceiling_usd: "0.2",
    latency_ceiling_ms: 5000,
    aggregate_metrics: {
      case_count: 1,
      succeeded: 1,
      failed: 0,
      missing: 0,
      regressions: 0,
      severe_regressions: 0,
      failure_categories: {},
    },
    token_usage: {},
    estimated_cost_usd: "0.01",
    safe_failure_category: null,
    created_at: "2026-08-19T10:00:00Z",
    started_at: "2026-08-19T10:00:01Z",
    completed_at: "2026-08-19T10:02:00Z",
    updated_at: "2026-08-19T10:02:00Z",
    ...overrides,
  };
}

function decisionResult(overrides: Record<string, unknown> = {}) {
  return {
    case_id: "00000000-0000-4000-8000-000000000011",
    case_revision: 1,
    feature_key: "recommendation",
    deterministic_assertions: [{
      baselinePassed: false,
      candidatePassed: true,
    }],
    judge_verdict: { winner: "candidate", confidence: .9 },
    requires_review: false,
    regression: false,
    severe_regression: false,
    baseline_latency_ms: 10,
    candidate_latency_ms: 20,
    baseline_input_tokens: 0,
    baseline_output_tokens: 0,
    candidate_input_tokens: 5,
    candidate_output_tokens: 2,
    estimated_cost_usd: "0.005",
    execution_status: "succeeded",
    safe_failure_category: null,
    attempt_count: 1,
    updated_at: "2026-08-19T10:01:00Z",
    ...overrides,
  };
}

async function decisionFor(
  run: Record<string, unknown>,
  results: Record<string, unknown>[],
) {
  return await handleEvalRunDetail(
    { action: "eval-run-detail", run_id: runId, request_id: requestId },
    context({
      rpc: { record_admin_read: "audit-id" },
      rows: { ai_eval_runs: [run], ai_eval_results: results },
    }),
  );
}

Deno.test("recommendation review semantics are persisted for missing, tied, and low-confidence verdicts", async () => {
  for (
    const judge of [{}, { winner: "tie", confidence: .9 }, {
      winner: "candidate",
      confidence: .69,
    }]
  ) {
    const output = await decisionFor(
      decisionRun(),
      [decisionResult({ judge_verdict: judge, requires_review: true })],
    );
    assertEquals(output.decision.status, "review_required");
    assertEquals(
      output.decision.blockers.includes("manual_review_required"),
      true,
    );
  }
});

Deno.test("candidate support fails closed for failed, missing, partial, and insufficient-fixture runs", async () => {
  const cases = [
    decisionRun({
      status: "completed_with_failures",
      safe_failure_category: "cost_ceiling_reached",
      aggregate_metrics: {
        case_count: 1,
        succeeded: 0,
        failed: 0,
        missing: 1,
        regressions: 0,
        severe_regressions: 0,
        failure_categories: {},
      },
    }),
    decisionRun({
      aggregate_metrics: {
        case_count: 2,
        succeeded: 1,
        failed: 0,
        missing: 1,
        regressions: 0,
        severe_regressions: 0,
        failure_categories: {},
      },
    }),
    decisionRun({
      status: "completed_with_failures",
      aggregate_metrics: {
        case_count: 1,
        succeeded: 0,
        failed: 1,
        missing: 0,
        regressions: 0,
        severe_regressions: 0,
        failure_categories: { insufficient_fixture: 1 },
      },
    }),
  ];
  for (const run of cases) {
    const output = await decisionFor(run, [decisionResult()]);
    assertEquals(output.decision.status, "review_required");
  }
});

Deno.test("eval mutation requires observed version and exact server receipt", async () => {
  const output = await handleEvalRunAction(
    {
      action: "eval-run-action",
      operation: "cancel",
      run_id: runId,
      request_id: requestId,
      observed_updated_at: "2026-08-19T10:00:00Z",
    },
    context({
      rpc: {
        admin_ai_eval_run_action: { run_id: runId, status: "cancelled" },
      },
    }),
  );
  assertEquals(output, { result: { run_id: runId, status: "cancelled" } });
});

Deno.test("gateway scheduler uses waitUntil with the private exact request", async () => {
  const requests: Request[] = [];
  const pending: Promise<unknown>[] = [];
  const schedule = createEvalScheduler({
    supabaseUrl: "https://example.supabase.co",
    serviceRoleKey: "service-secret",
    fetch: (request: Request | URL | string) => {
      requests.push(request as Request);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            run_id: runId,
            status: "not_claimed",
            processed: 0,
          }),
          { status: 202 },
        ),
      );
    },
    waitUntil: (promise: Promise<unknown>) => pending.push(promise),
  });
  await schedule(runId);
  assertEquals(requests.length, 1);
  assertEquals(
    requests[0].url,
    "https://example.supabase.co/functions/v1/ai-eval-runner",
  );
  assertEquals(
    requests[0].headers.get("authorization"),
    "Bearer service-secret",
  );
  assertEquals(await requests[0].json(), { run_id: runId });
  await Promise.all(pending);
});

Deno.test("gateway scheduler accepts every real safe runner receipt and rejects invented receipts", () => {
  for (
    const [status, receipt] of [
      [202, {
        run_id: runId,
        status: "running",
        processed: 5,
        continuation_required: true,
      }],
      [202, { run_id: runId, status: "not_claimed", processed: 0 }],
      [202, { run_id: runId, status: "cancelled", processed: 2 }],
      [200, { run_id: runId, status: "completed", processed: 2 }],
      [200, {
        run_id: runId,
        status: "completed_with_failures",
        processed: 0,
        safe_failure_category: "cost_ceiling_reached",
      }],
    ] as const
  ) validateAiEvalRunnerReceipt(status, receipt, runId);
  assertRejects(
    () =>
      Promise.resolve().then(() =>
        validateAiEvalRunnerReceipt(202, {
          run_id: runId,
          status: "accepted",
          processed: 0,
          continuation_scheduled: false,
        }, runId)
      ),
    Error,
    "eval_worker_schedule_failed",
  );
});
