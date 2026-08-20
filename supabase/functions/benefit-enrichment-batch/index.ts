import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @deno-types="data:application/typescript,export%20declare%20function%20createClient(...args%3A%20any%5B%5D)%3A%20any%3B"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?bundle&target=deno&no-dts";
import {
  type BenefitComparisonProposal,
  type BenefitDiff,
  type BenefitDocument,
  canonicalBenefitReplayText,
  currentBenefitProposal,
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
} from "../_shared/benefit_enrichment.ts";
export { currentBenefitProposal } from "../_shared/benefit_enrichment.ts";
import {
  cardScopedBenefitKey,
  stableCanonicalJson,
} from "../_shared/benefit_contract.ts";
import {
  redactSensitiveUrlsInText,
  safeHttpsDisplayUrl,
} from "../_shared/benefit_source_privacy.ts";
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
  sourceIdentityDigest,
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
  normalized_fields?: Record<string, unknown> | null;
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

function validatedPilotSnapshot(value: unknown): PilotLiveStateSnapshot | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  const output = {} as PilotLiveStateSnapshot;
  for (const table of pilotSnapshotTables) {
    const item = input[table];
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const snapshot = item as Record<string, unknown>;
    if (
      !Number.isInteger(snapshot.count) || Number(snapshot.count) < 0 ||
      Number(snapshot.count) > 512 ||
      typeof snapshot.row_hash !== "string" ||
      !lowercaseSha256.test(snapshot.row_hash)
    ) return null;
    output[table] = {
      count: Number(snapshot.count),
      row_hash: snapshot.row_hash,
    };
  }
  return output;
}

const pilotSourceAttemptKeys = new Set([
  "url",
  "role",
  "status",
  "httpStatus",
  "contentHash",
  "finalResourceIdentityHash",
  "errorCode",
  "attemptedAt",
  "parserCacheReusable",
  "logicalSourceKey",
  "attemptHistory",
  "attemptHistoryOverflow",
]);
const pilotAttemptHistoryKeys = new Set([
  "status",
  "httpStatus",
  "errorCode",
  "finalResourceIdentityHash",
  "attemptedAt",
]);

function validPilotAttemptHistory(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const event = value as Record<string, unknown>;
  return Object.keys(event).every((key) => pilotAttemptHistoryKeys.has(key)) &&
    ["success", "not_modified", "failed"].includes(String(event.status)) &&
    typeof event.attemptedAt === "string" &&
    utcInstant(event.attemptedAt) !== null &&
    (event.httpStatus === undefined ||
      (Number.isInteger(event.httpStatus) && Number(event.httpStatus) >= 100 &&
        Number(event.httpStatus) <= 599)) &&
    (event.errorCode === undefined ||
      (typeof event.errorCode === "string" &&
        /^[a-z0-9_]{1,64}$/.test(event.errorCode))) &&
    (event.finalResourceIdentityHash === undefined ||
      (typeof event.finalResourceIdentityHash === "string" &&
        lowercaseSha256.test(event.finalResourceIdentityHash)));
}

function validPilotSourceAttempt(value: unknown): value is SourceAttempt {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const attempt = value as Record<string, unknown>;
  const safeUrl = typeof attempt.url === "string"
    ? boundedSourceUrl(attempt.url)
    : "invalid-source";
  return Object.keys(attempt).every((key) => pilotSourceAttemptKeys.has(key)) &&
    safeUrl !== "invalid-source" && safeUrl === attempt.url &&
    ["primary", "required_supporting", "supporting"].includes(
      String(attempt.role),
    ) && ["success", "not_modified", "failed"].includes(
      String(attempt.status),
    ) && typeof attempt.attemptedAt === "string" &&
    utcInstant(attempt.attemptedAt) !== null &&
    (attempt.httpStatus === undefined ||
      (Number.isInteger(attempt.httpStatus) &&
        Number(attempt.httpStatus) >= 100 &&
        Number(attempt.httpStatus) <= 599)) &&
    (attempt.contentHash === undefined ||
      (typeof attempt.contentHash === "string" &&
        lowercaseSha256.test(attempt.contentHash))) &&
    (attempt.logicalSourceKey === undefined ||
      (typeof attempt.logicalSourceKey === "string" &&
        lowercaseSha256.test(attempt.logicalSourceKey))) &&
    (attempt.finalResourceIdentityHash === undefined ||
      (typeof attempt.finalResourceIdentityHash === "string" &&
        lowercaseSha256.test(attempt.finalResourceIdentityHash))) &&
    (attempt.errorCode === undefined ||
      (typeof attempt.errorCode === "string" &&
        /^[a-z0-9_]{1,64}$/.test(attempt.errorCode))) &&
    (attempt.parserCacheReusable === undefined ||
      typeof attempt.parserCacheReusable === "boolean") &&
    (attempt.attemptHistoryOverflow === undefined ||
      typeof attempt.attemptHistoryOverflow === "boolean") &&
    (attempt.attemptHistory === undefined ||
      (Array.isArray(attempt.attemptHistory) &&
        attempt.attemptHistory.length <= 6 &&
        attempt.attemptHistory.every(validPilotAttemptHistory)));
}

function decisivePilotSourceSucceeded(attempt: SourceAttempt): boolean {
  return (attempt.status === "success" ||
    (attempt.status === "not_modified" &&
      attempt.parserCacheReusable === true)) &&
    lowercaseSha256.test(attempt.contentHash ?? "") &&
    lowercaseSha256.test(attempt.logicalSourceKey ?? "") &&
    lowercaseSha256.test(attempt.finalResourceIdentityHash ?? "");
}

const pilotEvidenceKeys = new Set([
  "parser_version",
  "job_id",
  "card_id",
  "run_mode",
  "canonical_hash",
  "repeat_canonical_hash",
  "deterministic_replay_passed",
  "source_manifest_hash",
  "source_attempts",
  "expected_required_source_keys",
  "required_source_selection_overflow",
  "verification_envelope",
  "repeat_verification_envelope",
  "replay_input",
  "crawl_complete",
  "suppressed_removal_count",
  "unsafe_mutation_count",
  "raw_body_stored",
  "side_effect_proof_passed",
  "observed_at",
  "live_state_before",
  "live_state_after",
  "conflict_count",
  "catalog_identity_conflict_count",
  "proposal_count",
  "proposal_disposition",
  "canonical_benefit_hash",
  "previous_canonical_benefit_hash",
  "staging_id",
  "staging_content_hash",
]);

const pilotVerificationEnvelopeKeys = new Set([
  "parser_version",
  "job_id",
  "card_id",
  "run_mode",
  "source_manifest_hash",
  "source_resources",
  "retained_documents",
  "expected_required_source_keys",
  "required_source_selection_overflow",
  "replay_input_hash",
  "canonical_proposals",
]);

function pilotRequiredSourceKeys(
  attempts: readonly SourceAttempt[],
): string[] {
  return [
    ...new Set(
      attempts.filter((attempt) => attempt.role === "required_supporting").map((
        attempt,
      ) => attempt.logicalSourceKey ?? ""),
    ),
  ]
    .filter((key) => lowercaseSha256.test(key)).sort();
}

const retainedDocumentKeys = new Set([
  "requested_resource_identity_hash",
  "final_resource_identity_hash",
  "content_hash",
  "document_text_hash",
  "document_bytes",
]);

function validRetainedDocumentEnvelope(
  value: unknown,
  attempts: readonly SourceAttempt[],
): value is Record<string, unknown>[] {
  const decisiveAttemptCount =
    attempts.filter(decisivePilotSourceSucceeded).length;
  if (
    !Array.isArray(value) || value.length > 9 ||
    value.length !== decisiveAttemptCount
  ) return false;
  return value.every((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return false;
    const document = item as Record<string, unknown>;
    if (
      Object.keys(document).length !== retainedDocumentKeys.size ||
      !Object.keys(document).every((key) => retainedDocumentKeys.has(key)) ||
      !lowercaseSha256.test(
        String(document.requested_resource_identity_hash),
      ) ||
      !lowercaseSha256.test(String(document.final_resource_identity_hash)) ||
      !lowercaseSha256.test(String(document.content_hash)) ||
      !lowercaseSha256.test(String(document.document_text_hash)) ||
      !Number.isInteger(document.document_bytes) ||
      Number(document.document_bytes) < 0 ||
      Number(document.document_bytes) > 1_048_576
    ) return false;
    return attempts.filter((attempt) =>
      decisivePilotSourceSucceeded(attempt) &&
      attempt.logicalSourceKey === document.requested_resource_identity_hash &&
      attempt.finalResourceIdentityHash ===
        document.final_resource_identity_hash &&
      attempt.contentHash === document.content_hash
    ).length === 1;
  }) && new Set(value.map((item) =>
        stableCanonicalJson(item)
      )).size === value.length;
}

function validPilotRequiredSourceKeys(value: unknown): value is string[] {
  return Array.isArray(value) && value.length <= 8 &&
    value.every((key) =>
      typeof key === "string" && lowercaseSha256.test(key)
    ) &&
    new Set(value).size === value.length &&
    value.every((key, index) => index === 0 || value[index - 1] < key);
}

function validPilotVerificationEnvelope(
  value: unknown,
  binding: {
    parserVersion: unknown;
    jobId: unknown;
    cardId: unknown;
    runMode: unknown;
    sourceManifestHash: unknown;
    sourceAttempts: readonly SourceAttempt[];
    expectedRequiredSourceKeys: readonly string[];
    requiredSourceSelectionOverflow: boolean;
    retainedDocuments: readonly Record<string, unknown>[];
    replayInputHash: string;
  },
): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const envelope = value as Record<string, unknown>;
  const proposals = envelope.canonical_proposals;
  if (
    Object.keys(envelope).length !== pilotVerificationEnvelopeKeys.size ||
    !Object.keys(envelope).every((key) =>
      pilotVerificationEnvelopeKeys.has(key)
    ) || !Array.isArray(proposals) || proposals.length > 256
  ) return false;
  let canonical: string;
  try {
    canonical = stableCanonicalJson(envelope);
  } catch {
    return false;
  }
  return new TextEncoder().encode(canonical).byteLength <= 262_144 &&
    envelope.parser_version === binding.parserVersion &&
    envelope.job_id === binding.jobId && envelope.card_id === binding.cardId &&
    envelope.run_mode === binding.runMode &&
    envelope.source_manifest_hash === binding.sourceManifestHash &&
    stableCanonicalJson(envelope.source_resources) ===
      stableCanonicalJson(replaySourceEnvelope(binding.sourceAttempts)) &&
    stableCanonicalJson(envelope.retained_documents) ===
      stableCanonicalJson(binding.retainedDocuments) &&
    stableCanonicalJson(envelope.expected_required_source_keys) ===
      stableCanonicalJson(binding.expectedRequiredSourceKeys) &&
    envelope.required_source_selection_overflow ===
      binding.requiredSourceSelectionOverflow &&
    envelope.replay_input_hash === binding.replayInputHash &&
    !rawBodyWouldBeStored(envelope);
}

