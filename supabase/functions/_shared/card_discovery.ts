import {
  redactSensitiveUrlsInText,
  redactSensitiveUrlsInValue,
} from "./benefit_source_privacy.ts";

export type CanonicalCardIdentity = {
  issuer: string;
  cardName: string;
  network: string | null;
  aliases: string[];
};

export type OfficialCardIdentityAssessment = {
  status: "match" | "mismatch" | "ambiguous" | "unproven";
  identity: CanonicalCardIdentity | null;
  candidateKeys: string[];
};

export type CatalogUrlIdentityCandidate = {
  cardId: string;
  issuer: string;
  cardName: string;
  aliases: string[];
  network?: string | null;
  cardType: string;
};

export type AutomaticGateInput = {
  issuer: string;
  officialUrl: string;
  officialProduct: string;
  statementProducts: string[];
  confidence: number;
  catalogCandidateCount: number;
  conflicts: string[];
};

export type CardDiscoveryReasonCode =
  | "invalid_url"
  | "unapproved_domain"
  | "issuer_mismatch"
  | "not_product_page"
  | "unsafe_redirect"
  | "fetch_timeout"
  | "unsupported_content"
  | "identity_conflict"
  | "review_required";

type DiscoveryJobPublicSource = {
  id: string;
  status: string;
  resolved_card_id?: string | null;
  failure_category?: string | null;
  next_retry_at?: string | null;
};

export function publicReasonCode(error: unknown): CardDiscoveryReasonCode {
  const message = error instanceof Error ? error.message : String(error);
  const known: CardDiscoveryReasonCode[] = [
    "invalid_url",
    "unapproved_domain",
    "issuer_mismatch",
    "not_product_page",
    "unsafe_redirect",
    "fetch_timeout",
    "unsupported_content",
    "identity_conflict",
    "review_required",
  ];
  if (known.includes(message as CardDiscoveryReasonCode)) {
    return message as CardDiscoveryReasonCode;
  }
  if (
    (error instanceof DOMException && error.name === "TimeoutError") ||
    /timeout|official_fetch_(?:408|429|5\d\d)/i.test(message)
  ) {
    return "fetch_timeout";
  }
  if (/redirect/i.test(message)) return "unsafe_redirect";
  if (/content/i.test(message)) return "unsupported_content";
  return "review_required";
}

export function publicDiscoveryResult(job: DiscoveryJobPublicSource) {
  return {
    job_id: job.id,
    status: job.status,
    resolved_card_id: job.resolved_card_id ?? null,
    reason_code: job.status === "resolved"
      ? null
      : publicReasonCode(job.failure_category ?? "review_required"),
    retry_after: job.next_retry_at ?? null,
  };
}

export function reviewRequiredJobPatch(
  reviewItemId: string,
  updatedAt: string,
) {
  return {
    status: "review_required",
    review_item_id: reviewItemId,
    failure_category: null,
    next_retry_at: null,
    updated_at: updatedAt,
  };
}

export function terminalDiscoveryStatus(status: unknown): boolean {
  return status === "resolved" || status === "rejected";
}

const issuerDomains: Record<string, string[]> = {
  "Axis Bank": ["axis.bank.in", "axisbank.com"],
  "HDFC Bank": ["hdfcbank.com", "hdfc.bank.in"],
  "ICICI Bank": ["icicibank.com", "icici.bank.in"],
  "Kotak Bank": ["kotak.com", "kotak.bank.in"],
  "IndusInd Bank": ["indusind.com", "indusind.bank.in"],
  HSBC: ["hsbc.co.in"],
  "SBI Card": ["sbicard.com"],
  "IDFC FIRST Bank": ["idfcfirstbank.com", "idfcfirst.bank.in"],
  "Yes Bank": ["yesbank.in", "yes.bank.in"],
  "AU Small Finance Bank": ["aubank.in", "au.bank.in"],
  "RBL Bank": ["rbl.bank", "rblbank.com"],
  "Bank of Baroda": ["bobfinancial.com"],
  "Punjab National Bank": ["pnbcard.in", "pnbindia.in"],
  "Standard Chartered": ["sc.com"],
  "American Express": ["americanexpress.com"],
};

