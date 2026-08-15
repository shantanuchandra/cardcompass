# PDF Statement Parsing (Slice 2) Design

**Goal:** Extend Gmail sync so that, after email metadata is fetched (slice 1,
already working), each unprocessed statement email's PDF is downloaded,
unlocked, parsed into a statement + its transactions via Gemini, and stored in
Supabase — closing the loop from "found an email" to "real spend data on the
dashboard."

**Architecture:** A new `StatementProcessingService` orchestrates, per
unprocessed email: download PDF attachment (extends `GmailSyncService`) →
resolve a password via a ported `PdfPasswordResolver` chain (cached password →
DB date-of-birth → Google People API date-of-birth → DOB-entry dialog →
generated bank-pattern candidates → manual password dialog, in that order) →
extract text (`syncfusion_flutter_pdf`) → parse via a trimmed port of Gemini
statement/transaction parsing (calling the already-deployed `gemini-proxy`
Supabase Edge Function, so no Gemini API key touches this codebase) → persist
via a ported `SupabaseStatementRepository` → mark the source email
`processed=true` with `bank_detected`/`statement_id` populated.

**Tech Stack:** `syncfusion_flutter_pdf` (new dependency), existing
`googleapis`/`shared_preferences`/`http`/`supabase_flutter`, a `navigatorKey`
added to `MaterialApp.router` so dialogs can be triggered mid-async-flow.

---

## Why this scope, and what's ported vs. new

`main` (at `/Users/shantanuchandra/Downloads/Personal/cardcompass`, branch
`feature/ai-evals-dashboard`, main's history merged in) already has a working
version of every piece needed here. This slice ports the load-bearing logic
and drops what's genuinely unused for our case:

**Ported as-is (no behavior change):**
- `lib/core/services/parsing_logger.dart` — small, dependency-free logger.
- `lib/core/services/password_learning_service.dart` — SharedPreferences
  cache of successful bank→password mappings, keyed by bank+user email.
- `lib/core/services/pdf_password_detection_service.dart` — bank-specific
  password-pattern generation (name+DOB combinations) and the
  try-candidates-then-fall-back-to-manual orchestration logic.
- `lib/core/services/card_normalizer_service.dart` — bank/card name
  canonicalization, used when storing parsed statement metadata.
- `lib/core/repositories/{statement_repository,supabase_statement_repository}.dart`
  — statement + transaction persistence, already has DI seams for testing.

**Ported with a fix:**
- `lib/core/services/simple_birthday_input_service.dart` (DOB-entry dialog) —
  main's version silently no-ops because the caller never passes a real
  `BuildContext` (`enhanced_gmail_service.dart:984-985` has a commented-out
  `// context: context, // TODO: Pass context when available in UI`). This
  port fixes that by adding a `GlobalKey<NavigatorState> navigatorKey` to
  `MaterialApp.router` (in `app.dart`) and using
  `navigatorKey.currentContext` to actually show the dialog — following the
  exact pattern `main`'s (unused-in-practice) `global_password_service.dart`
  already demonstrates for the manual-password dialog. Confirmed by the user:
  replicate main's flow but fix this specific bug.
- `lib/core/services/password_input_service.dart` (manual password dialog) —
  ported with the same `navigatorKey`-based context resolution instead of
  requiring a `BuildContext` to be threaded through manually.

**New, trimmed port (not a straight copy):**
- A new `lib/core/services/gemini_statement_parser.dart` containing only
  `parseStatementInfo` and `parseTransactions` from main's 1164-line
  `gemini_transaction_parser.dart`, plus their direct dependencies:
  - `_pruneAndCleanText` (boilerplate trimming before sending PDF text to
    Gemini, to stay under token limits) — ported, but its call to
    `PruningAuditService().logPruning(...)` (an async audit-trail write) is
    dropped; pruning still happens, just without the audit log table write,
    since that table/service isn't part of this slice's scope.
  - `_extractJsonPayload` (strips markdown code fences Gemini sometimes wraps
    JSON in) — ported as-is.
  - A minimal `_callGemini` retry wrapper — ported *without* the Ollama/Groq
    branches in main's `_callGeminiWithFallback` (those providers are never
    configured or reachable in this project; dead branches would be pure
    YAGNI weight). Keeps: call `sendGeminiRequest` (below), detect 429 via a
    simple status-code check, wait and retry up to 3 attempts.
  - `card_normalizer_service.dart` (ported as-is, listed above).
