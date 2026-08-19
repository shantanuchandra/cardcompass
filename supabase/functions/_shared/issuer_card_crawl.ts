import {
  canonicalCardIdentity,
  canonicalOfficialUrl,
  normalizedProduct,
  officialCardIdentityFromHtml,
} from "./card_discovery.ts";
import {
  fetchOfficialIssuerResource as fetchOfficialIssuerResourceDefault,
  type OfficialFetchInput,
  type OfficialFetchResult,
} from "./official_issuer_fetch.ts";

export const MAX_SITEMAP_URLS = 200;
export const MAX_CANDIDATE_FETCHES = 40;
export const MAX_SITEMAP_DEPTH = 2;
export const DEFAULT_CRAWL_DELAY_MS = 250;

export type PageClassification = {
  kind: "card_product" | "supporting_document" | "not_a_card" | "ambiguous";
  canonicalUrl: string;
  proposedName?: string;
  aliases: string[];
  network?: string;
  confidence: number;
  warnings: string[];
  sanitizedEvidence: string[];
};

export type IssuerCrawlResult = {
  candidates: PageClassification[];
  quarantined: PageClassification[];
  consideredCount: number;
  fetchedCount: number;
};

export type PersistCrawlerCandidateResult = {
  outcome: "existing" | "review" | "duplicate";
  catalogCardId?: string;
  reviewId?: string;
};

type UntypedSupabaseClient = any;

type OfficialFetcher = (
  input: OfficialFetchInput,
) => Promise<OfficialFetchResult>;

export type DiscoverIssuerCardCandidatesInput = {
  issuer: string;
  sitemapUrl?: string;
  sitemapUrls?: string[];
  indexUrls?: string[];
  fetchOfficialIssuerResource?: OfficialFetcher;
  delay?: (milliseconds: number) => Promise<void> | void;
  delayMs?: number;
  deadlineAt?: number;
  now?: () => number;
};

export function issuerDiscoveryFallbackUrls(originUrl: string): {
  sitemapUrls: string[];
  indexUrls: string[];
} {
  const origin = new URL(originUrl).origin;
  return {
    sitemapUrls: [
      "/sitemap.xml",
      "/sitemap_index.xml",
      "/sitemap-index.xml",
      "/sitemaps/sitemap.xml",
    ].map((path) => new URL(path, origin).toString()),
    indexUrls: [
      "/cards/credit-card",
      "/cards/credit-cards",
      "/personal/cards/credit-cards",
    ].map((path) => new URL(path, origin).toString()),
  };
}

export type ClassifyIssuerPageInput = {
  issuer: string;
  url: string;
  canonicalUrl?: string;
  html?: string;
  text?: string;
};

type SitemapDocument = {
  isIndex: boolean;
  locations: string[];
};

const unsafePagePattern =
  /(?:^|[/?=&_.-])(?:login|log-in|apply|application|track|tracking|blog|stories?|story|protection|insurance|generic|help|support|learning-centre)(?:$|[/?=&_.-])/i;
const nonProductUrlPattern = /calculator/i;
const supportingPattern =
  /(?:benefits?|fees?|charges?|rewards?|terms?|conditions?|mitc)(?:$|[/?=&_.-])/i;
const productPattern =
  /(?:credit[-_ ]?cards?|cards?[-_ ]?credit|card[-_ ]?products?|product[-_ ]?cards?)(?:$|[/?=&_.-])/i;
const evidencePattern = /<(?:title|h1|h2)[^>]*>([\s\S]*?)<\/(?:title|h1|h2)>/gi;
const linkPattern = /<loc\b[^>]*>([\s\S]*?)<\/loc>/gi;
const htmlLinkPattern =
  /<a\b[^>]*\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>/gi;
const nonProductPathTokens = new Set([
  "card",
  "cards",
  "credit",
  "products",
  "product",
  "personal",
  "bank",
  "benefit",
  "benefits",
  "fee",
  "fees",
  "charge",
  "charges",
  "reward",
  "rewards",
  "term",
  "terms",
  "condition",
  "conditions",
  "mitc",
  "html",
  "pdf",
  "all",
  "overview",
  "compare",
  "comparison",
  "option",
  "options",
  "explore",
  "our",
  "range",
  "legal",
  "navigation",
  "home",
  "landing",
  "page",
  "and",
  "or",
  "the",
  "for",
  "of",
  "to",
  "in",
  "with",
  "your",
]);