const issuerAliases: Record<string, string[]> = {
  "Axis Bank": ["axis"],
  "HDFC Bank": ["hdfc"],
  "ICICI Bank": ["icici"],
  "Kotak Bank": ["kotak", "mahindra"],
  "IndusInd Bank": ["indusind"],
  HSBC: ["hsbc"],
  "Punjab National Bank": ["pnb", "punjab", "national"],
  "SBI Card": ["sbi"],
  "AU Small Finance Bank": ["au"],
};

const genericTokens = new Set([
  "bank",
  "credit",
  "card",
  "statement",
  "your",
  "the",
  "for",
  "club",
  "amex",
  "american",
  "express",
  "visa",
  "mastercard",
  "rupay",
]);

const metadataBoilerplateTokens = new Set([
  ...genericTokens,
  "cards",
  "portal",
  "navigation",
  "service",
  "services",
  "online",
  "banking",
  "website",
  "official",
  "home",
  "homepage",
  "center",
  "centre",
  "platform",
  "all",
  "overview",
  "compare",
  "comparison",
  "option",
  "options",
  "explore",
  "range",
]);

export function isAdminEmail(
  email: string | null | undefined,
  commaSeparatedAllowlist: string | null | undefined,
): boolean {
  if (!email || !commaSeparatedAllowlist) return false;
  const normalized = email.trim().toLowerCase();
  return commaSeparatedAllowlist
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean)
    .includes(normalized);
}

