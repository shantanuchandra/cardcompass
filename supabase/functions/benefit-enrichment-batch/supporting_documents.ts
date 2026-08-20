import { type BenefitDocument } from "../_shared/benefit_enrichment.ts";
import {
  redactSensitiveUrlsInText,
  safeHttpsDisplayUrl,
} from "../_shared/benefit_source_privacy.ts";
import { assessOfficialCardIdentity } from "../_shared/card_discovery.ts";
import {
  approvedStoredQueryParameters,
  canonicalOfficialRequestUrl,
  createOfficialRobotsCache,
  fetchOfficialIssuerObservation,
  fetchOfficialIssuerResource as fetchOfficialIssuerResourceDefault,
  type OfficialFetchInput,
  type OfficialFetchResult,
  officialResourceText,
  type OfficialRobotsCache,
  requireOfficialFetchBody,
} from "../_shared/official_issuer_fetch.ts";
import {
  boundedSourceUrl,
  sanitizedSourceErrorCode,
  type SourceAttemptInput,
  sourceIdentityDigest,
} from "./crawl_policy.ts";

const MAX_SUPPORTING_LINKS = 8;
const MAX_SUPPORTING_DEPTH = 2;
const relevantPath =
  /(?:credit[-_/ ]?cards?|cards?[-_/ ]?credit|benefits?|fees?|charges?|rewards?|terms?|conditions?|mitc)(?:$|[/?=&_.-])/i;
const unsafePath =
  /(?:^|[/?=&_.-])(?:login|apply|application|track)(?:$|[/?=&_.-])/i;
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
  primaryAttempts?: SourceAttemptInput[];
  identityLabels: string[];
  fetchOfficialIssuerResource?: OfficialFetcher;
  maximumLinks?: number;
  requestDeadlineAt?: number;
  parserVersion?: string;
  robotsCache?: OfficialRobotsCache;
};

export type CollectedSources = {
  documents: BenefitDocument[];
  attempts: SourceAttemptInput[];
  expectedRequiredSourceKeys: string[];
  requiredSourceSelectionOverflow: boolean;
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
  rejectionCode?: "unapproved_query" | "invalid_source_url";
};

function requiredSourceHint(href: string, anchorText: string): boolean {
  return requiredSourcePattern.test(href) ||
    requiredAnchorPattern.test(anchorText) ||
    anchorText.trim().toLowerCase() === "curated exact source";
}

function sourceRole(
  candidate: SourceCandidate,
  curated: boolean,
): "required_supporting" | "supporting" {
  return curated || requiredSourcePattern.test(candidate.url) ||
      candidate.requiredHint
    ? "required_supporting"
    : "supporting";
}

export function canonicalRequiredReplayAnchorText(value: string): string {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.toLowerCase() === "curated exact source") {
    return "curated exact source";
  }
  const known = normalized.match(
    /\b(?:most\s+important\s+terms(?:\s+and\s+conditions)?|terms?(?:\s+and\s+conditions)?|conditions?|mitc|fees?|charges?|benefits?|rewards?|supporting\s+(?:material|document))\b/i,
  )?.[0];
  return known?.toLowerCase().slice(0, 96) ?? "";
}

