import { type AdminActionHandler } from "./access.ts";
import {
  type AdminActionContext,
  type AdminDatabaseError,
  AdminHttpError,
} from "./types.ts";
import {
  createGeminiTriageModel,
  triageFeedback,
} from "../_shared/feedback_triage.ts";

type JsonRecord = Record<string, unknown>;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const listKeys = new Set([
  "action",
  "page",
  "limit",
  "feature",
  "review_status",
  "severity",
  "model_version",
]);
const features = new Set([
  "statement_processing",
  "card_data",
  "recommendation",
]);
const reviewStatuses = new Set([
  "pending",
  "eval_created",
  "data_issue",
  "product_defect",
  "dismissed",
]);
const severities = new Set(["critical", "high", "normal"]);
const reviewActions = new Set([
  "create_eval_draft",
  "data_issue",
  "product_defect",
  "dismiss",
]);
const caseActions = new Set(["approve", "revise", "retire"]);

function invalid(): never {
  throw new AdminHttpError("invalid_request", 400);
}
function only(body: JsonRecord, keys: ReadonlySet<string>) {
  if (Object.keys(body).some((key) => !keys.has(key))) invalid();
}
function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value)) invalid();
  return value;
}
function record(value: unknown): JsonRecord | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}
function text(value: unknown, min: number, max: number): string {
  if (typeof value !== "string") invalid();
  const result = value.trim();
  if (result.length < min || result.length > max) invalid();
  return result;
}
function object(value: unknown, max = 32_768): JsonRecord {
  const result = record(value);
  if (
    !result || new TextEncoder().encode(JSON.stringify(result)).byteLength > max
  ) invalid();
  return result;
}
function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 100 ||
    Number.isNaN(Date.parse(value))
  ) invalid();
  return value;
}
function optionalFilter(
  value: unknown,
  allowed: ReadonlySet<string>,
): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !allowed.has(value)) invalid();
  return value;
}
function dbError(error: AdminDatabaseError): AdminHttpError {
  const message = error.message?.toLowerCase() ?? "";
  if (
    message.includes("state_conflict") ||
    message.includes("request_id_collision")
  ) return new AdminHttpError("state_conflict", 409);
  if (message.includes("not_found")) {
    return new AdminHttpError("not_found", 404);
  }
  if (message.includes("reason_required")) {
    return new AdminHttpError("reason_required", 400);
  }
  if (message.includes("invalid_request")) {
    return new AdminHttpError("invalid_request", 400);
  }
  return new AdminHttpError("request_failed", 500);
}
async function rpc(
  context: AdminActionContext,
  name: string,
  args: JsonRecord,
) {
  const { data, error } = await context.db.rpc(name, args);
  if (error) throw dbError(error);
  const result = record(data);
  if (!result) throw new AdminHttpError("request_failed", 500);
  return result;
}

export function parseFeedbackListRequest(body: JsonRecord) {
  only(body, listKeys);
  const page = body.page ?? 1;
  const limit = body.limit ?? 25;
  if (
    !Number.isInteger(page) || (page as number) < 1 ||
    (page as number) > 10_000 || !Number.isInteger(limit) ||
    (limit as number) < 1 || (limit as number) > 100
  ) invalid();
  const model = body.model_version == null || body.model_version === ""
    ? null
    : text(body.model_version, 1, 100);
  if (model !== null && !/^[A-Za-z0-9._:-]+$/.test(model)) invalid();
  return {
    page: page as number,
    limit: limit as number,
    feature: optionalFilter(body.feature, features),
    reviewStatus: optionalFilter(body.review_status, reviewStatuses),
    severity: optionalFilter(body.severity, severities),
    modelVersion: model,
  };
}

function safeString(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  return [...value.replace(/[\p{Cc}\p{Cf}]/gu, " ").trim()].slice(0, max).join(
    "",
  );
}
function safeJson(value: unknown, max: number): JsonRecord {
  const row = record(value) ?? {};
  const raw = JSON.stringify(row);
  return new TextEncoder().encode(raw).byteLength <= max ? row : {};
}
function safeFeedback(rowValue: unknown, detail = false) {
  const row = record(rowValue);
  const id = row && safeString(row.id, 100);
  if (!row || !id || !UUID.test(id)) {
    throw new AdminHttpError("request_failed", 500);
  }
  const triage = safeJson(row.triage_result, 15_000);
  const base: JsonRecord = {
    id,
    feature: safeString(row.feature_key, 40) ?? "unknown",
    triage_status: safeString(row.triage_status, 30) ?? "unknown",
    review_status: safeString(row.review_status, 30) ?? "unknown",
    severity: severities.has(triage.severity as string)
      ? triage.severity
      : "normal",
    created_at: safeString(row.created_at, 100),
    model: safeString(row.model, 100),
    prompt_version: safeString(row.prompt_version, 100),
  };
  if (detail) {
    Object.assign(base, {
      feedback_text: safeString(row.feedback_text, 2000) ?? "",
      safe_context: safeJson(row.safe_input_context, 32_768),
      captured_output: safeJson(row.output_snapshot, 32_768),
      authoritative_context: safeJson(row.authoritative_context, 32_768),
      triage_proposal: triage,
      engine_version: safeString(row.engine_version, 100),
      parser_version: safeString(row.parser_version, 100),
    });
  }
  return base;
}

