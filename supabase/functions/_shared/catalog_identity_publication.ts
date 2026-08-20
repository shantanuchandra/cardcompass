import {
  approvedStoredQueryParameters,
  canonicalOfficialRequestUrl,
  type OfficialFetchResult,
} from "./official_issuer_fetch.ts";
import { redactSensitiveUrlsInValue } from "./benefit_source_privacy.ts";

export type CatalogPublicationAction =
  | "resolve_verified"
  | "observe_existing"
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

export type CatalogIdentityReviewStageInput = {
  discoveryJobId?: string | null;
  discoverySource: "statement" | "issuer_crawl";
  userId?: string | null;
  issuer: string;
  proposedProduct?: string | null;
  dedupeKey: string;
  semanticHash: string;
  proposedFields: Record<string, unknown>;
  sourceEvidence: Record<string, unknown>;
  existingCandidates: Array<Record<string, unknown>>;
  validationWarnings: string[];
  confidence: number;
  expectedJobStatus?: string | null;
  expectedJobUpdatedAt?: string | null;
};

export type CatalogIdentityReviewStageResult = {
  jobId: string;
  reviewItemId: string;
  resultingStatus: string;
  created: boolean;
};

export type CatalogLifecycleAction = "mark_discontinued" | "reactivate";
export type CatalogLifecycleObservationAction =
  | CatalogLifecycleAction
  | "observe_current";

export type CatalogLifecycleReviewInput = {
  cardId: string;
  suggestedAction: CatalogLifecycleObservationAction;
  sourceObservation: Record<string, unknown>;
  sourceUrl: string;
  sourceUrlHash: string;
  contentHash?: string | null;
  parserVersion?: string;
};

type CatalogBaselineSource = {
  id: unknown;
  card_name: unknown;
  network: unknown;
  annual_fee: unknown;
  joining_fee: unknown;
  apr: unknown;
  card_url: unknown;
  is_discontinued: unknown;
  updated_at: unknown;
  retrieved_at?: unknown;
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

const REVIEWED_FIELD_ALLOWLIST = new Set([
  "issuer",
  "bank",
  "cardName",
  "card_name",
  "network",
  "aliases",
  "official_url",
  "card_url",
  "submitted_url",
  "final_url",
  "submitted_url_hash",
  "final_url_hash",
  "submitted_resource_identity_hash",
  "final_resource_identity_hash",
  "content_hash",
  "retrieved_at",
  "source_status",
  "source_type",
  "source_observation",
  "confidence",
  "validation_version",
  "card_id",
  "cardId",
  "annual_fee",
  "joining_fee",
  "apr",
  "catalog_baseline",
  "suggested_action",
]);

const RESOURCE_FIELD_KEYS = new Set([
  "official_url",
  "card_url",
  "submitted_url",
  "final_url",
]);

const TRANSPORT_ONLY_OBSERVATION_KEYS = new Set([
  "retrieved_at",
  "attempted_at",
  "observed_at",
  "transport",
  "duration_ms",
  "retry_after_ms",
  "request_started_at",
  "request_completed_at",
  "nonce",
  "footer",
  "generated_at",
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

export function catalogLifecycleSuggestion(input: {
  isDiscontinued: boolean;
  httpStatus: number | null;
  identityValidated: boolean;
  explicitDiscontinuation: boolean;
}): CatalogLifecycleAction | null {
  if (
    input.isDiscontinued && input.httpStatus === 200 &&
    input.identityValidated && !input.explicitDiscontinuation
  ) return "reactivate";
  if (
    !input.isDiscontinued &&
    (input.httpStatus === 410 ||
      (input.httpStatus === 200 && input.identityValidated &&
        input.explicitDiscontinuation))
  ) return "mark_discontinued";
  return null;
}

export function catalogLifecycleObservationAction(input: {
  isDiscontinued: boolean;
  httpStatus: number | null;
  identityValidated: boolean;
  explicitDiscontinuation: boolean;
}): CatalogLifecycleObservationAction | null {
  const mutable = catalogLifecycleSuggestion(input);
  if (mutable) return mutable;
  if (input.httpStatus === 410 && input.isDiscontinued) {
    return "observe_current";
  }
  if (input.httpStatus !== 200 || !input.identityValidated) return null;
  if (input.isDiscontinued === input.explicitDiscontinuation) {
    return "observe_current";
  }
  return null;
}

export function boundedCatalogSourceObservation(
  input: Record<string, unknown>,
): Record<string, unknown> {
  const sanitized = redactSensitiveUrlsInValue(input);
  let remaining = 12_000;
  const bound = (value: unknown, depth: number): unknown => {
    if (remaining <= 0 || depth > 6) return "[truncated]";
    if (
      value === null || typeof value === "boolean" || typeof value === "number"
    ) {
      remaining -= 8;
      return value;
    }
    if (typeof value === "string") {
      const result = value.slice(0, Math.min(512, remaining));
      remaining -= result.length + 2;
      return result;
    }
    if (Array.isArray(value)) {
      return value.slice(0, 32).map((entry) => bound(entry, depth + 1));
    }
    if (typeof value === "object") {
      const output: Record<string, unknown> = {};
      for (const [rawKey, entry] of Object.entries(value).slice(0, 32)) {
        if (remaining <= 0) break;
        const key = rawKey.slice(0, 64);
        remaining -= key.length + 4;
        output[key] = bound(entry, depth + 1);
      }
      return output;
    }
    return String(value).slice(0, 128);
  };
  const output = bound(sanitized, 0) as Record<string, unknown>;
  if (JSON.stringify(output).length <= 16_384) return output;
  return {
    kind: typeof output.kind === "string"
      ? output.kind.slice(0, 128)
      : "observation",
    truncated: true,
  };
}

function stableJsonValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableJsonValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, stableJsonValue(entry)]),
    );
  }
  return value;
}

