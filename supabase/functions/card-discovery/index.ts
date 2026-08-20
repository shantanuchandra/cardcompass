import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.2";
import {
  allowedOfficialUrl,
  canonicalCardIdentity,
  discoveryObservationVersionKey,
  evaluateAutomaticCatalogGate,
  exactOfficialPageIdentity,
  normalizedProduct,
  officialCardIdentityFromHtml,
  officialDomainsForIssuer,
  publicDiscoveryResult,
  publicReasonCode,
  rankOfficialUrls,
  sanitizeDiscoveryEvidence,
  sanitizeEvidence,
  selectBoundCatalogResourceIdentity,
  selectSubmittedUrlIdentity,
  terminalDiscoveryStatus,
} from "../_shared/card_discovery.ts";
import {
  approvedStoredQueryParameters,
  createOfficialRobotsCache,
  fetchOfficialIssuerResource,
  type OfficialFetchResult,
  type OfficialRobotsCache,
  requireOfficialFetchBody,
} from "../_shared/official_issuer_fetch.ts";
import {
  canonicalPublicationResource,
  cardDiscontinuationEvidence,
  publicationFieldsFromFetch,
  publishReviewedCardIdentity,
  semanticProductEnvelopeHash,
  stageCatalogIdentityReview,
} from "../_shared/catalog_identity_publication.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
type UntypedSupabaseClient = any;
const DISCOVERY_FETCH_DEADLINE_MS = 25_000;
const DISCOVERY_MUTABLE_STATUSES = [
  "queued",
  "discovering",
  "failed",
  "review_required",
];

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
  return sanitizeDiscoveryEvidence({
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
  }) as SafeEvidence;
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

async function findCatalogCardsByUrlHash(
  db: UntypedSupabaseClient,
  hash: string,
): Promise<string[]> {
  if (!/^[0-9a-f]{64}$/.test(hash)) throw new Error("identity_conflict");
  const { data: keys, error: keyError } = await db.from("card_catalog_url_keys")
    .select("card_id")
    .eq("url_hash", hash);
  if (keyError) throw keyError;
  const { data, error } = await db.from("card_catalog_provenance")
    .select("card_id")
    .or(`submitted_url_hash.eq.${hash},final_url_hash.eq.${hash}`);
  if (error) throw error;
  return [
    ...new Set(
      [
        ...((keys ?? []) as Array<{ card_id?: string }>),
        ...((data ?? []) as Array<{ card_id?: string }>),
      ].map((row) => row.card_id).filter((id): id is string => Boolean(id)),
    ),
  ];
}

async function loadCatalogUrlIdentityCandidates(
  db: UntypedSupabaseClient,
  cardIds: string[],
): Promise<
  Array<{
    cardId: string;
    issuer: string;
    cardName: string;
    network: string | null;
    aliases: string[];
    cardType: string;
  }>
> {
  if (cardIds.length === 0) return [];
  const { data: cards, error: cardError } = await db.from("card_catalog")
    .select("id, bank, card_name, network, card_type")
    .in("id", cardIds);
  if (cardError) throw cardError;
  const { data: aliases, error: aliasError } = await db.from(
    "card_catalog_aliases",
  )
    .select("card_id, alias")
    .in("card_id", cardIds);
  if (aliasError) throw aliasError;
  return ((cards ?? []) as Array<{
    id: string;
    bank: string;
    card_name: string;
    network: string | null;
    card_type: string;
  }>).map(
    (card) => ({
      cardId: card.id,
      issuer: card.bank,
      cardName: card.card_name,
      network: card.network,
      cardType: card.card_type,
      aliases: ((aliases ?? []) as Array<{ card_id: string; alias: string }>)
        .filter((alias) => alias.card_id === card.id)
        .map((alias) => alias.alias),
    }),
  );
}

