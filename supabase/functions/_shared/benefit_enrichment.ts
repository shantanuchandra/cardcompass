export type BenefitDocument = {
  sourceUrl: string;
  text: string;
  contentHash?: string;
};

export type BenefitProposal = {
  dedupeKey: string;
  title: string;
  description: string;
  category: string;
  valueType?: string;
  value?: number;
  rate?: number;
  cap?: number;
  threshold?: number;
  frequency?: string;
  period?: string;
  restrictions: string[];
  exclusions: string[];
  effectiveFrom?: string;
  effectiveTo?: string;
  sourceUrl: string;
  sourceUrls?: string[];
  sourceExcerpt: string;
  contentHash: string;
  parserVersion: string;
  confidence: Record<string, number>;
  evidence: Record<string, string>;
  warnings: string[];
};

export type BenefitDiff = {
  additions: BenefitProposal[];
  modifications: Array<{ current: BenefitProposal; proposed: BenefitProposal }>;
  possibleRemovals: Array<{ benefit: BenefitProposal; informational: true }>;
  unchanged: Array<{ current: BenefitProposal; proposed: BenefitProposal }>;
  conflicts: Array<{
    code: "ambiguous_benefit_match" | "conflicting_proposed_terms" | "dedupe_key_condition_mismatch";
    current?: BenefitProposal[];
    proposed: BenefitProposal[];
  }>;
};

type ParsedFields = Pick<
  BenefitProposal,
  | "category"
  | "valueType"
  | "value"
  | "rate"
  | "cap"
  | "threshold"
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
  sourceExcerpt: string;
  contentHash: string;
  parserVersion: string;
  confidence: Record<string, number>;
  evidence: Record<string, string>;
  warnings: string[];
};

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
  return `benefit-${first.toString(16).padStart(8, "0")}${second.toString(16).padStart(8, "0")}`;
}

function sanitize(value: string): string {
  return value
    .replace(/(?<!\d)(?:\d[\s-]*){6,}(?!\d)/g, "[redacted]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 500);
}

function readableText(value: string): string {
  return value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
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
  return decimal(text.match(/(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.\d{1,2})?)/i)?.[1]);
}

function period(text: string): string | undefined {
  const matched = text.match(/\bper\s+(statement\s+month|calendar\s+month|month|quarter|year|annum|week|day)\b/i)?.[1];
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
  const matched = text.match(/\b(?:valid\s+(?:until|through)|offer\s+ends?|expires?\s+(?:on)?|effective\s+until)\s*(?:on\s*)?(\d{1,2})\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})\b/i);
  if (!matched) return undefined;
  const month = [
    "january", "february", "march", "april", "may", "june",
    "july", "august", "september", "october", "november", "december",
  ].indexOf(matched[2].toLowerCase()) + 1;
  return `${matched[3]}-${String(month).padStart(2, "0")}-${matched[1].padStart(2, "0")}`;
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

function withCommonFields(text: string, fields: ParsedFields): Pick<ParsedBenefit, "confidence" | "evidence"> {
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
  for (const key of [
    "valueType", "value", "rate", "cap", "threshold", "frequency", "period",
    "effectiveFrom", "effectiveTo",
  ]) {
    if (fields[key as keyof ParsedFields] !== undefined) field(confidence, evidence, key, sourceExcerpt);
  }
  if (fields.restrictions.length > 0) field(confidence, evidence, "restrictions", sourceExcerpt);
  if (fields.exclusions.length > 0) field(confidence, evidence, "exclusions", sourceExcerpt);
  return { confidence, evidence };
}

