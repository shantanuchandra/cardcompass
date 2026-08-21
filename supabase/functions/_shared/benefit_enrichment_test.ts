import {
  type BenefitComparisonProposal,
  canonicalBenefitReplayFactEnvelope,
  containsPrivateBenefitData,
  currentBenefitProposal,
  diffBenefits,
  extractGroundedBenefitsV6,
} from "./benefit_enrichment.ts";
import { canonicalConditionObject } from "./benefit_contract.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("structured comparison keeps flat commercial term changes material", () => {
  const current = currentBenefitProposal({
    benefit_id: "11111111-1111-4111-8111-111111111111",
    dedupe_key: "legacy:reward-points:dining",
    title: "Five reward points",
    description: "Earn 5 reward points on dining.",
    benefit_category: "POINTS",
    benefit_type: "reward_points",
    value_config: {
      multiplier: 1,
      rate: 5,
      restrictions: ["dining"],
    },
    exclusions: [],
    source_url: "https://issuer.example/card",
  });
  assert(current != null, "legacy live benefit did not reconstruct");

  const changed = {
    ...current,
    benefitId: `card-benefit-v2:card-1:${"a".repeat(64)}`,
    dedupeKey: `card-benefit-v2:card-1:${"a".repeat(64)}`,
    offerSubject: "rewards:reward_points:dining",
    rate: 10,
    valueConfig: { ...current.valueConfig, rate: 10 },
    parserVersion: "benefits-v6",
  } as BenefitComparisonProposal;
  const material = diffBenefits([current], [changed]);
  assert(
    material.modifications.length === 1 &&
      material.modifications[0].changeType === undefined &&
      material.additions.length === 0 &&
      material.possibleRemovals.length === 0,
    "a structured 5-to-10 rate change was mislabeled as identity migration",
  );

  const stableKey = `card-benefit-v2:card-1:${"b".repeat(64)}`;
  const approved = currentBenefitProposal({
    benefit_id: "22222222-2222-4222-8222-222222222222",
    dedupe_key: stableKey,
    title: "Five reward points",
    description: "Earn 5 reward points on dining.",
    benefit_category: "POINTS",
    benefit_type: "reward_points",
    value_config: {
      multiplier: 1,
      rate: 5,
      offer_subject: "rewards:reward_points:dining",
      restrictions: ["dining"],
      exclusions: {
        additional: { source_terms: [] },
        categories: [],
        days: [],
        mcc_codes: [],
        merchants: [],
        transaction_types: [],
      },
    },
    exclusions: {
      additional: { source_terms: [] },
      categories: [],
      days: [],
      mcc_codes: [],
      merchants: [],
      transaction_types: [],
    },
    source_url: "https://issuer.example/card",
  });
  assert(approved != null, "v6 live benefit did not reconstruct");
  const unchanged = diffBenefits([approved], [{
    ...approved,
    liveBenefitId: undefined,
    parserVersion: "benefits-v6",
  }]);
  assert(
    unchanged.unchanged.length === 1 &&
      unchanged.modifications.length === 0 &&
      unchanged.conflicts.length === 0,
    "an identical structured flat term stopped replaying unchanged",
  );
});

Deno.test("v6 excludes negated categories from the offer subject", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Earn 1% cashback on all other eligible spends except fuel, rent and wallet reloads.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(proposals.length === 1, "one cashback term did not parse once");
  assert(
    proposals[0].offerSubject === "cashback:cashback:general",
    `excluded fuel became an offer: ${proposals[0].offerSubject}`,
  );
});

