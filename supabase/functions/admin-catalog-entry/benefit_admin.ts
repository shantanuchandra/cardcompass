export type UntypedSupabaseClient = any;

export class BenefitAdminError extends Error {
  constructor(
    readonly code: string,
    readonly status = 400,
  ) {
    super(code);
  }
}

const benefitActions = new Set([
  "benefit-list",
  "benefit-status",
  "benefit-approve",
  "benefit-edit-approve",
  "benefit-reject",
  "benefit-retry",
  "benefit-quarantine",
  "benefit-unquarantine",
  "benefit-start-pilot",
]);

const safeJobColumns = `
  id, card_id, issuer, canonical_url, parser_version, status, run_mode,
  attempt_count, staging_id, failure_category, next_retry_at, normalized_fields,
  result_summary, created_at, updated_at,
  card_catalog!inner(id, bank, card_name),
  card_benefits_staging!card_catalog_enrichment_jobs_staging_id_fkey(
    id, card_id, request_type, parser_version, source_url, source_url_hash,
    content_hash, status, calculated_confidence, validation_reasons,
    validation_warnings, source_evidence, extracted_data, benefit_decisions,
    created_at, reviewed_at
  )
`;

const pilotProfiles = new Set([
  "straightforward",
  "redirect_or_js",
  "terms_linked",
  "known_invalid",
  "additional_valid",
]);

type Actor = { id: string };
type JsonRecord = Record<string, unknown>;
const benefitRunModes = ["pilot", "scheduled", "manual"];
const jobStatuses = [
  "queued",
  "processing",
  "completed",
  "review_required",
  "failed",
  "staged",
  "quarantined",
];
const benefitFields = [
  "dedupeKey",
  "title",
  "description",
  "category",
  "valueType",
  "value",
  "rate",
  "cap",
  "threshold",
  "frequency",
  "period",
  "restrictions",
  "exclusions",
  "effectiveFrom",
  "effectiveTo",
] as const;
const evidenceFields = [
  "title",
  "description",
  "category",
  "valueType",
  "value",
  "rate",
  "cap",
  "threshold",
  "frequency",
  "period",
  "restrictions",
  "exclusions",
  "effectiveFrom",
  "effectiveTo",
] as const;

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function requiredId(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new BenefitAdminError(`${field}_is_required`);
  }
  return value.trim();
}

function requiredReason(value: unknown): string {
  if (typeof value !== "string" || value.trim().length < 3) {
    throw new BenefitAdminError("rejection_reason_is_required");
  }
  return value.trim().slice(0, 500);
}

