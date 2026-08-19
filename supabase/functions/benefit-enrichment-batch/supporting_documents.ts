import { type BenefitDocument } from "../_shared/benefit_enrichment.ts";
import { canonicalOfficialUrl } from "../_shared/card_discovery.ts";
import {
  fetchOfficialIssuerResource as fetchOfficialIssuerResourceDefault,
  type OfficialFetchInput,
  type OfficialFetchResult,
  officialResourceText,
} from "../_shared/official_issuer_fetch.ts";
import {
  boundedSourceUrl,
  sanitizedSourceErrorCode,
  type SourceAttemptInput,
} from "./crawl_policy.ts";

const MAX_SUPPORTING_LINKS = 8;
const MAX_SUPPORTING_DEPTH = 2;
const relevantPath =
  /(?:credit[-_/ ]?cards?|cards?[-_/ ]?credit|benefits?|fees?|charges?|rewards?|terms?|conditions?|mitc)(?:$|[/?=&_.-])/i;
const unsafePath =
  /(?:^|[/?=&_.-])(?:login|apply|application|track|support|help)(?:$|[/?=&_.-])/i;
const anchorPattern =
  /<a\b[^>]*\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a\s*>/gi;
const requiredSourcePattern =
  /(?:^|[/?=&_.-])(?:terms?|conditions?|mitc|fees?|charges?)(?:$|[/?=&_.-])/i;
const requiredAnchorPattern =
  /\b(?:most\s+important\s+terms(?:\s+and\s+conditions)?|terms?(?:\s+and\s+conditions)?|conditions?|mitc|fees?|charges?)\b/i;
const relevantAnchorPattern =
  /\b(?:benefits?|rewards?|supporting\s+(?:material|document))\b/i;

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
  requestDeadlineAt?: number;
};

