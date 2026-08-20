import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @deno-types="data:application/typescript,export%20declare%20function%20createClient(...args%3A%20any%5B%5D)%3A%20any%3B"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?bundle&target=deno&no-dts";
import {
  type BenefitComparisonProposal,
  type BenefitDiff,
  currentBenefitProposal,
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
} from "../_shared/benefit_enrichment.ts";
export { currentBenefitProposal } from "../_shared/benefit_enrichment.ts";
import { cardScopedBenefitKey } from "../_shared/benefit_contract.ts";
import { safeHttpsDisplayUrl } from "../_shared/benefit_source_privacy.ts";
import {
  allowedOfficialUrl,
  canonicalOfficialUrl,
  normalizedProduct,
} from "../_shared/card_discovery.ts";
import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
  type IssuerCandidateOutcome,
  issuerDiscoveryFallbackUrls,
  persistCrawlerCandidate,
  stageCompleteIssuerDirectoryAbsenceReviews,
} from "../_shared/issuer_card_crawl.ts";
import {
  cardDiscontinuationEvidence,
  catalogLifecycleObservationAction,
  proposeCatalogLifecycleReview,
  stageCatalogIdentityReview,
} from "../_shared/catalog_identity_publication.ts";
import {
  approvedStoredQueryParameters,
  createOfficialRobotsCache,
  fetchOfficialIssuerObservation,
  type OfficialFetchAttempt,
  type OfficialFetchObservation,
  type OfficialFetchResult,
} from "../_shared/official_issuer_fetch.ts";
import {
  assertBenefitParserVersion,
  type BenefitEnrichmentQueueInput,
  enqueueBenefitEnrichmentJobs,
  evaluatePilotGate,
  failureDisposition,
  LEASE_SECONDS,
  MAX_PILOT_REVIEW_COUNT,
  type PilotCandidate,
  type PilotJob,
  type RunMode,
  runSequentially,
  safeFailureCategory,
  secureSecretEqual,
  selectPilotCandidates,
} from "./batch_policy.ts";
import { collectSupportingBenefitDocuments } from "./supporting_documents.ts";
import {
  assessCrawlCompleteness,
  boundedSourceUrl,
  compactSourceAttempts,
  MAX_EVIDENCE_CLOCK_SKEW_MS,
  retirementEligibility,
  sanitizedSourceErrorCode,
  type SourceAttempt,
  type SourceAttemptInput,
  utcInstant,
} from "./crawl_policy.ts";

type UntypedSupabaseClient = any;

type EnrichmentJob = {
  id: string;
  card_id: string;
  issuer: string;
  canonical_url: string;
  parser_version: string;
  attempt_count: number;
  run_mode: RunMode;
  lease_token: string;
  staging_id?: string | null;
  result_summary?: Record<string, unknown> | null;
};

type JobOutcome =
  | "staged"
  | "completed"
  | "quarantined"
  | "failed"
  | "review_required";

type ProcessResult = {
  outcome: JobOutcome;
  retried: boolean;
};

export const CURRENT_BENEFIT_PARSER_VERSION = "benefits-v6";
const INVOCATION_DEADLINE_MS = 180_000;
const ISSUER_DISCOVERY_LEASE_MS = 300_000;
const ISSUER_DISCOVERY_BACKLOG_PAGE_SIZE = 100;
const ISSUER_DISCOVERY_BACKLOG_MAX_PAGES = 10;
const ISSUER_DISCOVERY_MAX_ATTEMPTS = 5;
const ISSUER_DISCOVERY_QUARANTINE_BATCH = 20;

export function claimLimitForInvocation(_runMode: RunMode): 1 {
  return 1;
}

export function networkWorkMayStart(
  invocationStartedAt: number,
  now = Date.now(),
): boolean {
  return now - invocationStartedAt < INVOCATION_DEADLINE_MS;
}

export function refreshEligibleCard(input: {
  isDiscontinued: boolean;
  hasActiveCardholder: boolean;
}): boolean {
  return !input.isDiscontinued || input.hasActiveCardholder;
}

export async function requeueDueJobs(
  db: UntypedSupabaseClient,
  now = new Date(),
  limit = 1,
): Promise<number> {
  if (
    !Number.isInteger(limit) || limit < 1 || limit > 200 ||
    !Number.isFinite(now.getTime())
  ) {
    throw new Error("invalid_requeue_request");
  }
  const { data, error } = await db.rpc(
    "requeue_due_card_catalog_enrichment_jobs",
    {
      _parser_version: CURRENT_BENEFIT_PARSER_VERSION,
      _limit: limit,
      _now: now.toISOString(),
    },
  );
  if (error) throw error;
  return Array.isArray(data) ? data.length : 0;
}

export function sourceObservationSummary(input: {
  parserVersion: string;
  requestedUrl?: string;
  disposition: OfficialFetchObservation["disposition"];
  reviewReason?: string;
  crawlComplete: boolean;
  result?: OfficialFetchResult;
  attempts: OfficialFetchAttempt[];
}): Record<string, unknown> {
  const result = input.result;
  const terminalAttempt = input.attempts.at(-1);
  const requestedDisplay = input.requestedUrl
    ? boundedSourceUrl(input.requestedUrl)
    : undefined;
  const bounded = (value: string | undefined, maximum: number) =>
    value?.trim().slice(0, maximum) || undefined;
  return {
    parser_version: input.parserVersion.slice(0, 64),
    terminal_disposition: input.disposition,
    ...(input.reviewReason
      ? { review_reason: input.reviewReason.slice(0, 64) }
      : {}),
    crawl_complete: input.crawlComplete,
    http_status: result?.status ?? terminalAttempt?.status ?? null,
    ...(requestedDisplay
      ? {
        submitted_url: requestedDisplay,
        final_url: requestedDisplay,
        canonical_url: requestedDisplay,
      }
      : {}),
    ...(result
      ? {
        submitted_url: boundedSourceUrl(result.submittedUrl),
        final_url: boundedSourceUrl(result.finalUrl),
        canonical_url: boundedSourceUrl(result.canonicalUrl),
        retrieved_at: result.retrievedAt,
        not_modified: result.notModified,
        ...(bounded(result.etag, 512)
          ? { etag: bounded(result.etag, 512) }
          : {}),
        ...(bounded(result.lastModified, 512)
          ? { last_modified: bounded(result.lastModified, 512) }
          : {}),
        ...(bounded(result.contentHash, 128)
          ? { content_hash: bounded(result.contentHash, 128) }
          : {}),
        ...(/^[0-9a-f]{64}$/i.test(result.sourceIdentityHash ?? "")
          ? {
            submitted_identity_hash: result.sourceIdentityHash!.toLowerCase(),
          }
          : {}),
        ...(/^[0-9a-f]{64}$/i.test(result.finalResourceIdentityHash ?? "")
          ? {
            final_resource_url: boundedSourceUrl(result.finalUrl),
            final_resource_identity_hash: result.finalResourceIdentityHash!
              .toLowerCase(),
          }
          : {}),
        card_identity_validated: input.disposition === "not_modified",
      }
      : {}),
    attempts: input.attempts.slice(-6).map((attempt) => ({
      ...(attempt.status ? { status: attempt.status } : {}),
      ...(attempt.code ? { code: attempt.code.slice(0, 64) } : {}),
      attempted_at: attempt.attemptedAt,
      ...(attempt.retryAfterMs !== undefined
        ? {
          retry_after_ms: Math.min(120_000, Math.max(0, attempt.retryAfterMs)),
        }
        : {}),
    })),
  };
}

export function sourceObservationReviewSummary(
  summary: Record<string, unknown>,
  reviewReason: string,
): Record<string, unknown> {
  return {
    ...summary,
    terminal_disposition: "review_required",
    review_reason: reviewReason.slice(0, 64),
    crawl_complete: false,
    card_identity_validated: false,
  };
}

const PERMANENT_FAILURES = new Set([
  "not_a_card",
  "ambiguous_product",
  "identity_mismatch",
  "unapproved_domain",
  "unsupported_content",
  "insufficient_evidence",
]);

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

export async function authorizedSchedulerRequest(
  request: Request,
  serviceKey: string,
  cronSecret: string,
): Promise<boolean> {
  const bearer =
    request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ??
      null;
  const [serviceAuthorized, cronAuthorized] = await Promise.all([
    secureSecretEqual(bearer, serviceKey),
    secureSecretEqual(
      request.headers.get("x-cardcompass-cron-secret"),
      cronSecret,
    ),
  ]);
  return serviceAuthorized || cronAuthorized;
}

function runModeFromRequest(value: unknown): RunMode | null {
  if (value === undefined || value === null) return "scheduled";
  return value === "pilot" || value === "scheduled" || value === "manual"
    ? value
    : null;
}

export function issuerDiscoveryRunMode(
  body: Record<string, unknown>,
): "scheduled" | "manual" | null {
  if (body.action !== "issuer_discovery") return null;
  const runMode = body.runMode ?? body.run_mode;
  return runMode === "scheduled" || runMode === "manual" ? runMode : null;
}

function pilotJob(row: Record<string, any>): PilotJob {
  const summary = row.result_summary && typeof row.result_summary === "object"
    ? row.result_summary
    : {};
  const count = (value: unknown): number | null =>
    typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= MAX_PILOT_REVIEW_COUNT
      ? value
      : null;
  const reviewStatus = summary.review_status === "approved" ||
      summary.review_status === "rejected"
    ? summary.review_status
    : null;
  const reviewCountKeys = [
    "approved_count",
    "retained_count",
    "retired_count",
    "rejected_count",
  ] as const;
  const hasOwn = (key: string) => Object.hasOwn(summary, key);
  const reviewFields = ["review_status", ...reviewCountKeys] as const;
  const reviewMetadataPresent = reviewFields.some(hasOwn);
  const reviewMetadataMalformed = reviewMetadataPresent &&
    (
      !reviewFields.every(hasOwn) || reviewStatus === null ||
      reviewCountKeys.some((key) => count(summary[key]) === null)
    );
  const unsafeMutationCount = count(summary.unsafe_mutation_count);
  const safetyMetadataValid = hasOwn("unsafe_mutation_count") &&
    typeof summary.unsafe_mutation_count === "number" &&
    unsafeMutationCount !== null && hasOwn("raw_body_stored") &&
    typeof summary.raw_body_stored === "boolean";
  const quarantineReason = typeof row.failure_category === "string" &&
      /^[a-z0-9_]{1,64}$/.test(row.failure_category.trim())
    ? row.failure_category.trim()
    : null;
  return {
    id: String(row.id),
    runMode: row.run_mode,
    pilotQualified: summary.pilot_qualified === true,
    status: String(row.status),
    quarantineReason: row.status === "quarantined" ? quarantineReason : null,
    safetyMetadataValid,
    unsafeMutationCount: unsafeMutationCount ?? -1,
    idempotencyPassed: summary.idempotency_passed === true,
    evidencePassed: summary.evidence_passed === true,
    rawBodyStored: summary.raw_body_stored === true,
    successfulNoChange: summary.successful_no_change === true,
    reviewMetadataPresent,
    reviewMetadataMalformed,
    reviewStatus,
    approvedCount: count(summary.approved_count),
    retainedCount: count(summary.retained_count),
    retiredCount: count(summary.retired_count),
    rejectedCount: count(summary.rejected_count),
  };
}

export async function readPilotStatus(
  db: UntypedSupabaseClient,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
) {
  assertBenefitParserVersion(parserVersion);
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .select("id,run_mode,status,failure_category,result_summary")
    .eq("parser_version", parserVersion)
    .or("run_mode.eq.pilot,result_summary->>pilot_qualified.eq.true");
  if (error) throw error;
  return evaluatePilotGate((data ?? []).map(pilotJob));
}

export async function promoteQualifiedPilotJobs(
  db: UntypedSupabaseClient,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
): Promise<EnrichmentJob[]> {
  assertBenefitParserVersion(parserVersion);
  if (parserVersion !== CURRENT_BENEFIT_PARSER_VERSION) {
    throw new Error("unsupported_pilot_parser_version");
  }
  const { data, error } = await db.rpc(
    "promote_qualified_card_benefit_enrichment_pilot",
    { _parser_version: parserVersion },
  );
  if (error) throw error;
  const jobs = (data ?? []) as EnrichmentJob[];
  if (jobs.length !== 5) throw new Error("pilot_promotion_failed");
  return jobs;
}

export async function readCurrentBenefits(
  db: UntypedSupabaseClient,
  cardId: string,
): Promise<BenefitComparisonProposal[]> {
  // The Task 2 view is the one authoritative UTC lifecycle projection. In
  // particular, it excludes future replacements while retaining an old mapping
  // whose retirement boundary has not arrived yet.
  const { data, error } = await db.from("active_card_benefits")
    .select("*")
    .eq("card_id", cardId);
  if (error) throw error;
  return (data ?? []).map(currentBenefitProposal)
    .filter((
      benefit: BenefitComparisonProposal | null,
    ): benefit is BenefitComparisonProposal => benefit !== null);
}

async function cardScopedIdentifier(
  cardId: string,
  benefit: BenefitComparisonProposal,
): Promise<string> {
  if (benefit.benefitId?.startsWith("card-benefit-v2:")) {
    return benefit.benefitId;
  }
  if (benefit.dedupeKey.startsWith("card-benefit-v2:")) {
    return benefit.dedupeKey;
  }
  return await cardScopedBenefitKey(cardId, {
    title: benefit.title,
    description: benefit.description,
    category: benefit.category,
    benefitType: benefit.valueType,
    semanticKey: benefit.offerSubject ??
      `${benefit.category}:${benefit.valueType ?? "benefit"}`,
    value: benefit.value,
    rate: benefit.rate,
    cap: benefit.cap,
    threshold: benefit.threshold,
    frequency: benefit.frequency,
    period: benefit.period,
    valueConfig: benefit.valueConfig,
    exclusions: benefit.exclusions,
    restrictions: benefit.restrictions,
    partners: benefit.partners,
    validFrom: benefit.effectiveFrom,
    validUntil: benefit.effectiveTo,
  });
}

async function withCardScopedRemovalIds(
  cardId: string,
  removals: RemovalCandidate[],
): Promise<RemovalCandidate[]> {
  return await Promise.all(removals.map(async (removal) => ({
    ...removal,
    benefit: {
      ...removal.benefit,
      benefitId: await cardScopedIdentifier(cardId, removal.benefit),
    },
  })));
}

async function sha256Text(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function stagingSourceMetadata(
  sourceUrl: string,
  transientSourceIdentityHash?: string,
): Promise<{
  sourceUrl: string;
  sourceUrlHash: string;
}> {
  const displayUrl = safeHttpsDisplayUrl(sourceUrl);
  if (!displayUrl) throw new Error("invalid_source_url");
  let identityUrl: URL;
  try {
    identityUrl = new URL(sourceUrl);
    if (identityUrl.protocol !== "https:" || !identityUrl.hostname) {
      throw new Error("invalid_source_url");
    }
  } catch {
    throw new Error("invalid_source_url");
  }
  identityUrl.username = "";
  identityUrl.password = "";
  identityUrl.hash = "";
  identityUrl.searchParams.sort();
  return {
    sourceUrl: displayUrl,
    sourceUrlHash: /^[0-9a-f]{64}$/i.test(transientSourceIdentityHash ?? "")
      ? transientSourceIdentityHash!.toLowerCase()
      : await sha256Text(identityUrl.toString()),
  };
}

export async function computeSourceManifestHash(
  attempts: SourceAttempt[],
): Promise<string> {
  const stableValue = (value: unknown): unknown => {
    if (Array.isArray(value)) return value.map(stableValue);
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .filter(([key]) => key !== "attemptedAt")
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([key, nested]) => [key, stableValue(nested)]),
      );
    }
    return value;
  };
  const stableAttempts = attempts.map((attempt) =>
    JSON.stringify(stableValue(attempt))
  ).sort();
  return await sha256Text(stableAttempts.join("\n"));
}

type RemovalCandidate = BenefitDiff["possibleRemovals"][number];
type RetirementRemoval = RemovalCandidate & {
  retirementEligible: boolean;
  retirementReason: string;
};

