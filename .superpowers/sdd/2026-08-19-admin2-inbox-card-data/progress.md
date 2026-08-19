# Admin2 Inbox & Card Data — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-inbox-card-data.md`
- Base: `ab3f5937a53e7a552159fe7eff90ffaf8ec9a367`
- Status: active

## Preflight

- Foundation dependency is complete and independently reviewed.
- Existing `/app/admin/catalog-review` and `admin-catalog-entry` behavior must remain unchanged.
- Each task receives a fresh implementer and independent review; the final branch delta receives a whole-plan review.

Ruling: Treat the plan's SQL and handler snippets as behavioral scaffolding, not permission to weaken existing database constraints or duplicate locked catalog-resolution behavior. Cost if wrong: implementation may need a narrow adapter revision while preserving public behavior.

Ruling: Include the foundation's final adjudication ledger update in Task 1's code-bearing commit, honoring the operator's instruction not to commit documentation alone. Cost if wrong: Task 1's commit includes one prior-plan bookkeeping line with no runtime effect.

## Tasks

- Task 1: implementation complete, pending review — atomic audited card-data mutation RPC
- Task 2: pending — sanitized Card Data gateway actions
- Task 3: pending — derived ranked Action Inbox
- Task 4: pending — typed Flutter repositories
- Task 5: pending — Card Data review workspace
- Task 6: pending — Action Inbox and deep-linking

## Task 1 evidence

- RED: `node --test test/supabase/admin_card_data_operations_migration_test.js` failed 3/3 with `ENOENT` because the migration did not exist.
- GREEN: the named foundation, card-data, and benefit-enrichment migration contracts passed 13/13.

Ruling: Serialize each `(actor_id, request_id)` with a transaction-scoped advisory lock and persist the canonical normalized request JSONB, returning the prior result only when direct JSONB equality proves an exact replay and raising `request_id_collision` for changed request semantics. Cost if wrong: request processing takes one additional transaction lock, audit receipts are larger, and older receipts without the canonical request object cannot be replayed through this new RPC.

Ruling: Bind benefit approvals to the locked job's exact staging row and card, then mark that job completed in the same transaction after the existing approval RPC succeeds; quarantine excludes actively processing jobs. Cost if wrong: a future queue design that intentionally permits cross-job staging approval or live-job quarantine would require a narrow eligibility change.

- Task 1 review fix: replaced MD5-only replay comparison with direct canonical request JSONB equality. Added opt-in isolated PostgreSQL execution coverage that applies the real migration and verifies exact replay, changed-request collision, stale timestamps, staging ownership, audit-failure rollback, and concurrent identical calls. Local PostgreSQL: 4/4 passed; the disposable database and any temporary roles were removed.
- Task 1 review fix follow-up: PostgreSQL credentials are now passed only through protected libpq environment variables, never process arguments; the disposable connection replaces only the database name on the same validated loopback server, cleanup revalidates the generated database name, and errors redact both the source URL and password. Connection unit/static plus isolated PostgreSQL tests: 5/5 passed with no database or role residue.
- Task 1 review fix follow-up 2: the child process environment is now allowlisted, clearing inherited libpq host/address/port/database/user/password/service/SSL/options selectors before applying only validated URL-derived values. URL-less socket mode is pinned to `/tmp:5432`, password/service files are disabled, unsupported URL options are rejected, and hostile-inheritance plus socket regressions pass. Explicit TCP and socket opt-in PostgreSQL runs each passed 5/5 with no residue.
