# Benefit Refresh Review and Mapping-Only Design

## Purpose

Make the benefit-refresh review understandable at a glance, let an operator accept or reject each candidate benefit or a selected group, and return card-to-benefit ownership to `card_benefit_mapping`.

## Scope

This work changes the admin refresh-review experience and the persistence path used when an approved extraction is applied. It does not rerun AU Zenith or alter staging data as part of the schema migration.

## Review experience

The refresh dialog has two persistent regions on desktop and stacks on narrow screens.

- **Pipeline trace rail:** Shows the exact, ordered checkpoint flow below. Completed stages are teal, the active stage is cyan, future stages are muted, and terminal failure branches are visible but inactive. The active checkpoint is derived from the extraction/staging state.
- **Candidate benefits:** Shows the current active mappings beside the candidate benefits. Every candidate has an explicit Accept or Reject action. Operators can also select unresolved candidates and accept or reject the selected set in one action.

The exact checkpoint sequence is:

1. Select only the requested card.
2. Load official URL from `card_catalog`.
3. Scrape the bank product page.
4. Validate page identity: bank and card.
5. On valid identity, Gemini extracts fees, rewards, cashback, and special benefits. On invalid identity, stop and record the failure.
6. Ground every extracted claim against scraped evidence.
7. On rejected grounding, save a rejected staging record and leave active benefits unchanged. On accepted grounding, save a pending `card_benefits_staging` record.
8. Show current active data versus candidate data.
9. Operator review: discard leaves active data unchanged. Approval revalidates stored evidence. A passing revalidation applies only accepted candidate items for the selected card and marks the staging record approved; a failing revalidation marks it rejected and leaves active data unchanged.

Decision controls provide visible labels, 44px minimum hit areas, keyboard focus states, disabled/loading feedback during persistence, and text labels in addition to color.

## Candidate decisions

`card_benefits_staging.extracted_data` remains the immutable candidate snapshot. The review UI maintains decision state per normalized candidate item:

- `accepted`: eligible for application.
- `rejected`: retained in the staging audit record but excluded from application.
- `unresolved`: blocks final approval until resolved or explicitly bulk-accepted/rejected.

Bulk actions apply only to selected unresolved items. The final approval action remains disabled until all candidate items are resolved. A rejection-only review can finish the staging record without changing active mappings.

The stored staging record must retain per-item decisions and decision timestamps so a future audit can distinguish source extraction from operator judgment.

## Data model

`benefits` is the canonical benefit definition table.

`card_benefit_mapping` is the sole relationship between a catalog card and a canonical benefit. It owns `card_id`, `benefit_id`, display priority, and primary status.

`card_benefits` becomes a historical generic benefit-value/configuration table. It retains exactly:

- `id`
- `benefit_id`
- `value`
- `spending_categories`
- `monthly_cap`
- `annual_cap`
- `valid_from`
- `valid_to`
- `configuration`
- `is_active`
- `created_at`
- `updated_at`

The migration removes `card_id` and all AI/extraction/source-tracking fields from `card_benefits`. Any display or recommendation query that needs a card association must join through `card_benefit_mapping`, not `card_benefits`.

## Historical benefit ID recovery

The historical restore snapshot contains the original `benefit_id` for every `card_benefits.id`. Before columns are removed, the migration restores each missing `benefit_id` by matching its stable `card_benefits.id` to that snapshot. It verifies that every restored ID exists in `benefits` and aborts if any row cannot be safely reconciled. No inferred category/name matching is permitted.

## Approval persistence

For each accepted candidate item:

1. Revalidate its evidence against the stored source evidence.
2. Find or create the canonical `benefits` row using the normalized category, title, description, and configuration.
3. Upsert `card_benefit_mapping(card_id, benefit_id)` for the selected catalog card.
4. Store card-specific calculation limits in the canonical benefit configuration only when they are part of the accepted benefit definition; do not create a card-linked `card_benefits` row.

For rejected candidate items, persist only the review decision in staging. Do not create a mapping or change active mappings.

## Safety and verification

Before applying the migration:

1. Verify every legacy `card_benefits` row has a recoverable historical `benefit_id`.
2. Verify all affected code paths use `card_benefit_mapping` for card associations.
3. Back up the pre-migration row counts and relationship counts.

After applying it:

1. Confirm the retained `card_benefits` columns match this specification exactly.
2. Confirm every retained `benefit_id` references an existing canonical benefit.
3. Confirm active card benefits resolve through `card_benefit_mapping`.
4. Exercise per-item accept, per-item reject, bulk acceptance, bulk rejection, and approval-time validation failure without rerunning AU Zenith.
5. Run focused Flutter tests and static analysis for changed code.
