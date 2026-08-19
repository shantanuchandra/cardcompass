import { type AdminActionHandler } from "./access.ts";
import {
  type AdminActionContext,
  type AdminDatabaseError,
  AdminHttpError,
} from "./types.ts";
import {
  getCandidateConfig,
  getEvalConfig,
  getJudgeConfig,
} from "../ai-eval-runner/config_registry.ts";

type JsonRecord = Record<string, unknown>;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CANDIDATES = Object.freeze([
  "gemini-3.6-flash-statement-v1",
  "gemini-3.6-flash-card-data-v1",
  "gemini-3.6-flash-recommendation-v1",
]);
const STATUSES = new Set([
  "queued",
  "running",
  "completed",
  "completed_with_failures",
  "failed",
  "cancelled",
]);
const SAFE_FAILURES = new Set([
  "cost_ceiling_reached",
  "model_unavailable",
  "invalid_model_output",
  "provider_failed",
  "persistence_failed",
  "insufficient_fixture",
]);
const RUN_COLUMNS =
  "id,dataset_version,baseline_config_key,candidate_config_key,judge_config_key,status,maximum_case_count,cost_ceiling_usd,latency_ceiling_ms,aggregate_metrics,token_usage,estimated_cost_usd,safe_failure_category,created_at,started_at,completed_at,updated_at";
const RESULT_COLUMNS =
  "case_id,case_revision,feature_key,deterministic_assertions,judge_verdict,requires_review,regression,severe_regression,baseline_latency_ms,candidate_latency_ms,baseline_input_tokens,baseline_output_tokens,candidate_input_tokens,candidate_output_tokens,estimated_cost_usd,execution_status,safe_failure_category,attempt_count,updated_at";

function invalid(): never {
  throw new AdminHttpError("invalid_request", 400);
}
function only(body: JsonRecord, keys: ReadonlySet<string>) {
  if (Object.keys(body).some((key) => !keys.has(key))) invalid();
}
function record(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}
function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value)) invalid();
  return value;
}
function integer(value: unknown, min: number, max: number): number {
  if (
    !Number.isSafeInteger(value) || (value as number) < min ||
    (value as number) > max
  ) invalid();
  return value as number;
}
function money(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isFinite(value) || value <= 0 ||
    value > 100 || Math.round(value * 1_000_000) !== value * 1_000_000
  ) invalid();
  return value;
}
function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 100 ||
    !value.toLowerCase().includes("t") || Number.isNaN(Date.parse(value))
  ) invalid();
  return value;
}
function safeNumber(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new AdminHttpError("request_failed", 500);
  }
  return parsed;
}
function safeInt(value: unknown): number {
  const parsed = safeNumber(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new AdminHttpError("request_failed", 500);
  }
  return parsed;
}
function safeTimestamp(value: unknown, nullable = false): string | null {
  if (value == null && nullable) return null;
  if (
    typeof value !== "string" || value.length > 100 ||
    Number.isNaN(Date.parse(value))
  ) throw new AdminHttpError("request_failed", 500);
  return value;
}
function dbError(error: AdminDatabaseError): AdminHttpError {
  const text = error.message?.toLowerCase() ?? "";
  if (
    text.includes("state_conflict") || text.includes("request_id_collision")
  ) return new AdminHttpError("state_conflict", 409);
  if (text.includes("not_found")) return new AdminHttpError("not_found", 404);
  if (text.includes("invalid_request")) {
    return new AdminHttpError("invalid_request", 400);
  }
  return new AdminHttpError("request_failed", 500);
}

function configDto(key: string, role: "candidate" | "baseline" | "judge") {
  const config = role === "candidate"
    ? getCandidateConfig(key)
    : role === "judge"
    ? getJudgeConfig(key)
    : getEvalConfig(key);
  return {
    key: config.key,
    role,
    feature: config.featureKey,
    provider: config.provider,
    model: config.model,
    prompt_version: config.promptVersion,
    task_scope: config.taskScope,
    estimated_maximum_cost_usd: config.estimatedMaximumCostUsd,
    scope_note:
      config.taskScope === "fixed_selection_explanation_and_arithmetic"
        ? "Does not evaluate ranking."
        : null,
  };
}

