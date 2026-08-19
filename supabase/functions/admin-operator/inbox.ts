import { type AdminActionHandler } from "./access.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

type Severity = "critical" | "high" | "normal";
type Lane = "identity" | "benefit";

export type InboxItem = Readonly<{
  id: string;
  type: "card_identity_review" | "benefit_enrichment_review";
  severity: Severity;
  title: string;
  explanation: string;
  source_status: string;
  age_seconds: number;
  destination: Readonly<{
    section: "cardData";
    lane: Lane;
    target_id: string;
  }>;
}>;

type JsonRecord = Record<string, unknown>;

const MAX_SOURCE_ITEMS = 100;
const severityOrder: Readonly<Record<Severity, number>> = Object.freeze({
  critical: 0,
  high: 1,
  normal: 2,
});
const benefitPresentation = Object.freeze({
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
}>);

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

function safeAge(value: unknown, nowMs: number): number {
  if (typeof value !== "string" || value.length > 100) return 0;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return 0;
  return Math.max(0, Math.floor((nowMs - timestamp) / 1_000));
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
      title: "Review card identity proposal",
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

export async function loadBenefitInbox(
  context: AdminActionContext,
  requestedLimit = MAX_SOURCE_ITEMS,
  nowMs = Date.now(),
): Promise<InboxItem[]> {
  const limit = boundedLimit(requestedLimit);
  const query = (context.db as any).from("card_catalog_enrichment_jobs")
    .select("id, status, created_at")
    .neq("parser_version", "catalog-v1")
    .in("status", Object.keys(benefitPresentation))
    .order("created_at", { ascending: true })
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
    return [{
      id: `benefit-enrichment:${targetId}`,
      type: "benefit_enrichment_review" as const,
      severity: presentation.severity,
      title: presentation.title,
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
    loadBenefitInbox(context, MAX_SOURCE_ITEMS, nowMs),
  ]);
  const items = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
  return {
    items: rankInboxItems(items).slice(0, MAX_SOURCE_ITEMS),
    partial_failures: results.flatMap((result, index) =>
      result.status === "rejected"
        ? [index === 0 ? "card_identity" : "benefit_enrichment"]
        : []
    ),
    refreshed_at: new Date(nowMs).toISOString(),
  };
}

export const inboxActionHandlers: Readonly<Record<string, AdminActionHandler>> =
  Object.freeze(Object.assign(Object.create(null), {
    "inbox-list": handleInboxList,
  }));
