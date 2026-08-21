import { type AdminActionHandler } from "./access.ts";
import {
  type AdminActionContext,
  type AdminDatabaseError,
  AdminHttpError,
} from "./types.ts";

type JsonRecord = Record<string, unknown>;
type Lane = "identity" | "benefit";

const MAX_PAGE = 10_000;
const MAX_LIMIT = 50;
const MAX_REQUEST_BYTES = 32_768;
const MAX_LIST_ITEMS = 50;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_STATUS = /^[a-z][a-z0-9_]{0,49}$/;
const identityStatuses = new Set(["pending", "approved", "merged", "rejected"]);
const benefitStatuses = new Set([
  "queued",
  "processing",
  "completed",
  "review_required",
  "failed",
  "staged",
  "quarantined",
]);
const identityOperations = new Set([
  "approve",
  "edit_approve",
  "merge",
  "reject",
  "retry",
]);
const benefitOperations = new Set([
  "approve",
  "edit_approve",
  "reject",
  "retry",
  "quarantine",
  "unquarantine",
]);
const commonActionKeys = new Set([
  "action",
  "lane",
  "operation",
  "target_id",
  "request_id",
  "observed_updated_at",
  "reason",
  "staging_id",
  "proposed_fields",
  "merge_card_id",
  "decisions",
]);
const listKeys = new Set([
  "action",
  "lane",
  "page",
  "limit",
  "status",
  "target_id",
]);
const proposedFieldNames = [
  "id",
  "bank",
  "issuer",
  "card_name",
  "name",
  "network",
  "card_type",
  "annual_fee",
  "currency",
  "official_url",
  "image_url",
] as const;

function invalidRequest(): never {
  throw new AdminHttpError("invalid_request", 400);
}

function asRecord(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function safeText(value: unknown, maximum: number): string | null {
  return typeof value === "string" ? value.slice(0, maximum) : null;
}

function safeNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function safeUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function requiredUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value)) invalidRequest();
  return value;
}

function optionalUuid(value: unknown): string | null {
  return value == null ? null : requiredUuid(value);
}

function requiredTimestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 100 ||
    !/^\d{4}-\d{2}-\d{2}t/i.test(value) || Number.isNaN(Date.parse(value))
  ) invalidRequest();
  return value;
}

function requiredLane(value: unknown): Lane {
  if (value !== "identity" && value !== "benefit") invalidRequest();
  return value;
}

function onlyKeys(body: JsonRecord, allowed: ReadonlySet<string>) {
  if (Object.keys(body).some((key) => !allowed.has(key))) invalidRequest();
}

function pageRequest(body: JsonRecord) {
  const parsedPage = body.page === undefined ? 1 : Number(body.page);
  const parsedLimit = body.limit === undefined ? 25 : Number(body.limit);
  const page = Number.isFinite(parsedPage) && Number.isInteger(parsedPage)
    ? Math.min(MAX_PAGE, Math.max(1, parsedPage))
    : 1;
  const limit = Number.isFinite(parsedLimit) && Number.isInteger(parsedLimit)
    ? Math.min(MAX_LIMIT, Math.max(1, parsedLimit))
    : 25;
  return { page, limit, offset: (page - 1) * limit };
}

function statusFilter(value: unknown): string | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || !SAFE_STATUS.test(value)) invalidRequest();
  return value;
}

function safeProposedFields(value: unknown, strict = false): JsonRecord {
  const row = asRecord(value) ?? {};
  if (
    strict &&
    Object.keys(row).some((key) =>
      !proposedFieldNames.includes(key as typeof proposedFieldNames[number])
    )
  ) {
    invalidRequest();
  }
  const output: JsonRecord = {};
  for (const field of proposedFieldNames) {
    const item = row[field];
    if (field.endsWith("_url")) {
      const url = safeUrl(item);
      if (strict && item != null && url === null) invalidRequest();
      if (url !== null) output[field] = url;
    } else if (typeof item === "string") {
      output[field] = item.slice(0, 500);
    } else if (typeof item === "number" && Number.isFinite(item)) {
      output[field] = item;
    }
  }
  return output;
}