export async function semanticProductEnvelopeHash(
  input: Record<string, unknown>,
): Promise<string> {
  const stripTransport = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(stripTransport);
    if (value !== null && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .filter(([key]) => !TRANSPORT_ONLY_OBSERVATION_KEYS.has(key))
          .map(([key, entry]) => [key, stripTransport(entry)]),
      );
    }
    return typeof value === "string"
      ? value.trim().replace(/\s+/g, " ")
      : value;
  };
  const bounded = boundedCatalogSourceObservation(input);
  return await sha256(JSON.stringify(stableJsonValue(stripTransport(bounded))));
}

export function semanticCatalogSourceObservation(
  input: Record<string, unknown>,
): Record<string, unknown> {
  const sanitized = boundedCatalogSourceObservation(input);
  const strip = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(strip);
    if (value !== null && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .filter(([key]) => !TRANSPORT_ONLY_OBSERVATION_KEYS.has(key))
          .map(([key, entry]) => [key, strip(entry)]),
      );
    }
    return value;
  };
  return stableJsonValue(strip(sanitized)) as Record<string, unknown>;
}

function observationHistoryKey(entry: Record<string, unknown>): string {
  if (nonEmpty(entry.semantic_hash)) return entry.semantic_hash;
  const semantic = semanticCatalogSourceObservation(entry);
  return JSON.stringify(stableJsonValue(semantic));
}

