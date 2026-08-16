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

export type BenefitCandidate = {
  title: string;
  description: string;
  category: string;
  confidence: number;
  evidence: string;
  source_url: string;
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
  return value.replace(/(?<!\d)(?:\d[\s-]*){6,}(?!\d)/g, "[redacted]")
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

function feeField(text: string, label: RegExp): FieldEvidence<number> | undefined {
  const line = labelledLine(text, label);
  if (!line) return undefined;
  const value = normalizeMoney(line);
  return value == null
    ? undefined
    : { value, confidence: 0.96, evidence: excerpt(line) };
}

function benefitCategory(value: string): string {
  if (/dining|restaurant|food/i.test(value)) return "dining";
  if (/lounge|airport/i.test(value)) return "travel";
  if (/fuel/i.test(value)) return "fuel";
  if (/movie|cinema/i.test(value)) return "entertainment";
  if (/cashback/i.test(value)) return "cashback";
  return "rewards";
}

export function normalizeOfficialCatalogPage(
  html: string,
  sourceUrl: string,
): { patch: CatalogPatch; benefits: BenefitCandidate[]; evidence: Record<string, string> } {
  const text = decodedText(html);
  const patch: CatalogPatch = {};
  const joiningFee = feeField(text, /\bjoining\s+fee\b/i);
  const annualFee = feeField(text, /\bannual(?:|\s+membership)\s+fee\b/i);
  if (joiningFee) patch.joining_fee = joiningFee;
  if (annualFee) patch.annual_fee = annualFee;

  const aprLine = labelledLine(text, /\b(?:finance\s+charges?|annual percentage rate|apr)\b/i);
  const annualRate = aprLine?.match(/([0-9]+(?:\.[0-9]+)?)%\s*(?:annually|annual|p\.?a\.?)/i);
  if (aprLine && annualRate) {
    patch.apr = {
      value: Number(annualRate[1]),
      confidence: 0.94,
      evidence: excerpt(aprLine),
    };
  }

  const networkLine = labelledLine(text, /\bnetwork\b/i);
  const network = networkLine?.match(/\b(visa|mastercard|rupay|american express|amex)\b/i)?.[1];
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

  const seen = new Set<string>();
  const benefits: BenefitCandidate[] = [];
  for (const line of text.split("\n")) {
    const value = excerpt(line);
    if (value.length < 20 || !/(?:cashback|reward|lounge|fuel|dining|movie|complimentary|waiver)/i.test(value)) {
      continue;
    }
    if (!/(?:\d+(?:\.\d+)?%|₹\s*[\d,]+|\d+\s+(?:\w+\s+){0,2}(?:visit|point|mile)|fee waiver)/i.test(value)) {
      continue;
    }
    const key = value.toLowerCase().replace(/[^a-z0-9]+/g, "");
    if (seen.has(key)) continue;
    seen.add(key);
    benefits.push({
      title: value.length > 90 ? `${value.slice(0, 87)}...` : value,
      description: value,
      category: benefitCategory(value),
      confidence: 0.92,
      evidence: value,
      source_url: sourceUrl,
    });
  }

  return {
    patch,
    benefits: benefits.slice(0, 40),
    evidence: Object.fromEntries(
      Object.entries(patch).map(([field, value]) => [field, value.evidence]),
    ),
  };
}

export function diffCatalogFields(
  existing: Partial<Record<CatalogField, unknown>>,
  proposed: CatalogPatch,
): { backfill: Partial<Record<CatalogField, unknown>>; conflicts: FieldConflict[] } {
  const backfill: Partial<Record<CatalogField, unknown>> = {};
  const conflicts: FieldConflict[] = [];
  for (const [field, candidate] of Object.entries(proposed) as [CatalogField, FieldEvidence][]) {
    if (candidate.confidence < 0.9) continue;
    const current = existing[field];
    if (current == null || current === "") {
      backfill[field] = candidate.value;
    } else if (String(current).toLowerCase() !== String(candidate.value).toLowerCase()) {
      conflicts.push({
        field,
        existing: current,
        proposed: candidate.value,
        confidence: candidate.confidence,
        evidence: candidate.evidence,
      });
    }
  }
  return { backfill, conflicts };
}