export async function handleEvalConfigList(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(body, new Set(["action"]));
  const result = await (context.db as any).from("ai_eval_cases").select(
    "approved_in_dataset_version",
  ).eq("status", "approved").order("approved_in_dataset_version", {
    ascending: false,
  }).range(0, 0);
  if (result.error || !Array.isArray(result.data)) {
    throw new AdminHttpError("request_failed", 500);
  }
  const version = result.data.length === 0
    ? 0
    : safeInt(record(result.data[0])?.approved_in_dataset_version);
  return {
    dataset_version: version,
    baseline: configDto("captured-production-v1", "baseline"),
    judge: configDto("gemini-3.6-flash-blind-judge-v1", "judge"),
    configs: CANDIDATES.map((key) => configDto(key, "candidate")),
  };
}

function presentRun(value: unknown) {
  const row = record(value);
  if (
    !row || typeof row.id !== "string" || !UUID.test(row.id) ||
    typeof row.status !== "string" || !STATUSES.has(row.status)
  ) throw new AdminHttpError("request_failed", 500);
  const candidate = getCandidateConfig(String(row.candidate_config_key));
  if (
    row.baseline_config_key !== "captured-production-v1" ||
    row.judge_config_key !== "gemini-3.6-flash-blind-judge-v1"
  ) throw new AdminHttpError("request_failed", 500);
  return {
    id: row.id,
    dataset_version: safeInt(row.dataset_version),
    feature: candidate.featureKey,
    task_scope: candidate.taskScope,
    scope_note:
      candidate.taskScope === "fixed_selection_explanation_and_arithmetic"
        ? "Does not evaluate ranking."
        : null,
    baseline_config_key: row.baseline_config_key,
    candidate_config_key: row.candidate_config_key,
    judge_config_key: row.judge_config_key,
    status: row.status,
    maximum_case_count: safeInt(row.maximum_case_count),
    cost_ceiling_usd: safeNumber(row.cost_ceiling_usd),
    latency_ceiling_ms: safeInt(row.latency_ceiling_ms),
    aggregate_metrics: safeAggregates(row.aggregate_metrics),
    token_usage: safeTokenUsage(row.token_usage),
    estimated_cost_usd: safeNumber(row.estimated_cost_usd),
    safe_failure_category: safeFailure(row.safe_failure_category),
    created_at: safeTimestamp(row.created_at),
    started_at: safeTimestamp(row.started_at, true),
    completed_at: safeTimestamp(row.completed_at, true),
    updated_at: safeTimestamp(row.updated_at),
  };
}
function safeObject(value: unknown, max: number): JsonRecord {
  const result = record(value) ?? {};
  return new TextEncoder().encode(JSON.stringify(result)).byteLength <= max
    ? result
    : {};
}
function safeAggregates(value: unknown): JsonRecord {
  const row = record(value) ?? {};
  const result: JsonRecord = {};
  for (
    const key of [
      "case_count",
      "succeeded",
      "failed",
      "missing",
      "regressions",
      "severe_regressions",
      "average_latency_ms",
    ]
  ) {
    if (Object.hasOwn(row, key)) result[key] = safeNumber(row[key]);
  }
  const failures = record(row.failure_categories);
  if (failures) {
    const safe: JsonRecord = {};
    for (const [key, count] of Object.entries(failures)) {
      if (SAFE_FAILURES.has(key)) safe[key] = safeInt(count);
    }
    result.failure_categories = safe;
  }
  return result;
}
function safeTokenUsage(value: unknown): JsonRecord {
  const row = record(value) ?? {};
  const result: JsonRecord = {};
  for (
    const key of [
      "baseline_input",
      "baseline_output",
      "candidate_input",
      "candidate_output",
    ]
  ) if (Object.hasOwn(row, key)) result[key] = safeInt(row[key]);
  return result;
}
function safeFailure(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string" || !SAFE_FAILURES.has(value)) {
    throw new AdminHttpError("request_failed", 500);
  }
  return value;
}

