import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { isAdminEmail } from "../_shared/card_discovery.ts";
import { publishReviewedCardIdentity } from "../_shared/catalog_identity_publication.ts";
import { redactSensitiveUrlsInValue } from "../_shared/benefit_source_privacy.ts";
import {
  BenefitAdminError,
  handleBenefitAdminAction,
  isBenefitAdminAction,
  type UntypedSupabaseClient,
} from "./benefit_admin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

export function safeError(error: unknown): { error: string; status: number } {
  if (error instanceof BenefitAdminError) {
    return { error: error.code, status: error.status };
  }
  const candidate = error && typeof error === "object"
    ? error as { code?: unknown; message?: unknown }
    : {};
  const message = typeof candidate.message === "string"
    ? candidate.message
    : "";
  if (
    candidate.code === "40001" || message.includes(
      "reviewed_enrichment_source_busy",
    )
  ) return { error: "publication_busy", status: 409 };
  for (
    const code of [
      "conflicting_url_identity",
      "url_identity_incompatible",
      "ambiguous_catalog_identity",
      "edit_target_conflict",
      "stale_catalog_review",
      "stale_catalog_publication",
      "stale_catalog_baseline",
    ]
  ) {
    if (message.includes(code)) return { error: code, status: 409 };
  }
  return { error: "Request failed", status: 400 };
}

