# Gmail Sync — Fetch & List (First Slice) Design

**Goal:** Add a manual "Sync Gmail" action that finds likely credit-card-statement
emails in the user's inbox and records their metadata in the existing `emails`
table. No PDF download, unlock, or transaction parsing in this slice — those are
explicitly deferred to a later spec.

**Architecture:** A slim `GmailSyncService` calls the Gmail API using the Google
access token already captured by Supabase during login (`session.providerToken`),
runs a search query ported from the working implementation on `main`, and hands
results to a ported `EmailRepository` that writes rows into Supabase's `emails`
table. A Riverpod provider orchestrates the two, and a button on the Dashboard
triggers it manually.

**Tech Stack:** Flutter web, `googleapis` (gmail/v1), `supabase_flutter`,
`flutter_riverpod`.

---

## Why this scope

`main` (checked out at `/Users/shantanuchandra/Downloads/Personal/cardcompass`)
already has a full, working Gmail → PDF → parse → DB pipeline
(`lib/core/services/enhanced_gmail_service.dart`, `email_repository.dart`, and
supporting statement/parsing services). Rather than design from scratch, this
slice ports the two pieces needed for "fetch and list" — the search query and
the email-repository write path — and stops there. PDF download/unlock/parsing
reuse is a separate future slice once this foundation is verified working.

## Key difference from `main`'s implementation

`main`'s `enhanced_gmail_service.dart` obtains the Gmail access token via
`GoogleSignIn.instance.authenticate()` (the direct `google_sign_in` package).
Earlier this session, that package's web popup flow was found to unreliably
return tokens on Flutter web (`google_sign_in_web` 0.12.x doesn't reliably
surface a token after the GIS migration), which is why
`cardcompass-landing-v2`'s login already switched to Supabase's
`signInWithOAuth`. This slice reads the Google access token from Supabase's
`Session.providerToken` instead of calling `GoogleSignIn` again, avoiding a
second, redundant, and less reliable OAuth handshake.

## Components

### 1. `GmailSyncService` (new)
Location: `lib/core/services/gmail_sync_service.dart`

- Takes a Google OAuth access token (string) as input — does not manage auth
  itself.
- Builds an authenticated `gmail.GmailApi` client (same `_AuthenticatedClient`
  pattern as `main`'s service: a bearer-token HTTP client wrapper).
- `Future<List<GmailSearchResult>> searchStatementEmails({DateTime? after})`:
  runs the query `has:attachment filename:pdf (subject:"credit card statement"
  OR subject:"card statement" OR subject:"credit card")`, optionally scoped by
  an `after:` date filter, `maxResults: 50` — ported directly from
  `enhanced_gmail_service.dart:218-246`.
- For each matching message, calls `users.messages.get` and extracts: Gmail
  message id, subject, sender (`From` header), received date (`Date` header
  or internal timestamp), and whether it has a PDF attachment (checked from
  `payload.parts` mime types, not by trusting the search filter alone).
- Returns a lightweight `GmailSearchResult` (id, subject, from, date,
  hasAttachment) — no attachment bytes are downloaded in this slice.

### 2. `EmailRepository` (ported, unchanged)
Location: `lib/core/repositories/email_repository.dart`

Copied as-is from `main` — it already writes exactly the fields this slice
needs (`user_id`, `email_id`, `subject`, `sender`, `received_date`,
`has_attachments`, `processed: false`, `bank_detected: null`, `metadata: {}`).

Addition needed: a `storeEmail` call must not fail/duplicate on re-sync of the
same message. `main`'s version does a plain `insert`, which would throw on a
unique-constraint violation if `email_id` is already stored for that user. This
slice adds an existence check (`select` by `user_id` + `email_id` before
insert) so re-running sync is idempotent and simply skips emails already
recorded, rather than erroring.

### 3. `gmailSyncProvider` (new, Riverpod)
Location: `lib/features/dashboard/providers/gmail_sync_provider.dart`

- `Future<GmailSyncResult> syncGmail()`:
  1. Reads `Supabase.instance.client.auth.currentSession?.providerToken`.
  2. If null → return a result indicating "no Google session token — please
     sign in again" (this happens if the token wasn't captured at login, or
     the session was restored from a cached session that predates the token).
  3. Calls `GmailSyncService.searchStatementEmails()`.
  4. For each result not already in the `emails` table for this user, calls
     `EmailRepository.storeEmail(...)`.
  5. Returns a summary: `{foundCount, newlyStoredCount, skippedCount}`.
- Exposed as an `AsyncNotifier` so the Dashboard button can show
  loading/success/error state via `ref.watch`.

### 4. Dashboard UI (new button)
Location: `lib/features/dashboard/screens/dashboard_screen.dart`

- A "Sync Gmail" button/icon near the existing KPI row or app bar.
- Tap → calls `gmailSyncProvider`'s sync method.
- States: idle → loading (spinner in button) → success (brief snackbar:
  "Found N statement emails, M new") → error (snackbar with the error message,
  e.g. token-expired case).
- No automatic re-fetch of dashboard data is triggered by this slice — syncing
  emails does not yet produce transactions, so there's nothing new to show on
  the dashboard itself yet beyond the sync confirmation.

## Data flow

```
[Dashboard: tap "Sync Gmail"]
        |
        v
gmailSyncProvider.syncGmail()
        |
        v
read session.providerToken  --(null)--> return "sign in again" error
        |
        v
GmailSyncService.searchStatementEmails()
        |
        v
Gmail API: users.messages.list (query) -> users.messages.get (each)
        |
        v
for each result:
  EmailRepository: check if (user_id, email_id) already stored
    exists -> skip
    new    -> insert into `emails` table
        |
        v
return {foundCount, newlyStoredCount, skippedCount} to UI
```

## Error handling

- **No provider token** (null/missing): user-facing message telling them to
  sign out and sign back in. This is a known Supabase limitation — provider
  tokens aren't refreshed automatically, and this slice does not implement
  token refresh (out of scope; flagged as a known gap below).
- **Gmail API error** (401/403 — expired or insufficient-scope token): caught
  and surfaced as "Gmail access expired or was denied — please sign in again."
  Distinguished from a generic network error where possible via the HTTP
  status code.
- **Supabase insert error**: caught per-email (one failing insert should not
  abort the whole sync); failures are counted and surfaced in the summary
  (e.g. "3 found, 2 stored, 1 failed").

## Known gaps (explicitly out of scope for this slice)

- **No token refresh.** `providerToken` expires in ~1 hour and Supabase does
  not refresh it on session refresh. If sync is attempted after expiry, the
  user must sign out and back in. A future slice should persist
  `providerRefreshToken` and implement a manual refresh against Google's OAuth
  token endpoint, as documented in this session's earlier research.
- **No PDF download or unlock.** `has_attachments` is recorded, but the PDF
  itself is never fetched in this slice.
- **No bank detection.** `bank_detected` is always written as `null` — that
  requires either parsing the sender/subject against `card_catalog` bank names
  or inspecting the PDF, both deferred.
- **No pagination.** `maxResults: 50` per sync; a user with more than 50
  matching emails in history will need multiple syncs (each using `after:` to
  narrow the date range) — acceptable for a manual "sync at will" trigger in
  this slice.

## Testing

- Manual verification in Comet: sign in, tap "Sync Gmail", confirm the
  `emails` table in Supabase gets new rows matching real inbox statement
  emails, confirm re-tapping sync does not duplicate rows for the same
  messages.
- No automated test suite is being added in this slice (consistent with the
  project's current lack of Flutter widget/unit tests in this worktree).
