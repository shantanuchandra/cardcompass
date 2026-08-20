import {
  assessOfficialCardIdentity,
  canonicalCardIdentity,
  canonicalOfficialUrl,
  normalizedProduct,
  normalizedProductFamily,
  officialCardIdentityFromHtml,
} from "./card_discovery.ts";
import {
  approvedStoredQueryParameters,
  canonicalOfficialRequestUrl,
  createOfficialRobotsCache,
  fetchOfficialIssuerResource as fetchOfficialIssuerResourceDefault,
  type OfficialFetchInput,
  type OfficialFetchResult,
  requireOfficialFetchBody,
} from "./official_issuer_fetch.ts";
import {
  redactSensitiveUrlsInText,
  safeHttpsDisplayUrl,
} from "./benefit_source_privacy.ts";
import {
  canonicalPublicationResource,
  hasStrongExplicitCardDiscontinuation,
  proposeCatalogLifecycleReview,
  publishReviewedCardIdentity,
} from "./catalog_identity_publication.ts";

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
  submittedResourceIdentityHash?: string;
  finalResourceIdentityHash?: string;
  submittedUrl?: string;
  finalUrl?: string;
  contentHash?: string;
  retrievedAt?: string;
  sourceStatus?: number;
  explicitDiscontinuation?: boolean;
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
  submittedResourceIdentityHash?: string;
  finalResourceIdentityHash?: string;
  submittedUrl?: string;
  finalUrl?: string;
  contentHash?: string;
  retrievedAt?: string;
  sourceStatus?: number;
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
  return redactSensitiveUrlsInText(redactLongDigits(textOnly(value))).slice(
    0,
    300,
  );
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

