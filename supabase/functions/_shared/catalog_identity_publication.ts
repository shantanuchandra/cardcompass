import {
  approvedStoredQueryParameters,
  canonicalOfficialRequestUrl,
  type OfficialFetchResult,
} from "./official_issuer_fetch.ts";

export type CatalogPublicationAction =
  | "resolve_verified"
  | "approve"
  | "edit_approve"
  | "merge"
  | "retry"
  | "reject"
  | "mark_discontinued"
  | "reactivate";

export type ReviewedCatalogPublication = {
  discoveryJobId: string;
  reviewItemId?: string | null;
  actorId?: string | null;
  action: CatalogPublicationAction;
  reviewedFields: Record<string, unknown>;
  mergeCardId?: string | null;
  reason?: string | null;
  parserVersion?: string;
};

export type CatalogPublicationResult = {
  cardId: string | null;
  jobId: string;
  resultingStatus: string;
};

type PublicationClient = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data?: unknown; error: unknown }>;
};

const REVIEWED_ACTIONS = new Set<CatalogPublicationAction>([
  "approve",
  "edit_approve",
  "merge",
  "retry",
  "reject",
  "mark_discontinued",
  "reactivate",
]);

function nonEmpty(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Uses the exact Task 5 fetch URL contract. Approved functional query bytes,
 * including ordering and duplicates, are part of identity; tracking and the
 * fragment are not.
 */
export async function canonicalPublicationResource(
  issuer: string,
  rawUrl: string,
): Promise<{ canonicalUrl: string; urlHash: string }> {
  const allowed = approvedStoredQueryParameters(rawUrl);
  const parsed = new URL(rawUrl.trim());
  const nonTrackingCount =
    [...parsed.searchParams.keys()].filter((key) =>
      !/^utm_/i.test(key) && !["gclid", "fbclid"].includes(key.toLowerCase())
    ).length;
  if (nonTrackingCount > 0 && allowed.length === 0) {
    throw new Error("unapproved_query");
  }
  const canonicalUrl = canonicalOfficialRequestUrl(issuer, rawUrl, allowed);
  return { canonicalUrl, urlHash: await sha256(canonicalUrl) };
}

export function publicationFieldsFromFetch(
  fetchResult: Pick<
    OfficialFetchResult,
    | "submittedUrl"
    | "finalUrl"
    | "submittedResourceUrl"
    | "finalResourceUrl"
    | "sourceIdentityHash"
    | "finalResourceIdentityHash"
    | "contentHash"
    | "retrievedAt"
    | "status"
  >,
): Record<string, unknown> {
  const hash = (value: unknown, field: string): string => {
    if (typeof value !== "string" || !/^[0-9a-f]{64}$/i.test(value)) {
      throw new Error(`invalid_${field}`);
    }
    return value.toLowerCase();
  };
  const submittedUrl = fetchResult.submittedResourceUrl ??
    fetchResult.submittedUrl;
  const finalUrl = fetchResult.finalResourceUrl ?? fetchResult.finalUrl;
  if (!nonEmpty(submittedUrl) || !nonEmpty(finalUrl)) {
    throw new Error("invalid_source_url");
  }
  if (
    !nonEmpty(fetchResult.retrievedAt) || !Number.isInteger(fetchResult.status)
  ) {
    throw new Error("invalid_source_observation");
  }
  return {
    submitted_url: submittedUrl,
    final_url: finalUrl,
    submitted_url_hash: hash(
      fetchResult.sourceIdentityHash,
      "submitted_url_hash",
    ),
    final_url_hash: hash(
      fetchResult.finalResourceIdentityHash,
      "final_url_hash",
    ),
    content_hash: hash(fetchResult.contentHash, "content_hash"),
    retrieved_at: fetchResult.retrievedAt,
    source_status: fetchResult.status,
  };
}

export async function publishReviewedCardIdentity(
  db: PublicationClient,
  input: ReviewedCatalogPublication,
): Promise<CatalogPublicationResult> {
  if (
    !nonEmpty(input.discoveryJobId) || !input.reviewedFields ||
    Array.isArray(input.reviewedFields)
  ) {
    throw new Error("invalid_catalog_publication");
  }
  if (input.action === "resolve_verified") {
    if (input.reviewItemId || input.actorId) {
      throw new Error("invalid_verified_source_authority");
    }
  } else if (
    !REVIEWED_ACTIONS.has(input.action) || !nonEmpty(input.reviewItemId) ||
    !nonEmpty(input.actorId)
  ) {
    throw new Error("review_actor_required");
  }
  if (input.action === "merge" && !nonEmpty(input.mergeCardId)) {
    throw new Error("merge_target_required");
  }
  if (
    ["reject", "mark_discontinued", "reactivate"].includes(input.action) &&
    !nonEmpty(input.reason)
  ) throw new Error("reason_required");
  if (
    ["mark_discontinued", "reactivate"].includes(input.action) &&
    (!input.reviewedFields.source_observation ||
      typeof input.reviewedFields.source_observation !== "object")
  ) throw new Error("source_observation_required");
  const parserVersion = input.parserVersion?.trim() || "benefits-v6";
  if (parserVersion !== "benefits-v6") {
    throw new Error("invalid_publication_parser");
  }

  const { data, error } = await db.rpc("publish_card_catalog_identity", {
    _discovery_job_id: input.discoveryJobId,
    _review_item_id: input.reviewItemId ?? null,
    _actor_id: input.actorId ?? null,
    _action: input.action,
    _reviewed_fields: input.reviewedFields,
    _merge_card_id: input.mergeCardId ?? null,
    _reason: input.reason ?? null,
    _parser_version: parserVersion,
  });
  if (error) throw error;
  if (!Array.isArray(data) || data.length !== 1) {
    throw new Error("invalid_catalog_publication_outcome");
  }
  const row = data[0] as Record<string, unknown>;
  if (!nonEmpty(row.job_id) || !nonEmpty(row.resulting_status)) {
    throw new Error("invalid_catalog_publication_outcome");
  }
  const mayOmitCard = ["queued", "rejected"].includes(row.resulting_status);
  if (!mayOmitCard && !nonEmpty(row.card_id)) {
    throw new Error("invalid_catalog_publication_outcome");
  }
  return {
    cardId: nonEmpty(row.card_id) ? row.card_id : null,
    jobId: row.job_id,
    resultingStatus: row.resulting_status,
  };
}
