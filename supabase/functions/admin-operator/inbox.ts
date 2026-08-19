import { type AdminActionHandler } from "./access.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

type Severity = "critical" | "high" | "normal";
type CardDestination = Readonly<{
  section: "cardData";
  lane: "identity" | "benefit";
  target_id: string;
}>;
type SystemDestination = Readonly<{
  section: "system";
  control_key: "benefit_enrichment_scheduled";
}>;
type FeedbackDestination = Readonly<
  { section: "feedback"; feedback_id: string }
>;

export type InboxItem = Readonly<{
  id: string;
  type:
    | "card_identity_review"
    | "benefit_enrichment_review"
    | "paused_pipeline"
    | "feedback_review";
  severity: Severity;
  title: string;
  explanation: string;
  source_status: string;
  age_seconds: number;
  destination: CardDestination | SystemDestination | FeedbackDestination;
}>;

type JsonRecord = Record<string, unknown>;

const MAX_SOURCE_ITEMS = 100;
const SCHEDULED_BENEFIT_PARSER_VERSION = "benefits-v5";
const HIGH_BENEFIT_STATUSES = [
  "review_required",
  "failed",
  "quarantined",
] as const;
const ROUTINE_BENEFIT_STATUSES = ["staged"] as const;
const severityOrder: Readonly<Record<Severity, number>> = Object.freeze({
  critical: 0,
  high: 1,
  normal: 2,
});
const benefitPresentation = Object.freeze(
  {
    review_required: {
      severity: "high",
      title: "Review benefit enrichment",
      explanation: "A benefit proposal needs operator review.",
    },
    failed: {
      severity: "high",
      title: "Recover failed benefit enrichment",
      explanation: "Benefit enrichment failed and needs recovery.",
    },
    quarantined: {
      severity: "high",
      title: "Review quarantined benefit enrichment",
      explanation: "A quarantined benefit job needs operator review.",
    },
    staged: {
      severity: "normal",
      title: "Review staged benefits",
      explanation: "A staged benefit proposal is ready for review.",
    },
  } satisfies Record<string, {
    severity: Severity;
    title: string;
    explanation: string;
  }>,
);