async function upsertDiscoveryJob(
  db: UntypedSupabaseClient,
  userId: string,
  evidence: SafeEvidence,
  submittedUrl?: string,
) {
  const product = evidence.product_signals?.[0] ?? "unknown";
  const submittedResource = submittedUrl
    ? await canonicalPublicationResource(evidence.issuer, submittedUrl)
    : null;
  const dedupeKey = await sha256(
    `${evidence.issuer}:${
      normalizedProduct(product, evidence.issuer) || "unknown"
    }:${submittedResource?.urlHash ?? "product-discovery"}`,
  );
  const { data: existing, error: existingError } = await db
    .from("card_discovery_jobs")
    .select("*")
    .eq("user_id", userId)
    .eq("dedupe_key", dedupeKey)
    .maybeSingle();
  if (existingError) throw existingError;
  if (existing && terminalDiscoveryStatus(existing.status)) return existing;
  if (existing) return existing;
  const payload = {
    user_id: userId,
    issuer: evidence.issuer,
    proposed_product: product === "unknown" ? null : product,
    evidence: submittedResource
      ? {
        ...evidence,
        submitted_url: submittedResource.canonicalUrl,
        submitted_url_hash: submittedResource.urlHash,
      }
      : evidence,
    dedupe_key: dedupeKey,
    updated_at: new Date().toISOString(),
  };
  const { data, error } = await db.from("card_discovery_jobs").insert(payload)
    .select("*")
    .maybeSingle();
  if (error && error.code !== "23505") throw error;
  if (!data) {
    const { data: raced, error: racedError } = await db
      .from("card_discovery_jobs").select("*")
      .eq("user_id", userId).eq("dedupe_key", dedupeKey).single();
    if (racedError || !raced) throw racedError ?? error;
    return raced;
  }
  return data;
}

async function submittedRequestAnchor(
  evidence: SafeEvidence,
  submittedUrl: string,
): Promise<{ key: string; canonicalUrl: string; urlHash: string }> {
  const product = evidence.product_signals?.[0] ?? "unknown";
  const resource = await canonicalPublicationResource(
    evidence.issuer,
    submittedUrl,
  );
  return {
    key: await sha256(
      `${evidence.issuer}:${
        normalizedProduct(product, evidence.issuer) || "unknown"
      }:${resource.urlHash}`,
    ),
    canonicalUrl: resource.canonicalUrl,
    urlHash: resource.urlHash,
  };
}

export async function findPriorSubmittedRequestJob(
  db: UntypedSupabaseClient,
  userId: string,
  anchorKey: string,
): Promise<Record<string, any> | null> {
  const terminal = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", userId)
    .contains("evidence", { request_anchor_key: anchorKey })
    .in("status", ["resolved", "rejected"])
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (terminal.error) throw terminal.error;
  if (terminal.data) return terminal.data;
  const latest = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", userId)
    .contains("evidence", { request_anchor_key: anchorKey })
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (latest.error) throw latest.error;
  if (latest.data) return latest.data;
  // Compatibility with pre-round-four stable anchors whose dedupe key was
  // later rewritten by versioning.
  const legacyTerminal = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", userId).eq("dedupe_key", anchorKey)
    .in("status", ["resolved", "rejected"]).maybeSingle();
  if (legacyTerminal.error) throw legacyTerminal.error;
  if (legacyTerminal.data) return legacyTerminal.data;
  const legacy = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", userId).eq("dedupe_key", anchorKey).maybeSingle();
  if (legacy.error) throw legacy.error;
  return legacy.data ?? null;
}

