import {
  canonicalOfficialUrl,
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

type OfficialFetcher = (input: OfficialFetchInput) => Promise<OfficialFetchResult>;

export type DiscoverIssuerCardCandidatesInput = {
  issuer: string;
  sitemapUrl?: string;
  sitemapUrls?: string[];
  fetchOfficialIssuerResource?: OfficialFetcher;
  delay?: (milliseconds: number) => Promise<void> | void;
  delayMs?: number;
};

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

const unsafePagePattern = /(?:^|[/?=&_.-])(?:login|log-in|apply|application|track|tracking|blog|stories?|story|protection|insurance|generic|help|support|learning-centre)(?:$|[/?=&_.-])/i;
const supportingPattern = /(?:benefits?|fees?|charges?|rewards?|terms?|conditions?|mitc)(?:$|[/?=&_.-])/i;
const productPattern = /(?:credit[-_ ]?cards?|cards?[-_ ]?credit|card[-_ ]?products?|product[-_ ]?cards?)(?:$|[/?=&_.-])/i;
const evidencePattern = /<(?:title|h1|h2)[^>]*>([\s\S]*?)<\/(?:title|h1|h2)>/gi;
const linkPattern = /<loc\b[^>]*>([\s\S]*?)<\/loc>/gi;
const nonProductPathTokens = new Set([
  "card", "cards", "credit", "products", "product", "personal", "bank",
  "benefit", "benefits", "fee", "fees", "charge", "charges", "reward", "rewards",
  "term", "terms", "condition", "conditions", "mitc", "html", "pdf",
  "all", "overview", "compare", "comparison", "option", "options", "explore", "our",
  "range", "legal", "navigation", "home", "landing", "page",
  "and", "or", "the", "for", "of", "to", "in", "with", "your",
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
  return new Set(tokens(value).filter((token) =>
    !nonProductPathTokens.has(token) && !issuerTokens.has(token)
  ));
}

function urlPathAndHeadingTokens(url: string, html: string, issuer: string): Set<string> {
  try {
    const pathname = decodeURIComponent(new URL(url).pathname);
    return meaningfulTokens(`${pathname} ${evidenceFromHtml(html).join(" ")}`, issuer);
  } catch {
    return new Set();
  }
}

function hasProductSpecificUrlContext(url: string): boolean {
  return urlPathAndHeadingTokens(url, "", "").size > 0;
}

function hasSharedProductIdentityContext(
  identity: { cardName: string; aliases: string[] } | null,
  url: string,
  html: string,
  issuer: string,
): boolean {
  if (!identity) return false;
  const identityTokens = meaningfulTokens(
    [identity.cardName, ...identity.aliases].join(" "),
    issuer,
  );
  const contextTokens = urlPathAndHeadingTokens(url, html, issuer);
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
    proposedName: page.proposedName ? redactLongDigits(page.proposedName) : undefined,
    aliases: page.aliases.map(redactLongDigits),
    network: page.network ? redactLongDigits(page.network) : undefined,
    warnings: page.warnings.map(redactLongDigits),
    sanitizedEvidence: page.sanitizedEvidence.map(sanitizeEvidence),
  };
}

/**
 * Classifies only URL and short, redacted heading/title evidence. The supplied
 * page body is deliberately not returned or stored in the classification.
 */
export function classifyIssuerPage(input: ClassifyIssuerPageInput): PageClassification {
  const canonicalUrl = input.canonicalUrl ?? canonicalForIssuer(input.issuer, input.url) ?? input.url;
  const html = input.html ?? input.text ?? "";
  const evidence = pageEvidence(canonicalUrl, html);
  const sanitizedEvidence = evidenceFromHtml(html);
  const identity = officialCardIdentityFromHtml(html, input.issuer);
  const hasIdentityContext = hasSharedProductIdentityContext(
    identity,
    canonicalUrl,
    html,
    input.issuer,
  );
  const warnings: string[] = [];

  if (unsafePagePattern.test(evidence)) {
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
  const fetchResource = input.fetchOfficialIssuerResource ?? fetchOfficialIssuerResourceDefault;
  const sitemapStarts = input.sitemapUrls ?? (input.sitemapUrl ? [input.sitemapUrl] : []);
  const sitemapQueue: Array<{ url: string; depth: number }> = [];
  const seenSitemaps = new Set<string>();
  const candidateUrls: string[] = [];
  const seenCandidates = new Set<string>();
  const delay = input.delay ?? ((milliseconds: number) => new Promise<void>((resolve) => {
    setTimeout(resolve, milliseconds);
  }));
  let hasRequested = false;
  let anchorHost: string | null = null;

  const request = async (url: string, contentPurpose: OfficialFetchInput["contentPurpose"]) => {
    if (hasRequested) await delay(input.delayMs ?? DEFAULT_CRAWL_DELAY_MS);
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
    if (!anchorHost || !isAnchoredToHost(response.finalUrl, anchorHost) ||
      !isAnchoredToHost(response.canonicalUrl, anchorHost)) {
      continue;
    }
    const document = parseSitemap(response.text);
    for (const rawLocation of document.locations) {
      const location = canonicalForIssuer(input.issuer, rawLocation);
      if (!location || !anchorHost || !isAnchoredToHost(location, anchorHost)) continue;

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

      if (candidateUrls.length >= MAX_SITEMAP_URLS || seenCandidates.has(location)) continue;
      seenCandidates.add(location);
      candidateUrls.push(location);
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
    .sort((left, right) => right.positive - left.positive || left.index - right.index);
  let fetchedCount = 0;
  for (const { url } of fetchableCandidates.slice(0, MAX_CANDIDATE_FETCHES)) {
    fetchedCount += 1;
    try {
      const response = await request(url, /\.pdf(?:$|\?)/i.test(url) ? "document" : "html");
      if (!anchorHost || !isAnchoredToHost(response.finalUrl, anchorHost) ||
        !isAnchoredToHost(response.canonicalUrl, anchorHost)) {
        quarantined.push(emptyClassification(url, "cross_host_response"));
        continue;
      }
      const page = classifyIssuerPage({
        issuer: input.issuer,
        url,
        canonicalUrl: response.canonicalUrl,
        html: response.text,
      });
      (page.kind === "card_product" || page.kind === "supporting_document" ? candidates : quarantined)
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
