import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  allowedOfficialUrl,
  canonicalOfficialUrl,
} from "../_shared/card_discovery.ts";
import {
  diffCatalogFields,
  normalizeOfficialCatalogPage,
} from "../_shared/card_catalog_enrichment.ts";

type UntypedSupabaseClient = any;

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

async function fetchOfficialHtml(issuer: string, initialUrl: string) {
  let url = canonicalOfficialUrl(issuer, initialUrl);
  for (let redirects = 0; redirects <= 4; redirects++) {
    if (!allowedOfficialUrl(issuer, url)) throw new Error("unsafe_redirect");
    const response = await fetch(url, {
      redirect: "manual",
      headers: {
        "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
        Accept: "text/html,application/xhtml+xml",
      },
      signal: AbortSignal.timeout(12_000),
    });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      if (!location) throw new Error("unsafe_redirect");
      try {
        url = canonicalOfficialUrl(issuer, new URL(location, url).toString());
      } catch {
        throw new Error("unsafe_redirect");
      }
      continue;
    }
    if (!response.ok) throw new Error(`official_fetch_${response.status}`);
    const contentType = response.headers.get("content-type")?.split(";")[0] ?? "";
    if (!["text/html", "application/xhtml+xml"].includes(contentType)) {
      throw new Error("unsupported_content");
    }
    const declared = Number(response.headers.get("content-length") ?? 0);
    if (declared > 2_000_000) throw new Error("response_too_large");
    const html = await response.text();
    if (html.length > 2_000_000) throw new Error("response_too_large");
    return { html, finalUrl: url };
  }
  throw new Error("unsafe_redirect");
}

async function queueConflictReview(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  conflicts: unknown[],
) {
  if (!job.discovery_job_id) return;
  const { data: review, error } = await db.from("card_catalog_review_queue")
    .upsert({
      discovery_job_id: job.discovery_job_id,
      proposed_fields: { card_id: job.card_id },
      source_evidence: {
        official_url: job.canonical_url,
        content_hash: job.content_hash,
        field_conflicts: conflicts,
      },
      existing_candidates: [{ card_id: job.card_id }],
      validation_warnings: ["catalog_field_conflict"],
      confidence: 0.9,
      status: "pending",
      updated_at: new Date().toISOString(),
    }, { onConflict: "discovery_job_id" }).select("id").single();
  if (error) throw error;
  await db.from("card_discovery_jobs").update({
    review_item_id: review.id,
    updated_at: new Date().toISOString(),
  }).eq("id", job.discovery_job_id);
}

async function processJob(db: UntypedSupabaseClient, jobId: string) {
  const { data: current, error: readError } = await db
    .from("card_catalog_enrichment_jobs").select("*").eq("id", jobId).single();
  if (readError || !current) throw readError ?? new Error("job_not_found");
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
    .in("status", ["queued", "failed"])
    .select("*")
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return "already_processing";

  try {
    const page = await fetchOfficialHtml(claimed.issuer, claimed.canonical_url);
    const normalized = normalizeOfficialCatalogPage(page.html, page.finalUrl);
    const { data: catalog, error: catalogError } = await db.from("card_catalog")
      .select("id, network, card_type, joining_fee, annual_fee, apr")
      .eq("id", claimed.card_id).single();
    if (catalogError) throw catalogError;

    const compared = diffCatalogFields(catalog, normalized.patch);
    if (Object.keys(compared.backfill).length > 0) {
      const { error } = await db.from("card_catalog").update({
        ...compared.backfill,
        updated_at: new Date().toISOString(),
      }).eq("id", claimed.card_id);
      if (error) throw error;
    }

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

    if (compared.conflicts.length > 0) {
      await queueConflictReview(db, claimed, compared.conflicts);
    }
    const status = compared.conflicts.length > 0 ? "review_required" : "completed";
    const { error } = await db.from("card_catalog_enrichment_jobs").update({
      status,
      normalized_fields: normalized.patch,
      validation_warnings: compared.conflicts.map((item) => ({
        code: "catalog_field_conflict",
        field: item.field,
      })),
      failure_category: null,
      next_retry_at: null,
      updated_at: new Date().toISOString(),
    }).eq("id", claimed.id);
    if (error) throw error;
    return status;
  } catch (error) {
    const attempts = Number(claimed.attempt_count ?? 0);
    const terminal = attempts >= 3;
    const message = error instanceof Error ? error.message.slice(0, 120) : "enrichment_failed";
    await db.from("card_catalog_enrichment_jobs").update({
      status: terminal ? "review_required" : "failed",
      failure_category: message,
      next_retry_at: terminal
        ? null
        : new Date(Date.now() + Math.min(60, 2 ** attempts) * 60_000).toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", claimed.id);
    throw error;
  }
}

serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!serviceKey || request.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
    return json({ error: "authentication_required" }, 401);
  }
  try {
    const body = await request.json();
    if (typeof body.job_id !== "string") return json({ error: "invalid_job" }, 400);
    const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
    const status = await processJob(db, body.job_id);
    return json({ status });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "enrichment_failed",
    }, 500);
  }
});