async function observeExistingCard(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  cardId: string,
  publicationEvidence: Record<string, unknown>,
  sourceKind: string,
) {
  if (job.review_item_id || job.status === "review_required") {
    throw new Error("existing_observation_requires_review");
  }
  const { data: card, error: cardError } = await db.from("card_catalog")
    .select("id, bank, card_name, network, card_type")
    .eq("id", cardId)
    .single();
  if (
    cardError || !card ||
    String(card.card_type ?? "").trim().toLowerCase() !== "credit" ||
    String(card.bank ?? "").trim().toLowerCase() !==
      String(job.issuer ?? "").trim().toLowerCase()
  ) throw cardError ?? new Error("identity_conflict");
  const published = await publishReviewedCardIdentity(db, {
    discoveryJobId: job.id,
    action: "observe_existing",
    reviewedFields: {
      card_id: card.id,
      issuer: card.bank,
      cardName: card.card_name,
      network: card.network,
      ...publicationEvidence,
      source_type: "official_html",
      source_observation: {
        kind: sourceKind.slice(0, 64),
        identity_validated: true,
        source_status: publicationEvidence.source_status ?? null,
      },
    },
    parserVersion: "benefits-v6",
  });
  if (
    published.cardId !== card.id || published.jobId !== job.id ||
    published.resultingStatus !== "resolved"
  ) throw new Error("invalid_catalog_publication_outcome");
  const { data, error } = await db.from("card_discovery_jobs")
    .select("*").eq("id", job.id).single();
  if (error || !data) throw error ?? new Error("discovery_job_not_found");
  return data;
}

async function resolveBoundIdentityOrReview(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  content: string,
  publicationEvidence: Record<string, unknown>,
  submittedHash: string,
  finalHash: string,
  sourceKind: string,
  legacyHashes: { submitted: string; final: string } | null = null,
): Promise<{ cardId: string | null; reviewed: boolean }> {
  const labeledHashes = [
    ["submitted", submittedHash],
    ["final", finalHash],
    ...(legacyHashes
      ? [["legacy_submitted", legacyHashes.submitted], [
        "legacy_final",
        legacyHashes.final,
      ]]
      : []),
  ] as Array<[string, string]>;
  const idsByHash = new Map<string, string[]>();
  await Promise.all([...new Set(labeledHashes.map(([, hash]) => hash))].map(
    async (hash) =>
      idsByHash.set(hash, await findCatalogCardsByUrlHash(db, hash)),
  ));
  try {
    const cardId = await selectBoundCatalogResourceIdentity({
      resourceIdentityHashes: labeledHashes.map(([, hash]) => hash),
      issuer: job.issuer,
      content,
      lookupCardIds: async (hash) => idsByHash.get(hash) ?? [],
      loadCandidates: (ids) => loadCatalogUrlIdentityCandidates(db, ids),
    });
    return { cardId, reviewed: false };
  } catch (error) {
    if (!(error instanceof Error) || error.message !== "identity_conflict") {
      throw error;
    }
    const boundIds = [...new Set([...idsByHash.values()].flat())];
    const candidates = await loadCatalogUrlIdentityCandidates(db, boundIds);
    const observed = officialCardIdentityFromHtml(content, job.issuer) ??
      canonicalCardIdentity(
        job.issuer,
        String(job.proposed_product ?? "Unknown"),
      );
    const boundResourceIdentities = Object.fromEntries(labeledHashes.map(
      ([label, hash]) => [label, { hash, card_ids: idsByHash.get(hash) ?? [] }],
    ));
    await putInReview(
      db,
      job,
      { ...observed, ...publicationEvidence },
      {
        ...publicationEvidence,
        source_observation: { kind: sourceKind, identity_validated: false },
        bound_resource_identities: boundResourceIdentities,
      },
      ["conflicting_url_identity"],
      Number(job.evidence?.confidence ?? 0),
      candidates,
    );
    return { cardId: null, reviewed: true };
  }
}

type SubmittedUrlObservation = {
  page: OfficialFetchResult & { text: string; contentHash: string };
  submittedHash: string;
  finalHash: string;
  legacySubmittedHash: string;
  legacyFinalHash: string;
  publicationEvidence: Record<string, unknown>;
};

