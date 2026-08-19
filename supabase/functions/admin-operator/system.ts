import { type AdminActionHandler } from "./access.ts";
import {
  type AdminActionContext,
  type AdminDatabaseError,
  AdminHttpError,
} from "./types.ts";

type JsonRecord = Record<string, unknown>;
type JobFamily = "benefit_enrichment" | "card_discovery";

export type PipelineSummary = Readonly<{
  key: JobFamily;
  status: "healthy" | "degraded" | "paused" | "unknown";
  queued: number;
  running: number;
  failed: number;
  quarantined: number;
  last_success_at: string | null;
  source_error: "source_unavailable" | null;
}>;

export type SystemJobDto = Readonly<{
  id: string;
  family: JobFamily;
  status: string;
  failure_category: string | null;
  attempt_count: number;
  next_retry_at: string | null;
  updated_at: string;
}>;

type RuntimeControlDto = Readonly<{
  control_key: "benefit_enrichment_scheduled";
  is_paused: boolean;
  reason: string | null;
  updated_at: string;
}>;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_LIMIT = 50;
const MAX_PAGE = 10_000;
export const SAFE_SYSTEM_FAILURE_CATEGORIES = Object.freeze(
  [
    "source_timeout",
    "provider_timeout",
    "worker_resource_limit",
    "manual_quarantine",
    "manual_review",
    "ambiguous_identity",
    "fetch_failed",
    "parse_failed",
    "validation_failed",
    "rate_limited",
    "not_a_card",
    "ambiguous_product",
    "identity_mismatch",
    "unapproved_domain",
    "unsupported_content",
    "unreachable",
    "insufficient_evidence",
    "redirect_rejected",
    "private_address",
    "oversized",
    "timeout",
    "enrichment_failed",
    "invalid_url",
    "issuer_mismatch",
    "not_product_page",
    "unsafe_redirect",
    "fetch_timeout",
    "identity_conflict",
    "review_required",
  ] as const,
);
const safeFailureCategories = new Set<string>(
  SAFE_SYSTEM_FAILURE_CATEGORIES,
);
const statuses: Readonly<Record<JobFamily, ReadonlySet<string>>> = Object
  .freeze({
    benefit_enrichment: new Set([
      "queued",
      "processing",
      "completed",
      "review_required",
      "failed",
      "staged",
      "quarantined",
    ]),
    card_discovery: new Set([
      "queued",
      "discovering",
      "resolved",
      "review_required",
      "rejected",
      "failed",
    ]),
  });
const mutationStatuses: Readonly<Record<string, ReadonlySet<string>>> = Object
  .freeze({
    retry: new Set(["failed", "review_required", "quarantined"]),
    quarantine: new Set(["queued", "failed", "review_required", "staged"]),
    unquarantine: new Set(["quarantined"]),
  });

function invalidRequest(): never {
  throw new AdminHttpError("invalid_request", 400);
}

function onlyKeys(body: JsonRecord, allowed: ReadonlySet<string>) {
  if (Object.keys(body).some((key) => !allowed.has(key))) invalidRequest();
}

function record(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value)) invalidRequest();
  return value;
}

function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 100 ||
    !/^\d{4}-\d{2}-\d{2}t/i.test(value) || Number.isNaN(Date.parse(value))
  ) invalidRequest();
  return value;
}

function safeTimestamp(value: unknown): string | null {
  return typeof value === "string" && value.length <= 100 &&
      !Number.isNaN(Date.parse(value))
    ? value
    : null;
}

function reason(value: unknown, required = true): string | null {
  if (value == null && !required) return null;
  if (typeof value !== "string") invalidRequest();
  const normalized = value.trim();
  if (normalized.length < 2 || normalized.length > 500) invalidRequest();
  return normalized;
}

function family(value: unknown): JobFamily {
  if (value !== "benefit_enrichment" && value !== "card_discovery") {
    invalidRequest();
  }
  return value;
}

function mapDatabaseError(error: AdminDatabaseError): AdminHttpError {
  const message = typeof error.message === "string"
    ? error.message.toLowerCase()
    : "";
  if (
    message.includes("request_id_collision") ||
    message.includes("state_conflict")
  ) return new AdminHttpError("state_conflict", 409);
  if (message.includes("reason_required")) {
    return new AdminHttpError("reason_required", 400);
  }
  if (message.includes("not_found")) {
    return new AdminHttpError("not_found", 404);
  }
  if (message.includes("invalid_request")) {
    return new AdminHttpError("invalid_request", 400);
  }
  return new AdminHttpError("request_failed", 500);
}

async function exactStatusCount(
  context: AdminActionContext,
  table: string,
  status: string,
): Promise<number> {
  const { count, error } = await (context.db as any).from(table)
    .select("id", { count: "exact", head: true }).eq("status", status);
  if (
    error || typeof count !== "number" || !Number.isSafeInteger(count) ||
    count < 0
  ) {
    throw new Error("source_unavailable");
  }
  return count;
}

