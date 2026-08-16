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

const prohibitedOutputKey =
  /(?:^|_)(?:raw(?:_?body)?|page(?:_?body)?|html|authorization|secret|token|cookie|password|api_?key|private_?key|headers?)(?:$|_)/i;
const pilotProfiles = new Set([
  "straightforward",
  "redirect_or_js",
  "terms_linked",
  "known_invalid",
  "additional_valid",
]);

type Actor = { id: string };
type JsonRecord = Record<string, unknown>;

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

/** Removes crawler payloads and credentials before they cross the admin API. */
export function safeAdminValue(value: unknown): unknown {
  if (typeof value === "string") return value.slice(0, 8_000);
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(safeAdminValue);
  return Object.fromEntries(
    Object.entries(value).flatMap(([key, item]) =>
      prohibitedOutputKey.test(key) ? [] : [[key, safeAdminValue(item)]]
    ),
  );
}

function stagingForOutput(value: unknown) {
  const staging = Array.isArray(value) ? value[0] : value;
  const row = asRecord(staging);
  if (!row) return null;
  return safeAdminValue({
    id: row.id,
    card_id: row.card_id,
    request_type: row.request_type,
    parser_version: row.parser_version,
    source_url: row.source_url,
    source_url_hash: row.source_url_hash,
    content_hash: row.content_hash,
    status: row.status,
    calculated_confidence: row.calculated_confidence,
    validation_reasons: row.validation_reasons,
    validation_warnings: row.validation_warnings,
    source_evidence: row.source_evidence,
    extracted_data: row.extracted_data,
    benefit_decisions: row.benefit_decisions,
    created_at: row.created_at,
    reviewed_at: row.reviewed_at,
  });
}

export function presentBenefitJob(value: unknown) {
  const row = asRecord(value) ?? {};
  return safeAdminValue({
    id: row.id,
    card_id: row.card_id,
    issuer: row.issuer,
    canonical_url: row.canonical_url,
    parser_version: row.parser_version,
    status: row.status,
    run_mode: row.run_mode,
    attempt_count: row.attempt_count,
    staging_id: row.staging_id,
    failure_category: row.failure_category,
    next_retry_at: row.next_retry_at,
    normalized_fields: row.normalized_fields,
    result_summary: row.result_summary,
    created_at: row.created_at,
    updated_at: row.updated_at,
    card: row.card_catalog,
    staging: stagingForOutput(row.card_benefits_staging),
  });
}

function counts(rows: JsonRecord[]) {
  const byStatus: Record<string, number> = {};
  const byRunMode: Record<string, number> = {};
  for (const row of rows) {
    const status = typeof row.status === "string" ? row.status : "unknown";
    const runMode = typeof row.run_mode === "string" ? row.run_mode : "unknown";
    byStatus[status] = (byStatus[status] ?? 0) + 1;
    byRunMode[runMode] = (byRunMode[runMode] ?? 0) + 1;
  }
  return { total: rows.length, by_status: byStatus, by_run_mode: byRunMode };
}

async function readBenefitJobs(
  db: UntypedSupabaseClient,
  body: JsonRecord,
): Promise<JsonRecord[]> {
  let query = db.from("card_catalog_enrichment_jobs").select(safeJobColumns)
    .order("created_at", { ascending: false });
  if (typeof body.status === "string" && body.status.trim()) {
    query = query.eq("status", body.status.trim());
  }
  if (typeof body.job_id === "string" && body.job_id.trim()) {
    query = query.eq("id", body.job_id.trim());
  }
  const { data, error } = await query.limit(100);
  if (error) throw error;
  return (data ?? []).map((row: unknown) => asRecord(row) ?? {});
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
  const { data: job, error: jobError } = await db
    .from("card_catalog_enrichment_jobs")
    .select("id, card_id, staging_id, status")
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
    result: safeAdminValue({
      staging_id: result?.staging_id ?? target.stagingId,
      resulting_status: result?.resulting_status ??
        (mode === "reject" ? "rejected" : "approved"),
    }),
  };
}

async function resetJob(
  db: UntypedSupabaseClient,
  jobId: string,
  allowedStatuses: string[],
  patch: JsonRecord,
) {
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .update(patch)
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
      const rows = await readBenefitJobs(db, body);
      return { items: rows.map(presentBenefitJob), counts: counts(rows) };
    }
    case "benefit-status": {
      const rows = await readBenefitJobs(db, body);
      return {
        items: rows.map(presentBenefitJob),
        run_counts: counts(rows),
        history: rows.map((row) =>
          safeAdminValue({
            job_id: row.id,
            status: row.status,
            run_mode: row.run_mode,
            updated_at: row.updated_at,
            run_id: asRecord(row.result_summary)?.run_id ?? null,
          })
        ),
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
