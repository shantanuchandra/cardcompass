# Movie Deals — Readiness Gaps Specification

**Date:** 2026-08-02
**Last reviewed:** 2026-08-02, after the latest Movie Deals design revision
**Status:** Approved with blocking prerequisites after the remaining P0/P1 items are resolved
**Branch:** `feature/landing-v2`
**Worktree scope:** `cardcompass-landing-v2` only
**Companion design:** `docs/superpowers/specs/2026-08-02-movie-deals-design.md`
**Companion plan:** `docs/superpowers/plans/2026-08-02-movie-deals.md`

---

## 1. Purpose

This document is the implementation-readiness gate for Movie Deals. It records which findings the latest design resolves and which gaps remain after checking the design against the v2 migration chain, seed data, statement ingestion, milestone cache, and implementation plan.

The revised design is substantially aligned with the intended product outcome: trustworthy movie-benefit recommendations separated into guaranteed and potential tiers. It is not fully implementation-ready until every P0 and P1 item below is resolved or explicitly removed from scope.

## 2. Findings resolved by the revised design

The latest design closes the following earlier findings at the specification level:

- Card-benefit mappings must be curated and commercially approved; raw mappings must not be restored mechanically.
- The incompatible benefit column types must be corrected before the seed migration runs.
- The widened fetch must use an executable PostgREST OR expression or an RPC, including an integration test for JSONB-only discovery.
- The canonical rule includes validity dates and decision-relevant excluded categories.
- Exclusions must be evaluated across the complete widened candidate population, not only entertainment-tagged rows.
- Guaranteed-tier membership requires both usage certainty and explicit platform applicability.
- Recommendation output is split into `bestGuaranteedOwned`, `bestGuaranteedOverall`, `bestPotentialOwned`, and `bestPotentialOverall`.
- Duplicate platform confirmations use conflict-safe insertion behavior.
- Milestone selection is based on a completed statement cycle rather than the most recently updated cache row.
- Movie-platform choices exclude unrelated general partners and normalize aliases such as District by Zomato to Zomato.
- Mockups use neutral placeholders until commercially approved mappings exist.
- UI guidance now references the existing Space Grotesk/Inter typography and `AppColors.neonCyan` token.
- The design explicitly records that the current implementation plan has drifted and must not be executed unchanged.

These closures do not make the current implementation plan correct. They become implementation-ready only after the plan and tests are synchronized with the design.

## 3. Remaining gaps

