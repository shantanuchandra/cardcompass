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
  issuerDiscoveryFallbackUrls,
  persistCrawlerCandidate,
} from "../_shared/issuer_card_crawl.ts";
import {
  approvedStoredQueryParameters,
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

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

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

async function authorized(
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

function pilotJob(row: Record<string, any>): PilotJob {
  const summary = row.result_summary && typeof row.result_summary === "object"
    ? row.result_summary
    : {};
  return {
    id: String(row.id),
    runMode: row.run_mode,
    status: String(row.status),
    quarantineReason: row.status === "quarantined"
      ? String(row.failure_category ?? "").trim() || null
      : null,
    unsafeMutationCount: Number(summary.unsafe_mutation_count ?? 0),
    idempotencyPassed: summary.idempotency_passed === true,
    evidencePassed: summary.evidence_passed === true,
    rawBodyStored: summary.raw_body_stored === true,
  };
}

export async function readPilotStatus(
  db: UntypedSupabaseClient,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
) {
  assertBenefitParserVersion(parserVersion);
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .select("id,run_mode,status,failure_category,result_summary")
    .eq("run_mode", "pilot")
    .eq("parser_version", parserVersion);
  if (error) throw error;
  return evaluatePilotGate((data ?? []).map(pilotJob));
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
  const stableAttempts = attempts.map(({
    attemptedAt: _attemptedAt,
    ...attempt
  }) => attempt).map((attempt) => JSON.stringify(attempt)).sort();
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
  const byTimestamp = new Map<string, Record<string, unknown>>();
  for (const observation of summaries.flatMap(observationObjects)) {
    const observedAt = typeof observation.observed_at === "string"
      ? observation.observed_at
      : "";
    const timestamp = utcInstant(observedAt);
    if (
      timestamp === null ||
      timestamp > assessmentTimestamp + MAX_EVIDENCE_CLOCK_SKEW_MS ||
      byTimestamp.has(observedAt)
    ) {
      continue;
    }
    byTimestamp.set(observedAt, observation);
  }
  return [...byTimestamp.entries()].sort((left, right) =>
    Number(utcInstant(right[0])) - Number(utcInstant(left[0]))
  ).slice(0, 24).map(([, observation]) => observation);
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
  previousStagingId: string | null | undefined,
): boolean {
  return !previousStagingId || !previousCanonicalHash ||
    previousCanonicalHash !== canonicalHash;
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

export function rawOnlyNextRunAt(observedAt: string): string {
  const observed = Date.parse(observedAt);
  if (!Number.isFinite(observed) || !observedAt.endsWith("Z")) {
    throw new Error("invalid_observation_timestamp");
  }
  return new Date(observed + 30 * 24 * 60 * 60 * 1000).toISOString();
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
  const previousObservation = observationObjects(input.job.result_summary).at(
    -1,
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
    .select("card_id,parser_version")
    .eq("run_mode", "pilot")
    .eq("parser_version", parserVersion);
  if (pilotError) throw pilotError;
  const pilotIdentities = new Set(
    (pilotRows ?? []).map((row: Record<string, unknown>) =>
      `${String(row.card_id)}:${String(row.parser_version)}`
    ),
  );
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
    await enqueueBenefitEnrichmentJobs(db, queueInputs);
    seeded += queueInputs.length;
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
    .select("id,card_name,bank")
    .ilike("bank", String(card.bank))
    .eq("is_discontinued", false);
  if (catalogError) throw catalogError;
  const catalog = (catalogRows ?? []).filter((row: Record<string, unknown>) =>
    String(row.bank ?? "").trim().toLowerCase() ===
      String(card.bank).trim().toLowerCase()
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
  catalog: Array<{ id: string; card_name: string }>,
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
  );
}

export function requireExactCatalogIdentity(
  targetCardId: string,
  issuer: string,
  proposedName: string,
  catalog: Array<{ id: string; card_name: string }>,
  aliases: Array<{ card_id: string; alias: string }>,
): void {
  const exactProduct = (value: string): string => {
    const base = normalizedProduct(value, issuer);
    const networks = [
      /\b(?:amex|american\s+express)\b/i.test(value) ? "amex" : "",
      /\bmastercard\b/i.test(value) ? "mastercard" : "",
      /\brupay\b/i.test(value) ? "rupay" : "",
      /\bvisa\b/i.test(value) ? "visa" : "",
    ].filter(Boolean).sort();
    return [base, ...networks].join("|");
  };
  const proposedBase = normalizedProduct(proposedName, issuer);
  const proposed = exactProduct(proposedName);
  if (proposedBase.length < 2) throw new Error("identity_mismatch");
  const activeIds = new Set(catalog.map((row) => String(row.id)));
  const matches = new Set<string>();
  for (const row of catalog) {
    if (exactProduct(row.card_name) === proposed) {
      matches.add(String(row.id));
    }
  }
  for (const alias of aliases) {
    if (
      activeIds.has(String(alias.card_id)) &&
      exactProduct(alias.alias) === proposed
    ) {
      matches.add(String(alias.card_id));
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
} | undefined {
  const previousObservation = observationObjects(job.result_summary).at(-1);
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
  return {
    parserVersion,
    ...(etag ? { etag } : {}),
    ...(lastModified ? { lastModified } : {}),
    ...(contentHash ? { contentHash } : {}),
    reusableExtraction: previousObservation?.crawl_complete === true &&
      typeof canonicalBenefitHash === "string" &&
      /^[0-9a-f]{64}$/i.test(canonicalBenefitHash) && Boolean(contentHash),
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

async function processJob(
  db: UntypedSupabaseClient,
  job: EnrichmentJob,
  runId: string,
  invocationStartedAt: number,
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
    const fetchObservation = await fetchOfficialIssuerObservation({
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
      const previousObservation = observationObjects(job.result_summary).at(-1);
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
      const nextRunAt = rawOnlyNextRunAt(observedAt);
      const { error: dueDateError } = await db
        .from("card_catalog_enrichment_jobs")
        .update({ next_run_at: nextRunAt })
        .eq("id", job.id)
        .eq("status", "processing")
        .eq("lease_token", job.lease_token);
      if (dueDateError) throw dueDateError;
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
        next_run_at: nextRunAt,
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
      outcome = fetchObservation.disposition === "blocked"
        ? "quarantined"
        : fetchObservation.disposition === "review_required"
        ? "review_required"
        : "failed";
      return { outcome, retried: false };
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
    const previousObservation = observationObjects(job.result_summary).at(-1);
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
    let reusedStaging = false;
    let rawOnlyDueAt: string | null = null;
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
      stagingId = proposalDisposition === "no_change"
        ? null
        : String(job.staging_id);
      reusedStaging = proposalDisposition !== "no_change";
      rawOnlyDueAt = rawOnlyNextRunAt(validatedAt);
      const { error: dueDateError } = await db
        .from("card_catalog_enrichment_jobs")
        .update({ next_run_at: rawOnlyDueAt })
        .eq("id", job.id)
        .eq("status", "processing")
        .eq("lease_token", job.lease_token);
      if (dueDateError) throw dueDateError;
    }
    outcome = proposalDisposition === "no_change" ? "completed" : "staged";
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
      proposal_disposition: proposalDisposition,
      successful_no_change: proposalDisposition === "no_change",
      ...(rawOnlyDueAt ? { next_run_at: rawOnlyDueAt } : {}),
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

async function runIssuerDiscovery(
  db: UntypedSupabaseClient,
  job: Pick<EnrichmentJob, "issuer" | "canonical_url">,
  deadlineAt: number,
): Promise<void> {
  const fallback = issuerDiscoveryFallbackUrls(job.canonical_url);
  const result = await discoverIssuerCardCandidates({
    issuer: job.issuer,
    sitemapUrls: fallback.sitemapUrls,
    indexUrls: fallback.indexUrls,
    deadlineAt,
  });
  for (const candidate of result.candidates) {
    if (candidate.kind === "card_product") {
      await persistCrawlerCandidate(db, job.issuer, candidate);
    }
  }
}

async function loadDiscoverySeed(
  db: UntypedSupabaseClient,
): Promise<Pick<EnrichmentJob, "issuer" | "canonical_url"> | null> {
  const { data, error } = await db.from("card_catalog")
    .select("bank,card_url,card_type")
    .eq("is_discontinued", false)
    .not("card_url", "is", null)
    .order("bank", { ascending: true })
    .limit(100);
  if (error) throw error;
  for (const row of data ?? []) {
    const issuer = String(row.bank ?? "");
    const url = String(row.card_url ?? "");
    if (
      String(row.card_type ?? "").trim().toLowerCase() === "credit" &&
      allowedOfficialUrl(issuer, url)
    ) {
      return { issuer, canonical_url: canonicalOfficialUrl(issuer, url) };
    }
  }
  return null;
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
  if (!await authorized(request, serviceKey, cronSecret)) {
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
    // Issuer-wide discovery can inspect dozens of pages. Run it only on an
    // otherwise idle invocation so it cannot compete with card enrichment for
    // the Edge worker's compute and memory budget.
    if (
      jobs.length === 0 && Number(queued ?? 0) === 0 &&
      networkWorkMayStart(invocationStartedAt)
    ) {
      const discoverySeed = await loadDiscoverySeed(db);
      if (discoverySeed) {
        EdgeRuntime.waitUntil(
          runIssuerDiscovery(
            db,
            discoverySeed,
            invocationStartedAt + INVOCATION_DEADLINE_MS,
          ).catch((error) => {
            console.error(JSON.stringify({
              event: "issuer_discovery_background_failed",
              run_id: runId,
              category: safeFailureCategory(error),
            }));
          }),
        );
      }
    }
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
