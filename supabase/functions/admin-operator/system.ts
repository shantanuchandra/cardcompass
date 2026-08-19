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
const MAX_SOURCE_ROWS = 1_000;
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

async function boundedRows(
  context: AdminActionContext,
  table: string,
  columns: string,
): Promise<unknown[]> {
  const { data, error } = await (context.db as any).from(table).select(columns)
    .range(0, MAX_SOURCE_ROWS - 1);
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

function summarize(
  key: JobFamily,
  rows: unknown[],
  paused: boolean,
): PipelineSummary {
  const values = rows.map(record).filter((row): row is JsonRecord =>
    row !== null
  );
  const count = (...expected: string[]) =>
    values.filter((row) => expected.includes(row.status as string)).length;
  const successes = values.map((row) => ({
    status: row.status,
    at: safeTimestamp(row.updated_at),
  }))
    .filter((row) =>
      row.at !== null &&
      (key === "benefit_enrichment"
        ? row.status === "completed"
        : row.status === "resolved")
    )
    .map((row) => row.at as string).sort().reverse();
  const failed = count("failed");
  const quarantined = key === "benefit_enrichment" ? count("quarantined") : 0;
  return {
    key,
    status: paused
      ? "paused"
      : failed + quarantined > 0
      ? "degraded"
      : "healthy",
    queued: count("queued"),
    running: count(key === "benefit_enrichment" ? "processing" : "discovering"),
    failed,
    quarantined,
    last_success_at: successes[0] ?? null,
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
      boundedRows(context, "card_catalog_enrichment_jobs", "status,updated_at"),
      boundedRows(context, "card_discovery_jobs", "status,updated_at"),
      boundedRows(
        context,
        "admin_runtime_controls",
        "control_key,is_paused,reason,updated_at",
      ),
    ]);
  const controls = controlResult.status === "fulfilled"
    ? controlResult.value.map(presentControl).filter((
      item,
    ): item is RuntimeControlDto => item !== null)
    : [];
  const paused = controls.some((control) =>
    control.control_key === "benefit_enrichment_scheduled" && control.is_paused
  );
  return {
    pipelines: [
      benefitResult.status === "fulfilled"
        ? summarize("benefit_enrichment", benefitResult.value, paused)
        : unavailable("benefit_enrichment"),
      discoveryResult.status === "fulfilled"
        ? summarize("card_discovery", discoveryResult.value, false)
        : unavailable("card_discovery"),
    ],
    controls,
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
    failure_category: typeof row.failure_category === "string"
      ? row.failure_category.slice(0, 80)
      : null,
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
  if (body.action === "system-retry" && body.operation == null) {
    operation = "retry";
  } else if (
    body.action === "system-quarantine" &&
    (body.operation == null || body.operation === "quarantine" ||
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
  const { data, error } = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
    _request_id: uuid(body.request_id),
    _lane: "benefit",
    _operation: operation,
    _target_id: uuid(body.target_id),
    _staging_id: null,
    _payload: {},
    _reason: mutationReason,
    _observed_updated_at: timestamp(body.observed_updated_at),
  });
  if (error) throw mapDatabaseError(error);
  const result = record(data);
  return {
    result: {
      job_id: typeof result?.job_id === "string" ? result.job_id : null,
      resulting_status: typeof result?.resulting_status === "string"
        ? result.resulting_status.slice(0, 50)
        : null,
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
  const { data, error } = await context.db.rpc("admin_set_runtime_control", {
    _actor_id: context.actor.id,
    _request_id: uuid(body.request_id),
    _control_key: body.control_key,
    _is_paused: body.is_paused,
    _reason: reason(body.reason),
    _observed_updated_at: timestamp(body.observed_updated_at),
  });
  if (error) throw mapDatabaseError(error);
  const result = presentControl(data);
  if (!result) throw new AdminHttpError("request_failed", 500);
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