type PilotStagingEvidence = {
  id: string;
  card_id: string;
  parser_version: string;
  content_hash: string;
  status: string;
  benefit_decisions?: unknown;
  extracted_data?: unknown;
};

function canonicalPilotUtcTimestamp(value: unknown): {
  canonical: string;
  instant: number;
} | null {
  if (typeof value !== "string") return null;
  const match = value.match(
    /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(?:Z|\+00(?::00)?)$/,
  );
  if (!match) return null;
  const milliseconds = (match[3] ?? "").slice(0, 3).padEnd(3, "0");
  const instant = Date.parse(`${match[1]}T${match[2]}.${milliseconds}Z`);
  if (
    !Number.isFinite(instant) ||
    new Date(instant).toISOString().slice(0, 19) !==
      `${match[1]}T${match[2]}`
  ) return null;
  return {
    canonical: `${match[1]}T${match[2]}.${(match[3] ?? "").padEnd(6, "0")}Z`,
    instant,
  };
}

function reviewedDecisionInstant(value: unknown): number | null {
  const parsed = canonicalPilotUtcTimestamp(value)?.instant ?? null;
  return parsed !== null && parsed >= Date.UTC(2000, 0, 1) &&
      parsed <= Date.now() + MAX_EVIDENCE_CLOCK_SKEW_MS
    ? parsed
    : null;
}

function reviewedStagingCounts(value: unknown): {
  approved: number;
  retained: number;
  retired: number;
  rejected: number;
} | null {
  if (!Array.isArray(value) || value.length > MAX_PILOT_REVIEW_COUNT) {
    return null;
  }
  const counts = { approved: 0, retained: 0, retired: 0, rejected: 0 };
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) return null;
    const decision = item as Record<string, unknown>;
    if (reviewedDecisionInstant(decision.reviewed_at) === null) return null;
    if (decision.action === "approve" || decision.action === "edit") {
      counts.approved += 1;
    } else if (decision.action === "keep_existing") {
      counts.retained += 1;
    } else if (decision.action === "retire") {
      counts.retired += 1;
    } else if (decision.action === "reject") {
      counts.rejected += 1;
    } else return null;
  }
  return counts;
}

function exactReviewedStagingCounts(
  decisions: unknown,
  extracted: Record<string, unknown> | null,
): ReturnType<typeof reviewedStagingCounts> {
  const counts = reviewedStagingCounts(decisions);
  if (!counts || !extracted || !Array.isArray(extracted.proposals)) return null;
  const stagedProposals = extracted.proposals as unknown[];
  const proposalTargets = stagedProposals.map((_, index) =>
    `proposal:${index}`
  );
  const diff = extracted.diff && typeof extracted.diff === "object" &&
      !Array.isArray(extracted.diff)
    ? extracted.diff as Record<string, unknown>
    : {};
  const removals = Array.isArray(diff.possibleRemovals)
    ? diff.possibleRemovals
    : [];
  const pairedCurrentTargets = new Map<string, string>();
  for (const laneName of ["modifications", "unchanged"] as const) {
    const lane = Array.isArray(diff[laneName])
      ? diff[laneName] as unknown[]
      : [];
    for (const item of lane) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return null;
      const pair = item as Record<string, unknown>;
      const current = pair.current && typeof pair.current === "object" &&
          !Array.isArray(pair.current)
        ? pair.current as Record<string, unknown>
        : {};
      const proposed = pair.proposed;
      if (
        !proposed || typeof proposed !== "object" || Array.isArray(proposed)
      ) {
        return null;
      }
      const liveId = current.liveBenefitId ?? current.benefitId ??
        current.dedupeKey;
      const proposalIndex = stagedProposals.findIndex((candidate) =>
        stableCanonicalJson(candidate) === stableCanonicalJson(proposed)
      );
      if (
        typeof liveId !== "string" || liveId.length === 0 ||
        proposalIndex < 0 || pairedCurrentTargets.has(liveId)
      ) return null;
      pairedCurrentTargets.set(liveId, `proposal:${proposalIndex}`);
    }
  }
  const removalTargets = removals.map((item) => {
    const removal = item && typeof item === "object" && !Array.isArray(item)
      ? item as Record<string, unknown>
      : {};
    const benefit = removal.benefit && typeof removal.benefit === "object" &&
        !Array.isArray(removal.benefit)
      ? removal.benefit as Record<string, unknown>
      : {};
    const id = benefit.liveBenefitId ?? benefit.benefitId ?? benefit.dedupeKey;
    return typeof id === "string" && id.length > 0 ? `benefit:${id}` : "";
  });
  if (removalTargets.includes("")) return null;
  const expected = [...proposalTargets, ...removalTargets];
  const actual = (decisions as Record<string, unknown>[]).map((decision) => {
    const hasProposalField = Object.hasOwn(decision, "proposal_index");
    const hasBenefitField = Object.hasOwn(decision, "benefit_id");
    const hasProposal = Number.isInteger(decision.proposal_index) &&
      Number(decision.proposal_index) >= 0;
    const hasBenefit = typeof decision.benefit_id === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
        .test(
          decision.benefit_id,
        );
    const action = String(decision.action);
    if (action === "approve" || action === "edit") {
      if (
        !hasProposalField || !hasBenefitField || !hasProposal || !hasBenefit
      ) return "";
      const proposal = stagedProposals[Number(decision.proposal_index)];
      if (
        !proposal || typeof proposal !== "object" || Array.isArray(proposal)
      ) {
        return "";
      }
      const bound = proposal as Record<string, unknown>;
      if (
        decision.dedupe_key !== bound.dedupeKey ||
        decision.condition_hash !== bound.conditionHash
      ) return "";
      return `proposal:${decision.proposal_index}`;
    }
    if (
      action === "reject" && hasProposalField && !hasBenefitField &&
      hasProposal
    ) {
      const proposal = stagedProposals[Number(decision.proposal_index)];
      if (
        !proposal || typeof proposal !== "object" || Array.isArray(proposal)
      ) {
        return "";
      }
      const bound = proposal as Record<string, unknown>;
      return decision.dedupe_key === bound.dedupeKey &&
          decision.condition_hash === bound.conditionHash
        ? `proposal:${decision.proposal_index}`
        : "";
    }
    if (
      action === "retire" && hasBenefitField && !hasProposalField &&
      hasBenefit
    ) {
      const target = `benefit:${decision.benefit_id}`;
      return removalTargets.includes(target) ? target : "";
    }
    if (
      ["keep_existing", "reject"].includes(action) && hasBenefitField &&
      !hasProposalField && hasBenefit
    ) {
      const removalTarget = `benefit:${decision.benefit_id}`;
      return removalTargets.includes(removalTarget)
        ? removalTarget
        : pairedCurrentTargets.get(String(decision.benefit_id)) ?? "";
    }
    return "";
  });
  return actual.length === expected.length && !actual.includes("") &&
      new Set(actual).size === actual.length &&
      stableCanonicalJson([...actual].sort()) ===
        stableCanonicalJson([...expected].sort())
    ? counts
    : null;
}