export function applyRemovalPolicy(input: {
  possibleRemovals: RemovalCandidate[];
  crawlComplete: boolean;
  observedAt: string;
  completeAbsenceHistory: Record<string, string[]>;
}): {
  possibleRemovals: RetirementRemoval[];
  suppressedRemovalCount: number;
  absentBenefitIds: string[];
  absentLegacyBenefitIds: string[];
} {
  const scopedIds = new Set<string>();
  const legacyIds = new Set<string>();
  for (const { benefit } of input.possibleRemovals) {
    const benefitId = benefit.benefitId?.trim();
    const dedupeKey = benefit.dedupeKey.trim();
    if (benefitId?.startsWith("card-benefit-v2:")) scopedIds.add(benefitId);
    if (dedupeKey.startsWith("card-benefit-v2:")) scopedIds.add(dedupeKey);
    else if (dedupeKey) legacyIds.add(dedupeKey);
  }
  const absentBenefitIds = [...scopedIds].sort();
  const absentLegacyBenefitIds = [...legacyIds].sort();
  if (!input.crawlComplete) {
    return {
      possibleRemovals: [],
      suppressedRemovalCount: input.possibleRemovals.length,
      absentBenefitIds,
      absentLegacyBenefitIds,
    };
  }
  const possibleRemovals = input.possibleRemovals.map((removal) => {
    const identifiers = [
      removal.benefit.benefitId,
      removal.benefit.dedupeKey,
    ].filter((value): value is string => Boolean(value));
    const observed = [
      ...new Set([
        ...identifiers.flatMap((id) => input.completeAbsenceHistory[id] ?? []),
        input.observedAt,
      ]),
    ].sort();
    const eligibility = retirementEligibility({
      explicitEndDate: removal.benefit.effectiveTo,
      completeAbsenceObservedAt: observed,
      now: input.observedAt,
    });
    return {
      ...removal,
      retirementEligible: eligibility.eligible,
      retirementReason: eligibility.reason,
      completeAbsenceObservedAt: observed.slice(-24),
    };
  });
  return {
    possibleRemovals,
    suppressedRemovalCount: 0,
    absentBenefitIds,
    absentLegacyBenefitIds,
  };
}

export function buildCrawlObservation(input: {
  observedAt: string;
  assessmentTime: string;
  crawlComplete: boolean;
  crawlReason: string;
  sourceManifestHash: string;
  canonicalBenefitHash: string;
  absentBenefitIds: string[];
  absentLegacyBenefitIds: string[];
  attempts: SourceAttempt[];
}) {
  const compacted = compactSourceAttempts(input.attempts, input.assessmentTime);
  return {
    observed_at: input.observedAt,
    crawl_complete: input.crawlComplete && compacted.complete,
    crawl_reason: (compacted.complete ? input.crawlReason : compacted.reason)
      .slice(0, 64),
    source_manifest_hash: input.sourceManifestHash.slice(0, 128),
    canonical_benefit_hash: input.canonicalBenefitHash.slice(0, 128),
    absent_benefit_ids: [...new Set(input.absentBenefitIds)].sort().slice(
      0,
      256,
    ),
    absent_legacy_benefit_ids: [...new Set(input.absentLegacyBenefitIds)].sort()
      .slice(0, 256),
    source_attempts: compacted.attempts,
  };
}

function observationObjects(summary: unknown): Array<Record<string, unknown>> {
  if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
    return [];
  }
  const object = summary as Record<string, unknown>;
  return [
    ...(object.observation && typeof object.observation === "object" &&
        !Array.isArray(object.observation)
      ? [object.observation as Record<string, unknown>]
      : []),
    ...(Array.isArray(object.observations)
      ? object.observations.filter((item): item is Record<string, unknown> =>
        Boolean(item) && typeof item === "object" && !Array.isArray(item)
      )
      : []),
  ];
}

export function newestValidCrawlObservations(
  summaries: unknown[],
  assessmentTime: string,
): Array<Record<string, unknown>> {
  const assessmentTimestamp = utcInstant(assessmentTime);
  if (assessmentTimestamp === null) return [];
  const byIdentity = new Map<string, {
    observedAt: string;
    observation: Record<string, unknown>;
  }>();
  for (const observation of summaries.flatMap(observationObjects)) {
    const observedAt = typeof observation.observed_at === "string"
      ? observation.observed_at
      : "";
    const timestamp = utcInstant(observedAt);
    if (
      timestamp === null ||
      timestamp > assessmentTimestamp + MAX_EVIDENCE_CLOCK_SKEW_MS
    ) {
      continue;
    }
    const identity = [
      observedAt,
      typeof observation.source_manifest_hash === "string"
        ? observation.source_manifest_hash
        : "",
      typeof observation.canonical_benefit_hash === "string"
        ? observation.canonical_benefit_hash
        : "",
    ].join("\u0000");
    if (!byIdentity.has(identity)) {
      byIdentity.set(identity, { observedAt, observation });
    }
  }
  return [...byIdentity.values()].sort((left, right) =>
    Number(utcInstant(right.observedAt)) -
      Number(utcInstant(left.observedAt)) ||
    String(left.observation.source_manifest_hash ?? "").localeCompare(
      String(right.observation.source_manifest_hash ?? ""),
    ) ||
    String(left.observation.canonical_benefit_hash ?? "").localeCompare(
      String(right.observation.canonical_benefit_hash ?? ""),
    )
  ).slice(0, 24).map(({ observation }) => observation);
}

function latestValidCrawlObservation(
  summary: unknown,
  assessmentTime: string,
): Record<string, unknown> | undefined {
  const latest = newestValidCrawlObservations([summary], assessmentTime)[0];
  if (latest) return latest;
  const legacy = observationObjects(summary);
  return legacy.length === 1 &&
      typeof legacy[0].observed_at !== "string"
    ? legacy[0]
    : undefined;
}

export async function readCompleteAbsenceHistory(
  db: UntypedSupabaseClient,
  cardId: string,
  identifiers: string[],
  assessmentTime: string,
): Promise<Record<string, string[]>> {
  const requested = new Set(identifiers.filter(Boolean).slice(0, 512));
  if (requested.size === 0) return {};
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .select("id,staging_id,result_summary,updated_at")
    .eq("card_id", cardId)
    .eq("parser_version", "benefits-v6")
    .order("updated_at", { ascending: false })
    .limit(24);
  if (error) throw error;
  const stagingIds = [
    ...new Set(
      (data ?? []).map((row: Record<string, unknown>) =>
        typeof row.staging_id === "string" ? row.staging_id : ""
      ).filter(Boolean),
    ),
  ].slice(0, 24);
  const corroboratedStagingIds = new Set<string>();
  if (stagingIds.length > 0) {
    const { data: stagingRows, error: stagingError } = await db
      .from("card_benefits_staging")
      .select("id,card_id,parser_version,status,extracted_data,validated_at")
      .eq("card_id", cardId)
      .eq("parser_version", "benefits-v6")
      .in("id", stagingIds)
      .limit(24);
    if (stagingError) throw stagingError;
    for (const staging of stagingRows ?? []) {
      const extracted = staging.extracted_data;
      if (
        typeof staging.id === "string" &&
        extracted && typeof extracted === "object" &&
        !Array.isArray(extracted) &&
        (extracted as Record<string, unknown>).request_type ===
          "official_benefit_enrichment" &&
        (extracted as Record<string, unknown>).parser_version === "benefits-v6"
      ) corroboratedStagingIds.add(staging.id);
    }
  }
  const history: Record<string, string[]> = {};
  const eligibleSummaries = (data ?? []).filter((
    row: Record<string, unknown>,
  ) =>
    !(
      typeof row.staging_id === "string" &&
      !corroboratedStagingIds.has(row.staging_id)
    )
  ).map((row: Record<string, unknown>) => row.result_summary);
  for (
    const observation of newestValidCrawlObservations(
      eligibleSummaries,
      assessmentTime,
    )
  ) {
    if (observation.crawl_complete !== true) continue;
    const observedAt = String(observation.observed_at);
    for (
      const identifier of [
        ...(Array.isArray(observation.absent_benefit_ids)
          ? observation.absent_benefit_ids
          : []),
        ...(Array.isArray(observation.absent_legacy_benefit_ids)
          ? observation.absent_legacy_benefit_ids
          : []),
      ].map(String)
    ) {
      if (!requested.has(identifier)) continue;
      history[identifier] = [
        ...new Set([...(history[identifier] ?? []), observedAt]),
      ].sort();
    }
  }
  return history;
}

export function shouldStageMaterialProposal(
  previousCanonicalHash: string | null | undefined,
  canonicalHash: string,
  _previousStagingId: string | null | undefined,
): boolean {
  return !previousCanonicalHash || previousCanonicalHash !== canonicalHash;
}

export function crawlProposalDisposition(input: {
  crawlComplete: boolean;
  currentCount: number;
  proposedCount: number;
}): "material" | "removal_review" | "no_change" | "incomplete" {
  if (!input.crawlComplete && input.proposedCount === 0) return "incomplete";
  if (input.proposedCount > 0) return "material";
  return input.currentCount > 0 ? "removal_review" : "no_change";
}

export function observationValidatedAt(
  retrievedAt: string,
  assessmentTime: string,
): string {
  const retrieved = utcInstant(retrievedAt);
  const assessment = utcInstant(assessmentTime);
  if (
    retrieved === null || assessment === null ||
    retrieved > assessment + MAX_EVIDENCE_CLOCK_SKEW_MS
  ) {
    throw new Error("invalid_observation_timestamp");
  }
  return retrievedAt;
}

export async function stagingContentHashForObservation(input: {
  disposition: "material" | "removal_review" | "no_change" | "incomplete";
  sourceManifestHash: string;
  observedAt: string;
  removals: Array<{ benefitId: string; retirementEligible: boolean }>;
}): Promise<string> {
  if (input.disposition !== "removal_review") return input.sourceManifestHash;
  const removals = [...input.removals].sort((left, right) =>
    left.benefitId.localeCompare(right.benefitId)
  );
  return await sha256Text(JSON.stringify({
    source_manifest_hash: input.sourceManifestHash,
    observed_at: observationValidatedAt(input.observedAt, input.observedAt),
    removals,
  }));
}

async function incompleteObservationState(input: {
  job: EnrichmentJob;
  current: BenefitComparisonProposal[];
  runId: string;
  attempts: SourceAttempt[];
  observedAt: string;
  crawlReason: string;
  sourceManifestHash: string;
  sourceDocumentCount: number;
}): Promise<{
  normalizedFields: Record<string, unknown>;
  resultSummary: Record<string, unknown>;
}> {
  const removals = await withCardScopedRemovalIds(
    input.job.card_id,
    input.current.map((benefit) => ({ benefit, informational: true })),
  );
  const removalPolicy = applyRemovalPolicy({
    possibleRemovals: removals,
    crawlComplete: false,
    observedAt: input.observedAt,
    completeAbsenceHistory: {},
  });
  const previousObservation = latestValidCrawlObservation(
    input.job.result_summary,
    input.observedAt,
  );
  const canonicalBenefitHash = typeof previousObservation
      ?.canonical_benefit_hash === "string"
    ? previousObservation.canonical_benefit_hash
    : await sha256Text("[]");
  const observation = buildCrawlObservation({
    observedAt: input.observedAt,
    assessmentTime: input.observedAt,
    crawlComplete: false,
    crawlReason: input.crawlReason,
    sourceManifestHash: input.sourceManifestHash,
    canonicalBenefitHash,
    absentBenefitIds: removalPolicy.absentBenefitIds,
    absentLegacyBenefitIds: removalPolicy.absentLegacyBenefitIds,
    attempts: input.attempts,
  });
  return {
    normalizedFields: {
      source_document_count: input.sourceDocumentCount,
      source_manifest_hash: input.sourceManifestHash,
      canonical_benefit_hash: canonicalBenefitHash,
      crawl_complete: false,
    },
    resultSummary: {
      run_id: input.runId,
      source_documents: input.sourceDocumentCount,
      proposals: 0,
      additions: 0,
      modifications: 0,
      possible_removals: 0,
      suppressed_removal_count: removalPolicy.suppressedRemovalCount,
      conflicts: 0,
      source_manifest_hash: input.sourceManifestHash,
      canonical_benefit_hash: canonicalBenefitHash,
      crawl_complete: false,
      observation,
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      evidence_passed: false,
      idempotency_passed: true,
    },
  };
}

export async function initializePilotJobs(
  db: UntypedSupabaseClient,
  candidates: readonly PilotCandidate[],
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
): Promise<EnrichmentJob[]> {
  assertBenefitParserVersion(parserVersion);
  if (parserVersion !== CURRENT_BENEFIT_PARSER_VERSION) {
    throw new Error("unsupported_pilot_parser_version");
  }
  const selected = selectPilotCandidates(candidates);
  if (selected.length !== 5) throw new Error("invalid_pilot_candidates");
  const { data, error } = await db.rpc(
    "initialize_card_benefit_enrichment_pilot",
    {
      _candidates: selected.map((candidate) => ({
        card_id: candidate.id,
        profile: candidate.profile,
      })),
      _parser_version: parserVersion,
    },
  );
  if (error) throw error;
  const jobs = (data ?? []) as EnrichmentJob[];
  if (jobs.length !== 5) throw new Error("pilot_initialization_failed");
  return jobs;
}

