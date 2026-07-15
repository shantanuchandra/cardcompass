# Statement Ingestion and Payment Tracking Design

## Goal

Make statement dates trustworthy for card-cycle calculations, show the current
bill for every owned card, and retain an auditable record when a statement is
paid in full or in part.

## Data model

Extend the existing `public.statements` table. Do not create a parallel payment
table for the initial full/partial payment workflow.

- `paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0`: total amount applied to this
  statement.
- `paid_at TIMESTAMPTZ NULL`: timestamp of the most recent applied payment.
- Existing `payment_status` remains the lifecycle field: `pending`, `partial`,
  `paid`, or `overdue`.

The migration will add a check constraint that prevents negative paid amounts
and prevents a paid amount greater than `total_amount`. It will add an index
for locating a card's latest statement and its oldest unpaid statement.

## Ingestion and cycle dates

`GeminiTransactionParser.parseStatementInfo` already extracts `statement_date`
and `due_date` from PDF text. The Gmail ingestion result will use the parsed
statement date when it is a valid date. It will retain the email received date
only as a fallback if PDF extraction cannot provide a date.

Statement metadata will record `statement_date_source` as either `pdf` or
`email_fallback`, so benefit-cycle logic can distinguish verified dates from a
fallback. The parsed due date remains preferred; the existing default due-date
fallback remains only when the document omits it.

The actual benefit cycle is determined from consecutive statement dates for the
same `user_card_id`. It is not inferred from a fixed 30-day period when a prior
statement exists.

## Payment reconciliation

The parser will extract a statement-level `payments_received` total when the
PDF provides one. During ingestion, that amount is applied to prior open
statements for the same `user_card_id`, oldest due first.

- A payment less than the outstanding amount updates `paid_amount`, `paid_at`,
  and sets the statement to `partial`.
- A payment that clears the outstanding amount sets `payment_status` to `paid`.
- If one payment clears more than one prior statement, the remainder is applied
  to the next oldest open statement.
- Any remaining unmatched credit is retained in the current statement metadata
  as `unmatched_payment_credit`; it does not silently mark a statement paid.
- Re-ingesting the same statement must not apply its payment credit twice.

The user-facing “Mark paid” action applies the remaining outstanding amount to
that exact latest unpaid statement, sets `paid_at` to the action time, and
never alters a different card’s statement.

## Portfolio UI

The Show All Credit Cards page will load each card's latest statement by
`user_card_id` and render a compact bill panel below the existing card summary:

- total amount due;
- due date;
- payment status;
- a `Mark paid` action only when an amount remains outstanding.

The action requires confirmation and refreshes only after the database update
succeeds. Paid statements show their paid amount and timestamp instead of an
action. Cards with no statement show an explicit empty state, not invented
amounts or dates.

## Error handling

- Invalid or absent PDF dates never overwrite a valid stored statement date.
- A failed payment update leaves the UI unchanged and displays an error.
- The reconciliation is idempotent per source statement, protecting resyncs.
- RLS and ownership checks ensure statements can only be read or updated by
  their owner.

## Tests

Tests will be added before implementation and will cover:

1. parsed PDF statement date takes precedence over email date;
2. email date is explicitly marked as fallback only when PDF date is absent;
3. payment credits fully and partially reconcile prior statements, in oldest
   first order, without cross-card effects or duplicate application;
4. manual mark-paid records the exact remaining amount and timestamp;
5. latest-statement card summaries expose due date, total due, status, and
   empty-state behavior;
6. existing statement, sync, and movie-rule test suites continue to pass.
