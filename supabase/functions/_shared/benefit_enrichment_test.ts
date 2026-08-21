import {
  type BenefitComparisonProposal,
  containsPrivateBenefitData,
  currentBenefitProposal,
  diffBenefits,
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
    ]
  ) {
    assert(
      !containsPrivateBenefitData(value, context),
      `known issuer/card or public subject looked private: ${value}`,
    );
  }
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
