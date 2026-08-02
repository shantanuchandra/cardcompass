# Movie Deals — Readiness Gaps Specification

**Date:** 2026-08-02  
**Status:** Needs resolution before implementation  
**Branch:** `feature/landing-v2`  
**Worktree scope:** `cardcompass-landing-v2` only  
**Companion design:** `docs/superpowers/specs/2026-08-02-movie-deals-design.md`  
**Companion plan:** `docs/superpowers/plans/2026-08-02-movie-deals.md`

---

## 1. Purpose

This document records the remaining gaps found during the post-correction review of the Movie Deals design and implementation plan. It is an implementation-readiness gate: the feature should not be treated as capable of producing trustworthy recommendations until every P0 and P1 item below is either resolved or explicitly removed from the promised scope.

## 2. Corrections already incorporated

The revised design and plan correctly address several earlier problems:

- Per-transaction discount caps and whole-cycle amount caps are now separate concepts.
- `max_usage_per_month` is correctly described as a redemption limit, not a ticket limit.
- Platform and merchant data now comes from `benefits.partners`, merged with `value_config.platform` when present.
- Cinema filtering is explicitly documented as unsupported by the current data rather than silently presented as working.
- BOGO presentation copy now describes redemptions per month correctly.

These corrections are sound, but they do not resolve the data-foundation, eligibility, usage-tracking, ranking, and confirmation issues below.

## 3. Remaining gaps

| Priority | Missing or misaligned item | Evidence | Why it is important | Required correction |
|---|---|---|---|---|
| P0 | No reproducible card-benefit mappings | `supabase/migrations/20260713180753_normalize_card_benefit_mappings.sql:3-6` deletes all rows from `card_benefit_mapping` and no later migration repopulates them. | A clean v2 database can fetch benefits but cannot associate them with cards, so Movie Deals produces no candidates. | Add a migration containing approved mappings, or define a verified production bootstrap process. Add a clean-database integration test asserting that mapped movie candidates exist. |
| P0 | Migration schema disagrees with the schema assumed by the design | `schema.sql:73-75` defines `partners`, `exclusions`, and `regions` as JSONB, while `supabase/migrations/20260711043541_initial_schema.sql:66-80` defines them as `TEXT[]`. Seed values use JSON-style data. | Migrations are the reproducible database source. Clean environments may fail to load the seed or expose different types from production, invalidating partner parsing and tests. | Add a migration that establishes the intended JSONB types before compatible data is loaded. Verify the complete chain with `supabase db reset`. |
| P0 | No commercial-validity gate for card-benefit associations | `supabase/migrations/20260711043900_restore_reference_data.sql:320` contains an SBI Card ELITE movie allowance and line 1450 maps it to SimplyCLICK. Similar repeated associations exist for unrelated cards. | Normalizing a field shape does not prove that the benefit belongs to the mapped card. Bad associations can create confidently incorrect purchase and acquisition recommendations. | Use curated, approved mappings backed by card-specific source URLs. Add provenance/approval state and negative regression cases, including that SimplyCLICK does not receive ELITE benefits. |
| P1 | Eligibility data promised by the spec is absent from the rule model and repository query | Design §7 promises active-date, weekday, exclusion, and minimum-transaction checks. `MovieBenefitSource` in the plan carries only identifiers, title, `valueConfig`, partners, URL, card name, and priority. The evaluator checks only platform, milestone, and BOGO usage. | Expired or ineligible offers can be ranked as winners while the product claims that eligibility was verified. | Add `validFrom`, `validUntil`, exclusions, qualifying days, and minimum transaction amount to the source and rule models, fetch them, normalize them, and test them. Otherwise remove these checks from the current scope and UI claims. |
| P1 | Cycle, annual, and prior-month usage cannot be calculated from current v2 data | The planned transaction query omits `transaction_date`; the milestone query omits statement-cycle dates. Current statement ingestion in `lib/core/services/statement_processing_service.dart` does not write ticket count, platform, redemption, or discount-used metadata. | Monthly redemption limits, remaining monthly caps, remaining annual allowances, and prior-month milestone eligibility cannot be verified. | Define a benefit-usage metadata contract or dedicated redemption ledger. Query explicit cycle windows. Until populated usage exists, present affected benefits as informational or potential—not verified savings. |
| P1 | Unverified savings outrank verified savings | The planned evaluator assigns the full annual cap as current savings and sorts by savings before usage confidence (`movie-deals.md`, evaluator `_calculateSavings` and `_compareCandidates`). | An uncertain ₹6,000 allowance can beat a verified ₹500 discount even when the allowance may already be exhausted. This conflicts with “guaranteed savings” and “trustworthy recommendation.” | Separate `guaranteedSavings` from `potentialSavings`. Rank verified direct savings first and place benefits with unknown remaining usage in a clearly labeled potential-benefit section. |
| P1 | Community-confirmation state leaks between benefits on the same card | The repository groups confirmations by benefit, then unions the sets into a `MovieDealContext` keyed only by catalog card (`movie-deals.md`, repository snapshot construction). | A confirmation for benefit A can incorrectly promote benefit B on the same card to `communityConfirmed`. | Key evaluation context by `(catalogCardId, benefitId)` or pass a `confirmedPlatformsByBenefit` map directly to the evaluator. Add a two-benefits-on-one-card regression test. |
| P1 | The live widened query does not implement all design predicates | Design §4.1 requires JSON checks against `value_config.category` and `value_config.discount_type`. The plan filters only `benefit_category`, `title`, and `description`. | A valid benefit whose only movie signal is structured inside `value_config` can be silently omitted. | Implement and test the JSONB predicates through PostgREST or a small SQL/RPC function. Include a fixture whose only movie signal is inside `value_config`. |
| P2 | The platform selector does not represent the partner vocabulary now used by the model | The plan offers `BookMyShow`, `PVR`, `INOX`, `Cinepolis`, and `Moviemax`. Real partner data includes Zomato/District, Paytm, Uber, and others, while the design acknowledges that the listed cinema chains have no structured matching data. | Users cannot select several real booking partners, while unsupported selections mostly produce unconfirmed results. | Define a canonical movie-booking-platform vocabulary and alias map, including `District by Zomato` → `Zomato`. Populate the selector from supported canonical values and remove or disable unsupported cinema filtering. |
| P2 | Crowd confirmations lack uniqueness, normalization, and privacy boundaries | The planned table has no uniqueness or nonblank-platform constraint. Authenticated users receive direct read access to confirmation rows, including `user_id`. Only positive reports are modeled despite yes/no wording. | Duplicate reports, spelling variants, and direct reporter exposure weaken the trust and privacy of the crowd signal. One report currently creates `communityConfirmed` status. | Add a normalized platform key, a nonblank check, and `UNIQUE(user_id, benefit_id, platform_key)`. Expose aggregate counts through a view/RPC without reporter IDs. Decide whether negative reports and a minimum number of unique reporters are required. |
| P2 | The promised all-seed-row regression test is only a representative fixture set | Design §12 promises evaluation of every seed row matching the widened fetch query. The plan hardcodes a small list of representative configurations. | New, malformed, or commercially invalid seed rows can bypass the regression guard intended to prevent the original failures. | Generate a checked-in fixture from every matching migration row, including mapping/provenance data and an expected accepted, rejected, or quarantined outcome. |