const benefitKeys = new Set([
  "dedupe_key",
  "dedupeKey",
  "title",
  "description",
  "benefit_category",
  "category",
  "benefit_type",
  "valueType",
  "value_config",
  "valueConfig",
  "partners",
  "exclusions",
  "regions",
  "source_url",
  "sourceUrl",
  "valid_from",
  "effectiveFrom",
  "valid_until",
  "effectiveTo",
]);
const valueConfigKeys = new Set([
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
  "value",
  "rate",
  "cap",
  "threshold",
  "frequency",
  "period",
  "restrictions",
]);

function scalar(value: unknown, key: string): unknown {
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.length <= 2_000) {
    if (key.toLowerCase().includes("url")) {
      const url = safeUrl(value);
      if (url === null) invalidRequest();
      return url;
    }
    return value;
  }
  invalidRequest();
}

function scalarList(value: unknown, key: string): unknown[] {
  if (!Array.isArray(value) || value.length > MAX_LIST_ITEMS) invalidRequest();
  return value.map((item) => scalar(item, key));
}

function exactObject(value: unknown, allowed: ReadonlySet<string>): JsonRecord {
  const row = asRecord(value);
  if (!row || Object.keys(row).some((key) => !allowed.has(key))) {
    invalidRequest();
  }
  return row;
}

function canonicalBenefit(value: unknown): JsonRecord {
  const row = exactObject(value, benefitKeys);
  const output: JsonRecord = {};
  for (const [key, item] of Object.entries(row)) {
    if (key === "value_config" || key === "valueConfig") {
      const config = exactObject(item, valueConfigKeys);
      output.value_config = Object.fromEntries(
        Object.entries(config).map((
          [childKey, child],
        ) => [
          childKey,
          childKey === "restrictions"
            ? scalarList(child, childKey)
            : scalar(child, childKey),
        ]),
      );
    } else if (key === "exclusions") {
      output.exclusions = scalarList(item, key);
    } else if (["partners", "regions"].includes(key)) {
      output[key] = scalarList(item, key);
    } else {
      const canonicalKey: Record<string, string> = {
        dedupeKey: "dedupe_key",
        category: "benefit_category",
        valueType: "benefit_type",
        sourceUrl: "source_url",
        effectiveFrom: "valid_from",
        effectiveTo: "valid_until",
      };
      output[canonicalKey[key] ?? key] = scalar(item, key);
    }
  }
  return output;
}

function safeEvidence(value: unknown): JsonRecord {
  const row = asRecord(value) ?? {};
  const output: JsonRecord = {};
  for (const field of ["official_url", "source_url"] as const) {
    if (field in row) output[field] = safeUrl(row[field]);
  }
  for (const field of ["source_excerpt", "excerpt"] as const) {
    const text = safeText(row[field], 500);
    if (text !== null) output[field] = text;
  }
  const retrievedAt = safeText(row.retrieved_at, 100);
  if (retrievedAt !== null) output.retrieved_at = retrievedAt;
  const fieldEvidence = asRecord(row.evidence);
  if (fieldEvidence) {
    output.field_evidence = Object.fromEntries(
      Object.entries(fieldEvidence).flatMap(([key, item]) => {
        if (!benefitKeys.has(key) && !valueConfigKeys.has(key)) return [];
        const excerpt = safeText(item, 500);
        return excerpt === null ? [] : [[key, excerpt]];
      }),
    );
  }
  return output;
}

function presentCandidate(value: unknown): JsonRecord {
  const row = asRecord(value) ?? {};
  const output: JsonRecord = {};
  const id = safeText(row.id ?? row.card_id, 100);
  if (id !== null) output.id = id;
  for (
    const field of ["bank", "issuer", "card_name", "network"] as const
  ) {
    const text = safeText(row[field], field === "card_name" ? 300 : 200);
    if (text !== null) output[field] = text;
  }
  const confidence = safeNumber(row.confidence);
  if (confidence !== null) output.confidence = confidence;
  return output;
}