export async function handleFeedbackList(
  body: JsonRecord,
  context: AdminActionContext,
) {
  const request = parseFeedbackListRequest(body);
  const from = (request.page - 1) * request.limit;
  let query: any = (context.db as any).from("ai_feedback").select(
    "id,feature_key,triage_status,triage_result,review_status,model,prompt_version,created_at",
    { count: "exact" },
  );
  if (request.feature) query = query.eq("feature_key", request.feature);
  if (request.reviewStatus) {
    query = query.eq("review_status", request.reviewStatus);
  }
  if (request.modelVersion) {
    query = query.or(
      `model.eq.${request.modelVersion},prompt_version.eq.${request.modelVersion}`,
    );
  }
  if (request.severity) {
    query = query.contains("triage_result", { severity: request.severity });
  }
  query = query.order("created_at", { ascending: false }).order("id", {
    ascending: true,
  }).range(from, from + request.limit - 1);
  const { data, error, count } = await query;
  if (
    error || !Array.isArray(data) || !Number.isSafeInteger(count) || count < 0
  ) throw new AdminHttpError("request_failed", 500);
  const items = data.map((row: unknown) => safeFeedback(row));
  return { items, page: request.page, limit: request.limit, total: count };
}

export async function handleFeedbackDetail(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(body, new Set(["action", "feedback_id", "request_id"]));
  const feedbackId = uuid(body.feedback_id);
  const requestId = uuid(body.request_id);
  const audit = await context.db.rpc("record_admin_read", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _action: "feedback.detail",
    _target_type: "ai_feedback",
    _target_id: feedbackId,
    _details: {},
  });
  if (audit.error) throw dbError(audit.error);
  const result = await (context.db as any).from("ai_feedback").select(
    "id,feature_key,feedback_text,safe_input_context,output_snapshot,authoritative_context,triage_status,triage_result,review_status,engine_version,model,prompt_version,parser_version,created_at",
  ).eq("id", feedbackId).range(0, 0);
  if (result.error) throw new AdminHttpError("request_failed", 500);
  if (!Array.isArray(result.data) || result.data.length === 0) {
    throw new AdminHttpError("not_found", 404);
  }
  if (result.data.length !== 1) throw new AdminHttpError("request_failed", 500);
  const cases = await (context.db as any).from("ai_eval_cases").select(
    "id,status,revision,updated_at,approved_in_dataset_version,retired_in_dataset_version",
  ).eq("source_feedback_id", feedbackId).order("revision", { ascending: false })
    .range(0, 9);
  if (cases.error || !Array.isArray(cases.data)) {
    throw new AdminHttpError("request_failed", 500);
  }
  return {
    feedback: safeFeedback(result.data[0], true),
    eval_cases: cases.data.slice(0, 10).map((v: unknown) => safeJson(v, 4096)),
  };
}

export async function handleFeedbackReview(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(
    body,
    new Set([
      "action",
      "feedback_id",
      "review_action",
      "operator_feedback",
      "expected_output",
      "scoring_rubric",
      "severe_failure_conditions",
      "reason",
      "request_id",
    ]),
  );
  const feedbackId = uuid(body.feedback_id);
  const requestId = uuid(body.request_id);
  const action = body.review_action;
  if (typeof action !== "string" || !reviewActions.has(action)) invalid();
  let payload: JsonRecord = {};
  let reason: string | null = null;
  if (action === "create_eval_draft") {
    payload = {
      operator_feedback: text(body.operator_feedback, 2, 2000),
      expected_output: object(body.expected_output),
      scoring_rubric: object(body.scoring_rubric, 16_000),
      severe_failure_conditions: object(body.severe_failure_conditions, 16_000),
    };
  } else {try {
      reason = text(body.reason, 2, 1000);
    } catch (error) {
      if (error instanceof AdminHttpError) {
        throw new AdminHttpError("reason_required", 400);
      }
      throw error;
    }}
  const result = await rpc(context, "admin_review_ai_feedback", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _feedback_id: feedbackId,
    _action: action,
    _payload: payload,
    _reason: reason,
  });
  if (action === "create_eval_draft") {
    const caseId = uuid(result.case_id);
    const latest = await (context.db as any).from("ai_eval_cases").select(
      "id,updated_at",
    ).eq("id", caseId).range(0, 0);
    const row = Array.isArray(latest.data) ? record(latest.data[0]) : null;
    if (
      latest.error || !Array.isArray(latest.data) || latest.data.length !== 1 ||
      typeof row?.updated_at !== "string"
    ) {
      throw new AdminHttpError("request_failed", 500);
    }
    result.updated_at = row.updated_at;
  }
  return result;
}

