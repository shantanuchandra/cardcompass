import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.2";
import {
  allowedOfficialUrl,
  canonicalCardIdentity,
  canonicalOfficialUrl,
  evaluateAutomaticCatalogGate,
  exactOfficialPageIdentity,
  normalizedProduct,
  officialDomainsForIssuer,
  publicDiscoveryResult,
  publicReasonCode,
  rankOfficialUrls,
  reviewRequiredJobPatch,
  sanitizeEvidence,
  selectSubmittedUrlIdentity,
} from "../_shared/card_discovery.ts";
import { fetchOfficialIssuerResource } from "../_shared/official_issuer_fetch.ts";
import { enqueueBenefitEnrichmentJob } from "../benefit-enrichment-batch/batch_policy.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
type UntypedSupabaseClient = any;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const knownOfficialSources: Record<string, Record<string, string>> = {
  "Axis Bank": {
    privilege:
      "https://www.axis.bank.in/cards/credit-card/privilege-credit-card-with-unlimited-benefits",
  },
  "IndusInd Bank": {
    eazydinerplatinum:
      "https://www.indusind.com/in/en/personal/cards/credit-card/eazydiner-platinum-credit-card.html",
  },
  "Kotak Bank": {
    whitereserve: "https://www.kotak.com/rd/white-reserve",
  },
};

type SafeEvidence = {
  issuer: string;
  subject_product?: string;
  filename_product?: string;
  pdf_header_product?: string;
  network?: string;
  last_four?: string;
  attachment_filename?: string;
  pdf_header_excerpt?: string;
  product_signals?: string[];
  warnings?: string[];
  confidence?: number;
};

