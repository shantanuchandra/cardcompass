import {
  canonicalBenefitHash,
  type CanonicalBenefitInput,
  canonicalConditionObject,
  canonicalExclusions,
  canonicalValueConfig,
  cardScopedBenefitKey,
} from "./benefit_contract.ts";
import {
  redactSensitiveUrlsInText,
  redactSensitiveUrlsInValue,
  safeHttpsDisplayUrl,
} from "./benefit_source_privacy.ts";

export type BenefitDocument = {
  /** Full canonical URL requested by trusted fetch code; never persisted. */
  sourceUrl: string;
  /** Redirect-resolved canonical URL used only for redacted presentation. */
  finalUrl?: string;
  text: string;
  contentHash?: string;
};

export type BenefitProposal = {
  /** Existing live benefits row UUID; never used as canonical proposal identity. */
  liveBenefitId?: string;
  benefitId?: string;
  offerSubject?: string;
  dedupeKey: string;
  title: string;
  description: string;
  category: string;
  valueType?: string;
  value?: number;
  rate?: number;
  cap?: number;
  threshold?: number;
  valueConfig?: Record<string, unknown>;
  partners?: string[];
  frequency?: string;
  period?: string;
  restrictions: string[];
  exclusions: string[];
  effectiveFrom?: string;
  effectiveTo?: string;
  sourceUrl: string;
  sourceUrls?: string[];
  sourceIdentity?: string;
  sourceIdentities?: string[];
  sourceExcerpt: string;
  contentHash: string;
  parserVersion: string;
  confidence: Record<string, number>;
  evidence: Record<string, string>;
  warnings: string[];
};

export type BenefitProposalV6 =
  & Omit<BenefitProposal, "dedupeKey" | "valueConfig" | "exclusions">
  & {
    benefitId: string;
    offerSubject: string;
    dedupeKey: string;
    conditionHash: string;
    valueConfig: Record<string, unknown>;
    exclusions: Record<string, unknown>;
  };

export type BenefitComparisonProposal = BenefitProposal | BenefitProposalV6;

export type BenefitDiff = {
  additions: BenefitComparisonProposal[];
  modifications: Array<{
    current: BenefitComparisonProposal;
    proposed: BenefitComparisonProposal;
  }>;
  possibleRemovals: Array<{
    benefit: BenefitComparisonProposal;
    informational: true;
  }>;
  unchanged: Array<{
    current: BenefitComparisonProposal;
    proposed: BenefitComparisonProposal;
  }>;
  conflicts: Array<{
    code:
      | "ambiguous_benefit_match"
      | "conflicting_proposed_terms"
      | "dedupe_key_condition_mismatch";
    current?: BenefitComparisonProposal[];
    proposed: BenefitComparisonProposal[];
  }>;
};

function safeSourceUrl(value: unknown): string {
  return safeHttpsDisplayUrl(value) ?? "invalid-source";
}

function canonicalRequestedSourceUrl(value: unknown): string | null {
  try {
    const url = new URL(String(value ?? ""));
    if (
      url.protocol !== "https:" || !url.hostname || url.username ||
      url.password || url.hash
    ) return null;
    url.searchParams.sort();
    return url.toString().replace(/\/$/, "");
  } catch {
    return null;
  }
}

