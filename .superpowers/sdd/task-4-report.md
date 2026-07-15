# Task 4 — Portfolio statement summaries and payment

## Delivered

- Added `CardStatementSummary` plus `buildCardStatementSummaries`, which keeps
  the latest persisted statement for each owned card.
- Added `cardStatementSummariesProvider`, scoped to the signed-in user.
- Added the portfolio bill panel: due amount/date, paid amount/date, or `No
  statement available`.
- Added a confirmed `MARK PAID` flow that calls `markStatementPaid` for the
  selected statement and invalidates the summary provider to refresh the UI.
- Amounts in the bill panel, confirmation dialog, and paid label retain paise
  (for example, `₹900.50`, never rounded to `₹901`).

## Tests

- `card_statement_summary_test.dart` covers latest-statement selection and
  paid-state fields.
- `cards_list_payment_action_test.dart` covers confirmation/cancel/error
  behavior, no-statement behavior, and paise-preserving due/confirmation/paid
  rendering.
- `cards_provider_test.dart` uses an authenticated provider container and a
  fake repository to verify data loading and invalidation-driven refresh.

## TDD record

The paise regression test was run before the formatter change and failed
because the amount-due label rounded `₹900.50` to a whole rupee. Formatting
was updated to two decimal places in every payment-facing string, then the
focused Task 4 suite was rerun.