function validationCode(value: unknown): JsonRecord | null {
  const code = typeof value === "string"
    ? safeText(value, 100)
    : safeText(asRecord(value)?.code, 100);
  return code === null ? null : { code };
}

function presentIdentityRow(value: unknown) {
  const row = asRecord(value) ?? {};
  const discovery = asRecord(row.card_discovery_jobs) ?? {};
  return {
    id: safeText(row.id, 100),
    status: safeText(row.status, 50),
    proposed_fields: safeProposedFields(row.proposed_fields),
    source_evidence: safeEvidence(row.source_evidence),
    existing_candidates: Array.isArray(row.existing_candidates)
      ? row.existing_candidates.slice(0, MAX_LIST_ITEMS).map(presentCandidate)
      : [],
    validation_warnings: Array.isArray(row.validation_warnings)
      ? row.validation_warnings.slice(0, MAX_LIST_ITEMS)
        .map(validationCode).filter((warning) => warning !== null)
      : [],
    confidence: safeNumber(row.confidence),
    review_reason: safeText(row.review_reason, 500),
    created_at: safeText(row.created_at, 100),
    updated_at: safeText(row.updated_at, 100),
    reviewed_at: safeText(row.reviewed_at, 100),
    discovery_job: {
      id: safeText(discovery.id, 100),
      issuer: safeText(discovery.issuer, 200),
      proposed_product: safeText(discovery.proposed_product, 300),
      evidence: safeEvidence(discovery.evidence),
      status: safeText(discovery.status, 50),
      attempt_count: safeNumber(discovery.attempt_count),
      failure_category: safeText(discovery.failure_category, 100),
      resolved_card_id: safeText(discovery.resolved_card_id, 100),
      created_at: safeText(discovery.created_at, 100),
      updated_at: safeText(discovery.updated_at, 100),
    },
  };
}

function boundBenefitProjection(value: unknown): any {
  if (Array.isArray(value)) {
    return value.slice(0, MAX_LIST_ITEMS).map(boundBenefitProjection);
  }
  const row = asRecord(value);
  if (!row) return value;
  const output: JsonRecord = {};
  for (const [key, item] of Object.entries(row)) {
    if (
      key === "source_url" || key === "canonical_url" || key === "sourceUrl"
    ) {
      output[key] = safeUrl(item);
    } else if (key === "sourceUrls") {
      output[key] = Array.isArray(item)
        ? item.slice(0, MAX_LIST_ITEMS).map(safeUrl).filter((url) =>
          url !== null
        )
        : [];
    } else if (typeof item === "string") {
      output[key] = item.slice(
        0,
        key.toLowerCase().includes("excerpt") ? 500 : 2_000,
      );
    } else {
      output[key] = boundBenefitProjection(item);
    }
  }
  return output;
}

function presentBenefit(value: unknown): JsonRecord {
  const row = asRecord(value) ?? {};
  const output: JsonRecord = {};
  for (const key of benefitKeys) {
    if (!(key in row)) continue;
    try {
      Object.assign(output, canonicalBenefit({ [key]: row[key] }));
    } catch {
      // Stored legacy fields that do not satisfy the operator contract are omitted.
    }
  }
  const legacyConfig: JsonRecord = {};
  for (
    const key of [
      "value",
      "rate",
      "cap",
      "threshold",
      "frequency",
      "period",
    ] as const
  ) {
    if (key in row) {
      try {
        legacyConfig[key] = scalar(row[key], key);
      } catch { /* omit */ }
    }
  }
  if (Array.isArray(row.restrictions)) {
    legacyConfig.restrictions = scalarList(row.restrictions, "restrictions");
  }
  if (
    Object.keys(legacyConfig).length > 0 && output.value_config === undefined
  ) {
    output.value_config = legacyConfig;
  }
  return output;
}