function text(value: unknown, maximum = 8_000): string | null {
  return typeof value === "string" ? value.slice(0, maximum) : null;
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function textList(value: unknown): string[] {
  return Array.isArray(value)
    ? value.flatMap((item) =>
      typeof item === "string" ? [item.slice(0, 500)] : []
    )
    : [];
}

function objectList(value: unknown): JsonRecord[] {
  return Array.isArray(value)
    ? value.flatMap((item) => {
      const record = asRecord(item);
      return record ? [record] : [];
    })
    : [];
}

function fieldEvidence(value: unknown) {
  const row = asRecord(value) ?? {};
  return Object.fromEntries(evidenceFields.flatMap((field) => {
    const excerpt = text(row[field], 500);
    return excerpt === null ? [] : [[field, excerpt]];
  }));
}

function fieldConfidence(value: unknown) {
  const row = asRecord(value) ?? {};
  return Object.fromEntries(evidenceFields.flatMap((field) => {
    const confidence = number(row[field]);
    return confidence === null ? [] : [[field, confidence]];
  }));
}

function benefitForOutput(value: unknown) {
  const row = asRecord(value) ?? {};
  const scalar: JsonRecord = {};
  for (const field of benefitFields) {
    const value = row[field];
    if (typeof value === "string") scalar[field] = value.slice(0, 2_000);
    if (typeof value === "number" && Number.isFinite(value)) {
      scalar[field] = value;
    }
    if (
      (field === "restrictions" || field === "exclusions") &&
      Array.isArray(value)
    ) {
      scalar[field] = textList(value);
    }
  }
  return {
    ...scalar,
    sourceUrl: text(row.sourceUrl),
    sourceUrls: textList(row.sourceUrls),
    sourceExcerpt: text(row.sourceExcerpt, 500),
    contentHash: text(row.contentHash, 200),
    parserVersion: text(row.parserVersion, 100),
    confidence: fieldConfidence(row.confidence),
    evidence: fieldEvidence(row.evidence),
    warnings: textList(row.warnings),
  };
}

function benefitDiff(value: unknown) {
  const row = asRecord(value) ?? {};
  return {
    additions: objectList(row.additions).map(benefitForOutput),
    modifications: objectList(row.modifications).map((item) => ({
      current: benefitForOutput(item.current),
      proposed: benefitForOutput(item.proposed),
    })),
    possibleRemovals: objectList(row.possibleRemovals).map((item) => ({
      benefit: benefitForOutput(item.benefit),
      informational: item.informational === true,
    })),
    unchanged: objectList(row.unchanged).map((item) => ({
      current: benefitForOutput(item.current),
      proposed: benefitForOutput(item.proposed),
    })),
    conflicts: objectList(row.conflicts).map((item) => ({
      code: text(item.code, 100),
      current: objectList(item.current).map(benefitForOutput),
      proposed: objectList(item.proposed).map(benefitForOutput),
    })),
  };
}

function benefitDecision(value: unknown) {
  const row = asRecord(value) ?? {};
  return {
    action: text(row.action, 40),
    reason: text(row.reason, 500),
    change_type: text(row.change_type ?? row.changeType, 60),
    dedupe_key: text(row.dedupe_key ?? row.dedupeKey, 200),
    display_priority: number(row.display_priority),
    is_primary: typeof row.is_primary === "boolean" ? row.is_primary : null,
    benefit: benefitForOutput(row.benefit),
    proposed: benefitForOutput(row.proposed),
    edited_benefit: benefitForOutput(row.edited_benefit ?? row.editedBenefit),
  };
}

function validationItems(value: unknown) {
  return objectList(value).map((item) => ({ code: text(item.code, 100) }));
}

function sourceEvidence(value: unknown) {
  return objectList(value).map((item) => ({
    dedupe_key: text(item.dedupe_key, 200),
    source_url: text(item.source_url),
    source_excerpt: text(item.source_excerpt, 500),
    evidence: fieldEvidence(item.evidence),
  }));
}

function extractionForOutput(value: unknown) {
  const row = asRecord(value) ?? {};
  return {
    request_type: text(row.request_type, 100),
    parser_version: text(row.parser_version, 100),
    content_hash: text(row.content_hash, 200),
    retrieved_at: text(row.retrieved_at, 100),
    proposals: objectList(row.proposals).map(benefitForOutput),
    diff: benefitDiff(row.diff),
  };
}

function resultSummary(value: unknown) {
  const row = asRecord(value) ?? {};
  return {
    run_id: text(row.run_id, 100),
    proposals: number(row.proposals),
    additions: number(row.additions),
    modifications: number(row.modifications),
    possible_removals: number(row.possible_removals),
    conflicts: number(row.conflicts),
    reused_staging: row.reused_staging === true,
    unsafe_mutation_count: number(row.unsafe_mutation_count),
    raw_body_stored: row.raw_body_stored === true,
    evidence_passed: row.evidence_passed === true,
    idempotency_passed: row.idempotency_passed === true,
    retry_scheduled: row.retry_scheduled === true,
    quarantine_reason: text(row.quarantine_reason, 100),
  };
}

function stagingForOutput(value: unknown) {
  const staging = Array.isArray(value) ? value[0] : value;
  const row = asRecord(staging);
  if (!row) return null;
  return {
    id: text(row.id, 100),
    card_id: text(row.card_id, 100),
    request_type: text(row.request_type, 100),
    parser_version: text(row.parser_version, 100),
    source_url: text(row.source_url),
    source_url_hash: text(row.source_url_hash, 200),
    content_hash: text(row.content_hash, 200),
    status: text(row.status, 50),
    calculated_confidence: number(row.calculated_confidence),
    validation_reasons: validationItems(row.validation_reasons),
    validation_warnings: validationItems(row.validation_warnings),
    source_evidence: sourceEvidence(row.source_evidence),
    extracted_data: extractionForOutput(row.extracted_data),
    benefit_decisions: objectList(row.benefit_decisions).map(benefitDecision),
    created_at: text(row.created_at, 100),
    reviewed_at: text(row.reviewed_at, 100),
  };
}

export function presentBenefitJob(value: unknown) {
  const row = asRecord(value) ?? {};
  const card = asRecord(row.card_catalog) ?? {};
  return {
    id: text(row.id, 100),
    card_id: text(row.card_id, 100),
    issuer: text(row.issuer, 200),
    canonical_url: text(row.canonical_url),
    parser_version: text(row.parser_version, 100),
    status: text(row.status, 50),
    run_mode: text(row.run_mode, 50),
    attempt_count: number(row.attempt_count),
    staging_id: text(row.staging_id, 100),
    failure_category: text(row.failure_category, 100),
    next_retry_at: text(row.next_retry_at, 100),
    normalized_fields: {
      proposed_count: number(asRecord(row.normalized_fields)?.proposed_count),
    },
    result_summary: resultSummary(row.result_summary),
    created_at: text(row.created_at, 100),
    updated_at: text(row.updated_at, 100),
    card: {
      id: text(card.id, 100),
      bank: text(card.bank, 200),
      card_name: text(card.card_name, 300),
    },
    staging: stagingForOutput(row.card_benefits_staging),
  };
}

function benefitLane<T>(query: T): T {
  return (query as any)
    .neq("parser_version", "catalog-v1")
    .in("run_mode", benefitRunModes);
}

function pageRequest(body: JsonRecord) {
  const page = body.page === undefined ? 1 : Number(body.page);
  const limit = body.limit === undefined ? 50 : Number(body.limit);
  if (
    !Number.isInteger(page) || page < 1 || !Number.isInteger(limit) ||
    limit < 1 || limit > 100
  ) {
    throw new BenefitAdminError("invalid_benefit_page");
  }
  return { page, limit, offset: (page - 1) * limit };
}

async function exactCount(
  db: UntypedSupabaseClient,
  column: "status" | "run_mode" | null = null,
  value: string | null = null,
) {
  let query = benefitLane(
    db.from("card_catalog_enrichment_jobs").select("id", {
      count: "exact",
      head: true,
    }),
  );
  if (column && value) query = query.eq(column, value);
  const { count, error } = await query;
  if (error) throw error;
  return Number(count ?? 0);
}

async function benefitCounts(db: UntypedSupabaseClient) {
  const [total, ...buckets] = await Promise.all([
    exactCount(db),
    ...jobStatuses.map((status) => exactCount(db, "status", status)),
    ...benefitRunModes.map((runMode) => exactCount(db, "run_mode", runMode)),
  ]);
  return {
    total,
    by_status: Object.fromEntries(
      jobStatuses.map((status, index) => [status, buckets[index]]),
    ),
    by_run_mode: Object.fromEntries(
      benefitRunModes.map((runMode, index) => [
        runMode,
        buckets[jobStatuses.length + index],
      ]),
    ),
  };
}

async function readBenefitJobs(
  db: UntypedSupabaseClient,
  body: JsonRecord,
): Promise<
  { rows: JsonRecord[]; page: number; limit: number; hasMore: boolean }
> {
  const { page, limit, offset } = pageRequest(body);
  let query = benefitLane(
    db.from("card_catalog_enrichment_jobs").select(safeJobColumns),
  ).order("created_at", { ascending: false });
  if (typeof body.status === "string" && body.status.trim()) {
    query = query.eq("status", body.status.trim());
  }
  if (typeof body.job_id === "string" && body.job_id.trim()) {
    query = query.eq("id", body.job_id.trim());
  }
  const { data, error } = await query.range(offset, offset + limit);
  if (error) throw error;
  const rows = (data ?? []).map((row: unknown) => asRecord(row) ?? {});
  return {
    rows: rows.slice(0, limit),
    page,
    limit,
    hasMore: rows.length > limit,
  };
}

function allowedDecisions(
  value: unknown,
  acceptedActions: readonly string[],
): JsonRecord[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new BenefitAdminError("benefit_decisions_are_required");
  }
  const decisions = value.map(asRecord);
  if (decisions.some((decision) => decision === null)) {
    throw new BenefitAdminError("invalid_benefit_decision");
  }
  if (
    decisions.some((decision) =>
      !acceptedActions.includes(String(decision!.action ?? "").toLowerCase())
    )
  ) {
    throw new BenefitAdminError("invalid_benefit_decision");
  }
  return decisions as JsonRecord[];
}