export async function seedScheduledQueueIfAllowed(
  db: UntypedSupabaseClient,
  runMode: RunMode,
  scheduledClaimAllowed: boolean,
  pageSize = 200,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
): Promise<number> {
  if (runMode !== "scheduled" || !scheduledClaimAllowed) return 0;
  assertBenefitParserVersion(parserVersion);
  const { data: pilotRows, error: pilotError } = await db
    .from("card_catalog_enrichment_jobs")
    .select("card_id,parser_version,result_summary")
    .eq("parser_version", parserVersion)
    .or("run_mode.eq.pilot,result_summary->>pilot_qualified.eq.true");
  if (pilotError) throw pilotError;
  const pilotIdentities = new Set(
    (pilotRows ?? []).map((row: Record<string, unknown>) =>
      `${String(row.card_id)}:${String(row.parser_version)}`
    ),
  );
  const unresolvedIdentityCardIds = new Set<string>();
  const unresolvedIdentityUrls = new Set<string>();
  const identityUrlKey = (value: unknown): string | null => {
    if (typeof value !== "string") return null;
    try {
      const url = new URL(value);
      if (url.protocol !== "https:" || url.username || url.password) {
        return null;
      }
      url.hash = "";
      url.search = "";
      url.hostname = url.hostname.toLowerCase();
      url.pathname = url.pathname.replace(/\/+$/, "") || "/";
      return url.toString();
    } catch {
      return null;
    }
  };
  let reviewOffset = 0;
  const reviewPageSize = 200;
  while (true) {
    const { data: reviewRows, error: reviewError } = await db
      .from("card_catalog_review_queue")
      .select("id,existing_candidates,proposed_fields,source_evidence")
      .eq("status", "pending")
      .order("id", { ascending: true })
      .range(reviewOffset, reviewOffset + reviewPageSize - 1);
    if (reviewError) throw reviewError;
    const rows = (reviewRows ?? []) as Array<Record<string, unknown>>;
    for (const review of rows) {
      const proposed = review.proposed_fields &&
          typeof review.proposed_fields === "object" &&
          !Array.isArray(review.proposed_fields)
        ? review.proposed_fields as Record<string, unknown>
        : null;
      const sourceEvidence = review.source_evidence &&
          typeof review.source_evidence === "object" &&
          !Array.isArray(review.source_evidence)
        ? review.source_evidence as Record<string, unknown>
        : null;
      const sourceObservation = sourceEvidence?.source_observation;
      if (
        proposed?.suggested_action === "observe_directory_absence" &&
        sourceObservation && typeof sourceObservation === "object" &&
        !Array.isArray(sourceObservation) &&
        (sourceObservation as Record<string, unknown>).kind ===
          "complete_issuer_directory_absence"
      ) {
        continue;
      }
      const candidates = Array.isArray(review.existing_candidates)
        ? review.existing_candidates
        : [];
      for (const candidate of candidates) {
        if (!candidate || typeof candidate !== "object") continue;
        const object = candidate as Record<string, unknown>;
        const id = object.card_id ?? object.cardId ?? object.id;
        if (typeof id === "string" && id) unresolvedIdentityCardIds.add(id);
      }
      if (
        review.proposed_fields && typeof review.proposed_fields === "object" &&
        !Array.isArray(review.proposed_fields)
      ) {
        const proposedFields = review.proposed_fields as Record<
          string,
          unknown
        >;
        const id = proposedFields.card_id ?? proposedFields.cardId ??
          proposedFields.existing_card_id;
        if (typeof id === "string" && id) unresolvedIdentityCardIds.add(id);
        const proposedUrl = identityUrlKey(
          proposedFields.official_url ?? proposedFields.card_url ??
            proposedFields.source_url,
        );
        if (proposedUrl) unresolvedIdentityUrls.add(proposedUrl);
      }
      if (
        review.source_evidence && typeof review.source_evidence === "object" &&
        !Array.isArray(review.source_evidence)
      ) {
        const evidence = review.source_evidence as Record<string, unknown>;
        const evidenceUrl = identityUrlKey(
          evidence.official_url ?? evidence.source_url,
        );
        if (evidenceUrl) unresolvedIdentityUrls.add(evidenceUrl);
      }
    }
    if (rows.length < reviewPageSize) break;
    reviewOffset += reviewPageSize;
  }
  const boundedPageSize = Math.min(1000, Math.max(1, Math.trunc(pageSize)));
  let offset = 0;
  let seeded = 0;
  while (true) {
    const { data, error } = await db.from("card_catalog")
      .select("id,bank,card_url,card_type,is_discontinued")
      .ilike("card_type", "credit")
      .like("card_url", "https://%")
      .order("id", { ascending: true })
      .range(offset, offset + boundedPageSize - 1);
    if (error) throw error;
    const rows = (data ?? []) as Array<Record<string, unknown>>;
    const discontinuedIds = rows.filter((row) => row.is_discontinued === true)
      .map((row) => String(row.id));
    const { data: activeCardRows, error: activeCardError } =
      discontinuedIds.length === 0
        ? { data: [], error: null }
        : await db.from("user_cards").select("catalog_card_id")
          .in("catalog_card_id", discontinuedIds)
          .eq("is_active", true);
    if (activeCardError) throw activeCardError;
    const activelyHeld = new Set(
      (activeCardRows ?? []).map((row: Record<string, unknown>) =>
        String(row.catalog_card_id)
      ),
    );
    const queueInputs: BenefitEnrichmentQueueInput[] = [];
    for (const row of rows) {
      if (
        !refreshEligibleCard({
          isDiscontinued: row.is_discontinued === true,
          hasActiveCardholder: activelyHeld.has(String(row.id)),
        }) ||
        String(row.card_type ?? "").trim().toLowerCase() !== "credit" ||
        typeof row.bank !== "string" ||
        typeof row.card_url !== "string" ||
        unresolvedIdentityCardIds.has(String(row.id)) ||
        unresolvedIdentityUrls.has(identityUrlKey(row.card_url) ?? "") ||
        pilotIdentities.has(`${String(row.id)}:${parserVersion}`) ||
        !allowedOfficialUrl(row.bank, row.card_url)
      ) continue;
      const canonicalUrl = canonicalOfficialUrl(row.bank, row.card_url);
      const finalUrlHash = await sha256Text(canonicalUrl);
      queueInputs.push({
        cardId: String(row.id),
        issuer: row.bank,
        canonicalUrl,
        finalUrlHash,
        contentHash: null,
        parserVersion,
        runMode: "scheduled",
        resultSummary: {
          queue_source: "catalog_seed",
          unsafe_mutation_count: 0,
          raw_body_stored: false,
          evidence_passed: false,
          idempotency_passed: false,
        },
      });
    }
    seeded += await enqueueBenefitEnrichmentJobs(db, queueInputs);
    if (rows.length < boundedPageSize) return seeded;
    offset += boundedPageSize;
  }
}

export async function loadCatalogIdentity(
  db: UntypedSupabaseClient,
  cardId: string,
) {
  const { data: card, error: cardError } = await db.from("card_catalog").select(
    "id,card_name,bank,network,card_type,card_url,is_discontinued",
  ).eq("id", cardId).single();
  if (cardError || !card) throw cardError ?? new Error("identity_mismatch");
  const { data: catalogRows, error: catalogError } = await db
    .from("card_catalog")
    .select("id,card_name,bank,network,card_type,is_discontinued")
    .ilike("bank", String(card.bank));
  if (catalogError) throw catalogError;
  const catalog = (catalogRows ?? []).filter((row: Record<string, unknown>) =>
    String(row.bank ?? "").trim().toLowerCase() ===
      String(card.bank).trim().toLowerCase() &&
    String(row.card_type ?? "").trim().toLowerCase() === "credit"
  );
  if (
    !catalog.some((row: Record<string, unknown>) =>
      String(row.id) === String(card.id)
    )
  ) {
    catalog.push({
      id: card.id,
      card_name: card.card_name,
      bank: card.bank,
      network: card.network,
      card_type: card.card_type,
      is_discontinued: card.is_discontinued,
    });
  }
  const cardIds = catalog.map((row: Record<string, unknown>) => String(row.id));
  const { data: aliases, error: aliasError } = cardIds.length === 0
    ? { data: [], error: null }
    : await db.from("card_catalog_aliases").select("card_id,alias")
      .in("card_id", cardIds);
  if (aliasError) throw aliasError;
  return { card, catalog, aliases: aliases ?? [] };
}

function requireMatchingIdentity(
  job: EnrichmentJob,
  catalog: Array<{
    id: string;
    card_name: string;
    network?: string | null;
    card_type?: string | null;
  }>,
  aliases: Array<{ card_id: string; alias: string }>,
  html: string,
  canonicalUrl: string,
): void {
  const classification = classifyIssuerPage({
    issuer: job.issuer,
    url: job.canonical_url,
    canonicalUrl,
    html,
  });
  if (classification.kind === "not_a_card") throw new Error("not_a_card");
  if (classification.kind === "ambiguous") throw new Error("ambiguous_product");
  requireExactCatalogIdentity(
    job.card_id,
    job.issuer,
    classification.proposedName ?? "",
    catalog,
    aliases,
    classification.network,
  );
}

export function requireExactCatalogIdentity(
  targetCardId: string,
  issuer: string,
  proposedName: string,
  catalog: Array<{
    id: string;
    card_name: string;
    network?: string | null;
    card_type?: string | null;
  }>,
  aliases: Array<{ card_id: string; alias: string }>,
  proposedNetwork?: string | null,
): void {
  const networkKey = (
    value: string,
    network?: string | null,
  ): string | null => {
    const signal = `${value} ${network ?? ""}`;
    if (/\b(?:amex|american\s+express)\b/i.test(signal)) return "amex";
    if (/\bmaster\s*card\b/i.test(signal)) return "mastercard";
    if (/\brupay\b/i.test(signal)) return "rupay";
    if (/\bvisa\b/i.test(signal)) return "visa";
    return null;
  };
  const tierKey = (value: string): string | null => {
    const normalized = value.toLowerCase().replace(/[^a-z0-9]+/g, " ");
    if (/\bworld elite\b/.test(normalized)) return "world-elite";
    for (
      const tier of [
        "infinite",
        "signature",
        "world",
        "platinum",
        "gold",
        "select",
        "classic",
      ]
    ) {
      if (new RegExp(`\\b${tier}\\b`).test(normalized)) return tier;
    }
    return null;
  };
  const proposedBase = normalizedProduct(proposedName, issuer);
  const proposedNetworkKey = networkKey(proposedName, proposedNetwork);
  const proposedTierKey = tierKey(proposedName);
  if (proposedBase.length < 2) throw new Error("identity_mismatch");
  const matches = new Set<string>();
  for (
    const row of catalog.filter((candidate) =>
      candidate.card_type?.trim().toLowerCase() === "credit"
    )
  ) {
    const storedNetwork = networkKey(row.card_name, row.network);
    const storedTier = tierKey(row.card_name);
    if (
      (storedNetwork && proposedNetworkKey !== storedNetwork) ||
      (storedTier && proposedTierKey !== storedTier)
    ) continue;
    const labels = [
      row.card_name,
      ...aliases.filter((alias) => String(alias.card_id) === String(row.id))
        .map((alias) => alias.alias),
    ];
    if (
      labels.some((label) => normalizedProduct(label, issuer) === proposedBase)
    ) {
      matches.add(String(row.id));
    }
  }
  if (matches.size > 1) throw new Error("ambiguous_product");
  if (matches.size !== 1 || !matches.has(targetCardId)) {
    throw new Error("identity_mismatch");
  }
}

export function previousFetchValidators(
  job: EnrichmentJob,
): {
  parserVersion: string;
  etag?: string;
  lastModified?: string;
  reusableExtraction: boolean;
  contentHash?: string;
  canonicalBenefitHash?: string;
  sourceIdentityHash?: string;
  finalResourceUrl?: string;
  finalResourceIdentityHash?: string;
  cardIdentityValidated?: boolean;
} | undefined {
  const previousObservation = latestValidCrawlObservation(
    job.result_summary,
    new Date().toISOString(),
  );
  const source = previousObservation?.source_observation;
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return undefined;
  }
  const value = source as Record<string, unknown>;
  const parserVersion = String(value.parser_version ?? "").slice(0, 64);
  if (!parserVersion) return undefined;
  const etag = typeof value.etag === "string"
    ? value.etag.slice(0, 512)
    : undefined;
  const lastModified = typeof value.last_modified === "string"
    ? value.last_modified.slice(0, 512)
    : undefined;
  const contentHash = typeof value.content_hash === "string" &&
      /^[0-9a-f]{64}$/i.test(value.content_hash)
    ? value.content_hash.toLowerCase()
    : undefined;
  const canonicalBenefitHash = previousObservation?.canonical_benefit_hash;
  const sourceIdentityHash = typeof value.submitted_identity_hash ===
        "string" && /^[0-9a-f]{64}$/i.test(value.submitted_identity_hash)
    ? value.submitted_identity_hash.toLowerCase()
    : undefined;
  const finalResourceIdentityHash =
    typeof value.final_resource_identity_hash ===
        "string" && /^[0-9a-f]{64}$/i.test(value.final_resource_identity_hash)
      ? value.final_resource_identity_hash.toLowerCase()
      : undefined;
  const finalResourceUrl = typeof value.final_resource_url === "string" &&
      boundedSourceUrl(value.final_resource_url) !== "invalid-source"
    ? boundedSourceUrl(value.final_resource_url)
    : undefined;
  const cardIdentityValidated = value.card_identity_validated === true;
  const reusableExtraction = previousObservation?.crawl_complete === true &&
    typeof canonicalBenefitHash === "string" &&
    /^[0-9a-f]{64}$/i.test(canonicalBenefitHash) && Boolean(contentHash) &&
    Boolean(sourceIdentityHash) && Boolean(finalResourceIdentityHash) &&
    Boolean(finalResourceUrl) && cardIdentityValidated;
  return {
    parserVersion,
    ...(etag ? { etag } : {}),
    ...(lastModified ? { lastModified } : {}),
    ...(contentHash ? { contentHash } : {}),
    ...(typeof canonicalBenefitHash === "string" &&
        /^[0-9a-f]{64}$/i.test(canonicalBenefitHash)
      ? { canonicalBenefitHash: canonicalBenefitHash.toLowerCase() }
      : {}),
    ...(sourceIdentityHash ? { sourceIdentityHash } : {}),
    ...(finalResourceUrl ? { finalResourceUrl } : {}),
    ...(finalResourceIdentityHash ? { finalResourceIdentityHash } : {}),
    cardIdentityValidated,
    reusableExtraction,
  };
}

function sourceAttemptInputs(
  requestedUrl: string,
  observation: OfficialFetchObservation,
): SourceAttemptInput[] {
  return observation.attempts.map((attempt, index) => {
    const terminal = index === observation.attempts.length - 1
      ? observation.result
      : undefined;
    return {
      requestedUrl,
      ...(terminal ? { finalUrl: terminal.finalUrl } : {}),
      role: "primary",
      status: attempt.status === 304
        ? "not_modified"
        : attempt.status !== undefined && attempt.status >= 200 &&
            attempt.status < 300
        ? "success"
        : "failed",
      ...(attempt.status !== undefined ? { httpStatus: attempt.status } : {}),
      ...(terminal?.contentHash ? { contentHash: terminal.contentHash } : {}),
      ...(terminal?.finalResourceIdentityHash
        ? {
          finalResourceIdentityHash: terminal.finalResourceIdentityHash,
        }
        : {}),
      ...(terminal?.etag ? { etag: terminal.etag } : {}),
      ...(terminal?.lastModified
        ? { lastModified: terminal.lastModified }
        : {}),
      ...(attempt.code ? { errorCode: attempt.code } : {}),
      attemptedAt: attempt.attemptedAt,
      ...(attempt.status === 304
        ? {
          parserCacheReusable: observation.disposition === "not_modified",
        }
        : {}),
    };
  });
}