export function appendCatalogObservationHistory(
  existing: unknown,
  next: Record<string, unknown>,
  limit = 24,
): Array<Record<string, unknown>> {
  const entries = [
    ...(Array.isArray(existing)
      ? existing.filter((entry): entry is Record<string, unknown> =>
        entry !== null && typeof entry === "object" && !Array.isArray(entry)
      )
      : []),
    boundedCatalogSourceObservation(next),
  ];
  const newestByIdentity = new Map<string, Record<string, unknown>>();
  for (const entry of entries) {
    const key = observationHistoryKey(entry);
    const prior = newestByIdentity.get(key);
    const observed = nonEmpty(entry.observed_at)
      ? Date.parse(entry.observed_at)
      : nonEmpty(entry.retrieved_at)
      ? Date.parse(entry.retrieved_at)
      : Number.NEGATIVE_INFINITY;
    const priorObserved = prior && nonEmpty(prior.observed_at)
      ? Date.parse(prior.observed_at)
      : prior && nonEmpty(prior.retrieved_at)
      ? Date.parse(prior.retrieved_at)
      : Number.NEGATIVE_INFINITY;
    if (!prior || observed >= priorObserved) newestByIdentity.set(key, entry);
  }
  return [...newestByIdentity.values()].sort((left, right) => {
    const time = (entry: Record<string, unknown>) =>
      nonEmpty(entry.observed_at)
        ? Date.parse(entry.observed_at)
        : nonEmpty(entry.retrieved_at)
        ? Date.parse(entry.retrieved_at)
        : Number.NEGATIVE_INFINITY;
    return time(right) - time(left) ||
      observationHistoryKey(left).localeCompare(observationHistoryKey(right));
  }).slice(0, Math.max(1, Math.min(24, limit)));
}

function validReviewedResourceUrl(value: string): boolean {
  if (value.length > 2_048) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && Boolean(url.hostname) &&
      !url.username && !url.password && !url.hash &&
      ![...url.searchParams.keys()].some((key) =>
        /(token|session|secret|password|passwd|credential|auth|signature|sig|key|code|state|nonce)/i
          .test(key)
      );
  } catch {
    return false;
  }
}

export function boundedReviewedCatalogFields(
  input: Record<string, unknown>,
): Record<string, unknown> {
  const utf8Length = (value: string) => new TextEncoder().encode(value).length;
  const unknown = Object.keys(input).find((key) =>
    !REVIEWED_FIELD_ALLOWLIST.has(key)
  );
  if (unknown) throw new Error("unknown_reviewed_field");

  const bound = (
    value: unknown,
    depth: number,
    parentKey = "",
  ): unknown => {
    if (depth > 6) throw new Error("reviewed_fields_too_deep");
    if (
      value === null || typeof value === "boolean" || typeof value === "number"
    ) return value;
    if (typeof value === "string") {
      const max = RESOURCE_FIELD_KEYS.has(parentKey) || /_url$/.test(parentKey)
        ? 2_048
        : 512;
      if (utf8Length(value) > max) throw new Error("reviewed_field_too_long");
      if (
        RESOURCE_FIELD_KEYS.has(parentKey) && !validReviewedResourceUrl(value)
      ) {
        throw new Error("unsafe_reviewed_resource");
      }
      return value;
    }
    if (Array.isArray(value)) {
      if (value.length > 32) throw new Error("reviewed_fields_array_too_large");
      return value.map((entry) => bound(entry, depth + 1, parentKey));
    }
    if (typeof value === "object") {
      const entries = Object.entries(value);
      if (entries.length > 32) {
        throw new Error("reviewed_fields_object_too_large");
      }
      const output: Record<string, unknown> = {};
      for (const [key, entry] of entries) {
        if (utf8Length(key) > 64) {
          throw new Error("reviewed_field_key_too_long");
        }
        const sanitizedKey = redactSensitiveUrlsInValue(key);
        if (sanitizedKey !== key) throw new Error("unsafe_reviewed_field_key");
        output[key] = bound(entry, depth + 1, key);
      }
      return output;
    }
    throw new Error("invalid_reviewed_field");
  };
  const bounded = bound(input, 0) as Record<string, unknown>;
  const privacyProbe = { ...bounded };
  for (const key of RESOURCE_FIELD_KEYS) delete privacyProbe[key];
  if (
    JSON.stringify(redactSensitiveUrlsInValue(privacyProbe)) !==
      JSON.stringify(privacyProbe)
  ) throw new Error("unsafe_reviewed_resource");
  const sanitized = redactSensitiveUrlsInValue(bounded) as Record<
    string,
    unknown
  >;
  for (const key of RESOURCE_FIELD_KEYS) {
    if (typeof bounded[key] === "string") sanitized[key] = bounded[key];
  }
  if (new TextEncoder().encode(JSON.stringify(sanitized)).length > 16_384) {
    throw new Error("reviewed_fields_too_large");
  }
  return sanitized;
}

