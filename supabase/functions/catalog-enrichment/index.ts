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
import {
  boundedCatalogSourceObservation,
  cardDiscontinuationEvidence,
  catalogLifecycleObservationAction,
  catalogPublicationBaseline,
  proposeCatalogLifecycleReview,
  publicationFieldsFromFetch,
  semanticCatalogSourceObservation,
  semanticProductEnvelopeHash,
  stageCatalogIdentityReview,
} from "../_shared/catalog_identity_publication.ts";

type UntypedSupabaseClient = any;
const CATALOG_FETCH_DEADLINE_MS = 25_000;

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(bytes)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function queueConflictReview(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  conflicts: unknown[],
  proposedFields: Record<string, unknown>,
  sourceObservation: Record<string, unknown>,
) {
  if (!job.card_id || !job.issuer) {
    throw new Error("catalog_review_context_required");
  }
  const boundedObservation = boundedCatalogSourceObservation(sourceObservation);
  const digest = async (value: string) => {
    const bytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(value),
    );
    return [...new Uint8Array(bytes)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("");
  };
  const submittedHash = String(
    boundedObservation.submitted_url_hash ??
      boundedObservation.submitted_resource_identity_hash ?? "",
  ).toLowerCase();
  const finalHash = String(
    boundedObservation.final_url_hash ??
      boundedObservation.final_resource_identity_hash ?? submittedHash,
  ).toLowerCase();
  const sourceObservationHash = await digest(
    JSON.stringify(semanticCatalogSourceObservation(boundedObservation)),
  );
  const contentHash =
    /^[0-9a-f]{64}$/.test(String(boundedObservation.content_hash ?? ""))
      ? String(boundedObservation.content_hash).toLowerCase()
      : sourceObservationHash;
  const baselineHash = await digest(JSON.stringify(
    proposedFields.catalog_baseline ?? boundedObservation.catalog_baseline ??
      null,
  ));
  const baselineCardName =
    (proposedFields.catalog_baseline as Record<string, unknown> | undefined)
      ?.card_name;
  const semanticProductHash = await semanticProductEnvelopeHash({
    card_id: job.card_id,
    issuer: job.issuer,
    cardName: baselineCardName ?? job.card_name ?? null,
    proposed_fields: proposedFields,
    field_conflicts: conflicts,
    source_observation: semanticCatalogSourceObservation(boundedObservation),
  });
  const dedupeKey = await digest(
    `catalog-review:${job.card_id}:${submittedHash}:${finalHash}:${semanticProductHash}:${baselineHash}`,
  );
  const staged = await stageCatalogIdentityReview(db, {
    discoveryJobId: null,
    discoverySource: "issuer_crawl",
    userId: null,
    issuer: job.issuer,
    proposedProduct: baselineCardName ?? job.card_name ?? null,
    dedupeKey,
    semanticHash: semanticProductHash,
    proposedFields: {
      card_id: job.card_id,
      issuer: job.issuer,
      cardName: baselineCardName ?? job.card_name ?? null,
      ...proposedFields,
    },
    sourceEvidence: {
      official_url: safeHttpsDisplayUrl(job.canonical_url) ??
        "https://invalid.invalid/source",
      content_hash: contentHash,
      source_observation_hash: sourceObservationHash,
      semantic_product_hash: semanticProductHash,
      ...boundedObservation,
      field_conflicts: conflicts,
    },
    existingCandidates: [{ card_id: job.card_id }],
    validationWarnings: ["catalog_field_conflict"],
    confidence: 0.9,
    expectedJobStatus: null,
    expectedJobUpdatedAt: null,
  });
  return staged.reviewItemId;
}

async function finalizeOwnedCatalogJob(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  patch: Record<string, unknown>,
): Promise<void> {
  let update = db.from("card_catalog_enrichment_jobs")
    .update(patch)
    .eq("id", job.id)
    .eq("status", "processing")
    .eq("run_mode", "manual")
    .eq("parser_version", "catalog-v1")
    .eq("updated_at", job.updated_at);
  update = job.lease_token
    ? update.eq("lease_token", job.lease_token)
    : update.is("lease_token", null);
  const { data, error } = await update.select("id")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("job_not_owned");
}