Deno.test("v6 does not publish table-introduction headings as benefits", async () => {
  const documents = [
    {
      sourceUrl: "https://issuer.example/faq.pdf",
      text:
        "Eligible merchant category codes for 5% cashback on Example Credit Card are stated as below:",
      contentHash: "a".repeat(64),
    },
    {
      sourceUrl: "https://issuer.example/faq-2.pdf",
      text:
        "5% cashback categories will be identified basis the merchant category codes detailed below.",
      contentHash: "b".repeat(64),
    },
    {
      sourceUrl: "https://issuer.example/faq-3.pdf",
      text: "Q.37 What are the eligible transactions for 5% cashback?",
      contentHash: "c".repeat(64),
    },
    {
      sourceUrl: "https://issuer.example/terms.pdf",
      text: "Other merchant category codes are not eligible for 5% cashback.",
      contentHash: "d".repeat(64),
    },
    {
      sourceUrl: "https://issuer.example/example.pdf",
      text:
        "25th Jan Merchant transaction amounting to Rs 1000; Rs 1500 capping reached under 5% cashback category.",
      contentHash: "e".repeat(64),
    },
    {
      sourceUrl: "https://issuer.example/heading.pdf",
      text: "Capping for the 5% cashback",
      contentHash: "f".repeat(64),
    },
  ];
  const proposals = await extractGroundedBenefitsV6(
    documents,
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(proposals.length === 0, "a table heading became a cashback offer");
});

Deno.test("v6 consolidates equivalent observations around the strongest structured terms", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text: "Earn 10% cashback on eligible online spends.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/terms.pdf",
      text:
        "Get 10% cashback on online purchases, capped at Rs 1,500 per month.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(proposals.length === 1, "equivalent official observations duplicated");
  assert(proposals[0].cap === 1500, "the explicit cap was discarded");
  assert(
    proposals[0].sourceUrls?.length === 2,
    "merged evidence lost an official source",
  );
});

Deno.test("v6 tolerates issuer comma typos in bounded currency caps", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Earn 10% cashback on eligible app transactions up to Rs,1,500 per billing cycle.",
      contentHash: "a".repeat(64),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(proposals.length === 1, "the bounded cashback term did not parse");
  assert(proposals[0].cap === 1500, "the issuer cap typo erased the cap");
  assert(
    proposals[0].period === "statement month",
    "billing-cycle frequency was not canonicalized",
  );
});

Deno.test("v6 keeps contradictory explicit caps separate for review", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://issuer.example/card",
      text:
        "Get 10% cashback on online purchases, capped at Rs 1,500 per month.",
      contentHash: "a".repeat(64),
    }, {
      sourceUrl: "https://issuer.example/terms.pdf",
      text:
        "Get 10% cashback on online purchases, capped at Rs 2,000 per month.",
      contentHash: "b".repeat(64),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  const diff = diffBenefits([], proposals);
  assert(proposals.length === 2, "contradictory caps were silently merged");
  assert(
    diff.conflicts.length === 1 && diff.additions.length === 0,
    "contradictory caps did not require review",
  );
});

Deno.test("single-token contextual names fail closed while exact card identities remain public", () => {
  const context = {
    issuer: "Issuer Example",
    identityLabels: ["Issuer Example Card"],
  };
  for (
    const value of [
      "Cashback for alice is 10%.",
      "Cashback for aLiCe is 10%.",
      "Reward points to राहुल.",
    ]
  ) {
    assert(
      containsPrivateBenefitData(value, context),
      `single-token contextual name survived: ${value}`,
    );
  }
  for (
    const value of [
      "Cashback for Issuer Example is 10%.",
      "Reward points to Issuer Example Card.",
      "Cashback for cardholders is 10%.",
      "Interest rates are subject to change.",
      "The joining fee is paid to renew the card membership annually.",
      "Benefits are available to eligible cardholders.",
      "Renewal Year Fee is ₹500 per year.",
      "Customer Value Proposition includes 10% cashback.",
      "Cashback for the previous month will be adjusted in the next statement.",
      "Cashback will not get adjusted against financial charges.",
      "The renewal date lets cardholders get the annual fee waived.",
    ]
  ) {
    assert(
      !containsPrivateBenefitData(value, context),
      `known issuer/card or public subject looked private: ${value}`,
    );
  }
  const encodedPublicMarkup =
    "&lt;span class=&quot;benefit-title&quot;&gt;10% cashback for cardholders.&lt;/span&gt;";
  const encodedEnvelope = canonicalBenefitReplayFactEnvelope(
    encodedPublicMarkup,
    context,
  );
  assert(
    !encodedEnvelope.factOverflow &&
      encodedEnvelope.publicText === "10% cashback for cardholders.",
    `public encoded issuer markup was not normalized: ${encodedEnvelope.publicText}`,
  );
  const publicTermsEnvelope = canonicalBenefitReplayFactEnvelope(
    "T&Cs apply to 10% cashback for cardholders.",
    context,
  );
  assert(
    !publicTermsEnvelope.factOverflow &&
      publicTermsEnvelope.publicText.includes("10% cashback"),
    "ordinary T&Cs prose was mistaken for an encoded privacy payload",
  );
  const publicContactEnvelope = canonicalBenefitReplayFactEnvelope(
    "Call 1800 1600 1600 to manage your credit card controls.",
    context,
  );
  assert(
    !publicContactEnvelope.factOverflow &&
      publicContactEnvelope.publicText === "",
    "public issuer contact chrome blocked replay instead of being omitted",
  );
});

