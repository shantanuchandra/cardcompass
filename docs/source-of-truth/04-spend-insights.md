# Spend Insights

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

Convert normalized transactions into understandable spend patterns and pass a
precise spend context to the recommendation engine.

## Analysis periods

- Dashboard and insight screens respect the user-selected period.
- The initial default is the past 60 days.
- Card portfolio recommendations use a separate trailing 90-day profile.
- Every insight and recommendation displays its analysis period.
- Changing the dashboard filter does not silently change the 90-day portfolio
  basis.

## Eligible inputs

Include normalized billed retail purchases associated with an owned card.
Exclude payments, credits, refunds, fees, interest, rewards, cash withdrawals,
duplicates, and provisional alert rows already reconciled with a statement.

Refunds reduce spend when linked reliably. Unknown merchants and `other`
categories remain in totals but lower the applicable insight confidence.

## Common insight result

Every insight reports:

- title and insight type;
- analysis period;
- eligible transaction count;
- total relevant spend;
- share of eligible portfolio spend;
- supporting merchant/category breakdown;
- confidence and unresolved-data share;
- best eligible owned-card result;
- best eligible overall-market result;
- estimated incremental value; and
- explanation and applicable caveats.

Do not force a recommendation when data or benefits are insufficient. The spend
insight may still be useful without a card result.

## Insight 1: maximum-spend category

Aggregate eligible spend by the canonical 16-category taxonomy. Return the
category with the greatest billed spend, its amount, transaction count, and
share of total eligible spend.

Recommendations evaluate category-specific rules, merchant/MCC restrictions,
caps, thresholds, international-spend rules, and remaining cycle usage.

## Insight 2: maximum-spend merchant

Aggregate by canonical merchant identity. Report amount, transaction count,
average purchase size, and share of eligible spend.

Use merchant-specific benefits first. If none apply, fall back to the merchant's
category/MCC context. Keep marketplace and underlying merchant identities
separate unless the rule explicitly covers the marketplace.

## Insight 3: movie platform

Historical insight detects eligible entertainment/movie transactions from
merchant, platform metadata, category, and movie-platform aliases. Prospective
optimization accepts platform, cinema, ticket count, and ticket price.

Evaluation is delegated to the specialized movie rule engine described in
[Movie platform and specialized offers](06-movie-platform-and-specialized-offers.md).

## Insight 4: travel merchants

Include airlines, hotels, travel portals, rail, car rental, and eligible travel
services. Preserve subtypes such as flight, hotel, portal, and local transport
as attributes without expanding the primary category vocabulary.

Evaluate portal/airline-specific rules, broad travel accelerators,
international-spend rewards, milestones, and relevant travel benefits. Do not
assign a cash value to non-cash perks such as lounge access without an approved
valuation policy.

## Insight 5: e-commerce merchants

Include online marketplaces and direct online merchants. Distinguish:

- named-merchant rewards;
- general online-spend rewards;
- temporary issuer sale offers; and
- offline or payment-rail transactions that are not e-commerce.

Apply membership, EMI, channel, minimum order, monthly cap, and payment-method
restrictions. A payment gateway does not make every processed purchase eligible
for its merchant offers.

## Insight 6: food and grocery merchants

Report food and grocery independently, with an optional combined
everyday-essentials summary. Merchant subtype may distinguish restaurants,
delivery, supermarkets, quick commerce, and direct grocery merchants.

Rank merchant-specific value and broad food/grocery accelerators on the same
net-value basis, respecting online/offline and MCC conditions.

## Insight 7: fuel merchants

Use verified merchant identity and MCC where possible. Evaluate rewards or
cashback independently from fuel-surcharge waiver rules, then combine only when
the terms permit stacking.

Apply eligible transaction bands, monthly caps, fuel-brand restrictions,
minimum values, and waiver limits. Keyword-only fuel identification lowers
confidence.

## Ranking handoff

An insight sends the recommendation engine a structured context containing:

- insight type;
- period;
- total and representative transaction amounts;
- category and subtype;
- canonical merchant;
- MCC plus source/confidence;
- channel/platform;
- domestic/international status; and
- spend frequency.

The insight layer does not duplicate card-benefit calculations.

## Empty and low-confidence states

- No eligible transactions -> explain that more spend history is needed.
- Majority unresolved category/merchant -> show the aggregation but withhold or
  caveat recommendations.
- No applicable active benefit -> show the insight and say no verified card
  advantage was found.
- Tied spend groups -> show both or use amount, then transaction count as the
  deterministic tie-break.

## Acceptance criteria

- Default dashboard period is 60 days.
- Portfolio recommendation basis is 90 days.
- Non-spend ledger rows and reconciled duplicates do not affect totals.
- All seven insight families can return best-owned and best-overall results.
- Every result discloses period, spend basis, value, and assumptions.
- Insufficient data produces a useful empty state rather than fabricated advice.

## Supporting references

- Main repo: `docs/superpowers/2026-07-14-ledger-transactions-and-analytics.md`
- Main repo: `COMPETITIVE_ANALYSIS_AND_ROADMAP.md`
