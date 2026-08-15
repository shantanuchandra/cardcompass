# Movie Platform and Specialized Offers

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

Recommend the best eligible owned card and best eligible overall-market card
for a movie-ticket purchase without presenting uncertain platform eligibility
or unknown remaining quota as guaranteed savings.

## Inputs

The prospective optimizer accepts:

- ticket count;
- ticket price;
- platform, optional;
- cinema, optional/contextual; and
- purchase date/current benefit cycle.

Historical insight may infer movie spend from canonical merchant, entertainment
category, platform metadata, and the curated movie-platform alias registry.

## Candidate sources

Movie candidates come from active approved benefit mappings, not from a narrow
`entertainment` category query alone. The repository considers benefit title,
description, type, partners, value configuration, and exclusions because real
catalog rows encode movie offers inconsistently.

Owned candidates resolve through active `user_cards`. Overall candidates follow
the market and likely-eligibility restrictions in the general recommendation
engine.

## Canonical movie rule

The normalizer supports:

- percentage discount;
- fixed discount;
- BOGO/free-ticket structures;
- annual or cycle allowance;
- milestone benefit; and
- reward multiplier.

Rules may include:

- ticket/buy/free counts;
- discount value;
- per-transaction cap;
- cycle redemption limit;
- annual allowance;
- minimum transaction;
- platform/partner set;
- eligible and excluded categories;
- validity dates; and
- milestone or membership conditions.

Partners and platform compatibility are interpreted through the checked-in
alias registry and corrected `eligibleMoviePlatforms` logic. Raw partner text is
not treated as verified platform support without interpretation.

## Evaluation

For each candidate:

1. Confirm card availability and eligibility.
2. Normalize the offer.
3. Check date, platform, amount, ticket count, exclusions, and prerequisites.
4. Determine whether remaining quota/allowance is known.
5. Calculate direct savings or report reward rate without inventing cash value.
6. Apply per-transaction and cycle caps.
7. Place the result in the correct confidence tier.

## Result tiers

### Guaranteed

All material eligibility conditions are satisfied and the calculation does not
depend on unknown remaining quota or unverified platform support.

### Potential

The benefit may apply, but platform compatibility, remaining balance, cycle
usage, milestone state, or another material condition is not verified.

### Reward-rate only

The offer earns points/cashpoints/rewards but lacks a grounded rupee redemption
value. Display the rate and program context, never fabricated cash savings.

Owned and overall results are ranked independently within these tiers. A
potential result must not displace a guaranteed result without making the tier
difference unmistakable.

## Platform confidence

Use the corrected confidence states defined by Movie Deals v2, including the
distinction between a platform not requested, confirmed compatibility,
community confirmation, and unconfirmed compatibility.

Community feedback may improve platform confidence through the existing
confirmation system. It does not rewrite canonical bank terms.

## Savings rules

- Percentage discount: apply percentage to eligible amount, then cap.
- Fixed discount: apply no more than eligible amount or cap.
- BOGO: derive free-ticket count from ticket quantity and rule, then cap.
- Allowance: limit by known remaining allowance; otherwise potential.
- Milestone: guaranteed only when milestone state is verified as satisfied.
- Reward multiplier: return rate/program context unless redemption value is
  grounded.
- Never double count stacked offers unless explicitly allowed.

## User experience

The result surface clearly separates:

- best guaranteed card owned;
- best guaranteed card overall;
- potential owned/overall alternatives; and
- reward-rate-only cards.

Each card shows expected savings/rate, ownership, applicable platform, caps,
remaining-usage confidence, eligibility caveats, and the rule explanation.

## Failure and empty states

- Invalid ticket inputs -> inline validation.
- No movie benefit -> explain that no verified offer matched.
- No owned match but overall match -> show the overall result without inventing
  an owned recommendation.
- Unverified platform -> potential, not guaranteed.
- Unknown remaining balance -> potential.
- Malformed rule -> skip it and continue.
- Repository/network failure -> user-readable error without exposing raw errors.

## Acceptance criteria

- Movie optimization never recommends an unowned card as the best-owned card.
- Overall results stay within market and likely eligibility.
- Guaranteed and potential results are visually and semantically separate.
- BOGO, percent, fixed, allowance, milestone, and multiplier fixtures evaluate
  correctly.
- Reward multipliers do not display invented rupee savings.
- Platform confidence uses normalized eligible platforms, not raw partner text.

## Future specialized engines

The same architecture may later support e-commerce bank-sale offers and
no-cost-EMI-versus-rewards decisions. Those are not part of the MVP source of
truth until separately designed and approved.

## Supporting references

- `docs/superpowers/specs/2026-08-02-movie-deals-design.md`
- `docs/superpowers/specs/2026-08-02-movie-deals-readiness-gaps.md`
- `docs/superpowers/plans/2026-08-02-movie-deals-v2.md`
- Main repo: `docs/superpowers/2026-07-15-movie-deals-rule-engine.md`