async function fetchSubmittedUrlObservation(
  job: Record<string, any>,
  rawUrl: string,
  deadlineAt: number,
): Promise<SubmittedUrlObservation> {
  const robotsCache = createOfficialRobotsCache();
  const page = requireOfficialFetchBody(
    await fetchOfficialIssuerResource({
      issuer: job.issuer,
      url: rawUrl,
      enforceRobots: true,
      deadlineAt,
      allowedQueryParameters: approvedStoredQueryParameters(rawUrl),
      robotsCache,
    }),
  );
  const legacySubmittedHash = await sha256(page.submittedUrl);
  const submittedHash = page.sourceIdentityHash ?? legacySubmittedHash;
  const finalUrl = page.canonicalUrl;
  const legacyFinalHash = await sha256(finalUrl);
  const finalHash = page.finalResourceIdentityHash ?? legacyFinalHash;
  const publicationEvidence = {
    official_url: page.finalResourceUrl ?? page.finalUrl,
    ...publicationFieldsFromFetch({
      ...page,
      sourceIdentityHash: submittedHash,
      finalResourceIdentityHash: finalHash,
    }),
  };
  return {
    page,
    submittedHash,
    finalHash,
    legacySubmittedHash,
    legacyFinalHash,
    publicationEvidence,
  };
}

export async function versionSubmittedObservationJob(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  observation: SubmittedUrlObservation,
  requestAnchorKey: string,
  semanticProductHash: string,
): Promise<any> {
  const evidence = job.evidence as SafeEvidence;
  const versionKey = await discoveryObservationVersionKey({
    issuer: String(job.issuer ?? evidence.issuer),
    product: String(
      job.proposed_product ?? evidence.product_signals?.[0] ?? "unknown",
    ),
    submittedUrlHash: observation.submittedHash,
    finalUrlHash: observation.finalHash,
    contentHash: semanticProductHash,
    retrievedAt: observation.page.retrievedAt,
  });
  const existing = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", job.user_id).eq("dedupe_key", versionKey).maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) return existing.data;

  const now = new Date().toISOString();
  const versionEvidence = {
    ...evidence,
    ...observation.publicationEvidence,
    request_anchor_key: requestAnchorKey,
    semantic_product_hash: semanticProductHash,
    observation_version_key: versionKey,
  };
  const inserted = await db.from("card_discovery_jobs").insert({
    user_id: job.user_id,
    discovery_source: job.discovery_source ?? "statement",
    issuer: job.issuer,
    proposed_product: job.proposed_product,
    evidence: versionEvidence,
    dedupe_key: versionKey,
    status: "queued",
    updated_at: now,
  }).select("*").maybeSingle();
  if (inserted.error && inserted.error.code !== "23505") throw inserted.error;
  if (inserted.data) return inserted.data;
  const raced = await db.from("card_discovery_jobs").select("*")
    .eq("user_id", job.user_id).eq("dedupe_key", versionKey).single();
  if (raced.error || !raced.data) throw raced.error ?? inserted.error;
  return raced.data;
}

async function claimSubmittedObservationJob(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
): Promise<{ job: Record<string, any>; claimed: boolean }> {
  if (terminalDiscoveryStatus(job.status)) return { job, claimed: false };
  const now = new Date().toISOString();
  let update = db.from("card_discovery_jobs").update({
    status: "discovering",
    attempt_count: Number(job.attempt_count ?? 0) + 1,
    updated_at: now,
  }).eq("id", job.id).eq("user_id", job.user_id)
    .in("status", ["queued", "failed", "review_required"]);
  update = job.updated_at ? update.eq("updated_at", job.updated_at) : update;
  const claimed = await update.select("*").maybeSingle();
  if (claimed.error) throw claimed.error;
  if (claimed.data) return { job: claimed.data, claimed: true };
  const current = await db.from("card_discovery_jobs").select("*")
    .eq("id", job.id).eq("user_id", job.user_id).single();
  if (current.error || !current.data) throw current.error;
  return { job: current.data, claimed: false };
}