async function sha256SourceIdentity(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function currentBenefitProposal(
  row: Record<string, any>,
): BenefitComparisonProposal | null {
  const benefit = row.benefit ?? row.benefits ?? row;
  if (!benefit || typeof benefit !== "object" || !benefit.dedupe_key) {
    return null;
  }
  const rawConfig =
    benefit.value_config && typeof benefit.value_config === "object"
      ? benefit.value_config
      : {};
  const config = redactSensitiveUrlsInValue(rawConfig) as Record<string, any>;
  const canonicalV6 = String(benefit.dedupe_key).startsWith(
    "card-benefit-v2:",
  );
  const persistedExclusions = config.exclusions ?? benefit.exclusions;
  const canonicalExclusionTerms = persistedExclusions &&
      typeof persistedExclusions === "object" &&
      !Array.isArray(persistedExclusions) &&
      (persistedExclusions as Record<string, any>).additional &&
      typeof (persistedExclusions as Record<string, any>).additional ===
        "object" &&
      Array.isArray(
        (persistedExclusions as Record<string, any>).additional.source_terms,
      )
    ? (persistedExclusions as Record<string, any>).additional.source_terms.map(
      String,
    )
    : [];
  const proposal = {
    ...(benefit.benefit_id
      ? { liveBenefitId: String(benefit.benefit_id) }
      : {}),
    ...(canonicalV6 ? { benefitId: String(benefit.dedupe_key) } : {}),
    dedupeKey: String(benefit.dedupe_key),
    title: redactSensitiveUrlsInText(
      String(benefit.title ?? "Existing benefit"),
    ),
    description: redactSensitiveUrlsInText(
      String(benefit.description ?? ""),
    ).slice(0, 500),
    category: redactSensitiveUrlsInText(
      String(benefit.benefit_category ?? "other"),
    ),
    ...(benefit.benefit_type
      ? { valueType: redactSensitiveUrlsInText(String(benefit.benefit_type)) }
      : {}),
    ...(Number.isFinite(Number(config.value))
      ? { value: Number(config.value) }
      : {}),
    ...(Number.isFinite(Number(config.rate))
      ? { rate: Number(config.rate) }
      : {}),
    ...(Number.isFinite(Number(config.cap)) ? { cap: Number(config.cap) } : {}),
    ...(Number.isFinite(Number(config.threshold))
      ? { threshold: Number(config.threshold) }
      : {}),
    ...(config.frequency ? { frequency: String(config.frequency) } : {}),
    ...(config.period ? { period: String(config.period) } : {}),
    valueConfig: config,
    ...(Array.isArray(benefit.partners) && benefit.partners.length > 0
      ? {
        partners: benefit.partners.map((partner: unknown) =>
          redactSensitiveUrlsInText(String(partner))
        ),
      }
      : {}),
    restrictions: Array.isArray(config.restrictions)
      ? config.restrictions.map(String).slice(0, 32)
      : [],
    exclusions: !canonicalV6 && Array.isArray(persistedExclusions)
      ? persistedExclusions.map(String)
      : !canonicalV6
      ? canonicalExclusionTerms
      : boundedCanonicalExclusions(
        persistedExclusions ?? canonicalExclusionTerms,
      ),
    ...(benefit.valid_from
      ? { effectiveFrom: String(benefit.valid_from) }
      : {}),
    ...(benefit.valid_until
      ? { effectiveTo: String(benefit.valid_until) }
      : {}),
    sourceUrl: safeSourceUrl(benefit.source_url),
    sourceExcerpt: redactSensitiveUrlsInText(
      String(benefit.description ?? ""),
    ).slice(0, 500),
    contentHash: "current-approved-benefit",
    parserVersion: "current-approved-benefit",
    confidence: {},
    evidence: {},
    warnings: [],
  } as BenefitComparisonProposal;
  if (
    proposal.benefitId && typeof config.offer_subject === "string" &&
    config.offer_subject.trim()
  ) proposal.offerSubject = config.offer_subject.trim().slice(0, 256);
  return proposal;
}

type ParsedFields = Pick<
  BenefitProposal,
  | "category"
  | "valueType"
  | "value"
  | "rate"
  | "cap"
  | "threshold"
  | "valueConfig"
  | "partners"
  | "frequency"
  | "period"
  | "restrictions"
  | "exclusions"
  | "effectiveFrom"
  | "effectiveTo"
>;

type ParsedBenefit = ParsedFields & {
  title: string;
  description: string;
  sourceUrl: string;
  sourceIdentity?: string;
  sourceExcerpt: string;
  contentHash: string;
  parserVersion: string;
  confidence: Record<string, number>;
  evidence: Record<string, string>;
  warnings: string[];
};

type TrustedBenefitDocument = BenefitDocument & { sourceIdentity?: string };

function normalize(value: string): string {
  return value.toLowerCase().replace(/\s+/g, " ").trim();
}

function stableHash(value: string): string {
  // A deterministic, runtime-independent content identifier. This is not used for security.
  let first = 0x811c9dc5;
  let second = 0x01000193;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    first = Math.imul(first ^ code, 0x01000193) >>> 0;
    second = Math.imul(second ^ (code + index), 0x27d4eb2d) >>> 0;
  }
  return `benefit-${first.toString(16).padStart(8, "0")}${
    second.toString(16).padStart(8, "0")
  }`;
}