function decodeXml(value: string): string {
  return value
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .trim();
}

function textOnly(value: string): string {
  return decodeXml(value)
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function redactLongDigits(value: string): string {
  return value.replace(/\d{4,}/g, "[redacted]");
}

function sanitizeEvidence(value: string): string {
  return redactLongDigits(textOnly(value)).slice(0, 300);
}

function evidenceFromHtml(html: string): string[] {
  const evidence: string[] = [];
  for (const match of html.matchAll(evidencePattern)) {
    const sanitized = sanitizeEvidence(match[1] ?? "");
    if (sanitized && !evidence.includes(sanitized)) evidence.push(sanitized);
    if (evidence.length === 3) break;
  }
  return evidence;
}

function canonicalForIssuer(issuer: string, url: string): string | null {
  try {
    return canonicalOfficialUrl(issuer, url);
  } catch {
    return null;
  }
}

function pageEvidence(url: string, html: string): string {
  return `${url}\n${evidenceFromHtml(html).join(" ")}`;
}

function hostnameOf(url: string): string | null {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function isAnchoredToHost(url: string, hostname: string): boolean {
  return hostnameOf(url) === hostname;
}

function tokens(value: string): string[] {
  return value
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function meaningfulTokens(value: string, issuer: string): Set<string> {
  const issuerTokens = new Set(tokens(issuer));
  return new Set(
    tokens(value).filter((token) =>
      !nonProductPathTokens.has(token) && !issuerTokens.has(token)
    ),
  );
}

function urlPathTokens(url: string, issuer: string): Set<string> {
  try {
    const pathname = decodeURIComponent(new URL(url).pathname);
    return meaningfulTokens(pathname, issuer);
  } catch {
    return new Set();
  }
}

function hasProductSpecificUrlContext(url: string): boolean {
  return urlPathTokens(url, "").size > 0;
}

function hasSharedProductIdentityContext(
  identity: { cardName: string; aliases: string[] } | null,
  url: string,
  issuer: string,
): boolean {
  if (!identity) return false;
  const identityTokens = meaningfulTokens(
    [identity.cardName, ...identity.aliases].join(" "),
    issuer,
  );
  const contextTokens = urlPathTokens(url, issuer);
  return [...identityTokens].some((token) => contextTokens.has(token));
}

function candidateUrlScore(url: string): number {
  if (unsafePagePattern.test(url)) return -1;
  if (!hasProductSpecificUrlContext(url)) return 0;
  if (productPattern.test(url)) return 2;
  if (supportingPattern.test(url)) return 1;
  return 0;
}

function isSitemapUrl(url: string): boolean {
  try {
    const pathname = new URL(url).pathname.toLowerCase();
    return /(?:^|[-_/])sitemap(?:[-_.]|$)|\.xml(?:\.gz)?$/.test(pathname);
  } catch {
    return false;
  }
}

function parseSitemap(xml: string): SitemapDocument {
  const isIndex = /<\s*sitemapindex(?:\s|>)/i.test(xml);
  const locations: string[] = [];
  for (const match of xml.matchAll(linkPattern)) {
    const location = decodeXml(match[1] ?? "");
    if (location) locations.push(location);
  }
  return { isIndex, locations };
}

function emptyClassification(url: string, warning: string): PageClassification {
  return sanitizeClassification({
    kind: "ambiguous",
    canonicalUrl: url,
    aliases: [],
    confidence: 0,
    warnings: [warning],
    sanitizedEvidence: [],
  });
}

function sanitizeClassification(page: PageClassification): PageClassification {
  return {
    ...page,
    canonicalUrl: redactLongDigits(page.canonicalUrl),
    proposedName: page.proposedName
      ? redactLongDigits(page.proposedName)
      : undefined,
    aliases: page.aliases.map(redactLongDigits),
    network: page.network ? redactLongDigits(page.network) : undefined,
    warnings: page.warnings.map(redactLongDigits),
    sanitizedEvidence: page.sanitizedEvidence.map(sanitizeEvidence),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function uniqueStrings(values: string[], maxLength = 180): string[] {
  const result: string[] = [];
  for (const value of values) {
    const safe = redactLongDigits(value).trim().slice(0, maxLength);
    if (safe.length >= 2 && !result.includes(safe)) result.push(safe);
  }
  return result;
}

async function findCatalogCardByUrlHash(
  supabase: UntypedSupabaseClient,
  urlHash: string,
): Promise<string | null> {
  const { data: urlKey, error: urlKeyError } = await supabase
    .from("card_catalog_url_keys")
    .select("card_id")
    .eq("url_hash", urlHash)
    .maybeSingle();
  if (urlKeyError) throw urlKeyError;
  if (urlKey?.card_id) return urlKey.card_id;

  const { data: provenance, error: provenanceError } = await supabase
    .from("card_catalog_provenance")
    .select("card_id")
    .or(`submitted_url_hash.eq.${urlHash},final_url_hash.eq.${urlHash}`)
    .maybeSingle();
  if (provenanceError) throw provenanceError;
  return provenance?.card_id ?? null;
}

async function findCrawlerCatalogCandidates(
  supabase: UntypedSupabaseClient,
  issuer: string,
  normalizedNames: string[],
): Promise<Array<Record<string, unknown>>> {
  const { data: catalogRows, error: catalogError } = await supabase
    .from("card_catalog")
    .select("id, bank, card_name, network")
    .ilike("bank", issuer)
    .eq("is_discontinued", false);
  if (catalogError) throw catalogError;
  const catalog = ((catalogRows ?? []) as Array<Record<string, unknown>>)
    .filter((row) =>
      String(row.bank ?? "").trim().toLowerCase() ===
        issuer.trim().toLowerCase()
    );
  const byId = new Map(
    catalog.map((row: Record<string, unknown>) => [String(row.id), row]),
  );
  const matches = new Map<string, Record<string, unknown>>();
  for (const row of catalog) {
    if (
      normalizedNames.includes(
        normalizedProduct(String(row.card_name ?? ""), issuer),
      )
    ) {
      matches.set(String(row.id), row);
    }
  }

  if (normalizedNames.length > 0) {
    const { data: aliasRows, error: aliasError } = await supabase
      .from("card_catalog_aliases")
      .select("card_id, normalized_alias")
      .in("normalized_alias", normalizedNames);
    if (aliasError) throw aliasError;
    for (const alias of aliasRows ?? []) {
      const card = byId.get(String(alias.card_id));
      if (card) matches.set(String(alias.card_id), card);
    }
  }

  return [...matches.values()].map((row) => ({
    id: row.id,
    bank: row.bank,
    card_name: row.card_name,
    network: row.network ?? null,
  }));
}

/**
 * Persists a crawler result as review-only work. Crawler evidence is never an
 * independent statement signal, so this function intentionally never calls
 * the catalog resolver or writes catalog identity/provenance rows.
 */
export async function persistCrawlerCandidate(
  supabase: UntypedSupabaseClient,
  issuer: string,
  candidate: PageClassification,
): Promise<PersistCrawlerCandidateResult> {
  if (candidate.kind !== "card_product" || !candidate.proposedName?.trim()) {
    throw new Error("invalid_crawler_candidate");
  }
  const canonicalUrl = canonicalOfficialUrl(issuer, candidate.canonicalUrl);
  const urlHash = await sha256(canonicalUrl);
  const knownCardId = await findCatalogCardByUrlHash(supabase, urlHash);
  if (knownCardId) return { outcome: "existing", catalogCardId: knownCardId };

  const canonical = canonicalCardIdentity(issuer, candidate.proposedName);
  if (normalizedProduct(canonical.cardName, issuer).length < 2) {
    throw new Error("invalid_crawler_candidate");
  }
  const aliases = uniqueStrings([...canonical.aliases, ...candidate.aliases]);
  const normalizedNames = [
    ...new Set([canonical.cardName, ...aliases]
      .map((value) => normalizedProduct(value, issuer))),
  ]
    .filter((value) => value.length >= 2);
  const candidates = await findCrawlerCatalogCandidates(
    supabase,
    issuer,
    normalizedNames,
  );
  if (candidates.length === 1) {
    return { outcome: "existing", catalogCardId: String(candidates[0].id) };
  }
  const warnings = uniqueStrings([
    ...candidate.warnings,
    "crawler_discovered_without_statement_signal",
    ...(candidates.length > 1 ? ["ambiguous_catalog_identity"] : []),
  ]);
  const safeEvidence = uniqueStrings(candidate.sanitizedEvidence, 300).slice(
    0,
    3,
  );
  const dedupeKey = await sha256(`${issuer.trim().toLowerCase()}:${urlHash}`);

  const { data: existingJob, error: existingJobError } = await supabase
    .from("card_discovery_jobs")
    .select("id, review_item_id, status")
    .eq("discovery_source", "issuer_crawl")
    .eq("dedupe_key", dedupeKey)
    .is("user_id", null)
    .maybeSingle();
  if (existingJobError) throw existingJobError;
  if (existingJob && ["resolved", "rejected"].includes(existingJob.status)) {
    return {
      outcome: "duplicate",
      ...(existingJob.review_item_id
        ? { reviewId: existingJob.review_item_id }
        : {}),
    };
  }

  const proposal = {
    issuer,
    cardName: canonical.cardName,
    network: canonical.network ?? candidate.network ?? null,
    aliases,
    official_url: canonicalUrl,
  };
  const evidence = {
    issuer,
    official_url: canonicalUrl,
    url_hash: urlHash,
    product_signals: aliases,
    crawler_evidence: safeEvidence,
    warnings,
    confidence: Math.max(0, Math.min(1, candidate.confidence)),
    crawler_proposal: proposal,
    crawler_source_evidence: {
      official_url: canonicalUrl,
      url_hash: urlHash,
      excerpts: safeEvidence,
    },
    crawler_existing_candidates: candidates,
  };
  let job = existingJob;
  let duplicate = Boolean(existingJob);
  if (!job) {
    const { data, error } = await supabase.from("card_discovery_jobs")
      .insert({
        user_id: null,
        discovery_source: "issuer_crawl",
        issuer,
        proposed_product: canonical.cardName,
        evidence,
        dedupe_key: dedupeKey,
        status: "queued",
        updated_at: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (!error) {
      job = data;
    } else {
      const { data: racedJob, error: racedJobError } = await supabase
        .from("card_discovery_jobs")
        .select("id, review_item_id")
        .eq("discovery_source", "issuer_crawl")
        .eq("dedupe_key", dedupeKey)
        .is("user_id", null)
        .maybeSingle();
      if (racedJobError || !racedJob) throw error;
      job = racedJob;
      duplicate = true;
    }
  }

  const { data: existingReview, error: existingReviewError } = await supabase
    .from("card_catalog_review_queue")
    .select("id, status")
    .eq("discovery_job_id", job.id)
    .maybeSingle();
  if (existingReviewError) throw existingReviewError;
  if (
    existingReview &&
    ["approved", "merged", "rejected"].includes(existingReview.status)
  ) {
    return { outcome: "duplicate", reviewId: existingReview.id };
  }

  let review = existingReview;
  if (!review) {
    const { data, error } = await supabase.from("card_catalog_review_queue")
      .insert({
        discovery_job_id: job.id,
        proposed_fields: proposal,
        source_evidence: evidence.crawler_source_evidence,
        existing_candidates: candidates,
        validation_warnings: warnings,
        confidence: evidence.confidence,
        status: "pending",
        updated_at: new Date().toISOString(),
      })
      .select("id, status")
      .single();
    if (!error) {
      review = data;
    } else {
      const { data: racedReview, error: racedReviewError } = await supabase
        .from("card_catalog_review_queue")
        .select("id, status")
        .eq("discovery_job_id", job.id)
        .maybeSingle();
      if (racedReviewError || !racedReview) throw error;
      if (["approved", "merged", "rejected"].includes(racedReview.status)) {
        return { outcome: "duplicate", reviewId: racedReview.id };
      }
      review = racedReview;
      duplicate = true;
    }
  }

  const { error: updateError } = await supabase.from("card_discovery_jobs")
    .update({
      status: "review_required",
      review_item_id: review.id,
      failure_category: null,
      next_retry_at: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", job.id)
    .in("status", ["queued", "discovering", "failed", "review_required"]);
  if (updateError) throw updateError;
  return { outcome: duplicate ? "duplicate" : "review", reviewId: review.id };
}

/**
 * Classifies only URL and short, redacted heading/title evidence. The supplied
 * page body is deliberately not returned or stored in the classification.
 */
export function classifyIssuerPage(
  input: ClassifyIssuerPageInput,
): PageClassification {
  const canonicalUrl = input.canonicalUrl ??
    canonicalForIssuer(input.issuer, input.url) ?? input.url;
  const html = input.html ?? input.text ?? "";
  const evidence = pageEvidence(canonicalUrl, html);
  const sanitizedEvidence = evidenceFromHtml(html);
  const identity = officialCardIdentityFromHtml(html, input.issuer);
  const hasIdentityContext = hasSharedProductIdentityContext(
    identity,
    canonicalUrl,
    input.issuer,
  );
  const warnings: string[] = [];

  if (
    nonProductUrlPattern.test(canonicalUrl) || unsafePagePattern.test(evidence)
  ) {
    return sanitizeClassification({
      kind: "not_a_card",
      canonicalUrl,
      aliases: [],
      confidence: 0.99,
      warnings: ["quarantined_page_pattern"],
      sanitizedEvidence,
    });
  }

  // A product heading commonly appears on its benefit/fee/terms pages. The
  // canonical path is the durable signal that makes those supporting pages
  // distinct from the product itself.
  if (hasIdentityContext && supportingPattern.test(canonicalUrl)) {
    return sanitizeClassification({
      kind: "supporting_document",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.86 : 0.72,
      warnings,
      sanitizedEvidence,
    });
  }

  if (hasIdentityContext && productPattern.test(evidence)) {
    return sanitizeClassification({
      kind: "card_product",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.95 : 0.82,
      warnings,
      sanitizedEvidence,
    });
  }

  if (hasIdentityContext && supportingPattern.test(evidence)) {
    return sanitizeClassification({
      kind: "supporting_document",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.86 : 0.72,
      warnings,
      sanitizedEvidence,
    });
  }

  warnings.push("insufficient_card_signals");
  return sanitizeClassification({
    kind: "ambiguous",
    canonicalUrl,
    aliases: [],
    confidence: 0.2,
    warnings,
    sanitizedEvidence,
  });
}

/**
 * Traverses issuer sitemaps breadth-first with fixed depth and URL budgets.
 * Every request is awaited before the next one; callers may inject both the
 * hardened fetcher and a delay for deterministic testing and rate limiting.
 */
export async function discoverIssuerCardCandidates(
  input: DiscoverIssuerCardCandidatesInput,
): Promise<IssuerCrawlResult> {
  const fetchResource = input.fetchOfficialIssuerResource ??
    fetchOfficialIssuerResourceDefault;
  const sitemapStarts = input.sitemapUrls ??
    (input.sitemapUrl ? [input.sitemapUrl] : []);
  const sitemapQueue: Array<{ url: string; depth: number }> = [];
  const seenSitemaps = new Set<string>();
  const candidateUrls: string[] = [];
  const seenCandidates = new Set<string>();
  const delay = input.delay ??
    ((milliseconds: number) =>
      new Promise<void>((resolve) => {
        setTimeout(resolve, milliseconds);
      }));
  let hasRequested = false;
  let anchorHost: string | null = null;

  const request = async (
    url: string,
    contentPurpose: OfficialFetchInput["contentPurpose"],
  ) => {
    if (hasRequested) await delay(input.delayMs ?? DEFAULT_CRAWL_DELAY_MS);
    if (
      input.deadlineAt !== undefined &&
      (input.now ?? Date.now)() >= input.deadlineAt
    ) {
      throw new Error("deadline_exceeded");
    }
    hasRequested = true;
    return await fetchResource({ issuer: input.issuer, url, contentPurpose });
  };

  for (const rawUrl of sitemapStarts) {
    if (seenSitemaps.size >= MAX_SITEMAP_URLS) break;
    const url = canonicalForIssuer(input.issuer, rawUrl);
    const hostname = url ? hostnameOf(url) : null;
    if (!url || !hostname) continue;
    if (!anchorHost) anchorHost = hostname;
    if (hostname !== anchorHost) continue;
    if (!seenSitemaps.has(url)) {
      seenSitemaps.add(url);
      sitemapQueue.push({ url, depth: 0 });
    }
  }

  for (let position = 0; position < sitemapQueue.length; position++) {
    const current = sitemapQueue[position];
    let response: OfficialFetchResult;
    try {
      response = await request(current.url, "sitemap");
    } catch {
      continue;
    }
    if (
      !anchorHost || !isAnchoredToHost(response.finalUrl, anchorHost) ||
      !isAnchoredToHost(response.canonicalUrl, anchorHost)
    ) {
      continue;
    }
    const document = parseSitemap(response.text);
    for (const rawLocation of document.locations) {
      const location = canonicalForIssuer(input.issuer, rawLocation);
      if (!location || !anchorHost || !isAnchoredToHost(location, anchorHost)) {
        continue;
      }

      if (document.isIndex && isSitemapUrl(location)) {
        if (
          current.depth < MAX_SITEMAP_DEPTH &&
          seenSitemaps.size < MAX_SITEMAP_URLS &&
          !seenSitemaps.has(location)
        ) {
          seenSitemaps.add(location);
          sitemapQueue.push({ url: location, depth: current.depth + 1 });
        }
        continue;
      }

      if (
        candidateUrls.length >= MAX_SITEMAP_URLS || seenCandidates.has(location)
      ) continue;
      seenCandidates.add(location);
      candidateUrls.push(location);
    }
  }

  if (candidateUrls.length === 0) {
    for (const rawIndexUrl of (input.indexUrls ?? []).slice(0, 8)) {
      const indexUrl = canonicalForIssuer(input.issuer, rawIndexUrl);
      const hostname = indexUrl ? hostnameOf(indexUrl) : null;
      if (!indexUrl || !hostname) continue;
      if (!anchorHost) anchorHost = hostname;
      if (hostname !== anchorHost) continue;
      let response: OfficialFetchResult;
      try {
        response = await request(indexUrl, "html");
      } catch {
        continue;
      }
      if (
        !isAnchoredToHost(response.finalUrl, anchorHost) ||
        !isAnchoredToHost(response.canonicalUrl, anchorHost)
      ) continue;
      for (const match of response.text.matchAll(htmlLinkPattern)) {
        let linked: string;
        try {
          linked = new URL(
            match[1] ?? match[2] ?? match[3] ?? "",
            response.canonicalUrl,
          ).toString();
        } catch {
          continue;
        }
        const location = canonicalForIssuer(input.issuer, linked);
        if (
          !location || !isAnchoredToHost(location, anchorHost) ||
          seenCandidates.has(location) || candidateUrlScore(location) <= 0
        ) continue;
        seenCandidates.add(location);
        candidateUrls.push(location);
        if (candidateUrls.length >= MAX_SITEMAP_URLS) break;
      }
      if (candidateUrls.length > 0) break;
    }
  }

  const candidates: PageClassification[] = [];
  const quarantined: PageClassification[] = [];
  const rankedCandidates = candidateUrls
    .map((url, index) => {
      const classification = classifyIssuerPage({ issuer: input.issuer, url });
      return { url, index, classification, positive: candidateUrlScore(url) };
    });
  const fetchableCandidates = rankedCandidates
    .filter((candidate) => {
      if (candidate.classification.kind !== "not_a_card") return true;
      quarantined.push(candidate.classification);
      return false;
    })
    .sort((left, right) =>
      right.positive - left.positive || left.index - right.index
    );
  let fetchedCount = 0;
  for (const { url } of fetchableCandidates.slice(0, MAX_CANDIDATE_FETCHES)) {
    fetchedCount += 1;
    try {
      const response = await request(
        url,
        /\.pdf(?:$|\?)/i.test(url) ? "document" : "html",
      );
      if (
        !anchorHost || !isAnchoredToHost(response.finalUrl, anchorHost) ||
        !isAnchoredToHost(response.canonicalUrl, anchorHost)
      ) {
        quarantined.push(emptyClassification(url, "cross_host_response"));
        continue;
      }
      const page = classifyIssuerPage({
        issuer: input.issuer,
        url,
        canonicalUrl: response.canonicalUrl,
        html: response.text,
      });
      (page.kind === "card_product" || page.kind === "supporting_document"
        ? candidates
        : quarantined)
        .push(page);
    } catch {
      quarantined.push(emptyClassification(url, "candidate_fetch_failed"));
    }
  }

  return {
    candidates,
    quarantined,
    consideredCount: candidateUrls.length,
    fetchedCount,
  };
}
