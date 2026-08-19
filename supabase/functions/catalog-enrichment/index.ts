import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.2";
import {
  diffCatalogFields,
  normalizeOfficialCatalogPage,
  requireCatalogPageIdentity,
} from "../_shared/card_catalog_enrichment.ts";
import {
  approvedStoredQueryParameters,
  createOfficialRobotsCache,
  fetchOfficialIssuerResource,
  requireOfficialFetchBody,
} from "../_shared/official_issuer_fetch.ts";
import { safeHttpsDisplayUrl } from "../_shared/benefit_source_privacy.ts";
import { publicationFieldsFromFetch } from "../_shared/catalog_identity_publication.ts";

type UntypedSupabaseClient = any;
const CATALOG_FETCH_DEADLINE_MS = 25_000;

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

async function queueConflictReview(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  conflicts: unknown[],
  proposedFields: Record<string, unknown>,
  sourceObservation: Record<string, unknown>,
) {
  if (!job.discovery_job_id) throw new Error("catalog_review_context_required");
  const { data: existingReview, error: existingReviewError } = await db
    .from("card_catalog_review_queue")
    .select("id,status")
    .eq("discovery_job_id", job.discovery_job_id)
    .maybeSingle();
  if (existingReviewError) throw existingReviewError;
  if (
    existingReview &&
    ["approved", "merged", "rejected"].includes(existingReview.status)
  ) return existingReview.id;
  const reviewPayload = {
    discovery_job_id: job.discovery_job_id,
    proposed_fields: {
      card_id: job.card_id,
      issuer: job.issuer,
      ...proposedFields,
      ...sourceObservation,
    },
    source_evidence: {
      official_url: safeHttpsDisplayUrl(job.canonical_url) ??
        "invalid-source",
      content_hash: sourceObservation.content_hash ?? job.content_hash,
      ...sourceObservation,
      field_conflicts: conflicts,
    },
    existing_candidates: [{ card_id: job.card_id }],
    validation_warnings: ["catalog_field_conflict"],
    confidence: 0.9,
    status: "pending",
    updated_at: new Date().toISOString(),
  };
  let review = existingReview;
  if (existingReview) {
    const { data, error } = await db.from("card_catalog_review_queue")
      .update(reviewPayload)
      .eq("id", existingReview.id)
      .eq("status", "pending")
      .select("id,status")
      .maybeSingle();
    if (error) throw error;
    review = data;
  } else {
    const { data, error } = await db.from("card_catalog_review_queue")
      .insert(reviewPayload).select("id,status").maybeSingle();
    if (error && error.code !== "23505") throw error;
    review = data;
  }
  if (!review) {
    const { data, error } = await db.from("card_catalog_review_queue")
      .select("id,status")
      .eq("discovery_job_id", job.discovery_job_id)
      .single();
    if (error || !data) throw error ?? new Error("catalog_review_race");
    review = data;
  }
  if (["approved", "merged", "rejected"].includes(review.status)) {
    return review.id;
  }
  await db.from("card_discovery_jobs").update({
    review_item_id: review.id,
    updated_at: new Date().toISOString(),
  }).eq("id", job.discovery_job_id);
  return review.id;
}

async function finalizeOwnedCatalogJob(
  db: UntypedSupabaseClient,
  jobId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const { data, error } = await db.from("card_catalog_enrichment_jobs")
    .update(patch)
    .eq("id", jobId)
    .eq("status", "processing")
    .eq("run_mode", "manual")
    .eq("parser_version", "catalog-v1")
    .select("id")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("job_not_owned");
}