export async function processJob(
  db: UntypedSupabaseClient,
  job: EnrichmentJob,
  runId: string,
  invocationStartedAt: number,
  dependencies: {
    fetchObservation?: typeof fetchOfficialIssuerObservation;
  } = {},
): Promise<ProcessResult> {
  let outcome: JobOutcome = "failed";
  let retried = false;
  let failureCategory: string | null = null;
  let nextRetryAt: string | null = null;
  let stagingId: string | null = null;
  let contentHash: string | null = null;
  let normalizedFields: Record<string, unknown> = {};
  let resultSummary: Record<string, unknown> = {
    run_id: runId,
    unsafe_mutation_count: 0,
    raw_body_stored: false,
    evidence_passed: false,
    idempotency_passed: false,
  };

  try {
    const { card, catalog, aliases } = await loadCatalogIdentity(
      db,
      job.card_id,
    );
    const current = await readCurrentBenefits(db, job.card_id);
    if (!networkWorkMayStart(invocationStartedAt)) {
      throw new Error("deadline_exceeded");
    }
    const robotsCache = createOfficialRobotsCache();
    const fetchObservation = await (
      dependencies.fetchObservation ?? fetchOfficialIssuerObservation
    )({
      issuer: job.issuer,
      url: job.canonical_url,
      contentPurpose: "document",
      maxBytes: 2 * 1024 * 1024,
      parserVersion: job.parser_version,
      previous: previousFetchValidators(job),
      maxAttempts: 3,
      maxBackoffMs: 30_000,
      deadlineAt: invocationStartedAt + INVOCATION_DEADLINE_MS,
      enforceRobots: true,
      allowedQueryParameters: approvedStoredQueryParameters(job.canonical_url),
      robotsCache,
    });
    const primaryAttemptInputs = sourceAttemptInputs(
      job.canonical_url,
      fetchObservation,
    );
    const fetchSummary = sourceObservationSummary({
      parserVersion: job.parser_version,
      requestedUrl: job.canonical_url,
      disposition: fetchObservation.disposition,
      reviewReason: fetchObservation.reviewReason,
      crawlComplete: fetchObservation.disposition === "success" ||
        fetchObservation.disposition === "not_modified",
      result: fetchObservation.result,
      attempts: fetchObservation.attempts,
    });
    if (fetchObservation.disposition === "not_modified") {
      const observedAt = fetchObservation.result!.retrievedAt;
      const crawl = assessCrawlCompleteness(primaryAttemptInputs, observedAt);
      const previousObservation = latestValidCrawlObservation(
        job.result_summary,
        observedAt,
      );
      const sourceManifestHash = typeof previousObservation
          ?.source_manifest_hash === "string"
        ? previousObservation.source_manifest_hash
        : await computeSourceManifestHash(crawl.attempts);
      const canonicalBenefitHash = typeof previousObservation
          ?.canonical_benefit_hash === "string"
        ? previousObservation.canonical_benefit_hash
        : await sha256Text("[]");
      const observation = {
        ...buildCrawlObservation({
          observedAt,
          assessmentTime: observedAt,
          crawlComplete: true,
          crawlReason: "not_modified",
          sourceManifestHash,
          canonicalBenefitHash,
          absentBenefitIds: [],
          absentLegacyBenefitIds: [],
          attempts: crawl.attempts,
        }),
        source_observation: fetchSummary,
      };
      outcome = "completed";
      contentHash = sourceManifestHash;
      normalizedFields = {
        source_manifest_hash: sourceManifestHash,
        canonical_benefit_hash: canonicalBenefitHash,
        crawl_complete: true,
      };
      resultSummary = {
        run_id: runId,
        source_documents: 0,
        proposals: 0,
        proposal_disposition: "no_change",
        successful_no_change: true,
        source_manifest_hash: sourceManifestHash,
        canonical_benefit_hash: canonicalBenefitHash,
        crawl_complete: true,
        observation,
        source_observation: fetchSummary,
        unsafe_mutation_count: 0,
        raw_body_stored: false,
        evidence_passed: true,
        idempotency_passed: true,
      };
      return { outcome, retried };
    }
    if (
      fetchObservation.disposition !== "success" ||
      !fetchObservation.result
    ) {
      const attemptedAt = fetchObservation.attempts.at(-1)?.attemptedAt ??
        new Date().toISOString();
      const errorCode = fetchObservation.reviewReason ?? "unreachable";
      const crawl = assessCrawlCompleteness(primaryAttemptInputs, attemptedAt);
      const sourceManifestHash = await computeSourceManifestHash(
        crawl.attempts,
      );
      const incomplete = await incompleteObservationState({
        job,
        current,
        runId,
        attempts: crawl.attempts,
        observedAt: attemptedAt,
        crawlReason: crawl.reason,
        sourceManifestHash,
        sourceDocumentCount: 0,
      });
      normalizedFields = incomplete.normalizedFields;
      resultSummary = {
        ...incomplete.resultSummary,
        source_observation: fetchSummary,
        observation: {
          ...(incomplete.resultSummary.observation as Record<string, unknown>),
          source_observation: fetchSummary,
        },
      };
      failureCategory = errorCode;
      const lifecycleAction = catalogLifecycleObservationAction({
        isDiscontinued: card.is_discontinued === true,
        httpStatus: Number(fetchSummary.http_status ?? 0) || null,
        identityValidated: false,
        explicitDiscontinuation: false,
      });
      if (lifecycleAction) {
        await proposeCatalogLifecycleReview(db, {
          cardId: String(card.id),
          suggestedAction: lifecycleAction,
          sourceUrl: job.canonical_url,
          sourceUrlHash: await sha256Text(job.canonical_url),
          contentHash: null,
          sourceObservation: {
            ...fetchSummary,
            kind: "strong_gone_observation",
            source_status: fetchSummary.http_status,
            identity_validated: false,
            retrieved_at: attemptedAt,
          },
        });
      }
      if (fetchObservation.disposition === "blocked") {
        outcome = "quarantined";
      } else if (fetchObservation.disposition === "review_required") {
        outcome = "review_required";
      } else {
        const disposition = failureDisposition(Number(job.attempt_count ?? 1));
        outcome = disposition.status;
        nextRetryAt = disposition.nextRetryAt;
        retried = disposition.retried;
        resultSummary = { ...resultSummary, retry_scheduled: retried };
      }
      return { outcome, retried };
    }
    const page = fetchObservation.result;
    if (page.notModified || !page.text || !page.contentHash) {
      throw new Error("unusable_not_modified");
    }
    contentHash = page.contentHash;
    observationValidatedAt(page.retrievedAt, new Date().toISOString());
    try {
      requireMatchingIdentity(
        job,
        catalog,
        aliases,
        page.text,
        page.canonicalUrl,
      );
    } catch (error) {
      const errorCode = sanitizedSourceErrorCode(error);
      const reviewedFetchSummary = sourceObservationReviewSummary(
        fetchSummary,
        errorCode,
      );
      const attempts: SourceAttemptInput[] = primaryAttemptInputs.map((
        attempt,
        index,
      ) =>
        index === primaryAttemptInputs.length - 1
          ? {
            ...attempt,
            finalUrl: page.finalUrl,
            status: "failed" as const,
            httpStatus: 200,
            contentHash: page.contentHash,
            ...(page.finalResourceIdentityHash
              ? {
                finalResourceIdentityHash: page.finalResourceIdentityHash,
              }
              : {}),
            errorCode,
            attemptedAt: page.retrievedAt,
          }
          : attempt
      );
      const crawl = assessCrawlCompleteness(
        attempts,
        new Date().toISOString(),
      );
      const sourceManifestHash = await computeSourceManifestHash(
        crawl.attempts,
      );
      const incomplete = await incompleteObservationState({
        job,
        current,
        runId,
        attempts: crawl.attempts,
        observedAt: page.retrievedAt,
        crawlReason: errorCode,
        sourceManifestHash,
        sourceDocumentCount: 1,
      });
      normalizedFields = incomplete.normalizedFields;
      resultSummary = {
        ...incomplete.resultSummary,
        source_observation: reviewedFetchSummary,
        observation: {
          ...(incomplete.resultSummary.observation as Record<string, unknown>),
          source_observation: reviewedFetchSummary,
        },
      };
      throw error;
    }
    fetchSummary.card_identity_validated = true;
    const discontinuationEvidence = cardDiscontinuationEvidence(
      page.text,
      job.issuer,
      String(card.card_name),
    );
    const explicitDiscontinuation = discontinuationEvidence.explicit;
    const lifecycleAction = catalogLifecycleObservationAction({
      isDiscontinued: card.is_discontinued === true,
      httpStatus: page.status,
      identityValidated: true,
      explicitDiscontinuation,
    });
    if (lifecycleAction) {
      const lifecycleUrl = page.finalResourceUrl ?? page.finalUrl;
      await proposeCatalogLifecycleReview(db, {
        cardId: String(card.id),
        suggestedAction: lifecycleAction,
        sourceUrl: lifecycleUrl,
        sourceUrlHash: page.finalResourceIdentityHash ??
          await sha256Text(lifecycleUrl),
        contentHash: page.contentHash,
        sourceObservation: {
          ...fetchSummary,
          kind: explicitDiscontinuation
            ? "strong_explicit_discontinuation"
            : "exact_card_reappearance",
          source_status: page.status,
          identity_validated: true,
          explicit_discontinuation: explicitDiscontinuation,
          matched_excerpt: discontinuationEvidence.matchedExcerpt,
          retrieved_at: page.retrievedAt,
        },
      });
    }
    const collected = await collectSupportingBenefitDocuments({
      issuer: job.issuer,
      primary: page,
      primaryAttempts: primaryAttemptInputs,
      parserVersion: job.parser_version,
      requestDeadlineAt: invocationStartedAt + INVOCATION_DEADLINE_MS,
      identityLabels: [
        String(card.card_name ?? ""),
        ...aliases.filter((alias: Record<string, unknown>) =>
          String(alias.card_id) === job.card_id
        ).map((alias: Record<string, unknown>) => String(alias.alias ?? "")),
      ],
      robotsCache,
    });
    const { documents } = collected;
    const assessmentTime = new Date().toISOString();
    const validatedAt = observationValidatedAt(
      page.retrievedAt,
      assessmentTime,
    );
    const crawl = assessCrawlCompleteness(collected.attempts, assessmentTime);
    fetchSummary.crawl_complete = crawl.complete;
    const sourceManifestHash = await computeSourceManifestHash(crawl.attempts);
    contentHash = sourceManifestHash;
    const proposed: BenefitComparisonProposal[] = job.parser_version ===
        "benefits-v6"
      ? await extractGroundedBenefitsV6(documents, "benefits-v6", job.card_id)
      : extractGroundedBenefits(documents, job.parser_version);
    if (proposed.length === 0 && !crawl.complete) {
      const incomplete = await incompleteObservationState({
        job,
        current,
        runId,
        attempts: crawl.attempts,
        observedAt: validatedAt,
        crawlReason: "insufficient_evidence",
        sourceManifestHash,
        sourceDocumentCount: documents.length,
      });
      normalizedFields = incomplete.normalizedFields;
      resultSummary = incomplete.resultSummary;
      throw new Error("insufficient_evidence");
    }
    const canonicalBenefitHash = job.parser_version === "benefits-v6"
      ? await sha256Text(
        proposed.map((benefit) =>
          "conditionHash" in benefit ? benefit.conditionHash : benefit.dedupeKey
        ).sort().join("\n"),
      )
      : sourceManifestHash;
    const rawComparison = diffBenefits(current, proposed);
    const removals = await withCardScopedRemovalIds(
      job.card_id,
      rawComparison.possibleRemovals,
    );
    const removalIdentifiers = removals.flatMap(({ benefit }) => [
      benefit.benefitId ?? "",
      benefit.dedupeKey,
    ]).filter(Boolean);
    const completeAbsenceHistory = crawl.complete
      ? await readCompleteAbsenceHistory(
        db,
        job.card_id,
        removalIdentifiers,
        assessmentTime,
      )
      : {};
    const removalPolicy = applyRemovalPolicy({
      possibleRemovals: removals,
      crawlComplete: crawl.complete,
      observedAt: validatedAt,
      completeAbsenceHistory,
    });
    const compared = {
      ...rawComparison,
      possibleRemovals: removalPolicy.possibleRemovals,
    };
    const proposalDisposition = crawlProposalDisposition({
      crawlComplete: crawl.complete,
      currentCount: current.length,
      proposedCount: proposed.length,
    });
    const observation = {
      ...buildCrawlObservation({
        observedAt: validatedAt,
        assessmentTime,
        crawlComplete: crawl.complete,
        crawlReason: crawl.reason,
        sourceManifestHash,
        canonicalBenefitHash,
        absentBenefitIds: removalPolicy.absentBenefitIds,
        absentLegacyBenefitIds: removalPolicy.absentLegacyBenefitIds,
        attempts: crawl.attempts,
      }),
      source_observation: fetchSummary,
    };
    const stagingContentHash = await stagingContentHashForObservation({
      disposition: proposalDisposition,
      sourceManifestHash,
      observedAt: validatedAt,
      removals: compared.possibleRemovals.map((removal) => ({
        benefitId: removal.benefit.benefitId ?? removal.benefit.dedupeKey,
        retirementEligible: removal.retirementEligible,
      })),
    });
    const confidenceValues = proposed.flatMap((benefit) =>
      Object.values(benefit.confidence)
    );
    const calculatedConfidence = confidenceValues.length > 0
      ? Math.min(...confidenceValues)
      : 0;
    const safeExtraction = {
      request_type: "official_benefit_enrichment",
      parser_version: job.parser_version,
      content_hash: stagingContentHash,
      source_manifest_hash: sourceManifestHash,
      canonical_benefit_hash: canonicalBenefitHash,
      retrieved_at: validatedAt,
      crawl_observation: observation,
      source_documents: documents.map((document) => ({
        source_url: boundedSourceUrl(document.finalUrl ?? document.sourceUrl),
        content_hash: document.contentHash ?? null,
      })),
      proposals: proposed,
      diff: compared,
    };
    const sourceEvidence = proposed.length > 0
      ? proposed.map((benefit) => ({
        dedupe_key: benefit.dedupeKey,
        ...(benefit.offerSubject
          ? { offer_subject: benefit.offerSubject.slice(0, 256) }
          : {}),
        ...(benefit.sourceIdentity
          ? { source_identity: benefit.sourceIdentity.slice(0, 64) }
          : {}),
        ...(benefit.sourceIdentities
          ? { source_identities: benefit.sourceIdentities.slice(0, 32) }
          : {}),
        source_url: benefit.sourceUrl,
        source_excerpt: benefit.sourceExcerpt.slice(0, 500),
        content_hash: benefit.contentHash.slice(0, 128),
        evidence: Object.fromEntries(
          Object.entries(benefit.evidence).slice(0, 32).map((
            [field, excerpt],
          ) => [field.slice(0, 64), String(excerpt).slice(0, 500)]),
        ),
      }))
      : [{
        evidence_type: "crawl_observation",
        source_url: boundedSourceUrl(page.canonicalUrl),
        content_hash: sourceManifestHash,
        crawl_complete: true,
        absent_benefit_ids: observation.absent_benefit_ids,
        absent_legacy_benefit_ids: observation.absent_legacy_benefit_ids,
      }];
    const previousObservation = latestValidCrawlObservation(
      job.result_summary,
      validatedAt,
    );
    const previousCanonicalHash = typeof previousObservation
        ?.canonical_benefit_hash === "string"
      ? previousObservation.canonical_benefit_hash
      : null;
    const materialProposal = proposalDisposition === "removal_review" ||
      (proposalDisposition === "material" && shouldStageMaterialProposal(
        previousCanonicalHash,
        canonicalBenefitHash,
        job.staging_id,
      ));
    const effectiveProposalDisposition = materialProposal
      ? proposalDisposition
      : "no_change";
    let reusedStaging = false;
    if (materialProposal) {
      const stagingSource = await stagingSourceMetadata(
        page.submittedUrl,
        page.sourceIdentityHash,
      );
      const { data: stagedRows, error: stageError } = await db.rpc(
        "stage_card_benefit_enrichment",
        {
          _job_id: job.id,
          _lease_token: job.lease_token,
          _source_url: stagingSource.sourceUrl,
          _source_url_hash: stagingSource.sourceUrlHash,
          _parser_version: job.parser_version,
          _content_hash: stagingContentHash,
          _extracted_data: safeExtraction,
          _calculated_confidence: calculatedConfidence,
          _validation_reasons: [{ code: "official_issuer_source" }],
          _validation_warnings: proposed.flatMap((benefit) => benefit.warnings)
            .map((code) => ({ code: String(code).slice(0, 64) })),
          _source_evidence: sourceEvidence,
          _validated_at: validatedAt,
        },
      );
      const staged = Array.isArray(stagedRows) ? stagedRows[0] : stagedRows;
      if (stageError || !staged?.staging_id) {
        throw stageError ?? new Error("enrichment_failed");
      }
      stagingId = String(staged.staging_id);
      reusedStaging = staged.reused === true;
    } else {
      // Match the 304 path: the worker never makes a racy staging decision.
      // The finalizer locks the job and preserves only a link still pending at
      // that instant, converting the effective database status to staged.
      stagingId = null;
      reusedStaging = false;
    }
    outcome = materialProposal ? "staged" : "completed";
    normalizedFields = {
      proposed_count: proposed.length,
      source_document_count: documents.length,
      source_manifest_hash: sourceManifestHash,
      canonical_benefit_hash: canonicalBenefitHash,
      crawl_complete: crawl.complete,
    };
    resultSummary = {
      run_id: runId,
      proposals: proposed.length,
      source_documents: documents.length,
      additions: compared.additions.length,
      modifications: compared.modifications.length,
      possible_removals: compared.possibleRemovals.length,
      retirement_eligible_removals:
        compared.possibleRemovals.filter((removal) =>
          removal.retirementEligible
        ).length,
      suppressed_removal_count: removalPolicy.suppressedRemovalCount,
      conflicts: compared.conflicts.length,
      reused_staging: reusedStaging,
      material_proposal: materialProposal,
      proposal_disposition: effectiveProposalDisposition,
      successful_no_change: effectiveProposalDisposition === "no_change",
      source_manifest_hash: sourceManifestHash,
      canonical_benefit_hash: canonicalBenefitHash,
      crawl_complete: crawl.complete,
      observation,
      source_observation: fetchSummary,
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      evidence_passed: proposed.every((benefit) =>
        Object.keys(benefit.confidence).every((field) =>
          Boolean(benefit.evidence[field])
        )
      ),
      idempotency_passed: compared.conflicts.length === 0,
    };
    return { outcome, retried };
  } catch (error) {
    failureCategory = safeFailureCategory(error);
    if (PERMANENT_FAILURES.has(failureCategory)) {
      outcome = "quarantined";
      resultSummary = {
        ...resultSummary,
        quarantine_reason: failureCategory,
        idempotency_passed: true,
      };
    } else {
      const disposition = failureDisposition(Number(job.attempt_count ?? 1));
      outcome = disposition.status;
      nextRetryAt = disposition.nextRetryAt;
      retried = disposition.retried;
      resultSummary = { ...resultSummary, retry_scheduled: retried };
    }
    return { outcome, retried };
  } finally {
    const { data: finalizedId, error: finalizeError } = await db.rpc(
      "finalize_card_catalog_enrichment_job",
      {
        _job_id: job.id,
        _lease_token: job.lease_token,
        _status: outcome,
        _staging_id: stagingId,
        _content_hash: contentHash,
        _normalized_fields: normalizedFields,
        _result_summary: resultSummary,
        _failure_category: failureCategory,
        _next_retry_at: nextRetryAt,
      },
    );
    if (finalizeError || finalizedId !== job.id) {
      throw finalizeError ?? new Error("stale_enrichment_lease");
    }
  }
}