export async function handleEvalRunList(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(body, new Set(["action", "page", "limit", "status", "feature"]));
  const page = body.page == null ? 1 : integer(body.page, 1, 10_000),
    limit = body.limit == null ? 20 : integer(body.limit, 1, 50);
  const status = body.status == null || body.status === ""
    ? null
    : String(body.status);
  if (status && !STATUSES.has(status)) invalid();
  const feature = body.feature == null || body.feature === ""
    ? null
    : String(body.feature);
  if (
    feature &&
    !["statement_processing", "card_data", "recommendation"].includes(feature)
  ) invalid();
  let query: any = (context.db as any).from("ai_eval_runs").select(
    RUN_COLUMNS,
    { count: "exact" },
  );
  if (status) query = query.eq("status", status);
  if (feature) {
    query = query.eq(
      "candidate_config_key",
      CANDIDATES[
        ["statement_processing", "card_data", "recommendation"].indexOf(feature)
      ],
    );
  }
  const from = (page - 1) * limit;
  const result = await query.order("created_at", { ascending: false }).order(
    "id",
    { ascending: true },
  ).range(from, from + limit - 1);
  if (
    result.error || !Array.isArray(result.data) ||
    !Number.isSafeInteger(result.count) || result.count < 0
  ) throw new AdminHttpError("request_failed", 500);
  return {
    items: result.data.map(presentRun),
    page,
    limit,
    total: result.count,
  };
}

function assertionSummary(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) {
    return { baseline: false, candidate: false, review: true };
  }
  let baseline = true, candidate = true;
  for (const item of value) {
    const row = record(item);
    if (
      !row || typeof row.baselinePassed !== "boolean" ||
      typeof row.candidatePassed !== "boolean"
    ) return { baseline: false, candidate: false, review: true };
    baseline &&= row.baselinePassed;
    candidate &&= row.candidatePassed;
  }
  // A baseline miss is the improvement opportunity, not by itself a reason to
  // hold a passing candidate for review. Candidate failures remain fail-closed.
  return { baseline, candidate, review: !candidate };
}
function quantile95(values: number[]) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.ceil(sorted.length * .95) - 1];
}

