# Movie Deals — Readiness Gaps Specification

**Date:** 2026-08-02  
**Last reviewed:** 2026-08-02, after Design §1.2 corrections  
**Status:** Approved with blocking prerequisites after the remaining P0/P1 items are resolved  
**Branch:** `feature/landing-v2`  
**Worktree scope:** `cardcompass-landing-v2` only  
**Companion design:** `docs/superpowers/specs/2026-08-02-movie-deals-design.md`  
**Companion plan:** `docs/superpowers/plans/2026-08-02-movie-deals.md`

---

## 1. Purpose

This document is the implementation-readiness gate for Movie Deals. It records which earlier findings the revised design has resolved and which gaps still remain after re-reading Design §1.2 against the v2 migration chain, seed data, current statement ingestion, and implementation plan.

The design is now conceptually sound. It should not be implemented from the current plan, or described as producing trustworthy recommendations, until every P0 and P1 item below is resolved or explicitly removed from scope.

## 2. Findings resolved by the revised design

The following earlier findings are closed at the design level:

- Per-transaction caps and whole-cycle amount caps are separate concepts.
- `max_usage_per_month` is correctly described as a redemption limit, not a ticket limit.
- Partner data comes from `benefits.partners`, merged with `value_config.platform` where present.
- Cinema filtering is explicitly documented as unsupported by current data.
- Empty mappings and the schema/migration column-type disagreement are identified as blocking prerequisites.
- Mapping provenance and the SimplyCLICK/ELITE data defect are explicitly acknowledged.
- `validityStart` and `validityEnd` are included in the canonical rule.
- Guaranteed and potential savings are separated into different ranking tiers.
- Platform confirmations are specified as benefit-scoped rather than card-scoped.
- Confirmation storage includes normalization, uniqueness, and aggregate-only reads.
- The widened fetch requires the JSONB predicates from Design §4.1.
- The platform vocabulary must come from observed partner data rather than the previous static list.
- Verification now requires exhaustive seed-row fixtures and a clean-database integration check.

These items remain open in the implementation plan until the plan is synchronized with the revised design.

## 3. Remaining gaps