type IssuerDiscoveryRunSummary = {
  issuer: string;
  runDate: string;
  status: "complete" | "incomplete" | "budget_exhausted" | "lost_lease";
  complete: boolean;
  budgetExhausted: boolean;
  considered: number;
  fetched: number;
  resumed: number;
  outcomes: Record<string, number>;
  lastProcessedCandidateIdentity: string | null;
  incompleteReasons: string[];
};

export function upsertBoundedIssuerOutcomeSummary<
  T extends Record<string, unknown>,
>(summaries: T[], summary: T): T[] {
  const candidateKey = String(summary.candidate_key ?? "");
  return [
    ...summaries.filter((existing) =>
      String(existing.candidate_key ?? "") !== candidateKey
    ),
    summary,
  ].slice(-200);
}

function storedIssuerCandidateOutcomes(
  seed: IssuerDiscoverySeed,
): IssuerCandidateOutcome[] {
  const summaries = Array.isArray(seed.rotationEvidence.outcome_summaries)
    ? seed.rotationEvidence.outcome_summaries
    : [];
  const outcomes: IssuerCandidateOutcome[] = [];
  for (const value of summaries.slice(-200)) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    const item = value as Record<string, unknown>;
    const candidateKey = String(item.candidate_key ?? "");
    const classification = item.classification;
    const disposition = item.disposition;
    if (
      !/^[0-9a-f]{64}$/i.test(candidateKey) ||
      !classification || typeof classification !== "object" ||
      Array.isArray(classification) ||
      !["candidate", "quarantined", "rejected"].includes(
        String(disposition),
      )
    ) continue;
    outcomes.push({
      candidateKey: candidateKey.toLowerCase(),
      classification:
        classification as IssuerCandidateOutcome["classification"],
      disposition: disposition as IssuerCandidateOutcome["disposition"],
      attempted: item.attempted === true,
    });
  }
  return outcomes;
}

function boundedIssuerCandidateClassification(
  classification: IssuerCandidateOutcome["classification"],
): Record<string, unknown> {
  return {
    kind: classification.kind,
    canonicalUrl: classification.canonicalUrl,
    ...(classification.proposedName
      ? { proposedName: classification.proposedName.slice(0, 160) }
      : {}),
    aliases: classification.aliases.slice(0, 12),
    ...(classification.network
      ? { network: classification.network.slice(0, 64) }
      : {}),
    confidence: classification.confidence,
    warnings: classification.warnings.slice(0, 12),
    sanitizedEvidence: classification.sanitizedEvidence.slice(0, 3),
    ...(classification.submittedResourceIdentityHash
      ? {
        submittedResourceIdentityHash:
          classification.submittedResourceIdentityHash,
      }
      : {}),
    ...(classification.finalResourceIdentityHash
      ? {
        finalResourceIdentityHash: classification.finalResourceIdentityHash,
      }
      : {}),
    ...(classification.submittedUrl
      ? { submittedUrl: classification.submittedUrl }
      : {}),
    ...(classification.finalUrl ? { finalUrl: classification.finalUrl } : {}),
    ...(classification.contentHash
      ? { contentHash: classification.contentHash }
      : {}),
    ...(classification.retrievedAt
      ? { retrievedAt: classification.retrievedAt }
      : {}),
    ...(classification.sourceStatus
      ? { sourceStatus: classification.sourceStatus }
      : {}),
    ...(classification.explicitDiscontinuation
      ? { explicitDiscontinuation: true }
      : {}),
    ...(classification.matchedDiscontinuationExcerpt
      ? {
        matchedDiscontinuationExcerpt: classification
          .matchedDiscontinuationExcerpt.slice(0, 300),
      }
      : {}),
  };
}

export async function persistNonProductIssuerOutcome(
  db: UntypedSupabaseClient,
  issuer: string,
  outcome: IssuerCandidateOutcome,
  reason: string,
): Promise<"duplicate" | "quarantined" | "rejected" | "supporting"> {
  const classification = boundedIssuerCandidateClassification(
    outcome.classification,
  );
  const semanticHash = await sha256Text(JSON.stringify({
    candidate_key: outcome.candidateKey,
    disposition: outcome.disposition,
    classification,
    reason,
  }));
  const dedupeKey = await sha256Text(
    `issuer-candidate-outcome:${issuer.trim().toLowerCase()}:${outcome.candidateKey}:${semanticHash}`,
  );
  if (
    reason === "conflicting_url_identity" &&
    outcome.classification.proposedName?.trim()
  ) {
    await stageCatalogIdentityReview(db, {
      discoveryJobId: null,
      discoverySource: "issuer_crawl",
      userId: null,
      issuer,
      proposedProduct: outcome.classification.proposedName,
      dedupeKey,
      semanticHash,
      proposedFields: {
        issuer,
        cardName: outcome.classification.proposedName,
        aliases: outcome.classification.aliases,
        network: outcome.classification.network ?? null,
        official_url: outcome.classification.canonicalUrl,
        ...(outcome.classification.submittedUrl
          ? { submitted_url: outcome.classification.submittedUrl }
          : {}),
        ...(outcome.classification.finalUrl
          ? { final_url: outcome.classification.finalUrl }
          : {}),
        ...(outcome.classification.submittedResourceIdentityHash
          ? {
            submitted_url_hash:
              outcome.classification.submittedResourceIdentityHash,
          }
          : {}),
        ...(outcome.classification.finalResourceIdentityHash
          ? {
            final_url_hash: outcome.classification.finalResourceIdentityHash,
          }
          : {}),
        ...(outcome.classification.contentHash
          ? { content_hash: outcome.classification.contentHash }
          : {}),
        ...(outcome.classification.retrievedAt
          ? { retrieved_at: outcome.classification.retrievedAt }
          : {}),
        ...(outcome.classification.sourceStatus
          ? { source_status: outcome.classification.sourceStatus }
          : {}),
      },
      sourceEvidence: {
        source_observation: {
          kind: "conflicting_url_identity",
          identity_validated: false,
          candidate_key: outcome.candidateKey,
          classification,
        },
      },
      existingCandidates: [],
      validationWarnings: ["conflicting_url_identity"],
      confidence: outcome.classification.confidence,
      expectedJobStatus: null,
      expectedJobUpdatedAt: null,
    });
    return "quarantined";
  }
  const existing = await db.from("card_discovery_jobs")
    .select("id,status,failure_category")
    .eq("discovery_source", "issuer_crawl")
    .eq("dedupe_key", dedupeKey)
    .is("user_id", null)
    .maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) return "duplicate";
  const supporting = outcome.classification.kind === "supporting_document";
  const rejected = outcome.disposition === "rejected" ||
    outcome.classification.kind === "not_a_card";
  const inserted = await db.from("card_discovery_jobs").insert({
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer,
    proposed_product:
      outcome.classification.proposedName?.trim().slice(0, 160) ||
      null,
    evidence: {
      kind: "issuer_candidate_outcome",
      candidate_key: outcome.candidateKey,
      disposition: outcome.disposition,
      attempted: outcome.attempted,
      reason: reason.slice(0, 64),
      classification,
    },
    dedupe_key: dedupeKey,
    status: supporting ? "resolved" : rejected ? "rejected" : "review_required",
    updated_at: new Date().toISOString(),
  }).select("id,status,failure_category").maybeSingle();
  if (!inserted.error && inserted.data) {
    return supporting ? "supporting" : rejected ? "rejected" : "quarantined";
  }
  if (inserted.error?.code !== "23505") {
    throw inserted.error ?? new Error("issuer_candidate_persistence_failed");
  }
  const raced = await db.from("card_discovery_jobs")
    .select("id,status,failure_category")
    .eq("discovery_source", "issuer_crawl")
    .eq("dedupe_key", dedupeKey)
    .is("user_id", null)
    .maybeSingle();
  if (raced.error || !raced.data) {
    throw raced.error ?? new Error("issuer_candidate_persistence_race");
  }
  return "duplicate";
}

export async function persistIssuerRunProgress(
  db: UntypedSupabaseClient,
  seed: IssuerDiscoverySeed,
  summaries: Array<Record<string, unknown>>,
  counts: Record<string, number>,
): Promise<string> {
  const last = summaries.at(-1);
  const previousLeaseToken = seed.rotationLeaseToken;
  const nextLeaseToken = crypto.randomUUID();
  const evidence = {
    ...seed.rotationEvidence,
    lease_token: nextLeaseToken,
    outcome_summaries: summaries.slice(-200),
    outcome_counts: counts,
    last_processed_candidate_identity: last?.candidate_key ?? null,
  };
  const updated = await db.from("card_discovery_jobs").update({
    evidence,
    updated_at: new Date().toISOString(),
  }).eq("id", seed.rotationJobId).eq("status", "discovering")
    .contains("evidence", { lease_token: previousLeaseToken })
    .select("id,evidence,updated_at,failure_category").maybeSingle();
  if (updated.error || !updated.data) {
    throw updated.error ?? new Error("issuer_discovery_lease_lost");
  }
  seed.rotationEvidence = evidence;
  seed.rotationLeaseToken = nextLeaseToken;
  seed.rotationUpdatedAt = updated.data.updated_at
    ? String(updated.data.updated_at)
    : seed.rotationUpdatedAt;
  return nextLeaseToken;
}

