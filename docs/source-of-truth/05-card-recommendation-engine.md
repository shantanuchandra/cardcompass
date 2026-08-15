# Card Recommendation Engine

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

For a spend context or 90-day portfolio, independently identify the highest-net-
value eligible card the user owns and the highest-net-value eligible card
available in the user's country/market.

## Candidate pools

### Best card owned

Include active `user_cards` belonging to the authenticated user. Resolve their
catalog products and active card-benefit mappings. Never treat an unowned card
as owned merely because it exists in the catalog.

### Best card overall

Include active catalog cards only when:

- the card is offered in the user's country/market;
- the issuer/product is currently available;
- known age, income, residency, issuer-relationship, and product prerequisites
  are compatible; and
- an evidence-grounded applicable benefit exists.

Known-ineligible and cross-market cards are excluded rather than penalized.
Incomplete eligibility may produce `likely eligible`, with missing checks shown.

## Benefit authority

- `benefits` defines reusable benefit identity.
- `card_benefit_mapping` associates a benefit with a catalog card.
- Card-specific rate, cap, partner, threshold, validity, and exclusions belong
  to the mapping's rule configuration.
- Only active, approved, evidence-grounded mappings affect recommendations.
- Staging candidates never affect end-user ranking.
- Expired or contradicted rules are excluded.

## Normalized rule contract

A rule may define:

- cashback/reward rate and unit;
- reward redemption value;
- percentage or fixed discount;
- BOGO structure;
- minimum eligible transaction;
- per-transaction cap;
- monthly, quarterly, annual, or statement-cycle cap;
- milestone threshold and bonus;
- eligible categories, merchants, MCCs, platforms, and channels;
- transaction-type, merchant, and MCC exclusions;
- required membership, issuer relationship, or payment method;
- validity dates;
- stackability; and
- evidence freshness/confidence.

Rule evaluation is a pure function of card, spend context, user eligibility,
and known benefit-cycle usage.

## Value calculation

At minimum calculate:

- direct discount;
- cashback;
- realizable reward value;
- eligible fee/surcharge waiver;
- gross value;
- remaining cap;
- incremental value over the card actually used/current baseline;
- incremental annual fee for an unowned card;
- recurring net value; and
- first-year value, separately when joining benefits exist.

Conceptually:

`recurring net value = discount + cashback + realizable rewards + eligible waivers - incremental recurring fee`

Do not treat uncertain reward points as cash without a grounded redemption
value. Do not count temporary joining bonuses in recurring ranking.

## Portfolio simulation

The 90-day portfolio recommendation replays eligible transactions through each
candidate's rules and annualizes cautiously. It must respect caps and cycle
boundaries rather than multiplying a headline rate by total spend.

When benefit-cycle usage is known, use remaining capacity. When it is unknown,
return a potential value or range instead of guaranteed savings.

## Result contract

Each owned or overall result contains:

- card identity and ownership status;
- eligibility status;
- spend basis and analysis period;
- gross and recurring net value;
- current-card baseline and incremental savings;
- applicable rule IDs;
- calculation explanation;
- caps, thresholds, or milestone progress;
- confidence;
- evidence date/source;
- warnings and unmet conditions; and
- application action only when permitted and clearly disclosed.

## Ranking safeguards

- Do not rank by headline rate alone.
- Do not exceed remaining caps.
- Do not apply merchant rules to unidentified payment aggregators.
- Do not assume inferred MCC or unverified platform compatibility is guaranteed.
- Do not recommend an unowned card with negative recurring net value.
- Do not rank a cross-market or known-ineligible card.
- Do not combine benefits unless their rules permit stacking.
- Do not use an expired mapping.

Tie-break in this order:

1. higher recurring net value;
2. higher confidence;
3. lower recurring fee;
4. simpler redemption.

Owned and overall pools are ranked independently. Ownership does not grant an
artificial scoring bonus in the overall pool; switching cost and fee are shown
through the value calculation.

## Explainability

Every recommendation answers:

1. Why the card matches this spend.
2. How the estimated value was calculated.
3. Which limits or assumptions could reduce it.
4. Whether the user owns it.
5. Why it outranked the next-best alternative.

## Failure and empty states

- No owned card qualifies -> show that no current card has a verified advantage.
- No overall card qualifies -> show no eligible market card instead of widening
  to another market.
- Missing eligibility -> label likely eligibility and list missing inputs.
- Missing benefit terms -> exclude the uncertain rule rather than invent terms.
- MCC/platform/usage uncertainty -> potential result or confidence range.
- One malformed rule -> skip it and continue evaluating other candidates.

## Acceptance criteria

- Owned recommendations contain owned cards only.
- Overall recommendations stay within market and likely eligibility.
- Caps, thresholds, fees, exclusions, and benefit usage affect ranking.
- A new card must have positive recurring net value to be recommended.
- First-year promotional value is separate from recurring value.
- Every result includes a reproducible explanation.

## Supporting references

- Main repo: `docs/superpowers/2026-07-14-user-card-data-integrity.md`
- Main repo: `docs/superpowers/2026-07-14-benefit-extraction-and-catalog-pipeline.md`
- Main repo: `docs/superpowers/2026-07-09-guest-flow-and-design-refresh.md`
- Main repo: `COMPETITIVE_ANALYSIS_AND_ROADMAP.md`