async function lastSuccess(
  context: AdminActionContext,
  table: string,
  status: string,
): Promise<string | null> {
  const { data, error } = await (context.db as any).from(table)
    .select("updated_at").eq("status", status)
    .order("updated_at", { ascending: false }).order("id", { ascending: false })
    .range(0, 0);
  if (error || !Array.isArray(data)) throw new Error("source_unavailable");
  if (data.length === 0) return null;
  const value = safeTimestamp(record(data[0])?.updated_at);
  if (value === null) throw new Error("source_unavailable");
  return value;
}

async function loadPipeline(
  context: AdminActionContext,
  key: JobFamily,
): Promise<Omit<PipelineSummary, "status" | "source_error">> {
  const table = key === "benefit_enrichment"
    ? "card_catalog_enrichment_jobs"
    : "card_discovery_jobs";
  const runningStatus = key === "benefit_enrichment"
    ? "processing"
    : "discovering";
  const successStatus = key === "benefit_enrichment" ? "completed" : "resolved";
  const [queued, running, failed, quarantined, lastSuccessAt] = await Promise
    .all([
      exactStatusCount(context, table, "queued"),
      exactStatusCount(context, table, runningStatus),
      exactStatusCount(context, table, "failed"),
      key === "benefit_enrichment"
        ? exactStatusCount(context, table, "quarantined")
        : Promise.resolve(0),
      lastSuccess(context, table, successStatus),
    ]);
  return {
    key,
    queued,
    running,
    failed,
    quarantined,
    last_success_at: lastSuccessAt,
  };
}

function summarize(
  values: Omit<PipelineSummary, "status" | "source_error">,
  paused: boolean,
): PipelineSummary {
  return {
    ...values,
    status: paused
      ? "paused"
      : values.failed + values.quarantined > 0
      ? "degraded"
      : "healthy",
    source_error: null,
  };
}

const unavailable = (key: JobFamily): PipelineSummary => ({
  key,
  status: "unknown",
  queued: 0,
  running: 0,
  failed: 0,
  quarantined: 0,
  last_success_at: null,
  source_error: "source_unavailable",
});

function presentControl(value: unknown): RuntimeControlDto | null {
  const row = record(value);
  const updatedAt = safeTimestamp(row?.updated_at);
  if (
    row?.control_key !== "benefit_enrichment_scheduled" ||
    typeof row.is_paused !== "boolean" || updatedAt === null
  ) return null;
  return {
    control_key: row.control_key,
    is_paused: row.is_paused,
    reason: typeof row.reason === "string" ? row.reason.slice(0, 500) : null,
    updated_at: updatedAt,
  };
}

export async function handleSystemStatus(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(body, new Set(["action"]));
  const [benefitResult, discoveryResult, controlResult] = await Promise
    .allSettled([
      loadPipeline(context, "benefit_enrichment"),
      loadPipeline(context, "card_discovery"),
      (async () => {
        const { data, error } = await (context.db as any).from(
          "admin_runtime_controls",
        )
          .select("control_key,is_paused,reason,updated_at")
          .eq("control_key", "benefit_enrichment_scheduled").range(0, 0);
        const control = !error && Array.isArray(data) && data.length === 1
          ? presentControl(data[0])
          : null;
        if (control === null) throw new Error("source_unavailable");
        return control;
      })(),
    ]);
  const controls = controlResult.status === "fulfilled"
    ? [controlResult.value]
    : [];
  const controlAvailable = controlResult.status === "fulfilled";
  const paused = controlAvailable && controlResult.value.is_paused;
  return {
    pipelines: [
      benefitResult.status === "fulfilled" && controlAvailable
        ? summarize(benefitResult.value, paused)
        : unavailable("benefit_enrichment"),
      discoveryResult.status === "fulfilled"
        ? summarize(discoveryResult.value, false)
        : unavailable("card_discovery"),
    ],
    controls,
    control_source_error: controlAvailable ? null : "source_unavailable",
  };
}

function page(body: JsonRecord): { page: number; limit: number } {
  const p = body.page === undefined ? 1 : body.page;
  const l = body.limit === undefined ? 25 : body.limit;
  if (
    !Number.isInteger(p) || !Number.isInteger(l) || (p as number) < 1 ||
    (p as number) > MAX_PAGE || (l as number) < 1 || (l as number) > MAX_LIMIT
  ) invalidRequest();
  return { page: p as number, limit: l as number };
}

function presentJob(
  value: unknown,
  selectedFamily: JobFamily,
): SystemJobDto | null {
  const row = record(value);
  const updatedAt = safeTimestamp(row?.updated_at);
  if (
    !row || typeof row.id !== "string" || row.id.length > 100 ||
    typeof row.status !== "string" ||
    !statuses[selectedFamily].has(row.status) || updatedAt === null
  ) return null;
  return {
    id: row.id,
    family: selectedFamily,
    status: row.status,
    failure_category: row.failure_category == null
      ? null
      : typeof row.failure_category === "string" &&
          safeFailureCategories.has(row.failure_category)
      ? row.failure_category
      : "unknown_failure",
    attempt_count: typeof row.attempt_count === "number" &&
        Number.isSafeInteger(row.attempt_count) && row.attempt_count >= 0
      ? row.attempt_count
      : 0,
    next_retry_at: safeTimestamp(row.next_retry_at),
    updated_at: updatedAt,
  };
}