async function approvalTarget(
  db: UntypedSupabaseClient,
  body: JsonRecord,
) {
  const jobId = requiredId(body.job_id, "job_id");
  const stagingId = requiredId(body.staging_id, "staging_id");
  const { data: job, error: jobError } = await benefitLane(
    db.from("card_catalog_enrichment_jobs")
      .select("id, card_id, staging_id, status"),
  )
    .eq("id", jobId)
    .eq("staging_id", stagingId)
    .single();
  if (jobError || !job || job.status !== "staged") {
    throw new BenefitAdminError("invalid_benefit_job_staging", 409);
  }
  const { data: staging, error: stagingError } = await db
    .from("card_benefits_staging")
    .select("id, card_id, status, request_type")
    .eq("id", stagingId)
    .eq("card_id", job.card_id)
    .eq("request_type", "official_benefit_enrichment")
    .single();
  if (stagingError || !staging || staging.status !== "pending") {
    throw new BenefitAdminError("invalid_benefit_job_staging", 409);
  }
  return { jobId, stagingId };
}

async function approve(
  db: UntypedSupabaseClient,
  body: JsonRecord,
  actor: Actor,
  mode: "approve" | "edit" | "reject",
) {
  const accepted = mode === "approve"
    ? ["approve", "keep_existing"]
    : mode === "edit"
    ? ["edit", "keep_existing"]
    : ["reject"];
  let decisions = allowedDecisions(body.decisions, accepted);
  const reason = mode === "reject" ? requiredReason(body.reason) : null;
  const target = await approvalTarget(db, body);
  if (mode === "reject") {
    decisions = decisions.map((decision) => ({ ...decision, reason }));
  }
  const { data, error } = await db.rpc("approve_card_benefit_enrichment", {
    _staging_id: target.stagingId,
    _reviewed_by: actor.id,
    _decisions: decisions,
  });
  if (error) throw error;
  const result = Array.isArray(data) ? data[0] : data;
  return {
    success: true,
    result: {
      staging_id: result?.staging_id ?? target.stagingId,
      resulting_status: result?.resulting_status ??
        (mode === "reject" ? "rejected" : "approved"),
    },
  };
}