function replayLinksFromClassifierInput(
  issuer: string,
  baseUrl: string,
  html: string,
  curatedUrls: readonly string[] = [],
) {
  let overflow = false;
  const links: NonNullable<BenefitDocument["replayLinks"]> = [];
  const candidates: Array<{ url: string; anchorText: string }> = curatedUrls
    .map((url) => ({ url, anchorText: "curated exact source" }));
  for (const match of html.matchAll(anchorPattern)) {
    const anchorText = (match[4] ?? "").replace(/<[^>]*>/g, " ")
      .replace(/&(?:amp|nbsp);/gi, " ").replace(/\s+/g, " ").trim()
      .slice(0, 256);
    const encodedHref = match[1] ?? match[2] ?? match[3] ?? "";
    const hrefValue = encodedHref
      .replace(/&amp;|&#0*38;|&#x0*26;/gi, "&")
      .replace(/&quot;|&#0*34;|&#x0*22;/gi, '"')
      .replace(/&apos;|&#0*39;|&#x0*27;/gi, "'");
    if (!requiredSourceHint(hrefValue, anchorText)) continue;
    try {
      const raw = new URL(hrefValue, baseUrl).toString();
      let url = raw;
      try {
        url = canonicalOfficialRequestUrl(
          issuer,
          raw,
          approvedStoredQueryParameters(raw),
        );
      } catch {
        // The live classifier retains the raw identity for a rejected required
        // query/path. Replay must still be able to prove it was not omitted.
      }
      candidates.push({ url, anchorText });
    } catch {
      // Invalid hrefs remain decisive failed attempts in the live crawl. They
      // have no safe display URL or canonical identity to persist.
    }
  }
  candidates.sort((left, right) => left.url.localeCompare(right.url));
  for (const candidate of candidates) {
    const href = safeHttpsDisplayUrl(candidate.url);
    if (!href) continue;
    let resourceIdentityHash: string;
    try {
      resourceIdentityHash = sourceIdentityDigest(candidate.url);
    } catch {
      continue;
    }
    if (
      links.some((link) => link.resourceIdentityHash === resourceIdentityHash)
    ) continue;
    if (links.length >= MAX_SUPPORTING_LINKS) {
      overflow = true;
      continue;
    }
    links.push({
      href,
      anchorText: canonicalRequiredReplayAnchorText(candidate.anchorText),
      resourceIdentityHash,
    });
  }
  return { links, overflow };
}

/** Reuses the live required-source predicate over the retained link inputs. */
export function classifyRequiredReplaySourceKeys(
  documents: readonly BenefitDocument[],
): { keys: string[]; overflow: boolean } {
  const keys = new Set<string>();
  let overflow = false;
  for (const document of documents) {
    overflow ||= document.replayLinkOverflow === true;
    for (const link of document.replayLinks ?? []) {
      if (requiredSourceHint(link.href, link.anchorText)) {
        keys.add(link.resourceIdentityHash);
      }
    }
  }
  return { keys: [...keys].sort(), overflow };
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
    const anchorText = (match[4] ?? "").replace(/<[^>]*>/g, " ")
      .replace(/&(?:amp|nbsp);/gi, " ").replace(/\s+/g, " ").trim()
      .slice(0, 256);
    const requiredHint = requiredAnchorPattern.test(anchorText);
    const encodedHref = match[1] ?? match[2] ?? match[3] ?? "";
    const href = encodedHref
      .replace(/&amp;|&#0*38;|&#x0*26;/gi, "&")
      .replace(/&quot;|&#0*34;|&#x0*22;/gi, '"')
      .replace(/&apos;|&#0*39;|&#x0*27;/gi, "'");
    const decisiveRequired = requiredSourceHint(href, anchorText);
    let raw: string;
    try {
      raw = new URL(href, baseUrl).toString();
    } catch {
      if (decisiveRequired) {
        candidates.set(`invalid:${href.slice(0, 512)}`, {
          url: href,
          anchorText,
          requiredHint: true,
          rejectionCode: "invalid_source_url",
        });
      }
      continue;
    }
    const candidatePath = new URL(raw).pathname.toLowerCase();
    const sameProductPath = candidatePath === primaryPath.toLowerCase() ||
      candidatePath.startsWith(`${primaryPath.toLowerCase()}/`);
    const namesTargetProduct = tokens.length > 0 &&
      tokens.every((token) => candidatePath.includes(token));
    if (decisiveRequired && unsafePath.test(raw)) {
      candidates.set(`rejected:${raw}`, {
        url: raw,
        anchorText,
        requiredHint: true,
        rejectionCode: "invalid_source_url",
      });
      continue;
    }
    if (
      !((relevantPath.test(raw) || decisiveRequired ||
        relevantAnchorPattern.test(anchorText)) &&
        !unsafePath.test(raw) &&
        (decisiveRequired || sameProductPath || namesTargetProduct))
    ) continue;
    try {
      const url = canonicalOfficialRequestUrl(
        issuer,
        raw,
        approvedStoredQueryParameters(raw),
      );
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
        requiredHint: existing?.requiredHint === true || decisiveRequired,
      });
    } catch (error) {
      const code = sanitizedSourceErrorCode(error);
      candidates.set(`rejected:${raw}`, {
        url: raw,
        anchorText,
        requiredHint: decisiveRequired,
        rejectionCode: code === "unapproved_query"
          ? "unapproved_query"
          : "invalid_source_url",
      });
    }
  }
  return [...candidates.values()].sort((left, right) =>
    left.url.localeCompare(right.url)
  );
}

async function benefitDocument(
  resource: OfficialFetchResult,
  requestedUrl = resource.submittedUrl,
): Promise<BenefitDocument> {
  const body = requireOfficialFetchBody(resource);
  return {
    sourceUrl: requestedUrl,
    finalUrl: boundedSourceUrl(body.canonicalUrl),
    requestedResourceIdentityHash: sourceIdentityDigest(requestedUrl),
    finalResourceIdentityHash: body.finalResourceIdentityHash ??
      sourceIdentityDigest(body.canonicalUrl),
    text: redactSensitiveUrlsInText(await officialResourceText(body)),
    contentHash: body.contentHash,
  };
}

export async function collectSupportingBenefitDocuments(
  input: SupportingDocumentInput,
): Promise<CollectedSources> {
  const fetchResource = input.fetchOfficialIssuerResource ??
    fetchOfficialIssuerResourceDefault;
  const robotsCache = input.robotsCache ?? createOfficialRobotsCache();
  const budget = Math.min(
    MAX_SUPPORTING_LINKS,
    Math.max(0, Math.trunc(input.maximumLinks ?? MAX_SUPPORTING_LINKS)),
  );
  const primary = requireOfficialFetchBody(input.primary);
  const primaryDocument = await benefitDocument(
    primary,
    input.primary.submittedUrl,
  );
  const documents = primaryDocument.text.trim() ? [primaryDocument] : [];
  const attempts: SourceAttemptInput[] = input.primaryAttempts
    ? [...input.primaryAttempts]
    : [{
      requestedUrl: input.primary.submittedUrl,
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
      ...(input.primary.finalResourceIdentityHash
        ? {
          finalResourceIdentityHash: input.primary.finalResourceIdentityHash,
        }
        : {}),
    }];
  // Keep classification output independent from fetch attempts: dropping an
  // attempt must never erase the fact that a discovered source was required.
  const expectedRequiredSourceKeys = new Set<string>();
  let requiredSourceSelectionOverflow = false;
  const rememberRequiredSource = (url: string): void => {
    try {
      const key = sourceIdentityDigest(url);
      if (expectedRequiredSourceKeys.has(key)) return;
      if (expectedRequiredSourceKeys.size >= MAX_SUPPORTING_LINKS) {
        requiredSourceSelectionOverflow = true;
        return;
      }
      expectedRequiredSourceKeys.add(key);
    } catch {
      // Invalid required URLs remain explicit failed attempts, which keeps the
      // crawl incomplete even though no stable logical identity can be made.
    }
  };
  const recordRequiredOverflow = async (
    url: string,
    attemptedAt: string,
  ): Promise<void> => {
    rememberRequiredSource(url);
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
  const seen = new Set([
    input.primary.submittedUrl,
    input.primary.canonicalUrl,
  ]);
  const exactUrls = exactSupportingUrls(input.issuer, input.identityLabels);
  const exactSet = new Set(
    exactUrls.map((url) =>
      canonicalOfficialRequestUrl(
        input.issuer,
        url,
        approvedStoredQueryParameters(url),
      )
    ),
  );
  const initialCandidates: SourceCandidate[] = [
    ...[...exactSet].map((url) => ({
      url,
      anchorText: "curated exact source",
      requiredHint: true,
    })),
    ...linkedUrls(
      input.issuer,
      input.primary.canonicalUrl,
      input.primary.text ?? "",
      input.identityLabels,
      input.primary.canonicalUrl,
    ),
  ];
  const primaryReplayLinks = replayLinksFromClassifierInput(
    input.issuer,
    input.primary.canonicalUrl,
    input.primary.text ?? "",
    [...exactSet],
  );
  primaryDocument.replayLinks = primaryReplayLinks.links;
  primaryDocument.replayLinkOverflow = primaryReplayLinks.overflow;
  const rejectedInitial = initialCandidates.filter((candidate) =>
    candidate.rejectionCode
  );
  for (const candidate of rejectedInitial) {
    if (sourceRole(candidate, false) === "required_supporting") {
      rememberRequiredSource(candidate.url);
    }
    attempts.push({
      requestedUrl: candidate.url,
      role: sourceRole(candidate, false),
      status: "failed",
      errorCode: candidate.rejectionCode,
      attemptedAt: new Date().toISOString(),
    });
  }
  const uniqueInitial = initialCandidates.filter((candidate) =>
    !candidate.rejectionCode
  ).filter((candidate, index, all) =>
    all.findIndex((item) => item.url === candidate.url) === index
  ).map((candidate) => ({
    ...candidate,
    url: canonicalOfficialRequestUrl(
      input.issuer,
      candidate.url,
      approvedStoredQueryParameters(candidate.url),
    ),
    depth: 1,
    role: sourceRole(candidate, exactSet.has(candidate.url)),
  })).sort((left, right) =>
    Number(right.role === "required_supporting") -
    Number(left.role === "required_supporting")
  );
  const initialRequired = uniqueInitial.filter((candidate) =>
    candidate.role === "required_supporting"
  );
  initialRequired.forEach((candidate) => rememberRequiredSource(candidate.url));
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
    rememberRequiredSource(url);
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
      if (input.fetchOfficialIssuerResource) {
        resource = await fetchResource({
          issuer: input.issuer,
          url: current.url,
          contentPurpose: "document",
          maxBytes: 1024 * 1024,
          deadlineAt: input.requestDeadlineAt,
          allowedQueryParameters: approvedStoredQueryParameters(current.url),
          robotsCache,
        });
      } else {
        const observation = await fetchOfficialIssuerObservation({
          issuer: input.issuer,
          url: current.url,
          contentPurpose: "document",
          maxBytes: 1024 * 1024,
          parserVersion: input.parserVersion ?? "benefits-v6",
          maxAttempts: 3,
          maxBackoffMs: 30_000,
          deadlineAt: input.requestDeadlineAt,
          enforceRobots: true,
          allowedQueryParameters: approvedStoredQueryParameters(current.url),
          robotsCache,
        });
        for (const attempt of observation.attempts.slice(0, -1)) {
          attempts.push({
            requestedUrl: current.url,
            role: current.role,
            status: attempt.status === 304 ? "not_modified" : "failed",
            ...(attempt.status !== undefined
              ? { httpStatus: attempt.status }
              : {}),
            ...(attempt.code ? { errorCode: attempt.code } : {}),
            attemptedAt: attempt.attemptedAt,
          });
        }
        if (observation.disposition !== "success" || !observation.result) {
          const terminal = observation.attempts.at(-1);
          attempts.push({
            requestedUrl: current.url,
            role: current.role,
            status: terminal?.status === 304 ? "not_modified" : "failed",
            ...(terminal?.status !== undefined
              ? { httpStatus: terminal.status }
              : {}),
            errorCode: terminal?.code ?? observation.reviewReason ??
              "unreachable",
            attemptedAt: terminal?.attemptedAt ?? new Date().toISOString(),
          });
          continue;
        }
        resource = observation.result;
      }
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
    try {
      resource = requireOfficialFetchBody(resource);
    } catch (error) {
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "failed",
        ...(resource.status ? { httpStatus: resource.status } : {}),
        ...(resource.finalResourceIdentityHash
          ? { finalResourceIdentityHash: resource.finalResourceIdentityHash }
          : {}),
        errorCode: sanitizedSourceErrorCode(error),
        attemptedAt: resource.retrievedAt,
      });
      continue;
    }
    const resourceText = await officialResourceText(resource);
    if (!resourceText.trim()) {
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "failed",
        httpStatus: resource.status,
        errorCode: resource.contentType === "application/pdf"
          ? "corrupt_pdf"
          : "empty_document",
        ...(resource.finalResourceIdentityHash
          ? { finalResourceIdentityHash: resource.finalResourceIdentityHash }
          : {}),
        attemptedAt: resource.retrievedAt,
      });
      continue;
    }
    const identityAssessment = assessOfficialCardIdentity(
      resourceText,
      input.issuer,
      input.identityLabels,
    );
    if (identityAssessment.status !== "match") {
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "failed",
        httpStatus: resource.status,
        contentHash: resource.contentHash,
        ...(resource.finalResourceIdentityHash
          ? { finalResourceIdentityHash: resource.finalResourceIdentityHash }
          : {}),
        errorCode: identityAssessment.status === "ambiguous"
          ? "identity_ambiguous"
          : "identity_mismatch",
        attemptedAt: resource.retrievedAt,
      });
      continue;
    }
    const nestedCandidates = current.depth < MAX_SUPPORTING_DEPTH &&
        resource.contentType !== "application/pdf"
      ? linkedUrls(
        input.issuer,
        resource.canonicalUrl,
        resource.text ?? "",
        input.identityLabels,
        input.primary.canonicalUrl,
      )
      : [];
    const document = await benefitDocument(resource, current.url);
    const documentReplayLinks = replayLinksFromClassifierInput(
      input.issuer,
      resource.canonicalUrl,
      resource.text ?? "",
    );
    document.replayLinks = documentReplayLinks.links;
    document.replayLinkOverflow = documentReplayLinks.overflow;
    if (document.text.trim()) {
      documents.push(document);
      attempts.push({
        requestedUrl: current.url,
        finalUrl: resource.canonicalUrl,
        role: current.role,
        status: "success",
        httpStatus: 200,
        contentHash: resource.contentHash,
        ...(resource.finalResourceIdentityHash
          ? { finalResourceIdentityHash: resource.finalResourceIdentityHash }
          : {}),
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
        ...(resource.finalResourceIdentityHash
          ? { finalResourceIdentityHash: resource.finalResourceIdentityHash }
          : {}),
        attemptedAt: resource.retrievedAt,
      });
    }
    if (nestedCandidates.length > 0) {
      for (const candidate of nestedCandidates) {
        const discovered = {
          ...candidate,
          depth: current.depth + 1,
          role: sourceRole(candidate, false),
        };
        if (discovered.role === "required_supporting") {
          rememberRequiredSource(candidate.url);
        }
        if (candidate.rejectionCode) {
          if (!seen.has(candidate.url) && !scheduled.has(candidate.url)) {
            seen.add(candidate.url);
            attempts.push({
              requestedUrl: candidate.url,
              role: discovered.role,
              status: "failed",
              errorCode: candidate.rejectionCode,
              attemptedAt: resource.retrievedAt,
            });
          }
          continue;
        }
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
  return {
    documents,
    attempts,
    expectedRequiredSourceKeys: [...expectedRequiredSourceKeys].sort(),
    requiredSourceSelectionOverflow: requiredSourceSelectionOverflow ||
      documents.some((document) => document.replayLinkOverflow === true),
  };
}
