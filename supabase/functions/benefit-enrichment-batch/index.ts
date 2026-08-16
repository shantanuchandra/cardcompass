import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @deno-types="data:application/typescript,export%20declare%20function%20createClient(...args%3A%20any%5B%5D)%3A%20any%3B"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?bundle&target=deno&no-dts";
import {
  type BenefitProposal,
  diffBenefits,
  extractGroundedBenefits,
} from "../_shared/benefit_enrichment.ts";
import { normalizedProduct } from "../_shared/card_discovery.ts";
import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
  persistCrawlerCandidate,
} from "../_shared/issuer_card_crawl.ts";
import { fetchOfficialIssuerResource } from "../_shared/official_issuer_fetch.ts";
import {
  evaluatePilotGate,
  failureDisposition,
  findReusableStaging,
  LEASE_SECONDS,
  MAX_BATCH_SIZE,
  type PilotJob,
  type RunMode,
  runSequentially,
  safeFailureCategory,
} from "./batch_policy.ts";

type UntypedSupabaseClient = any;

type EnrichmentJob = {
  id: string;
  card_id: string;
  issuer: string;
  canonical_url: string;
  parser_version: string;
  attempt_count: number;
  run_mode: RunMode;
};

type JobOutcome = "staged" | "quarantined" | "failed" | "review_required";

type ProcessResult = {
  outcome: JobOutcome;
  retried: boolean;
};

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