async function loadKnownIssuerCards(
  db: UntypedSupabaseClient,
  issuer: string,
  pageSize = 200,
): Promise<Array<Record<string, unknown>>> {
  const rows: Array<Record<string, unknown>> = [];
  for (let offset = 0;; offset += pageSize) {
    const query = await db.from("card_catalog")
      .select("id,bank,card_name,network,card_type,is_discontinued")
      .ilike("bank", issuer)
      .ilike("card_type", "credit")
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (query.error) throw query.error;
    const page = (query.data ?? []) as Array<Record<string, unknown>>;
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

export async function runIssuerDiscovery(
  db: UntypedSupabaseClient,
  job: IssuerDiscoverySeed,
  deadlineAt: number,
  injected: Partial<{
    discover: typeof discoverIssuerCardCandidates;
    persistCrawlerCandidate: typeof persistCrawlerCandidate;
    persistNonProductIssuerOutcome: typeof persistNonProductIssuerOutcome;
    persistProgress: typeof persistIssuerRunProgress;
    loadKnownIssuerCards: typeof loadKnownIssuerCards;
    stageCompleteAbsenceReviews:
      typeof stageCompleteIssuerDirectoryAbsenceReviews;
    recordOutcome: typeof recordIssuerDiscoveryOutcome;
  }> = {},
): Promise<IssuerDiscoveryRunSummary> {
  const dependencies = {
    discover: discoverIssuerCardCandidates,
    persistCrawlerCandidate,
    persistNonProductIssuerOutcome,
    persistProgress: persistIssuerRunProgress,
    loadKnownIssuerCards,
    stageCompleteAbsenceReviews: stageCompleteIssuerDirectoryAbsenceReviews,
    recordOutcome: recordIssuerDiscoveryOutcome,
    ...injected,
  };
  const priorOutcomes = storedIssuerCandidateOutcomes(job);
  let summaries = priorOutcomes.map((outcome) => ({
    candidate_key: outcome.candidateKey,
    disposition: outcome.disposition,
    attempted: outcome.attempted,
    classification: boundedIssuerCandidateClassification(
      outcome.classification,
    ),
    persistence_outcome: "resumed",
  }));
  const counts: Record<string, number> = Object.fromEntries(
    Object.entries(
      job.rotationEvidence.outcome_counts &&
        typeof job.rotationEvidence.outcome_counts === "object" &&
        !Array.isArray(job.rotationEvidence.outcome_counts)
        ? job.rotationEvidence.outcome_counts as Record<string, unknown>
        : {},
    ).filter((entry): entry is [string, number] =>
      /^[a-z_]{1,32}$/.test(entry[0]) && Number.isInteger(entry[1]) &&
      Number(entry[1]) >= 0 && Number(entry[1]) <= 200
    ),
  );
  let result;
  const lostLeaseSummary = (): IssuerDiscoveryRunSummary => ({
    issuer: job.issuer,
    runDate: job.runDate,
    status: "lost_lease",
    complete: false,
    budgetExhausted: false,
    considered: 0,
    fetched: 0,
    resumed: priorOutcomes.length,
    outcomes: counts,
    lastProcessedCandidateIdentity:
      String(summaries.at(-1)?.candidate_key ?? "") || null,
    incompleteReasons: ["issuer_discovery_lease_lost"],
  });
  try {
    const fallback = issuerDiscoveryFallbackUrls(job.canonical_url);
    result = await dependencies.discover({
      issuer: job.issuer,
      sitemapUrls: fallback.sitemapUrls,
      indexUrls: fallback.indexUrls,
      deadlineAt,
      completedCandidateOutcomes: priorOutcomes,
      onCandidateOutcome: async (outcome) => {
        let persistenceOutcome: string;
        let accepted = true;
        if (outcome.classification.kind === "card_product") {
          try {
            persistenceOutcome = (await dependencies.persistCrawlerCandidate(
              db,
              job.issuer,
              outcome.classification,
            )).outcome;
          } catch (error) {
            if (
              !(error instanceof Error) ||
              !["identity_conflict", "conflicting_url_identity"].includes(
                error.message,
              )
            ) throw error;
            persistenceOutcome = await dependencies
              .persistNonProductIssuerOutcome(
                db,
                job.issuer,
                {
                  ...outcome,
                  classification: {
                    ...outcome.classification,
                    warnings: [
                      ...outcome.classification.warnings,
                      "conflicting_url_identity",
                    ],
                  },
                  disposition: "quarantined",
                },
                "conflicting_url_identity",
              );
            accepted = false;
          }
        } else {
          persistenceOutcome = await dependencies
            .persistNonProductIssuerOutcome(
              db,
              job.issuer,
              outcome,
              outcome.classification.warnings[0] ?? outcome.classification.kind,
            );
          accepted = outcome.classification.kind === "supporting_document";
        }
        counts[persistenceOutcome] = (counts[persistenceOutcome] ?? 0) + 1;
        summaries = upsertBoundedIssuerOutcomeSummary(summaries, {
          candidate_key: outcome.candidateKey,
          disposition: accepted ? outcome.disposition : "quarantined",
          attempted: outcome.attempted,
          classification: boundedIssuerCandidateClassification(
            outcome.classification,
          ),
          persistence_outcome: persistenceOutcome,
        });
        await dependencies.persistProgress(db, job, summaries, counts);
        return accepted;
      },
    });
    const positiveComplete = result.complete && !result.budgetExhausted &&
      result.incompleteReasons.length === 0;
    if (positiveComplete) {
      const knownCards = await dependencies.loadKnownIssuerCards(
        db,
        job.issuer,
      );
      await dependencies.stageCompleteAbsenceReviews(
        db,
        job.issuer,
        result,
        knownCards,
      );
    }
    await dependencies.recordOutcome(db, job, {
      complete: positiveComplete,
      budgetExhausted: result.budgetExhausted,
      reasons: result.incompleteReasons,
      counts,
      summaries,
      considered: result.consideredCount,
      fetched: result.fetchedCount,
      resumed: result.resumedCount,
    });
    return {
      issuer: job.issuer,
      runDate: job.runDate,
      status: positiveComplete
        ? "complete"
        : result.budgetExhausted
        ? "budget_exhausted"
        : "incomplete",
      complete: positiveComplete,
      budgetExhausted: result.budgetExhausted,
      considered: result.consideredCount,
      fetched: result.fetchedCount,
      resumed: result.resumedCount,
      outcomes: counts,
      lastProcessedCandidateIdentity:
        String(summaries.at(-1)?.candidate_key ?? "") || null,
      incompleteReasons: result.incompleteReasons,
    };
  } catch (error) {
    if (
      error instanceof Error &&
      error.message === "issuer_discovery_lease_lost"
    ) return lostLeaseSummary();
    const category = safeFailureCategory(error);
    try {
      await dependencies.recordOutcome(db, job, {
        complete: false,
        budgetExhausted: category === "deadline_exceeded",
        reasons: [category],
        counts,
        summaries,
        considered: result?.consideredCount ?? 0,
        fetched: result?.fetchedCount ?? 0,
        resumed: result?.resumedCount ?? priorOutcomes.length,
      });
    } catch (finalError) {
      if (
        finalError instanceof Error &&
        finalError.message === "issuer_discovery_lease_lost"
      ) return lostLeaseSummary();
      throw finalError;
    }
    throw error;
  }
}

export type IssuerDiscoverySeed =
  & Pick<
    EnrichmentJob,
    "issuer" | "canonical_url"
  >
  & {
    runDate: string;
    runKey: string;
    rotationJobId: string;
    rotationStatus: string;
    rotationUpdatedAt: string | null;
    rotationAttemptCount: number;
    rotationLeaseToken: string;
    rotationEvidence: Record<string, unknown>;
  };

export type IssuerDiscoveryClaim = {
  status:
    | "claimed"
    | "empty"
    | "already_running"
    | "already_completed"
    | "backoff"
    | "quarantined"
    | "resume_exhausted"
    | "legacy_conflict";
  seed: IssuerDiscoverySeed | null;
  reviewSummary?: IssuerDiscoveryReviewSummary;
};

type IssuerDiscoveryReviewSummary = {
  staged: number;
  quarantined: number;
  conflicts: number;
  remaining: number;
};

const emptyIssuerDiscoveryReviewSummary = (): IssuerDiscoveryReviewSummary => ({
  staged: 0,
  quarantined: 0,
  conflicts: 0,
  remaining: 0,
});

function addIssuerDiscoveryReviewSummary(
  left: IssuerDiscoveryReviewSummary,
  right?: IssuerDiscoveryReviewSummary,
): IssuerDiscoveryReviewSummary {
  return {
    staged: left.staged + (right?.staged ?? 0),
    quarantined: left.quarantined + (right?.quarantined ?? 0),
    conflicts: left.conflicts + (right?.conflicts ?? 0),
    remaining: left.remaining + (right?.remaining ?? 0),
  };
}

export function issuerDiscoveryResponseSummary(
  claim: Pick<IssuerDiscoveryClaim, "seed" | "reviewSummary">,
): IssuerDiscoveryReviewSummary & { noWork: boolean } {
  const review = addIssuerDiscoveryReviewSummary(
    emptyIssuerDiscoveryReviewSummary(),
    claim.reviewSummary,
  );
  return {
    ...review,
    noWork: !claim.seed && review.staged === 0 && review.quarantined === 0 &&
      review.conflicts === 0 && review.remaining === 0,
  };
}

type IssuerDiscoveryQuarantineReason =
  | "resume_attempts_exhausted"
  | "transient_producer_state"
  | "invalid_run_evidence"
  | "legacy_anchor_conflict"
  | "anchor_identity_conflict";

type IssuerDiscoveryQuarantineBudget = {
  limit: number;
  used: number;
  deadlineAt: number;
  nowMs: () => number;
};

type IssuerDiscoveryClaimOptions = {
  deadlineAt?: number;
  nowMs?: () => number;
  quarantineLimit?: number;
  quarantineBudget?: IssuerDiscoveryQuarantineBudget;
};

function issuerDiscoveryQuarantineBudget(
  options: IssuerDiscoveryClaimOptions = {},
): IssuerDiscoveryQuarantineBudget {
  if (options.quarantineBudget) return options.quarantineBudget;
  const nowMs = options.nowMs ?? Date.now;
  return {
    limit: Math.max(
      1,
      Math.min(
        ISSUER_DISCOVERY_QUARANTINE_BATCH,
        Math.trunc(
          options.quarantineLimit ?? ISSUER_DISCOVERY_QUARANTINE_BATCH,
        ),
      ),
    ),
    used: 0,
    deadlineAt: options.deadlineAt ?? nowMs() + INVOCATION_DEADLINE_MS,
    nowMs,
  };
}

function issuerQuarantineWorkMayStart(
  budget: IssuerDiscoveryQuarantineBudget,
): boolean {
  return budget.used < budget.limit && budget.nowMs() < budget.deadlineAt;
}

function normalizedIssuerKey(value: unknown): string {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
}

function utcIssuerRunDate(now: Date): string {
  if (!Number.isFinite(now.getTime())) {
    throw new Error("invalid_discovery_time");
  }
  return now.toISOString().slice(0, 10);
}

function issuerRowIsApproved(row: Record<string, unknown>): boolean {
  return !["approved", "is_approved", "enabled", "is_enabled"].some(
    (key) => Object.hasOwn(row, key) && row[key] === false,
  );
}

export async function loadApprovedIssuerCatalog(
  db: UntypedSupabaseClient,
  pageSize = 200,
): Promise<Array<Record<string, unknown>>> {
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new Error("invalid_issuer_page_size");
  }
  const rows: Array<Record<string, unknown>> = [];
  for (let offset = 0;; offset += pageSize) {
    const { data, error } = await db.from("card_catalog")
      .select("id,bank,card_url,card_type,is_discontinued")
      .order("bank", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (error) throw error;
    const page = (data ?? []) as Array<Record<string, unknown>>;
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

export function selectIssuerDiscoveryCandidate(
  catalogRows: Array<Record<string, unknown>>,
  now = new Date(),
): Pick<EnrichmentJob, "issuer" | "canonical_url"> | null {
  const runDate = utcIssuerRunDate(now);
  const issuers = new Map<
    string,
    Pick<EnrichmentJob, "issuer" | "canonical_url">
  >();
  for (const row of catalogRows) {
    const issuer = String(row.bank ?? "").trim();
    const url = String(row.card_url ?? "").trim();
    const key = issuer.toLowerCase();
    if (
      !issuerRowIsApproved(row) ||
      String(row.card_type ?? "").trim().toLowerCase() !== "credit" ||
      !allowedOfficialUrl(issuer, url)
    ) continue;
    const candidate = {
      issuer,
      canonical_url: canonicalOfficialUrl(issuer, url),
    };
    const current = issuers.get(key);
    if (!current || candidate.canonical_url < current.canonical_url) {
      issuers.set(key, candidate);
    }
  }
  const sorted = [...issuers.entries()].sort((
    [leftKey, left],
    [rightKey, right],
  ) =>
    leftKey.localeCompare(rightKey) ||
    left.canonical_url.localeCompare(right.canonical_url)
  ).map(([, issuer]) => issuer);
  if (sorted.length === 0) return null;
  const daySlot = Math.floor(
    Date.parse(`${runDate}T00:00:00.000Z`) / 86_400_000,
  );
  return sorted[daySlot % sorted.length];
}

export async function recordIssuerDiscoveryOutcome(
  db: UntypedSupabaseClient,
  seed: IssuerDiscoverySeed,
  outcome: {
    complete: boolean;
    budgetExhausted: boolean;
    reasons: string[];
    counts: Record<string, number>;
    summaries: Array<Record<string, unknown>>;
    considered: number;
    fetched: number;
    resumed: number;
  },
): Promise<string> {
  const nowDate = new Date();
  const now = nowDate.toISOString();
  const previousLeaseToken = seed.rotationLeaseToken;
  const nextLeaseToken = crypto.randomUUID();
  const positiveComplete = outcome.complete && !outcome.budgetExhausted &&
    outcome.reasons.length === 0;
  const status = positiveComplete ? "resolved" : "failed";
  const retryDelayMs = Math.min(
    6 * 60 * 60 * 1_000,
    5 * 60 * 1_000 *
      (2 ** Math.max(0, Math.min(10, seed.rotationAttemptCount - 1))),
  );
  const evidence = {
    ...seed.rotationEvidence,
    kind: "issuer_directory_anchor",
    lease_token: nextLeaseToken,
    last_outcome: positiveComplete
      ? "complete"
      : outcome.budgetExhausted
      ? "budget_exhausted"
      : "incomplete",
    ...(positiveComplete ? { last_complete_at: now } : {}),
    budget_exhausted: outcome.budgetExhausted,
    considered_count: outcome.considered,
    fetched_count: outcome.fetched,
    resumed_count: outcome.resumed,
    outcome_counts: outcome.counts,
    outcome_summaries: outcome.summaries.slice(-200),
    last_processed_candidate_identity:
      outcome.summaries.at(-1)?.candidate_key ?? null,
    incomplete_reasons: outcome.reasons.slice(0, 32).map((reason) =>
      reason.slice(0, 64)
    ),
  };
  const update = db.from("card_discovery_jobs").update({
    status,
    next_retry_at: positiveComplete
      ? null
      : new Date(nowDate.getTime() + retryDelayMs).toISOString(),
    failure_category: !positiveComplete
      ? (outcome.budgetExhausted
        ? "budget_exhausted"
        : outcome.reasons[0]?.slice(0, 64) ?? "incomplete")
      : null,
    evidence,
    updated_at: now,
  })
    .eq("id", seed.rotationJobId).eq("status", "discovering")
    .contains("evidence", { lease_token: previousLeaseToken });
  const { data, error } = await update.select("id,failure_category")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("issuer_discovery_lease_lost");
  seed.rotationEvidence = evidence;
  seed.rotationLeaseToken = nextLeaseToken;
  seed.rotationUpdatedAt = now;
  return nextLeaseToken;
}

const issuerLeaseTokenPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function issuerRunEvidence(row: Record<string, any>): Record<string, unknown> {
  return row.evidence && typeof row.evidence === "object" &&
      !Array.isArray(row.evidence)
    ? row.evidence as Record<string, unknown>
    : {};
}

function validIssuerRunDate(value: unknown): value is string {
  const runDate = String(value ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(runDate)) return false;
  const parsed = new Date(`${runDate}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === runDate;
}

function issuerRunIdentity(row: Record<string, any>): {
  selected: Pick<EnrichmentJob, "issuer" | "canonical_url">;
  runDate: string;
} | null {
  const evidence = issuerRunEvidence(row);
  const issuer = String(evidence.issuer ?? row.issuer ?? "").trim().replace(
    /\s+/g,
    " ",
  );
  const canonicalUrl = String(evidence.canonical_url ?? "").trim();
  const runDate = String(evidence.run_date ?? "");
  const attemptCount = Number(row.attempt_count ?? 0);
  if (
    !issuer ||
    normalizedIssuerKey(row.issuer) !== normalizedIssuerKey(issuer) ||
    !validIssuerRunDate(runDate) ||
    !Number.isInteger(attemptCount) || attemptCount < 0 ||
    attemptCount > ISSUER_DISCOVERY_MAX_ATTEMPTS ||
    !allowedOfficialUrl(issuer, canonicalUrl)
  ) return null;
  return {
    selected: {
      issuer,
      canonical_url: canonicalOfficialUrl(issuer, canonicalUrl),
    },
    runDate,
  };
}

async function issuerAnchorIdentityValid(
  row: Record<string, any>,
  selected: Pick<EnrichmentJob, "issuer" | "canonical_url">,
): Promise<boolean> {
  const evidence = issuerRunEvidence(row);
  const rowIssuer = String(row.issuer ?? "").trim().replace(/\s+/g, " ");
  const evidenceIssuer = String(evidence.issuer ?? "").trim().replace(
    /\s+/g,
    " ",
  );
  const evidenceUrl = String(evidence.canonical_url ?? "").trim();
  const attemptCount = Number(row.attempt_count ?? 0);
  const expectedAnchorKey = await sha256Text(
    `issuer-directory-anchor:${normalizedIssuerKey(rowIssuer)}`,
  );
  return String(evidence.kind ?? "") === "issuer_directory_anchor" &&
    normalizedIssuerKey(rowIssuer) === normalizedIssuerKey(selected.issuer) &&
    normalizedIssuerKey(rowIssuer) === normalizedIssuerKey(evidenceIssuer) &&
    String(row.dedupe_key ?? "") === expectedAnchorKey &&
    validIssuerRunDate(evidence.run_date) &&
    Number.isInteger(attemptCount) && attemptCount >= 0 &&
    attemptCount <= ISSUER_DISCOVERY_MAX_ATTEMPTS &&
    allowedOfficialUrl(
      selected.issuer.trim().replace(/\s+/g, " "),
      evidenceUrl,
    );
}

function issuerDiscoverySeedFromRow(
  row: Record<string, any>,
  selected: Pick<EnrichmentJob, "issuer" | "canonical_url">,
  runDate: string,
): IssuerDiscoverySeed {
  const evidence = issuerRunEvidence(row);
  const leaseToken = String(evidence.lease_token ?? "");
  if (!issuerLeaseTokenPattern.test(leaseToken)) {
    throw new Error("issuer_discovery_claim_missing_token");
  }
  return {
    ...selected,
    runDate,
    runKey: String(row.dedupe_key),
    rotationJobId: String(row.id),
    rotationStatus: String(row.status),
    rotationUpdatedAt: row.updated_at ? String(row.updated_at) : null,
    rotationAttemptCount: Math.max(1, Number(row.attempt_count ?? 1)),
    rotationLeaseToken: leaseToken,
    rotationEvidence: evidence,
  };
}

async function terminalizeIssuerDiscoveryBacklog(
  db: UntypedSupabaseClient,
  row: Record<string, any>,
  now: Date,
  reason: IssuerDiscoveryQuarantineReason,
): Promise<IssuerDiscoveryReviewSummary> {
  const previousEvidence = issuerRunEvidence(row);
  const issuer = String(row.issuer ?? "").trim().replace(/\s+/g, " ");
  if (issuer.length < 2 || issuer.length > 120) {
    throw new Error("invalid_issuer_quarantine_identity");
  }
  const nowIso = now.toISOString();
  if (
    String(row.status) === "failed" &&
    String(row.failure_category ?? "") === "issuer_discovery_quarantined" &&
    (row.next_retry_at === null || row.next_retry_at === undefined)
  ) {
    return emptyIssuerDiscoveryReviewSummary();
  }
  const buildFence = (fenceReason: IssuerDiscoveryQuarantineReason) => {
    const retryable = [
      "resume_attempts_exhausted",
      "transient_producer_state",
    ].includes(fenceReason);
    return {
      version: 1,
      classification: "issuer_discovery_quarantine",
      semantic_identity: `issuer-discovery-quarantine-v1:${
        String(row.id).slice(0, 64)
      }`,
      anchor_job_id: String(row.id).slice(0, 64),
      issuer,
      reason: fenceReason,
      retryable,
      retryability_reason: retryable
        ? "attempt_budget_reset_allowed"
        : "manual_repair_required",
    };
  };
  const readFence = (evidence: Record<string, unknown>) => {
    const value = evidence.quarantine_fence;
    if (value && typeof value === "object" && !Array.isArray(value)) {
      const fence = value as Record<string, unknown>;
      const fenceReason = String(fence.reason ?? "");
      const fenceIssuer = String(fence.issuer ?? "").trim().replace(
        /\s+/g,
        " ",
      );
      if (
        fence.version === 1 &&
        fence.classification === "issuer_discovery_quarantine" &&
        fence.semantic_identity ===
          `issuer-discovery-quarantine-v1:${String(row.id).slice(0, 64)}` &&
        fence.anchor_job_id === String(row.id).slice(0, 64) &&
        fenceIssuer.length >= 2 && fenceIssuer.length <= 120 &&
        [
          "resume_attempts_exhausted",
          "transient_producer_state",
          "invalid_run_evidence",
          "legacy_anchor_conflict",
          "anchor_identity_conflict",
        ].includes(fenceReason)
      ) {
        const expectedPolicy = buildFence(
          fenceReason as IssuerDiscoveryQuarantineReason,
        );
        if (
          fence.retryable === expectedPolicy.retryable &&
          fence.retryability_reason === expectedPolicy.retryability_reason
        ) {
          return {
            ...expectedPolicy,
            issuer: fenceIssuer,
          };
        }
      }
      throw new Error("invalid_persisted_issuer_quarantine_fence");
    }
    const legacyReason = String(evidence.quarantine_reason ?? "");
    if (
      [
        "resume_attempts_exhausted",
        "transient_producer_state",
        "invalid_run_evidence",
        "legacy_anchor_conflict",
        "anchor_identity_conflict",
      ].includes(legacyReason)
    ) {
      return buildFence(legacyReason as IssuerDiscoveryQuarantineReason);
    }
    return null;
  };
  let fence = readFence(previousEvidence);
  if (
    String(row.status) !== "failed" ||
    String(row.failure_category ?? "") !== "issuer_discovery_quarantined"
  ) {
    fence = buildFence(reason);
    let update = db.from("card_discovery_jobs").update({
      status: "failed",
      next_retry_at: nowIso,
      failure_category: "issuer_discovery_quarantined",
      review_item_id: null,
      evidence: {
        ...previousEvidence,
        last_outcome: reason,
        quarantine_reason: reason,
        quarantine_fence: fence,
      },
      updated_at: nowIso,
    }).eq("id", row.id).eq("status", row.status);
    const leaseToken = String(previousEvidence.lease_token ?? "");
    if (issuerLeaseTokenPattern.test(leaseToken)) {
      update = update.contains("evidence", { lease_token: leaseToken });
    } else if (row.updated_at) {
      update = update.eq("updated_at", row.updated_at);
    }
    const transitioned = await update.select(
      "id,user_id,discovery_source,issuer,evidence,status,updated_at,next_retry_at,attempt_count,dedupe_key,created_at,failure_category,review_item_id",
    ).maybeSingle();
    if (transitioned.error) throw transitioned.error;
    if (!transitioned.data) return emptyIssuerDiscoveryReviewSummary();
  } else if (!previousEvidence.quarantine_fence && fence) {
    let update = db.from("card_discovery_jobs").update({
      evidence: { ...previousEvidence, quarantine_fence: fence },
      updated_at: nowIso,
    }).eq("id", row.id).eq("status", "failed")
      .eq("failure_category", "issuer_discovery_quarantined");
    if (row.updated_at) update = update.eq("updated_at", row.updated_at);
    const persisted = await update.select("id,evidence,failure_category")
      .maybeSingle();
    if (persisted.error) throw persisted.error;
    if (!persisted.data) return emptyIssuerDiscoveryReviewSummary();
  }
  if (!fence) throw new Error("missing_persisted_issuer_quarantine_fence");
  const sourceObservation = {
    kind: "issuer_discovery_quarantine",
    classification: "issuer_discovery_quarantine",
    reason: fence.reason,
    retryable: fence.retryable,
    retryability_reason: fence.retryability_reason,
    anchor_job_id: fence.anchor_job_id,
    issuer: fence.issuer,
  };
  const semanticHash = await sha256Text(JSON.stringify(sourceObservation));
  const reviewDedupeKey = await sha256Text(
    `issuer-discovery-quarantine:${String(row.id)}:issuer_discovery_quarantine`,
  );
  const staged = await stageCatalogIdentityReview(db, {
    discoveryJobId: null,
    discoverySource: "issuer_crawl",
    userId: null,
    issuer,
    proposedProduct: "Issuer discovery quarantine",
    dedupeKey: reviewDedupeKey,
    semanticHash,
    proposedFields: {
      issuer,
      cardName: "Issuer discovery quarantine",
      suggested_action: sourceObservation.retryable ? "retry" : "reject",
      source_observation: sourceObservation,
    },
    sourceEvidence: { source_observation: sourceObservation },
    existingCandidates: [],
    validationWarnings: ["issuer_discovery_quarantine", fence.reason],
    confidence: 0,
    expectedJobStatus: null,
    expectedJobUpdatedAt: null,
  });
  if (
    staged.jobId === String(row.id) ||
    staged.resultingStatus !== "review_required"
  ) throw new Error("invalid_issuer_quarantine_review_stage");
  const cleared = await db.from("card_discovery_jobs").update({
    next_retry_at: null,
    updated_at: nowIso,
  }).eq("id", row.id).eq("status", "failed")
    .eq("failure_category", "issuer_discovery_quarantined")
    .contains("evidence", { quarantine_fence: fence })
    .select("id,failure_category").maybeSingle();
  if (cleared.error) throw cleared.error;
  if (!cleared.data) throw new Error("issuer_discovery_quarantine_race");
  return {
    staged: 1,
    quarantined: 1,
    conflicts: ["legacy_anchor_conflict", "anchor_identity_conflict"].includes(
        reason,
      )
      ? 1
      : 0,
    remaining: 0,
  };
}

async function terminalizeIssuerDiscoveryRows(
  db: UntypedSupabaseClient,
  rows: Array<Record<string, any>>,
  now: Date,
  reason: IssuerDiscoveryQuarantineReason,
  budget: IssuerDiscoveryQuarantineBudget,
): Promise<IssuerDiscoveryReviewSummary> {
  let summary = emptyIssuerDiscoveryReviewSummary();
  let processed = 0;
  const pendingRows = rows.filter((row) =>
    !(
      String(row.status) === "failed" &&
      String(row.failure_category ?? "") ===
        "issuer_discovery_quarantined" &&
      (row.next_retry_at === null || row.next_retry_at === undefined)
    )
  );
  for (const row of pendingRows) {
    if (!issuerQuarantineWorkMayStart(budget)) break;
    budget.used += 1;
    processed += 1;
    summary = addIssuerDiscoveryReviewSummary(
      summary,
      await terminalizeIssuerDiscoveryBacklog(db, row, now, reason),
    );
  }
  return {
    ...summary,
    remaining: summary.remaining + pendingRows.length - processed,
  };
}

function issuerRunHistoryEntry(
  evidence: Record<string, unknown>,
): Record<string, unknown> | null {
  const runDate = String(evidence.run_date ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(runDate)) return null;
  const boundedCount = (value: unknown) => {
    const count = Number(value ?? 0);
    return Number.isInteger(count) && count >= 0 ? Math.min(200, count) : 0;
  };
  return {
    run_date: runDate,
    last_outcome: String(evidence.last_outcome ?? "unknown").slice(0, 64),
    considered_count: boundedCount(evidence.considered_count),
    fetched_count: boundedCount(evidence.fetched_count),
    budget_exhausted: evidence.budget_exhausted === true,
  };
}

function boundedIssuerRunHistory(
  evidence: Record<string, unknown>,
  append?: Record<string, unknown> | null,
): Array<Record<string, unknown>> {
  const prior = Array.isArray(evidence.run_history)
    ? evidence.run_history.map((entry) =>
      entry && typeof entry === "object" && !Array.isArray(entry)
        ? issuerRunHistoryEntry(entry as Record<string, unknown>)
        : null
    ).filter((entry): entry is Record<string, unknown> => Boolean(entry))
    : [];
  const combined = append ? [...prior, append] : prior;
  return combined.slice(-24);
}

function issuerDiscoveryIssuerPattern(issuer: string): string {
  const tokens = normalizedIssuerKey(issuer).split(" ").filter(Boolean);
  if (tokens.length === 0) throw new Error("invalid_issuer_search_identity");
  const escaped = tokens.map((token) => token.replace(/[%_\\]/g, "\\$&"));
  return `%${escaped.join("%")}%`;
}

async function loadStableIssuerDiscoveryRows(
  db: UntypedSupabaseClient,
  issuer: string,
  expectedAnchorKey: string,
  budget: IssuerDiscoveryQuarantineBudget,
  pageSize = 100,
): Promise<{
  rows: Array<Record<string, any>>;
  complete: boolean;
}> {
  const rows: Array<Record<string, any>> = [];
  const issuerPattern = issuerDiscoveryIssuerPattern(issuer);
  const normalizedIssuer = normalizedIssuerKey(issuer);
  for (let offset = 0;; offset += pageSize) {
    if (budget.nowMs() >= budget.deadlineAt) {
      return { rows, complete: false };
    }
    const query = await db.from("card_discovery_jobs")
      .select(
        "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at,review_item_id",
      )
      .eq("discovery_source", "issuer_crawl")
      .is("user_id", null)
      .or(
        `issuer.ilike."${issuerPattern}",evidence->>issuer.ilike."${issuerPattern}",dedupe_key.eq.${expectedAnchorKey}`,
      )
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (query.error) throw query.error;
    const pageRows = (query.data ?? []) as Array<Record<string, any>>;
    rows.push(
      ...pageRows.filter((row) => {
        const evidence = issuerRunEvidence(row);
        return normalizedIssuerKey(row.issuer) === normalizedIssuer ||
          normalizedIssuerKey(evidence.issuer) === normalizedIssuer ||
          String(row.dedupe_key ?? "") === expectedAnchorKey;
      }),
    );
    if (pageRows.length < pageSize) return { rows, complete: true };
  }
}

function issuerQuarantineServiceReview(row: Record<string, any>): boolean {
  const evidence = issuerRunEvidence(row);
  const observation = evidence.source_observation;
  return typeof row.review_item_id === "string" &&
    row.review_item_id.length > 0 &&
    observation !== null && typeof observation === "object" &&
    !Array.isArray(observation) &&
    String((observation as Record<string, unknown>).classification ?? "") ===
      "issuer_discovery_quarantine";
}

function issuerCandidateOutcomeRow(row: Record<string, any>): boolean {
  const evidence = issuerRunEvidence(row);
  return String(evidence.kind ?? "") === "issuer_candidate_outcome" &&
    String(row.status ?? "") === "resolved" &&
    Number(row.attempt_count ?? -1) === 0 &&
    !evidence.issuer && !evidence.canonical_url && !evidence.run_date &&
    !evidence.lease_token;
}

async function loadLegacyIssuerDiscoveryRows(
  db: UntypedSupabaseClient,
  issuer: string,
  pageSize = 100,
  maxPages = 10,
): Promise<{
  rows: Array<Record<string, any>>;
  complete: boolean;
}> {
  const rows: Array<Record<string, any>> = [];
  for (let page = 0; page < maxPages; page += 1) {
    const offset = page * pageSize;
    const query = await db.from("card_discovery_jobs")
      .select(
        "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at,review_item_id",
      )
      .eq("discovery_source", "issuer_crawl")
      .ilike("issuer", issuerDiscoveryIssuerPattern(issuer))
      .is("user_id", null)
      .contains("evidence", { kind: "issuer_directory_run" })
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (query.error) throw query.error;
    const pageRows = (query.data ?? []) as Array<Record<string, any>>;
    rows.push(
      ...pageRows.filter((row) =>
        normalizedIssuerKey(row.issuer) === normalizedIssuerKey(issuer)
      ),
    );
    if (pageRows.length < pageSize) return { rows, complete: true };
  }
  return { rows, complete: false };
}

async function claimExistingIssuerDiscoveryRow(
  db: UntypedSupabaseClient,
  row: Record<string, any>,
  selected: Pick<EnrichmentJob, "issuer" | "canonical_url">,
  runDate: string,
  now: Date,
  budget: IssuerDiscoveryQuarantineBudget,
): Promise<IssuerDiscoveryClaim> {
  const rowStatus = String(row.status);
  const previousEvidence = issuerRunEvidence(row);
  if (!await issuerAnchorIdentityValid(row, selected)) {
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      [row],
      now,
      "anchor_identity_conflict",
      budget,
    );
    return { status: "quarantined", seed: null, reviewSummary };
  }
  const previousRunDate = String(previousEvidence.run_date ?? "");
  const startsNewSlot = rowStatus === "resolved" &&
    previousRunDate !== runDate;
  if (
    ["rejected", "review_required"].includes(rowStatus) ||
    (rowStatus === "resolved" && !startsNewSlot)
  ) {
    return { status: "already_completed", seed: null };
  }
  const leaseUntil = Date.parse(String(row.next_retry_at ?? ""));
  if (
    rowStatus === "failed" &&
    String(row.failure_category ?? "") === "issuer_discovery_quarantined"
  ) {
    if (row.next_retry_at === null || row.next_retry_at === undefined) {
      return { status: "quarantined", seed: null };
    }
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      [row],
      now,
      previousEvidence.quarantine_reason === "resume_attempts_exhausted" ||
        previousEvidence.quarantine_reason === "invalid_run_evidence" ||
        previousEvidence.quarantine_reason === "legacy_anchor_conflict" ||
        previousEvidence.quarantine_reason === "anchor_identity_conflict"
        ? previousEvidence.quarantine_reason
        : "invalid_run_evidence",
      budget,
    );
    return { status: "quarantined", seed: null, reviewSummary };
  }
  if (
    rowStatus === "failed" &&
    (!Number.isFinite(leaseUntil) || leaseUntil > now.getTime())
  ) return { status: "backoff", seed: null };
  if (
    rowStatus === "discovering" && Number.isFinite(leaseUntil) &&
    leaseUntil > now.getTime()
  ) return { status: "already_running", seed: null };
  if (
    !startsNewSlot &&
    Number(row.attempt_count ?? 0) >= ISSUER_DISCOVERY_MAX_ATTEMPTS
  ) {
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      [row],
      now,
      "resume_attempts_exhausted",
      budget,
    );
    return { status: "resume_exhausted", seed: null, reviewSummary };
  }
  const previousLeaseToken = String(previousEvidence.lease_token ?? "");
  const nextLeaseToken = crypto.randomUUID();
  const activeRunDate = startsNewSlot
    ? runDate
    : /^\d{4}-\d{2}-\d{2}$/.test(previousRunDate)
    ? previousRunDate
    : runDate;
  const previousHistoryEntry = startsNewSlot
    ? issuerRunHistoryEntry(previousEvidence)
    : null;
  const runAttempt = startsNewSlot ? 1 : Number(row.attempt_count ?? 0) + 1;
  const evidence = {
    ...(startsNewSlot
      ? {
        run_history: boundedIssuerRunHistory(
          previousEvidence,
          previousHistoryEntry,
        ),
        outcome_summaries: [],
        outcome_counts: {},
        last_processed_candidate_identity: null,
        incomplete_reasons: [],
        considered_count: 0,
        fetched_count: 0,
        resumed_count: 0,
        budget_exhausted: false,
      }
      : previousEvidence),
    kind: "issuer_directory_anchor",
    issuer: selected.issuer,
    canonical_url: selected.canonical_url,
    run_date: activeRunDate,
    rotation_slot: Math.floor(
      Date.parse(`${activeRunDate}T00:00:00.000Z`) / 86_400_000,
    ),
    run_attempt: runAttempt,
    lease_token: nextLeaseToken,
    last_attempt_at: now.toISOString(),
  };
  let update = db.from("card_discovery_jobs").update({
    status: "discovering",
    attempt_count: runAttempt,
    next_retry_at: new Date(
      now.getTime() + ISSUER_DISCOVERY_LEASE_MS,
    ).toISOString(),
    failure_category: null,
    evidence,
    updated_at: now.toISOString(),
  }).eq("id", row.id).eq("status", rowStatus);
  if (issuerLeaseTokenPattern.test(previousLeaseToken)) {
    update = update.contains("evidence", { lease_token: previousLeaseToken });
  }
  if (row.updated_at) update = update.eq("updated_at", row.updated_at);
  const claimed = await update.select(
    "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at",
  ).maybeSingle();
  if (claimed.error) throw claimed.error;
  return claimed.data
    ? {
      status: "claimed",
      seed: issuerDiscoverySeedFromRow(
        claimed.data,
        selected,
        activeRunDate,
      ),
    }
    : { status: "already_running", seed: null };
}

export async function loadIssuerDiscoveryBacklog(
  db: UntypedSupabaseClient,
  now = new Date(),
  pageSize = ISSUER_DISCOVERY_BACKLOG_PAGE_SIZE,
  maxPages = ISSUER_DISCOVERY_BACKLOG_MAX_PAGES,
): Promise<Array<Record<string, any>>> {
  if (
    !Number.isFinite(now.getTime()) || !Number.isInteger(pageSize) ||
    pageSize < 1 || pageSize > 500 || !Number.isInteger(maxPages) ||
    maxPages < 1 || maxPages > 20
  ) throw new Error("invalid_issuer_backlog_request");
  const rows: Array<Record<string, any>> = [];
  for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
    const offset = pageIndex * pageSize;
    const query = await db.from("card_discovery_jobs")
      .select(
        "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at",
      )
      .eq("discovery_source", "issuer_crawl")
      .is("user_id", null)
      .in("status", ["failed", "discovering"])
      .lte("next_retry_at", now.toISOString())
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + pageSize - 1);
    if (query.error) throw query.error;
    const page = (query.data ?? []) as Array<Record<string, any>>;
    rows.push(
      ...page.filter((row) =>
        ["issuer_directory_run", "issuer_directory_anchor"].includes(
          String(issuerRunEvidence(row).kind ?? ""),
        )
      ),
    );
    if (page.length < pageSize) break;
  }
  return rows.sort((left, right) => {
    const leftEvidence = issuerRunEvidence(left);
    const rightEvidence = issuerRunEvidence(right);
    return String(leftEvidence.run_date ?? left.created_at ?? "").localeCompare(
      String(rightEvidence.run_date ?? right.created_at ?? ""),
    ) || String(left.created_at ?? "").localeCompare(
      String(right.created_at ?? ""),
    ) || String(left.id ?? "").localeCompare(String(right.id ?? ""));
  });
}

export async function claimIssuerDiscoveryRun(
  db: UntypedSupabaseClient,
  selected: Pick<EnrichmentJob, "issuer" | "canonical_url">,
  now = new Date(),
  options: IssuerDiscoveryClaimOptions = {},
): Promise<IssuerDiscoveryClaim> {
  const budget = issuerDiscoveryQuarantineBudget(options);
  const runDate = utcIssuerRunDate(now);
  const key = await sha256Text(
    `issuer-directory-anchor:${normalizedIssuerKey(selected.issuer)}`,
  );
  const loadExisting = async (): Promise<Record<string, any> | null> => {
    const existing = await db.from("card_discovery_jobs")
      .select(
        "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at",
      )
      .eq("discovery_source", "issuer_crawl")
      .eq("dedupe_key", key)
      .is("user_id", null)
      .maybeSingle();
    if (existing.error) throw existing.error;
    return existing.data ?? null;
  };
  const stableScan = await loadStableIssuerDiscoveryRows(
    db,
    selected.issuer,
    key,
    budget,
  );
  if (!stableScan.complete) {
    throw new Error("issuer_discovery_stable_scan_exhausted");
  }
  const corruptStableRows: Array<Record<string, any>> = [];
  const validStableRows: Array<Record<string, any>> = [];
  const stableRows = stableScan.rows.filter((row) => {
    if (
      issuerQuarantineServiceReview(row) || issuerCandidateOutcomeRow(row)
    ) return false;
    return String(row.dedupe_key ?? "") === key ||
      String(issuerRunEvidence(row).kind ?? "") !== "issuer_directory_run";
  });
  for (const row of stableRows) {
    if (await issuerAnchorIdentityValid(row, selected)) {
      validStableRows.push(row);
    } else {
      corruptStableRows.push(row);
    }
  }
  if (corruptStableRows.length > 0) {
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      corruptStableRows,
      now,
      "anchor_identity_conflict",
      budget,
    );
    return { status: "quarantined", seed: null, reviewSummary };
  }
  if (validStableRows.length > 1) {
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      validStableRows.slice(1),
      now,
      "anchor_identity_conflict",
      budget,
    );
    return { status: "quarantined", seed: null, reviewSummary };
  }
  let previous: Record<string, any> | null = validStableRows[0] ?? null;
  const legacyScan = await loadLegacyIssuerDiscoveryRows(db, selected.issuer);
  if (!legacyScan.complete) {
    throw new Error("issuer_discovery_legacy_scan_exhausted");
  }
  const issuerRows = legacyScan.rows;
  const legacyRows = issuerRows.filter((row) => String(row.dedupe_key) !== key);
  const activeLegacy = legacyRows.filter((row) => {
    const retryAt = Date.parse(String(row.next_retry_at ?? ""));
    return String(row.status) === "discovering" &&
      Number.isFinite(retryAt) && retryAt > now.getTime();
  });
  if (activeLegacy.length > 0) {
    return { status: "already_running", seed: null };
  }
  const unfinishedLegacy = legacyRows.filter((row) => {
    const status = String(row.status);
    const retryAt = Date.parse(String(row.next_retry_at ?? ""));
    return (status === "failed" || status === "discovering") &&
      Number.isFinite(retryAt) && retryAt <= now.getTime();
  });

  if (previous && unfinishedLegacy.length > 0) {
    const conflictRows = unfinishedLegacy;
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      conflictRows,
      now,
      "legacy_anchor_conflict",
      budget,
    );
    return { status: "legacy_conflict", seed: null, reviewSummary };
  }
  if (previous) {
    return await claimExistingIssuerDiscoveryRow(
      db,
      previous,
      selected,
      runDate,
      now,
      budget,
    );
  }

  if (unfinishedLegacy.length > 1) {
    const reviewSummary = await terminalizeIssuerDiscoveryRows(
      db,
      unfinishedLegacy,
      now,
      "legacy_anchor_conflict",
      budget,
    );
    return { status: "legacy_conflict", seed: null, reviewSummary };
  }
  if (unfinishedLegacy.length === 1) {
    const legacy = unfinishedLegacy[0];
    const leaseUntil = Date.parse(String(legacy.next_retry_at ?? ""));
    if (
      legacy.status === "discovering" && Number.isFinite(leaseUntil) &&
      leaseUntil > now.getTime()
    ) return { status: "already_running", seed: null };
    const legacyEvidence = issuerRunEvidence(legacy);
    let migrate = db.from("card_discovery_jobs").update({
      dedupe_key: key,
      evidence: {
        ...legacyEvidence,
        kind: "issuer_directory_anchor",
        issuer: selected.issuer,
        canonical_url: selected.canonical_url,
        legacy_reconciliation_complete: true,
        run_history: [
          ...boundedIssuerRunHistory(legacyEvidence),
          ...legacyRows.filter((row) => row.id !== legacy.id).map((row) =>
            issuerRunHistoryEntry(issuerRunEvidence(row))
          ).filter((entry): entry is Record<string, unknown> => Boolean(entry)),
        ].slice(-24),
      },
      updated_at: now.toISOString(),
    }).eq("id", legacy.id).eq("dedupe_key", legacy.dedupe_key)
      .eq("status", legacy.status);
    if (legacy.updated_at) {
      migrate = migrate.eq("updated_at", legacy.updated_at);
    }
    const migrated = await migrate.select(
      "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at",
    ).maybeSingle();
    if (migrated.error?.code === "23505") {
      previous = await loadExisting();
      return previous
        ? await claimExistingIssuerDiscoveryRow(
          db,
          previous,
          selected,
          runDate,
          now,
          budget,
        )
        : { status: "already_running", seed: null };
    }
    if (migrated.error) throw migrated.error;
    if (!migrated.data) return { status: "already_running", seed: null };
    const identity = issuerRunIdentity(migrated.data);
    return await claimExistingIssuerDiscoveryRow(
      db,
      migrated.data,
      selected,
      identity?.runDate ?? runDate,
      now,
      budget,
    );
  }

  const leaseToken = crypto.randomUUID();
  const legacyHistory = legacyRows.map((row) =>
    issuerRunHistoryEntry(issuerRunEvidence(row))
  ).filter((entry): entry is Record<string, unknown> => Boolean(entry)).slice(
    -24,
  );
  const evidence = {
    kind: "issuer_directory_anchor",
    issuer: selected.issuer,
    canonical_url: selected.canonical_url,
    run_date: runDate,
    rotation_slot: Math.floor(
      Date.parse(`${runDate}T00:00:00.000Z`) / 86_400_000,
    ),
    run_attempt: 1,
    run_history: legacyHistory,
    legacy_reconciliation_complete: true,
    lease_token: leaseToken,
    last_attempt_at: now.toISOString(),
    outcome_summaries: [],
  };
  const inserted = await db.from("card_discovery_jobs").insert({
    user_id: null,
    discovery_source: "issuer_crawl",
    issuer: selected.issuer,
    proposed_product: "issuer directory run",
    evidence,
    dedupe_key: key,
    status: "discovering",
    attempt_count: 1,
    next_retry_at: new Date(
      now.getTime() + ISSUER_DISCOVERY_LEASE_MS,
    ).toISOString(),
    updated_at: now.toISOString(),
  }).select(
    "id,issuer,evidence,status,failure_category,updated_at,next_retry_at,attempt_count,dedupe_key,created_at",
  ).maybeSingle();
  if (!inserted.error && inserted.data) {
    return {
      status: "claimed",
      seed: issuerDiscoverySeedFromRow(inserted.data, selected, runDate),
    };
  }
  if (inserted.error?.code !== "23505") {
    throw inserted.error ?? new Error("issuer_discovery_claim_failed");
  }
  const raced = await loadExisting();
  if (!raced) throw new Error("issuer_discovery_claim_race");
  return await claimExistingIssuerDiscoveryRow(
    db,
    raced,
    selected,
    runDate,
    now,
    budget,
  );
}

export async function loadDiscoverySeed(
  db: UntypedSupabaseClient,
  now = new Date(),
  pageSize = 200,
  options: IssuerDiscoveryClaimOptions = {},
): Promise<IssuerDiscoveryClaim> {
  const quarantineBudget = issuerDiscoveryQuarantineBudget(options);
  const claimOptions = { ...options, quarantineBudget };
  let reviewSummary = emptyIssuerDiscoveryReviewSummary();
  const backlog = await loadIssuerDiscoveryBacklog(db, now);
  for (let index = 0; index < backlog.length; index += 1) {
    const row = backlog[index];
    const identity = issuerRunIdentity(row);
    if (!identity) {
      reviewSummary = addIssuerDiscoveryReviewSummary(
        reviewSummary,
        await terminalizeIssuerDiscoveryRows(
          db,
          [row],
          now,
          "invalid_run_evidence",
          quarantineBudget,
        ),
      );
      if (!issuerQuarantineWorkMayStart(quarantineBudget)) {
        return {
          status: "quarantined",
          seed: null,
          reviewSummary: {
            ...reviewSummary,
            remaining: reviewSummary.remaining + backlog.length - index - 1,
          },
        };
      }
      continue;
    }
    if (
      String(issuerRunEvidence(row).kind ?? "") ===
        "issuer_directory_anchor" &&
      !await issuerAnchorIdentityValid(row, identity.selected)
    ) {
      reviewSummary = addIssuerDiscoveryReviewSummary(
        reviewSummary,
        await terminalizeIssuerDiscoveryRows(
          db,
          [row],
          now,
          "anchor_identity_conflict",
          quarantineBudget,
        ),
      );
      return { status: "quarantined", seed: null, reviewSummary };
    }
    const claim = await claimIssuerDiscoveryRun(
      db,
      identity.selected,
      now,
      claimOptions,
    );
    reviewSummary = addIssuerDiscoveryReviewSummary(
      reviewSummary,
      claim.reviewSummary,
    );
    if (claim.seed) return { ...claim, reviewSummary };
    if (claim.status === "legacy_conflict") {
      return { ...claim, reviewSummary };
    }
    if (claim.status === "already_completed") continue;
  }
  const rows = await loadApprovedIssuerCatalog(db, pageSize);
  const selected = selectIssuerDiscoveryCandidate(rows, now);
  if (!selected) return { status: "empty", seed: null, reviewSummary };
  const claim = await claimIssuerDiscoveryRun(db, selected, now, claimOptions);
  return {
    ...claim,
    reviewSummary: addIssuerDiscoveryReviewSummary(
      reviewSummary,
      claim.reviewSummary,
    ),
  };
}

export async function handleBenefitEnrichmentBatch(
  request: Request,
): Promise<Response> {
  const invocationStartedAt = Date.now();
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const cronSecret = Deno.env.get("BENEFIT_ENRICHMENT_CRON_SECRET") ?? "";
  if (!await authorizedSchedulerRequest(request, serviceKey, cronSecret)) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    // An empty scheduler body selects the scheduled lane.
  }
  let runMode = runModeFromRequest(body.runMode ?? body.run_mode);
  if (!runMode) return json({ error: "invalid_run_mode" }, 400);

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
  const runId = crypto.randomUUID();
  try {
    if (body.action === "issuer_discovery") {
      const issuerMode = issuerDiscoveryRunMode(body);
      if (!issuerMode) {
        return json({ error: "invalid_issuer_discovery_request" }, 400);
      }
      const claim = await loadDiscoverySeed(db, new Date(), 200, {
        deadlineAt: invocationStartedAt + INVOCATION_DEADLINE_MS,
      });
      const discoveryState = issuerDiscoveryResponseSummary(claim);
      if (!claim.seed) {
        return json({
          runId,
          action: "issuer_discovery",
          runMode: issuerMode,
          claimed: 0,
          ...discoveryState,
          claimStatus: claim.status,
        });
      }
      const summary = await runIssuerDiscovery(
        db,
        claim.seed,
        invocationStartedAt + INVOCATION_DEADLINE_MS,
      );
      return json({
        runId,
        action: "issuer_discovery",
        runMode: issuerMode,
        claimed: 1,
        ...discoveryState,
        noWork: false,
        claimStatus: claim.status,
        summary,
      });
    }
    if (body.action === "initialize_pilot") {
      if (!Array.isArray(body.candidates)) {
        return json({ error: "invalid_pilot_candidates" }, 400);
      }
      const requestedParserVersion = typeof body.parserVersion === "string"
        ? body.parserVersion.trim()
        : CURRENT_BENEFIT_PARSER_VERSION;
      if (requestedParserVersion !== CURRENT_BENEFIT_PARSER_VERSION) {
        return json({ error: "unsupported_pilot_parser_version" }, 400);
      }
      await initializePilotJobs(
        db,
        body.candidates as PilotCandidate[],
        requestedParserVersion,
      );
      runMode = "pilot";
    }
    await requeueDueJobs(db, new Date());
    const pilot = await readPilotStatus(db);
    if (runMode === "scheduled" && !pilot.scheduledClaimAllowed) {
      return json({
        runId,
        queued: 0,
        claimed: 0,
        staged: 0,
        quarantined: 0,
        failed: 0,
        retried: 0,
        pilotStatus: pilot.status,
      });
    }
    if (runMode === "scheduled") {
      await promoteQualifiedPilotJobs(
        db,
        CURRENT_BENEFIT_PARSER_VERSION,
      );
    }

    await seedScheduledQueueIfAllowed(
      db,
      runMode,
      pilot.scheduledClaimAllowed,
      200,
      CURRENT_BENEFIT_PARSER_VERSION,
    );

    const { count: queued, error: countError } = await db
      .from("card_catalog_enrichment_jobs")
      .select("id", { count: "exact", head: true })
      .eq("run_mode", runMode)
      .eq("parser_version", CURRENT_BENEFIT_PARSER_VERSION)
      .in("status", ["queued", "failed"])
      .or(
        `next_retry_at.is.null,next_retry_at.lte.${new Date().toISOString()}`,
      );
    if (countError) throw countError;

    const { data: claimed, error: claimError } = await db.rpc(
      "claim_card_catalog_enrichment_jobs",
      {
        _max_jobs: claimLimitForInvocation(runMode),
        _lease_seconds: LEASE_SECONDS,
        _run_mode: runMode,
        _parser_version: CURRENT_BENEFIT_PARSER_VERSION,
      },
    );
    if (claimError) throw claimError;
    const jobs = (claimed ?? []) as EnrichmentJob[];
    const results = await runSequentially(
      jobs,
      async (job) => {
        try {
          return await processJob(db, job, runId, invocationStartedAt);
        } catch {
          // A failed final database write cannot be repaired in-memory, but it
          // must not stop later claimed rows from reaching their finally path.
          return { outcome: "failed", retried: false } as ProcessResult;
        }
      },
    );
    const finalPilot = await readPilotStatus(db);
    return json({
      runId,
      queued: Number(queued ?? 0),
      claimed: jobs.length,
      staged: results.filter((result) => result.outcome === "staged").length,
      completed: results.filter((result) => result.outcome === "completed")
        .length,
      quarantined: results.filter((result) =>
        result.outcome === "quarantined"
      ).length,
      failed: results.filter((result) =>
        result.outcome === "failed" || result.outcome === "review_required"
      ).length,
      retried: results.filter((result) => result.retried).length,
      pilotStatus: finalPilot.status,
    });
  } catch (error) {
    return json({
      runId,
      error: safeFailureCategory(error),
    }, 500);
  }
}

if (import.meta.main) {
  serve(handleBenefitEnrichmentBatch);
}