function presentBenefitDiff(value: unknown): JsonRecord {
  const row = asRecord(value) ?? {};
  const simple = (key: string, wrapper?: string) =>
    (Array.isArray(row[key]) ? row[key] : []).slice(0, MAX_LIST_ITEMS).map((
      item,
    ) =>
      wrapper
        ? { [wrapper]: presentBenefit(asRecord(item)?.[wrapper]) }
        : presentBenefit(item)
    );
  return {
    additions: simple("additions"),
    modifications: (Array.isArray(row.modifications) ? row.modifications : [])
      .slice(0, MAX_LIST_ITEMS).map((item) => ({
        current: presentBenefit(asRecord(item)?.current),
        proposed: presentBenefit(asRecord(item)?.proposed),
      })),
    possibleRemovals: simple("possibleRemovals", "benefit"),
    unchanged: (Array.isArray(row.unchanged) ? row.unchanged : [])
      .slice(0, MAX_LIST_ITEMS).map((item) => ({
        current: presentBenefit(asRecord(item)?.current),
        proposed: presentBenefit(asRecord(item)?.proposed),
      })),
    conflicts: (Array.isArray(row.conflicts) ? row.conflicts : [])
      .slice(0, MAX_LIST_ITEMS).map((item) => ({
        code: safeText(asRecord(item)?.code, 100),
      })),
  };
}

function validationCodes(value: unknown): JsonRecord[] {
  return (Array.isArray(value) ? value : []).slice(0, MAX_LIST_ITEMS)
    .map(validationCode).filter((item) => item !== null);
}

function presentAdminBenefitJob(value: unknown): JsonRecord {
  const row = asRecord(value) ?? {};
  const card = asRecord(row.card_catalog) ?? {};
  const stagingValue = Array.isArray(row.card_benefits_staging)
    ? row.card_benefits_staging[0]
    : row.card_benefits_staging;
  const staging = asRecord(stagingValue);
  const extracted = asRecord(staging?.extracted_data) ?? {};
  return boundBenefitProjection({
    id: safeText(row.id, 100),
    card_id: safeText(row.card_id, 100),
    issuer: safeText(row.issuer, 200),
    canonical_url: safeUrl(row.canonical_url),
    parser_version: safeText(row.parser_version, 100),
    status: safeText(row.status, 50),
    run_mode: safeText(row.run_mode, 50),
    attempt_count: safeNumber(row.attempt_count),
    staging_id: safeText(row.staging_id, 100),
    failure_category: safeText(row.failure_category, 100),
    next_retry_at: safeText(row.next_retry_at, 100),
    result_summary: {},
    created_at: safeText(row.created_at, 100),
    updated_at: safeText(row.updated_at, 100),
    card: {
      id: safeText(card.id, 100),
      bank: safeText(card.bank, 200),
      card_name: safeText(card.card_name, 300),
    },
    staging: staging === null ? null : {
      id: safeText(staging.id, 100),
      source_url: safeUrl(staging.source_url),
      status: safeText(staging.status, 50),
      calculated_confidence: safeNumber(staging.calculated_confidence),
      validation_reasons: validationCodes(staging.validation_reasons),
      validation_warnings: validationCodes(staging.validation_warnings),
      source_evidence:
        (Array.isArray(staging.source_evidence) ? staging.source_evidence : [])
          .slice(0, MAX_LIST_ITEMS).map(safeEvidence),
      extracted_data: {
        retrieved_at: safeText(extracted.retrieved_at, 100),
        proposals:
          (Array.isArray(extracted.proposals) ? extracted.proposals : [])
            .slice(0, MAX_LIST_ITEMS).map(presentBenefit),
        diff: presentBenefitDiff(extracted.diff),
      },
      benefit_decisions: (Array.isArray(staging.benefit_decisions)
        ? staging.benefit_decisions
        : [])
        .slice(0, MAX_LIST_ITEMS).map((decision) => {
          const item = asRecord(decision) ?? {};
          return {
            action: safeText(item.action, 40),
            reason: safeText(item.reason, 500),
            dedupe_key: safeText(item.dedupe_key ?? item.dedupeKey, 200),
          };
        }),
    },
  });
}

