# Benefit refresh review and mapping-only implementation plan

## Approved scope

- Keep the `benefits` catalog intact.
- Delete all rows in `card_benefit_mapping` and `card_benefits` only.
- Use `card_benefit_mapping` as the sole card-to-benefit relationship.
- Focus subsequent refresh/review work on AU Small Finance Bank — Zenith; do not rerun it during implementation.

## Delivery slices

1. Create the immutable candidate-decision model and tests.
2. Render the approved checkpoint diagram as the review status rail and provide individual/bulk candidate decisions.
3. Add a database migration which resets only the two approved tables, removes deprecated `card_benefits` columns, records staging decisions, and enforces canonical benefit deduplication with `benefits.dedupe_key`.
4. Convert all active card-benefit reads and writes to `card_benefit_mapping` plus canonical `benefits` configurations.
5. Before applying the destructive migration, verify it against a local Supabase database and retain a row-count backup. Do not use it against the remote project until that verification succeeds.

## Approval data path

| Moment | Data stored | Table |
| --- | --- | --- |
| Product page scraped | Transient page content | none |
| Identity/claim grounding succeeds or fails | Candidate snapshot, evidence, validation result | `card_benefits_staging` |
| Operator accepts/rejects candidates | Per-item decisions and reviewer/timestamp | `card_benefits_staging` |
| Accepted candidate has a known canonical key | Existing benefit reused | `benefits` |
| Accepted candidate is new | New canonical benefit, guarded by unique `dedupe_key` | `benefits` |
| Final approval | Selected card mapped to each accepted canonical benefit | `card_benefit_mapping` |
| All candidates rejected/discarded/revalidation fails | Audit status only; active mappings unchanged | `card_benefits_staging` |

`card_benefits` is not part of this new pipeline.