export async function projectPilotJobEvidence(
  row: Record<string, any>,
  boundary: {
    staging?: PilotStagingEvidence | null;
    currentLiveState?: PilotLiveStateSnapshot | null;
    catalogIdentityConflictCount?: number;
  } = {},
): Promise<PilotJob> {
  const summary = row.result_summary && typeof row.result_summary === "object"
    ? row.result_summary
    : {};
  const promotedEvidence = row.run_mode === "scheduled" &&
    summary.pilot_qualified === true;
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
  const normalized = row.normalized_fields &&
      typeof row.normalized_fields === "object" &&
      !Array.isArray(row.normalized_fields)
    ? row.normalized_fields as Record<string, unknown>
    : {};
  const pilotProfile = typeof normalized.pilot_profile === "string" &&
      [
        "straightforward",
        "redirect_or_js",
        "terms_linked",
        "known_invalid",
        "additional_valid",
      ].includes(normalized.pilot_profile)
    ? normalized.pilot_profile
    : null;
  const evidence = normalized.pilot_evidence &&
      typeof normalized.pilot_evidence === "object" &&
      !Array.isArray(normalized.pilot_evidence)
    ? normalized.pilot_evidence as Record<string, unknown>
    : null;
  const before = validatedPilotSnapshot(evidence?.live_state_before);
  const after = validatedPilotSnapshot(evidence?.live_state_after);
  const sourceAttempts = Array.isArray(evidence?.source_attempts) &&
      evidence!.source_attempts.length > 0 &&
      evidence!.source_attempts.length <= 9 &&
      evidence!.source_attempts.every(validPilotSourceAttempt)
    ? evidence!.source_attempts as SourceAttempt[]
    : [];
  const primaryAttempts = sourceAttempts.filter((attempt) =>
    attempt.role === "primary"
  );
  const requiredAttempts = sourceAttempts.filter((attempt) =>
    attempt.role === "required_supporting"
  );
  const persistedExpectedRequiredSourceKeys = validPilotRequiredSourceKeys(
      evidence?.expected_required_source_keys,
    )
    ? evidence!.expected_required_source_keys as string[]
    : null;
  const replayInput = parsePilotReplayInput(evidence?.replay_input);
  const replayExpectedRequiredSourceKeys = replayInput?.required_resources.map(
    (resource) => resource.logical_source_key,
  ) ?? null;
  const requiredSourceSelectionOverflow =
    typeof evidence?.required_source_selection_overflow === "boolean"
      ? evidence.required_source_selection_overflow
      : null;
  const actualRequiredSourceKeys = pilotRequiredSourceKeys(sourceAttempts);
  const decisiveSourcesComplete = primaryAttempts.length === 1 &&
    decisivePilotSourceSucceeded(primaryAttempts[0]) &&
    persistedExpectedRequiredSourceKeys !== null &&
    replayExpectedRequiredSourceKeys !== null &&
    stableCanonicalJson(persistedExpectedRequiredSourceKeys) ===
      stableCanonicalJson(replayExpectedRequiredSourceKeys) &&
    stableCanonicalJson(replayExpectedRequiredSourceKeys) ===
      stableCanonicalJson(actualRequiredSourceKeys) &&
    replayExpectedRequiredSourceKeys.every((key) => {
      const matches = requiredAttempts.filter((attempt) =>
        attempt.logicalSourceKey === key
      );
      return matches.length === 1 && decisivePilotSourceSucceeded(matches[0]);
    }) &&
    requiredAttempts.every(decisivePilotSourceSucceeded) &&
    sourceAttempts.every((attempt) => attempt.attemptHistoryOverflow !== true);
  const observedAt = canonicalPilotUtcTimestamp(evidence?.observed_at)
    ?.instant ?? null;
  const currentTime = Date.now();
  const observedAtValid = observedAt !== null &&
    observedAt >= Date.UTC(2000, 0, 1) &&
    observedAt <= currentTime + MAX_EVIDENCE_CLOCK_SKEW_MS;
  const sourceAttemptTimesValid = observedAt !== null &&
    sourceAttempts.flatMap((attempt) => [
      attempt.attemptedAt,
      ...(attempt.attemptHistory ?? []).map((event) => event.attemptedAt),
    ]).every((timestamp) => {
      const parsed = canonicalPilotUtcTimestamp(timestamp)?.instant ?? null;
      return parsed !== null && parsed >= Date.UTC(2000, 0, 1) &&
        parsed <= currentTime + MAX_EVIDENCE_CLOCK_SKEW_MS &&
        parsed <= observedAt + MAX_EVIDENCE_CLOCK_SKEW_MS;
    });
  const canonicalHash = typeof evidence?.canonical_hash === "string"
    ? evidence.canonical_hash
    : "";
  const repeatCanonicalHash = typeof evidence?.repeat_canonical_hash ===
      "string"
    ? evidence.repeat_canonical_hash
    : "";
  const verificationEnvelope = evidence?.verification_envelope;
  const repeatVerificationEnvelope = evidence?.repeat_verification_envelope;
  const replayInputHash = replayInput
    ? await sha256Text(stableCanonicalJson(replayInput))
    : "";
  const retainedDocuments = verificationEnvelope &&
      typeof verificationEnvelope === "object" &&
      !Array.isArray(verificationEnvelope) &&
      validRetainedDocumentEnvelope(
        (verificationEnvelope as Record<string, unknown>).retained_documents,
        sourceAttempts,
      )
    ? (verificationEnvelope as Record<string, unknown>)
      .retained_documents as Record<string, unknown>[]
    : [];
  const verificationBinding = {
    parserVersion: evidence?.parser_version,
    jobId: evidence?.job_id,
    cardId: evidence?.card_id,
    runMode: evidence?.run_mode,
    sourceManifestHash: evidence?.source_manifest_hash,
    sourceAttempts,
    expectedRequiredSourceKeys: persistedExpectedRequiredSourceKeys ?? [],
    requiredSourceSelectionOverflow: requiredSourceSelectionOverflow === true,
    retainedDocuments,
    replayInputHash,
  };
  const envelopesValid = persistedExpectedRequiredSourceKeys !== null &&
    replayInput !== null && lowercaseSha256.test(replayInputHash) &&
    requiredSourceSelectionOverflow !== null &&
    validPilotVerificationEnvelope(
      verificationEnvelope,
      verificationBinding,
    ) && validPilotVerificationEnvelope(
      repeatVerificationEnvelope,
      verificationBinding,
    );
  const recomputedCanonicalHash = envelopesValid
    ? await sha256Text(stableCanonicalJson(verificationEnvelope))
    : "";
  const recomputedRepeatCanonicalHash = envelopesValid
    ? await sha256Text(stableCanonicalJson(repeatVerificationEnvelope))
    : "";
  let independentlyRecomputedReplay:
    | Awaited<ReturnType<typeof computePilotReplayEvidence>>
    | null = null;
  if (
    replayInput && persistedExpectedRequiredSourceKeys &&
    requiredSourceSelectionOverflow !== null &&
    typeof evidence?.source_manifest_hash === "string"
  ) {
    try {
      independentlyRecomputedReplay = await computePilotReplayEvidence({
        jobId: String(row.id),
        cardId: String(row.card_id),
        parserVersion: String(row.parser_version),
        runMode: "pilot",
        sourceManifestHash: evidence.source_manifest_hash,
        expectedRequiredSourceKeys: replayExpectedRequiredSourceKeys ?? [],
        requiredSourceSelectionOverflow,
        attempts: sourceAttempts,
        documents: pilotReplayDocuments(replayInput),
      });
    } catch {
      independentlyRecomputedReplay = null;
    }
  }
  const replayPassed = lowercaseSha256.test(canonicalHash) &&
    lowercaseSha256.test(repeatCanonicalHash) &&
    canonicalHash === repeatCanonicalHash &&
    canonicalHash === recomputedCanonicalHash &&
    repeatCanonicalHash === recomputedRepeatCanonicalHash &&
    independentlyRecomputedReplay !== null &&
    stableCanonicalJson(independentlyRecomputedReplay.replayInput) ===
      stableCanonicalJson(replayInput) &&
    stableCanonicalJson(independentlyRecomputedReplay.verificationEnvelope) ===
      stableCanonicalJson(verificationEnvelope) &&
    stableCanonicalJson(
        independentlyRecomputedReplay.repeatVerificationEnvelope,
      ) === stableCanonicalJson(repeatVerificationEnvelope);
  const mutationCount = before && after
    ? liveStateMutationCount(before, after)
    : -1;
  const sideEffectPassed = mutationCount === 0;
  const expectedEvidenceMode = row.run_mode === "scheduled" &&
      summary.pilot_qualified === true
    ? "pilot"
    : row.run_mode;
  let expectedPrimarySourceKey: string | null = null;
  try {
    expectedPrimarySourceKey = typeof row.canonical_url === "string"
      ? sourceIdentityDigest(row.canonical_url)
      : null;
  } catch {
    expectedPrimarySourceKey = null;
  }
  const sourceBindingValid = evidence !== null &&
    evidence.parser_version === row.parser_version &&
    evidence.job_id === row.id && evidence.card_id === row.card_id &&
    evidence.run_mode === expectedEvidenceMode &&
    typeof evidence.source_manifest_hash === "string" &&
    lowercaseSha256.test(evidence.source_manifest_hash) &&
    sourceAttempts.length > 0 &&
    expectedPrimarySourceKey !== null && primaryAttempts.length === 1 &&
    primaryAttempts[0].logicalSourceKey === expectedPrimarySourceKey &&
    await computeSourceManifestHash(sourceAttempts) ===
      evidence.source_manifest_hash;
  const proposalCount = count(evidence?.proposal_count);
  const envelopeProposalCount = envelopesValid &&
      Array.isArray(verificationEnvelope.canonical_proposals)
    ? verificationEnvelope.canonical_proposals.length
    : -1;
  const proposalIdentityValues = envelopesValid &&
      Array.isArray(verificationEnvelope.canonical_proposals)
    ? verificationEnvelope.canonical_proposals.map((proposal: unknown) => {
      if (
        !proposal || typeof proposal !== "object" || Array.isArray(proposal)
      ) {
        return "";
      }
      const value = proposal as Record<string, unknown>;
      return typeof value.conditionHash === "string"
        ? value.conditionHash
        : typeof value.dedupeKey === "string"
        ? value.dedupeKey
        : "";
    })
    : [];
  const recomputedCanonicalBenefitHash =
    proposalIdentityValues.length === envelopeProposalCount &&
      !proposalIdentityValues.includes("")
      ? await sha256Text([...proposalIdentityValues].sort().join("\n"))
      : "";
  const canonicalBenefitHash = typeof evidence?.canonical_benefit_hash ===
        "string" && lowercaseSha256.test(evidence.canonical_benefit_hash)
    ? evidence.canonical_benefit_hash
    : null;
  const previousCanonicalBenefitHash =
    evidence?.previous_canonical_benefit_hash === null
      ? null
      : typeof evidence?.previous_canonical_benefit_hash === "string" &&
          lowercaseSha256.test(evidence.previous_canonical_benefit_hash)
      ? evidence.previous_canonical_benefit_hash
      : undefined;
  const proposalDisposition = evidence?.proposal_disposition === "material" ||
      evidence?.proposal_disposition === "removal_review" ||
      evidence?.proposal_disposition === "no_change"
    ? evidence.proposal_disposition
    : null;
  const evidenceStagingId = evidence?.staging_id === null ||
      (typeof evidence?.staging_id === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
          .test(
            evidence.staging_id,
          ))
    ? evidence.staging_id as string | null
    : undefined;
  const evidenceStagingContentHash = evidence?.staging_content_hash === null ||
      (typeof evidence?.staging_content_hash === "string" &&
        lowercaseSha256.test(evidence.staging_content_hash))
    ? evidence.staging_content_hash as string | null
    : undefined;
  const proposalBindingValid = proposalCount !== null &&
    proposalCount === envelopeProposalCount &&
    canonicalBenefitHash === recomputedCanonicalBenefitHash &&
    previousCanonicalBenefitHash !== undefined &&
    (promotedEvidence ||
      (summary.proposals === proposalCount &&
        summary.proposal_disposition === proposalDisposition));
  const noChangeBindingValid = proposalDisposition === "no_change" &&
    canonicalBenefitHash !== null &&
    (previousCanonicalBenefitHash === canonicalBenefitHash ||
      (previousCanonicalBenefitHash === null && proposalCount === 0 &&
        after?.benefits.count === 0 &&
        after?.card_benefit_mapping.count === 0)) &&
    evidenceStagingId === null && evidenceStagingContentHash === null &&
    (promotedEvidence ||
      (row.staging_id == null && summary.successful_no_change === true &&
        !reviewMetadataPresent));
  const staging = boundary.staging;
  const stagingExtraction = staging?.extracted_data &&
      typeof staging.extracted_data === "object" &&
      !Array.isArray(staging.extracted_data)
    ? staging.extracted_data as Record<string, unknown>
    : null;
  const stagingProposalsValid = stagingExtraction !== null &&
    Array.isArray(stagingExtraction.proposals) &&
    stagingExtraction.proposals.length <= 256 && envelopesValid &&
    stableCanonicalJson(stagingExtraction.proposals) ===
      stableCanonicalJson(verificationEnvelope.canonical_proposals) &&
    stableCanonicalJson(stagingExtraction.retained_documents) ===
      stableCanonicalJson(verificationEnvelope.retained_documents);
  const publishedLiveState = validatedPilotSnapshot(
    stagingExtraction?.published_live_state,
  );
  const reviewPreLiveState = validatedPilotSnapshot(
    stagingExtraction?.review_pre_live_state,
  );
  const stagingIdentityValid = proposalDisposition !== "no_change" &&
    typeof evidenceStagingId === "string" &&
    typeof evidenceStagingContentHash === "string" &&
    (promotedEvidence || row.staging_id === evidenceStagingId) &&
    staging?.id === evidenceStagingId &&
    staging.card_id === row.card_id &&
    staging.parser_version === row.parser_version &&
    staging.content_hash === evidenceStagingContentHash &&
    stagingProposalsValid &&
    (promotedEvidence || summary.successful_no_change === false);
  const stagingCounts = stagingIdentityValid &&
      (promotedEvidence || row.status === "completed")
    ? exactReviewedStagingCounts(staging?.benefit_decisions, stagingExtraction)
    : null;
  const stagingReviewTimesValid = Array.isArray(staging?.benefit_decisions) &&
    observedAt !== null && staging.benefit_decisions.every((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        return false;
      }
      const reviewedAt = reviewedDecisionInstant(
        (item as Record<string, unknown>).reviewed_at,
      );
      return reviewedAt !== null &&
        reviewedAt >= observedAt - MAX_EVIDENCE_CLOCK_SKEW_MS;
    });
  const stagingReviewStatus = staging?.status === "approved" ||
      staging?.status === "rejected"
    ? staging.status
    : null;
  const stagingStateValid = noChangeBindingValid ||
    (promotedEvidence
      ? stagingIdentityValid && stagingReviewStatus !== null &&
        stagingCounts !== null && stagingReviewTimesValid
      : stagingIdentityValid &&
        ((row.status === "staged" && staging?.status === "pending") ||
          (row.status === "completed" && staging?.status === reviewStatus &&
            stagingCounts !== null && stagingReviewTimesValid &&
            stagingCounts.approved === count(summary.approved_count) &&
            stagingCounts.retained === count(summary.retained_count) &&
            stagingCounts.retired === count(summary.retired_count) &&
            stagingCounts.rejected === count(summary.rejected_count))));
  const currentLiveState = validatedPilotSnapshot(boundary.currentLiveState);
  const prePublicationState = !promotedEvidence &&
    (proposalDisposition === "no_change" || row.status === "staged");
  const currentLiveStateValid = currentLiveState !== null && after !== null &&
    (promotedEvidence
      ? true
      : prePublicationState || proposalDisposition === "no_change"
      ? liveStateMutationCount(after, currentLiveState) === 0
      : reviewPreLiveState !== null && publishedLiveState !== null &&
        liveStateMutationCount(after, reviewPreLiveState) === 0 &&
        liveStateMutationCount(publishedLiveState, currentLiveState) === 0);
  const suppressedRemovalCount = count(evidence?.suppressed_removal_count);
  const conflictCount = count(evidence?.conflict_count);
  const catalogIdentityConflictCount = count(
    boundary.catalogIdentityConflictCount ??
      evidence?.catalog_identity_conflict_count,
  );
  const catalogIdentityConflictBindingValid =
    boundary.catalogIdentityConflictCount === undefined ||
    evidence?.catalog_identity_conflict_count ===
      boundary.catalogIdentityConflictCount;
  const exactEvidenceShape = evidence !== null &&
    Object.keys(evidence).length === pilotEvidenceKeys.size &&
    Object.keys(evidence).every((key) => pilotEvidenceKeys.has(key));
  const computedEvidenceValid = exactEvidenceShape && sourceBindingValid &&
    observedAtValid && sourceAttemptTimesValid && replayPassed &&
    proposalBindingValid && stagingStateValid && currentLiveStateValid &&
    evidence!.deterministic_replay_passed === true &&
    evidence!.crawl_complete === true && decisiveSourcesComplete &&
    requiredSourceSelectionOverflow === false &&
    suppressedRemovalCount === 0 && mutationCount === 0 &&
    evidence!.unsafe_mutation_count === 0 &&
    evidence!.raw_body_stored === false &&
    evidence!.side_effect_proof_passed === true &&
    conflictCount === 0 && catalogIdentityConflictCount === 0 &&
    catalogIdentityConflictBindingValid &&
    !rawBodyWouldBeStored(evidence);
  const projectedReviewMetadataPresent = promotedEvidence
    ? proposalDisposition !== "no_change"
    : reviewMetadataPresent;
  const projectedReviewMetadataMalformed = promotedEvidence
    ? proposalDisposition !== "no_change" &&
      (stagingReviewStatus === null || stagingCounts === null)
    : reviewMetadataMalformed;
  const projectedReviewStatus = promotedEvidence
    ? stagingReviewStatus
    : reviewStatus;
  const projectedReviewCounts = promotedEvidence && stagingCounts
    ? stagingCounts
    : {
      approved: count(summary.approved_count),
      retained: count(summary.retained_count),
      retired: count(summary.retired_count),
      rejected: count(summary.rejected_count),
    };
  return {
    id: String(row.id),
    issuer: typeof row.issuer === "string" ? row.issuer : "",
    pilotProfile: pilotProfile ?? undefined,
    runMode: row.run_mode,
    pilotQualified: summary.pilot_qualified === true,
    status: String(row.status),
    quarantineReason: row.status === "quarantined" ? quarantineReason : null,
    safetyMetadataValid: (promotedEvidence || safetyMetadataValid) &&
      (promotedEvidence
          ? count(evidence?.unsafe_mutation_count)
          : unsafeMutationCount) === mutationCount &&
      (promotedEvidence ||
        summary.raw_body_stored === evidence?.raw_body_stored),
    unsafeMutationCount: mutationCount,
    idempotencyPassed: replayPassed,
    evidencePassed: computedEvidenceValid,
    rawBodyStored: evidence?.raw_body_stored !== false,
    successfulNoChange: noChangeBindingValid,
    reviewMetadataPresent: projectedReviewMetadataPresent,
    reviewMetadataMalformed: projectedReviewMetadataMalformed,
    reviewStatus: projectedReviewStatus,
    approvedCount: projectedReviewCounts.approved,
    retainedCount: projectedReviewCounts.retained,
    retiredCount: projectedReviewCounts.retired,
    rejectedCount: projectedReviewCounts.rejected,
    computedEvidenceValid,
    deterministicReplayPassed: replayPassed,
    sideEffectProofPassed: sideEffectPassed,
    crawlComplete: evidence?.crawl_complete === true &&
      decisiveSourcesComplete,
    suppressedRemovalCount: suppressedRemovalCount ?? -1,
    sourceBindingValid,
    conflictCount: (conflictCount ?? -1) +
      (catalogIdentityConflictCount ?? -1),
  };
}