| Priority | Missing or misaligned item | Evidence | Why it is important | Required correction |
|---|---|---|---|---|
| P0 | The implementation plan still implements the pre-§1.2 design | `docs/superpowers/plans/2026-08-02-movie-deals.md` still contains card-level confirmation context, raw-savings-first ranking, the old confirmation migration, the incomplete widened query, and a static platform list. See approximately lines 1095, 1713, 1766, 2192, 2228, and 2533. | Executing the current plan would recreate several defects the revised design explicitly resolves. | Rewrite the affected plan tasks before implementation: rule/context models, evaluator, migration, repository/query, provider/result model, UI, and tests. |
| P0 | The UI examples still use commercially invalid or unverified card-benefit associations | Design §3.1 identifies the SimplyCLICK/ELITE association as incorrect. Design §8 nevertheless shows “SBI Card Simplyclick — Up to ₹6,000/year” in the Potential mockup. The HDFC Millennia/BookMyShow example is also not demonstrated to come from an approved mapping. | A specification should not normalize or advertise an association it identifies as invalid, even in a potential-results example. It undermines the commercial-provenance prerequisite. | Replace concrete examples with commercially verified mappings. Until curated mappings exist, use neutral placeholders rather than real card names. |
| P1 | `transaction_date` does not make benefit usage verifiable by itself | Design §7 now requires date-bounded transactions, but current ingestion in `lib/core/services/statement_processing_service.dart` stores merchant transactions without `benefit_id`, redemption state, ticket count, discount used, or platform metadata. | A merchant charge proves a purchase occurred; it does not prove which offer was redeemed or how much of a monthly or annual cap was consumed. Counts inferred from ordinary transactions can be wrong. | Introduce a benefit-redemption ledger or a populated metadata contract containing at least `benefit_id`, canonical platform, redemption count, discount used, and cycle. Keep capped offers potential/unverified until this signal exists. |
| P1 | Guaranteed-tier membership does not require confirmed platform applicability | Design §5 defines the guaranteed tier primarily from usage confidence or absence of a usage cap. The same section permits a candidate with no partner record to be `unconfirmed`. | Savings are not guaranteed when the system does not know whether the offer works on the selected platform. Such a candidate can still become the primary winner. | Require platform certainty as part of guaranteed-tier eligibility. At minimum require `platformConfidence == explicit`; if community reports are accepted, place `communityConfirmed` in a separately labeled reported-working tier or treat it as potential. |
| P1 | General benefit partners are still treated as movie-booking platforms | Real multi-purpose benefits list partners such as Uber, cult.fit, Big Basket, OYO, Swiggy, and BookMyShow. Design §8 proposes deriving dropdown choices from distinct partners across fetched benefits. | This can offer irrelevant choices such as Uber as a movie platform and can treat every partner on a multi-purpose benefit as eligible for its movie component, even though the data does not map categories to individual partners. | Derive a separate canonical `moviePlatforms` projection. Include only verified movie-booking partners and aliases, such as `District by Zomato` → `Zomato`. Quarantine ambiguous multi-partner rules from platform-specific guarantees. |
| P1 | Prior-month milestone selection is not defined precisely enough | Design §7 requires prior-month spend from `statement_milestone_cache`, whose authoritative fields are statement-cycle start/end dates. The existing plan selects `card_id`, `total_spending`, and `last_updated`, then takes the newest row. | The latest updated row may represent the current cycle or an unrelated category, producing false milestone eligibility. Credit-card statement cycles also need not align with calendar months. | Define the exact lookup: the most recently completed statement cycle for the owned card, ending before the evaluation date, with the required category/benefit association. Fetch `statement_start_date` and `statement_end_date` and add boundary tests. |
| P1 | Exclusion analysis covers only entertainment-tagged rows, not the full widened candidate set | Design §4.2 declines exclusion fields because the entertainment subset has empty exclusion shells. The widened fetch also includes `rewards`, `offers`, `dining`, and `lifestyle` rows; matching examples such as the Paytm movie reward row contain non-empty exclusion categories in `restore_reference_data.sql`. | The population used to justify omitting exclusions is narrower than the population evaluated at runtime. Relevant restrictions can be silently ignored. | Analyze exclusions across every row matching Design §4.1. Normalize observed, decision-relevant exclusion shapes or reject/quarantine candidates whose restrictions cannot be represented safely. |
| P1 | The column-type fix must occur before the incompatible seed migration, not merely afterward | Design §3.1 correctly requires JSONB before the JSON-formatted seed is loaded. A normally appended corrective migration runs after the initial schema and restore-data migrations. | If the restore migration cannot load JSON-array syntax into `TEXT[]`, migration execution fails before reaching a later correction. | Correct the baseline migration, change the seed payload to valid PostgreSQL-array syntax, or add an ordered migration between the initial-schema and restore-data timestamps. Prove the complete chain with `supabase db reset`. |
| P1 | “Reinstate mappings” could restore mappings already known to be invalid | Design §3.1 separately says mappings must be reinstated and commercially verified. A mechanical restoration of the raw seed mappings would include the SimplyCLICK/ELITE defect and similar associations. | Restoring the old relationship set would make the database non-empty while preserving the exact commercial correctness problem that blocks trustworthy recommendations. | State that the migration inserts only curated, approved mappings. Make approval/provenance an enforceable repository eligibility condition rather than an informal operational expectation. |
| P2 | Confirmation inserts are not fully specified as idempotent | Design §6 adds a unique constraint and states that a repeat click does not fail visibly, but a normal insert against the constraint raises a uniqueness error. | A harmless repeat confirmation can surface as a UI error even though it should be treated as success. | Require an upsert/ignore-duplicate operation targeting `(user_id, benefit_id, platform_key)`, or catch SQLSTATE `23505`. Explicitly specify base-table privilege revocation and aggregate-view/RPC grants. |
| P2 | Potential-only result semantics are ambiguous | Design §5 allows `bestOwned` and `bestOverall` to fall back to potential candidates, while Design §8 places potential candidates in a separate non-winner section. | A potential-only candidate can be duplicated or placed in a field whose name encourages the UI to call it a winner. | Model tiered results explicitly, for example `bestGuaranteedOwned`, `bestGuaranteedOverall`, `bestPotentialOwned`, and `bestPotentialOverall`. Never place a potential result in a guaranteed-winner field. |
| P2 | The widened JSONB OR query is not defined as executable query-builder code | Design §4.1 describes several alternatives joined by OR but mentions individual `.filter(...)` calls. Separate Supabase filters normally combine as AND unless assembled into a compatible `.or(...)` expression. | An implementation may appear to include every predicate while accidentally requiring all of them, silently returning fewer candidates. | Specify and test the exact PostgREST `.or(...)` expression or implement the candidate fetch as an SQL/RPC function. The JSON-only case must be a real query-builder/integration test, not only a fake-data-source test. |
| P3 | Design-system references remain inaccurate | Design §8 refers to `AppTheme.primaryColor` and Plus Jakarta Sans as established Flutter-app tokens. The v2 app uses `AppColors.neonCyan` and Inter for body typography. | Literal implementation can cause a compile error or visual inconsistency. | Replace the references with `AppColors.neonCyan` and the existing Space Grotesk/Inter typography. |
| P3 | This readiness document and the plan need explicit lifecycle status | The design now incorporates many former gaps, while the implementation plan still contains their old behavior. | Without status labels, an implementer can mistake the old plan or the earlier findings for the current source of truth. | Mark the current plan “Needs revision for Design §1.2” until regenerated. Treat the latest design plus this readiness gate as authoritative in the interim. |