async function resetJob(
  db: UntypedSupabaseClient,
  jobId: string,
  allowedStatuses: string[],
  patch: JsonRecord,
) {
  const { data, error } = await benefitLane(
    db.from("card_catalog_enrichment_jobs").update(patch),
  )
    .eq("id", jobId)
    .in("status", allowedStatuses)
    .select(
      "id, status, attempt_count, run_mode, parser_version, result_summary, failure_category, next_retry_at",
    )
    .single();
  if (error || !data) {
    throw new BenefitAdminError("invalid_benefit_job_state", 409);
  }
  return { success: true, job: presentBenefitJob(data) };
}

function pilotCandidates(value: unknown) {
  if (!Array.isArray(value) || value.length !== 5) {
    throw new BenefitAdminError("invalid_pilot_candidates");
  }
  const candidates = value.map(asRecord);
  if (
    candidates.some((candidate) =>
      !candidate || typeof candidate.card_id !== "string" ||
      !pilotProfiles.has(String(candidate.profile ?? "").trim().toLowerCase())
    )
  ) {
    throw new BenefitAdminError("invalid_pilot_candidates");
  }
  return candidates.map((candidate) => ({
    card_id: String(candidate!.card_id).trim(),
    profile: String(candidate!.profile).trim().toLowerCase(),
  }));
}