export async function processCatalogEnrichmentJob(
  db: UntypedSupabaseClient,
  jobId: string,
  deadlineAt = Date.now() + CATALOG_FETCH_DEADLINE_MS,
) {
  let catalogSnapshot: Record<string, unknown> | null = null;
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
    .eq("updated_at", current.updated_at)
    .select("*")
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return "already_processing";

  try {
    const { data: catalog, error: catalogError } = await db.from("card_catalog")
      .select(
        "id, bank, card_name, network, card_type, joining_fee, annual_fee, apr, card_url, is_discontinued, updated_at",
      )
      .eq("id", claimed.card_id).single();
    if (catalogError) throw catalogError;
    catalogSnapshot = catalog;
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
    const catalogBaseline = catalogPublicationBaseline({
      ...catalog,
      retrieved_at: page.retrievedAt,
    });
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
    const discontinuationEvidence = cardDiscontinuationEvidence(
      page.text,
      String(catalog.bank),
      String(catalog.card_name),
    );
    const explicitDiscontinuation = discontinuationEvidence.explicit;
    const lifecycleAction = catalogLifecycleObservationAction({
      isDiscontinued: catalog.is_discontinued === true,
      httpStatus: page.status,
      identityValidated: true,
      explicitDiscontinuation,
    });
    if (!lifecycleAction) throw new Error("invalid_catalog_lifecycle_evidence");
    const lifecycleObservation = {
      source_status: page.status,
      kind: lifecycleAction === "reactivate"
        ? "exact_card_reappearance"
        : lifecycleAction === "mark_discontinued"
        ? "strong_explicit_discontinuation"
        : catalog.is_discontinued === true
        ? "strong_explicit_discontinuation"
        : "exact_card_reappearance",
      identity_validated: true,
      explicit_discontinuation: explicitDiscontinuation,
      matched_excerpt: discontinuationEvidence.matchedExcerpt,
      retrieved_at: page.retrievedAt,
    };
    const lifecycleSourceUrl = page.finalResourceUrl ?? page.finalUrl;
    const lifecycleSourceHash = page.finalResourceIdentityHash ??
      await sha256Hex(lifecycleSourceUrl);
    await proposeCatalogLifecycleReview(db, {
      cardId: String(claimed.card_id),
      suggestedAction: lifecycleAction,
      sourceObservation: lifecycleObservation,
      sourceUrl: lifecycleSourceUrl,
      sourceUrlHash: lifecycleSourceHash,
      contentHash: page.contentHash,
      parserVersion: "benefits-v6",
    });
    const reviewChanges = [
      ...compared.conflicts,
      ...Object.entries(compared.backfill).map(([field, proposed]) => ({
        field,
        existing: null,
        proposed,
        kind: "reviewed_backfill",
      })),
    ];
    if (reviewChanges.length > 0) {
      await queueConflictReview(
        db,
        claimed,
        reviewChanges,
        {
          ...proposedCatalogFields,
          catalog_baseline: catalogBaseline,
        },
        {
          ...publicationEvidence,
          source_type: "official_html",
          source_observation: lifecycleObservation,
          catalog_baseline: catalogBaseline,
        },
      );
    }
    const status = reviewChanges.length > 0 ||
        lifecycleAction !== "observe_current"
      ? "review_required"
      : "completed";
    await finalizeOwnedCatalogJob(db, claimed, {
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
        .includes(message)
    ) {
      const strongGoneObservation = message === "http_410";
      const catalogBaseline = catalogSnapshot
        ? catalogPublicationBaseline(catalogSnapshot as never)
        : null;
      const observedAt = new Date().toISOString();
      if (strongGoneObservation && catalogSnapshot) {
        const lifecycleAction = catalogLifecycleObservationAction({
          isDiscontinued: catalogSnapshot.is_discontinued === true,
          httpStatus: 410,
          identityValidated: false,
          explicitDiscontinuation: false,
        });
        if (!lifecycleAction) {
          throw new Error("invalid_catalog_lifecycle_evidence");
        }
        await proposeCatalogLifecycleReview(db, {
          cardId: String(claimed.card_id),
          suggestedAction: lifecycleAction,
          sourceObservation: {
            failure: message,
            kind: "strong_gone_observation",
            source_status: 410,
            identity_validated: false,
            explicit_discontinuation: false,
            retrieved_at: observedAt,
          },
          sourceUrl: String(claimed.canonical_url),
          sourceUrlHash: /^[0-9a-f]{64}$/.test(
              String(claimed.final_url_hash ?? "").toLowerCase(),
            )
            ? String(claimed.final_url_hash).toLowerCase()
            : await sha256Hex(String(claimed.canonical_url)),
          contentHash: /^[0-9a-f]{64}$/.test(
              String(claimed.content_hash ?? "").toLowerCase(),
            )
            ? String(claimed.content_hash).toLowerCase()
            : null,
          parserVersion: "benefits-v6",
        });
      } else {
        await queueConflictReview(
          db,
          claimed,
          [{
            field: "is_discontinued",
            existing: catalogSnapshot?.is_discontinued === true,
            proposed: true,
            kind: "weak_source_absence_observation",
          }],
          catalogBaseline ? { catalog_baseline: catalogBaseline } : {},
          {
            official_url: claimed.canonical_url,
            ...(message === "http_404" ? { source_status: 404 } : {}),
            source_type: "official_html",
            source_observation: {
              failure: message,
              kind: "weak_source_absence_observation",
              source_status: message === "http_404" ? 404 : null,
              identity_validated: false,
              retrieved_at: observedAt,
            },
            ...(catalogBaseline ? { catalog_baseline: catalogBaseline } : {}),
          },
        );
      }
    }
    await finalizeOwnedCatalogJob(db, claimed, {
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