export async function handleEvalCaseAction(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(
    body,
    new Set([
      "action",
      "case_id",
      "case_action",
      "observed_updated_at",
      "confirmation",
      "operator_feedback",
      "expected_output",
      "scoring_rubric",
      "severe_failure_conditions",
      "reason",
      "request_id",
    ]),
  );
  const caseId = uuid(body.case_id);
  const requestId = uuid(body.request_id);
  const action = body.case_action;
  if (typeof action !== "string" || !caseActions.has(action)) invalid();
  if (
    (action === "approve" && body.confirmation !== "APPROVE") ||
    (action === "retire" && body.confirmation !== "RETIRE")
  ) invalid();
  const payload = action === "revise"
    ? {
      operator_feedback: text(body.operator_feedback, 2, 2000),
      expected_output: object(body.expected_output),
      scoring_rubric: object(body.scoring_rubric, 16_000),
      severe_failure_conditions: object(body.severe_failure_conditions, 16_000),
    }
    : {};
  return await rpc(context, "admin_ai_eval_case_action", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _case_id: caseId,
    _action: action,
    _payload: payload,
    _reason: body.reason == null ? null : text(body.reason, 2, 1000),
    _observed_updated_at: timestamp(body.observed_updated_at),
  });
}

export async function handleFeedbackTriageRetry(
  body: JsonRecord,
  context: AdminActionContext,
) {
  only(body, new Set(["action", "feedback_id", "request_id"]));
  const id = uuid(body.feedback_id);
  const requestId = uuid(body.request_id);
  const current = await (context.db as any).from("ai_feedback").select(
    "id,triage_status",
  ).eq("id", id).range(0, 0);
  if (current.error) throw new AdminHttpError("request_failed", 500);
  if (!Array.isArray(current.data) || current.data.length === 0) {
    throw new AdminHttpError("not_found", 404);
  }
  if (record(current.data[0])?.triage_status !== "triage_failed") {
    throw new AdminHttpError("state_conflict", 409);
  }
  const audit = await context.db.rpc("record_admin_read", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _action: "feedback.triage_retry",
    _target_type: "ai_feedback",
    _target_id: id,
    _details: {},
  });
  if (audit.error) throw dbError(audit.error);
  const reset = await (context.db as any).from("ai_feedback").update({
    triage_status: "awaiting_triage",
    triage_failure_category: null,
  }).eq("id", id).eq("triage_status", "triage_failed").select("id").range(0, 0);
  if (reset.error || !Array.isArray(reset.data) || reset.data.length !== 1) {
    throw new AdminHttpError("state_conflict", 409);
  }
  const apiKeys = [
    Deno.env.get("GEMINI_API_KEY"),
    Deno.env.get("GEMINI_API_KEY_2"),
  ].filter((key): key is string => Boolean(key));
  const model = createGeminiTriageModel({ apiKeys, fetch });
  const task = triageFeedback(id, {
    rpc: async (name, args) => {
      const result = await context.db.rpc(name, args);
      if (result.error) throw dbError(result.error);
      return result.data;
    },
    model,
  });
  try {
    (globalThis as any).EdgeRuntime?.waitUntil?.(task);
  } catch {
    task.catch(() => undefined);
  }
  return { feedback_id: id, triage_status: "awaiting_triage" };
}

export const feedbackActionHandlers: Readonly<
  Record<string, AdminActionHandler>
> = Object.freeze(Object.assign(Object.create(null), {
  "feedback-list": handleFeedbackList,
  "feedback-detail": handleFeedbackDetail,
  "feedback-review": handleFeedbackReview,
  "feedback-triage-retry": handleFeedbackTriageRetry,
  "eval-case-action": handleEvalCaseAction,
}));