export function catalogPublicationBaseline(
  card: CatalogBaselineSource,
): Record<string, unknown> {
  if (
    !nonEmpty(card.id) || !nonEmpty(card.card_name) ||
    (card.updated_at !== null &&
      (!nonEmpty(card.updated_at) ||
        !Number.isFinite(Date.parse(card.updated_at))))
  ) throw new Error("invalid_catalog_baseline");
  const retrievedAt =
    card.retrieved_at === undefined || card.retrieved_at === null
      ? null
      : nonEmpty(card.retrieved_at) &&
          Number.isFinite(Date.parse(card.retrieved_at))
      ? card.retrieved_at
      : (() => {
        throw new Error("invalid_catalog_baseline");
      })();
  const baseline: Record<string, unknown> = {
    card_id: card.id,
    card_name: card.card_name,
    network: card.network ?? null,
    annual_fee: card.annual_fee ?? null,
    joining_fee: card.joining_fee ?? null,
    apr: card.apr ?? null,
    card_url: card.card_url ?? null,
    is_discontinued: card.is_discontinued === true,
    updated_at: card.updated_at ?? null,
  };
  if (card.updated_at === null && retrievedAt !== null) {
    baseline.version_observed_at = retrievedAt;
  }
  return baseline;
}

export function hasStrongExplicitCardDiscontinuation(text: string): boolean {
  return /\b(?:this\s+)?(?:credit\s+)?card\s+(?:has\s+been\s+|is\s+)(?:discontinued|withdrawn)\b|\b(?:this\s+)?(?:credit\s+)?card\s+is\s+no\s+longer\s+(?:available|issued)\b/i
    .test(text.slice(0, 120_000));
}

