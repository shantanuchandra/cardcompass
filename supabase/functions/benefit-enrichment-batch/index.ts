import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @deno-types="data:application/typescript,export%20declare%20function%20createClient(...args%3A%20any%5B%5D)%3A%20any%3B"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?bundle&target=deno&no-dts";
import {
  type BenefitProposal,
  diffBenefits,
  extractGroundedBenefits,
} from "../_shared/benefit_enrichment.ts";
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
import { fetchOfficialIssuerResource } from "../_shared/official_issuer_fetch.ts";
import {
  assertBenefitParserVersion,
  type BenefitEnrichmentQueueInput,
  enqueueBenefitEnrichmentJobs,
  evaluatePilotGate,
  failureDisposition,
  LEASE_SECONDS,
  MAX_BATCH_SIZE,
  type PilotCandidate,
  type PilotJob,
  type RunMode,
  runSequentially,
  safeFailureCategory,
  secureSecretEqual,
  selectPilotCandidates,
} from "./batch_policy.ts";
import { collectSupportingBenefitDocuments } from "./supporting_documents.ts";

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
};

type JobOutcome = "staged" | "quarantined" | "failed" | "review_required";

type ProcessResult = {
  outcome: JobOutcome;
  retried: boolean;
};

export const CURRENT_BENEFIT_PARSER_VERSION = "benefits-v5";

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

export function currentBenefitProposal(
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
    valueConfig: config,
    partners: Array.isArray(benefit.partners)
      ? benefit.partners.map(String)
      : [],
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

async function sha256Text(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
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
      .eq("is_discontinued", false)
      .ilike("card_type", "credit")
      .like("card_url", "https://%")
      .order("id", { ascending: true })
      .range(offset, offset + boundedPageSize - 1);
    if (error) throw error;
    const rows = (data ?? []) as Array<Record<string, unknown>>;
    const queueInputs: BenefitEnrichmentQueueInput[] = [];
    for (const row of rows) {
      if (
        row.is_discontinued !== false ||
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
  const proposed = normalizedProduct(proposedName, issuer);
  if (proposed.length < 2) throw new Error("identity_mismatch");
  const activeIds = new Set(catalog.map((row) => String(row.id)));
  const matches = new Set<string>();
  for (const row of catalog) {
    if (normalizedProduct(row.card_name, issuer) === proposed) {
      matches.add(String(row.id));
    }
  }
  for (const alias of aliases) {
    if (
      activeIds.has(String(alias.card_id)) &&
      normalizedProduct(alias.alias, issuer) === proposed
    ) {
      matches.add(String(alias.card_id));
    }
  }
  if (matches.size > 1) throw new Error("ambiguous_product");
  if (matches.size !== 1 || !matches.has(targetCardId)) {
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
    const { card, catalog, aliases } = await loadCatalogIdentity(
      db,
      job.card_id,
    );
    const page = await fetchOfficialIssuerResource({
      issuer: job.issuer,
      url: job.canonical_url,
      contentPurpose: "document",
      maxBytes: 2 * 1024 * 1024,
    });
    contentHash = page.contentHash;
    requireMatchingIdentity(
      job,
      catalog,
      aliases,
      page.text,
      page.canonicalUrl,
    );
    const documents = await collectSupportingBenefitDocuments({
      issuer: job.issuer,
      primary: page,
      // Keep each five-card batch comfortably inside Edge compute limits.
      // The crawler still supports the audited hard ceiling of eight.
      maximumLinks: 1,
      identityLabels: [
        String(card.card_name ?? ""),
        ...aliases.filter((alias: Record<string, unknown>) =>
          String(alias.card_id) === job.card_id
        ).map((alias: Record<string, unknown>) => String(alias.alias ?? "")),
      ],
    });
    contentHash = await sha256Text(
      documents.map((document) =>
        `${document.sourceUrl}:${document.contentHash ?? ""}`
      ).join("\n"),
    );
    const proposed = extractGroundedBenefits(documents, job.parser_version);
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
      content_hash: contentHash,
      retrieved_at: page.retrievedAt,
      source_documents: documents.map((document) => ({
        source_url: document.sourceUrl,
        content_hash: document.contentHash ?? null,
      })),
      proposals: proposed,
      diff: compared,
    };
    const sourceEvidence = proposed.map((benefit) => ({
      dedupe_key: benefit.dedupeKey,
      source_url: benefit.sourceUrl,
      source_excerpt: benefit.sourceExcerpt,
      evidence: benefit.evidence,
    }));
    const { data: stagedRows, error: stageError } = await db.rpc(
      "stage_card_benefit_enrichment",
      {
        _job_id: job.id,
        _lease_token: job.lease_token,
        _source_url: page.canonicalUrl,
        _source_url_hash: await sha256Text(page.canonicalUrl),
        _parser_version: job.parser_version,
        _content_hash: contentHash,
        _extracted_data: safeExtraction,
        _calculated_confidence: calculatedConfidence,
        _validation_reasons: [{ code: "official_issuer_source" }],
        _validation_warnings: proposed.flatMap((benefit) => benefit.warnings)
          .map((code) => ({ code })),
        _source_evidence: sourceEvidence,
        _validated_at: new Date().toISOString(),
      },
    );
    const staged = Array.isArray(stagedRows) ? stagedRows[0] : stagedRows;
    if (stageError || !staged?.staging_id) {
      throw stageError ?? new Error("enrichment_failed");
    }
    stagingId = String(staged.staging_id);
    outcome = "staged";
    normalizedFields = {
      proposed_count: proposed.length,
      source_document_count: documents.length,
    };
    resultSummary = {
      run_id: runId,
      proposals: proposed.length,
      source_documents: documents.length,
      additions: compared.additions.length,
      modifications: compared.modifications.length,
      possible_removals: compared.possibleRemovals.length,
      conflicts: compared.conflicts.length,
      reused_staging: staged.reused === true,
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
): Promise<void> {
  const fallback = issuerDiscoveryFallbackUrls(job.canonical_url);
  const result = await discoverIssuerCardCandidates({
    issuer: job.issuer,
    sitemapUrls: fallback.sitemapUrls,
    indexUrls: fallback.indexUrls,
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
        _max_jobs: runMode === "scheduled" ? 1 : MAX_BATCH_SIZE,
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
          return await processJob(db, job, runId);
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
    if (jobs.length === 0 && Number(queued ?? 0) === 0) {
      const discoverySeed = await loadDiscoverySeed(db);
      if (discoverySeed) {
        EdgeRuntime.waitUntil(
          runIssuerDiscovery(db, discoverySeed).catch((error) => {
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
