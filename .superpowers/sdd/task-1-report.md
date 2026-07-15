# Task 1 Report: Statement payment audit fields

## Status

Completed.

## Test-first evidence

1. Added `test/statement_payment_model_test.dart` and a migration-content test to `test/statement_schema_fix_test.dart`.
2. Ran `flutter test test/statement_payment_model_test.dart test/statement_schema_fix_test.dart` before implementation. It failed because `Statement.remainingAmount`, `Statement.paidAt`, and the migration file did not exist.
3. Implemented the requested payment fields, serialisation, copy support, remaining-balance getter, migration constraint, and index.
4. Re-ran the same command successfully: 4 tests passed.

## Files committed

- `supabase/migrations/20260716090000_statement_payment_tracking.sql`
- `lib/shared/models/statement.dart`
- `test/statement_payment_model_test.dart`
- `test/statement_schema_fix_test.dart`

## Scope and review

- Preserved unrelated existing modifications in `lib/core/services/data_pipeline_debug_service.dart` and `test/data_pipeline_debug_service_test.dart`.
- `git diff --check` completed without whitespace errors.

## Review follow-up: payment bounds and idempotent migration

### Test-first evidence

1. Added regression coverage for a missing `paid_amount` (defaults to zero),
   negative amounts through the constructor, `fromJson`, and `copyWith`,
   amounts above the total, and `NaN`/infinite values.
2. Extended the migration-content test to require a `total_amount` null backfill,
   `NOT NULL` enforcement, and a catalog-guarded named constraint.
3. Before the fix, ran `flutter test test/statement_payment_model_test.dart test/statement_schema_fix_test.dart`.
   The negative, over-total, and non-finite model tests failed because invalid
   values were accepted; the schema test failed because the migration lacked
   null protection and an idempotency guard.
4. Re-ran `flutter test test/statement_payment_model_test.dart test/statement_schema_fix_test.dart` after the fix: **8 tests passed**.
   `git diff --check` also passed.

### Implementation

- `Statement` now rejects non-finite/negative totals and non-finite,
  negative, or over-total payments in its constructor, covering `fromJson` and
  `copyWith` centrally; omitted JSON `paid_amount` still defaults to zero.
- The migration backfills null totals to zero, makes `total_amount` non-null,
  and uses a `pg_constraint` catalog check inside `DO $$` before adding the
  named bounds constraint.