export type CollectedSources = {
  documents: BenefitDocument[];
  attempts: SourceAttemptInput[];
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

type SourceCandidate = {
  url: string;
  anchorText: string;
  requiredHint: boolean;
};

function sourceRole(
  candidate: SourceCandidate,
  curated: boolean,
): "required_supporting" | "supporting" {
  return curated || requiredSourcePattern.test(candidate.url) ||
      candidate.requiredHint
    ? "required_supporting"
    : "supporting";
}

function linkedUrls(
  issuer: string,
  baseUrl: string,
  html: string,
  labels: string[],
  primaryUrl: string,
): SourceCandidate[] {
  const candidates = new Map<string, SourceCandidate>();
  const tokens = identityTokens(labels);
  const primaryPath = new URL(primaryUrl).pathname.replace(/\/$/, "");
  for (const match of html.matchAll(anchorPattern)) {
    try {
      const raw = new URL(match[1] ?? match[2] ?? match[3] ?? "", baseUrl)
        .toString();
      const url = canonicalOfficialUrl(issuer, raw);
      const anchorText = (match[4] ?? "").replace(/<[^>]*>/g, " ")
        .replace(/&(?:amp|nbsp);/gi, " ").replace(/\s+/g, " ").trim()
        .slice(0, 256);
      const candidatePath = new URL(url).pathname.toLowerCase();
      const sameProductPath = candidatePath === primaryPath.toLowerCase() ||
        candidatePath.startsWith(`${primaryPath.toLowerCase()}/`);
      const namesTargetProduct = tokens.length > 0 &&
        tokens.every((token) => candidatePath.includes(token));
      if (
        (relevantPath.test(url) || requiredAnchorPattern.test(anchorText) ||
          relevantAnchorPattern.test(anchorText)) &&
        !unsafePath.test(url) && (sameProductPath || namesTargetProduct)
      ) {
        const existing = candidates.get(url);
        const anchorTexts = [
          ...new Set([
            existing?.anchorText ?? "",
            anchorText,
          ].filter(Boolean)),
        ].sort();
        candidates.set(url, {
          url,
          anchorText: anchorTexts.join(" ").slice(0, 256),
          requiredHint: existing?.requiredHint === true ||
            requiredAnchorPattern.test(anchorText),
        });
      }
    } catch {
      // Only approved issuer URLs enter the supporting queue.
    }
  }
  return [...candidates.values()].sort((left, right) =>
    left.url.localeCompare(right.url)
  );
}

async function benefitDocument(
  resource: OfficialFetchResult,
  requestedUrl = resource.canonicalUrl,
): Promise<BenefitDocument> {
  return {
    sourceUrl: requestedUrl,
    finalUrl: resource.canonicalUrl,
    text: await officialResourceText(resource),
    contentHash: resource.contentHash,
  };
}

export async function collectSupportingBenefitDocuments(
  input: SupportingDocumentInput,
): Promise<CollectedSources> {
  const fetchResource = input.fetchOfficialIssuerResource ??
    fetchOfficialIssuerResourceDefault;
  const budget = Math.min(
    MAX_SUPPORTING_LINKS,
    Math.max(0, Math.trunc(input.maximumLinks ?? MAX_SUPPORTING_LINKS)),
  );
  const primaryDocument = await benefitDocument(
    input.primary,
    input.primary.canonicalUrl,
  );
  const documents = primaryDocument.text.trim() ? [primaryDocument] : [];
  const attempts: SourceAttemptInput[] = [{
    requestedUrl: input.primary.canonicalUrl,
    finalUrl: input.primary.canonicalUrl,
    role: "primary",
    status: primaryDocument.text.trim() ? "success" : "failed",
    httpStatus: 200,
    ...(primaryDocument.text.trim()
      ? { contentHash: input.primary.contentHash }
      : {
        errorCode: input.primary.contentType === "application/pdf"
          ? "corrupt_pdf"
          : "empty_document",
      }),
    attemptedAt: input.primary.retrievedAt,
  }];
  const recordRequiredOverflow = async (
    url: string,
    attemptedAt: string,
  ): Promise<void> => {
    if (
      attempts.some((attempt) =>
        attempt.role === "required_supporting" &&
        attempt.errorCode === "required_source_overflow"
      )
    ) return;
    if (attempts.length >= MAX_SUPPORTING_LINKS + 1) {
      const removable = attempts.findLastIndex((attempt) =>
        attempt.role === "supporting"
      );
      const index = removable >= 0 ? removable : attempts.length - 1;
      const [removed] = attempts.splice(index, 1);
      const removedUrl = boundedSourceUrl(
        removed.finalUrl ?? removed.requestedUrl,
      );
      const documentIndex = documents.findLastIndex((document) =>
        boundedSourceUrl(document.finalUrl ?? document.sourceUrl) === removedUrl
      );
      if (documentIndex >= 0) documents.splice(documentIndex, 1);
    }
    attempts.push({
      requestedUrl: url,
      role: "required_supporting",
      status: "failed",
      errorCode: "required_source_overflow",
      attemptedAt,
    });
  };
  const seen = new Set([input.primary.canonicalUrl]);
  const exactUrls = exactSupportingUrls(input.issuer, input.identityLabels);
  const exactSet = new Set(
    exactUrls.map((url) => canonicalOfficialUrl(input.issuer, url)),
  );
  const initialCandidates = [
    ...[...exactSet].map((url) => ({
      url,
      anchorText: "curated exact source",
      requiredHint: true,
    })),
    ...linkedUrls(
      input.issuer,
      input.primary.canonicalUrl,
      input.primary.text,
      input.identityLabels,
      input.primary.canonicalUrl,
    ),
  ];
  const uniqueInitial = initialCandidates.filter((candidate, index, all) =>
    all.findIndex((item) => item.url === candidate.url) === index
  ).map((candidate) => ({
    ...candidate,
    url: canonicalOfficialUrl(input.issuer, candidate.url),
    depth: 1,
    role: sourceRole(candidate, exactSet.has(candidate.url)),
  })).sort((left, right) =>
    Number(right.role === "required_supporting") -
    Number(left.role === "required_supporting")
  );
  const initialRequired = uniqueInitial.filter((candidate) =>
    candidate.role === "required_supporting"
  );
  const initialOverflow = initialRequired.length > MAX_SUPPORTING_LINKS;
  const initialLimit = initialOverflow
    ? MAX_SUPPORTING_LINKS - 1
    : MAX_SUPPORTING_LINKS;
  const queue = uniqueInitial.slice(0, initialLimit);
  if (initialOverflow) {
    await recordRequiredOverflow(
      initialRequired[initialLimit].url,
      new Date().toISOString(),
    );
  }
  const scheduled = new Set(queue.map((candidate) => candidate.url));
  const queueLimit = (): number =>
    MAX_SUPPORTING_LINKS -
    Number(attempts.some((attempt) =>
      attempt.errorCode === "required_source_overflow"
    ));
  let fetched = 0;
  const upgradeRequired = async (
    url: string,
    attemptedAt: string,
    position: number,
  ): Promise<void> => {
    let represented = false;
    for (const attempt of attempts) {
      if (attempt.requestedUrl !== url) continue;
      attempt.role = "required_supporting";
      represented = true;
    }
    const queuedIndex = queue.findIndex((candidate) => candidate.url === url);
    if (queuedIndex >= 0) {
      queue[queuedIndex].role = "required_supporting";
      represented = true;
      if (queuedIndex > position + 1) {
        const [upgraded] = queue.splice(queuedIndex, 1);
        queue.splice(position + 1, 0, upgraded);
      }
    }
    if (!represented && seen.has(url)) {
      await recordRequiredOverflow(url, attemptedAt);
    }
  };
  for (let position = 0; position < queue.length; position++) {
    const current = queue[position];
    if (seen.has(current.url)) continue;
    seen.add(current.url);
    if (fetched >= budget) {
      if (current.role === "required_supporting") {
        attempts.push({
          requestedUrl: current.url,
          role: current.role,
          status: "failed",
          errorCode: "fetch_budget_exhausted",
          attemptedAt: new Date().toISOString(),
        });
      }
      continue;
    }
    fetched += 1;
    if (
      input.requestDeadlineAt !== undefined &&
      Date.now() >= input.requestDeadlineAt
    ) {
      if (current.role === "required_supporting") {
        attempts.push({
          requestedUrl: current.url,
          role: current.role,
          status: "failed",
          errorCode: "deadline_exceeded",
          attemptedAt: new Date().toISOString(),
        });
      }
      continue;
    }
    let resource: OfficialFetchResult;
    try {
      resource = await fetchResource({
        issuer: input.issuer,
        url: current.url,
        contentPurpose: "document",
        maxBytes: 1024 * 1024,
      });
    } catch (error) {
      attempts.push({
        requestedUrl: current.url,
        role: current.role,
        status: "failed",
        errorCode: sanitizedSourceErrorCode(error),
        attemptedAt: new Date().toISOString(),
      });
      continue;
    }
    const document = await benefitDocument(resource, current.url);
    if (document.text.trim()) {
      documents.push(document);
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "success",
        httpStatus: 200,
        contentHash: resource.contentHash,
        attemptedAt: resource.retrievedAt,
      });
    } else {
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "failed",
        httpStatus: 200,
        errorCode: resource.contentType === "application/pdf"
          ? "corrupt_pdf"
          : "empty_document",
        attemptedAt: resource.retrievedAt,
      });
    }
    if (
      current.depth < MAX_SUPPORTING_DEPTH &&
      resource.contentType !== "application/pdf"
    ) {
      for (
        const candidate of linkedUrls(
          input.issuer,
          resource.canonicalUrl,
          resource.text,
          input.identityLabels,
          input.primary.canonicalUrl,
        )
      ) {
        const discovered = {
          ...candidate,
          depth: current.depth + 1,
          role: sourceRole(candidate, false),
        };
        if (discovered.role === "required_supporting") {
          await upgradeRequired(
            discovered.url,
            resource.retrievedAt,
            position,
          );
        }
        if (!seen.has(candidate.url) && !scheduled.has(candidate.url)) {
          if (
            queue.length >= queueLimit() &&
            discovered.role === "required_supporting"
          ) {
            const replaceable = queue.findLastIndex((item, index) =>
              index > position && item.role === "supporting"
            );
            if (replaceable >= 0) {
              scheduled.delete(queue[replaceable].url);
              queue.splice(replaceable, 1);
            } else {
              if (position + 1 < queue.length) {
                scheduled.delete(queue.at(-1)!.url);
                queue.pop();
              }
              await recordRequiredOverflow(
                discovered.url,
                resource.retrievedAt,
              );
            }
          }
          if (queue.length >= queueLimit()) continue;
          scheduled.add(discovered.url);
          if (discovered.role === "required_supporting") {
            queue.splice(position + 1, 0, discovered);
          } else {
            queue.push(discovered);
          }
        }
      }
    }
  }
  return { documents, attempts };
}