| Priority | Missing or misaligned item | Evidence | Why it is important | Required correction |
|---|---|---|---|---|
| P0 | The plan-rewrite scope in Design §14 contradicts its own drift analysis | Design §14 identifies missing `excludedCategories`, validity handling, normalizer behavior, and non-exhaustive fixtures, but its final paragraph says Tasks 1–4 remain accurate and only Tasks 5–8 and 11 require rewriting. | Task 1 cannot represent the canonical rule, and the normalization and fixture tasks cannot satisfy the revised contract. Following the stated rewrite list would preserve known defects before implementation begins. | Regenerate or reassess the complete plan. At minimum, rewrite every task affected by canonical fields, normalizers, fixtures, evaluation, persistence, queries, providers, UI, and verification; do not exempt Tasks 1–4 without a line-by-line proof. |
| P1 | A dated merchant transaction still does not prove that a benefit was redeemed | Design §7 bounds matching transactions to the current cycle. Current ingestion stores ordinary merchant transactions without `benefit_id`, canonical platform, redemption count, ticket count, discount consumed, or an offer-redemption state. | A BookMyShow charge proves that a purchase occurred, not that a particular BOGO, fixed-discount, or capped benefit was used. Treating it as usage can overstate remaining allowance and present uncertain savings as guaranteed. | Add a benefit-redemption ledger or an explicit populated redemption metadata contract. Until such a signal exists, keep capped BOGO, fixed-discount, and annual-allowance candidates in the potential tier even when a related transaction exists. |
| P1 | “Any Platform” turns missing platform evidence into explicit confidence | Design §5 says that when no platform is selected every otherwise eligible rule has `explicit` platform confidence; the guaranteed tier also requires `explicit`. | Not requesting a platform removes a comparison constraint, but it does not prove that a rule is platform-agnostic. A rule with missing or ambiguous partner data can consequently be presented as guaranteed. | Add a separate state such as `notRequested` or `unknownPlatform`. Permit guaranteed classification only for explicitly matched partners or terms that are explicitly documented as platform-agnostic. Keep empty/ambiguous partner rules potential under “Any Platform.” |
| P1 | Milestone cache rows are not unambiguously associated with a benefit | Design §7 specifies completed-cycle selection, but `statement_milestone_cache` associates spending with a card/user-card and broad benefit category rather than `benefit_id`. Movie-relevant milestones can be tagged `lifestyle`, and a card can have multiple milestones. | Filtering only `entertainment` can miss a valid movie-relevant milestone; filtering only by card can apply spending from the wrong category or milestone. This can create false guaranteed eligibility. | Prefer a `benefit_id` association in the milestone cache or a dedicated benefit-progress record. If schema expansion is rejected, define a deterministic category association and collision policy, and cover lifestyle-tagged movie milestones and multiple milestones per card in tests. |
| P1 | The `moviePlatforms` projection has no owned, reproducible data contract | Design §8 says to derive movie platforms by cross-referencing movie relevance with partners and to normalize aliases. The current benefit model does not encode which partner belongs to which category inside a multi-purpose benefit. | Different implementations can classify the same generic partner list differently. Unrelated partners may reappear in filters or a movie benefit may be guaranteed for a partner whose applicability is not established. | Define an owned canonical movie-platform registry/alias map, its file or table, update ownership, and deterministic inclusion rules. Normalize each candidate to `eligibleMoviePlatforms`; quarantine ambiguous multi-partner candidates from platform-specific guarantees. |
| P2 | Aggregate confirmation-read security is not specified as executable permissions | Design §6 creates an aggregate view and states that clients must not read individual confirmation rows, but it does not prescribe view ownership/security mode or the required `REVOKE` and `GRANT` statements. | The privacy boundary is only reliable when the base table is inaccessible to authenticated clients and the aggregate interface can still read it under a deliberate security model. | Specify and test exact privileges. Revoke base-row reads, grant only the required insert privilege, and expose aggregation through either a fixed-output owner-backed view or a security-definer RPC with a fixed `search_path`. |
| P2 | The design status and scope understate its blocking prerequisites | The header says `Approved`, while the schema scope emphasizes the new confirmation table even though implementation also depends on baseline type corrections and curated mapping changes. | An implementer may treat prerequisite migration/data work as outside the approved scope or begin feature work before the data contract is viable. | Change the design status to `Approved with blocking prerequisites` and explicitly include the prerequisite migration and curated-data changes in authorized implementation scope. |

## 4. Implementation-readiness criteria

Movie Deals is ready for implementation only when all of the following are true:

- [ ] The implementation plan has been regenerated or comprehensively synchronized with the latest design, including every affected early model, normalization, and fixture task.
- [ ] A clean `supabase db reset` succeeds with the intended JSONB/array column contract.
- [ ] The migration chain inserts only curated and commercially approved card-benefit mappings.
- [ ] Capped benefit usage is backed by a real benefit-level redemption signal, or all such candidates remain potential.
- [ ] “Any Platform” cannot convert missing or ambiguous platform evidence into guaranteed applicability.
- [ ] Milestone progress is associated unambiguously with the evaluated benefit and a completed statement cycle.
- [ ] `moviePlatforms` and `eligibleMoviePlatforms` come from an owned canonical registry with deterministic aliases and ambiguity handling.
- [ ] Confirmation writes are idempotent, base confirmation rows are inaccessible to clients, and aggregate reads have explicit tested permissions.
- [ ] The design status and implementation scope include all blocking schema and curated-data prerequisites.
- [ ] Guaranteed and potential result types cannot be confused or rendered twice.
- [ ] The widened fetch uses a tested OR query including the JSONB-only case.
- [ ] Exhaustive seed fixtures and clean-database integration checks pass.

## 5. Recommended resolution order

1. Correct Design §14 and regenerate the implementation plan from the latest design.
2. Define the benefit-level redemption signal and milestone-to-benefit association.
3. Correct platform confidence semantics for “Any Platform.”
4. Establish the canonical movie-platform registry and per-rule projection.
5. Finalize confirmation-view/RPC privileges and security tests.
6. Update the design status and scope to include its blocking prerequisites.
7. Run the clean migration, exhaustive fixture, unit, widget, and integration verification suite.

Until steps 1–4 are complete, the feature may be prototyped visually but must not be described as producing trustworthy best-card recommendations.