export async function handleEvalRunDetail(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(
    body,
    new Set(["action", "run_id", "request_id", "result_page", "result_limit"]),
  );
  const id = uuid(body.run_id), request = uuid(body.request_id);
  const resultPage = body.result_page == null
    ? 1
    : integer(body.result_page, 1, 10_000);
  const resultLimit = body.result_limit == null
    ? 25
    : integer(body.result_limit, 1, 50);
  const audit = await context.db.rpc("record_admin_read", {
    _actor_id: context.actor.id,
    _request_id: request,
    _action: "eval.run.detail",
    _target_type: "ai_eval_run",
    _target_id: id,
    _details: {},
  });
  if (audit.error) throw dbError(audit.error);
  const runResult = await (context.db as any).from("ai_eval_runs").select(
    RUN_COLUMNS,
  ).eq("id", id).range(0, 0);
  if (runResult.error) throw new AdminHttpError("request_failed", 500);
  if (!Array.isArray(runResult.data) || runResult.data.length === 0) {
    throw new AdminHttpError("not_found", 404);
  }
  if (runResult.data.length !== 1) {
    throw new AdminHttpError("request_failed", 500);
  }
  const run = presentRun(runResult.data[0]);
  const resultsQuery = await (context.db as any).from("ai_eval_results").select(
    RESULT_COLUMNS,
  ).eq("run_id", id).order("case_id", { ascending: true }).order(
    "case_revision",
    { ascending: true },
  ).range(0, 99);
  if (resultsQuery.error || !Array.isArray(resultsQuery.data)) {
    throw new AdminHttpError("request_failed", 500);
  }
  let baselinePass = 0, candidatePass = 0, reviewCount = 0;
  const latencies: number[] = [];
  const results = resultsQuery.data.map((value: unknown) => {
    const row = record(value);
    if (!row || typeof row.case_id !== "string" || !UUID.test(row.case_id)) {
      throw new AdminHttpError("request_failed", 500);
    }
    const execution = row.execution_status;
    if (execution !== "succeeded" && execution !== "failed") {
      throw new AdminHttpError("request_failed", 500);
    }
    const assertions = assertionSummary(row.deterministic_assertions);
    safeObject(row.judge_verdict, 2_048);
    if (typeof row.requires_review !== "boolean") {
      throw new AdminHttpError("request_failed", 500);
    }
    const requiresReview = execution !== "succeeded" || assertions.review ||
      row.requires_review;
    if (execution === "succeeded" && assertions.baseline) baselinePass++;
    if (execution === "succeeded" && assertions.candidate) candidatePass++;
    if (requiresReview) reviewCount++;
    const candidateLatency = safeInt(row.candidate_latency_ms);
    latencies.push(candidateLatency);
    return {
      case_id: row.case_id,
      case_revision: safeInt(row.case_revision),
      feature: row.feature_key,
      execution_status: execution,
      baseline_passed: assertions.baseline,
      candidate_passed: assertions.candidate,
      regression: row.regression === true,
      severe_regression: row.severe_regression === true,
      requires_review: requiresReview,
      safe_failure_category: safeFailure(row.safe_failure_category),
      baseline_latency_ms: safeInt(row.baseline_latency_ms),
      candidate_latency_ms: candidateLatency,
      baseline_input_tokens: safeInt(row.baseline_input_tokens),
      baseline_output_tokens: safeInt(row.baseline_output_tokens),
      candidate_input_tokens: safeInt(row.candidate_input_tokens),
      candidate_output_tokens: safeInt(row.candidate_output_tokens),
      estimated_cost_usd: safeNumber(row.estimated_cost_usd),
      attempt_count: safeInt(row.attempt_count),
      updated_at: safeTimestamp(row.updated_at),
    };
  });
  const count = results.length,
    baselineRate = count ? baselinePass / count : 0,
    candidateRate = count ? candidatePass / count : 0,
    p95 = quantile95(latencies);
  const aggregate = run.aggregate_metrics;
  const authoritativeAggregate = [
    "case_count",
    "succeeded",
    "failed",
    "missing",
    "severe_regressions",
  ].every((key) => Object.hasOwn(aggregate, key));
  const caseCount = safeInt(aggregate.case_count ?? 0);
  const succeeded = safeInt(aggregate.succeeded ?? 0);
  const failed = safeInt(aggregate.failed ?? 0);
  const missing = safeInt(aggregate.missing ?? 0);
  const severe = safeInt(aggregate.severe_regressions ?? 0);
  const failureCategories = record(aggregate.failure_categories) ?? {};
  const insufficientFixture = Object.hasOwn(
      failureCategories,
      "insufficient_fixture",
    )
    ? safeInt(failureCategories.insufficient_fixture)
    : 0;
  const blockers: string[] = [];
  if (candidateRate <= baselineRate) {
    blockers.push("candidate_pass_rate_not_improved");
  }
  if (severe > 0) blockers.push("severe_regressions_present");
  if (run.estimated_cost_usd > run.cost_ceiling_usd) {
    blockers.push("cost_ceiling_exceeded");
  }
  if (p95 > run.latency_ceiling_ms) blockers.push("latency_ceiling_exceeded");
  if (reviewCount > 0) blockers.push("manual_review_required");
  if (run.status !== "completed") blockers.push("run_not_completed");
  if (failed > 0) blockers.push("failed_cases_present");
  if (missing > 0) blockers.push("missing_cases_present");
  if (insufficientFixture > 0) blockers.push("insufficient_fixture_present");
  if (
    !authoritativeAggregate || caseCount !== count || succeeded !== caseCount ||
    succeeded + failed + missing !== caseCount
  ) blockers.push("incomplete_result_set");
  return {
    run,
    metrics: {
      baseline_pass_rate: baselineRate,
      candidate_pass_rate: candidateRate,
      p95_candidate_latency_ms: p95,
      manual_review_count: reviewCount,
    },
    decision: {
      status: blockers.length === 0 ? "candidate_supported" : "review_required",
      blockers,
    },
    results: {
      items: results.slice(
        (resultPage - 1) * resultLimit,
        resultPage * resultLimit,
      ),
      page: resultPage,
      limit: resultLimit,
      total: results.length,
    },
  };
}

