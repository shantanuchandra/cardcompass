# Task 4 — Portfolio statement summaries and payment

## Delivered

- Added a pure `buildCardStatementSummaries` helper that selects the latest
  persisted statement by `statementDate` for every owned `userCardId`.
- Added `cardStatementSummariesProvider`, scoped to the signed-in user and
  backed by the existing `StatementRepository`.
- Added a portfolio panel below every card summary. It shows the real amount
  due and due date, a paid amount/date, or `No statement available` when no
  statement exists.
- Added a confirmation flow for `MARK PAID`. Confirmation calls the existing
  repository `markStatementPaid` API with the selected statement/card IDs and
  refreshes summaries. Failures keep the UI unchanged and show a SnackBar.

## Verification

- Targeted Task 4 tests: pass (8 tests).
- Full `flutter test`: pass (257 tests, 16 intentional Supabase-bound skips).
- `flutter analyze`: exits with 68 pre-existing warnings/info diagnostics in
  unrelated files; the newly changed Task 4 files add no diagnostics.

## TDD record

The three Task 4 test files were added and run before implementation. The
initial run failed because the summary model/helper, provider, and payment
panel did not yet exist. The implementation was then added and the targeted
suite passed.