export async function readPilotStatus(
  db: UntypedSupabaseClient,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
  dependencies: {
    captureLiveStateSnapshot?: typeof capturePilotLiveStateSnapshot;
    readCatalogIdentityConflictCount?: (
      db: UntypedSupabaseClient,
      cardId: string,
      canonicalUrl: string,
    ) => Promise<number>;
  } = {},
) {
  assertBenefitParserVersion(parserVersion);
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .select(
      "id,card_id,issuer,canonical_url,parser_version,run_mode,status,failure_category,staging_id,normalized_fields,result_summary",
    )
    .eq("parser_version", parserVersion)
    .limit(6)
    .or("run_mode.eq.pilot,result_summary->>pilot_qualified.eq.true");
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  const evidenceStagingId = (row: Record<string, any>): string | null => {
    const candidate = row.normalized_fields?.pilot_evidence?.staging_id;
    return typeof candidate === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
          .test(
            candidate,
          )
      ? candidate
      : null;
  };
  const stagingIds = [
    ...new Set(
      rows.map(evidenceStagingId).filter((id): id is string => id !== null),
    ),
  ];
  const stagingById = new Map<string, PilotStagingEvidence>();
  if (stagingIds.length > 0) {
    if (stagingIds.length > 5) {
      throw new Error("pilot_staging_evidence_unbounded");
    }
    const { data: stagingRows, error: stagingError } = await db.from(
      "card_benefits_staging",
    ).select(
      "id,card_id,parser_version,content_hash,status,benefit_decisions,extracted_data",
    ).in("id", stagingIds).limit(6);
    if (stagingError || !Array.isArray(stagingRows)) {
      throw stagingError ?? new Error("pilot_staging_evidence_invalid");
    }
    for (const staging of stagingRows) {
      if (stagingById.has(String(staging.id))) {
        throw new Error("pilot_staging_evidence_ambiguous");
      }
      stagingById.set(String(staging.id), staging as PilotStagingEvidence);
    }
  }
  return evaluatePilotGate(
    await Promise.all(rows.map(async (row) =>
      projectPilotJobEvidence(row, {
        staging: evidenceStagingId(row)
          ? stagingById.get(evidenceStagingId(row)!) ?? null
          : null,
        currentLiveState: await (
          dependencies.captureLiveStateSnapshot ?? capturePilotLiveStateSnapshot
        )(db, String(row.card_id)),
        catalogIdentityConflictCount: await (
          dependencies.readCatalogIdentityConflictCount ??
            readPilotCatalogIdentityConflictCount
        )(db, String(row.card_id), String(row.canonical_url)),
      })
    )),
  );
}

async function readPilotCatalogIdentityConflictCount(
  db: UntypedSupabaseClient,
  cardId: string,
  canonicalUrl: string,
): Promise<number> {
  const { data, error } = await db.rpc("card_has_unresolved_catalog_identity", {
    _card_id: cardId,
    _canonical_url: canonicalUrl,
  });
  if (error || typeof data !== "boolean") {
    throw error ?? new Error("pilot_catalog_identity_conflict_check_failed");
  }
  return data ? 1 : 0;
}

