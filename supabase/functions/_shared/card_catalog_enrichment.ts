export type CatalogField =
  | "network"
  | "card_type"
  | "joining_fee"
  | "annual_fee"
  | "apr";

export type FieldEvidence<T = string | number> = {
  value: T;
  confidence: number;
  evidence: string;
};

export type CatalogPatch = Partial<{
  network: FieldEvidence<string>;
  card_type: FieldEvidence<"credit">;
  joining_fee: FieldEvidence<number>;
  annual_fee: FieldEvidence<number>;
  apr: FieldEvidence<number>;
}>;

import {
  type BenefitProposal,
  extractGroundedBenefits,
} from "./benefit_enrichment.ts";
import {
  redactSensitiveUrlsInText,
  redactSensitiveUrlsInValue,
  safeHttpsDisplayUrl,
} from "./benefit_source_privacy.ts";
import {
  type CanonicalCardIdentity,
  exactOfficialPageIdentity,
} from "./card_discovery.ts";

export function requireCatalogPageIdentity(
  html: string,
  issuer: string,
  expectedCardName: string,
  sourceUrl?: string,
): CanonicalCardIdentity {
  const identity = exactOfficialPageIdentity(
    html,
    issuer,
    expectedCardName,
    sourceUrl,
  );
  if (!identity) throw new Error("identity_mismatch");
  return identity;
}

/**
 * Legacy catalog-enrichment shape plus the reviewable, grounded proposal fields.
 * The legacy scalar confidence/evidence fields remain while field-level evidence
 * is available to the benefit staging flow.
 */
export type BenefitCandidate =
  & Omit<BenefitProposal, "confidence" | "evidence">
  & {
    confidence: number;
    evidence: string;
    source_url: string;
    fieldConfidence: Record<string, number>;
    fieldEvidence: Record<string, string>;
  };

export type FieldConflict = {
  field: CatalogField;
  existing: unknown;
  proposed: unknown;
  confidence: number;
  evidence: string;
};

function decodedText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<\/(?:p|div|li|dd|dt|h[1-6]|tr)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&#8377;|&#x20b9;/gi, "₹")
    .replace(/[ \t]+/g, " ")
    .replace(/\n\s*\n+/g, "\n")
    .trim()
    .slice(0, 160_000);
}

function excerpt(value: string): string {
  return redactSensitiveUrlsInText(value)
    .replace(/(?<!\d)(?:\d[\s-]*){6,}(?!\d)/g, "[redacted]")
    .replace(/\s+/g, " ").trim().slice(0, 300);
}

export function normalizeMoney(value: string): number | null {
  const match = value.replace(/,/g, "").match(
    /(?:₹|rs\.?|inr)\s*([0-9]+(?:\.[0-9]{1,2})?)/i,
  );
  return match ? Number(match[1]) : null;
}

function labelledLine(text: string, label: RegExp): string | null {
  const lines = text.split("\n").map((line) => line.trim()).filter(Boolean);
  for (let index = 0; index < lines.length; index++) {
    if (!label.test(lines[index])) continue;
    return `${lines[index]} ${lines[index + 1] ?? ""}`.trim();
  }
  return null;
}

function feeField(
  text: string,
  label: RegExp,
): FieldEvidence<number> | undefined {
  const line = labelledLine(text, label);
  if (!line) return undefined;
  const value = normalizeMoney(line);
  return value == null
    ? undefined
    : { value, confidence: 0.96, evidence: excerpt(line) };
}

export function normalizeOfficialCatalogPage(
  html: string,
  sourceUrl: string,
): {
  patch: CatalogPatch;
  benefits: BenefitCandidate[];
  evidence: Record<string, string>;
} {
  const text = decodedText(html);
  sourceUrl = safeHttpsDisplayUrl(sourceUrl) ?? "invalid-source";
  const patch: CatalogPatch = {};
  const joiningFee = feeField(text, /\bjoining\s+fee\b/i);
  const annualFee = feeField(text, /\bannual(?:|\s+membership)\s+fee\b/i);
  if (joiningFee) patch.joining_fee = joiningFee;
  if (annualFee) patch.annual_fee = annualFee;

  const aprLine = labelledLine(
    text,
    /\b(?:finance\s+charges?|annual percentage rate|apr)\b/i,
  );
  const annualRate = aprLine?.match(
    /([0-9]+(?:\.[0-9]+)?)%\s*(?:annually|annual|p\.?a\.?)/i,
  );
  if (aprLine && annualRate) {
    patch.apr = {
      value: Number(annualRate[1]),
      confidence: 0.94,
      evidence: excerpt(aprLine),
    };
  }

  const networkLine = labelledLine(text, /\bnetwork\b/i);
  const network = networkLine?.match(
    /\b(visa|mastercard|rupay|american express|amex)\b/i,
  )?.[1];
  if (network && networkLine) {
    patch.network = {
      value: /american express|amex/i.test(network)
        ? "American Express"
        : network[0].toUpperCase() + network.slice(1).toLowerCase(),
      confidence: 0.96,
      evidence: excerpt(networkLine),
    };
  }
  if (/\bcredit\s+card\b/i.test(text)) {
    patch.card_type = {
      value: "credit",
      confidence: 0.99,
      evidence: "Official page identifies a credit card",
    };
  }

  const benefits = extractGroundedBenefits([
    { sourceUrl, text },
  ], "official-catalog-v2")
    .map((benefit): BenefitCandidate => ({
      ...benefit,
      confidence: Math.min(...Object.values(benefit.confidence)),
      evidence: benefit.sourceExcerpt,
      source_url: benefit.sourceUrl,
      fieldConfidence: benefit.confidence,
      fieldEvidence: benefit.evidence,
    }))
    .sort((left, right) =>
      text.indexOf(left.sourceExcerpt) - text.indexOf(right.sourceExcerpt)
    );

  return redactSensitiveUrlsInValue({
    patch,
    benefits: benefits.slice(0, 40),
    evidence: Object.fromEntries(
      Object.entries(patch).map(([field, value]) => [field, value.evidence]),
    ),
  }) as {
    patch: CatalogPatch;
    benefits: BenefitCandidate[];
    evidence: Record<string, string>;
  };
}

export function diffCatalogFields(
  existing: Partial<Record<CatalogField, unknown>>,
  proposed: CatalogPatch,
): {
  backfill: Partial<Record<CatalogField, unknown>>;
  conflicts: FieldConflict[];
} {
  const backfill: Partial<Record<CatalogField, unknown>> = {};
  const conflicts: FieldConflict[] = [];
  for (
    const [field, candidate] of Object.entries(proposed) as [
      CatalogField,
      FieldEvidence,
    ][]
  ) {
    if (candidate.confidence < 0.9) continue;
    const current = existing[field];
    if (current == null || current === "") {
      backfill[field] = candidate.value;
    } else if (
      String(current).toLowerCase() !== String(candidate.value).toLowerCase()
    ) {
      conflicts.push({
        field,
        existing: redactSensitiveUrlsInValue(current),
        proposed: redactSensitiveUrlsInValue(candidate.value),
        confidence: candidate.confidence,
        evidence: redactSensitiveUrlsInText(candidate.evidence),
      });
    }
  }
  return { backfill, conflicts };
}
