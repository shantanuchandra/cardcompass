import {
  canonicalBenefitCategory,
  canonicalBenefitHash,
  canonicalConditionObject,
  canonicalExclusions,
  canonicalValueConfig,
  cardScopedBenefitKey,
} from "./benefit_contract.ts";

Deno.test("reward aliases share the live points category and canonical hash", async () => {
  for (const alias of ["rewards", "reward", "points", "POINTS"]) {
    assertEquals(canonicalBenefitCategory(alias), "points");
  }
  const reward = {
    title: "Reward points",
    category: "rewards",
    benefitType: "reward_points",
    semanticKey: "rewards:reward_points:general",
    value: 5,
  };
  assertEquals(canonicalConditionObject(reward).category, "points");
  assertEquals(
    await canonicalBenefitHash([reward]),
    await canonicalBenefitHash([{ ...reward, category: "POINTS" }]),
  );
});

function assertEquals(
  actual: unknown,
  expected: unknown,
  message?: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("canonical value config preserves flat zero and false terms while parsing Indian amounts", () => {
  // Catches the approval projection that discarded flat parser fields or treated
  // zero/false as absent values.
  assertEquals(
    canonicalValueConfig({
      title: "Cashback",
      value: "₹1,25,000.50",
      rate: "0",
      cap: "₹2 lakh",
      threshold: "1 crore",
      frequency: " 2  Redemptions ",
      period: " Month ",
      valueConfig: {
        enabled: false,
        nested: { ignored: null, Unit: " Reward Points " },
      },
    }),
    {
      cap: 200000,
      enabled: false,
      frequency: "2 redemptions",
      nested: { unit: "reward points" },
      period: "month",
      rate: 0,
      threshold: 10000000,
      value: 125000.5,
    },
  );
});

Deno.test("canonical value config merges explicit configuration and keeps decimals", () => {
  // Catches a serializer that loses supported explicit configuration or rounds
  // commercial decimal values.
  assertEquals(
    canonicalValueConfig({
      title: "Points multiplier",
      rate: "2.5",
      valueConfig: { multiplier: "3.75", tiered: false, unused: null },
    }),
    {
      multiplier: 3.75,
      rate: 2.5,
      tiered: false,
    },
  );
});

Deno.test("canonical exclusions accepts legacy arrays and normalizes current objects", () => {
  // Catches JSONB array/object drift that made equal exclusions compare as
  // different conditions.
  assertEquals(
    canonicalExclusions([
      " Fuel ",
      "fuel",
      "Wallet\u00a0Reloads",
    ]),
    {
      additional: { source_terms: ["fuel", "wallet reloads"] },
      categories: [],
      days: [],
      mcc_codes: [],
      merchants: [],
      transaction_types: [],
    },
  );
  assertEquals(
    canonicalExclusions({
      days: [" Sunday", "sunday"],
      mccCodes: ["5411", 5411],
      merchants: [" ACME  MART ", "acme mart"],
      categories: [" Fuel ", "fuel"],
      transactionTypes: [" Wallet Reload ", "wallet reload"],
      additional: { source_terms: [" Cash Advance ", "cash advance"] },
    }),
    {
      additional: { source_terms: ["cash advance"] },
      categories: ["fuel"],
      days: ["sunday"],
      mcc_codes: ["5411"],
      merchants: ["acme mart"],
      transaction_types: ["wallet reload"],
    },
  );
});

Deno.test("canonical aliases resolve independently of property order", async () => {
  // Catches aliases whose selected scalar or exclusion array depends on the
  // order an upstream JSON parser happened to insert object properties.
  const first = {
    title: "Movie benefit",
    valueConfig: {
      "Max Usage Per Month": 1,
      max_usage_per_month: 2,
      nested: { "Reward Rate": 1, reward_rate: 2 },
    },
    exclusions: {
      mccCodes: ["5411", "5541"],
      mcc_codes: ["5541", "5812"],
    },
  };
  const reversed = {
    title: "Movie benefit",
    valueConfig: {
      nested: { reward_rate: 2, "Reward Rate": 1 },
      max_usage_per_month: 2,
      "Max Usage Per Month": 1,
    },
    exclusions: {
      mcc_codes: ["5541", "5812"],
      mccCodes: ["5411", "5541"],
    },
  };
  assertEquals(canonicalValueConfig(first), {
    max_usage_per_month: 2,
    nested: { reward_rate: 2 },
  });
  assertEquals(canonicalValueConfig(first), canonicalValueConfig(reversed));
  assertEquals(canonicalExclusions(first.exclusions), {
    additional: { source_terms: [] },
    categories: [],
    days: [],
    mcc_codes: ["5411", "5541", "5812"],
    merchants: [],
    transaction_types: [],
  });
  assertEquals(
    canonicalExclusions(first.exclusions),
    canonicalExclusions(reversed.exclusions),
  );
  assertEquals(
    await canonicalBenefitHash([first]),
    await canonicalBenefitHash([reversed]),
  );
});

Deno.test("canonical condition omits null presentation fields and is independent of property order", async () => {
  // Catches condition hashes that change with object insertion order, presentational
  // title wording, or omitted optional values.
  const first = {
    title: "Cashback title",
    description: null,
    category: " CashBack ",
    benefitType: " CashBack ",
    valueConfig: { z: null, cap: "₹500", rate: "5" },
    restrictions: [" Online   Spends ", "online spends"],
    partners: ["M\u00e9tro", "m\u00e9tro"],
    regions: [" IN ", "in"],
    exclusions: ["Fuel"],
    validFrom: "2026-01-01",
    validUntil: "2026-12-31",
  };
  const second = {
    title: "Different marketing copy",
    validUntil: "2026-12-31",
    exclusions: { additional: { source_terms: [" fuel "] } },
    regions: ["in"],
    partners: ["m\u00e9tro"],
    restrictions: ["online spends"],
    valueConfig: { rate: 5, cap: 500 },
    benefitType: "cashback",
    category: "cashback",
    validFrom: "2026-01-01",
  };
  assertEquals(canonicalConditionObject(first), {
    benefit_type: "cashback",
    category: "cashback",
    exclusions: {
      additional: { source_terms: ["fuel"] },
      categories: [],
      days: [],
      mcc_codes: [],
      merchants: [],
      transaction_types: [],
    },
    partners: ["m\u00e9tro"],
    regions: ["in"],
    restrictions: ["online spends"],
    valid_from: "2026-01-01",
    valid_until: "2026-12-31",
    value_config: { cap: 500, rate: 5 },
  });
  assertEquals(
    await canonicalBenefitHash([first]),
    await canonicalBenefitHash([second]),
  );
});

Deno.test("card-scoped keys keep insurance semantic families distinct", async () => {
  // Catches globally-scoped dedupe keys that collapse equal-value insurance
  // benefits across cards or across distinct insurance coverages.
  const travelInsurance = {
    title: "Travel insurance",
    category: "insurance",
    benefitType: "insurance",
    semanticKey: "travel-medical",
    value: "₹5 lakh",
  };
  const purchaseInsurance = {
    title: "Purchase protection",
    category: "insurance",
    benefitType: "insurance",
    semanticKey: "purchase-protection",
    value: 500000,
  };
  const cardA = await cardScopedBenefitKey(
    "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    travelInsurance,
  );
  const cardB = await cardScopedBenefitKey(
    "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    travelInsurance,
  );
  assertEquals(cardA === cardB, false);
  assertEquals(
    await canonicalBenefitHash([travelInsurance]) ===
      await canonicalBenefitHash([purchaseInsurance]),
    false,
  );
  assertEquals(
    cardA.startsWith("card-benefit-v2:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:"),
    true,
  );
});