export function createAdminAuthClient(
  request: Request,
  supabaseUrl: string,
  fallbackKey: string,
  factory: (...args: any[]) => any = createClient,
) {
  const authorization = request.headers.get("Authorization") ?? "";
  const apiKey = request.headers.get("apikey") ?? fallbackKey;
  return factory(supabaseUrl, apiKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function terminalizeCalculatorReviewRows(
  db: UntypedSupabaseClient,
  actorId: string,
  confirmed: boolean,
): Promise<number> {
  if (!confirmed) throw new Error("explicit_admin_confirmation_required");
  const { data, error } = await db.rpc("terminalize_calculator_review_rows", {
    _actor_id: actorId,
    _limit: 1000,
    _confirmed: true,
  });
  if (error) throw error;
  if (!Number.isInteger(data) || Number(data) < 0) {
    throw new Error("invalid_terminal_review_count");
  }
  return Number(data);
}

const catalogReviewProjection = `
  id, proposed_fields, source_evidence, existing_candidates,
  validation_warnings, confidence, status, review_reason, created_at,
  updated_at, reviewed_at,
  card_discovery_jobs!card_catalog_review_queue_discovery_job_id_fkey!inner(
    id, issuer, proposed_product, evidence, status, attempt_count,
    failure_category, resolved_card_id, created_at, updated_at
  )
`;

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function catalogReviewText(value: unknown, maximum = 512): string | null {
  return typeof value === "string" && value.trim()
    ? value.slice(0, maximum)
    : null;
}

function pickCatalogFields(
  source: Record<string, unknown>,
  keys: readonly string[],
): Record<string, unknown> {
  const entries: Array<[string, unknown]> = [];
  for (const key of keys) {
    const value = source[key];
    if (
      value === null || typeof value === "boolean" ||
      (typeof value === "number" && Number.isFinite(value))
    ) {
      entries.push([key, value]);
      continue;
    }
    const bounded = catalogReviewText(value, key.includes("url") ? 2_048 : 512);
    if (bounded !== null) entries.push([key, bounded]);
  }
  return Object.fromEntries(entries);
}

export function presentCatalogReview(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const proposed = record(value.proposed_fields);
  const observation = record(proposed.source_observation);
  const baseline = record(proposed.catalog_baseline);
  const evidence = record(value.source_evidence);
  const rawJob = Array.isArray(value.card_discovery_jobs)
    ? value.card_discovery_jobs[0]
    : value.card_discovery_jobs;
  const job = record(rawJob);
  const jobEvidence = record(job.evidence);
  const candidateRows = Array.isArray(value.existing_candidates)
    ? value.existing_candidates.slice(0, 32)
    : [];
  const output = {
    ...pickCatalogFields(value, [
      "id",
      "status",
      "review_reason",
      "created_at",
      "updated_at",
      "reviewed_at",
    ]),
    confidence: typeof value.confidence === "number" &&
        Number.isFinite(value.confidence)
      ? value.confidence
      : null,
    validation_warnings: Array.isArray(value.validation_warnings)
      ? value.validation_warnings.slice(0, 32).flatMap((item) =>
        catalogReviewText(item, 100) ? [catalogReviewText(item, 100)!] : []
      )
      : [],
    proposed_fields: {
      ...pickCatalogFields(proposed, [
        "issuer",
        "bank",
        "cardName",
        "card_name",
        "network",
        "official_url",
        "card_url",
        "joining_fee",
        "annual_fee",
        "apr",
        "suggested_action",
        "submitted_url_hash",
        "final_url_hash",
        "content_hash",
        "retrieved_at",
      ]),
      ...(Object.keys(baseline).length > 0
        ? {
          catalog_baseline: pickCatalogFields(baseline, [
            "card_id",
            "card_name",
            "network",
            "joining_fee",
            "annual_fee",
            "apr",
            "card_url",
            "is_discontinued",
            "updated_at",
            "version_observed_at",
          ]),
        }
        : {}),
      ...(Object.keys(observation).length > 0
        ? {
          source_observation: pickCatalogFields(observation, [
            "kind",
            "classification",
            "issuer",
            "reason",
            "retryable",
            "retryability_reason",
            "public_evidence",
            "source_status",
            "identity_validated",
            "explicit_discontinuation",
            "retrieved_at",
            "observed_at",
            "matched_excerpt",
          ]),
        }
        : {}),
    },
    source_evidence: pickCatalogFields(evidence, [
      "issuer",
      "official_url",
      "submitted_url",
      "final_url",
      "retrieved_at",
      "source_status",
      "target_excerpt",
      "matched_excerpt",
    ]),
    existing_candidates: candidateRows.map((candidate) =>
      pickCatalogFields(record(candidate), [
        "id",
        "card_name",
        "bank",
        "network",
        "card_url",
        "is_discontinued",
      ])
    ),
    card_discovery_jobs: {
      ...pickCatalogFields(job, [
        "id",
        "issuer",
        "proposed_product",
        "status",
        "attempt_count",
        "failure_category",
        "resolved_card_id",
        "created_at",
        "updated_at",
      ]),
      evidence: pickCatalogFields(jobEvidence, [
        "subject_product",
        "filename_product",
        "pdf_header_product",
        "network",
        "last_four",
        "official_url",
        "pdf_header_excerpt",
        "target_excerpt",
        "retrieved_at",
      ]),
    },
  };
  return redactSensitiveUrlsInValue(output) as Record<string, unknown>;
}

function issuerQuarantineCursor(row: Record<string, unknown>): string {
  const encoded = btoa(JSON.stringify({
    created_at: row.created_at,
    id: row.id,
  }));
  return encoded.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function parseIssuerQuarantineCursor(value: unknown): {
  createdAt: string;
  id: string;
} | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || value.length > 512) {
    throw new Error("invalid_quarantine_cursor");
  }
  try {
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const parsed = JSON.parse(atob(padded));
    const createdAt = String(parsed?.created_at ?? "");
    const id = String(parsed?.id ?? "");
    const date = new Date(createdAt);
    if (
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
        .test(createdAt) ||
      !Number.isFinite(date.getTime()) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(id)
    ) throw new Error("invalid_quarantine_cursor");
    // `Date` validates the instant only. Keep the original PostgreSQL text so
    // six-digit fractional precision is not silently rounded to milliseconds.
    return { createdAt, id };
  } catch {
    throw new Error("invalid_quarantine_cursor");
  }
}

export async function handleAdminCatalogEntry(
  request: Request,
  providedDb?: UntypedSupabaseClient,
  providedAuthDb?: UntypedSupabaseClient,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }
  let user: Record<string, any> | null = null;
  let authError: unknown = null;
  let authDb: UntypedSupabaseClient | null = null;
  try {
    authDb = providedAuthDb ?? providedDb ?? createAdminAuthClient(
      request,
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    );
    const authResult = await authDb.auth.getUser(
      authorization.slice("Bearer ".length),
    );
    user = authResult.data.user;
    authError = authResult.error;
  } catch (error) {
    authError = error;
  }
  if (authError || !user) {
    return json({ error: "Authentication required" }, 401);
  }
  const confirmedIdentity = Boolean(
    user.email_confirmed_at || user.confirmed_at ||
      (Array.isArray(user.identities) &&
        user.identities.some((identity: any) =>
          identity?.identity_data?.email_verified === true ||
          Boolean(identity?.identity_data?.email_confirmed_at)
        )),
  );
  if (!confirmedIdentity) {
    return json({ error: "Administrator access required" }, 403);
  }

  let databaseAdmin = false;
  try {
    const { data, error } = await (authDb as any).from("users")
      .select("is_admin")
      .eq("id", user.id)
      .maybeSingle();
    databaseAdmin = !error && data?.is_admin === true;
  } catch {
    databaseAdmin = false;
  }
  const breakGlass = !databaseAdmin &&
    isAdminEmail(user.email, Deno.env.get("CARD_CATALOG_ADMIN_EMAILS"));
  if (!databaseAdmin && !breakGlass) {
    return json({ error: "Administrator access required" }, 403);
  }
  const authorizationSource = databaseAdmin ? "database_admin" : "break_glass";

  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid request" }, 400);
    }
    const action = body.action;
    if (breakGlass) {
      console.warn(
        `card_catalog_admin_break_glass user_id=${
          String(user.id).slice(0, 100)
        } action=${String(action).slice(0, 80)}`,
      );
    }
    if (action === "access") {
      return json({
        is_admin: true,
        authorization_source: authorizationSource,
      });
    }

    // The privileged client is intentionally created only after the caller's
    // JWT, confirmed identity, and server-governed admin profile are checked.
    const db: UntypedSupabaseClient = providedDb ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    if (action === "purge-calculator-reviews") {
      if (body.confirm !== "non_product_calculator_resource") {
        return json({ error: "explicit_admin_confirmation_required" }, 400);
      }
      return json({
        transitioned: await terminalizeCalculatorReviewRows(db, user.id, true),
      });
    }

    if (isBenefitAdminAction(action)) {
      return json(await handleBenefitAdminAction(db, body, { id: user.id }));
    }

    if (action === "issuer-quarantine-list") {
      const limit = body.limit === undefined ? 25 : Number(body.limit);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
        return json({ error: "invalid_quarantine_limit" }, 400);
      }
      const allowedStatuses = new Set([
        "pending",
        "approved",
        "merged",
        "rejected",
      ]);
      if (
        body.status !== undefined &&
        (typeof body.status !== "string" || !allowedStatuses.has(body.status))
      ) return json({ error: "invalid_quarantine_status" }, 400);
      if (
        body.classification !== undefined &&
        body.classification !== "issuer_discovery_quarantine"
      ) return json({ error: "invalid_quarantine_classification" }, 400);
      const cursor = parseIssuerQuarantineCursor(body.cursor);
      let query = db.from("card_catalog_review_queue")
        .select(catalogReviewProjection)
        .contains("proposed_fields", {
          source_observation: {
            kind: "issuer_discovery_quarantine",
            classification: "issuer_discovery_quarantine",
          },
        })
        .order("created_at", { ascending: false })
        .order("id", { ascending: false });
      if (typeof body.status === "string" && body.status.length > 0) {
        query = query.eq("status", body.status);
      }
      if (cursor) {
        query = query.or(
          `created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`,
        );
      }
      const { data, error } = await query.limit(limit + 1);
      if (error) throw error;
      const rows = (data ?? []) as Array<Record<string, unknown>>;
      const hasMore = rows.length > limit;
      const items = rows.slice(0, limit);
      return json({
        items: items.map(presentCatalogReview),
        has_more: hasMore,
        next_cursor: hasMore
          ? issuerQuarantineCursor(items[items.length - 1])
          : null,
      });
    }

    if (action === "list") {
      let query = db.from("card_catalog_review_queue")
        .select(catalogReviewProjection)
        .order("created_at", { ascending: true });
      if (typeof body.status === "string" && body.status.length > 0) {
        query = query.eq("status", body.status);
      }
      const { data, error } = await query.limit(100);
      if (error) throw error;
      return json({
        items: ((data ?? []) as Array<Record<string, unknown>>).map(
          presentCatalogReview,
        ),
      });
    }

    if (
      ![
        "approve",
        "edit_approve",
        "merge",
        "retry",
        "reject",
        "mark_discontinued",
        "reactivate",
      ].includes(action)
    ) {
      return json({ error: "Unsupported action" }, 400);
    }
    if (
      typeof body.review_item_id !== "string" ||
      body.review_item_id.length === 0
    ) {
      return json({ error: "review_item_id is required" }, 400);
    }
    const editFieldAllowlist = new Set([
      "cardName",
      "card_name",
      "network",
      "annual_fee",
      "joining_fee",
      "apr",
    ]);
    let reviewedFields: Record<string, unknown> = {};
    if (body.proposed_fields !== undefined) {
      if (
        action !== "edit_approve" || !body.proposed_fields ||
        typeof body.proposed_fields !== "object" ||
        Array.isArray(body.proposed_fields) ||
        Object.keys(body.proposed_fields).some((key) =>
          !editFieldAllowlist.has(key)
        )
      ) {
        return json({ error: "immutable_reviewed_field_override" }, 400);
      }
      reviewedFields = { ...body.proposed_fields };
    }
    if (action !== "merge" && body.merge_card_id !== undefined) {
      return json({ error: "invalid_merge_target" }, 400);
    }
    const { data: review, error: reviewError } = await db
      .from("card_catalog_review_queue")
      .select("discovery_job_id,proposed_fields,source_evidence")
      .eq("id", body.review_item_id)
      .single();
    if (reviewError || !review) {
      throw reviewError ?? new Error("review_not_found");
    }
    const data = await publishReviewedCardIdentity(db, {
      discoveryJobId: review.discovery_job_id,
      reviewItemId: body.review_item_id,
      actorId: user.id,
      action,
      reviewedFields,
      mergeCardId: body.merge_card_id ?? null,
      reason: body.reason ?? null,
      parserVersion: "benefits-v6",
    });
    return json({
      success: true,
      result: data,
    });
  } catch (error) {
    const result = safeError(error);
    return json({ error: result.error }, result.status);
  }
}

if (import.meta.main) {
  serve((request) => handleAdminCatalogEntry(request));
}
