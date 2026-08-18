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

const exactSupportingSources: Record<string, Record<string, string[]>> = {
  "SBI Card": {
    elite: ["https://www.sbicard.com/en/eapply/sbicampaign.page"],
  },
};

type OfficialFetcher = (
  input: OfficialFetchInput,
) => Promise<OfficialFetchResult>;

export type SupportingDocumentInput = {
  issuer: string;
  primary: OfficialFetchResult;
  identityLabels: string[];
  fetchOfficialIssuerResource?: OfficialFetcher;
  maximumLinks?: number;
};

const genericIdentityTokens = new Set([
  "bank",
  "card",
  "cards",
  "credit",
  "debit",
  "the",
  "and",
]);

function identityTokens(labels: string[]): string[] {
  return [
    ...new Set(
      labels.flatMap((label) =>
        label.toLowerCase().split(/[^a-z0-9]+/).filter((token) =>
          token.length > 2 && !genericIdentityTokens.has(token)
        )
      ),
    ),
  ];
}

function exactSupportingUrls(issuer: string, labels: string[]): string[] {
  const sources = exactSupportingSources[issuer] ?? {};
  const exactLabels = new Set(
    labels.map((label) =>
      label.toLowerCase()
        .replace(/\bsbi\s+card\b/g, "")
        .replace(/[^a-z0-9]+/g, "")
    ).filter(Boolean),
  );
  return [...exactLabels].flatMap((label) => sources[label] ?? []);
}

function linkedUrls(
  issuer: string,
  baseUrl: string,
  html: string,
  labels: string[],
  primaryUrl: string,
): string[] {
  const urls: string[] = [];
  const tokens = identityTokens(labels);
  const primaryPath = new URL(primaryUrl).pathname.replace(/\/$/, "");
  for (const match of html.matchAll(anchorPattern)) {
    try {
      const raw = new URL(match[1] ?? match[2] ?? match[3] ?? "", baseUrl)
        .toString();
      const url = canonicalOfficialUrl(issuer, raw);
      const candidatePath = new URL(url).pathname.toLowerCase();
      const sameProductPath = candidatePath === primaryPath.toLowerCase() ||
        candidatePath.startsWith(`${primaryPath.toLowerCase()}/`);
      const namesTargetProduct = tokens.length > 0 &&
        tokens.every((token) => candidatePath.includes(token));
      if (
        relevantPath.test(url) && !unsafePath.test(url) &&
        (sameProductPath || namesTargetProduct) && !urls.includes(url)
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
  const queue = [
    ...exactSupportingUrls(input.issuer, input.identityLabels),
    ...linkedUrls(
      input.issuer,
      input.primary.canonicalUrl,
      input.primary.text,
      input.identityLabels,
      input.primary.canonicalUrl,
    ),
  ].map((url) => ({
    url: canonicalOfficialUrl(input.issuer, url),
    depth: 1,
  }));
  let fetched = 0;
  for (
    let position = 0;
    position < queue.length && fetched < budget;
    position++
  ) {
    const current = queue[position];
    if (seen.has(current.url)) continue;
    seen.add(current.url);
    fetched += 1;
    let resource: OfficialFetchResult;
    try {
      resource = await fetchResource({
        issuer: input.issuer,
        url: current.url,
        contentPurpose: "document",
        maxBytes: 1024 * 1024,
      });
    } catch {
      continue;
    }
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
          input.identityLabels,
          input.primary.canonicalUrl,
        )
      ) {
        if (!seen.has(url)) queue.push({ url, depth: current.depth + 1 });
      }
    }
  }
  return documents;
}