export function isBenefitAdminAction(action: unknown): action is string {
  return typeof action === "string" && benefitActions.has(action);
}

export async function handleBenefitAdminAction(
  db: UntypedSupabaseClient,
  body: JsonRecord,
  actor: Actor,
): Promise<unknown> {
  switch (body.action) {
    case "benefit-list": {
      const [page, counts] = await Promise.all([
        readBenefitJobs(db, body),
        benefitCounts(db),
      ]);
      return {
        items: page.rows.map(presentBenefitJob),
        counts,
        page: page.page,
        limit: page.limit,
        has_more: page.hasMore,
      };
    }
    case "benefit-status": {
      const [page, counts] = await Promise.all([
        readBenefitJobs(db, body),
        benefitCounts(db),
      ]);
      return {
        items: page.rows.map(presentBenefitJob),
        run_counts: counts,
        history: page.rows.map((row) => ({
          job_id: text(row.id, 100),
          status: text(row.status, 50),
          run_mode: text(row.run_mode, 50),
          updated_at: text(row.updated_at, 100),
          run_id: text(asRecord(row.result_summary)?.run_id, 100),
        })),
        page: page.page,
        limit: page.limit,
        has_more: page.hasMore,
      };
    }
    case "benefit-approve":
      return await approve(db, body, actor, "approve");
    case "benefit-edit-approve":
      return await approve(db, body, actor, "edit");
    case "benefit-reject":
      return await approve(db, body, actor, "reject");
    case "benefit-retry":
      return await resetJob(db, requiredId(body.job_id, "job_id"), [
        "failed",
        "review_required",
      ], {
        status: "queued",
        next_retry_at: null,
        failure_category: null,
        lease_expires_at: null,
        lease_token: null,
        updated_at: new Date().toISOString(),
      });
    case "benefit-quarantine":
      return await resetJob(db, requiredId(body.job_id, "job_id"), [
        "queued",
        "failed",
        "review_required",
      ], {
        status: "quarantined",
        failure_category: requiredReason(body.reason),
        next_retry_at: null,
        lease_expires_at: null,
        lease_token: null,
        updated_at: new Date().toISOString(),
      });
    case "benefit-unquarantine":
      return await resetJob(db, requiredId(body.job_id, "job_id"), [
        "quarantined",
      ], {
        status: "queued",
        failure_category: null,
        next_retry_at: null,
        lease_expires_at: null,
        lease_token: null,
        updated_at: new Date().toISOString(),
      });
    case "benefit-start-pilot": {
      const parserVersion = typeof body.parser_version === "string"
        ? body.parser_version.trim()
        : "benefits-v1";
      if (!parserVersion || parserVersion.toLowerCase() === "catalog-v1") {
        throw new BenefitAdminError("invalid_pilot_parser_version");
      }
      const { data, error } = await db.rpc(
        "initialize_card_benefit_enrichment_pilot",
        {
          _candidates: pilotCandidates(body.candidates),
          _parser_version: parserVersion,
        },
      );
      if (error) throw error;
      return { jobs: (data ?? []).map(presentBenefitJob) };
    }
    default:
      throw new BenefitAdminError("unsupported_benefit_action");
  }
}
