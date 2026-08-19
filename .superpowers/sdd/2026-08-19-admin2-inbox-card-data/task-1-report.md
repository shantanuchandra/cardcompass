# Task 1 report — atomic audited card-data mutation

## Outcome

Added `public.admin_card_data_action`, a service-only, fixed-search-path wrapper that locks authoritative queue rows, checks observed timestamps and eligible states, invokes the existing locked identity/benefit resolution functions, and writes the successful admin audit receipt in the same PostgreSQL transaction.

## Safety decisions

- Lane/operation pairs are explicitly allowlisted.
- Reject and quarantine require a bounded reason.
- `(actor_id, request_id)` is serialized before lookup; direct equality against the stored canonical request JSONB proves exact retries, while changed requests fail with `request_id_collision`.
- Identity actions require a pending review row.
- Benefit actions exclude the reserved `catalog-v1` lane, bind approvals to the job's exact pending staging row and card, and never quarantine a processing job.
- Browser roles have no execute grant; only `service_role` can invoke the wrapper.

## TDD evidence

- RED: the new three-test contract failed 3/3 with `ENOENT` before the migration existed.
- GREEN: `node --test test/supabase/admin_operator_foundation_migration_test.js test/supabase/admin_card_data_operations_migration_test.js test/supabase/automated_benefit_enrichment_migration_test.js` passed 13/13.
- REVIEW FIX GREEN: `RUN_ADMIN_CARD_DATA_PG_INTEGRATION=true node --test test/supabase/admin_card_data_operations_migration_test.js` passed 4/4 against an isolated disposable local PostgreSQL database. It compiled/applied the real migration and exercised exact replay, changed-request collision, stale timestamps, staging ownership, audit-failure rollback, and concurrent identical requests. Cleanup left no test databases or roles.
- REVIEW FIX FOLLOW-UP: the harness derives admin and disposable connections from one validated loopback URL, moves credentials and connection options into libpq environment variables, keeps passwords out of process arguments, redacts failures, and guards the generated cleanup target. Unit/static and opt-in PostgreSQL coverage passed 5/5; cleanup again left no database or role residue.

## Residual risk

The execution harness uses minimal faithful table and consumed-RPC fixtures rather than replaying the repository's full migration history. Full-schema compatibility remains covered by the static producer contracts and should also be exercised during the eventual local Supabase reset/smoke cycle.