function sanitize(value: string): string {
  return redactSensitiveUrlsInText(value)
    .replace(/(?<!\d)(?:\d[\s-]*){6,}(?!\d)/g, "[redacted]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 500);
}

function readableText(value: string): string {
  return redactSensitiveUrlsInText(value)
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(
      /<a\b[^>]*\bhref=["']([^"']*(?:bookmyshow|district|zomato|pvr|inox|cinepolis)[^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi,
      "$2 $1",
    )
    .replace(/<\/(?:p|div|li|dd|dt|h[1-6]|tr)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&#8377;|&#x20b9;/gi, "₹")
    .replace(/[ \t]+/g, " ")
    .replace(/\n\s*\n+/g, "\n")
    .trim();
}

function decimal(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const parsed = Number(value.replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : undefined;
}

function money(text: string): number | undefined {
  return decimal(
    text.match(/(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.\d{1,2})?)/i)?.[1],
  );
}

function period(text: string): string | undefined {
  const matched = text.match(
    /\bper\s+(statement\s+month|calendar\s+month|month|quarter|year|annum|week|day)\b/i,
  )?.[1];
  if (!matched) return undefined;
  return normalize(matched).replace("annum", "year");
}

function exclusions(text: string): string[] {
  const matched = text.match(
    /\bexcluding\s+(.+?)(?=\s*,?\s*(?:valid\s+(?:until|through)|offer\s+ends?|expires?(?:\s+on)?|effective\s+until|capp?ed\s+(?:at|to)|maximum\s+(?:of\s+)?|up\s+to|per\s+(?:statement\s+month|calendar\s+month|month|quarter|year|annum|week|day))\b|[.;]|$)/i,
  )?.[1];
  if (!matched) return [];
  return matched
    .split(/,|\band\b/gi)
    .map((item) => normalize(item.replace(/[.;:]+$/, "")))
    .filter(Boolean);
}

function dateToIso(text: string): string | undefined {
  const matched = text.match(
    /\b(?:valid\s+(?:until|through)|offer\s+ends?|expires?\s+(?:on)?|effective\s+until)\s*(?:on\s*)?(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})\b/i,
  );
  if (!matched) return undefined;
  const month = [
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
  ].indexOf(matched[2].toLowerCase()) + 1;
  return `${matched[3]}-${String(month).padStart(2, "0")}-${
    matched[1].padStart(2, "0")
  }`;
}

function field(
  confidence: Record<string, number>,
  evidence: Record<string, string>,
  key: string,
  excerpt: string,
): void {
  confidence[key] = 0.96;
  evidence[key] = excerpt;
}

function withCommonFields(
  text: string,
  fields: ParsedFields,
): Pick<ParsedBenefit, "confidence" | "evidence"> {
  const sourceExcerpt = sanitize(text);
  const confidence: Record<string, number> = {
    title: 0.92,
    description: 0.92,
    category: 0.9,
  };
  const evidence: Record<string, string> = {
    title: sourceExcerpt,
    description: sourceExcerpt,
    category: sourceExcerpt,
  };
  for (
    const key of [
      "valueType",
      "value",
      "rate",
      "cap",
      "threshold",
      "frequency",
      "period",
      "effectiveFrom",
      "effectiveTo",
    ]
  ) {
    if (fields[key as keyof ParsedFields] !== undefined) {
      field(confidence, evidence, key, sourceExcerpt);
    }
  }
  if (fields.restrictions.length > 0) {
    field(confidence, evidence, "restrictions", sourceExcerpt);
  }
  if (fields.exclusions.length > 0) {
    field(confidence, evidence, "exclusions", sourceExcerpt);
  }
  return { confidence, evidence };
}

function parseCashback(text: string): ParsedFields | null {
  if (!/\bcashback\b/i.test(text)) return null;
  const rate = decimal(
    text.match(/\b([0-9]+(?:\.\d+)?)\s*%\s*cashback\b/i)?.[1],
  );
  const fixedValue = rate === undefined
    ? money(
      text.match(/(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?\s+cashback/i)
        ?.[0] ?? "",
    )
    : undefined;
  if (rate === undefined && fixedValue === undefined) return null;
  const cap = money(
    text.match(
      /\b(?:capp?ed\s+(?:at|to)|maximum\s+(?:of\s+)?|up\s+to)\s*((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i,
    )?.[1] ?? "",
  );
  const restriction = text.match(
    /\bcashback\s+on\s+(.+?)(?=\s*,?\s*(?:capp?ed|excluding|valid|until|per\b)|[.;]|$)/i,
  )?.[1];
  return {
    category: "cashback",
    valueType: "cashback",
    ...(rate === undefined ? { value: fixedValue } : { rate }),
    ...(cap === undefined ? {} : { cap }),
    ...(period(text) === undefined ? {} : { period: period(text) }),
    restrictions: restriction ? [normalize(restriction)] : [],
    exclusions: exclusions(text),
    ...(dateToIso(text) === undefined ? {} : { effectiveTo: dateToIso(text) }),
  };
}

function parseRewards(text: string): ParsedFields | null {
  const matched = text.match(
    /\bearn\s+([0-9]+(?:\.\d+)?)\s+reward\s+points?\b/i,
  );
  if (!matched) return null;
  const thresholdMatch = text.match(
    /\b(?:for\s+every|per)\s*((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i,
  )?.[1];
  const restriction = text.match(
    /\bspent\s+on\s+(.+?)(?=\s*,?\s*(?:valid|until|excluding)|[.;]|$)/i,
  )?.[1];
  const threshold = money(thresholdMatch ?? "");
  const normalizedRestriction = restriction
    ? normalize(restriction)
    : undefined;
  const isMovieReward = normalizedRestriction != null &&
    /\bmovies?\b/i.test(normalizedRestriction);
  return {
    category: "rewards",
    valueType: "reward_points",
    value: decimal(matched[1]),
    ...(threshold === undefined ? {} : { threshold }),
    ...(isMovieReward && threshold !== undefined
      ? {
        valueConfig: {
          category: "movies",
          multiplier: decimal(matched[1]),
          unit: `reward points per Rs. ${threshold}`,
        },
      }
      : {}),
    restrictions: normalizedRestriction ? [normalizedRestriction] : [],
    exclusions: exclusions(text),
    ...(dateToIso(text) === undefined ? {} : { effectiveTo: dateToIso(text) }),
  };
}

function moviePartners(text: string): string[] {
  const partners: string[] = [];
  if (/\bbook\s*my\s*show\b/i.test(text)) partners.push("BookMyShow");
  if (/\bdistrict\b/i.test(text)) partners.push("District");
  if (/\bzomato\b/i.test(text)) partners.push("Zomato");
  if (/\bpvr\b/i.test(text)) partners.push("PVR");
  if (/\binox\b/i.test(text)) partners.push("INOX");
  if (/\bcinepolis\b/i.test(text)) partners.push("Cinepolis");
  return partners;
}

function usageLimit(
  text: string,
): { count: number; period: "month" | "quarter" | "year" } | undefined {
  const matched = text.match(
    /\b(?:up\s+to\s+|(?:a\s+)?maximum\s+of\s+)?(once|twice|[0-9]+)\s+(?:times?\s+)?(?:per|in|a)\s+(?:a\s+)?(?:calendar\s+)?(month|quarter|year)\b/i,
  );
  const rawCount = matched?.[1]?.toLowerCase();
  const period = matched?.[2]?.toLowerCase() as
    | "month"
    | "quarter"
    | "year"
    | undefined;
  if (!rawCount || !period) return undefined;
  const count = rawCount === "once"
    ? 1
    : rawCount === "twice"
    ? 2
    : decimal(rawCount);
  return count === undefined ? undefined : { count, period };
}

function cappedAmount(text: string): number | undefined {
  const matched = text.match(
    /\b(?:capp?ed\s+(?:at|to)|maximum(?:\s+discount)?(?:\s+per\s+(?:ticket\s+)?(?:booking|transaction))?(?:\s+(?:is|of))?|up\s+to)\s*((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i,
  )?.[1];
  return money(matched ?? "");
}

function mentionsBogo(text: string): boolean {
  return /\bbuy\s+(?:one|1)\b[\s\S]*\bget\s+(?:one|1|the\s+second|second)\b/i
    .test(text) &&
    /\b(?:free|complimentary)\b/i.test(text);
}

function startsIndependentBenefitClause(text: string): boolean {
  return mentionsBogo(text) ||
    /\b[0-9]+(?:\.[0-9]+)?\s*%\s*(?:off|discount)\b/i.test(text) ||
    /\bget\s+[0-9]+\s+(?:pvr\s+inox\s+)?movie\s+tickets?\s+on\s+every\s+spend\b/i
      .test(text) ||
    (/\b(?:free|complimentary)\b[\s\S]*\bmovie\s+tickets?\b/i.test(text) &&
      /\b(?:year|annual|annum)\b/i.test(text)) ||
    /\b(?:cashback|reward\s+points?|lounge)\b/i.test(text) ||
    /(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?\s*(?:off|discount)\b/i
      .test(text);
}

function adjacentClauses(
  lines: readonly string[],
  index: number,
  maximumLines: number,
): string {
  const clauses = [lines[index]];
  for (const candidate of lines.slice(index + 1, index + maximumLines)) {
    if (startsIndependentBenefitClause(candidate)) break;
    clauses.push(candidate);
  }
  return clauses.join(" ");
}

function parseMovieBenefit(text: string): ParsedFields | null {
  if (
    !/\b(?:movies?|movie\s+tickets?|cinema|book\s*my\s*show|district|zomato|pvr|inox|cinepolis)\b/i
      .test(text)
  ) {
    return null;
  }
  if (
    /\b(?:food\s*(?:&|and)\s*beverages?|f\s*&\s*b)\b/i.test(text) &&
    !/\bmovie\s+tickets?\b/i.test(text)
  ) {
    return null;
  }
  const partners = moviePartners(text);
  const percent = decimal(
    text.match(/\b([0-9]+(?:\.\d+)?)\s*%\s*(?:off|discount)\b/i)?.[1] ??
      text.match(/\bdiscount(?:ed)?\s+(?:of\s+)?([0-9]+(?:\.\d+)?)\s*%\b/i)
        ?.[1],
  );
  if (percent !== undefined) {
    const cap = cappedAmount(text);
    return {
      category: "entertainment",
      valueType: "percent_discount",
      rate: percent,
      valueConfig: {
        category: "movie_tickets",
        discount_type: "percent",
        discount_percent: percent,
        ...(cap === undefined ? {} : { max_discount_per_transaction: cap }),
      },
      partners,
      restrictions: [],
      exclusions: exclusions(text),
    };
  }

  if (mentionsBogo(text)) {
    const cap = cappedAmount(text);
    const usage = usageLimit(text);
    if (cap === undefined || usage === undefined) return null;
    return {
      category: "entertainment",
      valueType: "bogo",
      value: cap,
      frequency: `${usage.count} redemptions`,
      period: usage.period,
      valueConfig: {
        category: "movie_tickets",
        discount_type: "bogo",
        max_discount_per_transaction: cap,
        ...(usage.period === "month" ? { max_usage_per_month: usage.count } : {
          max_usage_per_period: usage.count,
          usage_period: usage.period,
        }),
      },
      partners,
      restrictions: [],
      exclusions: exclusions(text),
    };
  }

  const fixedDiscount = money(
    text.match(
      /((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)\s*(?:off|discount)\b/i,
    )?.[1] ?? "",
  );
  if (fixedDiscount !== undefined) {
    return {
      category: "entertainment",
      valueType: "fixed_discount",
      value: fixedDiscount,
      valueConfig: {
        category: "movie_tickets",
        discount_type: "fixed",
        discount_amount: fixedDiscount,
      },
      partners,
      restrictions: [],
      exclusions: exclusions(text),
    };
  }

  const milestone = text.match(
    /\bget\s+([0-9]+)\s+(?:pvr\s+inox\s+)?movie\s+tickets?\s+on\s+every\s+spend\s+of\s+((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i,
  );
  const ticketValue = text.match(
    /\btickets?\s+worth\s+((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)\s+each\b/i,
  )?.[1];
  if (milestone && ticketValue && /\bmonthly\s+billing\s+cycle\b/i.test(text)) {
    const threshold = money(milestone[2]);
    const rewardValue = money(ticketValue);
    if (threshold === undefined || rewardValue === undefined) return null;
    return {
      category: "entertainment",
      valueType: "milestone",
      value: rewardValue,
      threshold,
      period: "month",
      valueConfig: {
        category: "movie_tickets",
        milestone_type: "monthly",
        threshold_amount: threshold,
        reward_value: rewardValue,
      },
      partners,
      restrictions: [],
      exclusions: exclusions(text),
    };
  }

  if (
    /\b(?:free|complimentary)\b[\s\S]*\bmovie\s+tickets?\b/i.test(text) &&
    /\b(?:year|annual|annum)\b/i.test(text)
  ) {
    const annualCap = money(text);
    if (annualCap === undefined) return null;
    return {
      category: "entertainment",
      valueType: "annual_allowance",
      value: annualCap,
      period: "year",
      valueConfig: {
        category: "movie_tickets",
        unit: "fixed",
        annual_cap: annualCap,
      },
      partners,
      restrictions: [],
      exclusions: exclusions(text),
    };
  }

  return null;
}

function parseLounge(text: string): ParsedFields | null {
  if (!/\b(?:airport\s+)?lounge\b/i.test(text)) return null;
  const beforeLounge = text.match(
    /\b([0-9]+)\s+(?:complimentary\s+)?(?:airport\s+)?lounge\s+(?:access\s+)?visits?\b/i,
  )?.[1];
  const afterLounge = text.match(
    /\b(?:airport\s+)?lounge\s+access\s*:\s*([0-9]+)\s+complimentary\s+visits?\b/i,
  )?.[1];
  const visitCount = beforeLounge ?? afterLounge;
  if (!visitCount) return null;
  const visits = decimal(visitCount);
  return {
    category: "travel",
    valueType: "lounge_access",
    value: visits,
    frequency: `${visitCount} visits`,
    ...(period(text) === undefined ? {} : { period: period(text) }),
    restrictions: [],
    exclusions: exclusions(text),
    ...(dateToIso(text) === undefined ? {} : { effectiveTo: dateToIso(text) }),
  };
}

function parseLine(
  text: string,
  document: TrustedBenefitDocument,
  parserVersion: string,
): ParsedBenefit | null {
  const fields = parseMovieBenefit(text) ?? parseCashback(text) ??
    parseRewards(text) ?? parseLounge(text);
  if (!fields) return null;
  const sourceExcerpt = sanitize(text);
  const { confidence, evidence } = withCommonFields(text, fields);
  const title = fields.valueType === "cashback"
    ? `${fields.rate ?? fields.value} ${
      fields.rate === undefined ? "cashback" : "% cashback"
    }`
    : fields.valueType === "reward_points"
    ? `${fields.value} reward points`
    : fields.valueType === "lounge_access"
    ? `${fields.value} lounge visits`
    : fields.valueType === "percent_discount"
    ? `${fields.rate}% off movie tickets`
    : fields.valueType === "bogo"
    ? "Buy 1 get 1 movie ticket"
    : fields.valueType === "fixed_discount"
    ? `₹${fields.value} off movie tickets`
    : fields.valueType === "milestone"
    ? `₹${fields.value} movie ticket milestone`
    : `₹${fields.value} annual movie tickets`;
  return {
    ...fields,
    title,
    description: sourceExcerpt,
    sourceUrl: safeSourceUrl(document.finalUrl ?? document.sourceUrl),
    ...(document.sourceIdentity
      ? { sourceIdentity: document.sourceIdentity }
      : {}),
    sourceExcerpt,
    contentHash: document.contentHash ?? stableHash(normalize(document.text)),
    parserVersion,
    confidence,
    evidence,
    warnings: [],
  };
}

function canonicalJson(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, canonicalJson(item)]),
    );
  }
  return value;
}

function comparisonExclusions(benefit: {
  exclusions: unknown;
  benefitId?: string;
}): unknown {
  return !Array.isArray(benefit.exclusions) ||
      benefit.benefitId?.startsWith("card-benefit-v2:")
    ? canonicalJson(canonicalExclusions(benefit.exclusions))
    : benefit.exclusions.map((item) => normalize(String(item))).sort();
}

function conditionKey(benefit: ParsedFields | BenefitProposalV6): string {
  const hasStructuredValue = benefit.valueConfig !== undefined &&
    Object.keys(benefit.valueConfig).length > 0;
  return JSON.stringify({
    category: benefit.category,
    valueType: benefit.valueType,
    // Movie proposals persist their commercial terms in value_config. The
    // flat parser fields are a transient projection of those same terms and
    // are not stored in benefits, so comparing both creates false conflicts
    // on the next identical crawl.
    value: hasStructuredValue ? undefined : benefit.value,
    rate: hasStructuredValue ? undefined : benefit.rate,
    cap: hasStructuredValue ? undefined : benefit.cap,
    threshold: hasStructuredValue ? undefined : benefit.threshold,
    valueConfig: canonicalJson(benefit.valueConfig),
    partners: benefit.partners?.map(normalize).sort(),
    frequency: hasStructuredValue || benefit.frequency === undefined
      ? undefined
      : normalize(benefit.frequency),
    period: hasStructuredValue || benefit.period === undefined
      ? undefined
      : normalize(benefit.period),
    restrictions: benefit.restrictions.map(normalize).sort(),
    exclusions: comparisonExclusions(benefit),
    effectiveFrom: benefit.effectiveFrom,
    effectiveTo: benefit.effectiveTo,
  });
}

function semanticKey(
  benefit: Pick<
    BenefitComparisonProposal,
    | "category"
    | "valueType"
    | "partners"
    | "restrictions"
    | "exclusions"
    | "offerSubject"
  >,
): string {
  if (benefit.offerSubject) {
    return `offer-subject:${benefit.offerSubject}`;
  }
  return JSON.stringify({
    category: normalize(benefit.category),
    valueType: benefit.valueType === undefined
      ? undefined
      : normalize(benefit.valueType),
    partners: benefit.partners?.map(normalize).sort(),
    restrictions: benefit.restrictions.map(normalize).sort(),
    exclusions: comparisonExclusions(benefit),
  });
}

function conflictSubjectKey(
  benefit: Pick<
    BenefitComparisonProposal,
    "category" | "valueType" | "offerSubject"
  >,
): string {
  return benefit.offerSubject ?? JSON.stringify({
    category: normalize(benefit.category),
    valueType: benefit.valueType === undefined
      ? undefined
      : normalize(benefit.valueType),
  });
}

export function offerSubjectForProposal(
  benefit: Pick<BenefitProposal, "category" | "valueType" | "sourceExcerpt">,
): string {
  const text = normalize(benefit.sourceExcerpt);
  const qualifier = benefit.valueType === "lounge_access"
    ? (/\bdomestic\b/.test(text)
      ? "domestic"
      : /\binternational\b/.test(text)
      ? "international"
      : "general")
    : benefit.category === "cashback" || benefit.category === "rewards"
    ? [
      "dining",
      "fuel",
      "grocery",
      "groceries",
      "travel",
      "movies",
      "movie",
      "online",
      "international",
      "utility",
    ].map((term) => ({ term, index: text.search(new RegExp(`\\b${term}\\b`)) }))
      .filter((candidate) => candidate.index >= 0)
      .sort((left, right) => left.index - right.index)[0]?.term ?? "general"
    : benefit.category === "entertainment"
    ? "movie_tickets"
    : "general";
  const canonicalQualifier = ({
    grocery: "grocery",
    groceries: "grocery",
    movie: "movie",
    movies: "movie",
  } as Record<string, string>)[qualifier] ?? qualifier;
  return `${normalize(benefit.category)}:${
    normalize(benefit.valueType ?? "benefit")
  }:${canonicalQualifier}`;
}

function sourceIdentity(benefit: BenefitComparisonProposal): string {
  return /^[0-9a-f]{64}$/i.test(benefit.sourceIdentity ?? "")
    ? benefit.sourceIdentity!.toLowerCase()
    : benefit.sourceUrl;
}

function boundedTerms(values: unknown): string[] {
  return (Array.isArray(values) ? values : values == null ? [] : [values])
    .flatMap((value) => typeof value === "string" ? [normalize(value)] : [])
    .filter(Boolean).slice(0, 32).map((value) => value.slice(0, 500));
}

function boundedCanonicalExclusions(value: unknown): Record<string, unknown> {
  const canonical = canonicalExclusions(value);
  const additional = canonical.additional as Record<string, unknown>;
  return {
    additional: {
      source_terms: boundedTerms(additional.source_terms),
    },
    categories: boundedTerms(canonical.categories),
    days: boundedTerms(canonical.days),
    mcc_codes: boundedTerms(canonical.mcc_codes),
    merchants: boundedTerms(canonical.merchants),
    transaction_types: boundedTerms(canonical.transaction_types),
  };
}

function isCanonicalV6Proposal(
  benefit: BenefitComparisonProposal,
): boolean {
  return benefit.benefitId?.startsWith("card-benefit-v2:") === true;
}

function sorted<T extends { dedupeKey: string }>(benefits: T[]): T[] {
  return [...benefits].sort((left, right) =>
    left.dedupeKey.localeCompare(right.dedupeKey)
  );
}

/**
 * Extracts only terms that state a concrete benefit. This intentionally does not
 * turn headings or implied eligibility into values, caps, or merchant restrictions.
 */
function parsedGroundedBenefits(
  documents: TrustedBenefitDocument[],
  parserVersion: string,
): ParsedBenefit[] {
  return documents.flatMap((source) => {
    const document = { ...source, text: readableText(source.text) };
    const lines = document.text
      .split(/(?:\r?\n|(?<=[!?])\s+|(?<=\.)\s+(?=[A-Z]))/)
      .map((line) => line.trim())
      .filter(Boolean);
    return lines.flatMap((line, index) => {
      const direct = parseLine(line, document, parserVersion);
      if (
        direct?.valueType === "percent_discount" &&
        direct.valueConfig?.max_discount_per_transaction === undefined
      ) {
        const assembled = parseLine(
          adjacentClauses(lines, index, 4),
          document,
          parserVersion,
        );
        if (
          assembled?.valueConfig?.max_discount_per_transaction !== undefined
        ) {
          return [assembled];
        }
      }
      if (
        direct?.valueType === "annual_allowance" &&
        (direct.partners?.length ?? 0) === 0
      ) {
        const assembled = parseLine(
          adjacentClauses(lines, index, 7),
          document,
          parserVersion,
        );
        if ((assembled?.partners?.length ?? 0) > 0) return [assembled!];
      }
      if (direct) return [direct];
      const isMilestoneLead =
        /\bget\s+[0-9]+\s+(?:pvr\s+inox\s+)?movie\s+tickets?\s+on\s+every\s+spend\b/i
          .test(line);
      if (!mentionsBogo(line) && !isMilestoneLead) {
        return [];
      }
      const clauses = [line];
      for (const candidate of lines.slice(index + 1, index + 7)) {
        if (startsIndependentBenefitClause(candidate)) break;
        clauses.push(candidate);
      }
      const assembled = parseLine(clauses.join(" "), document, parserVersion);
      return assembled ? [assembled] : [];
    });
  });
}

export function extractGroundedBenefits(
  documents: BenefitDocument[],
  parserVersion: string,
): BenefitProposal[] {
  const parsed = parsedGroundedBenefits(documents, parserVersion);
  const byKey = new Map<string, ParsedBenefit[]>();
  for (const benefit of parsed) {
    const key = stableHash(conditionKey(benefit));
    byKey.set(key, [...(byKey.get(key) ?? []), benefit]);
  }

  const semanticGroups = new Map<string, string[]>();
  for (const [key, benefits] of byKey) {
    const semantic = semanticKey(benefits[0]);
    semanticGroups.set(semantic, [
      ...(semanticGroups.get(semantic) ?? []),
      key,
    ]);
  }

  return sorted([...byKey.entries()].map(([dedupeKey, matches]) => {
    const representative = [...matches].sort((left, right) =>
      left.sourceUrl.localeCompare(right.sourceUrl)
    )[0];
    const sources = [
      ...new Set(matches.map((item) =>
        item.sourceUrl
      )),
    ].sort();
    const conflict =
      (semanticGroups.get(semanticKey(representative)) ?? []).length > 1;
    return {
      ...representative,
      dedupeKey,
      sourceUrl: sources[0],
      sourceUrls: sources,
      warnings: conflict ? ["conflicting_official_terms"] : [],
    };
  }));
}

/**
 * Projects the existing deterministic parser into the v6 card-scoped contract.
 * v5 deliberately remains on the synchronous legacy proposal shape for rollback.
 */
export async function extractGroundedBenefitsV6(
  documents: BenefitDocument[],
  parserVersion: "benefits-v6",
  cardId: string,
): Promise<BenefitProposalV6[]> {
  const trustedDocuments = (await Promise.all(documents.map(
    async (document): Promise<TrustedBenefitDocument | null> => {
      const requestedUrl = canonicalRequestedSourceUrl(document.sourceUrl);
      const finalUrl = canonicalRequestedSourceUrl(
        document.finalUrl ?? document.sourceUrl,
      );
      if (!requestedUrl || !finalUrl) return null;
      return {
        sourceUrl: requestedUrl,
        finalUrl,
        text: document.text,
        contentHash: document.contentHash,
        sourceIdentity: await sha256SourceIdentity(requestedUrl),
      };
    },
  ))).filter((document): document is TrustedBenefitDocument =>
    document !== null
  );
  const parsed = parsedGroundedBenefits(trustedDocuments, parserVersion);
  const canonical = parsed.filter((benefit) =>
    !/\b(?:no\s+longer\s+available|discontinued)\b/i.test(
      benefit.sourceExcerpt,
    ) &&
    !/\bup\s+to\s+(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?\s+cashback\b/i
      .test(benefit.sourceExcerpt)
  );
  const grouped = new Map<
    string,
    Array<ParsedBenefit & { offerSubject: string }>
  >();
  for (const benefit of canonical) {
    const offerSubject = offerSubjectForProposal(benefit);
    const key = `${offerSubject}:${stableHash(conditionKey(benefit))}`;
    grouped.set(key, [
      ...(grouped.get(key) ?? []),
      { ...benefit, offerSubject },
    ]);
  }
  const projected = [...grouped.values()].map((matches) => {
    const representative = [...matches].sort((left, right) =>
      left.sourceUrl.localeCompare(right.sourceUrl)
    )[0];
    const sourceUrls = [
      ...new Set(matches.map((item) =>
        item.sourceUrl
      )),
    ]
      .sort();
    const sourceIdentities = [
      ...new Set(matches.flatMap((item) =>
        /^[0-9a-f]{64}$/i.test(item.sourceIdentity ?? "")
          ? [item.sourceIdentity!.toLowerCase()]
          : []
      )),
    ].sort();
    return {
      ...representative,
      sourceUrl: sourceUrls[0],
      sourceUrls,
      ...(sourceIdentities.length > 0
        ? {
          sourceIdentity: sourceIdentities[0],
          sourceIdentities,
        }
        : {}),
    };
  });
  return await Promise.all(projected.map(async (benefit) => {
    const subject = benefit.offerSubject;
    const restrictions = boundedTerms(benefit.restrictions);
    const exclusions = boundedTerms(benefit.exclusions);
    const input: CanonicalBenefitInput = {
      title: benefit.title,
      description: benefit.description,
      category: benefit.category,
      benefitType: benefit.valueType ?? null,
      semanticKey: subject,
      value: benefit.value,
      rate: benefit.rate,
      cap: benefit.cap,
      threshold: benefit.threshold,
      frequency: benefit.frequency,
      period: benefit.period,
      valueConfig: benefit.valueConfig,
      exclusions,
      restrictions,
      partners: benefit.partners,
      validFrom: benefit.effectiveFrom,
      validUntil: benefit.effectiveTo,
    };
    const conditionHash = await canonicalBenefitHash([input]);
    const dedupeKey = await cardScopedBenefitKey(cardId, input);
    return {
      ...benefit,
      offerSubject: subject,
      benefitId: dedupeKey,
      dedupeKey,
      conditionHash,
      valueConfig: {
        ...canonicalValueConfig(input),
        offer_subject: subject,
        restrictions: canonicalConditionObject(input).restrictions,
        exclusions: boundedCanonicalExclusions(input.exclusions),
      },
      restrictions,
      exclusions: boundedCanonicalExclusions(input.exclusions),
    };
  }));
}

/**
 * Computes a review-only diff. `possibleRemovals` deliberately contains no action
 * field, so absence from a crawl cannot be approved as a destructive mutation.
 */
export function diffBenefits(
  current: BenefitComparisonProposal[],
  proposed: BenefitComparisonProposal[],
): BenefitDiff {
  const currentByKey = new Map<string, BenefitComparisonProposal[]>();
  const proposedByKey = new Map<string, BenefitComparisonProposal[]>();
  for (const benefit of current) {
    currentByKey.set(benefit.dedupeKey, [
      ...(currentByKey.get(benefit.dedupeKey) ?? []),
      benefit,
    ]);
  }
  for (const benefit of proposed) {
    proposedByKey.set(benefit.dedupeKey, [
      ...(proposedByKey.get(benefit.dedupeKey) ?? []),
      benefit,
    ]);
  }
  const unchanged: BenefitDiff["unchanged"] = [];
  const conflicts: BenefitDiff["conflicts"] = [];
  const allDedupeKeys = new Set([
    ...currentByKey.keys(),
    ...proposedByKey.keys(),
  ]);
  for (const key of allDedupeKeys) {
    const currentMatches = sorted(currentByKey.get(key) ?? []);
    const proposedMatches = sorted(proposedByKey.get(key) ?? []);
    if (
      new Set(currentMatches.map(conditionKey)).size < 2 &&
      new Set(proposedMatches.map(conditionKey)).size < 2
    ) continue;
    conflicts.push({
      code: "dedupe_key_condition_mismatch",
      ...(currentMatches.length > 0 ? { current: currentMatches } : {}),
      proposed: proposedMatches,
    });
    currentByKey.delete(key);
    proposedByKey.delete(key);
  }
  const proposedBySemantic = new Map<string, BenefitComparisonProposal[]>();
  for (const benefit of proposed) {
    const key = semanticKey(benefit);
    proposedBySemantic.set(key, [
      ...(proposedBySemantic.get(key) ?? []),
      benefit,
    ]);
  }
  const conflictedDedupeKeys = new Set<string>();
  for (const [key, candidates] of proposedBySemantic) {
    if (
      new Set(candidates.map(conditionKey)).size < 2 ||
      new Set(candidates.map(sourceIdentity)).size < 2
    ) continue;
    const currentMatches = current.filter((benefit) =>
      semanticKey(benefit) === key
    );
    conflicts.push({
      code: "conflicting_proposed_terms",
      ...(currentMatches.length > 0 ? { current: sorted(currentMatches) } : {}),
      proposed: sorted(candidates),
    });
    for (const benefit of candidates) proposedByKey.delete(benefit.dedupeKey);
    for (const benefit of candidates) {
      conflictedDedupeKeys.add(benefit.dedupeKey);
    }
    for (const benefit of currentMatches) {
      currentByKey.delete(benefit.dedupeKey);
    }
  }
  const proposedByConflictSubject = new Map<
    string,
    BenefitComparisonProposal[]
  >();
  for (const benefit of proposed) {
    if (
      conflictedDedupeKeys.has(benefit.dedupeKey) ||
      !isCanonicalV6Proposal(benefit)
    ) continue;
    const key = conflictSubjectKey(benefit);
    proposedByConflictSubject.set(key, [
      ...(proposedByConflictSubject.get(key) ?? []),
      benefit,
    ]);
  }
  for (const [key, candidates] of proposedByConflictSubject) {
    if (
      new Set(candidates.map(semanticKey)).size < 2 ||
      new Set(candidates.map(sourceIdentity)).size < 2
    ) continue;
    const currentMatches = current.filter((benefit) =>
      conflictSubjectKey(benefit) === key
    );
    conflicts.push({
      code: "conflicting_proposed_terms",
      ...(currentMatches.length > 0 ? { current: sorted(currentMatches) } : {}),
      proposed: sorted(candidates),
    });
    for (const benefit of candidates) proposedByKey.delete(benefit.dedupeKey);
    for (const benefit of currentMatches) {
      currentByKey.delete(benefit.dedupeKey);
    }
  }
  const sharedDedupeKeys = [...currentByKey.keys()].filter((key) =>
    proposedByKey.has(key)
  ).sort();
  for (const key of sharedDedupeKeys) {
    const currentMatches = sorted(currentByKey.get(key)!);
    const proposedMatches = sorted(proposedByKey.get(key)!);
    const currentConditions = new Set(currentMatches.map(conditionKey));
    const proposedConditions = new Set(proposedMatches.map(conditionKey));
    if (
      currentConditions.size !== 1 ||
      proposedConditions.size !== 1 ||
      [...currentConditions][0] !== [...proposedConditions][0]
    ) {
      conflicts.push({
        code: "dedupe_key_condition_mismatch",
        current: currentMatches,
        proposed: proposedMatches,
      });
      currentByKey.delete(key);
      proposedByKey.delete(key);
      continue;
    }
    unchanged.push({
      current: currentMatches[0],
      proposed: proposedMatches[0],
    });
    currentByKey.delete(key);
    proposedByKey.delete(key);
  }

  const currentBySemantic = new Map<string, BenefitComparisonProposal[]>();
  const unmatchedProposedBySemantic = new Map<
    string,
    BenefitComparisonProposal[]
  >();
  for (const benefits of currentByKey.values()) {
    for (const benefit of benefits) {
      const key = semanticKey(benefit);
      currentBySemantic.set(key, [
        ...(currentBySemantic.get(key) ?? []),
        benefit,
      ]);
    }
  }
  for (const benefits of proposedByKey.values()) {
    for (const benefit of benefits) {
      const key = semanticKey(benefit);
      unmatchedProposedBySemantic.set(key, [
        ...(unmatchedProposedBySemantic.get(key) ?? []),
        benefit,
      ]);
    }
  }

  const modifications: BenefitDiff["modifications"] = [];
  for (
    const key of [...currentBySemantic.keys()].filter((key) =>
      unmatchedProposedBySemantic.has(key)
    ).sort()
  ) {
    const currentMatches = sorted(currentBySemantic.get(key)!);
    const proposedMatches = sorted(unmatchedProposedBySemantic.get(key)!);
    if (currentMatches.length === 1 && proposedMatches.length === 1) {
      modifications.push({
        current: currentMatches[0],
        proposed: proposedMatches[0],
      });
      currentByKey.delete(currentMatches[0].dedupeKey);
      proposedByKey.delete(proposedMatches[0].dedupeKey);
    } else {
      conflicts.push({
        code: "ambiguous_benefit_match",
        current: currentMatches,
        proposed: proposedMatches,
      });
      for (const benefit of currentMatches) {
        currentByKey.delete(benefit.dedupeKey);
      }
      for (const benefit of proposedMatches) {
        proposedByKey.delete(benefit.dedupeKey);
      }
    }
  }

  for (const benefits of unmatchedProposedBySemantic.values()) {
    const unmatched = sorted(
      benefits.filter((benefit) => proposedByKey.has(benefit.dedupeKey)),
    );
    if (
      unmatched.length > 1 &&
      new Set(unmatched.map(sourceIdentity)).size > 1
    ) {
      conflicts.push({
        code: "conflicting_proposed_terms",
        proposed: unmatched,
      });
      for (const benefit of unmatched) proposedByKey.delete(benefit.dedupeKey);
    }
  }

  const additions = sorted([...proposedByKey.values()].flat());
  const possibleRemovals = sorted([...currentByKey.values()].flat()).map((
    benefit,
  ) => ({ benefit, informational: true as const }));
  return { additions, modifications, possibleRemovals, unchanged, conflicts };
}
