# Task 6 Report — Recur Card Benefit Observations Safely

Date: 2026-08-20

## Outcome

Task 6 reuses each existing `benefits-v6` job as a recurring observation job
without adding a business table or column. Terminal observations now receive a
central SQL-scheduled cadence, due jobs are requeued under row locks, every
invocation claims at most one card with a 300-second lease, and the worker keeps
its existing 180-second network-start budget. Staging identity, audit history,
and stable job identity survive recurrence.

## Red proof

The behavioral and static contracts were introduced before their implementation:

- The first Deno run failed type checking because `recurrence_policy.ts` and
  the exported `requeueDueJobs` boundary did not exist.
- The new migration suite initially reported **0 passed / 4 failed** because
  no recurrence migration existed.
- A focused unresolved-official-URL seed fixture failed before pending catalog
  identity reviews were excluded.
- Three focused SQL contracts failed before unresolved identity checks,
  service-only helper grants, and privacy-safe persisted summaries existed.
- The pre-existing terminal-v6 backfill contract failed before the migration
  routed old null-due terminal rows through the central trigger.
- Nested timestamp, typed-summary, and content-hash preservation contracts each
  failed before the corresponding sanitizers/finalizer behavior was added.
- The newest-recurring-observation regression failed while the worker still
  selected the oldest retained observation with `.at(-1)`.

All red cases remain as green regression coverage.

## Implementation

- Added one documented UTF-8 byte-sum jitter algorithm in TypeScript and SQL.
  Successful/not-modified observations recur at 30 days with inclusive ±3-day
  jitter; blocked/missing/terminal-failed observations recur at 7 days with
  inclusive ±1-day jitter. Unheld discontinued cards stop; actively held
  discontinued cards retain normal cadence.
- Added `requeue_due_card_catalog_enrichment_jobs(text, integer, timestamptz)`
  as a service-role-only, security-invoker RPC. It accepts only `benefits-v6`,
  rejects limits outside 1..200, takes deterministically ordered due terminal
  rows with `FOR UPDATE SKIP LOCKED`, and resets only queue/attempt/lease/due
  state while preserving stable identity, staging, history, and audit links.
- Centralized terminal scheduling in a trigger shared by batch finalization and
  Task 4 admin completion. Existing terminal v6 rows with no due date are
  backfilled through that trigger; v5 remains untouched.
- Versioned the same-signature claim RPC to one row and a 300-second lease.
  Expired-lease recovery and every claim path remain parser-scoped and exclude
  unavailable unheld cards and unresolved catalog identities.
- Versioned the same-signature finalizer to allow completed/no-change 304s with
  null new staging, preserve prior staging/content hashes, keep retry due dates
  separate from recurrence, and append/deduplicate/sort the newest 24 sanitized
  observations under the locked job row. Malformed/future timestamps and raw
  response bodies cannot enter retained history.
- The worker requeues due v6 jobs before pilot evaluation, scheduled seeding,
  and claiming. Scheduled seeding pages pending identity reviews, treats
  historical null discontinuation explicitly as available, includes only held
  discontinued cards, and does not create a second job.
- Recurring cache/history reads now select the newest valid observation rather
  than relying on array order. The workflow's existing 240-second HTTP cap and
  the worker's 180-second new-network-work deadline remain unchanged.
- Added pure migration-time assertions for jitter/cadence and 26-to-24 history
  normalization, including duplicate, future, malformed, and raw-body rejection.

## Changed files

- `supabase/functions/benefit-enrichment-batch/recurrence_policy.ts`
- `supabase/functions/benefit-enrichment-batch/recurrence_policy_test.ts`
- `supabase/functions/benefit-enrichment-batch/batch_policy.ts`
- `supabase/functions/benefit-enrichment-batch/batch_policy_test.ts`
- `supabase/functions/benefit-enrichment-batch/index.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`
- `supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`
- `test/supabase/recur_card_enrichment_jobs_migration_test.js`

## Green verification

- Exact Task 6 Deno command — **89 passed, 0 failed**.
- Exact Task 6 migration command — **24 passed, 0 failed**.
- Total named behavioral/static tests — **113 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all changed production TypeScript
  files — passed.
- `deno fmt --check` on all changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration:
`supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`

Migration SHA-256 before commit:
`08bc69b8e4f186ef594f875a1556f6867cdfbc1967bc96f492dd94847e86d532`

## Scope and remaining gate

Live applied: **no**.

The migration name was generated with the local offline
`supabase migration new recur_card_enrichment_jobs` command. No Docker, local
database/PostgreSQL/Supabase runtime, linked Supabase command, migration
apply/push/dry-run, external network request, production data, or live write was
used.

The unresolved integration gate is ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction verification in an explicitly authorized
environment. In particular, static tests do not claim real row-lock concurrency,
trigger execution, RPC privilege, or rollback-chain execution.
