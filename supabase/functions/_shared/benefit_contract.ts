export type CanonicalBenefitInput = {
  benefitId?: string;
  dedupeKey?: string;
  semanticKey?: string | null;
  category?: string | null;
  title: string;
  description?: string | null;
  benefitType?: string | null;
  value?: number | string | null;
  rate?: number | string | null;
  cap?: number | string | null;
  threshold?: number | string | null;
  frequency?: string | null;
  period?: string | null;
  valueConfig?: Record<string, unknown> | null;
  exclusions?: unknown;
  restrictions?: string[] | string | null;
  partners?: string[] | null;
  regions?: string[] | null;
  validFrom?: string | null;
  validUntil?: string | null;
};

type CanonicalObject = Record<string, unknown>;

function normalizedText(value: string): string {
  return value.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
}

function normalizedKey(value: string): string {
  return value.normalize("NFKC")
    .replace(/([a-z])([A-Z])/g, "$1_$2")
    .replace(/[\s-]+/g, "_")
    .toLowerCase()
    .trim();
}

function numericValue(value: unknown): number | undefined {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : undefined;
  }
  if (typeof value !== "string") return undefined;
  const normalized = value.normalize("NFKC").trim().toLowerCase()
    .replace(/(?:₹|rs\.?|inr)\s*/g, "")
    .replace(/\s+/g, " ");
  const matched = normalized.match(
    /^([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)\s*(lakh|lac|lacs|crore|crores)?$/,
  );
  if (!matched) return undefined;
  const number = Number(matched[1].replace(/,/g, ""));
  if (!Number.isFinite(number)) return undefined;
  const unit = matched[2];
  return number * (unit?.startsWith("crore") ? 10_000_000 : unit ? 100_000 : 1);
}

function canonicalScalar(value: unknown): unknown {
  if (typeof value === "string") {
    return numericValue(value) ?? normalizedText(value);
  }
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : undefined;
  }
  if (typeof value === "boolean") return value;
  return undefined;
}

function canonicalObject(value: unknown): CanonicalObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .map(([key, item]) =>
        [normalizedKey(key), canonicalUnknown(item)] as const
      )
      .filter(([, item]) => item !== undefined)
      .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0),
  );
}

function canonicalUnknown(value: unknown): unknown {
  if (value === null || value === undefined) return undefined;
  if (Array.isArray(value)) {
    return value.map(canonicalUnknown).filter((item) => item !== undefined);
  }
  if (typeof value === "object") return canonicalObject(value);
  return canonicalScalar(value);
}

function canonicalTerms(value: unknown): string[] {
  const values = Array.isArray(value) ? value : value == null ? [] : [value];
  return [
    ...new Set(
      values
        .map((item) =>
          typeof item === "string" || typeof item === "number"
            ? normalizedText(String(item))
            : ""
        )
        .filter(Boolean),
    ),
  ]
    .sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
}

function field(object: Record<string, unknown>, ...names: string[]): unknown {
  for (const [key, value] of Object.entries(object)) {
    if (names.includes(normalizedKey(key))) return value;
  }
  return undefined;
}

/** Converts legacy exclusion arrays and current JSON objects to the stable JSONB shape. */
export function canonicalExclusions(input: unknown): Record<string, unknown> {
  const object = input && typeof input === "object" && !Array.isArray(input)
    ? input as Record<string, unknown>
    : {};
  const additional = field(object, "additional");
  const additionalObject =
    additional && typeof additional === "object" && !Array.isArray(additional)
      ? additional as Record<string, unknown>
      : {};
  const sourceTerms = Array.isArray(input) || typeof input === "string"
    ? input
    : field(additionalObject, "source_terms", "sourceterms") ??
      field(object, "source_terms", "sourceterms");
  return {
    additional: { source_terms: canonicalTerms(sourceTerms) },
    categories: canonicalTerms(field(object, "categories")),
    days: canonicalTerms(field(object, "days")),
    mcc_codes: canonicalTerms(field(object, "mcc_codes", "mcccodes")),
    merchants: canonicalTerms(field(object, "merchants")),
    transaction_types: canonicalTerms(
      field(object, "transaction_types", "transactiontypes"),
    ),
  };
}

/** Merges every machine-readable commercial term into a sorted value_config object. */
export function canonicalValueConfig(
  input: CanonicalBenefitInput,
): Record<string, unknown> {
  const config = canonicalObject(input.valueConfig);
  for (
    const [key, value] of Object.entries({
      value: input.value,
      rate: input.rate,
      cap: input.cap,
      threshold: input.threshold,
      frequency: input.frequency,
      period: input.period,
    })
  ) {
    const canonical = canonicalScalar(value);
    if (canonical !== undefined) config[key] = canonical;
  }
  return canonicalObject(config);
}

function optionalTerm(value: unknown): string | undefined {
  return typeof value === "string" && normalizedText(value)
    ? normalizedText(value)
    : undefined;
}

/** Returns the presentation-independent terms that define one benefit condition. */
export function canonicalConditionObject(
  input: CanonicalBenefitInput,
): Record<string, unknown> {
  const condition: CanonicalObject = {
    benefit_type: optionalTerm(input.benefitType),
    category: optionalTerm(input.category),
    exclusions: canonicalExclusions(input.exclusions),
    partners: canonicalTerms(input.partners),
    regions: canonicalTerms(input.regions),
    restrictions: canonicalTerms(input.restrictions),
    semantic_key: optionalTerm(input.semanticKey),
    valid_from: optionalTerm(input.validFrom),
    valid_until: optionalTerm(input.validUntil),
    value_config: canonicalValueConfig(input),
  };
  return canonicalObject(condition);
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)
        .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`)
        .join(",")
    }}`;
  }
  return JSON.stringify(value);
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

/** Hashes a replay-stable, order-independent set of canonical benefit conditions. */
export async function canonicalBenefitHash(
  input: CanonicalBenefitInput[],
): Promise<string> {
  const conditions = input.map(canonicalConditionObject).map(stableJson).sort();
  return await sha256(`[${conditions.join(",")}]`);
}

/** Creates the v2 identifier that prevents terms on different cards from sharing a live row. */
export async function cardScopedBenefitKey(
  cardId: string,
  input: CanonicalBenefitInput,
): Promise<string> {
  return `card-benefit-v2:${
    normalizedText(cardId)
  }:${await canonicalBenefitHash([input])}`;
}