export async function handleSystemJobs(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set(["action", "family", "status", "page", "limit", "target_id"]),
  );
  const selectedFamily = family(body.family);
  const selectedStatus = body.status == null
    ? null
    : typeof body.status === "string" &&
        statuses[selectedFamily].has(body.status)
    ? body.status
    : invalidRequest();
  const targetId = body.target_id == null ? null : uuid(body.target_id);
  const pagination = page(body);
  const table = selectedFamily === "benefit_enrichment"
    ? "card_catalog_enrichment_jobs"
    : "card_discovery_jobs";
  let query = (context.db as any).from(table).select(
    "id,status,failure_category,attempt_count,next_retry_at,updated_at",
  );
  if (selectedStatus) query = query.eq("status", selectedStatus);
  if (targetId) query = query.eq("id", targetId);
  const offset = (pagination.page - 1) * pagination.limit;
  const { data, error } = await query.order("updated_at", { ascending: false })
    .order("id", { ascending: false }).range(offset, offset + pagination.limit);
  if (error) throw mapDatabaseError(error);
  const items = (Array.isArray(data) ? data : []).map((row) =>
    presentJob(row, selectedFamily)
  ).filter((item): item is SystemJobDto => item !== null)
    .sort((left, right) =>
      right.updated_at.localeCompare(left.updated_at) ||
      right.id.localeCompare(left.id)
    );
  return {
    items: items.slice(0, pagination.limit),
    page: pagination.page,
    limit: pagination.limit,
    has_more: items.length > pagination.limit,
  };
}

export async function handleSystemMutation(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set([
      "action",
      "operation",
      "family",
      "status",
      "target_id",
      "request_id",
      "observed_updated_at",
      "reason",
    ]),
  );
  if (family(body.family) !== "benefit_enrichment") invalidRequest();
  let operation: "retry" | "quarantine" | "unquarantine";
  if (
    body.action === "system-retry" && !Object.hasOwn(body, "operation")
  ) {
    operation = "retry";
  } else if (
    body.action === "system-quarantine" &&
    (body.operation === "quarantine" ||
      body.operation === "unquarantine")
  ) {
    operation = body.operation === "unquarantine"
      ? "unquarantine"
      : "quarantine";
  } else {
    invalidRequest();
  }
  if (
    typeof body.status !== "string" ||
    !mutationStatuses[operation].has(body.status)
  ) invalidRequest();
  const mutationReason = reason(body.reason, operation === "quarantine");
  const targetId = uuid(body.target_id);
  const { data, error } = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
    _request_id: uuid(body.request_id),
    _lane: "benefit",
    _operation: operation,
    _target_id: targetId,
    _staging_id: null,
    _payload: {},
    _reason: mutationReason,
    _observed_updated_at: timestamp(body.observed_updated_at),
  });
  if (error) throw mapDatabaseError(error);
  const result = record(data);
  const expectedStatus = operation === "quarantine" ? "quarantined" : "queued";
  if (
    result?.job_id !== targetId || result.resulting_status !== expectedStatus
  ) {
    throw new AdminHttpError("request_failed", 500);
  }
  return {
    result: {
      job_id: targetId,
      resulting_status: expectedStatus,
    },
  };
}

export async function handleSystemControl(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set([
      "action",
      "control_key",
      "is_paused",
      "request_id",
      "observed_updated_at",
      "reason",
    ]),
  );
  if (
    body.control_key !== "benefit_enrichment_scheduled" ||
    typeof body.is_paused !== "boolean"
  ) invalidRequest();
  const requestedReason = reason(body.reason);
  const observedAt = timestamp(body.observed_updated_at);
  const { data, error } = await context.db.rpc("admin_set_runtime_control", {
    _actor_id: context.actor.id,
    _request_id: uuid(body.request_id),
    _control_key: body.control_key,
    _is_paused: body.is_paused,
    _reason: requestedReason,
    _observed_updated_at: observedAt,
  });
  if (error) throw mapDatabaseError(error);
  const result = presentControl(data);
  if (
    !result || result.control_key !== body.control_key ||
    result.is_paused !== body.is_paused || result.reason !== requestedReason ||
    Date.parse(result.updated_at) <= Date.parse(observedAt)
  ) throw new AdminHttpError("request_failed", 500);
  return { result };
}

export const systemActionHandlers: Readonly<
  Record<string, AdminActionHandler>
> = Object.freeze(Object.assign(Object.create(null), {
  "system-status": handleSystemStatus,
  "system-jobs": handleSystemJobs,
  "system-retry": handleSystemMutation,
  "system-quarantine": handleSystemMutation,
  "system-control": handleSystemControl,
}));