export function cardDiscontinuationEvidence(
  html: string,
  issuer: string,
  cardName: string,
): { explicit: boolean; matchedExcerpt: string | null } {
  const clean = (value: string) =>
    redactSensitiveUrlsInValue(
      value.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
        .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
        .replace(/<[^>]+>/g, " ")
        .replace(/&(?:nbsp|amp);/gi, " ")
        .replace(/\s+/g, " ")
        .trim(),
    ) as string;
  const meaningful = (value: string) =>
    value.toLowerCase().split(/[^a-z0-9]+/).filter((token) =>
      token.length > 1 && !new Set([
        "bank",
        "credit",
        "card",
        "cards",
        "the",
        "and",
        "with",
      ]).has(token)
    );
  const targetTokens = meaningful(cardName);
  if (targetTokens.length === 0) {
    return { explicit: false, matchedExcerpt: null };
  }
  const boundedHtml = html.slice(0, 120_000).replace(
    /<script\b[^>]*>[\s\S]*?<\/script>|<style\b[^>]*>[\s\S]*?<\/style>/gi,
    " ",
  );
  const containsTarget = (value: string) => {
    const tokens = new Set(meaningful(value));
    return targetTokens.every((token) => tokens.has(token));
  };
  const boundedExcerpt = (value: string) => clean(value).slice(0, 512);
  const structuredStatus =
    /\b(?:status\s*:?\s*)?(?:discontinued|withdrawn|no\s+longer\s+(?:available|issued))\b/i;

  const headings = [...boundedHtml.matchAll(
    /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi,
  )].map((match) => ({
    start: match.index ?? 0,
    end: (match.index ?? 0) + match[0].length,
    level: Number(match[1]),
    text: clean(match[2] ?? ""),
  }));
  const sectionHeadingTokens = new Set([
    "about",
    "access",
    "annual",
    "application",
    "apply",
    "apr",
    "availability",
    "benefit",
    "benefits",
    "charge",
    "charges",
    "contact",
    "details",
    "document",
    "documents",
    "eligibility",
    "faq",
    "feature",
    "features",
    "fee",
    "fees",
    "frequently",
    "how",
    "important",
    "information",
    "interest",
    "joining",
    "key",
    "lounge",
    "milestone",
    "offer",
    "offers",
    "overview",
    "points",
    "pricing",
    "product",
    "question",
    "questions",
    "rate",
    "rates",
    "reward",
    "rewards",
    "status",
    "term",
    "terms",
    "update",
    "notice",
    "discontinuation",
    "welcome",
  ]);
  const issuerTokens = new Set(meaningful(issuer));
  const normalSectionHeading = (value: string) => {
    const tokens = meaningful(value).filter((token) =>
      !issuerTokens.has(token)
    );
    return tokens.length === 0 ||
      tokens.every((token) => sectionHeadingTokens.has(token));
  };
  const productHeading = (value: string) => {
    if (containsTarget(value) || normalSectionHeading(value)) return false;
    if (/\b(?:credit\s+)?card\b/i.test(value)) return true;
    const tokens = meaningful(value);
    const hasIssuerIdentity = tokens.some((token) => issuerTokens.has(token));
    const distinctive = tokens.filter((token) =>
      !issuerTokens.has(token) && !sectionHeadingTokens.has(token)
    );
    return distinctive.length > 0 &&
      (hasIssuerIdentity || (tokens.length <= 6 && value.length <= 96));
  };
  const lifecycleBindingTokens = new Set([
    ...sectionHeadingTokens,
    "and",
    "april",
    "august",
    "available",
    "been",
    "december",
    "discontinued",
    "due",
    "effective",
    "february",
    "from",
    "has",
    "immediate",
    "immediately",
    "is",
    "issued",
    "january",
    "july",
    "june",
    "longer",
    "march",
    "may",
    "no",
    "not",
    "november",
    "october",
    "of",
    "on",
    "portfolio",
    "review",
    "september",
    "the",
    "this",
    "to",
    "withdrawn",
  ]);
  const targetStrongIdentity = targetTokens.filter((token) =>
    !issuerTokens.has(token)
  );
  const hasForeignExplicitCardSubject = (value: string) => {
    const subjects = [...value.matchAll(
      /(?:^|[,:;.!?\u2013\u2014-]\s*)((?:[a-z0-9&+'\u2019.-]+\s+){1,16}(?:credit\s+)?card)\b/gi,
    )].map((match) => match[1] ?? "");
    return subjects.some((subject) => {
      const identity = meaningful(subject).filter((token) =>
        token !== "this" && !issuerTokens.has(token)
      );
      if (identity.length === 0) return false;
      return identity.length !== targetStrongIdentity.length ||
        identity.some((token) => !targetStrongIdentity.includes(token));
    });
  };
  const hasCompetingProductIdentity = (value: string) => {
    if (hasForeignExplicitCardSubject(value)) return true;
    const remaining = meaningful(value).filter((token) =>
      !targetTokens.includes(token) && !issuerTokens.has(token) &&
      !lifecycleBindingTokens.has(token) && !/^\d{1,4}$/.test(token)
    );
    return remaining.length > 0;
  };
  const competingContext = (value: string) =>
    /\b(?:alternative|compare|comparison|related|successor|replacement|replaces?|replaced|versus|vs\.?)\b/i
      .test(value);

  // A table row is accepted only when one product cell owns the status. A
  // comparison row that contains another distinctive identity is ambiguous.
  for (const row of boundedHtml.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const rowHtml = row[1] ?? "";
    const rowText = clean(rowHtml);
    const cells = [...rowHtml.matchAll(
      /<(?:td|th)\b[^>]*>([\s\S]*?)<\/(?:td|th)>/gi,
    )].map((cell) => clean(cell[1] ?? "")).filter(Boolean);
    const competingCell = cells.some((cell) =>
      !containsTarget(cell) && !structuredStatus.test(cell) &&
      productHeading(cell)
    );
    if (
      containsTarget(rowText) && structuredStatus.test(rowText) &&
      !competingCell && !hasCompetingProductIdentity(rowText) &&
      !competingContext(rowText) &&
      !/\bnot\s+(?:discontinued|withdrawn)\b/i.test(rowText)
    ) {
      return { explicit: true, matchedExcerpt: boundedExcerpt(rowText) };
    }
  }
  const anaphoric =
    /\b(?:this|the)\s+(?:credit\s+)?card\s+(?:has\s+been\s+|is\s+)(?:discontinued|withdrawn)\b|\b(?:this|the)\s+(?:credit\s+)?card\s+is\s+no\s+longer\s+(?:available|issued)\b/i;
  const targetPhrase = meaningful(cardName).join("[\\s\\W_]*");
  const direct = targetPhrase
    ? new RegExp(
      `\\b${targetPhrase}\\b(?:[\\s\\W_]*(?:credit[\\s\\W_]*)?card)?[\\s\\W_]*(?:has[\\s\\W_]*been|is)[\\s\\W_]*(?:discontinued|withdrawn|no[\\s\\W_]*longer[\\s\\W_]*(?:available|issued))\\b`,
      "i",
    )
    : null;
  const boundedSentences = (value: string): string[] => {
    const withBoundaries = value
      .replace(
        /<\/?(?:article|aside|br|div|li|p|section|td|th|tr)\b[^>]*>/gi,
        "\n",
      )
      .replace(/<[^>]+>/g, " ")
      .replace(/&(?:nbsp|amp);/gi, " ");
    return (withBoundaries.match(/[^.!?\n]+[.!?]?/g) ?? [])
      .map((sentence) => clean(sentence))
      .filter(Boolean)
      .slice(0, 256);
  };
  const exactTargetSentence = (value: string): string | null => {
    if (!direct) return null;
    for (const sentence of boundedSentences(value)) {
      const match = direct.exec(sentence);
      if (!match) continue;
      const remainder = `${sentence.slice(0, match.index)} ${
        sentence.slice(match.index + match[0].length)
      }`.replace(
        new RegExp(
          `\\b${meaningful(issuer).join("[\\s\\W_]*")}\\b`,
          "ig",
        ),
        " ",
      );
      if (
        /\b(?:alternative|compare|comparison|instead|other|related|replacement|replaces?|successor|versus|vs\.?|while|whereas)\b/i
          .test(remainder) ||
        /\b(?:credit\s+)?card\b/i.test(remainder) ||
        hasCompetingProductIdentity(remainder)
      ) continue;
      return sentence;
    }
    return null;
  };

  for (let index = 0; index < headings.length; index += 1) {
    const heading = headings[index];
    if (!containsTarget(heading.text)) continue;
    const sibling = headings.slice(index + 1).find((candidate) =>
      productHeading(candidate.text) && !containsTarget(candidate.text)
    );
    const remainder = boundedHtml.slice(heading.end, heading.end + 12_000);
    const structuralBoundary =
      /<(?:table\b|(?:div|section|article)\b[^>]*(?:class|data-component)\s*=\s*["'][^"']*(?:product[-_ ]?card|card[-_ ]?product|product[-_ ]?tile)[^"']*["'])/i
        .exec(remainder);
    const scopeEnd = Math.min(
      sibling?.start ?? boundedHtml.length,
      structuralBoundary?.index === undefined
        ? boundedHtml.length
        : heading.end + structuralBoundary.index,
      heading.end + 12_000,
    );
    const rawScope = boundedHtml.slice(heading.end, scopeEnd);
    const scoped = clean(rawScope).slice(0, 2_000);
    const directSentence = exactTargetSentence(rawScope);
    if (directSentence) {
      return {
        explicit: true,
        matchedExcerpt: boundedExcerpt(`${heading.text} ${directSentence}`),
      };
    }
    const neutralStatusSentence = boundedSentences(rawScope).find((value) =>
      structuredStatus.test(value) &&
      !/\b(?:this|the)\s+(?:credit\s+)?card\b/i.test(value) &&
      !hasCompetingProductIdentity(value) &&
      !competingContext(value) &&
      !/\bnot\s+(?:discontinued|withdrawn)\b/i.test(value)
    );
    if (neutralStatusSentence) {
      return {
        explicit: true,
        matchedExcerpt: boundedExcerpt(
          `${heading.text} ${neutralStatusSentence}`,
        ),
      };
    }
    const statusElement = [...rawScope.matchAll(
      /<(?:div|span|p|td)\b[^>]*(?:class|data-status|aria-label)\s*=\s*["'][^"']*(?:status|availability)[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|span|p|td)>/gi,
    )].map((match) => clean(match[1] ?? "")).find((value) =>
      structuredStatus.test(value) &&
      !hasCompetingProductIdentity(value) &&
      !/\bnot\s+(?:discontinued|withdrawn)\b/i.test(value)
    );
    if (statusElement) {
      return {
        explicit: true,
        matchedExcerpt: boundedExcerpt(`${heading.text} ${statusElement}`),
      };
    }
    const anaphoricMatch = anaphoric.exec(scoped);
    if (anaphoricMatch) {
      const prior = scoped.slice(0, anaphoricMatch.index);
      const immediatePrior = boundedSentences(prior).at(-1) ?? "";
      const refersToOtherProduct = competingContext(prior) ||
        hasCompetingProductIdentity(immediatePrior);
      if (!refersToOtherProduct) {
        return {
          explicit: true,
          matchedExcerpt: boundedExcerpt(
            `${heading.text} ${anaphoricMatch[0]}`,
          ),
        };
      }
    }
  }
  if (headings.length === 0) {
    const sentence = exactTargetSentence(boundedHtml);
    if (sentence) {
      return { explicit: true, matchedExcerpt: boundedExcerpt(sentence) };
    }
  }
  return { explicit: false, matchedExcerpt: null };
}

export async function stageCatalogIdentityReview(
  db: PublicationClient,
  input: CatalogIdentityReviewStageInput,
): Promise<CatalogIdentityReviewStageResult> {
  if (
    !["statement", "issuer_crawl"].includes(input.discoverySource) ||
    !nonEmpty(input.issuer) || !nonEmpty(input.dedupeKey) ||
    !/^[0-9a-f]{64}$/i.test(input.semanticHash) ||
    !input.proposedFields || Array.isArray(input.proposedFields) ||
    !input.sourceEvidence || Array.isArray(input.sourceEvidence) ||
    !Array.isArray(input.existingCandidates) ||
    !Array.isArray(input.validationWarnings) ||
    !Number.isFinite(input.confidence) || input.confidence < 0 ||
    input.confidence > 1
  ) throw new Error("invalid_catalog_review_stage");
  const proposedFields = boundedReviewedCatalogFields(input.proposedFields);
  const sourceEvidence = boundedCatalogSourceObservation(input.sourceEvidence);
  const existingCandidates = boundedCatalogSourceObservation({
    candidates: input.existingCandidates,
  }).candidates;
  if (!Array.isArray(existingCandidates)) {
    throw new Error("invalid_catalog_review_stage");
  }
  const { data, error } = await db.rpc("stage_card_catalog_identity_review", {
    _discovery_job_id: input.discoveryJobId ?? null,
    _discovery_source: input.discoverySource,
    _user_id: input.userId ?? null,
    _issuer: input.issuer.trim(),
    _proposed_product: input.proposedProduct?.trim() || null,
    _dedupe_key: input.dedupeKey,
    _semantic_hash: input.semanticHash.toLowerCase(),
    _proposed_fields: proposedFields,
    _source_evidence: sourceEvidence,
    _existing_candidates: existingCandidates,
    _validation_warnings: input.validationWarnings.slice(0, 32),
    _confidence: input.confidence,
    _expected_job_status: input.expectedJobStatus ?? null,
    _expected_job_updated_at: input.expectedJobUpdatedAt ?? null,
  });
  if (error) throw error;
  if (!Array.isArray(data) || data.length !== 1) {
    throw new Error("invalid_catalog_review_stage_outcome");
  }
  const row = data[0] as Record<string, unknown>;
  if (
    !nonEmpty(row.job_id) || !nonEmpty(row.review_item_id) ||
    !nonEmpty(row.resulting_status) || typeof row.created !== "boolean"
  ) throw new Error("invalid_catalog_review_stage_outcome");
  return {
    jobId: row.job_id,
    reviewItemId: row.review_item_id,
    resultingStatus: row.resulting_status,
    created: row.created,
  };
}

export async function proposeCatalogLifecycleReview(
  db: PublicationClient,
  input: CatalogLifecycleReviewInput,
): Promise<string> {
  const parserVersion = input.parserVersion?.trim() || "benefits-v6";
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(input.cardId) ||
    !["mark_discontinued", "reactivate", "observe_current"].includes(
      input.suggestedAction,
    ) ||
    !input.sourceObservation || Array.isArray(input.sourceObservation) ||
    typeof input.sourceObservation !== "object" ||
    !nonEmpty(input.sourceUrl) ||
    !/^[0-9a-f]{64}$/i.test(input.sourceUrlHash) ||
    (input.contentHash !== undefined && input.contentHash !== null &&
      !/^[0-9a-f]{64}$/i.test(input.contentHash)) ||
    parserVersion !== "benefits-v6"
  ) throw new Error("invalid_catalog_lifecycle_review");

  const { data, error } = await db.rpc("stage_card_catalog_lifecycle_review", {
    _card_id: input.cardId,
    _suggested_action: input.suggestedAction,
    _source_observation: boundedCatalogSourceObservation(
      input.sourceObservation,
    ),
    _source_url: input.sourceUrl,
    _source_url_hash: input.sourceUrlHash.toLowerCase(),
    _content_hash: input.contentHash?.toLowerCase() ?? null,
    _parser_version: parserVersion,
  });
  if (error) throw error;
  if (
    typeof data !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(data)
  ) throw new Error("invalid_catalog_lifecycle_review_outcome");
  return data;
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
  } else if (input.action === "observe_existing") {
    const sourceObservation = input.reviewedFields.source_observation;
    if (
      input.reviewItemId || input.actorId ||
      !nonEmpty(input.reviewedFields.card_id) ||
      !sourceObservation || typeof sourceObservation !== "object" ||
      Array.isArray(sourceObservation) ||
      input.reviewedFields.source_type !== "official_html" ||
      (sourceObservation as Record<string, unknown>).identity_validated !==
        true ||
      (sourceObservation as Record<string, unknown>).source_status !== 200
    ) throw new Error("invalid_existing_observation_authority");
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
    ["retry", "reject", "mark_discontinued", "reactivate"].includes(
      input.action,
    ) &&
    !nonEmpty(input.reason)
  ) throw new Error("reason_required");
  // Reviewed immutable evidence is reconstructed from the locked review row
  // by SQL. The caller may only send edit_approve catalog-field overrides.
  const parserVersion = input.parserVersion?.trim() || "benefits-v6";
  if (parserVersion !== "benefits-v6") {
    throw new Error("invalid_publication_parser");
  }

  const reviewedFields = boundedReviewedCatalogFields(input.reviewedFields);
  const { data, error } = await db.rpc("publish_card_catalog_identity", {
    _discovery_job_id: input.discoveryJobId,
    _review_item_id: input.reviewItemId ?? null,
    _actor_id: input.actorId ?? null,
    _action: input.action,
    _reviewed_fields: reviewedFields,
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
  const mayOmitCard = ["queued", "review_required", "rejected"].includes(
    row.resulting_status,
  );
  if (!mayOmitCard && !nonEmpty(row.card_id)) {
    throw new Error("invalid_catalog_publication_outcome");
  }
  return {
    cardId: nonEmpty(row.card_id) ? row.card_id : null,
    jobId: row.job_id,
    resultingStatus: row.resulting_status,
  };
}
