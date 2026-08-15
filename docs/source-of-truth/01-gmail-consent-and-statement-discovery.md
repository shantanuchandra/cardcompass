# Gmail Consent and Statement Discovery

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

Find likely credit-card statement emails through the existing Google/Supabase
sign-in flow, persist enough metadata to process them reliably, and make sync
repeatable without duplicate email records.

## Authentication and consent

- Use Supabase Google OAuth and its provider token; do not start a second Google
  Sign-In flow.
- Keep the existing `email`, `profile`, Gmail read-only, and birthday-read
  scopes used by the working v2 flow.
- If the provider token is missing or expired, tell the user to authenticate
  again. Do not report a successful empty sync.
- Gmail access is read-only.

## Statement email discovery

The initial query targets likely credit-card statement messages with PDF
attachments. The current subject terms and PDF filename/MIME checks remain the
baseline. A search-filter match is only a candidate: inspect each message to
confirm that a PDF attachment exists.

For each result, capture:

- Gmail message ID;
- subject;
- sender;
- received date;
- attachment presence;
- attachment ID and filename in metadata; and
- processing state and detected bank when known.

The same `(user_id, Gmail message ID)` must not be inserted twice. A repeated
sync reports found, new, skipped, and failed counts.

## Incremental sync

- Use the current last-sync/date filtering behavior where available.
- Treat the existing result limit as a batch limit, not a declaration that
  older messages do not exist.
- A later implementation may add pagination or durable cursors without changing
  the downstream processing contract.
- Instant transaction-alert emails are a separate ingestion subtype. They may
  be used for fresher provisional transactions and later reconciled with the
  official statement.

## Bank and card identification

Sender, subject, known bank aliases, filename, and parsed statement content may
identify the issuer. Card assignment follows this order:

1. Match the parsed last four digits to an active owned card.
2. If exactly one same-bank card has no verified last four, assign it and
   backfill the parsed last four.
3. Reuse a previous user-confirmed bank-to-card assignment when unambiguous.
4. Otherwise mark the email as needing card assignment and ask the user.

Never guess between multiple same-bank cards.

## Processing states

The product-level lifecycle is:

- `discovered`
- `processing`
- `needs_password`
- `needs_card_assignment`
- `processed`
- `failed`

The implementation may continue using its current columns and metadata flags;
these names define user-visible meaning, not a required schema migration.

Useful failure reasons include:

- unsupported or unknown issuer;
- missing PDF attachment;
- attachment download failure;
- password unresolved;
- card assignment unresolved;
- parse failure; and
- persistence failure.

One email failure does not abort the remaining batch.

## Persistence contract

The existing email record remains the source of processing state and contains
the link to the created statement when processing succeeds. Updating processing
status preserves attachment metadata needed for retries.

An email becomes `processed` only after its statement and valid transactions
have been persisted. A parser response containing zero valid transaction rows
is not silently treated as a complete success.

## User experience

The sync surface reports:

- statement emails found;
- new emails stored;
- statements processed;
- statements needing passwords;
- statements needing card assignment; and
- failures.

Items needing user action remain visible and retryable.

## Acceptance criteria

- Re-running sync does not duplicate Gmail email rows.
- A missing/expired provider token produces an actionable error.
- A non-PDF message cannot enter PDF processing solely because it matched the
  search query.
- Multiple same-bank cards are never assigned by guesswork.
- One failed email does not stop other statement emails from processing.
- Every processed email links to the resulting statement.

## Supporting references

- `docs/superpowers/specs/2026-08-02-gmail-sync-fetch-list-design.md`
- `docs/superpowers/plans/2026-08-02-gmail-sync-fetch-list.md`
- Main repo: `SYNC_FLOW_DEBUG_GUIDE.md`