export async function promoteQualifiedPilotJobs(
  db: UntypedSupabaseClient,
  parserVersion = CURRENT_BENEFIT_PARSER_VERSION,
  dependencies: {
    captureLiveStateSnapshot?: typeof capturePilotLiveStateSnapshot;
    readCatalogIdentityConflictCount?: (
      db: UntypedSupabaseClient,
      cardId: string,
      canonicalUrl: string,
    ) => Promise<number>;
  } = {},
): Promise<EnrichmentJob[]> {
  assertBenefitParserVersion(parserVersion);
  if (parserVersion !== CURRENT_BENEFIT_PARSER_VERSION) {
    throw new Error("unsupported_pilot_parser_version");
  }
  const gate = await readPilotStatus(db, parserVersion, dependencies);
  if (gate.status !== "passed") throw new Error("pilot_evidence_not_qualified");
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

const lowercaseSha256 = /^[0-9a-f]{64}$/;
const MAX_PILOT_REPLAY_TEXT_BYTES = 65_536;
const pilotSnapshotTables = [
  "card_catalog",
  "benefits",
  "card_benefit_mapping",
] as const;

type PilotLiveStateSnapshot = Record<
  (typeof pilotSnapshotTables)[number],
  { count: number; row_hash: string }
>;

type PilotReplayExtractor = (
  documents: BenefitDocument[],
  parserVersion: "benefits-v6",
  cardId: string,
) => Promise<BenefitComparisonProposal[]>;

function immutableDocumentSnapshot(
  documents: readonly BenefitDocument[],
): BenefitDocument[] {
  if (documents.length > 9) throw new Error("pilot_evidence_unbounded");
  return documents.map((document) =>
    Object.freeze({
      sourceUrl: String(document.sourceUrl),
      ...(document.finalUrl ? { finalUrl: String(document.finalUrl) } : {}),
      ...(document.requestedResourceIdentityHash
        ? {
          requestedResourceIdentityHash: String(
            document.requestedResourceIdentityHash,
          ),
        }
        : {}),
      ...(document.finalResourceIdentityHash
        ? {
          finalResourceIdentityHash: String(
            document.finalResourceIdentityHash,
          ),
        }
        : {}),
      text: String(document.text),
      contentHash: String(document.contentHash),
    })
  );
}

async function retainedDocumentEnvelope(
  documents: readonly BenefitDocument[],
): Promise<Record<string, unknown>[]> {
  if (documents.length > 9) throw new Error("pilot_evidence_unbounded");
  return await Promise.all(documents.map(async (document) => {
    const text = String(document.text);
    const contentHash = String(document.contentHash ?? "");
    if (!lowercaseSha256.test(contentHash)) {
      throw new Error("invalid_pilot_document_content_hash");
    }
    const requestedResourceIdentityHash =
      document.requestedResourceIdentityHash ??
        sourceIdentityDigest(String(document.sourceUrl));
    const finalResourceIdentityHash = document.finalResourceIdentityHash ??
      sourceIdentityDigest(String(document.finalUrl ?? document.sourceUrl));
    if (
      !lowercaseSha256.test(requestedResourceIdentityHash) ||
      !lowercaseSha256.test(finalResourceIdentityHash)
    ) throw new Error("invalid_pilot_document_resource_identity");
    return {
      requested_resource_identity_hash: requestedResourceIdentityHash,
      final_resource_identity_hash: finalResourceIdentityHash,
      content_hash: contentHash,
      document_text_hash: await sha256Text(text),
      document_bytes: new TextEncoder().encode(text).byteLength,
    };
  }));
}

function replaySourceEnvelope(attempts: readonly SourceAttempt[]) {
  return attempts.slice(0, 9).map((attempt) => ({
    url: attempt.url,
    role: attempt.role,
    status: attempt.status,
    ...(attempt.httpStatus !== undefined
      ? { http_status: attempt.httpStatus }
      : {}),
    ...(attempt.contentHash ? { content_hash: attempt.contentHash } : {}),
    ...(attempt.logicalSourceKey
      ? { logical_source_key: attempt.logicalSourceKey }
      : {}),
    ...(attempt.finalResourceIdentityHash
      ? { final_resource_identity_hash: attempt.finalResourceIdentityHash }
      : {}),
    ...(attempt.errorCode ? { error_code: attempt.errorCode } : {}),
  }));
}

function pilotVerificationSourceAttempts(
  attempts: readonly SourceAttempt[],
): SourceAttempt[] {
  if (attempts.length < 1 || attempts.length > 9) {
    throw new Error("invalid_pilot_replay_binding");
  }
  return attempts.map((
    { etag: _etag, lastModified: _lastModified, ...attempt },
  ) => structuredClone(attempt));
}

type PilotReplayInputDocument = {
  requested_source_url: string;
  final_source_url: string;
  requested_resource_identity_hash: string;
  final_resource_identity_hash: string;
  content_hash: string;
  public_text: string;
};

type PilotReplayInput = {
  version: 1;
  documents: PilotReplayInputDocument[];
  required_resources: Array<{ logical_source_key: string }>;
};

function pilotReplayDocuments(input: PilotReplayInput): BenefitDocument[] {
  return input.documents.map((document) => ({
    sourceUrl: document.requested_source_url,
    finalUrl: document.final_source_url,
    requestedResourceIdentityHash: document.requested_resource_identity_hash,
    finalResourceIdentityHash: document.final_resource_identity_hash,
    contentHash: document.content_hash,
    text: document.public_text,
  }));
}

function parsePilotReplayInput(value: unknown): PilotReplayInput | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  if (
    Object.keys(input).length !== 3 || input.version !== 1 ||
    !Array.isArray(input.documents) || input.documents.length < 1 ||
    input.documents.length > 9 || !Array.isArray(input.required_resources) ||
    input.required_resources.length > 8
  ) return null;
  const documentKeys = new Set([
    "requested_source_url",
    "final_source_url",
    "requested_resource_identity_hash",
    "final_resource_identity_hash",
    "content_hash",
    "public_text",
  ]);
  const documents: PilotReplayInputDocument[] = [];
  for (const value of input.documents) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const document = value as Record<string, unknown>;
    if (
      Object.keys(document).length !== documentKeys.size ||
      !Object.keys(document).every((key) => documentKeys.has(key)) ||
      safeHttpsDisplayUrl(document.requested_source_url) !==
        document.requested_source_url ||
      safeHttpsDisplayUrl(document.final_source_url) !==
        document.final_source_url ||
      !lowercaseSha256.test(
        String(document.requested_resource_identity_hash),
      ) ||
      !lowercaseSha256.test(String(document.final_resource_identity_hash)) ||
      !lowercaseSha256.test(String(document.content_hash)) ||
      typeof document.public_text !== "string" ||
      document.public_text.length === 0 ||
      new TextEncoder().encode(document.public_text).byteLength >
        MAX_PILOT_REPLAY_TEXT_BYTES ||
      redactSensitiveUrlsInText(document.public_text) !== document.public_text
    ) return null;
    documents.push(document as PilotReplayInputDocument);
  }
  const requiredResources: Array<{ logical_source_key: string }> = [];
  for (const value of input.required_resources) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const resource = value as Record<string, unknown>;
    if (
      Object.keys(resource).length !== 1 ||
      !lowercaseSha256.test(String(resource.logical_source_key))
    ) return null;
    requiredResources.push({
      logical_source_key: String(resource.logical_source_key),
    });
  }
  const requiredKeys = requiredResources.map((resource) =>
    resource.logical_source_key
  );
  if (
    new Set(requiredKeys).size !== requiredKeys.length ||
    requiredKeys.some((key, index) =>
      index > 0 && requiredKeys[index - 1] >= key
    )
  ) return null;
  const parsed: PilotReplayInput = {
    version: 1,
    documents,
    required_resources: requiredResources,
  };
  try {
    assertSafePersistedEvidence(parsed);
  } catch {
    return null;
  }
  return parsed;
}

function buildPilotReplayInput(
  documents: readonly BenefitDocument[],
  expectedRequiredSourceKeys: readonly string[],
): PilotReplayInput {
  const value: PilotReplayInput = {
    version: 1,
    documents: documents.map((document) => {
      const requestedSourceUrl = safeHttpsDisplayUrl(document.sourceUrl);
      const finalSourceUrl = safeHttpsDisplayUrl(
        document.finalUrl ?? document.sourceUrl,
      );
      const requestedResourceIdentityHash =
        document.requestedResourceIdentityHash ??
          sourceIdentityDigest(document.sourceUrl);
      const finalResourceIdentityHash = document.finalResourceIdentityHash ??
        sourceIdentityDigest(
          document.finalUrl ?? document.sourceUrl,
        );
      if (!requestedSourceUrl || !finalSourceUrl) {
        throw new Error("invalid_pilot_replay_input");
      }
      return {
        requested_source_url: requestedSourceUrl,
        final_source_url: finalSourceUrl,
        requested_resource_identity_hash: requestedResourceIdentityHash,
        final_resource_identity_hash: finalResourceIdentityHash,
        content_hash: String(document.contentHash ?? ""),
        public_text: canonicalBenefitReplayText(String(document.text)),
      };
    }),
    required_resources: expectedRequiredSourceKeys.map((logicalSourceKey) => ({
      logical_source_key: logicalSourceKey,
    })),
  };
  const parsed = parsePilotReplayInput(value);
  if (!parsed) throw new Error("unsafe_persisted_evidence");
  return parsed;
}

