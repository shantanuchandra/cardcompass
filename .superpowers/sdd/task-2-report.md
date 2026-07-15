# Task 2 Report: Verified PDF Dates and Payment Credits

## Delivered

- Added `payments_received` to the Gemini statement-info prompt and the
  deterministic fallback parser.
- Added `StatementParsingResult.fromParsedInfo`, which uses a valid PDF
  statement date in preference to the email received date and records either
  `pdf` or `email_fallback` as its source.
- Carried the PDF-derived payment credit through `StatementParsingResult`.
- Preserved date source, payment credit, and the initial `unreconciled`
  reconciliation state in ingested statement metadata.
- Preserved the pre-existing Task 1 fuzzy-card-match changes in the shared
  debug service and its test file; they are intentionally not staged by this
  task.

## TDD Evidence

1. Added `test/gemini_statement_info_test.dart` before production changes.
2. Ran:

   ```sh
   flutter test test/gemini_statement_info_test.dart test/data_pipeline_debug_service_test.dart
   ```

   The new test file failed as expected because
   `StatementParsingResult.fromParsedInfo` and
   `GeminiTransactionParser.fallbackStatementParsingForTesting` did not yet
   exist.
3. Implemented the smallest production changes and reran the same command:
   all 9 tests passed.

## Verification

- `git diff --check` passed.

- Focused Flutter test suite passed: 9 tests.
- Focused analyzer run completed with two existing warnings in
  `data_pipeline_debug_service.dart`: an unused `app_config.dart` import and
  unused `_getUserCardId`. No errors were reported.

## Commit Scope

The commit contains only Task 2 production files and the new statement-info
test. The pre-existing Task 1 fuzzy-match modifications in
`data_pipeline_debug_service.dart` and
`test/data_pipeline_debug_service_test.dart` remain unstaged.

## Review Follow-up: Storage Metadata Coverage

- Added a focused storage-path test that derives a statement from PDF facts
  and asserts the created statement metadata contains
  `statement_date_source: pdf`, `payments_received: 1250.0`, and
  `payment_reconciliation_status: unreconciled`.
- The test was first run red. It failed to compile because
  `DataPipelineDebugService` did not expose a statement repository seam, so
  the persisted statement payload could not be observed.
- Added the minimal optional `StatementRepository` constructor dependency;
  production still defaults to `SupabaseStatementRepository`.
- Reran `flutter test test/gemini_statement_info_test.dart
  test/data_pipeline_debug_service_test.dart`: all 10 tests passed.
- `git diff --check` passed.

## Review Follow-up: Repository Metadata Persistence

- Added a repository-level regression test that injects the statement upsert
  operation, avoiding live Supabase initialization, and asserts the exact
  persistence row contains the PDF-ingestion metadata:
  `statement_date_source`, `payments_received`, and
  `payment_reconciliation_status`.
- The test was run red first and failed to compile because
  `SupabaseStatementRepository` did not expose an upsert seam.
- Added the minimal optional `StatementUpsert` constructor dependency and
  copied `statementData['metadata']` into the repository's upsert row.
- Ran `flutter test test/supabase_statement_repository_test.dart
  test/gemini_statement_info_test.dart
  test/data_pipeline_debug_service_test.dart`: all 13 tests passed.
- `git diff --check` passed.

## Review Follow-up: Metadata Schema Contract

- Added a migration contract test for `statements.metadata` and ran it red
  before changing the migration; it failed because the column was absent.
- Extended `20260716090000_statement_payment_tracking.sql` with idempotent
  `metadata JSONB NOT NULL DEFAULT '{}'::jsonb` provisioning. The migration
  reapplies the default, backfills existing nulls, then enforces `NOT NULL` so
  installations with a previously nullable metadata column are repaired.
- Ran the focused repository/schema/parser suite:

  ```sh
  flutter test test/statement_schema_fix_test.dart \
    test/supabase_statement_repository_test.dart \
    test/gemini_statement_info_test.dart \
    test/data_pipeline_debug_service_test.dart
  ```

  All 17 tests passed. `git diff --check` also passed.

## Review Follow-up: Deploy-Safe Metadata Migration

- Restored `20260716090000_statement_payment_tracking.sql` to its original
  Task 1 payment-tracking scope so it is not retroactively changed after
  deployment.
- Added the later, idempotent
  `20260716090100_statement_metadata_contract.sql` migration to add
  `statements.metadata` with a JSONB default, reapply that default, backfill
  existing nulls, and then enforce `NOT NULL`.
- Updated the schema contract test to require the later migration’s add-column,
  default, null-backfill, and `SET NOT NULL` statements.
- Ran `flutter test test/statement_schema_fix_test.dart` red first; it failed
  as expected because the new migration file did not yet exist.
- After adding the migration, reran that focused test successfully.
