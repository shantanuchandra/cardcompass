# PDF Password Resolution and Parsing

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

Download a discovered statement PDF, unlock it with the existing bounded
password-resolution flow, extract statement facts and ledger transactions, and
persist normalized records without blocking the rest of the sync batch.

## Inputs

- Gmail message and attachment IDs
- PDF filename, subject, and available email hints
- detected bank
- authenticated user ID, name, and email
- active owned cards
- current Google provider token

## Password resolution order

Preserve the working v2 sequence:

1. Try opening the PDF without a password.
2. Extract password hints from available email content and filename context.
3. Load learned/cached candidates for this bank and user.
4. Resolve date of birth from the stored profile.
5. If absent, try the Google People API and store a successful result.
6. If still absent, ask the user for date of birth.
7. Generate bounded bank-specific candidates from name, date of birth,
   filename, and masked card information available to the existing service.
8. Try the deduplicated candidates.
9. If they fail, allow up to two manual password attempts.
10. Return an unresolved result and mark the email `needs_password`.

This is user-authorized password recovery for the user's own statement. It is
not an unrestricted brute-force facility.

Successful passwords continue to use the working local learning/cache behavior.
Changing that storage mechanism is outside this MVP revamp.

## Text extraction and pruning

After unlocking, extract text from the PDF and prune content before AI parsing.
Retain:

- statement and due dates;
- balances, limits, minimum due, payments, rewards, interest, and fees;
- masked card identity;
- transaction dates, descriptions, amounts, currencies, and debit/credit cues;
- transaction table headings needed to interpret rows.

Remove or ignore:

- repeated headers and footers;
- page numbers;
- postal addresses and generic profile content;
- marketing and unrelated product copy;
- customer-service instructions;
- generic reward advertisements; and
- totals that are not ledger transactions.

The pruning step must not remove context required to interpret continuation
lines, foreign-currency rows, or debit/credit markers.

## Statement facts

The parser produces, when present:

- statement date;
- payment due date;
- total amount due;
- minimum payment;
- closing and available balances;
- credit limit;
- rewards earned;
- interest and fees;
- payments received; and
- last four card digits.

Date precedence is:

1. valid PDF statement date;
2. direct deterministic extraction from PDF text;
3. email received date.

Due-date precedence is parsed PDF date followed by the existing fallback. A
fallback date must not overwrite a valid stored PDF-derived date.

## Transaction rows

The parser returns only genuine ledger entries. Each row should include:

- transaction date and posting date when both exist;
- issuer description;
- amount;
- explicit or resolved currency;
- transaction type;
- merchant candidate;
- category candidate; and
- stated reward amount when available.

Payments, refunds, fees, interest, rewards, and withdrawals remain ledger rows
with distinct transaction types. They are not eligible retail spend merely
because they appear as debits.

## Persistence

- Resolve through `user_cards`; do not attach a statement directly to a catalog
  card without an owned-card record.
- Upsert statements by `(user_card_id, statement_date)`.
- Link every statement transaction through `statement_id` and `user_card_id`.
- Backfill masked last four and credit limit only when the owned-card values are
  currently unverified; do not overwrite user-entered facts silently.
- Preserve idempotency when the same statement is processed again.

PDF bytes and extracted text continue to follow the existing process-local
behavior. This document does not introduce a new document-storage system.

## Payment reconciliation

When a statement provides `payments_received`, apply it to prior open statements
for the same owned card, oldest due first:

- partial payment -> update paid amount and `partial` status;
- full settlement -> `paid` status;
- excess after clearing known statements -> retain as unmatched credit;
- reprocessing -> never apply the same payment twice.

Manual “Mark paid” affects only the selected statement and its outstanding
amount.

## Failure handling

- Download error -> retain retryable download failure.
- Password unresolved -> `needs_password`.
- Text extraction failure -> parse failure.
- No valid transaction rows -> parse failure requiring attention.
- Persistence error -> keep the source email unprocessed.
- Any per-email failure -> continue with the next email.

## Acceptance criteria

- Standard bank password patterns and manual fallback work in the active UI.
- Statement dates prefer verified PDF values.
- Reprocessing is idempotent.
- Every transaction points to its owned card and source statement.
- A zero-row parse is visible, not silently successful.
- One locked or malformed PDF does not abort the batch.

## Supporting references

- `docs/superpowers/specs/2026-08-02-pdf-statement-parsing-design.md`
- `docs/superpowers/plans/2026-08-02-pdf-statement-parsing.md`
- Main repo: `docs/superpowers/2026-07-16-statement-ingestion-and-payment-tracking.md`
- Main repo: `docs/superpowers/2026-07-14-user-card-data-integrity.md`