export async function computePilotReplayEvidence(input: {
  jobId: string;
  cardId: string;
  parserVersion: string;
  runMode: RunMode;
  sourceManifestHash: string;
  expectedRequiredSourceKeys: string[];
  requiredSourceSelectionOverflow: boolean;
  attempts: SourceAttempt[];
  documents: readonly BenefitDocument[];
  extract?: PilotReplayExtractor;
}): Promise<{
  proposals: BenefitComparisonProposal[];
  canonicalHash: string;
  repeatCanonicalHash: string;
  deterministicReplayPassed: boolean;
  sourceManifestHash: string;
  verificationEnvelope: Record<string, unknown>;
  repeatVerificationEnvelope: Record<string, unknown>;
  expectedRequiredSourceKeys: string[];
  requiredSourceSelectionOverflow: boolean;
  sourceAttempts: SourceAttempt[];
  retainedDocuments: Record<string, unknown>[];
  replayInput: PilotReplayInput;
}> {
  if (
    input.parserVersion !== CURRENT_BENEFIT_PARSER_VERSION ||
    input.runMode !== "pilot" || !input.jobId || !input.cardId ||
    !lowercaseSha256.test(input.sourceManifestHash) ||
    !validPilotRequiredSourceKeys(input.expectedRequiredSourceKeys) ||
    typeof input.requiredSourceSelectionOverflow !== "boolean" ||
    input.attempts.length < 1 || input.attempts.length > 9
  ) throw new Error("invalid_pilot_replay_binding");
  if (input.documents.length > 9) throw new Error("pilot_evidence_unbounded");
  const sourceAttempts = pilotVerificationSourceAttempts(input.attempts);
  const sourceManifestHash = await computeSourceManifestHash(sourceAttempts);
  if (sourceManifestHash !== input.sourceManifestHash) {
    throw new Error("pilot_source_manifest_mismatch");
  }
  const replayInput = buildPilotReplayInput(
    input.documents,
    input.expectedRequiredSourceKeys,
  );
  const replayInputHash = await sha256Text(stableCanonicalJson(replayInput));
  const retained = immutableDocumentSnapshot(pilotReplayDocuments(replayInput));
  const retainedDocuments = await retainedDocumentEnvelope(retained);
  const extract = input.extract ?? extractGroundedBenefitsV6;
  const first = await extract(
    structuredClone(retained),
    "benefits-v6",
    input.cardId,
  );
  const second = await extract(
    structuredClone(retained),
    "benefits-v6",
    input.cardId,
  );
  const expectedRequiredSourceKeys = [...input.expectedRequiredSourceKeys];
  const envelope = (proposals: BenefitComparisonProposal[]) => ({
    parser_version: input.parserVersion,
    job_id: input.jobId,
    card_id: input.cardId,
    run_mode: input.runMode,
    source_manifest_hash: sourceManifestHash,
    source_resources: replaySourceEnvelope(sourceAttempts),
    retained_documents: retainedDocuments,
    expected_required_source_keys: expectedRequiredSourceKeys,
    required_source_selection_overflow: input.requiredSourceSelectionOverflow,
    replay_input_hash: replayInputHash,
    canonical_proposals: proposals,
  });
  const verificationEnvelope = envelope(first);
  const repeatVerificationEnvelope = envelope(second);
  const canonicalHash = await sha256Text(
    stableCanonicalJson(verificationEnvelope),
  );
  const repeatCanonicalHash = await sha256Text(
    stableCanonicalJson(repeatVerificationEnvelope),
  );
  return {
    proposals: first,
    canonicalHash,
    repeatCanonicalHash,
    deterministicReplayPassed: canonicalHash === repeatCanonicalHash,
    sourceManifestHash,
    verificationEnvelope,
    repeatVerificationEnvelope,
    expectedRequiredSourceKeys,
    requiredSourceSelectionOverflow: input.requiredSourceSelectionOverflow,
    sourceAttempts,
    retainedDocuments,
    replayInput,
  };
}

async function snapshotRows(
  rows: Array<Record<string, unknown>>,
  identityKey: string,
): Promise<{ count: number; row_hash: string }> {
  if (rows.length > 512) throw new Error("pilot_live_state_unbounded");
  const canonicalRows = rows.map((row) =>
    Object.fromEntries(
      Object.entries(row).map(([key, value]) => {
        if (
          ["created_at", "updated_at", "retired_at"].includes(key) &&
          typeof value === "string"
        ) {
          const timestamp = canonicalPilotUtcTimestamp(value);
          return [
            key,
            timestamp === null ? value : timestamp.canonical,
          ];
        }
        return [key, value];
      }),
    )
  );
  const sorted = canonicalRows.sort((left, right) =>
    String(left[identityKey] ?? "").localeCompare(
      String(right[identityKey] ?? ""),
    )
  );
  return {
    count: sorted.length,
    row_hash: await sha256Text(stableCanonicalJson(sorted)),
  };
}

export async function capturePilotLiveStateSnapshot(
  db: UntypedSupabaseClient,
  cardId: string,
): Promise<PilotLiveStateSnapshot> {
  const { data: catalog, error: catalogError } = await db.from("card_catalog")
    .select(
      "id,card_name,bank,network,card_type,annual_fee,joining_fee,apr,card_url,is_discontinued,created_at,updated_at",
    )
    .eq("id", cardId)
    .limit(2);
  if (catalogError || !Array.isArray(catalog) || catalog.length !== 1) {
    throw catalogError ?? new Error("pilot_catalog_snapshot_invalid");
  }
  const { data: mappings, error: mappingError } = await db
    .from("card_benefit_mapping")
    .select(
      "mapping_id,card_id,benefit_id,display_priority,is_primary,category_codes,retired_at,created_at",
    )
    .eq("card_id", cardId)
    .limit(513);
  if (mappingError || !Array.isArray(mappings)) {
    throw mappingError ?? new Error("pilot_mapping_snapshot_invalid");
  }
  const benefitIds = [
    ...new Set(
      mappings.map((row) => String(row.benefit_id ?? "")).filter(Boolean),
    ),
  ].slice(0, 513);
  let benefits: Array<Record<string, unknown>> = [];
  if (benefitIds.length > 0) {
    const { data, error } = await db.from("benefits").select(
      "benefit_id,dedupe_key,title,description,benefit_category,benefit_type,value_config,partners,exclusions,regions,source_url,valid_from,valid_until,is_active,created_at,updated_at",
    ).in("benefit_id", benefitIds).limit(513);
    if (error || !Array.isArray(data)) {
      throw error ?? new Error("pilot_benefit_snapshot_invalid");
    }
    benefits = data;
  }
  return {
    card_catalog: await snapshotRows(catalog, "id"),
    benefits: await snapshotRows(benefits, "benefit_id"),
    card_benefit_mapping: await snapshotRows(mappings, "mapping_id"),
  };
}

export function liveStateMutationCount(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): number {
  return pilotSnapshotTables.filter((table) => {
    const left = before[table] as Record<string, unknown> | undefined;
    const right = after[table] as Record<string, unknown> | undefined;
    return !left || !right || left.count !== right.count ||
      left.row_hash !== right.row_hash;
  }).length;
}

const blockedFetchCodes = new Set([
  "http_401",
  "http_403",
  "http_429",
  "robots_disallowed",
  "challenge_page",
  "js_challenge",
  "empty_shell",
]);
const missingFetchCodes = new Set(["http_404", "http_410", "soft_404"]);
const omittedRequiredCodes = new Set([
  "required_source_overflow",
  "fetch_budget_exhausted",
  "deadline_exceeded",
]);
const operationalReasonCodes = new Set([
  "complete",
  "corrupt_pdf",
  "unusable_not_modified",
  "empty_document",
  "primary_incomplete",
  "required_supporting_incomplete",
  "required_source_overflow",
  "fetch_budget_exhausted",
  "deadline_exceeded",
  "decisive_attempt_overflow",
  "invalid_attempt_history",
  "attempt_history_overflow",
  "invalid_source_url",
  "invalid_attempt",
  "http_401",
  "http_403",
  "http_404",
  "http_410",
  "http_429",
  "http_5xx",
  "soft_404",
  "challenge_page",
  "empty_shell",
  "unsupported_charset",
  "robots_disallowed",
  "robots_invalid",
  "unapproved_query",
  "identity_review",
  "identity_mismatch",
  "identity_ambiguous",
  "final_resource_identity_conflict",
  "insufficient_evidence",
  "js_challenge",
  "not_a_card",
  "ambiguous_product",
  "oversized",
  "private_address",
  "redirect_rejected",
  "timeout",
  "unapproved_domain",
  "unreachable",
  "unsupported_content",
  "enrichment_failed",
  "proposal_conflict",
  "conflicting_url_identity",
  "incomplete_crawl",
  "deterministic_replay_failed",
  "side_effect_proof_failed",
  "pilot_source_mismatch",
]);

function exactList(value: unknown): Array<Record<string, unknown>> {
  if (value === undefined || value === null) return [];
  if (
    !Array.isArray(value) || value.length > 512 ||
    value.some((item) =>
      !item || typeof item !== "object" || Array.isArray(item)
    )
  ) throw new Error("invalid_operational_metric_input");
  return value as Array<Record<string, unknown>>;
}

