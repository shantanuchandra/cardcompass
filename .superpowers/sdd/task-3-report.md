# Task 3 — Statement payment reconciliation

## Delivered

- Added `StatementPaymentReconciliationService`, which allocates an imported
  payment credit oldest due date first and keeps allocations within one user
  and owned card.
- Added repository APIs for open-statement lookup, imported-payment
  reconciliation, manual payment application, and marking exactly the
  remaining balance as paid.
- Added a transactional Supabase RPC migration. It locks and validates the
  source statement, derives the credit from source metadata, records the
  idempotency state before target allocations, locks eligible same-card
  statements, and records any unmatched remainder.
- Wired reconciliation immediately after a statement is persisted during
  ingestion. Existing fuzzy-card-match work remains unstaged and untouched.

## Tests

`flutter test test/core/services/statement_payment_reconciliation_service_test.dart test/supabase_statement_repository_test.dart test/data_pipeline_debug_service_test.dart`

Result: 16 tests passed.

## Note

`flutter analyze` reported two pre-existing warnings in
`data_pipeline_debug_service.dart` (an unused `app_config` import and unused
`_getUserCardId` helper). No reconciliation-specific analyzer errors occurred.