export async function processCatalogEnrichmentJob(
  db: UntypedSupabaseClient,
  jobId: string,
  deadlineAt = Date.now() + CATALOG_FETCH_DEADLINE_MS,
) {
  const { data: current, error: readError } = await db
    .from("card_catalog_enrichment_jobs").select("*").eq("id", jobId).single();
  if (readError || !current) throw readError ?? new Error("job_not_found");
  if (
    current.run_mode !== "manual" || current.parser_version !== "catalog-v1"
  ) {
    throw new Error("job_not_owned");
  }
  if (current.status === "completed" || current.status === "review_required") {
    return current.status;
  }

  const { data: claimed, error: claimError } = await db
    .from("card_catalog_enrichment_jobs")
    .update({
      status: "processing",
      attempt_count: Number(current.attempt_count ?? 0) + 1,
      updated_at: new Date().toISOString(),
    })
    .eq("id", jobId)
    .eq("run_mode", "manual")
    .eq("parser_version", "catalog-v1")
    .in("status", ["queued", "failed"])
    .select("*")
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return "already_processing";

  try {
    const robotsCache = createOfficialRobotsCache();
    const page = requireOfficialFetchBody(
      await fetchOfficialIssuerResource({
        issuer: claimed.issuer,
        url: claimed.canonical_url,
        contentPurpose: "html",
        enforceRobots: true,
        allowedQueryParameters: approvedStoredQueryParameters(
          claimed.canonical_url,
        ),
        deadlineAt,
        robotsCache,
      }),
    );
    const { data: catalog, error: catalogError } = await db.from("card_catalog")
      .select(
        "id, bank, card_name, network, card_type, joining_fee, annual_fee, apr, is_discontinued",
      )
      .eq("id", claimed.card_id).single();
    if (catalogError) throw catalogError;
    requireCatalogPageIdentity(
      page.text,
      claimed.issuer,
      String(catalog.card_name ?? ""),
    );
    const normalized = normalizeOfficialCatalogPage(page.text, page.finalUrl);
    const publicationEvidence = {
      official_url: page.finalResourceUrl ?? page.finalUrl,
      ...publicationFieldsFromFetch(page),
    };

    const compared = diffCatalogFields(catalog, normalized.patch);

    if (normalized.benefits.length > 0) {
      const { error } = await db.from("card_benefits_staging").insert({
        card_id: claimed.card_id,
        source_url: page.finalUrl,
        extracted_data: {
          request_type: "official_card_enrichment",
          benefits: normalized.benefits,
        },
        status: "pending",
        validation_version: "official-catalog-v1",
        calculated_confidence: Math.min(
          ...normalized.benefits.map((benefit) => benefit.confidence),
        ),
        validation_reasons: [{ code: "official_issuer_source" }],
        validation_warnings: [],
        source_evidence: normalized.evidence,
        validated_at: new Date().toISOString(),
      });
      if (error) throw error;
    }

    const proposedCatalogFields = Object.fromEntries(
      Object.entries(normalized.patch).map(([field, proposal]) => [
        field,
        proposal.value,
      ]),
    );
    const lifecycleSuggestion = catalog.is_discontinued === true
      ? "reactivate"
      : /\b(?:product|card)\s+(?:has\s+been\s+)?(?:discontinued|withdrawn)\b|\bno\s+longer\s+(?:available|issued)\b/i
          .test(page.text)
      ? "mark_discontinued"
      : null;
    const reviewChanges = [
      ...compared.conflicts,
      ...Object.entries(compared.backfill).map(([field, proposed]) => ({
        field,
        existing: null,
        proposed,
        kind: "reviewed_backfill",
      })),
      ...(lifecycleSuggestion
        ? [{
          field: "is_discontinued",
          existing: catalog.is_discontinued === true,
          proposed: lifecycleSuggestion === "mark_discontinued",
          kind: "lifecycle_observation",
        }]
        : []),
    ];
    if (reviewChanges.length > 0) {
      await queueConflictReview(
        db,
        claimed,
        reviewChanges,
        {
          ...proposedCatalogFields,
          ...(lifecycleSuggestion
            ? { suggested_action: lifecycleSuggestion }
            : {}),
        },
        {
          ...publicationEvidence,
          source_type: "official_html",
          source_observation: {
            status: page.status,
            kind: "catalog_enrichment",
          },
        },
      );
    }
    const status = reviewChanges.length > 0 ? "review_required" : "completed";
    await finalizeOwnedCatalogJob(db, claimed.id, {
      status,
      normalized_fields: normalized.patch,
      validation_warnings: reviewChanges.map((item) => ({
        code: "catalog_field_conflict",
        field: item.field,
      })),
      failure_category: null,
      next_retry_at: null,
      updated_at: new Date().toISOString(),
    });
    return status;
  } catch (error) {
    const attempts = Number(claimed.attempt_count ?? 0);
    const terminal = attempts >= 3;
    const message = error instanceof Error
      ? error.message.slice(0, 120)
      : "enrichment_failed";
    if (
      ["http_404", "http_410", "identity_review", "redirect_rejected"]
        .includes(message) && claimed.discovery_job_id
    ) {
      const strongGoneObservation = message === "http_410";
      await queueConflictReview(
        db,
        claimed,
        [{
          field: "is_discontinued",
          existing: false,
          proposed: true,
          kind: strongGoneObservation
            ? "http_lifecycle_observation"
            : "weak_source_absence_observation",
        }],
        strongGoneObservation ? { suggested_action: "mark_discontinued" } : {},
        {
          official_url: claimed.canonical_url,
          ...(message === "http_404"
            ? { source_status: 404 }
            : message === "http_410"
            ? { source_status: 410 }
            : {}),
          source_type: "official_html",
          source_observation: {
            failure: message,
            kind: strongGoneObservation
              ? "strong_gone_observation"
              : "weak_source_absence_observation",
          },
        },
      );
    }
    await finalizeOwnedCatalogJob(db, claimed.id, {
      status: terminal ? "review_required" : "failed",
      failure_category: message,
      next_retry_at: terminal
        ? null
        : new Date(Date.now() + Math.min(60, 2 ** attempts) * 60_000)
          .toISOString(),
      updated_at: new Date().toISOString(),
    });
    throw error;
  }
}

if (import.meta.main) {
  serve(async (request) => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (
      !serviceKey ||
      request.headers.get("Authorization") !== `Bearer ${serviceKey}`
    ) {
      return json({ error: "authentication_required" }, 401);
    }
    try {
      const body = await request.json();
      if (typeof body.job_id !== "string") {
        return json({ error: "invalid_job" }, 400);
      }
      const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
      const status = await processCatalogEnrichmentJob(db, body.job_id);
      return json({ status });
    } catch (error) {
      return json({
        error: error instanceof Error ? error.message : "enrichment_failed",
      }, 500);
    }
  });
}