export function buildOperationalMetrics(input: {
  attempts?: unknown;
  crawlComplete?: unknown;
  additions?: unknown;
  modifications?: unknown;
  removals?: unknown;
  suppressedRemovals?: unknown;
  conflicts?: unknown;
  catalogIdentityConflicts?: unknown;
  decisions?: unknown;
  retryCount?: unknown;
  deterministicReplayPassed?: unknown;
  sideEffectProofPassed?: unknown;
  startedAt?: unknown;
  completedAt?: unknown;
}): Record<string, unknown> {
  const attempts = exactList(input.attempts);
  const attemptEvents = attempts.flatMap((attempt) => {
    const history = exactList(attempt.attemptHistory);
    if (history.length === 0) return [attempt];
    return history.map((event) => ({
      ...event,
      role: attempt.role,
      ...(event.status === "not_modified" &&
          attempt.parserCacheReusable === true
        ? { parserCacheReusable: true }
        : {}),
    }));
  });
  const additions = exactList(input.additions);
  const modifications = exactList(input.modifications);
  const removals = exactList(input.removals);
  const conflicts = exactList(input.conflicts);
  const catalogConflicts = exactList(input.catalogIdentityConflicts);
  const decisions = exactList(input.decisions);
  const required = attempts.filter((attempt) =>
    attempt.role === "required_supporting"
  );
  const blocked =
    attemptEvents.filter((attempt) =>
      attempt.status === "failed" &&
      blockedFetchCodes.has(String(attempt.errorCode ?? ""))
    ).length;
  const missing =
    attemptEvents.filter((attempt) =>
      attempt.status === "failed" &&
      missingFetchCodes.has(String(attempt.errorCode ?? ""))
    ).length;
  const failed =
    attemptEvents.filter((attempt) =>
      attempt.status === "failed" &&
      !blockedFetchCodes.has(String(attempt.errorCode ?? "")) &&
      !missingFetchCodes.has(String(attempt.errorCode ?? ""))
    ).length;
  const successes =
    attemptEvents.filter((attempt) => attempt.status === "success").length;
  const notModified =
    attemptEvents.filter((attempt) =>
      attempt.status === "not_modified" &&
      attempt.parserCacheReusable === true
    ).length;
  const requiredOmitted =
    required.filter((attempt) =>
      omittedRequiredCodes.has(String(attempt.errorCode ?? ""))
    ).length;
  const requiredSucceeded =
    required.filter((attempt) =>
      attempt.status === "success" ||
      (attempt.status === "not_modified" &&
        attempt.parserCacheReusable === true)
    ).length;
  const requiredFailed =
    required.filter((attempt) =>
      attempt.status === "failed" &&
      !omittedRequiredCodes.has(String(attempt.errorCode ?? ""))
    ).length;
  const identityMigrations =
    modifications.filter((item) =>
      item.changeType === "identity_migration" ||
      item.change_type === "identity_migration"
    ).length;
  const suppressed = typeof input.suppressedRemovals === "number" &&
      Number.isInteger(input.suppressedRemovals) &&
      input.suppressedRemovals >= 0
    ? input.suppressedRemovals
    : exactList(input.suppressedRemovals).length;
  const decisionCount = (action: string) =>
    decisions.filter((decision) => decision.action === action).length;
  const targetedRejects =
    decisions.filter((decision) =>
      decision.action === "reject" &&
      (Boolean(decision.benefit_id) ||
        (Object.hasOwn(decision, "proposal_index") &&
          Number.isInteger(decision.proposal_index) &&
          Number(decision.proposal_index) >= 0))
    ).length;
  const globalRejects =
    decisions.filter((decision) =>
      decision.action === "reject" &&
      !Boolean(decision.benefit_id) &&
      !(Object.hasOwn(decision, "proposal_index") &&
        Number.isInteger(decision.proposal_index) &&
        Number(decision.proposal_index) >= 0)
    ).length;
  const startedAt = typeof input.startedAt === "string"
    ? utcInstant(input.startedAt)
    : null;
  const completedAt = typeof input.completedAt === "string"
    ? utcInstant(input.completedAt)
    : null;
  if (
    startedAt === null || completedAt === null || completedAt < startedAt ||
    startedAt < Date.UTC(2000, 0, 1) ||
    completedAt > Date.now() + MAX_EVIDENCE_CLOCK_SKEW_MS ||
    completedAt - startedAt > 10 * 60 * 1000
  ) throw new Error("invalid_operational_metric_input");
  const attempted = attemptEvents.length;
  const decisiveSuccesses = successes + notModified;
  return {
    fetch_attempts: attempted,
    fetch_success: successes,
    fetch_not_modified: notModified,
    fetch_blocked: blocked,
    fetch_missing: missing,
    fetch_failed: failed,
    fetch_incomplete: input.crawlComplete === true ? 0 : 1,
    fetch_attempt_history_overflow:
      attempts.filter((attempt) => attempt.attemptHistoryOverflow === true)
        .length,
    fetch_success_rate: attempted === 0 ? 0 : decisiveSuccesses / attempted,
    required_supporting_attempted: required.length - requiredOmitted,
    required_supporting_succeeded: requiredSucceeded,
    required_supporting_failed: requiredFailed,
    required_supporting_omitted: requiredOmitted,
    required_supporting_success_rate: required.length === 0
      ? 1
      : requiredSucceeded / required.length,
    staged_additions: additions.length,
    staged_modifications: modifications.length - identityMigrations,
    staged_removals: removals.length,
    identity_migrations: identityMigrations,
    suppressed_removals: suppressed,
    suppressed_removal_reason_codes: suppressed > 0 &&
        input.crawlComplete !== true
      ? ["incomplete_crawl"]
      : [],
    proposal_conflicts: conflicts.length,
    catalog_identity_conflicts: catalogConflicts.length,
    approvals: decisionCount("approve"),
    edits: decisionCount("edit"),
    targeted_rejects: targetedRejects,
    global_rejects: globalRejects,
    retirements: decisionCount("retire"),
    retries: Number.isInteger(input.retryCount) && Number(input.retryCount) >= 0
      ? Number(input.retryCount)
      : decisionCount("retry"),
    deterministic_replay_passed: input.deterministicReplayPassed === true,
    side_effect_proof_passed: input.sideEffectProofPassed === true,
    processing_started_at: input.startedAt,
    processing_completed_at: input.completedAt,
    processing_duration_ms: completedAt - startedAt,
  };
}

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const operationalMetricKeys = new Set([
  "fetch_attempts",
  "fetch_success",
  "fetch_not_modified",
  "fetch_blocked",
  "fetch_missing",
  "fetch_failed",
  "fetch_incomplete",
  "fetch_attempt_history_overflow",
  "fetch_success_rate",
  "required_supporting_attempted",
  "required_supporting_succeeded",
  "required_supporting_failed",
  "required_supporting_omitted",
  "required_supporting_success_rate",
  "staged_additions",
  "staged_modifications",
  "staged_removals",
  "identity_migrations",
  "suppressed_removals",
  "proposal_conflicts",
  "catalog_identity_conflicts",
  "approvals",
  "edits",
  "targeted_rejects",
  "global_rejects",
  "retirements",
  "retries",
  "deterministic_replay_passed",
  "side_effect_proof_passed",
  "processing_started_at",
  "processing_completed_at",
  "processing_duration_ms",
]);

