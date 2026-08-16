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

function sanitizeEvidence(value: string): string {
  return textOnly(value)
    .replace(/\d{4,}/g, "[redacted]")
    .slice(0, 300);
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
  return {
    kind: "ambiguous",
    canonicalUrl: url,
    aliases: [],
    confidence: 0,
    warnings: [warning],
    sanitizedEvidence: [],
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
  const warnings: string[] = [];

  if (unsafePagePattern.test(evidence)) {
    return {
      kind: "not_a_card",
      canonicalUrl,
      aliases: [],
      confidence: 0.99,
      warnings: ["quarantined_page_pattern"],
      sanitizedEvidence,
    };
  }

  // A product heading commonly appears on its benefit/fee/terms pages. The
  // canonical path is the durable signal that makes those supporting pages
  // distinct from the product itself.
  if (supportingPattern.test(canonicalUrl)) {
    return {
      kind: "supporting_document",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.86 : 0.72,
      warnings,
      sanitizedEvidence,
    };
  }

  if (productPattern.test(evidence)) {
    return {
      kind: "card_product",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.95 : 0.82,
      warnings,
      sanitizedEvidence,
    };
  }

  if (supportingPattern.test(evidence)) {
    return {
      kind: "supporting_document",
      canonicalUrl,
      proposedName: identity?.cardName,
      aliases: identity?.aliases ?? [],
      network: identity?.network ?? undefined,
      confidence: identity ? 0.86 : 0.72,
      warnings,
      sanitizedEvidence,
    };
  }

  warnings.push("insufficient_card_signals");
  return {
    kind: "ambiguous",
    canonicalUrl,
    aliases: [],
    confidence: 0.2,
    warnings,
    sanitizedEvidence,
  };
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
  let hasRequested = false;

  const request = async (url: string, contentPurpose: OfficialFetchInput["contentPurpose"]) => {
    if (hasRequested && input.delay) await input.delay(input.delayMs ?? 0);
    hasRequested = true;
    return await fetchResource({ issuer: input.issuer, url, contentPurpose });
  };

  for (const rawUrl of sitemapStarts) {
    if (seenSitemaps.size >= MAX_SITEMAP_URLS) break;
    const url = canonicalForIssuer(input.issuer, rawUrl);
    if (url && !seenSitemaps.has(url)) {
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
    const document = parseSitemap(response.text);
    for (const rawLocation of document.locations) {
      const location = canonicalForIssuer(input.issuer, rawLocation);
      if (!location) continue;

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
  let fetchedCount = 0;
  for (const url of candidateUrls.slice(0, MAX_CANDIDATE_FETCHES)) {
    fetchedCount += 1;
    try {
      const response = await request(url, /\.pdf(?:$|\?)/i.test(url) ? "document" : "html");
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