function mapDatabaseError(error: AdminDatabaseError): AdminHttpError {
  const message = error.message ?? "";
  if (message.includes("request_id_collision")) {
    return new AdminHttpError("state_conflict", 409);
  }
  const code = ([
    "invalid_request",
    "not_found",
    "state_conflict",
    "reason_required",
  ] as const)
    .find((candidate) => message.includes(candidate));
  if (code === "not_found") return new AdminHttpError(code, 404);
  if (code === "state_conflict") return new AdminHttpError(code, 409);
  if (code) return new AdminHttpError(code, 400);
  return new AdminHttpError("request_failed", 500);
}

export async function handleCardReviewList(
  body: JsonRecord,
  context: AdminActionContext,
): Promise<any> {
  onlyKeys(body, listKeys);
  const lane = requiredLane(body.lane);
  const status = statusFilter(body.status);
  const targetId = body.target_id == null ? null : requiredUuid(body.target_id);
  if (
    status !== null &&
    !(lane === "identity" ? identityStatuses : benefitStatuses).has(status)
  ) invalidRequest();
  const requested = pageRequest(body);
  const { page, limit, offset } = targetId === null
    ? requested
    : { page: 1, limit: 1, offset: 0 };
  let query: any;
  if (lane === "identity") {
    query = (context.db as any).from("card_catalog_review_queue").select(`
      id, proposed_fields, source_evidence, existing_candidates,
      validation_warnings, confidence, status, review_reason, created_at,
      updated_at, reviewed_at,
      card_discovery_jobs!card_catalog_review_queue_discovery_job_id_fkey!inner(
        id, issuer, proposed_product, evidence, status, attempt_count,
        failure_category, resolved_card_id, created_at, updated_at
      )
    `).order("created_at", { ascending: true }).order("id", {
      ascending: true,
    });
  } else {
    query = (context.db as any).from("card_catalog_enrichment_jobs").select(`
      id, card_id, issuer, canonical_url, parser_version, status, run_mode,
      attempt_count, staging_id, failure_category, next_retry_at,
      normalized_fields, result_summary, created_at, updated_at,
      card_catalog!inner(id, bank, card_name),
      card_benefits_staging!card_catalog_enrichment_jobs_staging_id_fkey(
        id, card_id, request_type, parser_version, source_url, source_url_hash,
        content_hash, status, calculated_confidence, validation_reasons,
        validation_warnings, source_evidence, extracted_data,
        benefit_decisions, created_at, reviewed_at
      )
    `).neq("parser_version", "catalog-v1")
      .in("run_mode", ["pilot", "scheduled", "manual"])
      .order("created_at", { ascending: false }).order("id", {
        ascending: true,
      });
  }
  if (status !== null) query = query.eq("status", status);
  if (targetId !== null) query = query.eq("id", targetId);
  const { data, error } = await query.range(
    offset,
    targetId === null ? offset + limit : 0,
  );
  if (error) throw mapDatabaseError(error);
  const rows = Array.isArray(data) ? data : [];
  return {
    lane,
    items: rows.slice(0, limit).map((row) =>
      lane === "identity"
        ? presentIdentityRow(row)
        : presentAdminBenefitJob(row)
    ),
    page,
    limit,
    has_more: targetId === null && rows.length > limit,
  };
}

function decisionPayload(
  value: unknown,
  accepted: ReadonlySet<string>,
  reason: string | null,
) {
  if (
    !Array.isArray(value) || value.length === 0 || value.length > MAX_LIST_ITEMS
  ) {
    invalidRequest();
  }
  return value.map((item) => {
    const row = asRecord(item);
    const action = typeof row?.action === "string"
      ? row.action.toLowerCase()
      : "";
    if (!row || !accepted.has(action)) invalidRequest();
    const allowed = new Set([
      "action",
      "reason",
      "change_type",
      "changeType",
      "dedupe_key",
      "dedupeKey",
      "display_priority",
      "is_primary",
      "benefit",
      "proposed",
      "edited_benefit",
      "editedBenefit",
    ]);
    if (Object.keys(row).some((key) => !allowed.has(key))) invalidRequest();
    const result: JsonRecord = { action };
    for (
      const key of [
        "change_type",
        "dedupe_key",
        "display_priority",
        "is_primary",
      ] as const
    ) {
      const aliases: Record<string, string> = {
        change_type: "changeType",
        dedupe_key: "dedupeKey",
      };
      const itemValue = row[key] ?? row[aliases[key]];
      if (itemValue !== undefined) result[key] = scalar(itemValue, key);
    }
    for (const key of ["benefit", "proposed", "edited_benefit"] as const) {
      const alias = key === "edited_benefit" ? row.editedBenefit : undefined;
      const itemValue = row[key] ?? alias;
      if (itemValue !== undefined) result[key] = canonicalBenefit(itemValue);
    }
    const itemReason = reason ??
      (typeof row.reason === "string" ? row.reason.trim() : null);
    if (itemReason) result.reason = scalar(itemReason, "reason");
    return result;
  });
}