export async function handleEvalRunAction(
  body: JsonRecord,
  context: AdminActionContext,
) {
  const operation = body.operation;
  if (operation === "start") {
    only(
      body,
      new Set([
        "action",
        "operation",
        "request_id",
        "dataset_version",
        "baseline_config_key",
        "candidate_config_key",
        "judge_config_key",
        "maximum_case_count",
        "cost_ceiling_usd",
        "latency_ceiling_ms",
      ]),
    );
    const request = uuid(body.request_id),
      dataset = integer(body.dataset_version, 1, Number.MAX_SAFE_INTEGER),
      maxCases = integer(body.maximum_case_count, 1, 100),
      cost = money(body.cost_ceiling_usd),
      latency = integer(body.latency_ceiling_ms, 1, 600_000);
    if (
      body.baseline_config_key !== "captured-production-v1" ||
      body.judge_config_key !== "gemini-3.6-flash-blind-judge-v1" ||
      typeof body.candidate_config_key !== "string" ||
      !CANDIDATES.includes(body.candidate_config_key)
    ) invalid();
    const config = getCandidateConfig(body.candidate_config_key);
    const requiredCost =
      (config.estimatedMaximumCostUsd + (config.featureKey === "recommendation"
        ? getJudgeConfig(String(body.judge_config_key)).estimatedMaximumCostUsd
        : 0)) * maxCases;
    if (cost + 1e-9 < requiredCost) {
      invalid();
    }
    const rpc = await context.db.rpc("admin_create_ai_eval_run", {
      _actor_id: context.actor.id,
      _request_id: request,
      _dataset_version: dataset,
      _baseline_config_key: body.baseline_config_key,
      _candidate_config_key: body.candidate_config_key,
      _judge_config_key: body.judge_config_key,
      _maximum_case_count: maxCases,
      _cost_ceiling_usd: cost,
      _latency_ceiling_ms: latency,
    });
    if (rpc.error) {
      throw dbError(rpc.error);
    }
    const receipt = exactReceipt(
      rpc.data,
      new Set(["run_id", "status", "case_count"]),
    );
    const run = uuid(receipt.run_id);
    if (typeof receipt.status !== "string" || !STATUSES.has(receipt.status)) {
      throw new AdminHttpError("request_failed", 500);
    }
    integer(receipt.case_count, 1, maxCases);
    if (receipt.status === "queued" || receipt.status === "running") {
      try {
        await context.scheduleEvalRun?.(run);
      } catch {
        /* durable receipt wins; retry remains available */
      }
    }
    return {
      result: {
        run_id: run,
        status: receipt.status,
        case_count: receipt.case_count,
      },
    };
  }
  if (operation !== "cancel" && operation !== "resume_failed") invalid();
  only(
    body,
    new Set([
      "action",
      "operation",
      "run_id",
      "request_id",
      "observed_updated_at",
    ]),
  );
  const id = uuid(body.run_id),
    request = uuid(body.request_id),
    observed = timestamp(body.observed_updated_at);
  const rpc = await context.db.rpc("admin_ai_eval_run_action", {
    _actor_id: context.actor.id,
    _request_id: request,
    _run_id: id,
    _action: operation,
    _observed_updated_at: observed,
  });
  if (rpc.error) throw dbError(rpc.error);
  const receipt = exactReceipt(rpc.data, new Set(["run_id", "status"]));
  if (
    receipt.run_id !== id ||
    (operation === "cancel"
      ? receipt.status !== "cancelled"
      : receipt.status !== "queued")
  ) throw new AdminHttpError("request_failed", 500);
  if (operation === "resume_failed") {
    try {
      await context.scheduleEvalRun?.(id);
    } catch { /* durable queued state remains resumable */ }
  }
  return { result: { run_id: id, status: receipt.status } };
}
function exactReceipt(value: unknown, keys: ReadonlySet<string>): JsonRecord {
  const result = record(value);
  if (
    !result || Object.keys(result).length !== keys.size ||
    Object.keys(result).some((key) => !keys.has(key))
  ) throw new AdminHttpError("request_failed", 500);
  return result;
}

export const evalActionHandlers: Readonly<Record<string, AdminActionHandler>> =
  Object.freeze(Object.assign(Object.create(null), {
    "eval-config-list": handleEvalConfigList,
    "eval-run-list": handleEvalRunList,
    "eval-run-detail": handleEvalRunDetail,
    "eval-run-action": handleEvalRunAction,
  }));