- `lib/core/services/gemini_request_service.dart` (ported as-is) — the
  `sendGeminiRequest` wrapper that, on web, calls the already-deployed
  `gemini-proxy` Supabase Edge Function
  (`supabase/functions/gemini-proxy`, same Supabase project
  `prbcoxqobhjnnfnxevxf` this worktree already points at — confirmed via
  `dart_defines.json` in both repos). No new Edge Function deployment needed.
- A minimal `lib/core/config/ai_config.dart` — main's version handles
  Ollama/Groq provider switching and a multi-model fallback chain with
  persisted runtime settings; none of that applies here since this project
  only ever uses Gemini via the proxy. This port keeps just
  `AIConfig.geminiModel` (a constant model name string) since that's the only
  field `gemini_request_service.dart` and the trimmed parser actually read.

**Explicitly not ported:**
- `benefit_repair_service.dart` and the benefit-extraction/repair methods in
  main's `gemini_transaction_parser.dart` (`extractCardBenefits`,
  `repairBenefitClaims`, etc.) — unrelated to statement/transaction parsing,
  confirmed unused by `parseStatementInfo`/`parseTransactions` (the import is
  dead code in main's file).
- Ollama and Groq AI provider paths — not configured anywhere in this
  project; dropping them is a straightforward YAGNI cut, not a capability
  loss.
- `pruning_audit_service.dart`'s logging table write — kept only the
  leak-detection check (`detectPotentialLeaks`) that gates whether pruning is
  safe, dropped the audit-trail persistence.

## New OAuth scope

`https://www.googleapis.com/auth/user.birthday.read` is added to
`lib/features/auth/providers/auth_provider.dart`'s `signInWithOAuth` scopes
string, alongside the existing `email profile
https://www.googleapis.com/auth/gmail.readonly`. Confirmed via Google's
official People API docs: the `profile` scope alone does not grant access to
the `birthdays` field on `people.get` — a dedicated scope is required. Users
will see one additional consent line ("View your complete date of birth") on
their next Google sign-in.

## Components

### 1. `GmailSyncService` (extended)
Location: `lib/core/services/gmail_sync_service.dart` (existing file from
slice 1)

- Add `Future<Uint8List> downloadAttachment(String messageId, String
  attachmentId)` — ported from `enhanced_gmail_service.dart:1398-1412`
  (`users.messages.attachments.get` + base64url decode). Slice 1's
  `GmailSearchResult` already carries `messageId`; this slice adds
  `attachmentId` and `attachmentFilename` (needed for filename-based password
  hints) to that model, populated from the same `payload.parts` walk that
  currently only checks for a `.pdf` filename to set `hasAttachment`.

### 2. `UserProfileService` (new, trimmed)
Location: `lib/core/services/user_profile_service.dart`

- `Future<DateTime?> getDateOfBirth(String userId)` — reads
  `users.date_of_birth` from Supabase (ported from
  `user_profile_database_service.dart:9-24`).
- `Future<void> storeDateOfBirth(String userId, DateTime dob)` — writes it
  back (ported from lines 29-43).
- `Future<DateTime?> getGoogleBirthday(String accessToken)` — calls
  `https://people.googleapis.com/v1/people/me?personFields=birthdays` with
  the bearer token (ported logic from `enhanced_gmail_service.dart:1414-1460`
  region), parses the first birthday entry's `date` object into a `DateTime`.
  Returns `null` on any failure (missing scope, no birthday set on the Google
  account, network error) — never throws, since this is one step in a
  fallback chain.

### 3. `PdfPasswordResolver` (new orchestrator, wraps ported pieces)
Location: `lib/core/services/pdf_password_resolver.dart`

- `Future<String?> extractText({required Uint8List pdfBytes, required String
  bankName, required String userId, required String userEmail, required
  String userName, String? fileName, String? emailSubject, String?
  emailBody})`.
- Sequence (ported from `pdf_password_detection_service.dart`'s
  `findPasswordAndExtractText`, extended with the DOB chain):
  1. Try opening the PDF with no password (some statements aren't encrypted).
  2. Extract password hints from the email subject/body (ported
     `extractPasswordHints`).
  3. Get learned/cached passwords for this bank+user
     (`PasswordLearningService.getLearnedPasswordCandidates`).
  4. Resolve a DOB: `UserProfileService.getDateOfBirth` (DB) → if null,
     `UserProfileService.getGoogleBirthday` (People API, stores to DB on
     success) → if still null, show the DOB-entry dialog via `navigatorKey`
     (ported + fixed `SimpleBirthdayInputService`); if the user provides one,
     store it via `storeDateOfBirth`.
  5. Generate bank-pattern password candidates using whatever DOB was
     resolved (ported `generatePasswordCandidates` — degrades gracefully to
     name-only candidates if DOB is still unavailable, e.g. user dismissed
     the dialog).
  6. Try all candidates (learned + generated) against the PDF
     (`tryOpenPdfWithPasswords`); on success, cache the winning password via
     `PasswordLearningService.storeSuccessfulPassword` and return the
     extracted text.
  7. If all candidates fail, show the manual password dialog (ported +
     `navigatorKey`-fixed `PasswordInputService`), up to 2 attempts, testing
     each against the PDF and caching on success.
  8. Return `null` if every step above fails (caller marks this email as
     needing attention rather than crashing the whole sync run).

### 4. `GeminiStatementParser` (new, trimmed)
Location: `lib/core/services/gemini_statement_parser.dart`

- `Future<Map<String, dynamic>> parseStatementInfo({required String pdfText,
  required String bankName})` — ported prompt + JSON-parsing logic from
  `gemini_transaction_parser.dart:20-135`, calling the trimmed
  `_callGemini`/`sendGeminiRequest` path instead of the full
  Gemini/Ollama/Groq fallback chain. Falls back to the existing regex-based
  `_fallbackStatementParsing` (ported as-is) if the Gemini call fails
  entirely.
- `Future<List<Map<String, dynamic>>> parseTransactions({required String
  pdfText, required String bankName})` — ported from lines 217-315, same
  trimmed call path. Returns `[]` (not a throw) if parsing fails, matching
  main's behavior — an email that fails to parse still gets marked
  `processed=true` with `bank_detected` set and an empty transaction set,
  rather than blocking the rest of the sync run.

### 5. `SupabaseStatementRepository` + `StatementRepository` interface (ported as-is)
Location: `lib/core/repositories/{statement_repository,supabase_statement_repository}.dart`

Copied verbatim — already handles resolving `user_cards.id` → `catalog_card_id`,
upserting the `statements` row (with `on_conflict` semantics for re-processing
the same statement), and inserting linked `transactions` rows.

### 6. `StatementProcessingService` (new orchestrator)
Location: `lib/core/services/statement_processing_service.dart`

- `Future<StatementProcessingResult> processUnprocessedEmails(String userId,
  String accessToken)`:
  1. Query `emails` where `user_id = userId AND processed = false AND
     has_attachments = true` (new method on `EmailRepository`,
     `getUnprocessedEmails`, ported from main's version already in
     `email_repository.dart` on main but dropped from slice 1's trimmed
     port — added back now since this slice needs it).
  2. For each: detect bank from sender/subject (simple substring match
     against known bank names — reuses the same bank-name list already
     implicit in `pdf_password_detection_service.dart`'s
     `bankPasswordPatterns` keys), download the PDF attachment, resolve
     password + extract text via `PdfPasswordResolver`, parse via
     `GeminiStatementParser`, persist via `SupabaseStatementRepository`,
     then update the source `emails` row (`processed=true`,
     `bank_detected`, `statement_id`) via
     `EmailRepository.updateEmailStatus`.
  3. Continues past per-email failures (a PDF that can't be unlocked, or a
     Gemini call that fails entirely) — collects a per-email outcome
     (`succeeded` / `needsPassword` / `failed`) rather than aborting the
     whole run.
  4. Returns a summary: `{totalAttempted, succeeded, needsPassword, failed}`.

### 7. Dashboard wiring
Location: `lib/features/dashboard/providers/gmail_sync_provider.dart`
(extended) and `lib/features/dashboard/screens/dashboard_screen.dart`

- After slice 1's email-fetch step completes successfully, `syncGmail()` goes
  on to call `StatementProcessingService.processUnprocessedEmails`, and the
  snackbar summary is extended to report both stages, e.g.: *"Found 50
  statement emails, 43 new. Processed 43: 38 succeeded, 3 need a password, 2
  failed."*
- The dashboard's `dashboardProvider` is invalidated
  (`ref.invalidate(dashboardProvider)`) after a successful processing run so
  newly-stored transactions/statements appear without a manual pull-to-refresh.

### 8. `navigatorKey` wiring
Location: `lib/app.dart`

- Add `final navigatorKey = GlobalKey<NavigatorState>();` at file scope (or a
  small dedicated file, matching main's `import 'package:cardcompass/app.dart';
  // Import for navigatorKey` pattern) and pass `navigatorKey:
  navigatorKey` to `MaterialApp.router`. This is the single addition that
  makes the DOB-entry and manual-password dialogs actually work mid-sync,
  fixing the bug this design intentionally does not replicate.

## Data flow

```
[Dashboard: tap "Sync Gmail"]
        |
        v
gmailSyncProvider.syncGmail()
        |
        +-- (slice 1, unchanged) fetch + store email metadata --+
        |                                                        |
        v                                                        |
StatementProcessingService.processUnprocessedEmails() <----------+
        |
        v
for each unprocessed email with an attachment:
    downloadAttachment(messageId, attachmentId)
        |
        v
    PdfPasswordResolver.extractText(...)
        no password needed -> text
        cached password works -> text (fast path)
        DB DOB -> candidates work -> text
        People API DOB -> candidates work -> text (stores DOB to DB)
        DOB dialog -> candidates work -> text (stores DOB to DB)
        candidates all fail -> manual password dialog (2 attempts) -> text
        everything fails -> null (mark email as "needs password", continue)
        |
        v (if text extracted)
    GeminiStatementParser.parseStatementInfo(text, bank)
    GeminiStatementParser.parseTransactions(text, bank)
        |
        v
    SupabaseStatementRepository: upsert statement, insert transactions
        |
        v
    EmailRepository.updateEmailStatus(processed=true, bank_detected, statement_id)
        |
        v
return {totalAttempted, succeeded, needsPassword, failed}
        |
        v
Dashboard snackbar shows combined summary; dashboardProvider invalidated
```

## Error handling

- **PDF download failure** (Gmail API error, missing attachment): caught
  per-email, counted as `failed`, sync continues to the next email.
- **Password resolution failure** (all steps in `PdfPasswordResolver`
  exhausted, including a cancelled manual dialog): counted as
  `needsPassword`, not `failed` — a distinct, actionable state ("we found
  this statement but couldn't open it") the user can address later (a
  future slice could add a "retry with password" UI entry point; out of
  scope here, matching the "process all, report clearly" approach already
  chosen for slice 1).
- **Gemini parsing failure** (both the API call and the regex fallback
  produce nothing usable): the email is still marked `processed=true` with
  `bank_detected` set, but zero transactions are stored — matches main's
  behavior of never blocking on a single bad parse.
- **Supabase write failure** (statement upsert or transaction insert
  throws): caught per-email, counted as `failed`; does not mark
  `processed=true` so a future sync run will retry it.

## Known gaps (explicitly out of scope for this slice)

- **No "retry with password" UI** for emails stuck in `needsPassword` state
  — the user must wait for the next full sync run, which will re-prompt.
- **No progress indicator during processing** — with "process all"
  potentially meaning dozens of PDFs and several blocking password dialogs
  in a row, the sync button's spinner is the only feedback until the final
  summary. Flagged as a real UX risk (already raised during brainstorming);
  not solved in this slice per the user's explicit choice to process
  everything now and iterate later.
- **No `PruningAuditService` audit trail** — pruning still happens
  (correctness preserved), just without the logging table write.
- **Provider token expiry mid-run** — if `session.providerToken` expires
  partway through processing many PDFs (each Gmail attachment download uses
  the same token from slice 1), the run will start failing with 401s;
  slice 1's known gap about no token refresh applies here too, unchanged.

## Testing

- Manual verification in Comet: sign in fresh (to pick up the new
  `user.birthday.read` scope), tap "Sync Gmail," observe the DOB dialog (if
  no DOB is stored yet) or the manual password dialog (if bank-pattern
  guessing fails), confirm real transactions and a statement row appear in
  Supabase and on the dashboard afterward.
- No automated test suite is being added, consistent with slice 1 and the
  project's current lack of a Flutter test suite in this worktree (note:
  `main` does have tests for the ported services, e.g.
  `test/test_password_generation.dart` — those aren't ported since this
  worktree has no test runner set up yet; a future slice could address that
  separately).