function words(value: string): string[] {
  return value
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function hasMeaningfulMetadataProductToken(
  value: string,
  issuer: string,
): boolean {
  const ignored = new Set(metadataBoilerplateTokens);
  for (const token of words(issuer)) ignored.add(token);
  for (const alias of issuerAliases[issuer] ?? []) ignored.add(alias);
  return words(value).some((token) => !ignored.has(token));
}

export function normalizedProduct(value: string, issuer = ""): string {
  const ignored = new Set(genericTokens);
  for (const alias of issuerAliases[issuer] ?? []) ignored.add(alias);
  return words(value).filter((token) => !ignored.has(token)).join("");
}

function displayProduct(value: string, issuer: string): string {
  const ignored = new Set(genericTokens);
  for (const alias of issuerAliases[issuer] ?? []) ignored.add(alias);
  return words(value)
    .filter((token) => !ignored.has(token))
    .map((token) =>
      token === "eazydiner"
        ? "EazyDiner"
        : `${token[0].toUpperCase()}${token.slice(1)}`
    )
    .join(" ");
}

export function canonicalCardIdentity(
  issuer: string,
  rawProduct: string,
): CanonicalCardIdentity {
  const hasAmex = /\b(?:amex|american\s+express)\b/i.test(rawProduct);
  const cardName = displayProduct(rawProduct, issuer);
  return {
    issuer,
    cardName,
    network: hasAmex || issuer.trim().toLowerCase() === "american express"
      ? "American Express"
      : null,
    aliases: rawProduct.trim() === cardName ? [] : [rawProduct.trim()],
  };
}

function networkFromIdentityText(value: unknown): string | null {
  const text = String(value ?? "");
  if (/\b(?:american\s+express|amex)\b/i.test(text)) {
    return "American Express";
  }
  if (/\bmaster\s*card\b/i.test(text)) return "Mastercard";
  if (/\brupay\b/i.test(text)) return "RuPay";
  if (/\bvisa\b/i.test(text)) return "Visa";
  return null;
}

export function effectiveCatalogNetwork(
  cardName: unknown,
  network: unknown,
  issuer = "",
): string | null {
  const signals = [
    networkFromIdentityText(network),
    networkFromIdentityText(cardName),
    issuer.trim().toLowerCase() === "american express"
      ? "American Express"
      : null,
  ].filter((value): value is string => value !== null);
  const distinct = [...new Set(signals.map((value) => value.toLowerCase()))];
  if (distinct.length > 1) throw new Error("identity_conflict");
  if (signals.length === 0) return null;
  return signals[0];
}

export async function discoveryObservationVersionKey(input: {
  issuer: string;
  product: string;
  submittedUrlHash: string;
  finalUrlHash: string;
  contentHash: string;
  retrievedAt?: string;
}): Promise<string> {
  for (
    const value of [
      input.submittedUrlHash,
      input.finalUrlHash,
      input.contentHash,
    ]
  ) {
    if (!/^[0-9a-f]{64}$/i.test(value)) {
      throw new Error("invalid_observation_identity");
    }
  }
  const identity = [
    input.issuer.trim().toLowerCase(),
    normalizedProduct(input.product, input.issuer) || "unknown",
    input.submittedUrlHash.toLowerCase(),
    input.finalUrlHash.toLowerCase(),
    input.contentHash.toLowerCase(),
  ].join(":");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(identity),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function decodeHtmlText(value: string): string {
  return value
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;|&#34;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function stripTitleMarketing(value: string, issuer: string): string {
  let label = value.trim().replace(/^apply\s+for\s+/i, "");
  const pipeAt = label.lastIndexOf("|");
  if (pipeAt >= 0) {
    const suffix = label.slice(pipeAt + 1).trim();
    if (suffix && normalizedProduct(suffix, issuer).length === 0) {
      label = label.slice(0, pipeAt).trim();
    }
  }
  return label
    .replace(
      /(\b(?:credit\s+)?card)\s+(?:benefits?|features?|terms?(?:\s+and\s+conditions)?|conditions?|rewards?|mitc|fees?|charges?)\b[\s\S]*$/i,
      "$1",
    )
    .replace(
      /\s*[-–—:]\s*(?:best\s+entertainment(?:\s+credit\s+card)?|[0-9]+%\s+fuel\s+cashback|exclusive\s+rewards?\s*(?:&|and)\s*benefits?|benefits?\s*(?:&|and)\s*features?(?:\s*[-–—]\s*apply\s+now)?)\s*$/i,
      "",
    )
    .replace(/\s+with\s+unlimited\s+benefits\s*$/i, "")
    .trim();
}

const weakIdentityAliases = new Set([
  "gold",
  "platinum",
  "classic",
  "signature",
  "infinite",
]);

export function normalizedProductFamily(value: string, issuer: string): string {
  const family = normalizedProduct(
    value.replace(
      /\b(?:visa|master\s*card|rupay|american\s+express|amex|world\s+elite|infinite|signature|world|platinum|gold|select|classic)\b/gi,
      " ",
    ),
    issuer,
  );
  return family || normalizedProduct(value, issuer);
}

function identityKey(value: string, issuer: string): string {
  return normalizedProductFamily(value, issuer);
}

function tierVariantKey(value: string): string | null {
  const normalized = words(value).join(" ");
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
}

function networkVariantKey(value: string): string | null {
  const normalized = words(value).join(" ");
  const family = /\b(?:american express|amex)\b/.test(normalized)
    ? "amex"
    : /\bvisa\b/.test(normalized)
    ? "visa"
    : /\bmaster\s*card\b/.test(normalized)
    ? "mastercard"
    : /\brupay\b/.test(normalized)
    ? "rupay"
    : null;
  const tier = tierVariantKey(value);
  if (family && tier) return `${family}:${tier}`;
  if (family) return family;
  if (tier) return `tier:${tier}`;
  return null;
}

function networkVariantsConflict(values: Array<string | null>): boolean {
  const signals = [
    ...new Set(values.filter((value): value is string => Boolean(value))),
  ];
  const families = new Set(
    signals.filter((value) => !value.startsWith("tier:"))
      .map((value) => value.split(":")[0]),
  );
  if (families.size > 1) return true;
  const tiers = new Set(
    signals.map((value) => value.split(":")[1]).filter(Boolean),
  );
  return tiers.size > 1;
}

function networkVariantMatches(
  actual: string | null,
  expected: string | null,
): boolean {
  if (!expected || !actual) return true;
  if (actual === expected) return true;
  if (expected.startsWith("tier:")) {
    return actual.split(":")[1] === expected.slice(5);
  }
  if (actual.startsWith("tier:")) {
    return expected.split(":")[1] === actual.slice(5);
  }
  const [actualFamily] = actual.split(":");
  const [expectedFamily] = expected.split(":");
  return actualFamily === expectedFamily && !expected.includes(":");
}

function strongExpectedIdentity(value: string, issuer: string): boolean {
  const key = identityKey(value, issuer);
  const variant = networkVariantKey(value);
  return key.length >= 4 &&
    (!weakIdentityAliases.has(key) ||
      (variant !== null && !variant.startsWith("tier:")) ||
      issuer === "American Express");
}

function identityWords(value: string, issuer: string): string[] {
  const ignored = new Set(genericTokens);
  for (const token of words(issuer)) ignored.add(token);
  for (const alias of issuerAliases[issuer] ?? []) ignored.add(alias);
  return words(value).filter((token) => !ignored.has(token));
}

function containsExpectedIdentityPhrase(
  content: string,
  expected: string,
  issuer: string,
): boolean {
  if (!strongExpectedIdentity(expected, issuer)) return false;
  const expectedWords = identityWords(expected, issuer);
  const visibleWords = words(
    decodeHtmlText(
      content.slice(0, 120_000)
        .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
        .replace(/<style\b[\s\S]*?<\/style>/gi, " "),
    ),
  );
  return expectedWords.length > 0 &&
    visibleWords.some((_, index) =>
      expectedWords.every((word, offset) =>
        visibleWords[index + offset] === word
      )
    );
}

function identityFromLabel(
  value: string,
  issuer: string,
): CanonicalCardIdentity | null {
  const decodedLabel = decodeHtmlText(value);
  const rawProduct = redactSensitiveUrlsInText(stripTitleMarketing(
    decodedLabel,
    issuer,
  )).replace(/\[redacted(?:-encoded)?-url\]/g, " ")
    .replace(/\s+/g, " ").trim();
  if (
    !/\bcard\b/i.test(rawProduct) || /\bdebit\b/i.test(rawProduct) ||
    identityKey(rawProduct, issuer).length < 4
  ) return null;
  const withoutNetworkVariant = rawProduct.replace(
    /\b(?:visa|master\s*card|rupay|american\s+express|amex)\b/gi,
    " ",
  ).replace(/\s+/g, " ").trim();
  const identity = canonicalCardIdentity(issuer, withoutNetworkVariant);
  const network = /\brupay\b/i.test(decodedLabel)
    ? "RuPay"
    : /\bvisa\b/i.test(decodedLabel)
    ? "Visa"
    : /\bmaster\s*card\b/i.test(decodedLabel)
    ? "Mastercard"
    : /\b(?:american express|amex)\b/i.test(decodedLabel)
    ? "American Express"
    : identity.network;
  return {
    ...identity,
    network,
    aliases: rawProduct === identity.cardName ? [] : [rawProduct],
  };
}

function strongIdentityLabels(content: string, issuer: string): string[] {
  const labels: string[] = [];
  const add = (value: string, metadata = false) => {
    const label = decodeHtmlText(value);
    if (metadata && !hasMeaningfulMetadataProductToken(label, issuer)) return;
    if (identityFromLabel(label, issuer)) labels.push(label);
  };
  for (const match of content.matchAll(/<title\b[^>]*>([\s\S]*?)<\/title>/gi)) {
    add(match[1] ?? "", true);
  }
  for (
    const match of content.matchAll(
      /<meta[^>]+(?:property|name)=["'](?:og:title|twitter:title)["'][^>]+content=["']([^"']+)["'][^>]*>/gi,
    )
  ) add(match[1] ?? "", true);
  for (
    const match of content.matchAll(
      /<script[^>]+type=["']application\/ld\+json["'][^>]*>[\s\S]*?["']name["']\s*:\s*["']([^"']+)["'][\s\S]*?<\/script>/gi,
    )
  ) add(match[1] ?? "", true);
  for (const match of content.matchAll(/<h[1-2][^>]*>([\s\S]*?)<\/h[1-2]>/gi)) {
    add(match[1] ?? "");
  }
  for (
    const match of content.matchAll(
      /<[^>]+class=["'][^"']*\btitle\b[^"']*["'][^>]*>([\s\S]*?)<\/[^>]+>/gi,
    )
  ) add(match[1] ?? "");

  return labels.slice(0, 32);
}

const relationshipCardLabels = new Set([
  "primary",
  "supplementary",
  "additional",
  "addon",
  "companion",
  "partner",
]);

const bodyIdentityPrefixTokens = new Set([
  "a",
  "an",
  "and",
  "about",
  "each",
  "for",
  "fees",
  "charges",
  "conditions",
  "benefits",
  "of",
  "or",
  "the",
  "terms",
  "to",
  "with",
]);

function targetBodyIdentityLabels(
  content: string,
  issuer: string,
): string[] {
  const visible = decodeHtmlText(
    content.slice(0, 120_000)
      .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
      .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
      .replace(/<nav\b[\s\S]*?<\/nav>/gi, " ")
      .replace(/<(?:title|h[1-2])\b[\s\S]*?<\/(?:title|h[1-2])>/gi, " "),
  );
  const labels: string[] = [];
  for (
    const match of visible.matchAll(
      /\b((?:(?!card\b)[a-z0-9&'-]+\s+){0,6})(?:credit\s+)?card\b/gi,
    )
  ) {
    const candidateWords = words(match[1] ?? "").slice(-7);
    while (
      candidateWords.length > 0 &&
      bodyIdentityPrefixTokens.has(candidateWords[0])
    ) candidateWords.shift();
    if (
      candidateWords.length === 0 ||
      candidateWords.some((word) => relationshipCardLabels.has(word))
    ) continue;
    const label = `${candidateWords.join(" ")} Card`;
    const key = identityKey(label, issuer);
    if (
      !key || relationshipCardLabels.has(key) ||
      !strongExpectedIdentity(label, issuer)
    ) continue;
    labels.push(label);
    if (labels.length === 16) break;
  }
  return labels;
}

export function assessOfficialCardIdentity(
  content: string,
  issuer: string,
  expectedProducts: string[] = [],
): OfficialCardIdentityAssessment {
  const labels = strongIdentityLabels(content, issuer);
  if (expectedProducts.length > 0) {
    labels.push(...targetBodyIdentityLabels(content, issuer));
  }
  const candidates = labels.map((label) => {
    const identity = identityFromLabel(label, issuer)!;
    return {
      identity,
      key: identityKey(identity.cardName, issuer),
      networkKey: networkVariantKey(label),
    };
  });
  for (const expected of expectedProducts) {
    if (!containsExpectedIdentityPhrase(content, expected, issuer)) continue;
    const label = `${expected} Credit Card`;
    const identity = identityFromLabel(label, issuer) ??
      canonicalCardIdentity(issuer, expected);
    candidates.push({
      identity,
      key: identityKey(identity.cardName, issuer),
      networkKey: networkVariantKey(label),
    });
  }
  const productKeys = [...new Set(candidates.map((candidate) => candidate.key))]
    .sort();
  const candidateKeys = [
    ...new Set(
      candidates.map((candidate) =>
        `${candidate.key}${
          candidate.networkKey ? `@${candidate.networkKey}` : ""
        }`
      ),
    ),
  ].sort();
  if (candidateKeys.length === 0) {
    return { status: "unproven", identity: null, candidateKeys };
  }
  if (
    productKeys.length > 1 ||
    networkVariantsConflict(candidates.map((candidate) => candidate.networkKey))
  ) {
    return { status: "ambiguous", identity: null, candidateKeys };
  }
  const identity =
    candidates.find((candidate) => candidate.networkKey?.includes(":"))
      ?.identity ??
      candidates.find((candidate) => candidate.networkKey)?.identity ??
      candidates[0].identity;
  if (expectedProducts.length === 0) {
    return { status: "match", identity, candidateKeys };
  }
  const expected = expectedProducts
    .filter((label) => strongExpectedIdentity(label, issuer))
    .map((label) => ({
      key: identityKey(label, issuer),
      networkKey: networkVariantKey(label),
    }));
  const sameFamily = expected.some((target) => target.key === productKeys[0]);
  const strongExpectedVariants = expected.filter((target) =>
    target.key === productKeys[0] && target.networkKey !== null
  );
  const actualVariants = candidates.map((candidate) => candidate.networkKey)
    .filter((value): value is string => value !== null);
  const strongestVariantMatches = strongExpectedVariants.length === 0
    ? actualVariants.length === 0
    : (actualVariants.length > 0 &&
      actualVariants.every((actual) =>
        strongExpectedVariants.some((target) =>
          networkVariantMatches(actual, target.networkKey)
        )
      ));
  const matchesExpected = sameFamily && strongestVariantMatches;
  return matchesExpected
    ? { status: "match", identity, candidateKeys }
    : { status: "mismatch", identity: null, candidateKeys };
}

export function officialCardIdentityFromHtml(
  html: string,
  issuer: string,
): CanonicalCardIdentity | null {
  return assessOfficialCardIdentity(html, issuer).identity;
}

export function exactOfficialPageIdentity(
  html: string,
  issuer: string,
  expectedProduct: string,
): CanonicalCardIdentity | null {
  const assessment = assessOfficialCardIdentity(
    html,
    issuer,
    [expectedProduct],
  );
  return assessment.status === "match" ? assessment.identity : null;
}

export function selectCatalogUrlIdentityMatch(
  content: string,
  issuer: string,
  candidates: CatalogUrlIdentityCandidate[],
): string | null {
  const matchingIds = new Set<string>();
  for (const candidate of candidates) {
    if (
      candidate.issuer.trim().toLowerCase() !== issuer.trim().toLowerCase() ||
      candidate.cardType.trim().toLowerCase() !== "credit"
    ) continue;
    const expectedProducts = [
      candidate.cardName,
      ...candidate.aliases.filter((alias) =>
        strongExpectedIdentity(alias, issuer)
      ),
    ]
      .filter((value, index, all) => value && all.indexOf(value) === index);
    const identities = expectedProducts
      .map((expected) => exactOfficialPageIdentity(content, issuer, expected))
      .filter((identity): identity is CanonicalCardIdentity =>
        identity !== null
      );
    let storedNetwork: string | null;
    try {
      storedNetwork = effectiveCatalogNetwork(
        candidate.cardName,
        candidate.network,
        candidate.issuer,
      )?.toLowerCase() ?? null;
    } catch {
      continue;
    }
    const storedTier = tierVariantKey(candidate.cardName);
    const networkCompatible = identities.some((identity) => {
      let observedNetwork: string | null;
      try {
        observedNetwork = effectiveCatalogNetwork(
          identity.cardName,
          identity.network,
          identity.issuer,
        )?.toLowerCase() ?? null;
      } catch {
        return false;
      }
      return (!storedNetwork || observedNetwork === storedNetwork) &&
        (!storedTier || tierVariantKey(identity.cardName) === storedTier);
    });
    if (identities.length > 0 && networkCompatible) {
      matchingIds.add(candidate.cardId);
    }
  }
  return matchingIds.size === 1 ? [...matchingIds][0] : null;
}

export async function selectBoundCatalogResourceIdentity(input: {
  submittedResourceIdentityHash?: string;
  finalResourceIdentityHash?: string;
  resourceIdentityHashes?: string[];
  issuer: string;
  content: string;
  lookupCardIds: (resourceIdentityHash: string) => Promise<string[]>;
  loadCandidates: (
    cardIds: string[],
  ) => Promise<CatalogUrlIdentityCandidate[]>;
}): Promise<string | null> {
  const hashes = [
    ...(input.resourceIdentityHashes ?? []),
    input.submittedResourceIdentityHash,
    input.finalResourceIdentityHash,
  ].filter((value): value is string => Boolean(value));
  if (hashes.some((hash) => !/^[0-9a-f]{64}$/i.test(hash))) {
    throw new Error("identity_conflict");
  }
  const distinctHashes = [...new Set(hashes.map((hash) => hash.toLowerCase()))];
  if (distinctHashes.length === 0) return null;
  const resolved = await Promise.all(
    distinctHashes.map(async (hash) => ({
      hash,
      cardIds: [...new Set(await input.lookupCardIds(hash))],
    })),
  );
  if (resolved.some(({ cardIds }) => cardIds.length > 1)) {
    throw new Error("identity_conflict");
  }
  const boundIds = [...new Set(resolved.flatMap(({ cardIds }) => cardIds))];
  if (boundIds.length > 1) throw new Error("identity_conflict");
  if (boundIds.length === 0) return null;
  const matched = selectCatalogUrlIdentityMatch(
    input.content,
    input.issuer,
    await input.loadCandidates(boundIds),
  );
  if (matched !== boundIds[0]) throw new Error("identity_conflict");
  return matched;
}

export function selectSubmittedUrlIdentity(input: {
  html: string;
  issuer: string;
  statementProducts: string[];
}): {
  identity: CanonicalCardIdentity | null;
  statementProducts: string[];
} {
  const statementProducts = input.statementProducts.filter(
    (value) => normalizedProduct(value, input.issuer).length >= 4,
  );
  const identity = officialCardIdentityFromHtml(input.html, input.issuer) ??
    (statementProducts[0]
      ? canonicalCardIdentity(input.issuer, statementProducts[0])
      : null);
  return { identity, statementProducts };
}

export function officialDomainsForIssuer(issuer: string): string[] {
  return issuerDomains[issuer] ?? [];
}

export function allowedOfficialUrl(issuer: string, rawUrl: string): boolean {
  try {
    const url = new URL(rawUrl);
    if (url.protocol !== "https:") return false;
    const hostname = url.hostname.toLowerCase();
    return officialDomainsForIssuer(issuer).some(
      (domain) => hostname === domain || hostname.endsWith(`.${domain}`),
    );
  } catch {
    return false;
  }
}

export function canonicalOfficialUrl(issuer: string, rawUrl: string): string {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    throw new Error("invalid_url");
  }
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("invalid_url");
  }
  if (!allowedOfficialUrl(issuer, url.toString())) {
    throw new Error("unapproved_domain");
  }

  url.hash = "";
  url.port = "";
  url.pathname = url.pathname
    .replace(/\/{2,}/g, "/")
    .replace(/\/$/, "") || "/";

  const kept = [...url.searchParams.entries()]
    .filter(([key]) =>
      !/^utm_/i.test(key) &&
      !["gclid", "fbclid"].includes(key.toLowerCase())
    )
    .sort(([leftKey, leftValue], [rightKey, rightValue]) =>
      leftKey.localeCompare(rightKey) || leftValue.localeCompare(rightValue)
    );
  url.search = "";
  for (const [key, value] of kept) url.searchParams.append(key, value);
  return url.toString();
}

export function evaluateAutomaticCatalogGate(
  input: AutomaticGateInput,
): { autoAdd: boolean; reasons: string[] } {
  const reasons: string[] = [];
  if (!allowedOfficialUrl(input.issuer, input.officialUrl)) {
    reasons.push("unofficial_source");
  }
  if (input.confidence < 0.9) reasons.push("low_confidence");

  const official = normalizedProduct(input.officialProduct, input.issuer);
  if (input.statementProducts.length === 0) {
    reasons.push("missing_statement_signal");
  } else if (
    !input.statementProducts.some((value) => {
      const statement = normalizedProduct(value, input.issuer);
      return statement.length >= 4 && official === statement;
    })
  ) {
    reasons.push("product_mismatch");
  }

  for (const conflict of input.conflicts) {
    if (!reasons.includes(conflict)) reasons.push(conflict);
  }
  if (input.catalogCandidateCount > 1) reasons.push("ambiguous_catalog");
  return { autoAdd: reasons.length === 0, reasons };
}

export function rankOfficialUrls(
  product: string,
  urls: string[],
): string[] {
  const tokens = words(product).filter((token) => !genericTokens.has(token));
  return [...new Set(urls)].sort((left, right) => {
    const score = (url: string) => {
      const normalized = decodeURIComponent(url).toLowerCase();
      const matched = tokens.filter((token) =>
        normalized.includes(token)
      ).length;
      return matched * 100 + (matched === tokens.length ? 1000 : 0) -
        url.length / 1000;
    };
    return score(right) - score(left);
  });
}

export function sanitizeEvidence(value: string): string {
  return redactSensitiveUrlsInText(value)
    .split(/\r?\n/)
    .filter((line) =>
      /credit\s*card|primary\s+card|card\s+ending|amex|visa|mastercard|rupay/i
        .test(line)
    )
    .slice(0, 4)
    .map((line) =>
      line
        .replace(/(?<!\d)(?:\d[\s-]*){6,}(?!\d)/g, "[redacted]")
        .replace(/\s+/g, " ")
        .trim()
    )
    .join("\n");
}

export function sanitizeDiscoveryEvidence(value: unknown): unknown {
  return redactSensitiveUrlsInValue(value);
}
