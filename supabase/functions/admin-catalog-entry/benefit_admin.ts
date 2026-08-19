import {
  canonicalConditionObject,
  canonicalExclusions,
} from "../_shared/benefit_contract.ts";

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
const valueConfigFields = [
  "category",
  "discount_type",
  "discount_percent",
  "discount_amount",
  "max_discount_per_transaction",
  "max_usage_per_month",
  "max_usage_per_period",
  "usage_period",
  "monthly_cap",
  "annual_cap",
  "unit",
  "milestone_type",
  "threshold_amount",
  "reward_value",
  "multiplier",
  "base_rate",
  "currency_unit",
  "platform",
] as const;
const v6ValueConfigFields = [
  "value",
  "rate",
  "cap",
  "threshold",
  "frequency",
  "period",
  "offer_subject",
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

function safeUrl(value: unknown): string | null {
  const candidate = text(value);
  if (!candidate) return null;
  try {
    const url = new URL(candidate);
    if (url.protocol !== "https:") return null;
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "").slice(0, 2048);
  } catch {
    return null;
  }
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function textList(value: unknown, maximumItems = 64): string[] {
  return Array.isArray(value)
    ? value.flatMap((item) =>
      typeof item === "string" ? [item.slice(0, 500)] : []
    ).slice(0, maximumItems)
    : [];
}

function valueConfig(value: unknown, v6 = false): JsonRecord {
  const row = asRecord(value) ?? {};
  const sanitized: JsonRecord = {};
  for (
    const field of [
      ...valueConfigFields,
      ...(v6 ? v6ValueConfigFields : []),
    ]
  ) {
    const item = row[field];
    if (typeof item === "string") sanitized[field] = item.slice(0, 500);
    if (typeof item === "number" && Number.isFinite(item)) {
      sanitized[field] = item;
    }
    if (typeof item === "boolean") sanitized[field] = item;
  }
  if (v6) sanitized.restrictions = textList(row.restrictions, 32);
  if (v6) sanitized.exclusions = boundedExclusions(row.exclusions);
  return sanitized;
}

function digest(value: unknown): string | null {
  const candidate = text(value, 64)?.toLowerCase() ?? "";
  return /^[0-9a-f]{64}$/.test(candidate) ? candidate : null;
}

function boundedExclusions(value: unknown): JsonRecord {
  const canonical = canonicalExclusions(value);
  const additional = asRecord(canonical.additional) ?? {};
  return {
    additional: {
      source_terms: textList(additional.source_terms, 32),
    },
    categories: textList(canonical.categories, 32),
    days: textList(canonical.days, 32),
    mcc_codes: textList(canonical.mcc_codes, 32),
    merchants: textList(canonical.merchants, 32),
    transaction_types: textList(canonical.transaction_types, 32),
  };
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

function benefitForOutput(value: unknown, forceV6 = false) {
  const row = asRecord(value) ?? {};
  const v6 = forceV6 || row.parserVersion === "benefits-v6" ||
    String(row.benefitId ?? row.dedupeKey ?? "").startsWith(
      "card-benefit-v2:",
    );
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
    ...(v6 && text(row.benefitId, 200)
      ? { benefitId: text(row.benefitId, 200) }
      : {}),
    ...(v6 && text(row.offerSubject, 256)
      ? { offerSubject: text(row.offerSubject, 256) }
      : {}),
    ...(v6 && digest(row.conditionHash)
      ? { conditionHash: digest(row.conditionHash) }
      : {}),
    valueConfig: valueConfig(row.valueConfig ?? row.value_config, v6),
    partners: textList(row.partners),
    ...(v6 && !Array.isArray(row.exclusions)
      ? { exclusions: boundedExclusions(row.exclusions) }
      : {}),
    sourceUrl: safeUrl(row.sourceUrl),
    sourceUrls: textList(row.sourceUrls).flatMap((item) =>
      safeUrl(item) ? [safeUrl(item)!] : []
    ),
    ...(v6 && digest(row.sourceIdentity)
      ? { sourceIdentity: digest(row.sourceIdentity) }
      : {}),
    ...(v6
      ? {
        sourceIdentities: textList(row.sourceIdentities, 32).flatMap((item) =>
          digest(item) ? [digest(item)!] : []
        ),
      }
      : {}),
    sourceExcerpt: text(row.sourceExcerpt, 500),
    contentHash: text(row.contentHash, 200),
    parserVersion: text(row.parserVersion, 100),
    confidence: fieldConfidence(row.confidence),
    evidence: fieldEvidence(row.evidence),
    warnings: textList(row.warnings),
  };
}

function benefitDiff(value: unknown, v6 = false) {
  const row = asRecord(value) ?? {};
  return {
    additions: objectList(row.additions).map((item) =>
      benefitForOutput(item, v6)
    ),
    modifications: objectList(row.modifications).map((item) => ({
      current: benefitForOutput(item.current, v6),
      proposed: benefitForOutput(item.proposed, v6),
    })),
    possibleRemovals: objectList(row.possibleRemovals).map((item) => ({
      benefit: benefitForOutput(item.benefit, v6),
      informational: item.informational === true,
    })),
    unchanged: objectList(row.unchanged).map((item) => ({
      current: benefitForOutput(item.current, v6),
      proposed: benefitForOutput(item.proposed, v6),
    })),
    conflicts: objectList(row.conflicts).map((item) => ({
      code: text(item.code, 100),
      current: objectList(item.current).map((benefit) =>
        benefitForOutput(benefit, v6)
      ),
      proposed: objectList(item.proposed).map((benefit) =>
        benefitForOutput(benefit, v6)
      ),
    })),
  };
}

function benefitDecision(value: unknown, v6 = false) {
  const row = asRecord(value) ?? {};
  return {
    action: text(row.action, 40),
    reason: text(row.reason, 500),
    change_type: text(row.change_type ?? row.changeType, 60),
    dedupe_key: text(row.dedupe_key ?? row.dedupeKey, 200),
    display_priority: number(row.display_priority),
    is_primary: typeof row.is_primary === "boolean" ? row.is_primary : null,
    benefit: benefitForOutput(row.benefit, v6),
    proposed: benefitForOutput(row.proposed, v6),
    edited_benefit: benefitForOutput(
      row.edited_benefit ?? row.editedBenefit,
      v6,
    ),
  };
}

function validationItems(value: unknown) {
  return objectList(value).map((item) => ({ code: text(item.code, 100) }));
}

function sourceEvidence(value: unknown) {
  return objectList(value).map((item) => ({
    dedupe_key: text(item.dedupe_key, 200),
    offer_subject: text(item.offer_subject, 256),
    source_identity: digest(item.source_identity),
    source_identities: textList(item.source_identities, 32).flatMap((
      identity,
    ) => digest(identity) ? [digest(identity)!] : []),
    source_url: safeUrl(item.source_url),
    source_excerpt: text(item.source_excerpt, 500),
    evidence: fieldEvidence(item.evidence),
  }));
}

function extractionForOutput(value: unknown) {
  const row = asRecord(value) ?? {};
  const v6 = row.parser_version === "benefits-v6";
  return {
    request_type: text(row.request_type, 100),
    parser_version: text(row.parser_version, 100),
    content_hash: text(row.content_hash, 200),
    retrieved_at: text(row.retrieved_at, 100),
    proposals: objectList(row.proposals).map((item) =>
      benefitForOutput(item, v6)
    ),
    diff: benefitDiff(row.diff, v6),
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
  const v6 = row.parser_version === "benefits-v6";
  return {
    id: text(row.id, 100),
    card_id: text(row.card_id, 100),
    request_type: text(row.request_type, 100),
    parser_version: text(row.parser_version, 100),
    source_url: safeUrl(row.source_url),
    source_url_hash: text(row.source_url_hash, 200),
    content_hash: text(row.content_hash, 200),
    status: text(row.status, 50),
    calculated_confidence: number(row.calculated_confidence),
    validation_reasons: validationItems(row.validation_reasons),
    validation_warnings: validationItems(row.validation_warnings),
    source_evidence: sourceEvidence(row.source_evidence),
    extracted_data: extractionForOutput(row.extracted_data),
    benefit_decisions: objectList(row.benefit_decisions).map((item) =>
      benefitDecision(item, v6)
    ),
    created_at: text(row.created_at, 100),
    reviewed_at: text(row.reviewed_at, 100),
  };
}

export function presentBenefitJob(value: unknown, crawlerDiscovered = false) {
  const row = asRecord(value) ?? {};
  const card = asRecord(row.card_catalog) ?? {};
  return {
    id: text(row.id, 100),
    card_id: text(row.card_id, 100),
    issuer: text(row.issuer, 200),
    canonical_url: safeUrl(row.canonical_url),
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
    crawler_discovered_without_statement_signal: crawlerDiscovered,
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
  {
    rows: JsonRecord[];
    page: number;
    limit: number;
    hasMore: boolean;
    crawlerCardIds: Set<string>;
  }
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
  const cardIds = rows.map((row: JsonRecord) => text(row.card_id, 100))
    .filter((id: string | null): id is string => id !== null);
  const crawlerCardIds = new Set<string>();
  if (cardIds.length > 0) {
    const { data: crawlerRows, error: crawlerError } = await db
      .from("card_discovery_jobs")
      .select("resolved_card_id")
      .eq("discovery_source", "issuer_crawl")
      .eq("status", "resolved")
      .in("resolved_card_id", cardIds);
    if (crawlerError) throw crawlerError;
    for (const row of crawlerRows ?? []) {
      const cardId = text(asRecord(row)?.resolved_card_id, 100);
      if (cardId) crawlerCardIds.add(cardId);
    }
  }
  return {
    rows: rows.slice(0, limit),
    page,
    limit,
    hasMore: rows.length > limit,
    crawlerCardIds,
  };
}

function allowedDecisions(
  value: unknown,
  acceptedActions: readonly string[],
  parserVersion = "benefits-v5",
  stagedExtraction?: unknown,
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
  if (parserVersion !== "benefits-v6") return decisions as JsonRecord[];
  return validateV6ApprovalDecisions(
    decisions as JsonRecord[],
    stagedExtraction,
  );
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return "{" + Object.entries(value as JsonRecord).sort(([left], [right]) =>
      left.localeCompare(right)
    ).map(([key, item]) =>
      `${JSON.stringify(key)}:${stableJson(item)}`
    ).join(",") + "}";
  }
  return JSON.stringify(value);
}

function canonicalApprovalIdentity(value: unknown): string {
  const proposal = benefitForOutput(value, true) as JsonRecord;
  const config = asRecord(proposal.valueConfig) ?? {};
  return stableJson({
    benefit_id: text(proposal.benefitId, 200),
    dedupe_key: text(proposal.dedupeKey, 200),
    condition_hash: digest(proposal.conditionHash),
    offer_subject: text(proposal.offerSubject, 256),
    condition: canonicalConditionObject({
      title: String(proposal.title ?? ""),
      category: text(proposal.category, 200),
      benefitType: text(proposal.valueType, 200),
      semanticKey: text(proposal.offerSubject, 256),
      valueConfig: config,
      exclusions: proposal.exclusions,
      restrictions: textList(proposal.restrictions, 32),
      partners: textList(proposal.partners, 64),
      validFrom: text(proposal.effectiveFrom, 100),
      validUntil: text(proposal.effectiveTo, 100),
    }),
    source_identity: digest(proposal.sourceIdentity),
    source_identities: textList(proposal.sourceIdentities, 32).flatMap((item) =>
      digest(item) ? [digest(item)!] : []
    ).sort(),
  });
}

export function validateV6ApprovalDecisions(
  decisions: JsonRecord[],
  stagedExtraction: unknown,
): JsonRecord[] {
  const extraction = asRecord(stagedExtraction);
  if (
    !extraction || extraction.parser_version !== "benefits-v6" ||
    extraction.request_type !== "official_benefit_enrichment"
  ) throw new BenefitAdminError("invalid_benefit_job_staging", 409);
  const staged = objectList(extraction.proposals).map((proposal) =>
    benefitForOutput(proposal, true) as JsonRecord
  );
  const stagedByKey = new Map<string, JsonRecord>();
  for (const proposal of staged) {
    const key = text(proposal.benefitId ?? proposal.dedupeKey, 200);
    if (!key || stagedByKey.has(key)) {
      throw new BenefitAdminError("invalid_staged_benefit_identity", 409);
    }
    stagedByKey.set(key, proposal);
  }
  const selected = new Set<string>();
  return decisions.map((decision) => {
    const action = String(decision.action ?? "").toLowerCase();
    const base: JsonRecord = {
      action,
      ...(text(decision.reason, 500)
        ? { reason: text(decision.reason, 500) }
        : {}),
      ...(text(decision.change_type ?? decision.changeType, 60)
        ? {
          change_type: text(decision.change_type ?? decision.changeType, 60),
        }
        : {}),
      ...(number(decision.display_priority) !== null
        ? { display_priority: number(decision.display_priority) }
        : {}),
      ...(typeof decision.is_primary === "boolean"
        ? { is_primary: decision.is_primary }
        : {}),
    };
    if (action !== "approve" && action !== "edit") return base;
    const submitted = asRecord(
      action === "edit"
        ? decision.edited_benefit ?? decision.editedBenefit ?? decision.benefit
        : decision.benefit ?? decision.proposed,
    );
    if (!submitted) throw new BenefitAdminError("invalid_benefit_decision");
    const key = text(submitted.benefitId ?? submitted.dedupeKey, 200);
    const server = key ? stagedByKey.get(key) : undefined;
    if (
      !server || selected.has(key!) ||
      canonicalApprovalIdentity(submitted) !== canonicalApprovalIdentity(server)
    ) throw new BenefitAdminError("benefit_decision_identity_mismatch", 409);
    selected.add(key!);
    if (action === "approve") return { ...base, benefit: server };
    const edited = {
      ...server,
      ...(text(submitted.title, 2_000)
        ? { title: text(submitted.title, 2_000) }
        : {}),
      ...(text(submitted.description, 2_000)
        ? { description: text(submitted.description, 2_000) }
        : {}),
    };
    return { ...base, edited_benefit: edited };
  });
}

async function approvalTarget(
  db: UntypedSupabaseClient,
  body: JsonRecord,
) {
  const jobId = requiredId(body.job_id, "job_id");
  const stagingId = requiredId(body.staging_id, "staging_id");
  const { data: job, error: jobError } = await benefitLane(
    db.from("card_catalog_enrichment_jobs")
      .select("id, card_id, staging_id, status, parser_version"),
  )
    .eq("id", jobId)
    .eq("staging_id", stagingId)
    .single();
  if (jobError || !job || job.status !== "staged") {
    throw new BenefitAdminError("invalid_benefit_job_staging", 409);
  }
  const { data: staging, error: stagingError } = await db
    .from("card_benefits_staging")
    .select("id, card_id, status, request_type, parser_version, extracted_data")
    .eq("id", stagingId)
    .eq("card_id", job.card_id)
    .eq("request_type", "official_benefit_enrichment")
    .single();
  if (
    stagingError || !staging || staging.status !== "pending" ||
    (job.parser_version === "benefits-v6" &&
      staging.parser_version !== job.parser_version)
  ) {
    throw new BenefitAdminError("invalid_benefit_job_staging", 409);
  }
  return {
    jobId,
    stagingId,
    parserVersion: String(job.parser_version ?? "benefits-v5"),
    stagedExtraction: staging.extracted_data,
  };
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
  const reason = mode === "reject" ? requiredReason(body.reason) : null;
  const target = await approvalTarget(db, body);
  let decisions = allowedDecisions(
    body.decisions,
    accepted,
    target.parserVersion,
    target.stagedExtraction,
  );
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
  observedUpdatedAt?: string,
) {
  let query = benefitLane(
    db.from("card_catalog_enrichment_jobs").update(patch),
  )
    .eq("id", jobId);
  if (observedUpdatedAt) {
    query = query.eq("updated_at", observedUpdatedAt);
  }
  const { data, error } = await query
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

async function quarantineJob(
  db: UntypedSupabaseClient,
  jobId: string,
  reason: string,
) {
  const allowedStatuses = ["queued", "failed", "review_required"];
  const { data: current, error } = await benefitLane(
    db.from("card_catalog_enrichment_jobs").select(
      "id, status, run_mode, parser_version, result_summary, updated_at",
    ),
  )
    .eq("id", jobId)
    .in("status", allowedStatuses)
    .single();
  if (error || !current || typeof current.updated_at !== "string") {
    throw new BenefitAdminError("invalid_benefit_job_state", 409);
  }
  return await resetJob(db, jobId, allowedStatuses, {
    status: "quarantined",
    failure_category: reason,
    result_summary: {
      ...(asRecord(current.result_summary) ?? {}),
      quarantine_reason: reason,
      idempotency_passed: true,
    },
    next_retry_at: null,
    lease_expires_at: null,
    lease_token: null,
    updated_at: new Date().toISOString(),
  }, current.updated_at);
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

async function movieMappingHealth(db: UntypedSupabaseClient) {
  const { data, error } = await db.rpc("get_movie_benefit_mapping_health");
  if (error) {
    throw new BenefitAdminError("movie_mapping_health_unavailable", 503);
  }
  return Array.isArray(data) ? data : [];
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
        items: page.rows.map((row) =>
          presentBenefitJob(
            row,
            page.crawlerCardIds.has(String(row.card_id ?? "")),
          )
        ),
        counts,
        page: page.page,
        limit: page.limit,
        has_more: page.hasMore,
      };
    }
    case "benefit-status": {
      const [page, counts, mappingHealth] = await Promise.all([
        readBenefitJobs(db, body),
        benefitCounts(db),
        movieMappingHealth(db),
      ]);
      return {
        items: page.rows.map((row) =>
          presentBenefitJob(
            row,
            page.crawlerCardIds.has(String(row.card_id ?? "")),
          )
        ),
        run_counts: counts,
        movie_mapping_health: mappingHealth,
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
      return await quarantineJob(
        db,
        requiredId(body.job_id, "job_id"),
        requiredReason(body.reason),
      );
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
        : "benefits-v5";
      if (parserVersion !== "benefits-v5") {
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