function parseCashback(text: string): ParsedFields | null {
  if (!/\bcashback\b/i.test(text)) return null;
  const rate = decimal(text.match(/\b([0-9]+(?:\.\d+)?)\s*%\s*cashback\b/i)?.[1]);
  const fixedValue = rate === undefined
    ? money(text.match(/(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?\s+cashback/i)?.[0] ?? "")
    : undefined;
  if (rate === undefined && fixedValue === undefined) return null;
  const cap = money(text.match(/\b(?:capp?ed\s+(?:at|to)|maximum\s+(?:of\s+)?|up\s+to)\s*((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i)?.[1] ?? "");
  const restriction = text.match(/\bcashback\s+on\s+(.+?)(?=\s*,?\s*(?:capp?ed|excluding|valid|until|per\b)|[.;]|$)/i)?.[1];
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
  const matched = text.match(/\bearn\s+([0-9]+(?:\.\d+)?)\s+reward\s+points?\b/i);
  if (!matched) return null;
  const thresholdMatch = text.match(/\b(?:for\s+every|per)\s*((?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.\d{1,2})?)/i)?.[1];
  const restriction = text.match(/\bspent\s+on\s+(.+?)(?=\s*,?\s*(?:valid|until|excluding)|[.;]|$)/i)?.[1];
  return {
    category: "rewards",
    valueType: "reward_points",
    value: decimal(matched[1]),
    ...(money(thresholdMatch ?? "") === undefined ? {} : { threshold: money(thresholdMatch ?? "") }),
    restrictions: restriction ? [normalize(restriction)] : [],
    exclusions: exclusions(text),
    ...(dateToIso(text) === undefined ? {} : { effectiveTo: dateToIso(text) }),
  };
}

function parseLounge(text: string): ParsedFields | null {
  if (!/\b(?:airport\s+)?lounge\b/i.test(text)) return null;
  const beforeLounge = text.match(/\b([0-9]+)\s+(?:complimentary\s+)?(?:airport\s+)?lounge\s+(?:access\s+)?visits?\b/i)?.[1];
  const afterLounge = text.match(/\b(?:airport\s+)?lounge\s+access\s*:\s*([0-9]+)\s+complimentary\s+visits?\b/i)?.[1];
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

function parseLine(text: string, document: BenefitDocument, parserVersion: string): ParsedBenefit | null {
  const fields = parseCashback(text) ?? parseRewards(text) ?? parseLounge(text);
  if (!fields) return null;
  const sourceExcerpt = sanitize(text);
  const { confidence, evidence } = withCommonFields(text, fields);
  const title = fields.valueType === "cashback"
    ? `${fields.rate ?? fields.value} ${fields.rate === undefined ? "cashback" : "% cashback"}`
    : fields.valueType === "reward_points"
    ? `${fields.value} reward points`
    : `${fields.value} lounge visits`;
  return {
    ...fields,
    title,
    description: sourceExcerpt,
    sourceUrl: document.sourceUrl,
    sourceExcerpt,
    contentHash: document.contentHash ?? stableHash(normalize(document.text)),
    parserVersion,
    confidence,
    evidence,
    warnings: [],
  };
}

function conditionKey(benefit: ParsedFields): string {
  return JSON.stringify({
    category: benefit.category,
    valueType: benefit.valueType,
    value: benefit.value,
    rate: benefit.rate,
    cap: benefit.cap,
    threshold: benefit.threshold,
    frequency: benefit.frequency === undefined ? undefined : normalize(benefit.frequency),
    period: benefit.period === undefined ? undefined : normalize(benefit.period),
    restrictions: benefit.restrictions.map(normalize).sort(),
    exclusions: benefit.exclusions.map(normalize).sort(),
    effectiveFrom: benefit.effectiveFrom,
    effectiveTo: benefit.effectiveTo,
  });
}

function semanticKey(benefit: Pick<BenefitProposal, "category" | "valueType" | "restrictions" | "exclusions">): string {
  return JSON.stringify({
    category: normalize(benefit.category),
    valueType: benefit.valueType === undefined ? undefined : normalize(benefit.valueType),
    restrictions: benefit.restrictions.map(normalize).sort(),
    exclusions: benefit.exclusions.map(normalize).sort(),
  });
}

function sorted<T extends { dedupeKey: string }>(benefits: T[]): T[] {
  return [...benefits].sort((left, right) => left.dedupeKey.localeCompare(right.dedupeKey));
}

/**
 * Extracts only terms that state a concrete benefit. This intentionally does not
 * turn headings or implied eligibility into values, caps, or merchant restrictions.
 */
export function extractGroundedBenefits(
  documents: BenefitDocument[],
  parserVersion: string,
): BenefitProposal[] {
  const parsed = documents.flatMap((source) => {
    const document = { ...source, text: readableText(source.text) };
    return document.text
    .split(/(?:\r?\n|(?<=[.!?])\s+)/)
    .map((line) => parseLine(line.trim(), document, parserVersion))
    .filter((benefit): benefit is ParsedBenefit => benefit !== null);
  });
  const byKey = new Map<string, ParsedBenefit[]>();
  for (const benefit of parsed) {
    const key = stableHash(conditionKey(benefit));
    byKey.set(key, [...(byKey.get(key) ?? []), benefit]);
  }

  const semanticGroups = new Map<string, string[]>();
  for (const [key, benefits] of byKey) {
    const semantic = semanticKey(benefits[0]);
    semanticGroups.set(semantic, [...(semanticGroups.get(semantic) ?? []), key]);
  }

  return sorted([...byKey.entries()].map(([dedupeKey, matches]) => {
    const representative = [...matches].sort((left, right) => left.sourceUrl.localeCompare(right.sourceUrl))[0];
    const sources = [...new Set(matches.map((item) => item.sourceUrl))].sort();
    const conflict = (semanticGroups.get(semanticKey(representative)) ?? []).length > 1;
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
 * Computes a review-only diff. `possibleRemovals` deliberately contains no action
 * field, so absence from a crawl cannot be approved as a destructive mutation.
 */
export function diffBenefits(current: BenefitProposal[], proposed: BenefitProposal[]): BenefitDiff {
  const currentByKey = new Map<string, BenefitProposal[]>();
  const proposedByKey = new Map<string, BenefitProposal[]>();
  for (const benefit of current) {
    currentByKey.set(benefit.dedupeKey, [...(currentByKey.get(benefit.dedupeKey) ?? []), benefit]);
  }
  for (const benefit of proposed) {
    proposedByKey.set(benefit.dedupeKey, [...(proposedByKey.get(benefit.dedupeKey) ?? []), benefit]);
  }
  const unchanged: BenefitDiff["unchanged"] = [];
  const conflicts: BenefitDiff["conflicts"] = [];
  const allDedupeKeys = new Set([...currentByKey.keys(), ...proposedByKey.keys()]);
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
  const proposedBySemantic = new Map<string, BenefitProposal[]>();
  for (const benefit of proposed) {
    const key = semanticKey(benefit);
    proposedBySemantic.set(key, [...(proposedBySemantic.get(key) ?? []), benefit]);
  }
  for (const [key, candidates] of proposedBySemantic) {
    if (new Set(candidates.map(conditionKey)).size < 2) continue;
    const currentMatches = current.filter((benefit) => semanticKey(benefit) === key);
    conflicts.push({
      code: "conflicting_proposed_terms",
      ...(currentMatches.length > 0 ? { current: sorted(currentMatches) } : {}),
      proposed: sorted(candidates),
    });
    for (const benefit of candidates) proposedByKey.delete(benefit.dedupeKey);
    for (const benefit of currentMatches) currentByKey.delete(benefit.dedupeKey);
  }
  const sharedDedupeKeys = [...currentByKey.keys()].filter((key) => proposedByKey.has(key)).sort();
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
    unchanged.push({ current: currentMatches[0], proposed: proposedMatches[0] });
    currentByKey.delete(key);
    proposedByKey.delete(key);
  }

  const currentBySemantic = new Map<string, BenefitProposal[]>();
  const unmatchedProposedBySemantic = new Map<string, BenefitProposal[]>();
  for (const benefits of currentByKey.values()) {
    for (const benefit of benefits) {
      const key = semanticKey(benefit);
      currentBySemantic.set(key, [...(currentBySemantic.get(key) ?? []), benefit]);
    }
  }
  for (const benefits of proposedByKey.values()) {
    for (const benefit of benefits) {
      const key = semanticKey(benefit);
      unmatchedProposedBySemantic.set(key, [...(unmatchedProposedBySemantic.get(key) ?? []), benefit]);
    }
  }

  const modifications: BenefitDiff["modifications"] = [];
  for (const key of [...currentBySemantic.keys()].filter((key) => unmatchedProposedBySemantic.has(key)).sort()) {
    const currentMatches = sorted(currentBySemantic.get(key)!);
    const proposedMatches = sorted(unmatchedProposedBySemantic.get(key)!);
    if (currentMatches.length === 1 && proposedMatches.length === 1) {
      modifications.push({ current: currentMatches[0], proposed: proposedMatches[0] });
      currentByKey.delete(currentMatches[0].dedupeKey);
      proposedByKey.delete(proposedMatches[0].dedupeKey);
    } else {
      conflicts.push({ code: "ambiguous_benefit_match", current: currentMatches, proposed: proposedMatches });
      for (const benefit of currentMatches) currentByKey.delete(benefit.dedupeKey);
      for (const benefit of proposedMatches) proposedByKey.delete(benefit.dedupeKey);
    }
  }

  for (const benefits of unmatchedProposedBySemantic.values()) {
    const unmatched = sorted(benefits.filter((benefit) => proposedByKey.has(benefit.dedupeKey)));
    if (unmatched.length > 1) {
      conflicts.push({ code: "conflicting_proposed_terms", proposed: unmatched });
      for (const benefit of unmatched) proposedByKey.delete(benefit.dedupeKey);
    }
  }

  const additions = sorted([...proposedByKey.values()].flat());
  const possibleRemovals = sorted([...currentByKey.values()].flat()).map((benefit) => ({ benefit, informational: true as const }));
  return { additions, modifications, possibleRemovals, unchanged, conflicts };
}