## 4. Implementation-readiness criteria

Movie Deals is ready for implementation only when all of the following are true:

- [ ] The implementation plan has been regenerated or comprehensively synchronized with Design §1.2.
- [ ] A clean `supabase db reset` succeeds with the intended JSONB/array column contract.
- [ ] The migration chain inserts only curated and commercially approved card-benefit mappings.
- [ ] UI examples and fixtures use approved mappings or neutral placeholders.
- [ ] Guaranteed-tier eligibility requires both usage certainty and platform certainty.
- [ ] Capped benefit usage is backed by a real redemption/usage signal, or those candidates remain potential.
- [ ] Prior-month milestones use a precisely selected completed statement cycle.
- [ ] Exclusions have been evaluated across every row matched by the widened query.
- [ ] Movie-platform choices are distinct from general benefit partners and use canonical aliases.
- [ ] Confirmation writes are idempotent and confirmation reads expose aggregates only.
- [ ] Guaranteed and potential result types cannot be confused or rendered twice.
- [ ] The widened fetch uses a tested OR query including the JSONB-only case.
- [ ] The screen uses existing v2 theme tokens and typography.
- [ ] Exhaustive seed fixtures and the clean-database integration check pass.

## 5. Recommended resolution order

1. Repair the migration ordering/type contract and create curated approved mappings.
2. Replace invalid design examples and define enforceable mapping provenance.
3. Regenerate the implementation plan from the revised design.
4. Define guaranteed-tier eligibility, including platform confidence.
5. Define the benefit-redemption signal and exact milestone-cycle lookup.
6. Separate movie platforms from general partners and complete exclusion analysis.
7. Finalize confirmation idempotency, tiered result types, and the executable widened query.
8. Correct theme references and run the exhaustive/unit/widget/integration verification suite.

Until steps 1–5 are complete, the feature may be prototyped visually but should not be described as producing trustworthy best-card recommendations.