function requestForIssuer(issuer: string, url: string): string | null {
  try {
    return canonicalOfficialRequestUrl(
      issuer,
      url,
      approvedStoredQueryParameters(url),
    );
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

function redirectPreservesProductIdentity(
  requestedUrl: string,
  finalUrl: string,
  issuer: string,
): boolean {
  const requested = safeHttpsDisplayUrl(requestedUrl);
  const final = safeHttpsDisplayUrl(finalUrl);
  if (!requested || !final) return false;
  if (requested === final) return true;
  const requestedTokens = urlPathTokens(requested, issuer);
  const finalTokens = urlPathTokens(final, issuer);
  return requestedTokens.size > 0 &&
    [...requestedTokens].some((token) => finalTokens.has(token));
}

function responseMatchesRequestedProduct(
  requestedUrl: string,
  responseText: string,
  issuer: string,
): boolean {
  const requestedTokens = urlPathTokens(requestedUrl, issuer);
  if (requestedTokens.size === 0) return false;
  const assessment = assessOfficialCardIdentity(responseText, issuer);
  if (assessment.status === "ambiguous") return false;
  const identity = assessment.identity;
  const evidenceTokens = identity
    ? meaningfulTokens(
      [identity.cardName, ...identity.aliases].join(" "),
      issuer,
    )
    : /\bcredit\s+card\b/i.test(responseText)
    ? meaningfulTokens(responseText.slice(0, 32_000), issuer)
    : new Set<string>();
  return evidenceTokens.size > 0 &&
    [...requestedTokens].every((token) => evidenceTokens.has(token));
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
  const {
    submittedResourceIdentityHash,
    finalResourceIdentityHash,
    submittedUrl,
    finalUrl,
    contentHash,
    retrievedAt,
    sourceStatus,
    explicitDiscontinuation,
    ...classification
  } = page;
  const validHash = (value: string | undefined): value is string =>
    typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
  return {
    ...classification,
    canonicalUrl: safeHttpsDisplayUrl(page.canonicalUrl) ?? "invalid-source",
    proposedName: page.proposedName
      ? redactSensitiveUrlsInText(redactLongDigits(page.proposedName))
      : undefined,
    aliases: page.aliases.map((value) =>
      redactSensitiveUrlsInText(redactLongDigits(value))
    ),
    network: page.network
      ? redactSensitiveUrlsInText(redactLongDigits(page.network))
      : undefined,
    warnings: page.warnings.map((value) =>
      redactSensitiveUrlsInText(redactLongDigits(value))
    ),
    sanitizedEvidence: page.sanitizedEvidence.map(sanitizeEvidence),
    ...(validHash(submittedResourceIdentityHash)
      ? {
        submittedResourceIdentityHash: submittedResourceIdentityHash
          .toLowerCase(),
      }
      : {}),
    ...(validHash(finalResourceIdentityHash)
      ? { finalResourceIdentityHash: finalResourceIdentityHash.toLowerCase() }
      : {}),
    ...(safeApprovedResourceUrl(submittedUrl)
      ? { submittedUrl: safeApprovedResourceUrl(submittedUrl)! }
      : {}),
    ...(safeApprovedResourceUrl(finalUrl)
      ? { finalUrl: safeApprovedResourceUrl(finalUrl)! }
      : {}),
    ...(validHash(contentHash)
      ? { contentHash: contentHash.toLowerCase() }
      : {}),
    ...(typeof retrievedAt === "string" &&
        /^\d{4}-\d{2}-\d{2}T/.test(retrievedAt)
      ? { retrievedAt: retrievedAt.slice(0, 40) }
      : {}),
    ...(Number.isInteger(sourceStatus) && sourceStatus! >= 100 &&
        sourceStatus! <= 599
      ? { sourceStatus }
      : {}),
    ...(explicitDiscontinuation === true
      ? { explicitDiscontinuation: true }
      : {}),
  };
}

function safeApprovedResourceUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  try {
    const exact = value.trim().split("#", 1)[0];
    const url = new URL(exact);
    if (
      url.protocol !== "https:" || !url.hostname || url.username || url.password
    ) {
      return null;
    }
    const nonTracking = [...url.searchParams.keys()].filter((key) =>
      !/^utm_/i.test(key) && !["gclid", "fbclid"].includes(key.toLowerCase())
    );
    const approved = approvedStoredQueryParameters(exact);
    if (nonTracking.length > 0 && approved.length === 0) return null;
    if (nonTracking.length !== [...url.searchParams.keys()].length) return null;
    return exact;
  } catch {
    return null;
  }
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
  const { data: urlKeyData, error: urlKeyError } = await supabase
    .from("card_catalog_url_keys")
    .select("card_id")
    .eq("url_hash", urlHash);
  if (urlKeyError) throw urlKeyError;

  const { data: provenanceData, error: provenanceError } = await supabase
    .from("card_catalog_provenance")
    .select("card_id")
    .or(`submitted_url_hash.eq.${urlHash},final_url_hash.eq.${urlHash}`);
  if (provenanceError) throw provenanceError;
  const asRows = (value: unknown): Array<{ card_id?: string }> =>
    Array.isArray(value)
      ? value as Array<{ card_id?: string }>
      : value && typeof value === "object"
      ? [value as { card_id?: string }]
      : [];
  const cardIds = [
    ...new Set(
      [...asRows(urlKeyData), ...asRows(provenanceData)].map((row) =>
        row.card_id
      ).filter(
        (value): value is string => typeof value === "string" && Boolean(value),
      ),
    ),
  ];
  if (cardIds.length > 1) throw new Error("identity_conflict");
  return cardIds[0] ?? null;
}

async function findCrawlerCatalogCandidates(
  supabase: UntypedSupabaseClient,
  issuer: string,
  normalizedNames: string[],
  normalizedFamilies: string[],
): Promise<Array<Record<string, unknown>>> {
  const { data: catalogRows, error: catalogError } = await supabase
    .from("card_catalog")
    .select(
      "id, bank, card_name, network, card_type, is_discontinued, updated_at",
    )
    .ilike("bank", issuer);
  if (catalogError) throw catalogError;
  const catalog = ((catalogRows ?? []) as Array<Record<string, unknown>>)
    .filter((row) =>
      String(row.bank ?? "").trim().toLowerCase() ===
        issuer.trim().toLowerCase() &&
      String(row.card_type ?? "").trim().toLowerCase() === "credit"
    );
  const byId = new Map(
    catalog.map((row: Record<string, unknown>) => [String(row.id), row]),
  );
  const matches = new Map<string, Record<string, unknown>>();
  for (const row of catalog) {
    if (
      normalizedNames.includes(
        normalizedProduct(String(row.card_name ?? ""), issuer),
      ) || normalizedFamilies.includes(
        normalizedProductFamily(String(row.card_name ?? ""), issuer),
      )
    ) {
      matches.set(String(row.id), row);
    }
  }

  if (normalizedNames.length > 0) {
    const { data: aliasRows, error: aliasError } = await supabase
      .from("card_catalog_aliases")
      .select("card_id, alias, normalized_alias")
      .in("card_id", [...byId.keys()]);
    if (aliasError) throw aliasError;
    for (const alias of aliasRows ?? []) {
      const card = byId.get(String(alias.card_id));
      const normalizedAlias = normalizedProduct(
        String(alias.alias ?? alias.normalized_alias ?? ""),
        issuer,
      );
      if (card && normalizedNames.includes(normalizedAlias)) {
        matches.set(String(alias.card_id), card);
      }
    }
  }

  return [...matches.values()].map((row) => ({
    id: row.id,
    bank: row.bank,
    card_name: row.card_name,
    network: row.network ?? null,
    card_type: row.card_type,
    is_discontinued: row.is_discontinued === true,
    updated_at: row.updated_at ?? null,
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
  const validOpaqueHash = (value: string | undefined): value is string =>
    typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
  const submittedResource = await canonicalPublicationResource(
    issuer,
    candidate.submittedUrl ?? canonicalUrl,
  );
  const finalResource = await canonicalPublicationResource(
    issuer,
    candidate.finalUrl ?? candidate.submittedUrl ?? canonicalUrl,
  );
  const submittedHash = validOpaqueHash(
      candidate.submittedResourceIdentityHash,
    )
    ? candidate.submittedResourceIdentityHash.toLowerCase()
    : submittedResource.urlHash;
  const finalHash = validOpaqueHash(candidate.finalResourceIdentityHash)
    ? candidate.finalResourceIdentityHash.toLowerCase()
    : finalResource.urlHash;
  if (
    submittedHash !== submittedResource.urlHash ||
    finalHash !== finalResource.urlHash
  ) throw new Error("identity_conflict");
  const resourceHashes = [...new Set([submittedHash, finalHash])];
  const boundCardIds = [
    ...new Set(
      (await Promise.all(
        resourceHashes.map((hash) => findCatalogCardByUrlHash(supabase, hash)),
      )).filter((value): value is string => Boolean(value)),
    ),
  ];
  if (boundCardIds.length > 1) throw new Error("identity_conflict");
  const knownCardId = boundCardIds[0] ?? null;
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
  const normalizedFamilies = [
    ...new Set([canonical.cardName, ...aliases]
      .map((value) => normalizedProductFamily(value, issuer))),
  ].filter((value) => value.length >= 2);
  const candidates = await findCrawlerCatalogCandidates(
    supabase,
    issuer,
    normalizedNames,
    normalizedFamilies,
  );
  const proposedNetwork = (canonical.network ?? candidate.network)?.trim()
    .toLowerCase() ?? null;
  const tierKey = (value: unknown): string | null => {
    const normalized = String(value ?? "").toLowerCase().replace(
      /[^a-z0-9]+/g,
      " ",
    );
    if (/\bworld elite\b/.test(normalized)) return "world-elite";
    for (
      const tier of [
        "infinite",
        "signature",
        "world",
        "platinum",
        "gold",
        "select",
        "classic",
      ]
    ) {
      if (new RegExp(`\\b${tier}\\b`).test(normalized)) return tier;
    }
    return null;
  };
  const proposedTier = tierKey(canonical.cardName);
  const networkCompatibleCandidates = candidates.filter((row) => {
    const storedNetwork = typeof row.network === "string"
      ? row.network.trim().toLowerCase()
      : "";
    const storedTier = tierKey(row.card_name);
    return (!storedNetwork ||
      Boolean(proposedNetwork && storedNetwork === proposedNetwork)) &&
      (!storedTier || storedTier === proposedTier);
  });
  const exactExisting = candidates.length === 1 &&
      networkCompatibleCandidates.length === 1 &&
      (!knownCardId ||
        String(networkCompatibleCandidates[0].id) === knownCardId)
    ? networkCompatibleCandidates[0]
    : null;
  const warnings = uniqueStrings([
    ...candidate.warnings,
    "crawler_discovered_without_statement_signal",
    ...(candidates.length > 1 ? ["ambiguous_catalog_identity"] : []),
    ...(proposedNetwork && candidates.length > 0 &&
        networkCompatibleCandidates.length === 0
      ? ["conflicting_network_identity"]
      : []),
    ...(candidates.length > 0 && networkCompatibleCandidates.length === 0
      ? ["conflicting_strong_identity"]
      : []),
  ]);
  const safeEvidence = uniqueStrings(candidate.sanitizedEvidence, 300).slice(
    0,
    3,
  );
  const contentIdentity = validOpaqueHash(candidate.contentHash)
    ? candidate.contentHash.toLowerCase()
    : await sha256(JSON.stringify({
      evidence: safeEvidence,
      source_status: candidate.sourceStatus ?? 200,
    }));
  const dedupeKey = await sha256(
    `${issuer.trim().toLowerCase()}:${submittedHash}:${finalHash}:${contentIdentity}`,
  );

  const sourceObservation = {
    kind: "strong_existing_official_card",
    identity_validated: true,
    source_status: Number.isInteger(candidate.sourceStatus)
      ? candidate.sourceStatus
      : 200,
    submitted_url_hash: submittedHash,
    final_url_hash: finalHash,
    content_hash: contentIdentity,
    explicit_discontinuation: candidate.explicitDiscontinuation === true,
    ...(candidate.retrievedAt ? { retrieved_at: candidate.retrievedAt } : {}),
  };
  if (
    exactExisting?.is_discontinued === true &&
    candidate.explicitDiscontinuation !== true
  ) {
    const reviewId = await proposeCatalogLifecycleReview(supabase, {
      cardId: String(exactExisting.id),
      suggestedAction: "reactivate",
      sourceUrl: finalResource.canonicalUrl,
      sourceUrlHash: finalHash,
      contentHash: validOpaqueHash(candidate.contentHash)
        ? candidate.contentHash.toLowerCase()
        : null,
      sourceObservation: {
        ...sourceObservation,
        kind: "exact_card_reappearance",
      },
    });
    return { outcome: "review", reviewId };
  }
  if (
    exactExisting?.is_discontinued === true &&
    candidate.explicitDiscontinuation === true
  ) {
    return {
      outcome: "duplicate",
      catalogCardId: String(exactExisting.id),
    };
  }

  const { data: existingJob, error: existingJobError } = await supabase
    .from("card_discovery_jobs")
    .select("id, review_item_id, status")
    .eq("discovery_source", "issuer_crawl")
    .eq("dedupe_key", dedupeKey)
    .is("user_id", null)
    .maybeSingle();
  if (existingJobError) throw existingJobError;
  if (
    existingJob && ["resolved", "rejected"].includes(existingJob.status) &&
    !(
      existingJob.status === "resolved" && exactExisting &&
      !existingJob.review_item_id
    )
  ) {
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
    submitted_url: submittedResource.canonicalUrl,
    final_url: finalResource.canonicalUrl,
    submitted_url_hash: submittedHash,
    final_url_hash: finalHash,
    ...(validOpaqueHash(candidate.contentHash)
      ? { content_hash: candidate.contentHash.toLowerCase() }
      : {}),
    ...(candidate.retrievedAt ? { retrieved_at: candidate.retrievedAt } : {}),
    source_status: Number.isInteger(candidate.sourceStatus)
      ? candidate.sourceStatus
      : 200,
  };
  const evidence = {
    issuer,
    official_url: canonicalUrl,
    url_hash: submittedHash,
    submitted_resource_identity_hash: submittedHash,
    final_resource_identity_hash: finalHash,
    submitted_url: submittedResource.canonicalUrl,
    final_url: finalResource.canonicalUrl,
    ...(validOpaqueHash(candidate.contentHash)
      ? { content_hash: candidate.contentHash.toLowerCase() }
      : {}),
    ...(candidate.retrievedAt ? { retrieved_at: candidate.retrievedAt } : {}),
    ...(Number.isInteger(candidate.sourceStatus)
      ? { source_status: candidate.sourceStatus }
      : {}),
    product_signals: aliases,
    crawler_evidence: safeEvidence,
    warnings,
    confidence: Math.max(0, Math.min(1, candidate.confidence)),
    crawler_proposal: proposal,
    crawler_source_evidence: {
      official_url: canonicalUrl,
      url_hash: submittedHash,
      submitted_resource_identity_hash: submittedHash,
      final_resource_identity_hash: finalHash,
      submitted_url: submittedResource.canonicalUrl,
      final_url: finalResource.canonicalUrl,
      ...(validOpaqueHash(candidate.contentHash)
        ? { content_hash: candidate.contentHash.toLowerCase() }
        : {}),
      ...(candidate.retrievedAt ? { retrieved_at: candidate.retrievedAt } : {}),
      ...(Number.isInteger(candidate.sourceStatus)
        ? { source_status: candidate.sourceStatus }
        : {}),
      source_observation: sourceObservation,
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

  if (exactExisting && !job.review_item_id) {
    const published = await publishReviewedCardIdentity(supabase, {
      discoveryJobId: String(job.id),
      action: "observe_existing",
      reviewedFields: {
        ...proposal,
        card_id: exactExisting.id,
        source_type: "official_html",
        source_observation: sourceObservation,
      },
      parserVersion: "benefits-v6",
    });
    if (
      published.cardId !== String(exactExisting.id) ||
      published.jobId !== String(job.id) ||
      published.resultingStatus !== "resolved"
    ) throw new Error("invalid_catalog_publication_outcome");
    return {
      outcome: "existing",
      catalogCardId: String(exactExisting.id),
    };
  }

  const { data: existingReview, error: existingReviewError } = await supabase
    .from("card_catalog_review_queue")
    .select(
      "id, status, proposed_fields, source_evidence, existing_candidates, validation_warnings, confidence, updated_at",
    )
    .eq("discovery_job_id", job.id)
    .maybeSingle();
  if (existingReviewError) throw existingReviewError;
  if (
    existingReview &&
    ["approved", "merged", "rejected"].includes(existingReview.status)
  ) {
    return { outcome: "duplicate", reviewId: existingReview.id };
  }

  if (existingReview?.status === "pending") {
    const history =
      Array.isArray(existingReview.source_evidence?.observation_history)
        ? existingReview.source_evidence.observation_history.slice(-15)
        : [];
    if (history.length === 0 && existingReview.source_evidence) {
      history.push({
        observed_at: existingReview.source_evidence.retrieved_at ??
          existingReview.updated_at,
        content_hash: existingReview.source_evidence.content_hash ??
          contentIdentity,
        submitted_url_hash:
          existingReview.source_evidence.submitted_resource_identity_hash ??
            submittedHash,
        final_url_hash:
          existingReview.source_evidence.final_resource_identity_hash ??
            finalHash,
        source_status: existingReview.source_evidence.source_status ?? 200,
      });
    }
    const refreshedAt = new Date().toISOString();
    const refreshedEvidence = {
      ...evidence.crawler_source_evidence,
      observation_history: [
        ...history.slice(-14),
        {
          observed_at: candidate.retrievedAt ?? refreshedAt,
          content_hash: contentIdentity,
          source_status: candidate.sourceStatus ?? 200,
        },
      ],
    };
    const update = supabase.from("card_catalog_review_queue")
      .update({
        proposed_fields: proposal,
        source_evidence: refreshedEvidence,
        existing_candidates: candidates,
        validation_warnings: warnings,
        confidence: evidence.confidence,
        updated_at: refreshedAt,
      })
      .eq("id", existingReview.id)
      .eq("status", "pending");
    const { data: refreshedReview, error: refreshError } =
      existingReview.updated_at
        ? await update.eq("updated_at", existingReview.updated_at).select(
          "id, status",
        ).maybeSingle()
        : await update.is("updated_at", null).select("id, status")
          .maybeSingle();
    if (refreshError || !refreshedReview) {
      throw refreshError ?? new Error("catalog_review_race");
    }
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
  const resourceIdentities = {
    ...(input.submittedResourceIdentityHash
      ? {
        submittedResourceIdentityHash: input.submittedResourceIdentityHash,
      }
      : {}),
    ...(input.finalResourceIdentityHash
      ? { finalResourceIdentityHash: input.finalResourceIdentityHash }
      : {}),
    ...(input.submittedUrl ? { submittedUrl: input.submittedUrl } : {}),
    ...(input.finalUrl ? { finalUrl: input.finalUrl } : {}),
    ...(input.contentHash ? { contentHash: input.contentHash } : {}),
    ...(input.retrievedAt ? { retrievedAt: input.retrievedAt } : {}),
    ...(input.sourceStatus ? { sourceStatus: input.sourceStatus } : {}),
    ...(hasStrongExplicitCardDiscontinuation(html)
      ? { explicitDiscontinuation: true }
      : {}),
  };

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
      ...resourceIdentities,
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
      ...resourceIdentities,
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
      ...resourceIdentities,
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
      ...resourceIdentities,
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
    ...resourceIdentities,
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
  const robotsCache = createOfficialRobotsCache();
  const sitemapStarts = input.sitemapUrls ??
    (input.sitemapUrl ? [input.sitemapUrl] : []);
  const sitemapQueue: Array<{ url: string; depth: number }> = [];
  const seenSitemaps = new Set<string>();
  const candidateUrls: string[] = [];
  const seenCandidates = new Set<string>();
  const rejectedCandidateUrls: string[] = [];
  const delay = input.delay ??
    ((milliseconds: number) =>
      new Promise<void>((resolve) => {
        setTimeout(resolve, milliseconds);
      }));
  let hasRequested = false;
  let anchorHost: string | null = null;
  const now = input.now ?? Date.now;

  const request = async (
    url: string,
    contentPurpose: OfficialFetchInput["contentPurpose"],
  ) => {
    if (hasRequested) {
      const intendedDelay = input.delayMs ?? DEFAULT_CRAWL_DELAY_MS;
      if (
        input.deadlineAt !== undefined &&
        (now() >= input.deadlineAt ||
          intendedDelay > input.deadlineAt - now())
      ) throw new Error("deadline_exceeded");
      await delay(intendedDelay);
    }
    if (
      input.deadlineAt !== undefined &&
      now() >= input.deadlineAt
    ) {
      throw new Error("deadline_exceeded");
    }
    hasRequested = true;
    return requireOfficialFetchBody(
      await fetchResource({
        issuer: input.issuer,
        url,
        contentPurpose,
        deadlineAt: input.deadlineAt,
        now: input.now,
        enforceRobots: input.fetchOfficialIssuerResource === undefined,
        robotsCache,
        allowedQueryParameters: approvedStoredQueryParameters(url),
      }),
    );
  };

  for (const rawUrl of sitemapStarts) {
    if (seenSitemaps.size >= MAX_SITEMAP_URLS) break;
    const url = requestForIssuer(input.issuer, rawUrl);
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
    const document = parseSitemap(response.text ?? "");
    for (const rawLocation of document.locations) {
      const location = requestForIssuer(input.issuer, rawLocation);
      if (!location) {
        const display = canonicalForIssuer(input.issuer, rawLocation);
        if (
          display && anchorHost && isAnchoredToHost(display, anchorHost) &&
          !document.isIndex && !seenCandidates.has(display)
        ) {
          seenCandidates.add(display);
          rejectedCandidateUrls.push(display);
        }
        continue;
      }
      if (!anchorHost || !isAnchoredToHost(location, anchorHost)) {
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
      const indexUrl = requestForIssuer(input.issuer, rawIndexUrl);
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
      for (const match of (response.text ?? "").matchAll(htmlLinkPattern)) {
        let linked: string;
        try {
          linked = new URL(
            match[1] ?? match[2] ?? match[3] ?? "",
            response.canonicalUrl,
          ).toString();
        } catch {
          continue;
        }
        const location = requestForIssuer(input.issuer, linked);
        if (!location) {
          const display = canonicalForIssuer(input.issuer, linked);
          if (
            display && isAnchoredToHost(display, anchorHost) &&
            !seenCandidates.has(display) && candidateUrlScore(display) > 0
          ) {
            seenCandidates.add(display);
            rejectedCandidateUrls.push(display);
          }
          continue;
        }
        if (
          !isAnchoredToHost(location, anchorHost) ||
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
  const quarantined: PageClassification[] = rejectedCandidateUrls.map((url) =>
    emptyClassification(url, "unapproved_query")
  );
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
      if (
        !redirectPreservesProductIdentity(
          url,
          response.canonicalUrl,
          input.issuer,
        ) || !responseMatchesRequestedProduct(
          url,
          response.text,
          input.issuer,
        )
      ) {
        quarantined.push(
          emptyClassification(url, "redirect_identity_mismatch"),
        );
        continue;
      }
      const page = classifyIssuerPage({
        issuer: input.issuer,
        url,
        canonicalUrl: response.canonicalUrl,
        html: response.text,
        submittedResourceIdentityHash: response.sourceIdentityHash,
        finalResourceIdentityHash: response.finalResourceIdentityHash,
        submittedUrl: response.submittedResourceUrl ?? response.submittedUrl,
        finalUrl: response.finalResourceUrl ?? response.finalUrl,
        contentHash: response.contentHash,
        retrievedAt: response.retrievedAt,
        sourceStatus: response.status,
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
    consideredCount: candidateUrls.length + rejectedCandidateUrls.length,
    fetchedCount,
  };
}