async function processSubmittedUrlObservation(
  db: UntypedSupabaseClient,
  job: Record<string, any>,
  observation: SubmittedUrlObservation,
) {
  const evidence = job.evidence as SafeEvidence;
  const {
    page,
    submittedHash,
    finalHash,
    legacySubmittedHash,
    legacyFinalHash,
    publicationEvidence,
  } = observation;
  const finalUrl = page.canonicalUrl;
  const opaqueBinding = await resolveBoundIdentityOrReview(
    db,
    job,
    page.text,
    publicationEvidence,
    submittedHash,
    finalHash,
    "bound_resource_identity_conflict",
    { submitted: legacySubmittedHash, final: legacyFinalHash },
  );
  if (opaqueBinding.reviewed) {
    return (await db.from("card_discovery_jobs").select("*").eq("id", job.id)
      .single()).data;
  }
  if (opaqueBinding.cardId) {
    return observeExistingCard(
      db,
      job,
      opaqueBinding.cardId,
      publicationEvidence,
      "bound_official_card_observation",
    );
  }
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
      { ...canonical, ...publicationEvidence },
      {
        evidence,
        ...publicationEvidence,
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
      { ...officialIdentity, ...publicationEvidence },
      {
        evidence,
        ...publicationEvidence,
        excerpt: sanitizeEvidence(pageText),
      },
      gate.reasons,
      evidence.confidence ?? 0,
    );
    return (await db.from("card_discovery_jobs").select("*").eq("id", job.id)
      .single()).data;
  }

  await putInReview(
    db,
    job,
    {
      ...officialIdentity,
      network: officialIdentity.network ?? canonical.network ??
        evidence.network ?? null,
      aliases: [...canonical.aliases, ...(evidence.product_signals ?? [])],
      ...publicationEvidence,
      source_type: "official_html",
      source_observation: {
        status: page.status,
        kind: "submitted_statement_url",
      },
    },
    {
      evidence,
      ...publicationEvidence,
      excerpt: sanitizeEvidence(pageText),
    },
    ["authenticated_source_requires_admin_review"],
    evidence.confidence ?? 0,
  );
  return (await db.from("card_discovery_jobs").select("*").eq("id", job.id)
    .single()).data;
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
  deadlineAt: number,
  robotsCache: OfficialRobotsCache,
): Promise<string | null> {
  const normalized = normalizedProduct(product, issuer);
  const known = knownOfficialSources[issuer]?.[normalized];
  if (known) return known;

  const urls: string[] = [];
  for (const domain of officialDomainsForIssuer(issuer)) {
    for (const sitemapPath of ["/sitemap.xml", "/sitemap_index.xml"]) {
      try {
        const response = requireOfficialFetchBody(
          await fetchOfficialIssuerResource({
            issuer,
            url: `https://${domain}${sitemapPath}`,
            contentPurpose: "sitemap",
            enforceRobots: true,
            deadlineAt,
            allowedQueryParameters: approvedStoredQueryParameters(
              `https://${domain}${sitemapPath}`,
            ),
            robotsCache,
          }),
        );
        urls.push(
          ...Array.from(
            response.text.matchAll(/<loc>\s*([^<]+)\s*<\/loc>/gi),
            (m) =>
              m[1]
                .replace(/&amp;/gi, "&")
                .replace(/&#38;/gi, "&")
                .replace(/&quot;|&#34;/gi, '"')
                .trim(),
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
) {
  const reviewIssuer = typeof job.issuer === "string" ? job.issuer : "";
  if (!reviewIssuer) throw new Error("issuer_mismatch");
  const rawProposedFields = proposedFields;
  const rawSourceEvidence = sourceEvidence;
  proposedFields = sanitizeDiscoveryEvidence(proposedFields) as Record<
    string,
    unknown
  >;
  sourceEvidence = sanitizeDiscoveryEvidence(sourceEvidence) as Record<
    string,
    unknown
  >;
  const restoreResourceIdentity = async (
    raw: Record<string, unknown>,
    sanitized: Record<string, unknown>,
  ) => {
    for (const prefix of ["submitted", "final"] as const) {
      const rawUrl = raw[`${prefix}_url`];
      if (typeof rawUrl !== "string") continue;
      const resource = await canonicalPublicationResource(reviewIssuer, rawUrl);
      const rawHash = raw[`${prefix}_url_hash`] ??
        raw[`${prefix}_resource_identity_hash`];
      if (
        typeof rawHash !== "string" ||
        rawHash.toLowerCase() !== resource.urlHash
      ) throw new Error("identity_conflict");
      sanitized[`${prefix}_url`] = resource.canonicalUrl;
      sanitized[`${prefix}_url_hash`] = resource.urlHash;
    }
    if (
      typeof raw.content_hash === "string" &&
      /^[0-9a-f]{64}$/i.test(raw.content_hash)
    ) sanitized.content_hash = raw.content_hash.toLowerCase();
    if (
      typeof raw.retrieved_at === "string" &&
      /^\d{4}-\d{2}-\d{2}T/.test(raw.retrieved_at)
    ) sanitized.retrieved_at = raw.retrieved_at.slice(0, 40);
    if (
      Number.isInteger(raw.source_status) && Number(raw.source_status) >= 100 &&
      Number(raw.source_status) <= 599
    ) sanitized.source_status = raw.source_status;
  };
  await restoreResourceIdentity(rawProposedFields, proposedFields);
  await restoreResourceIdentity(rawSourceEvidence, sourceEvidence);
  existingCandidates = sanitizeDiscoveryEvidence(
    existingCandidates,
  ) as unknown[];
  const semanticHash = await semanticProductEnvelopeHash({
    issuer: proposedFields.issuer ?? proposedFields.bank ?? reviewIssuer,
    cardName: proposedFields.cardName ?? proposedFields.card_name ??
      job.proposed_product ?? null,
    network: proposedFields.network ?? null,
    annual_fee: proposedFields.annual_fee ?? null,
    joining_fee: proposedFields.joining_fee ?? null,
    apr: proposedFields.apr ?? null,
    suggested_action: proposedFields.suggested_action ?? null,
    source_observation: proposedFields.source_observation ??
      sourceEvidence.source_observation ?? null,
    warnings,
  });
  const staged = await stageCatalogIdentityReview(db, {
    discoveryJobId: String(job.id),
    discoverySource: job.discovery_source === "issuer_crawl"
      ? "issuer_crawl"
      : "statement",
    userId: typeof job.user_id === "string" ? job.user_id : null,
    issuer: reviewIssuer,
    proposedProduct: typeof job.proposed_product === "string"
      ? job.proposed_product
      : null,
    dedupeKey: String(job.dedupe_key),
    semanticHash,
    proposedFields,
    sourceEvidence: { ...sourceEvidence, semantic_product_hash: semanticHash },
    existingCandidates: existingCandidates as Array<Record<string, unknown>>,
    validationWarnings: warnings.slice(0, 32),
    confidence: Math.max(0, Math.min(1, confidence)),
    expectedJobStatus: typeof job.status === "string" ? job.status : null,
    expectedJobUpdatedAt: typeof job.updated_at === "string"
      ? job.updated_at
      : null,
  });
  if (
    staged.jobId !== String(job.id) ||
    !["review_required", "resolved", "rejected"].includes(
      staged.resultingStatus,
    )
  ) throw new Error("invalid_catalog_review_stage_outcome");
}

async function processDiscoveryJob(
  db: UntypedSupabaseClient,
  jobId: string,
  deadlineAt = Date.now() + DISCOVERY_FETCH_DEADLINE_MS,
) {
  const { data: rawJob, error } = await db.from("card_discovery_jobs")
    .select("*").eq("id", jobId).single();
  if (error || !rawJob) return;
  let job = rawJob as Record<string, any>;
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

  const claimed = await db.from("card_discovery_jobs").update({
    status: "discovering",
    attempt_count: Number(job.attempt_count ?? 0) + 1,
    updated_at: new Date().toISOString(),
  }).eq("id", jobId).in("status", ["queued", "failed"])
    .eq("updated_at", job.updated_at).select("*").maybeSingle();
  if (claimed.error || !claimed.data) return;
  job = claimed.data;

  try {
    const canonical = canonicalCardIdentity(job.issuer, product);
    const robotsCache = createOfficialRobotsCache();
    const officialUrl = await discoverOfficialUrl(
      job.issuer,
      canonical.cardName,
      deadlineAt,
      robotsCache,
    );
    if (!officialUrl) {
      await putInReview(db, job, canonical, { evidence }, [
        "official_source_not_found",
      ], evidence.confidence ?? 0);
      return;
    }
    const page = requireOfficialFetchBody(
      await fetchOfficialIssuerResource({
        issuer: job.issuer,
        url: officialUrl,
        enforceRobots: true,
        deadlineAt,
        allowedQueryParameters: approvedStoredQueryParameters(officialUrl),
        robotsCache,
      }),
    );
    const submittedHash = page.sourceIdentityHash ??
      await sha256(page.submittedUrl);
    const finalHash = page.finalResourceIdentityHash ??
      await sha256(page.canonicalUrl);
    const publicationEvidence = {
      official_url: page.finalResourceUrl ?? page.finalUrl,
      ...publicationFieldsFromFetch({
        ...page,
        sourceIdentityHash: submittedHash,
        finalResourceIdentityHash: finalHash,
      }),
    };
    if (page.contentType === "application/pdf") {
      await putInReview(
        db,
        job,
        canonical,
        {
          evidence,
          ...publicationEvidence,
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
        { ...canonical, ...publicationEvidence },
        {
          evidence,
          ...publicationEvidence,
        },
        ["official_product_not_found"],
        evidence.confidence ?? 0,
      );
      return;
    }
    const officialProduct = officialIdentity.cardName;
    const bound = await resolveBoundIdentityOrReview(
      db,
      job,
      page.text,
      publicationEvidence,
      submittedHash,
      finalHash,
      "discovered_bound_resource_identity_conflict",
    );
    if (bound.reviewed) return;
    if (bound.cardId) {
      await observeExistingCard(
        db,
        job,
        bound.cardId,
        publicationEvidence,
        "discovered_bound_official_card_observation",
      );
      return;
    }

    const { data: catalogRows, error: catalogError } = await db
      .from("card_catalog")
      .select("id, bank, card_name, network, card_type")
      .ilike("bank", job.issuer)
      .ilike("card_type", "credit")
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
        { ...officialIdentity, ...publicationEvidence },
        {
          evidence,
          ...publicationEvidence,
          excerpt: sanitizeEvidence(pageText),
        },
        gate.reasons,
        evidence.confidence ?? 0,
        existing,
      );
      return;
    }

    await putInReview(
      db,
      job,
      {
        ...officialIdentity,
        network: officialIdentity.network ?? canonical.network ??
          evidence.network ?? null,
        aliases: [
          ...officialIdentity.aliases,
          ...canonical.aliases,
          ...(evidence.product_signals ?? []),
        ],
        ...publicationEvidence,
        source_type: "official_html",
        source_observation: {
          status: page.status,
          kind: "statement_discovery",
        },
      },
      {
        evidence,
        ...publicationEvidence,
        excerpt: sanitizeEvidence(pageText),
      },
      ["authenticated_source_requires_admin_review"],
      evidence.confidence ?? 0,
      existing,
    );
  } catch (error) {
    const attempt = Number(job.attempt_count ?? 1);
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
    const failed = await db.from("card_discovery_jobs").update({
      status: "failed",
      failure_category: failure,
      next_retry_at: new Date(Date.now() + Math.min(60, 2 ** attempt) * 60_000)
        .toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", jobId).eq("status", "discovering")
      .eq("updated_at", job.updated_at).select("id").maybeSingle();
    if (failed.error) throw failed.error;
  }
}

export const handleRequest = async (request: Request): Promise<Response> => {
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
    const invocationDeadlineAt = Date.now() + DISCOVERY_FETCH_DEADLINE_MS;
    const body = await request.json();
    const action = body.action;
    if (action === "resolve_url") {
      const evidence = safeEvidence(body.evidence);
      if (
        typeof body.source_url !== "string" || body.source_url.length > 2048
      ) {
        return json({ error: "invalid_url", reason_code: "invalid_url" }, 400);
      }
      const anchor = await submittedRequestAnchor(evidence, body.source_url);
      const priorJob = await findPriorSubmittedRequestJob(
        db,
        user.id,
        anchor.key,
      );
      const fetchContext = {
        id: "unpersisted-request-anchor",
        user_id: user.id,
        discovery_source: "statement",
        issuer: evidence.issuer,
        proposed_product: evidence.product_signals?.[0] ?? null,
        evidence: {
          ...evidence,
          request_anchor_key: anchor.key,
          submitted_url: anchor.canonicalUrl,
          submitted_url_hash: anchor.urlHash,
        },
      };
      let job: Record<string, any> = priorJob ?? fetchContext;
      try {
        const observation = await fetchSubmittedUrlObservation(
          fetchContext,
          body.source_url,
          invocationDeadlineAt,
        );
        const observedIdentity = observation.page.contentType ===
            "application/pdf"
          ? null
          : officialCardIdentityFromHtml(
            observation.page.text,
            evidence.issuer,
          );
        const lifecycleEvidence = observedIdentity
          ? cardDiscontinuationEvidence(
            observation.page.text,
            evidence.issuer,
            observedIdentity.cardName,
          )
          : { explicit: false, matchedExcerpt: null };
        const semanticProductHash = await semanticProductEnvelopeHash({
          issuer: evidence.issuer,
          cardName: observedIdentity?.cardName ??
            evidence.product_signals?.[0] ?? null,
          network: observedIdentity?.network ?? evidence.network ?? null,
          content_type: observation.page.contentType,
          source_status: observation.page.status,
          explicit_discontinuation: lifecycleEvidence.explicit,
          matched_discontinuation_excerpt: lifecycleEvidence.matchedExcerpt,
        });
        job = await versionSubmittedObservationJob(
          db,
          fetchContext,
          observation,
          anchor.key,
          semanticProductHash,
        );
        const claim = await claimSubmittedObservationJob(db, job);
        job = claim.job;
        if (!claim.claimed || terminalDiscoveryStatus(job.status)) {
          return json(publicDiscoveryResult(job as any));
        }
        const result = await processSubmittedUrlObservation(
          db,
          job,
          observation,
        );
        return json(publicDiscoveryResult(result));
      } catch (error) {
        if (priorJob && terminalDiscoveryStatus(priorJob.status)) {
          return json(publicDiscoveryResult(priorJob as any));
        }
        const reason = publicReasonCode(error);
        const retryAt = reason === "fetch_timeout"
          ? new Date(Date.now() + 120_000).toISOString()
          : null;
        if (job.id === "unpersisted-request-anchor") {
          job = await upsertDiscoveryJob(
            db,
            user.id,
            evidence,
            body.source_url,
          );
        }
        const failed = await db.from("card_discovery_jobs").update({
          status: reason === "fetch_timeout" ? "failed" : "review_required",
          failure_category: reason,
          next_retry_at: retryAt,
          updated_at: new Date().toISOString(),
        }).eq("id", job.id).eq("user_id", user.id)
          .in("status", DISCOVERY_MUTABLE_STATUSES)
          .eq("updated_at", job.updated_at)
          .select("*").maybeSingle();
        if (failed.error) throw failed.error;
        const responseJob = failed.data ??
          (await db.from("card_discovery_jobs").select("*")
            .eq("id", job.id).eq("user_id", user.id).single()).data ??
          job;
        if (terminalDiscoveryStatus(responseJob.status)) {
          return json(publicDiscoveryResult(responseJob));
        }
        return json(
          {
            ...publicDiscoveryResult({
              id: responseJob.id,
              status: reason === "fetch_timeout" ? "failed" : "review_required",
              failure_category: reason,
              next_retry_at: retryAt,
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
      const job = await upsertDiscoveryJob(db, user.id, evidence);
      if (!terminalDiscoveryStatus(job.status)) {
        EdgeRuntime.waitUntil(
          processDiscoveryJob(db, job.id, invocationDeadlineAt),
        );
      }
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
};

if (import.meta.main) {
  serve(handleRequest);
}