function record(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function safeId(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 && value.length <= 100
    ? value
    : null;
}

function safeLabelPart(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value
    .replace(/[\p{Cc}\p{Cf}]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (normalized.length < 2) return null;
  return [...normalized].slice(0, 80).join("");
}

function safeDisplayLabel(
  issuer: unknown,
  product: unknown,
): string | null {
  const safeIssuer = safeLabelPart(issuer);
  const safeProduct = safeLabelPart(product);
  return safeIssuer !== null && safeProduct !== null
    ? `${safeIssuer} — ${safeProduct}`
    : null;
}

function safeAge(value: unknown, nowMs: number): number {
  if (typeof value !== "string" || value.length > 100) return 0;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return 0;
  return Math.max(0, Math.floor((nowMs - timestamp) / 1_000));
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && value.length <= 100 &&
    Number.isFinite(Date.parse(value));
}

function boundedLimit(limit: number): number {
  return Number.isInteger(limit)
    ? Math.max(1, Math.min(MAX_SOURCE_ITEMS, limit))
    : MAX_SOURCE_ITEMS;
}

function sourceFailure(): never {
  throw new Error("source_unavailable");
}

export function rankInboxItems(items: readonly InboxItem[]): InboxItem[] {
  return [...items].sort((left, right) =>
    severityOrder[left.severity] - severityOrder[right.severity] ||
    right.age_seconds - left.age_seconds ||
    left.id.localeCompare(right.id)
  );
}

export async function loadIdentityInbox(
  context: AdminActionContext,
  requestedLimit = MAX_SOURCE_ITEMS,
  nowMs = Date.now(),
): Promise<InboxItem[]> {
  const limit = boundedLimit(requestedLimit);
  const query = (context.db as any).from("card_catalog_review_queue")
    .select("id, status, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .range(0, limit - 1);
  const { data, error } = await query;
  if (error) sourceFailure();

  return (Array.isArray(data) ? data : []).slice(0, limit).flatMap((value) => {
    const row = record(value);
    const targetId = safeId(row?.id);
    if (!row || targetId === null || row.status !== "pending") return [];
    return [{
      id: `card-identity:${targetId}`,
      type: "card_identity_review" as const,
      severity: "normal" as const,
      title: "Review card identity",
      explanation: "A pending card identity proposal needs review.",
      source_status: "pending",
      age_seconds: safeAge(row.created_at, nowMs),
      destination: {
        section: "cardData" as const,
        lane: "identity" as const,
        target_id: targetId,
      },
    }];
  });
}

async function loadBenefitInboxTier(
  context: AdminActionContext,
  statuses: readonly string[],
  requestedLimit: number,
  nowMs: number,
): Promise<InboxItem[]> {
  const limit = boundedLimit(requestedLimit);
  const query = (context.db as any).from("card_catalog_enrichment_jobs")
    .select("id, status, created_at, card_catalog!inner(bank, card_name)")
    .neq("parser_version", "catalog-v1")
    .in("status", statuses)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .range(0, limit - 1);
  const { data, error } = await query;
  if (error) sourceFailure();

  return (Array.isArray(data) ? data : []).slice(0, limit).flatMap((value) => {
    const row = record(value);
    const targetId = safeId(row?.id);
    const status = typeof row?.status === "string" ? row.status : "";
    const presentation = benefitPresentation[
      status as keyof typeof benefitPresentation
    ];
    if (!row || targetId === null || !presentation) return [];
    const catalog = record(row.card_catalog);
    const label = safeDisplayLabel(catalog?.bank, catalog?.card_name);
    const action = status === "failed"
      ? "Recover benefits"
      : status === "quarantined"
      ? "Review quarantined benefits"
      : "Review benefits";
    return [{
      id: `benefit-enrichment:${targetId}`,
      type: "benefit_enrichment_review" as const,
      severity: presentation.severity,
      title: label === null ? action : `${action}: ${label}`,
      explanation: presentation.explanation,
      source_status: status,
      age_seconds: safeAge(row.created_at, nowMs),
      destination: {
        section: "cardData" as const,
        lane: "benefit" as const,
        target_id: targetId,
      },
    }];
  });
}

export async function loadBenefitInbox(
  context: AdminActionContext,
  requestedLimit = MAX_SOURCE_ITEMS,
  nowMs = Date.now(),
): Promise<InboxItem[]> {
  const results = await Promise.all([
    loadBenefitInboxTier(
      context,
      HIGH_BENEFIT_STATUSES,
      requestedLimit,
      nowMs,
    ),
    loadBenefitInboxTier(
      context,
      ROUTINE_BENEFIT_STATUSES,
      requestedLimit,
      nowMs,
    ),
  ]);
  return results.flat();
}

export async function loadSystemInbox(
  context: AdminActionContext,
  nowMs = Date.now(),
): Promise<InboxItem[]> {
  const controlQuery = (context.db as any).from("admin_runtime_controls")
    .select("control_key,is_paused,updated_at")
    .eq("control_key", "benefit_enrichment_scheduled")
    .range(0, 0);
  const eligibleCount = (status: "queued" | "failed") =>
    (context.db as any).from("card_catalog_enrichment_jobs")
      .select("id", { count: "exact", head: true })
      .eq("run_mode", "scheduled")
      .eq("parser_version", SCHEDULED_BENEFIT_PARSER_VERSION)
      .eq("status", status)
      .or(
        `next_retry_at.is.null,next_retry_at.lte.${
          new Date(nowMs).toISOString()
        }`,
      )
      .range(0, 0);
  const [controlResult, queuedResult, failedResult] = await Promise.all([
    controlQuery,
    eligibleCount("queued"),
    eligibleCount("failed"),
  ]);
  if (controlResult.error || queuedResult.error || failedResult.error) {
    sourceFailure();
  }
  if (!Array.isArray(controlResult.data) || controlResult.data.length !== 1) {
    sourceFailure();
  }
  const control = record(controlResult.data[0]);
  const queued = queuedResult.count;
  const failed = failedResult.count;
  if (
    control?.control_key !== "benefit_enrichment_scheduled" ||
    typeof control.is_paused !== "boolean" ||
    !validTimestamp(control.updated_at) ||
    !Number.isSafeInteger(queued) || queued < 0 ||
    !Number.isSafeInteger(failed) || failed < 0 ||
    !Number.isSafeInteger(queued + failed)
  ) sourceFailure();
  const backlog = queued + failed;
  if (!control.is_paused || backlog === 0) return [];

  const displayCount = Math.min(backlog, 999_999);
  const countLabel = `${displayCount.toLocaleString("en-US")}${
    backlog > displayCount ? "+" : ""
  }`;
  const queueNoun = backlog === 1 ? "job is" : "jobs are";
  return [{
    id: "system:benefit_enrichment_scheduled:paused",
    type: "paused_pipeline",
    severity: "critical",
    title: "Scheduled benefit enrichment is paused",
    explanation:
      `${countLabel} queued benefit enrichment ${queueNoun} waiting while scheduled processing is paused.`,
    source_status: "paused",
    age_seconds: safeAge(control.updated_at, nowMs),
    destination: {
      section: "system",
      control_key: "benefit_enrichment_scheduled",
    },
  }];
}

export function feedbackInboxItem(
  value: unknown,
  nowMs = Date.now(),
): InboxItem | null {
  const row = record(value);
  const targetId = safeId(row?.id);
  if (!row || targetId === null || row.review_status !== "pending") return null;
  const triage = record(row.triage_result);
  const severity =
    triage?.severity === "critical" || triage?.severity === "high"
      ? triage.severity
      : "normal";
  const feature = row.feature_key === "statement_processing"
    ? "statement processing"
    : row.feature_key === "card_data"
    ? "card data"
    : row.feature_key === "recommendation"
    ? "recommendation"
    : "AI output";
  return {
    id: `feedback:${targetId}`,
    type: "feedback_review",
    severity,
    title: `Review ${feature} feedback`,
    explanation: "User feedback is waiting for human review.",
    source_status: "pending",
    age_seconds: safeAge(row.created_at, nowMs),
    destination: { section: "feedback", feedback_id: targetId },
  };
}

export async function loadFeedbackInbox(
  context: AdminActionContext,
  requestedLimit = MAX_SOURCE_ITEMS,
  nowMs = Date.now(),
): Promise<InboxItem[]> {
  const limit = boundedLimit(requestedLimit);
  const result = await (context.db as any).from("ai_feedback").select(
    "id,feature_key,triage_status,triage_result,review_status,created_at",
  ).eq("review_status", "pending").order("created_at", { ascending: true })
    .order("id", { ascending: true }).range(0, limit - 1);
  if (result.error || !Array.isArray(result.data)) sourceFailure();
  return result.data.slice(0, limit).map((row: unknown) =>
    feedbackInboxItem(row, nowMs)
  ).filter((item: InboxItem | null): item is InboxItem => item !== null);
}

export async function handleInboxList(
  body: JsonRecord,
  context: AdminActionContext,
) {
  if (Object.keys(body).some((key) => key !== "action")) {
    throw new AdminHttpError("invalid_request", 400);
  }
  const nowMs = Date.now();
  const results = await Promise.allSettled([
    loadIdentityInbox(context, MAX_SOURCE_ITEMS, nowMs),
    loadBenefitInboxTier(
      context,
      HIGH_BENEFIT_STATUSES,
      MAX_SOURCE_ITEMS,
      nowMs,
    ),
    loadBenefitInboxTier(
      context,
      ROUTINE_BENEFIT_STATUSES,
      MAX_SOURCE_ITEMS,
      nowMs,
    ),
    loadSystemInbox(context, nowMs),
    loadFeedbackInbox(context, MAX_SOURCE_ITEMS, nowMs),
  ]);
  const items = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
  return {
    items: rankInboxItems(items).slice(0, MAX_SOURCE_ITEMS),
    partial_failures: [
      ...new Set(
        results.flatMap((result, index) =>
          result.status === "rejected"
            ? [
              index === 0
                ? "card_identity"
                : index < 3
                ? "benefit_enrichment"
                : index === 3
                ? "system_operations"
                : "feedback",
            ]
            : []
        ),
      ),
    ],
    refreshed_at: new Date(nowMs).toISOString(),
  };
}

export const inboxActionHandlers: Readonly<Record<string, AdminActionHandler>> =
  Object.freeze(Object.assign(Object.create(null), {
    "inbox-list": handleInboxList,
  }));