Deno.test("commercial redemption language and card labels are not customer identities", () => {
  const context = {
    issuer: "HDFC Bank",
    identityLabels: ["Swiggy HDFC Bank Credit Card"],
  };
  const safe = [
    "There is no minimum value of cashback for auto redemption.",
    "Minimum value of the cashback to be earned for redemption will be Rs 100.",
    "Swiggy BLCK Card: An annual membership fee of Rs 1,000 will be applicable.",
    "10% Cashback on Swiggy Food ordering 15000 18000",
    "5% Cashback on E-shopping spends 30000 18000",
  ];
  for (const value of safe) {
    assert(!containsPrivateBenefitData(value, context), value);
    const replay = canonicalBenefitReplayFactEnvelope(value, context);
    assert(!replay.factOverflow, value);
    assert(replay.publicText.length > 0, value);
  }

  const publicContact = canonicalBenefitReplayFactEnvelope(
    "For overseas travel assistance: 020-12345678",
    context,
  );
  assert(!publicContact.factOverflow, "public issuer contact blocked replay");
  assert(
    !publicContact.publicText.includes("12345678"),
    "public issuer contact crossed the replay boundary",
  );
});

Deno.test("canonical scalar currency parsing accepts shared prefix and suffix forms without rewriting prose", () => {
  const condition = (value: unknown, flat = false) =>
    canonicalConditionObject({
      title: "Currency parity",
      category: "cashback",
      benefitType: "cashback",
      ...(flat ? { rate: value as string } : { valueConfig: { rate: value } }),
      restrictions: [],
      exclusions: [],
    }).value_config as Record<string, unknown>;

  for (
    const value of [
      "INR 10",
      "10 INR",
      "Rs. 10",
      "10 Rs.",
      "₹10",
      "10 ₹",
    ]
  ) {
    assert(condition(value).rate === 10, `config currency drifted: ${value}`);
    assert(
      condition(value, true).rate === 10,
      `flat currency drifted: ${value}`,
    );
  }

  assert(
    condition("first purchase").rate === "first purchase",
    "embedded rs prose was rewritten",
  );
  assert(
    condition("10 INR bonus").rate === "10 inr bonus",
    "non-numeric currency prose was rewritten",
  );
});

Deno.test("current Axis IndianOil benefit grammar remains grounded and complete", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl:
        "https://www.axis.bank.in/cards/credit-card/indianoil-axis-bank-credit-card",
      finalUrl:
        "https://www.axis.bank.in/cards/credit-card/indianoil-axis-bank-credit-card",
      text: [
        "Enjoy benefit of 4% value back on fuel transactions by earning 20 reward points per ₹100 spent at any IOCL fuel outlet in India.",
        "Enjoy benefit of 1% value back on online shopping by earning 5 reward points per ₹100 spent.",
        "Free yourself from paying fuel surcharge waiver of 1%.",
        "Spend more than ₹3,50,000 in a card anniversary year and you will be eligible for annual fee waiver.",
        "Get instant discount up to 10% on your movie ticket booked via BookMyShow.",
      ].join("\n"),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );

  assert(
    proposals.some((item) =>
      item.category === "points" && item.value === 20 && item.threshold === 100
    ),
    "fuel reward points were not extracted",
  );
  assert(
    proposals.some((item) =>
      item.category === "points" && item.value === 5 && item.threshold === 100
    ),
    "online reward points were not extracted",
  );
  assert(
    proposals.some((item) =>
      item.valueType === "fuel_surcharge_waiver" && item.rate === 1
    ),
    "reverse-order fuel waiver was not extracted",
  );
  assert(
    proposals.some((item) =>
      item.valueType === "fee_waiver" && item.threshold === 350000
    ),
    "spend-more-than annual fee waiver was not extracted",
  );
  assert(
    proposals.some((item) =>
      item.category === "entertainment" && item.rate === 10
    ),
    "instant movie discount was not extracted",
  );
});