function reasonFor(body: JsonRecord, required: boolean): string | null {
  if (body.reason == null) {
    if (required) invalidRequest();
    return null;
  }
  if (typeof body.reason !== "string") invalidRequest();
  const reason = body.reason.trim();
  if ((required && reason.length < 2) || reason.length > 1_000) {
    invalidRequest();
  }
  return reason || null;
}

function safeActionPayload(
  body: JsonRecord,
  lane: Lane,
  operation: string,
  reason: string | null,
) {
  let payload: JsonRecord = {};
  let stagingId: string | null = null;
  if (lane === "identity") {
    if (operation === "edit_approve") {
      if (!asRecord(body.proposed_fields)) invalidRequest();
      payload = {
        proposed_fields: safeProposedFields(body.proposed_fields, true),
      };
    } else if (operation === "merge") {
      payload = { merge_card_id: requiredUuid(body.merge_card_id) };
    }
    if (body.staging_id != null || body.decisions != null) invalidRequest();
    if (operation !== "edit_approve" && body.proposed_fields != null) {
      invalidRequest();
    }
    if (operation !== "merge" && body.merge_card_id != null) invalidRequest();
  } else {
    if (["approve", "edit_approve", "reject"].includes(operation)) {
      stagingId = requiredUuid(body.staging_id);
      const accepted = operation === "approve"
        ? new Set(["approve", "keep_existing"])
        : operation === "edit_approve"
        ? new Set(["approve", "edit", "reject", "keep_existing"])
        : new Set(["reject"]);
      payload = {
        decisions: decisionPayload(
          body.decisions,
          accepted,
          operation === "reject" ? reason : null,
        ),
      };
    } else if (body.staging_id != null || body.decisions != null) {
      invalidRequest();
    }
    if (body.proposed_fields != null || body.merge_card_id != null) {
      invalidRequest();
    }
  }
  return { payload, stagingId };
}

export async function handleCardReviewAction(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(body, commonActionKeys);
  if (
    new TextEncoder().encode(
      JSON.stringify({ action: "card-review-action", ...body }),
    ).byteLength > MAX_REQUEST_BYTES
  ) {
    invalidRequest();
  }
  const lane = requiredLane(body.lane);
  const operation = typeof body.operation === "string" ? body.operation : "";
  const operations = lane === "identity"
    ? identityOperations
    : benefitOperations;
  if (!operations.has(operation)) invalidRequest();
  const targetId = requiredUuid(body.target_id);
  const requestId = requiredUuid(body.request_id);
  const observed = requiredTimestamp(body.observed_updated_at);
  const reason = reasonFor(
    body,
    operation === "reject" || operation === "quarantine",
  );
  const { payload, stagingId } = safeActionPayload(
    body,
    lane,
    operation,
    reason,
  );
  const { data, error } = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _lane: lane,
    _operation: operation,
    _target_id: targetId,
    _staging_id: stagingId,
    _payload: payload,
    _reason: reason,
    _observed_updated_at: observed,
  });
  if (error) throw mapDatabaseError(error);
  return { result: data };
}

export const cardDataActionHandlers: Readonly<
  Record<string, AdminActionHandler>
> = Object.freeze({
  "card-review-list": handleCardReviewList,
  "card-review-action": handleCardReviewAction,
});