export function operationalLogEntry(
  input: Record<string, unknown>,
): Record<string, unknown> {
  const metrics = input.metrics && typeof input.metrics === "object" &&
      !Array.isArray(input.metrics)
    ? input.metrics as Record<string, unknown>
    : {};
  const safeMetrics = Object.fromEntries(
    Object.entries(metrics).filter(([key, value]) =>
      operationalMetricKeys.has(key) &&
      (typeof value === "boolean" ||
        (typeof value === "number" && Number.isFinite(value)) ||
        (typeof value === "string" && value.length <= 40 &&
          utcInstant(value) !== null))
    ).slice(0, 64),
  );
  const outcome = [
      "staged",
      "completed",
      "quarantined",
      "failed",
      "review_required",
    ].includes(String(input.outcome))
    ? String(input.outcome)
    : "failed";
  const metricReasonCodes = Array.isArray(
      metrics.suppressed_removal_reason_codes,
    )
    ? metrics.suppressed_removal_reason_codes
    : [];
  const reasonCodes = Array.isArray(input.reasonCodes)
    ? [
      ...new Set(
        [...input.reasonCodes, ...metricReasonCodes].map(String).filter((
          reason,
        ) => operationalReasonCodes.has(reason)),
      ),
    ].sort().slice(0, 16)
    : [];
  return {
    event: "card_benefit_ingestion_observation",
    ...(typeof input.jobId === "string" && uuid.test(input.jobId)
      ? { job_id: input.jobId.toLowerCase() }
      : {}),
    ...(typeof input.cardId === "string" && uuid.test(input.cardId)
      ? { card_id: input.cardId.toLowerCase() }
      : {}),
    outcome,
    reason_codes: reasonCodes,
    metrics: safeMetrics,
  };
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

const forbiddenStoredEvidenceKey =
  /(?:^|_)(?:raw_?body|response_?body|page_?html|document_?text|statement|customer|email|phone|last_?four|card_?number|lease_?token|access_?token|refresh_?token|password|secret|credential)(?:_|$)/i;

function safePilotReplayText(value: unknown): value is string {
  if (
    typeof value !== "string" || value.length === 0 ||
    new TextEncoder().encode(value).byteLength > MAX_PILOT_REPLAY_TEXT_BYTES ||
    redactSensitiveUrlsInText(value) !== value
  ) return false;
  let probe = value;
  for (let pass = 0; pass < 3; pass += 1) {
    try {
      const decoded = decodeURIComponent(probe);
      if (decoded === probe) break;
      probe = decoded;
    } catch {
      break;
    }
  }
  return !/(?:authorization\s*:\s*bearer|bearer\s+[a-z0-9._~-]{8,}|(?:access[_ -]?token|refresh[_ -]?token|lease[_ -]?token|password|secret|credential|customer[_ -]?(?:name|id|email|phone)|statement[_ -]?(?:id|header)|last[_ -]?four|card[_ -]?number)\s*[:=]\s*\S+)/i
    .test(probe);
}

function rawBodyWouldBeStored(value: unknown, depth = 0): boolean {
  if (depth > 12) return true;
  if (typeof value === "string") {
    if (value.length > 8_000 || redactSensitiveUrlsInText(value) !== value) {
      return true;
    }
    let probe = value;
    for (let pass = 0; pass < 3; pass += 1) {
      try {
        const decoded = decodeURIComponent(probe);
        if (decoded === probe) break;
        probe = decoded;
      } catch {
        break;
      }
    }
    return /(?:authorization\s*:\s*bearer|bearer\s+[a-z0-9._~-]{8,}|(?:access[_ -]?token|refresh[_ -]?token|lease[_ -]?token|password|secret|credential|customer[_ -]?(?:name|id|email|phone)|statement[_ -]?(?:id|header)|last[_ -]?four|card[_ -]?number)\s*[:=]\s*\S+)/i
      .test(probe);
  }
  if (Array.isArray(value)) {
    return value.length > 512 ||
      value.some((item) => rawBodyWouldBeStored(item, depth + 1));
  }
  if (!value || typeof value !== "object") return false;
  const entries = Object.entries(value as Record<string, unknown>);
  return entries.length > 512 ||
    entries.some(([key, item]) =>
      key === "public_text"
        ? !safePilotReplayText(item)
        : (key === "raw_body_stored"
          ? item !== false
          : key === "document_text_hash"
          ? !(typeof item === "string" && lowercaseSha256.test(item))
          : forbiddenStoredEvidenceKey.test(key)) ||
          rawBodyWouldBeStored(item, depth + 1)
    );
}

export function assertSafePersistedEvidence(value: unknown): void {
  let encoded: string;
  try {
    encoded = stableCanonicalJson(value);
  } catch {
    throw new Error("unsafe_persisted_evidence");
  }
  if (
    new TextEncoder().encode(encoded).byteLength > 1_048_576 ||
    rawBodyWouldBeStored(value)
  ) throw new Error("unsafe_persisted_evidence");
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
  const processingStartedAt = new Date().toISOString();
  let outcome: JobOutcome = "failed";
  let retried = false;
  let failureCategory: string | null = null;
  let nextRetryAt: string | null = null;
  let stagingId: string | null = null;
  let contentHash: string | null = null;
  let normalizedFields: Record<string, unknown> = {};
  let metricAttempts: SourceAttempt[] = [];
  let metricCrawlComplete = false;
  let metricAdditions: Array<Record<string, unknown>> = [];
  let metricModifications: Array<Record<string, unknown>> = [];
  let metricRemovals: Array<Record<string, unknown>> = [];
  let metricSuppressedRemovalCount = 0;
  let metricConflicts: Array<Record<string, unknown>> = [];
  let pilotBefore: PilotLiveStateSnapshot | null = null;
  let pilotReplay:
    | Awaited<ReturnType<typeof computePilotReplayEvidence>>
    | null = null;
  let pilotObservedAt: string | null = null;
  let pilotStagingContentHash: string | null = null;
  let pilotPreviousCanonicalBenefitHash: string | null = null;
  let metricCatalogIdentityConflictCount = -1;
  const persistedArtifacts: unknown[] = [];
  let resultSummary: Record<string, unknown> = {
    run_id: runId,
    unsafe_mutation_count: 0,
    raw_body_stored: false,
    evidence_passed: false,
    idempotency_passed: false,
  };

  try {
    if (job.run_mode === "pilot") {
      pilotBefore = await capturePilotLiveStateSnapshot(db, job.card_id);
    }
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
      metricAttempts = crawl.attempts;
      metricCrawlComplete = crawl.complete;
      pilotObservedAt = observedAt;
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
      metricAttempts = crawl.attempts;
      metricCrawlComplete = crawl.complete;
      pilotObservedAt = attemptedAt;
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
      metricAttempts = crawl.attempts;
      metricCrawlComplete = crawl.complete;
      pilotObservedAt = page.retrievedAt;
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
    const {
      documents,
      expectedRequiredSourceKeys,
      requiredSourceSelectionOverflow,
    } = collected;
    const assessmentTime = new Date().toISOString();
    const validatedAt = observationValidatedAt(
      page.retrievedAt,
      assessmentTime,
    );
    const crawl = assessCrawlCompleteness(collected.attempts, assessmentTime);
    metricAttempts = crawl.attempts;
    metricCrawlComplete = crawl.complete;
    pilotObservedAt = validatedAt;
    fetchSummary.crawl_complete = crawl.complete;
    const sourceManifestHash = await computeSourceManifestHash(crawl.attempts);
    contentHash = sourceManifestHash;
    let proposed: BenefitComparisonProposal[];
    if (job.parser_version === "benefits-v6" && job.run_mode === "pilot") {
      const pilotAttempts = pilotVerificationSourceAttempts(crawl.attempts);
      const pilotSourceManifestHash = await computeSourceManifestHash(
        pilotAttempts,
      );
      pilotReplay = await computePilotReplayEvidence({
        jobId: job.id,
        cardId: job.card_id,
        parserVersion: job.parser_version,
        runMode: job.run_mode,
        sourceManifestHash: pilotSourceManifestHash,
        expectedRequiredSourceKeys,
        requiredSourceSelectionOverflow,
        attempts: pilotAttempts,
        documents,
      });
      proposed = pilotReplay.proposals;
    } else {
      proposed = job.parser_version === "benefits-v6"
        ? await extractGroundedBenefitsV6(
          documents,
          "benefits-v6",
          job.card_id,
        )
        : extractGroundedBenefits(documents, job.parser_version);
    }
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
    metricAdditions = compared.additions;
    metricModifications = compared.modifications;
    metricRemovals = compared.possibleRemovals;
    metricSuppressedRemovalCount = removalPolicy.suppressedRemovalCount;
    metricConflicts = compared.conflicts;
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
    if (job.run_mode === "pilot") pilotStagingContentHash = stagingContentHash;
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
      ...(pilotReplay
        ? { retained_documents: pilotReplay.retainedDocuments }
        : {}),
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
    // This is the last boundary before any proposal/evidence can enter
    // staging. The finalizer repeats the same fail-closed check below.
    assertSafePersistedEvidence([safeExtraction, sourceEvidence]);
    persistedArtifacts.push(safeExtraction, sourceEvidence);
    const previousObservation = latestValidCrawlObservation(
      job.result_summary,
      validatedAt,
    );
    const previousCanonicalHash = typeof previousObservation
        ?.canonical_benefit_hash === "string"
      ? previousObservation.canonical_benefit_hash
      : null;
    if (job.run_mode === "pilot") {
      pilotPreviousCanonicalBenefitHash = previousCanonicalHash;
    }
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
    if (
      error instanceof Error && error.message === "unsafe_persisted_evidence"
    ) {
      // Unsafe in-memory parser output must not be copied into pilot replay or
      // final evidence after the pre-staging boundary rejects it.
      pilotReplay = null;
      persistedArtifacts.length = 0;
      normalizedFields = {};
      resultSummary = {};
    }
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
    const processingCompletedAt = new Date().toISOString();
    let pilotAfter: PilotLiveStateSnapshot | null = null;
    if (job.run_mode === "pilot" && pilotBefore) {
      try {
        pilotAfter = await capturePilotLiveStateSnapshot(db, job.card_id);
      } catch {
        outcome = "review_required";
        failureCategory = "pilot_side_effect_proof_failed";
      }
    }
    metricSuppressedRemovalCount = Number.isInteger(
        resultSummary.suppressed_removal_count,
      )
      ? Number(resultSummary.suppressed_removal_count)
      : metricSuppressedRemovalCount;
    const rawBodyStored = rawBodyWouldBeStored([
      normalizedFields,
      resultSummary,
      ...persistedArtifacts,
    ]);
    const unsafeMutationCount = pilotBefore && pilotAfter
      ? liveStateMutationCount(pilotBefore, pilotAfter)
      : job.run_mode === "pilot"
      ? -1
      : 0;
    const sideEffectProofPassed = unsafeMutationCount === 0;
    try {
      metricCatalogIdentityConflictCount =
        await readPilotCatalogIdentityConflictCount(
          db,
          job.card_id,
          job.canonical_url,
        );
    } catch {
      metricCatalogIdentityConflictCount = -1;
      if (job.run_mode === "pilot") {
        outcome = "review_required";
        failureCategory = "pilot_catalog_identity_check_failed";
      }
    }
    const operationalMetrics = buildOperationalMetrics({
      attempts: metricAttempts,
      crawlComplete: metricCrawlComplete,
      additions: metricAdditions,
      modifications: metricModifications,
      removals: metricRemovals,
      suppressedRemovals: metricSuppressedRemovalCount,
      conflicts: metricConflicts,
      catalogIdentityConflicts: metricCatalogIdentityConflictCount > 0
        ? Array.from({ length: metricCatalogIdentityConflictCount }, () => ({
          kind: "pending_catalog_identity_review",
        }))
        : [],
      decisions: [],
      retryCount: retried ? 1 : 0,
      deterministicReplayPassed:
        pilotReplay?.deterministicReplayPassed === true,
      sideEffectProofPassed,
      startedAt: processingStartedAt,
      completedAt: processingCompletedAt,
    });
    const retainedPilotEvidence = job.run_mode === "scheduled" &&
        job.result_summary?.pilot_qualified === true &&
        job.normalized_fields?.pilot_evidence &&
        typeof job.normalized_fields.pilot_evidence === "object"
      ? job.normalized_fields.pilot_evidence
      : null;
    const pilotProfile = typeof job.result_summary?.pilot_profile === "string"
      ? job.result_summary.pilot_profile
      : typeof job.normalized_fields?.pilot_profile === "string"
      ? job.normalized_fields.pilot_profile
      : null;
    normalizedFields = {
      ...normalizedFields,
      ...(pilotProfile ? { pilot_profile: pilotProfile } : {}),
      ...(retainedPilotEvidence
        ? { pilot_evidence: retainedPilotEvidence }
        : {}),
      operational_metrics: operationalMetrics,
    };
    if (
      job.run_mode === "pilot" && pilotReplay && pilotBefore && pilotAfter &&
      pilotObservedAt
    ) {
      const pilotEvidence = {
        parser_version: job.parser_version,
        job_id: job.id,
        card_id: job.card_id,
        run_mode: job.run_mode,
        canonical_hash: pilotReplay.canonicalHash,
        repeat_canonical_hash: pilotReplay.repeatCanonicalHash,
        deterministic_replay_passed: pilotReplay.deterministicReplayPassed,
        source_manifest_hash: pilotReplay.sourceManifestHash,
        source_attempts: pilotReplay.sourceAttempts,
        expected_required_source_keys: pilotReplay.expectedRequiredSourceKeys,
        required_source_selection_overflow:
          pilotReplay.requiredSourceSelectionOverflow,
        verification_envelope: pilotReplay.verificationEnvelope,
        repeat_verification_envelope: pilotReplay.repeatVerificationEnvelope,
        replay_input: pilotReplay.replayInput,
        crawl_complete: metricCrawlComplete,
        suppressed_removal_count: metricSuppressedRemovalCount,
        unsafe_mutation_count: unsafeMutationCount,
        raw_body_stored: rawBodyStored,
        side_effect_proof_passed: sideEffectProofPassed,
        observed_at: pilotObservedAt,
        live_state_before: pilotBefore,
        live_state_after: pilotAfter,
        conflict_count: metricConflicts.length,
        catalog_identity_conflict_count: metricCatalogIdentityConflictCount,
        proposal_count: resultSummary.proposals,
        proposal_disposition: resultSummary.proposal_disposition,
        canonical_benefit_hash: resultSummary.canonical_benefit_hash,
        previous_canonical_benefit_hash: pilotPreviousCanonicalBenefitHash,
        staging_id: stagingId,
        staging_content_hash: stagingId ? pilotStagingContentHash : null,
      };
      normalizedFields.pilot_evidence = pilotEvidence;
      resultSummary = {
        ...resultSummary,
        parser_version: job.parser_version,
        canonical_hash: pilotReplay.canonicalHash,
        repeat_canonical_hash: pilotReplay.repeatCanonicalHash,
        deterministic_replay_passed: pilotReplay.deterministicReplayPassed,
        source_manifest_hash: pilotReplay.sourceManifestHash,
        crawl_complete: metricCrawlComplete,
        suppressed_removal_count: metricSuppressedRemovalCount,
        unsafe_mutation_count: Math.max(0, unsafeMutationCount),
        raw_body_stored: rawBodyStored,
        side_effect_proof_passed: sideEffectProofPassed,
        idempotency_passed: pilotReplay.deterministicReplayPassed,
        evidence_passed: pilotReplay.deterministicReplayPassed &&
          metricCrawlComplete && metricSuppressedRemovalCount === 0 &&
          sideEffectProofPassed && !rawBodyStored &&
          metricConflicts.length === 0,
        operational_metrics: operationalMetrics,
      };
    } else {
      resultSummary = {
        ...resultSummary,
        raw_body_stored: rawBodyStored,
        ...(job.run_mode === "pilot"
          ? {
            unsafe_mutation_count: Math.max(0, unsafeMutationCount),
            evidence_passed: false,
            idempotency_passed: false,
          }
          : {}),
        operational_metrics: operationalMetrics,
      };
    }
    assertSafePersistedEvidence([normalizedFields, resultSummary]);
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
    if (import.meta.main) {
      console.info(JSON.stringify(operationalLogEntry({
        jobId: job.id,
        cardId: job.card_id,
        outcome,
        reasonCodes: [
          failureCategory,
          (resultSummary.observation as Record<string, unknown> | undefined)
            ?.crawl_reason,
        ].filter((value): value is string => typeof value === "string"),
        metrics: operationalMetrics,
      })));
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