Deno.test("current SBI ELITE JSON benefit grammar produces reviewable categories", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl:
        "https://www.sbicard.com/json/templatedata/product/card/data/en/personal/sbi-card-elite.json",
      finalUrl:
        "https://www.sbicard.com/json/templatedata/product/card/data/en/personal/sbi-card-elite.json",
      text: [
        "SBI Card ELITE",
        "5X Reward Points on dining, departmental stores and grocery spends",
        "1% Fuel Surcharge Waiver across all petrol pumps.",
        "2 complimentary domestic airport lounge visits every quarter",
        "Annual fee reversal on annual spends of Rs. 10 lakhs.",
        "Free movie tickets worth Rs. 6,000 every year.",
      ].join("\n"),
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );

  for (
    const category of ["points", "fuel", "travel", "other", "entertainment"]
  ) {
    assert(
      proposals.some((item) => item.category === category),
      `SBI ${category} benefit was not extracted`,
    );
  }
});

Deno.test("excluded reward categories do not manufacture a positive multiplier", async () => {
  const proposals = await extractGroundedBenefitsV6(
    [{
      sourceUrl: "https://www.idfcfirstbank.com/credit-card/wealth",
      finalUrl: "https://www.idfcfirstbank.com/credit-card/wealth",
      text:
        "Categories not included in the 10X Reward Points threshold include Utility, Insurance, Government Services and Education.",
    }],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  assert(
    proposals.length === 0,
    "a reward exclusion became a positive benefit",
  );
});

Deno.test("equivalent reward multiplier observations consolidate but explicit scopes stay distinct", async () => {
  const base = "https://www.idfcfirstbank.com/credit-card/wealth";
  const proposals = await extractGroundedBenefitsV6(
    [
      {
        sourceUrl: base,
        finalUrl: base,
        text: "Earn up to 3X reward points on your spends.",
      },
      {
        sourceUrl: `${base}/terms`,
        finalUrl: `${base}/terms`,
        text: "Earn 3X reward points on all eligible spends (online/offline).",
      },
      {
        sourceUrl: `${base}/upi`,
        finalUrl: `${base}/upi`,
        text: "Earn 3X reward points on UPI spends.",
      },
      {
        sourceUrl: `${base}/heading`,
        finalUrl: `${base}/heading`,
        text: "10X Reward Points",
      },
    ],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  const general = proposals.filter((item) =>
    item.offerSubject?.endsWith(":general")
  );
  const upi = proposals.filter((item) =>
    item.sourceExcerpt.toLowerCase().includes("upi")
  );
  assert(
    general.length === 1,
    "equivalent general multipliers were duplicated",
  );
  assert(
    upi.length === 1,
    "an explicit UPI multiplier was collapsed into general evidence",
  );
  assert(
    (general[0].sourceUrls?.length ?? 0) === 2,
    "merged reward provenance was lost",
  );
});

Deno.test("compatible access observations consolidate without hiding explicit differences", async () => {
  const base = "https://www.idfcfirstbank.com/credit-card/wealth";
  const proposals = await extractGroundedBenefitsV6(
    [
      { sourceUrl: base, finalUrl: base, text: "1% Fuel surcharge waiver." },
      {
        sourceUrl: `${base}/fuel`,
        finalUrl: `${base}/fuel`,
        text: "1% Fuel surcharge waiver up to ₹400 per month.",
      },
      {
        sourceUrl: `${base}/lounge`,
        finalUrl: `${base}/lounge`,
        text: "1 complimentary airport lounge visit.",
      },
      {
        sourceUrl: `${base}/lounge-terms`,
        finalUrl: `${base}/lounge-terms`,
        text: "1 complimentary airport lounge visit per quarter.",
      },
      {
        sourceUrl: `${base}/other-lounge`,
        finalUrl: `${base}/other-lounge`,
        text: "2 complimentary airport lounge visits per quarter.",
      },
      {
        sourceUrl: `${base}/golf`,
        finalUrl: `${base}/golf`,
        text: "1 complimentary golf round.",
      },
      {
        sourceUrl: `${base}/golf-terms`,
        finalUrl: `${base}/golf-terms`,
        text: "1 complimentary golf round per quarter.",
      },
    ],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );
  const fuel = proposals.filter((item) =>
    item.valueType === "fuel_surcharge_waiver"
  );
  const lounges = proposals.filter((item) =>
    item.valueType === "lounge_access"
  );
  const golf = proposals.filter((item) => item.valueType === "golf_access");
  assert(
    fuel.length === 1 && fuel[0].cap === 400,
    "fuel cap evidence did not consolidate",
  );
  assert(
    lounges.length === 2,
    "different lounge counts collapsed or compatible visits duplicated",
  );
  assert(
    golf.length === 1 && (golf[0].sourceUrls?.length ?? 0) === 2,
    "compatible golf evidence did not consolidate",
  );
});

Deno.test("current IDFC observations reject headings and history while consolidating exact subjects", async () => {
  const base = "https://www.idfcfirstbank.com/credit-card/wealth";
  const proposals = await extractGroundedBenefitsV6(
    [
      {
        sourceUrl: base,
        finalUrl: base,
        text: [
          "1% Cashback",
          "Earlier, 10X Reward Points were only unlocked after spending ₹20,000 in a billing cycle.",
          "This totals up to 8 complimentary lounge visits annually (4 domestic + 4 international).",
          "1 complimentary visit per quarter to airport lounges at airport terminals in India.",
        ].join("\n"),
      },
      {
        sourceUrl: `${base}/terms`,
        finalUrl: `${base}/terms`,
        text:
          "10X reward points on Dining, Travel and International transactions only.",
      },
      {
        sourceUrl: `${base}/communication`,
        finalUrl: `${base}/communication`,
        text:
          "Earn 10X reward points on all Dining, Travel, and International transactions from the first eligible spend.",
      },
      {
        sourceUrl: `${base}/current`,
        finalUrl: `${base}/current`,
        text:
          "Earn 10X reward points starting from your very first transaction on Dining, Travel, and International purchases.",
      },
      {
        sourceUrl: `${base}/lounge`,
        finalUrl: `${base}/lounge`,
        text: [
          "1 complimentary domestic airport lounge visit per quarter.",
          "1 complimentary visit per quarter to global airport lounges.",
          "1 complimentary international airport lounge visit per quarter.",
        ].join("\n"),
      },
    ],
    "benefits-v6",
    "00000000-0000-4000-8000-000000000001",
  );

  const dining = proposals.filter((item) =>
    item.valueType === "reward_multiplier" && item.rate === 10
  );
  const lounge = proposals.filter((item) => item.valueType === "lounge_access");
  assert(
    dining.length === 1,
    "equivalent current dining evidence remained split",
  );
  assert(
    (dining[0].sourceUrls?.length ?? 0) === 3,
    "current dining provenance was not retained",
  );
  assert(
    lounge.length === 2 && lounge.every((item) => item.value === 1),
    "India/global lounge evidence did not consolidate by region",
  );
  assert(
    !proposals.some((item) => item.valueType === "cashback"),
    "a bare cashback heading became a benefit",
  );
  assert(
    !proposals.some((item) => item.value === 8),
    "a composite domestic/international total became one scoped benefit",
  );
});