type CrawlerReviewEvidence = SafeEvidence & {
  official_url?: string;
  crawler_evidence?: unknown[];
  crawler_proposal?: Record<string, unknown>;
  crawler_source_evidence?: Record<string, unknown>;
  crawler_existing_candidates?: Array<Record<string, unknown>>;
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

function safeEvidence(raw: unknown): SafeEvidence {
  if (!raw || typeof raw !== "object") throw new Error("evidence is required");
  const value = raw as Record<string, unknown>;
  const issuer = typeof value.issuer === "string" ? value.issuer.trim() : "";
  if (issuer.length < 2 || officialDomainsForIssuer(issuer).length === 0) {
    throw new Error("unsupported issuer");
  }
  const short = (key: string, max = 180) => {
    const item = value[key];
    return typeof item === "string" && item.trim()
      ? item.trim().slice(0, max)
      : undefined;
  };
  const lastFour = short("last_four", 4);
  const signals = [
    short("subject_product"),
    short("filename_product"),
    short("pdf_header_product"),
  ].filter((item): item is string => Boolean(item));
  return {
    issuer,
    subject_product: short("subject_product"),
    filename_product: short("filename_product"),
    pdf_header_product: short("pdf_header_product"),
    network: short("network", 40),
    last_four: lastFour && /^\d{4}$/.test(lastFour) ? lastFour : undefined,
    attachment_filename: short("attachment_filename", 220)?.replace(
      /(?<!\d)\d{6,}(?!\d)/g,
      "[redacted]",
    ),
    pdf_header_excerpt: sanitizeEvidence(
      short("pdf_header_excerpt", 1000) ?? "",
    ),
    product_signals: signals,
    warnings: Array.isArray(value.warnings)
      ? value.warnings.filter((item): item is string =>
        typeof item === "string"
      ).slice(0, 10)
      : [],
    confidence: typeof value.confidence === "number"
      ? Math.max(0, Math.min(1, value.confidence))
      : 0,
  };
}

async function sha256(value: string): Promise<string> {
  return sha256Bytes(new TextEncoder().encode(value));
}

async function sha256Bytes(value: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    value.slice().buffer as ArrayBuffer,
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function findCatalogCardByUrlHashes(
  db: UntypedSupabaseClient,
  hashes: string[],
): Promise<string | null> {
  const unique = [...new Set(hashes.filter(Boolean))];
  if (unique.length === 0) return null;
  const { data: key, error: keyError } = await db.from("card_catalog_url_keys")
    .select("card_id")
    .in("url_hash", unique)
    .limit(1)
    .maybeSingle();
  if (keyError) throw keyError;
  if (key?.card_id) return key.card_id;
  const filter = unique.flatMap((hash) => [
    `submitted_url_hash.eq.${hash}`,
    `final_url_hash.eq.${hash}`,
  ]).join(",");
  const { data, error } = await db.from("card_catalog_provenance")
    .select("card_id")
    .or(filter)
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data?.card_id ?? null;
}

async function upsertDiscoveryJob(
  db: UntypedSupabaseClient,
  userId: string,
  evidence: SafeEvidence,
) {
  const product = evidence.product_signals?.[0] ?? "unknown";
  const dedupeKey = await sha256(
    `${evidence.issuer}:${
      normalizedProduct(product, evidence.issuer) || "unknown"
    }`,
  );
  const { data, error } = await db.from("card_discovery_jobs").upsert({
    user_id: userId,
    issuer: evidence.issuer,
    proposed_product: product === "unknown" ? null : product,
    evidence,
    dedupe_key: dedupeKey,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id,dedupe_key", ignoreDuplicates: false })
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

async function markResolved(
  db: UntypedSupabaseClient,
  jobId: string,
  cardId: string,
) {
  const { data, error } = await db.from("card_discovery_jobs").update({
    status: "resolved",
    resolved_card_id: cardId,
    failure_category: null,
    next_retry_at: null,
    updated_at: new Date().toISOString(),
  }).eq("id", jobId).select("*").single();
  if (error) throw error;
  return data;
}

async function processSubmittedUrl(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  rawUrl: string,
) {
  const evidence = job.evidence as SafeEvidence;
  const submittedUrl = canonicalOfficialUrl(job.issuer, rawUrl);
  const submittedHash = await sha256(submittedUrl);
  const knownSubmitted = await findCatalogCardByUrlHashes(db, [submittedHash]);
  if (knownSubmitted) return markResolved(db, job.id, knownSubmitted);

  const page = await fetchOfficialIssuerResource({
    issuer: job.issuer,
    url: submittedUrl,
  });
  const finalUrl = page.canonicalUrl;
  const finalHash = await sha256(finalUrl);
  const knownFinal = await findCatalogCardByUrlHashes(
    db,
    [submittedHash, finalHash],
  );
  if (knownFinal) return markResolved(db, job.id, knownFinal);

  if (page.contentType === "application/pdf") {
    const product = evidence.product_signals?.find((value) =>
      normalizedProduct(value, job.issuer).length >= 4
    ) ?? job.proposed_product;
    if (!product) {
      throw new Error("not_product_page");
    }
    const canonical = canonicalCardIdentity(job.issuer, product);
    await putInReview(
      db,
      job,
      { ...canonical, official_url: finalUrl },
      {
        evidence,
        official_url: finalUrl,
        content_hash: page.contentHash,
        source_type: "official_pdf",
      },
      ["official_pdf_requires_review"],
      evidence.confidence ?? 0,
    );
    return (await db.from("card_discovery_jobs").select("*").eq("id", job.id)
      .single()).data;
  }

  const pageText = htmlText(page.text);
  const selected = selectSubmittedUrlIdentity({
    html: page.text,
    issuer: job.issuer,
    statementProducts: evidence.product_signals ?? [],
  });
  const canonical = selected.identity;
  if (!canonical) throw new Error("not_product_page");
  const officialIdentity = exactOfficialPageIdentity(
    page.text,
    job.issuer,
    canonical.cardName,
  );
  if (!officialIdentity) {
    throw new Error("not_product_page");
  }
  const gate = evaluateAutomaticCatalogGate({
    issuer: job.issuer,
    officialUrl: finalUrl,
    officialProduct: officialIdentity.cardName,
    statementProducts: selected.statementProducts,
    confidence: evidence.confidence ?? 0,
    catalogCandidateCount: 0,
    conflicts: evidence.warnings ?? [],
  });
  if (!gate.autoAdd) {
    await putInReview(
      db,
      job,
      { ...officialIdentity, official_url: finalUrl },
      {
        evidence,
        official_url: finalUrl,
        content_hash: page.contentHash,
        excerpt: sanitizeEvidence(pageText),
      },
      gate.reasons,
      evidence.confidence ?? 0,
    );
    return (await db.from("card_discovery_jobs").select("*").eq("id", job.id)
      .single()).data;
  }

  const { data: cardId, error: resolveError } = await db.rpc(
    "resolve_card_catalog_identity",
    {
      _issuer: job.issuer,
      _card_name: officialIdentity.cardName,
      _network: canonical.network ?? evidence.network ?? null,
      _source_url: finalUrl,
      _submitted_url_hash: submittedHash,
      _final_url_hash: finalHash,
    },
  );
  if (resolveError || !cardId) {
    throw resolveError ?? new Error("identity_conflict");
  }

  for (
    const alias of [...canonical.aliases, ...(evidence.product_signals ?? [])]
  ) {
    const normalizedAlias = normalizedProduct(alias, job.issuer);
    if (normalizedAlias.length < 2) continue;
    const { error } = await db.from("card_catalog_aliases").upsert({
      card_id: cardId,
      discovery_job_id: job.id,
      alias,
      normalized_alias: normalizedAlias,
      evidence_type: "issuer_page",
      source_url: finalUrl,
    }, { onConflict: "card_id,normalized_alias" });
    if (error) throw error;
  }
  const { error: provenanceError } = await db.from("card_catalog_provenance")
    .upsert({
      card_id: cardId,
      source_url: finalUrl,
      canonical_submitted_url: submittedUrl,
      canonical_final_url: finalUrl,
      submitted_url_hash: submittedHash,
      final_url_hash: finalHash,
      source_type: "official_html",
      content_hash: page.contentHash,
      extracted_fields: canonical,
      source_evidence: { excerpt: sanitizeEvidence(pageText) },
      validation_version: "card-identity-v2",
      confidence: evidence.confidence ?? 0,
      approval_method: "automatic",
      retrieved_at: new Date().toISOString(),
    }, { onConflict: "card_id,source_url,content_hash" });
  if (provenanceError) throw provenanceError;

  await enqueueBenefitEnrichmentJob(db, {
    cardId,
    issuer: job.issuer,
    canonicalUrl: finalUrl,
    finalUrlHash: finalHash,
    contentHash: page.contentHash,
    parserVersion: "benefits-v5",
  });
  return markResolved(db, job.id, cardId);
}

function htmlText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .slice(0, 120_000);
}

async function discoverOfficialUrl(
  issuer: string,
  product: string,
): Promise<string | null> {
  const normalized = normalizedProduct(product, issuer);
  const known = knownOfficialSources[issuer]?.[normalized];
  if (known) return known;

  const urls: string[] = [];
  for (const domain of officialDomainsForIssuer(issuer)) {
    for (const sitemapPath of ["/sitemap.xml", "/sitemap_index.xml"]) {
      try {
        const response = await fetchOfficialIssuerResource({
          issuer,
          url: `https://${domain}${sitemapPath}`,
          contentPurpose: "sitemap",
        });
        urls.push(
          ...Array.from(
            response.text.matchAll(/<loc>\s*([^<]+)\s*<\/loc>/gi),
            (m) => m[1],
          ),
        );
      } catch {
        // An issuer may not publish a sitemap at either conventional path.
      }
    }
  }
  return rankOfficialUrls(product, urls)
    .find((url) => allowedOfficialUrl(issuer, url)) ?? null;
}

async function putInReview(
  db: UntypedSupabaseClient,
  job: Record<string, unknown>,
  proposedFields: Record<string, unknown>,
  sourceEvidence: Record<string, unknown>,
  warnings: string[],
  confidence: number,
  existingCandidates: unknown[] = [],
  preserveTerminal = false,
) {
  if (preserveTerminal) {
    const { data: currentReview, error: currentReviewError } = await db
      .from("card_catalog_review_queue")
      .select("id, status")
      .eq("discovery_job_id", job.id)
      .maybeSingle();
    if (currentReviewError) throw currentReviewError;
    if (
      currentReview &&
      ["approved", "merged", "rejected"].includes(currentReview.status)
    ) {
      return;
    }

    let review = currentReview;
    if (!review) {
      const { data, error } = await db.from("card_catalog_review_queue")
        .insert({
          discovery_job_id: job.id,
          proposed_fields: proposedFields,
          source_evidence: sourceEvidence,
          existing_candidates: existingCandidates,
          validation_warnings: warnings,
          confidence,
          status: "pending",
          updated_at: new Date().toISOString(),
        })
        .select("id, status")
        .single();
      if (!error) {
        review = data;
      } else {
        const { data: racedReview, error: racedReviewError } = await db
          .from("card_catalog_review_queue")
          .select("id, status")
          .eq("discovery_job_id", job.id)
          .maybeSingle();
        if (racedReviewError || !racedReview) throw error;
        if (["approved", "merged", "rejected"].includes(racedReview.status)) {
          return;
        }
        review = racedReview;
      }
    }
    const { error: updateError } = await db.from("card_discovery_jobs").update(
      reviewRequiredJobPatch(review.id, new Date().toISOString()),
    ).eq("id", job.id).in("status", [
      "queued",
      "discovering",
      "failed",
      "review_required",
    ]);
    if (updateError) throw updateError;
    return;
  }

  const { data: review, error } = await db.from("card_catalog_review_queue")
    .upsert({
      discovery_job_id: job.id,
      proposed_fields: proposedFields,
      source_evidence: sourceEvidence,
      existing_candidates: existingCandidates,
      validation_warnings: warnings,
      confidence,
      status: "pending",
      updated_at: new Date().toISOString(),
    }, { onConflict: "discovery_job_id" })
    .select("id")
    .single();
  if (error) throw error;
  await db.from("card_discovery_jobs").update(
    reviewRequiredJobPatch(review.id, new Date().toISOString()),
  ).eq("id", job.id);
}

async function processDiscoveryJob(
  db: UntypedSupabaseClient,
  jobId: string,
) {
  const { data: rawJob, error } = await db.from("card_discovery_jobs")
    .select("*").eq("id", jobId).single();
  if (error || !rawJob) return;
  const job = rawJob as Record<string, any>;
  const evidence = job.evidence as SafeEvidence;
  if (job.discovery_source === "issuer_crawl") {
    if (["resolved", "rejected"].includes(job.status)) return;
    const crawlerEvidence = evidence as CrawlerReviewEvidence;
    const proposal = crawlerEvidence.crawler_proposal ?? {
      issuer: job.issuer,
      cardName: job.proposed_product ?? "",
    };
    const sourceEvidence = crawlerEvidence.crawler_source_evidence ?? {
      official_url: typeof crawlerEvidence.official_url === "string"
        ? crawlerEvidence.official_url
        : undefined,
      excerpts: Array.isArray(crawlerEvidence.crawler_evidence)
        ? crawlerEvidence.crawler_evidence
        : [],
    };
    const existingCandidates =
      Array.isArray(crawlerEvidence.crawler_existing_candidates)
        ? crawlerEvidence.crawler_existing_candidates
        : [];
    const warnings = [
      ...new Set([
        ...(evidence.warnings ?? []),
        "crawler_discovered_without_statement_signal",
      ]),
    ];
    await putInReview(
      db,
      job,
      proposal,
      sourceEvidence,
      warnings,
      evidence.confidence ?? 0,
      existingCandidates,
      true,
    );
    return;
  }
  const product = evidence.product_signals?.[0] ?? job.proposed_product;
  if (!product) {
    await putInReview(db, job, { issuer: job.issuer }, { evidence }, [
      "missing_product_identity",
    ], 0);
    return;
  }

  await db.from("card_discovery_jobs").update({
    status: "discovering",
    attempt_count: Number(job.attempt_count ?? 0) + 1,
    updated_at: new Date().toISOString(),
  }).eq("id", jobId);

  try {
    const canonical = canonicalCardIdentity(job.issuer, product);
    const officialUrl = await discoverOfficialUrl(
      job.issuer,
      canonical.cardName,
    );
    if (!officialUrl) {
      await putInReview(db, job, canonical, { evidence }, [
        "official_source_not_found",
      ], evidence.confidence ?? 0);
      return;
    }
    const page = await fetchOfficialIssuerResource({
      issuer: job.issuer,
      url: officialUrl,
    });
    if (page.contentType === "application/pdf") {
      await putInReview(
        db,
        job,
        canonical,
        {
          evidence,
          official_url: page.finalUrl,
          content_hash: page.contentHash,
          source_type: "official_pdf",
        },
        ["official_pdf_requires_review"],
        evidence.confidence ?? 0,
      );
      return;
    }
    const pageText = htmlText(page.text);
    const officialIdentity = exactOfficialPageIdentity(
      page.text,
      job.issuer,
      canonical.cardName,
    );
    if (!officialIdentity) {
      await putInReview(
        db,
        job,
        { ...canonical, official_url: page.finalUrl },
        {
          evidence,
          official_url: page.finalUrl,
          content_hash: page.contentHash,
        },
        ["official_product_not_found"],
        evidence.confidence ?? 0,
      );
      return;
    }
    const officialProduct = officialIdentity.cardName;

    const { data: catalogRows, error: catalogError } = await db
      .from("card_catalog")
      .select("id, bank, card_name, network")
      .ilike("bank", job.issuer)
      .eq("is_discontinued", false);
    if (catalogError) throw catalogError;
    const existing = (catalogRows ?? []).filter((
      row: Record<string, unknown>,
    ) =>
      normalizedProduct(String(row.card_name ?? ""), job.issuer) ===
        normalizedProduct(officialProduct, job.issuer)
    );
    const gate = evaluateAutomaticCatalogGate({
      issuer: job.issuer,
      officialUrl: page.finalUrl,
      officialProduct,
      statementProducts: evidence.product_signals ?? [],
      confidence: evidence.confidence ?? 0,
      catalogCandidateCount: existing.length,
      conflicts: evidence.warnings ?? [],
    });
    if (!gate.autoAdd) {
      await putInReview(
        db,
        job,
        { ...officialIdentity, official_url: page.finalUrl },
        {
          evidence,
          official_url: page.finalUrl,
          content_hash: page.contentHash,
          excerpt: sanitizeEvidence(pageText),
        },
        gate.reasons,
        evidence.confidence ?? 0,
        existing,
      );
      return;
    }

    let cardId = existing[0]?.id as string | undefined;
    if (!cardId) {
      const { data: card, error: insertError } = await db.from("card_catalog")
        .insert({
          bank: officialIdentity.issuer,
          card_name: officialIdentity.cardName,
          network: officialIdentity.network ?? canonical.network ??
            evidence.network ?? null,
          card_type: "credit",
          card_url: page.finalUrl,
        }).select("id").single();
      if (insertError) throw insertError;
      cardId = card.id;
    }
    for (
      const alias of [
        ...officialIdentity.aliases,
        ...canonical.aliases,
        ...(evidence.product_signals ?? []),
      ]
    ) {
      await db.from("card_catalog_aliases").upsert({
        card_id: cardId,
        alias,
        normalized_alias: normalizedProduct(alias, job.issuer),
        evidence_type: "issuer_page",
        source_url: page.finalUrl,
      }, { onConflict: "card_id,normalized_alias" });
    }
    await db.from("card_catalog_provenance").upsert({
      card_id: cardId,
      source_url: page.finalUrl,
      source_type: "official_html",
      content_hash: page.contentHash,
      extracted_fields: officialIdentity,
      source_evidence: { excerpt: sanitizeEvidence(pageText) },
      validation_version: "card-identity-v1",
      confidence: evidence.confidence ?? 0,
      approval_method: "automatic",
      retrieved_at: new Date().toISOString(),
    }, { onConflict: "card_id,source_url,content_hash" });
    await db.from("card_discovery_jobs").update({
      status: "resolved",
      resolved_card_id: cardId,
      failure_category: null,
      next_retry_at: null,
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  } catch (error) {
    const attempt = Number(job.attempt_count ?? 0) + 1;
    const failure = error instanceof Error
      ? error.message.slice(0, 120)
      : "discovery_failed";
    if (attempt >= 3) {
      const canonical = canonicalCardIdentity(job.issuer, String(product));
      await putInReview(
        db,
        job,
        canonical,
        { evidence },
        [failure],
        evidence.confidence ?? 0,
      );
      return;
    }
    await db.from("card_discovery_jobs").update({
      status: "failed",
      failure_category: failure,
      next_retry_at: new Date(Date.now() + Math.min(60, 2 ** attempt) * 60_000)
        .toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  }
}

serve(async (request) => {
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

  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data: { user }, error: authError } = await db.auth.getUser(
    authorization.slice("Bearer ".length),
  );
  if (authError || !user) {
    return json({ error: "Authentication required" }, 401);
  }

  try {
    const body = await request.json();
    const action = body.action;
    if (action === "resolve_url") {
      const evidence = safeEvidence(body.evidence);
      if (
        typeof body.source_url !== "string" || body.source_url.length > 2048
      ) {
        return json({ error: "invalid_url", reason_code: "invalid_url" }, 400);
      }
      const job = await upsertDiscoveryJob(db, user.id, evidence);
      try {
        const result = await processSubmittedUrl(db, job, body.source_url);
        return json(publicDiscoveryResult(result));
      } catch (error) {
        const reason = publicReasonCode(error);
        await db.from("card_discovery_jobs").update({
          status: reason === "fetch_timeout" ? "failed" : "review_required",
          failure_category: reason,
          next_retry_at: reason === "fetch_timeout"
            ? new Date(Date.now() + 120_000).toISOString()
            : null,
          updated_at: new Date().toISOString(),
        }).eq("id", job.id);
        return json(
          {
            ...publicDiscoveryResult({
              id: job.id,
              status: reason === "fetch_timeout" ? "failed" : "review_required",
              failure_category: reason,
              next_retry_at: reason === "fetch_timeout"
                ? new Date(Date.now() + 120_000).toISOString()
                : null,
            }),
          },
          reason === "invalid_url" || reason === "unapproved_domain"
            ? 400
            : 200,
        );
      }
    }
    if (action === "discover") {
      const evidence = safeEvidence(body.evidence);
      const product = evidence.product_signals?.[0] ?? "unknown";
      const dedupeKey = await sha256(
        `${evidence.issuer}:${
          normalizedProduct(product, evidence.issuer) || "unknown"
        }`,
      );
      const { data: job, error } = await db.from("card_discovery_jobs").upsert({
        user_id: user.id,
        issuer: evidence.issuer,
        proposed_product: product === "unknown" ? null : product,
        evidence,
        dedupe_key: dedupeKey,
        status: "queued",
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,dedupe_key", ignoreDuplicates: false })
        .select("id, status, resolved_card_id, next_retry_at")
        .single();
      if (error) throw error;
      EdgeRuntime.waitUntil(processDiscoveryJob(db, job.id));
      return json({
        job_id: job.id,
        status: job.status,
        resolved_card_id: job.resolved_card_id,
        retry_after: job.next_retry_at,
      }, 202);
    }
    if (action === "status") {
      const { data, error } = await db.from("card_discovery_jobs")
        .select("id, status, resolved_card_id, next_retry_at, failure_category")
        .eq("id", body.job_id).eq("user_id", user.id).single();
      if (error) throw error;
      return json(data);
    }
    if (action === "resume") {
      const { data, error } = await db.from("card_discovery_jobs")
        .select("id, status, resolved_card_id, next_retry_at, failure_category")
        .eq("user_id", user.id)
        .in("status", ["resolved", "review_required", "failed"])
        .order("updated_at", { ascending: false });
      if (error) throw error;
      return json({ jobs: data ?? [] });
    }
    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Request failed",
    }, 400);
  }
});