function equalSecret(actual: string | null, expected: string): boolean {
  if (!actual || !expected) return false;
  const encoder = new TextEncoder();
  const left = encoder.encode(actual);
  const right = encoder.encode(expected);
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function authorized(
  request: Request,
  serviceKey: string,
  cronSecret: string,
): boolean {
  const bearer =
    request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1] ??
      null;
  return equalSecret(bearer, serviceKey) ||
    equalSecret(request.headers.get("x-cardcompass-cron-secret"), cronSecret);
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

async function readPilotStatus(db: UntypedSupabaseClient) {
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .select("id,run_mode,status,failure_category,result_summary")
    .eq("run_mode", "pilot");
  if (error) throw error;
  return evaluatePilotGate((data ?? []).map(pilotJob));
}

function currentBenefitProposal(
  row: Record<string, any>,
): BenefitProposal | null {
  const benefit = row.benefit ?? row.benefits ?? row;
  if (!benefit || typeof benefit !== "object" || !benefit.dedupe_key) {
    return null;
  }
  const config =
    benefit.value_config && typeof benefit.value_config === "object"
      ? benefit.value_config
      : {};
  return {
    dedupeKey: String(benefit.dedupe_key),
    title: String(benefit.title ?? "Existing benefit"),
    description: String(benefit.description ?? "").slice(0, 500),
    category: String(benefit.benefit_category ?? "other"),
    ...(benefit.benefit_type
      ? { valueType: String(benefit.benefit_type) }
      : {}),
    ...(Number.isFinite(Number(config.value))
      ? { value: Number(config.value) }
      : {}),
    ...(Number.isFinite(Number(config.rate))
      ? { rate: Number(config.rate) }
      : {}),
    ...(Number.isFinite(Number(config.cap)) ? { cap: Number(config.cap) } : {}),
    ...(Number.isFinite(Number(config.threshold))
      ? { threshold: Number(config.threshold) }
      : {}),
    ...(config.frequency ? { frequency: String(config.frequency) } : {}),
    ...(config.period ? { period: String(config.period) } : {}),
    restrictions: Array.isArray(config.restrictions)
      ? config.restrictions.map(String)
      : [],
    exclusions: Array.isArray(benefit.exclusions)
      ? benefit.exclusions.map(String)
      : [],
    ...(benefit.valid_from
      ? { effectiveFrom: String(benefit.valid_from) }
      : {}),
    ...(benefit.valid_until
      ? { effectiveTo: String(benefit.valid_until) }
      : {}),
    sourceUrl: String(benefit.source_url ?? ""),
    sourceExcerpt: String(benefit.description ?? "").slice(0, 500),
    contentHash: "current-approved-benefit",
    parserVersion: "current-approved-benefit",
    confidence: {},
    evidence: {},
    warnings: [],
  };
}

async function readCurrentBenefits(
  db: UntypedSupabaseClient,
  cardId: string,
): Promise<BenefitProposal[]> {
  const { data, error } = await db.from("card_benefit_mapping")
    .select("benefit:benefits(*)")
    .eq("card_id", cardId);
  if (error) throw error;
  return (data ?? []).map(currentBenefitProposal)
    .filter((benefit: BenefitProposal | null): benefit is BenefitProposal =>
      benefit !== null
    );
}

async function stagingForContent(
  db: UntypedSupabaseClient,
  job: EnrichmentJob,
  sourceUrl: string,
  contentHash: string,
): Promise<string | null> {
  const { data, error } = await db.from("card_benefits_staging")
    .select("id,card_id,source_url,extracted_data")
    .eq("card_id", job.card_id)
    .eq("source_url", sourceUrl)
    .order("created_at", { ascending: false })
    .limit(20);
  if (error) throw error;
  const reusable = findReusableStaging(
    (data ?? []).map((row: Record<string, any>) => ({
      id: String(row.id),
      cardId: String(row.card_id),
      sourceUrl: String(row.source_url),
      requestType: String(row.extracted_data?.request_type ?? ""),
      parserVersion: String(row.extracted_data?.parser_version ?? ""),
      contentHash: String(row.extracted_data?.content_hash ?? ""),
    })),
    {
      cardId: job.card_id,
      sourceUrl,
      parserVersion: job.parser_version,
      contentHash,
    },
  );
  return reusable?.id ?? null;
}

async function catalogIdentity(db: UntypedSupabaseClient, cardId: string) {
  const [
    { data: card, error: cardError },
    { data: aliases, error: aliasError },
  ] = await Promise.all([
    db.from("card_catalog").select(
      "id,card_name,bank,network,card_type,card_url,is_discontinued",
    )
      .eq("id", cardId).single(),
    db.from("card_catalog_aliases").select("alias").eq("card_id", cardId),
  ]);
  if (cardError || !card) throw cardError ?? new Error("identity_mismatch");
  if (aliasError) throw aliasError;
  return {
    card,
    aliases: (aliases ?? []).map((row: Record<string, any>) =>
      String(row.alias)
    ),
  };
}

function requireMatchingIdentity(
  job: EnrichmentJob,
  cardName: string,
  aliases: string[],
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
  const proposed = normalizedProduct(
    classification.proposedName ?? "",
    job.issuer,
  );
  const expected = [cardName, ...aliases].map((value) =>
    normalizedProduct(value, job.issuer)
  )
    .filter((value) => value.length >= 2);
  if (
    !proposed ||
    !expected.some((value) =>
      proposed === value || proposed.includes(value) || value.includes(proposed)
    )
  ) {
    throw new Error("identity_mismatch");
  }
}

async function processJob(
  db: UntypedSupabaseClient,
  job: EnrichmentJob,
  runId: string,
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
    const { card, aliases } = await catalogIdentity(db, job.card_id);
    const page = await fetchOfficialIssuerResource({
      issuer: job.issuer,
      url: job.canonical_url,
      contentPurpose: "document",
    });
    contentHash = page.contentHash;
    requireMatchingIdentity(
      job,
      String(card.card_name),
      aliases,
      page.text,
      page.canonicalUrl,
    );

    stagingId = await stagingForContent(
      db,
      job,
      page.canonicalUrl,
      page.contentHash,
    );
    if (stagingId) {
      outcome = "staged";
      resultSummary = {
        run_id: runId,
        proposals: 0,
        reused_staging: true,
        unsafe_mutation_count: 0,
        raw_body_stored: false,
        evidence_passed: true,
        idempotency_passed: true,
      };
      return { outcome, retried };
    }

    const proposed = extractGroundedBenefits([{
      sourceUrl: page.canonicalUrl,
      text: page.text,
      contentHash: page.contentHash,
    }], job.parser_version);
    if (proposed.length === 0) throw new Error("insufficient_evidence");
    const current = await readCurrentBenefits(db, job.card_id);
    const compared = diffBenefits(current, proposed);
    const confidenceValues = proposed.flatMap((benefit) =>
      Object.values(benefit.confidence)
    );
    const calculatedConfidence = confidenceValues.length > 0
      ? Math.min(...confidenceValues)
      : 0;
    const safeExtraction = {
      request_type: "official_benefit_enrichment",
      parser_version: job.parser_version,
      content_hash: page.contentHash,
      retrieved_at: page.retrievedAt,
      proposals: proposed,
      diff: compared,
    };
    const { data: staged, error: stageError } = await db.from(
      "card_benefits_staging",
    )
      .insert({
        card_id: job.card_id,
        source_url: page.canonicalUrl,
        extracted_data: safeExtraction,
        status: "pending",
        validation_version: job.parser_version,
        calculated_confidence: calculatedConfidence,
        validation_reasons: [{ code: "official_issuer_source" }],
        validation_warnings: proposed.flatMap((benefit) => benefit.warnings)
          .map((code) => ({ code })),
        source_evidence: proposed.map((benefit) => ({
          dedupe_key: benefit.dedupeKey,
          source_url: benefit.sourceUrl,
          source_excerpt: benefit.sourceExcerpt,
          evidence: benefit.evidence,
        })),
        validated_at: new Date().toISOString(),
      }).select("id").single();
    if (stageError || !staged) {
      throw stageError ?? new Error("enrichment_failed");
    }
    stagingId = String(staged.id);
    outcome = "staged";
    normalizedFields = { proposed_count: proposed.length };
    resultSummary = {
      run_id: runId,
      proposals: proposed.length,
      additions: compared.additions.length,
      modifications: compared.modifications.length,
      possible_removals: compared.possibleRemovals.length,
      conflicts: compared.conflicts.length,
      reused_staging: false,
      unsafe_mutation_count: 0,
      raw_body_stored: false,
      evidence_passed: proposed.every((benefit) =>
        Object.keys(benefit.confidence).every((field) =>
          Boolean(benefit.evidence[field])
        )
      ),
      idempotency_passed: true,
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
    const { error: finalizeError } = await db.from(
      "card_catalog_enrichment_jobs",
    ).update({
      status: outcome,
      lease_expires_at: null,
      staging_id: stagingId,
      content_hash: contentHash,
      normalized_fields: normalizedFields,
      result_summary: resultSummary,
      failure_category: failureCategory,
      next_retry_at: nextRetryAt,
      updated_at: new Date().toISOString(),
    }).eq("id", job.id).eq("status", "processing");
    if (finalizeError) throw finalizeError;
  }
}

async function runIssuerDiscovery(
  db: UntypedSupabaseClient,
  job: EnrichmentJob,
): Promise<void> {
  try {
    const sitemapUrl = new URL("/sitemap.xml", job.canonical_url).toString();
    const result = await discoverIssuerCardCandidates({
      issuer: job.issuer,
      sitemapUrl,
    });
    for (const candidate of result.candidates) {
      if (candidate.kind === "card_product") {
        await persistCrawlerCandidate(db, job.issuer, candidate);
      }
    }
  } catch {
    // Issuer-wide discovery is best-effort and must not strand already leased
    // benefit jobs. The next issuer run can safely retry persisted candidates.
  }
}

export async function handleBenefitEnrichmentBatch(
  request: Request,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const cronSecret = Deno.env.get("BENEFIT_ENRICHMENT_CRON_SECRET") ?? "";
  if (!authorized(request, serviceKey, cronSecret)) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    // An empty scheduler body selects the scheduled lane.
  }
  const runMode = runModeFromRequest(body.runMode ?? body.run_mode);
  if (!runMode) return json({ error: "invalid_run_mode" }, 400);

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
  const runId = crypto.randomUUID();
  try {
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

    const { count: queued, error: countError } = await db
      .from("card_catalog_enrichment_jobs")
      .select("id", { count: "exact", head: true })
      .eq("run_mode", runMode)
      .in("status", ["queued", "failed"])
      .or(
        `next_retry_at.is.null,next_retry_at.lte.${new Date().toISOString()}`,
      );
    if (countError) throw countError;

    const { data: claimed, error: claimError } = await db.rpc(
      "claim_card_catalog_enrichment_jobs",
      {
        _max_jobs: MAX_BATCH_SIZE,
        _lease_seconds: LEASE_SECONDS,
        _run_mode: runMode,
      },
    );
    if (claimError) throw claimError;
    const jobs = (claimed ?? []) as EnrichmentJob[];
    const results = await runSequentially(
      jobs,
      async (job) => {
        try {
          return await processJob(db, job, runId);
        } catch {
          // A failed final database write cannot be repaired in-memory, but it
          // must not stop later claimed rows from reaching their finally path.
          return { outcome: "failed", retried: false } as ProcessResult;
        }
      },
    );
    if (jobs[0]) await runIssuerDiscovery(db, jobs[0]);
    const finalPilot = await readPilotStatus(db);
    return json({
      runId,
      queued: Number(queued ?? 0),
      claimed: jobs.length,
      staged: results.filter((result) => result.outcome === "staged").length,
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
