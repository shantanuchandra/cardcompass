import { type BenefitDocument } from "../_shared/benefit_enrichment.ts";
import { canonicalOfficialUrl } from "../_shared/card_discovery.ts";
import {
  fetchOfficialIssuerResource as fetchOfficialIssuerResourceDefault,
  type OfficialFetchInput,
  type OfficialFetchResult,
  officialResourceText,
} from "../_shared/official_issuer_fetch.ts";

const MAX_SUPPORTING_LINKS = 8;
const MAX_SUPPORTING_DEPTH = 2;
const relevantPath =
  /(?:credit[-_/ ]?cards?|cards?[-_/ ]?credit|benefits?|fees?|charges?|rewards?|terms?|conditions?|mitc)(?:$|[/?=&_.-])/i;
const unsafePath =
  /(?:^|[/?=&_.-])(?:login|apply|application|track|support|help)(?:$|[/?=&_.-])/i;
const anchorPattern =
  /<a\b[^>]*\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>/gi;

type OfficialFetcher = (
  input: OfficialFetchInput,
) => Promise<OfficialFetchResult>;

export type SupportingDocumentInput = {
  issuer: string;
  primary: OfficialFetchResult;
  fetchOfficialIssuerResource?: OfficialFetcher;
  maximumLinks?: number;
};

function linkedUrls(
  issuer: string,
  baseUrl: string,
  html: string,
): string[] {
  const urls: string[] = [];
  for (const match of html.matchAll(anchorPattern)) {
    try {
      const raw = new URL(match[1] ?? match[2] ?? match[3] ?? "", baseUrl)
        .toString();
      const url = canonicalOfficialUrl(issuer, raw);
      if (
        relevantPath.test(url) && !unsafePath.test(url) && !urls.includes(url)
      ) urls.push(url);
    } catch {
      // Only approved issuer URLs enter the supporting queue.
    }
  }
  return urls;
}

async function benefitDocument(
  resource: OfficialFetchResult,
): Promise<BenefitDocument> {
  return {
    sourceUrl: resource.canonicalUrl,
    text: await officialResourceText(resource),
    contentHash: resource.contentHash,
  };
}

export async function collectSupportingBenefitDocuments(
  input: SupportingDocumentInput,
): Promise<BenefitDocument[]> {
  const fetchResource = input.fetchOfficialIssuerResource ??
    fetchOfficialIssuerResourceDefault;
  const budget = Math.min(
    MAX_SUPPORTING_LINKS,
    Math.max(0, Math.trunc(input.maximumLinks ?? MAX_SUPPORTING_LINKS)),
  );
  const documents = [await benefitDocument(input.primary)];
  const seen = new Set([input.primary.canonicalUrl]);
  const queue = linkedUrls(
    input.issuer,
    input.primary.canonicalUrl,
    input.primary.text,
  ).map((url) => ({ url, depth: 1 }));
  let fetched = 0;
  for (
    let position = 0;
    position < queue.length && fetched < budget;
    position++
  ) {
    const current = queue[position];
    if (seen.has(current.url)) continue;
    seen.add(current.url);
    let resource: OfficialFetchResult;
    try {
      resource = await fetchResource({
        issuer: input.issuer,
        url: current.url,
        contentPurpose: "document",
      });
    } catch {
      continue;
    }
    fetched += 1;
    const document = await benefitDocument(resource);
    if (document.text.trim()) documents.push(document);
    if (
      current.depth < MAX_SUPPORTING_DEPTH &&
      resource.contentType !== "application/pdf"
    ) {
      for (
        const url of linkedUrls(
          input.issuer,
          resource.canonicalUrl,
          resource.text,
        )
      ) {
        if (!seen.has(url)) queue.push({ url, depth: current.depth + 1 });
      }
    }
  }
  return documents;
}
