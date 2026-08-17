export type CanonicalCardIdentity = {
  issuer: string;
  cardName: string;
  network: string | null;
  aliases: string[];
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

export function reviewRequiredJobPatch(reviewItemId: string, updatedAt: string) {
  return {
    status: "review_required",
    review_item_id: reviewItemId,
    failure_category: null,
    next_retry_at: null,
    updated_at: updatedAt,
  };
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
  "Kotak Bank": ["kotak"],
  "IndusInd Bank": ["indusind"],
  HSBC: ["hsbc"],
  "Punjab National Bank": ["pnb", "punjab", "national"],
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

export function isAdminEmail(
  email: string | null | undefined,
  commaSeparatedAllowlist: string | null | undefined,
): boolean {
  if (!email || !commaSeparatedAllowlist) return false;
  const normalized = email.trim().toLowerCase();
  return commaSeparatedAllowlist
    .split(',')
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
    .map((token) => token === "eazydiner"
      ? "EazyDiner"
      : `${token[0].toUpperCase()}${token.slice(1)}`)
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
    network: hasAmex ? "American Express" : null,
    aliases: rawProduct.trim() === cardName ? [] : [rawProduct.trim()],
  };
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
    .replace(/\s+with\s+unlimited\s+benefits\s*$/i, "")
    .trim();
}

export function officialCardIdentityFromHtml(
  html: string,
  issuer: string,
): CanonicalCardIdentity | null {
  const candidates: string[] = [];
  const patterns = [
    {
      pattern: /<title\b[^>]*>([\s\S]*?)<\/title>/gi,
      documentMetadata: true,
    },
    {
      pattern: /<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["'][^>]*>/gi,
      documentMetadata: true,
    },
    {
      pattern: /<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/gi,
      documentMetadata: false,
    },
    {
      pattern: /<[^>]+class=["'][^"']*\btitle\b[^"']*["'][^>]*>([\s\S]*?)<\/[^>]+>/gi,
      documentMetadata: false,
    },
  ];
  for (const source of patterns) {
    for (const match of html.matchAll(source.pattern)) {
      const candidate = stripTitleMarketing(
        decodeHtmlText(match[1] ?? ""),
        issuer,
      );
      if (source.documentMetadata && /\bcredit\s+card\s+portal\b/i.test(candidate)) {
        continue;
      }
      if (/\bcard\b/i.test(candidate) && normalizedProduct(candidate, issuer).length >= 4) {
        candidates.push(candidate);
      }
    }
    if (candidates.length > 0) break;
  }
  const rawProduct = candidates[0];
  if (!rawProduct) return null;
  const identity = canonicalCardIdentity(issuer, rawProduct);
  const network = /\brupay\b/i.test(rawProduct)
    ? "RuPay"
    : /\bvisa\b/i.test(rawProduct)
    ? "Visa"
    : /\bmaster\s*card\b/i.test(rawProduct)
    ? "Mastercard"
    : identity.network;
  return { ...identity, network };
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
  } else if (!input.statementProducts.some((value) => {
    const statement = normalizedProduct(value, input.issuer);
    return statement.length >= 4 &&
      (official === statement || official.includes(statement) || statement.includes(official));
  })) {
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
      const matched = tokens.filter((token) => normalized.includes(token)).length;
      return matched * 100 + (matched === tokens.length ? 1000 : 0) - url.length / 1000;
    };
    return score(right) - score(left);
  });
}

export function sanitizeEvidence(value: string): string {
  return value
    .split(/\r?\n/)
    .filter((line) =>
      /credit\s*card|primary\s+card|card\s+ending|amex|visa|mastercard|rupay/i.test(line)
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