## 4. Implementation readiness criteria

Movie Deals is ready for implementation only when all of the following are true:

- [ ] A clean v2 migration run succeeds and produces approved card-benefit mappings.
- [ ] JSONB/array column types have one authoritative definition across migrations and schema documentation.
- [ ] Mappings used by recommendations have card-specific commercial provenance and approval.
- [ ] Every eligibility check claimed by the design is represented in the rule model and covered by evaluator tests.
- [ ] Cycle and annual usage either have a populated, date-bounded tracking contract or are explicitly excluded from guaranteed savings.
- [ ] Verified and potential savings are represented and ranked separately.
- [ ] Platform confirmations remain scoped to a single benefit and canonical platform.
- [ ] The widened live query includes every predicate specified by Design §4.1.
- [ ] Platform options align with real canonical partner data and aliases.
- [ ] Confirmation aggregation does not expose reporter identities or count duplicate reports from one user.
- [ ] The regression fixture covers every matching seed row and its approved mapping outcome.

## 5. Recommended resolution order

1. Repair migration reproducibility and establish approved mappings.
2. Add commercial provenance and quarantine invalid associations.
3. Align the canonical rule model with the eligibility claims.
4. Define usage tracking and separate verified savings from potential value.
5. Correct benefit-level confirmation scoping and confirmation-table integrity.
6. Complete the widened query and exhaustive seed fixture.
7. Align platform choices and aliases with the real partner vocabulary.

Until steps 1–4 are complete, the feature may be prototyped visually but should not be described as producing trustworthy best-card recommendations.
