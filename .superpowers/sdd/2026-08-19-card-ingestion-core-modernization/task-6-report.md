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

## Review fix round 1/5 — 2026-08-20

### Red proof

The review findings were reproduced before their fixes:

- The strict recurrence-policy suite reported **4 passed / 1 failed** because
  JavaScript accepted a normalized February 30 timestamp. The retained cases
  also reject spaces, offsets, missing milliseconds, and future values.
- The pilot-policy suite reported **14 passed / 1 failed** because a safe
  `completed` job was treated as nonterminal.
- The batch suite failed type checking because the real `processJob` boundary
  was not exported/injectable for a controlled primary fetch. After the test
  boundary existed, four real process-to-finalizer cases covered deadline,
  timeout, HTTP 5xx, and unreachable dispositions.
- The expanded recurrence migration suite reported **0 passed / 6 failed** for
  null-due revival, pilot/run-mode policy, pending staging protection, legacy
  root history, one locked mutation, strict UTC parity, and transition helpers.
- Three later focused reds each reported **0 passed / 1 failed** before the
  worker used `_limit=1`, expired pending-staging work recovered to reviewable
  `staged`, and queueable live work sorted ahead of clear-only pilot/manual
  housekeeping.

### Fixes

- Failed primary fetch observations now derive the normal bounded job-level
  retry before finalization. The finalizer receives a non-null 15/60-minute
  retry for attempts one/two, while every compacted source attempt and terminal
  source disposition remains in the sanitized observation.
- `completed`, `staged`, and justified `quarantined` are explicit pilot terminal
  states. Pilot/manual rows are one-shot qualification/operator lanes: terminal
  scheduling recurs only `scheduled` rows, and stale non-live due fields are
  cleared without queueing them or blocking the pilot gate.
- Replaced the separate unbounded discontinued-row update with one policy-driven
  `LIMIT _limit ... FOR UPDATE SKIP LOCKED` update. The worker invokes it with
  `_limit=1`; queueable scheduled work sorts before bounded housekeeping.
- The same transition queues an eligible scheduled terminal row whose due date
  is null after a holder, availability, or identity-review resolution change.
  Still-discontinued/unheld, unresolved, pending-review, future-due, retrying,
  leased, processing, v5, pilot, and manual rows cannot be revived.
- Added a partial v6 recurrence index over parser/run-mode/status/due/order keys.
  No business table or column was added.
- A linked pending staging proposal freezes recurrence and claiming. Expired
  processing work with such a proposal returns to `staged`, not failed, so Task
  4 can approve it. Approval changes staging status before completing the job;
  the shared trigger then schedules the next live observation. This prevents a
  newer observation from silently making an older pending proposal unsafe.
- First recurrence now merges the legacy root `result_summary.observation` with
  the existing array before sanitizing, deterministic composite deduplication,
  sorting, and newest-24 truncation. Root/current priority is deterministic.
- Read-side deduplication now matches SQL identity exactly:
  observed timestamp + source-manifest hash + canonical-benefit hash. Distinct
  same-time evidence survives; exact duplicates collapse.
- TypeScript accepts only real canonical `YYYY-MM-DDTHH:mm:ss.SSSZ` instants.
  SQL independently round-trips that shape and performs recurrence arithmetic
  as epoch seconds plus exact 86,400-second UTC days, independent of session
  timezone or DST. Migration assertions run the DST case under
  `America/New_York` and reject malformed/noncanonical values.
- Apply-time pure assertions now cover pilot clear, scheduled due/null revival,
  pending/ineligible clearing, future no-op, exact DST cadence, malformed time,
  legacy-root retention, same-time composite identity, and newest-24 history.

### Green verification

- Exact Task 6 Deno command — **91 passed, 0 failed**.
- Exact Task 6 migration command — **26 passed, 0 failed**.
- Total named behavioral/static tests — **117 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all changed production TypeScript
  files — passed.
- `deno fmt --check` on all changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration remains
`supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`.
Review-fix SHA-256 before commit:
`5864b39567d6ee6b4e202961a6e4e9f817be1e49d477b9d72285ca0014319466`.

Live applied: **no**. No Docker, local database/PostgreSQL/Supabase runtime,
linked Supabase command, migration apply/push/dry-run, external network,
production data, or live write was used. Ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction verification remains the explicit unresolved gate.

## Review fix round 2/5 — 2026-08-20

### Red proof

- The expanded pilot-policy case reported **14 passed / 1 failed** when a
  fully rejected Task 4 review still unlocked rollout. After review projection
  was introduced, an additional red proved a promoted job becoming queued or
  processing self-deadlocked its own scheduled claim.
- The worker suite initially failed type checking because neither the Task 4
  review projection nor the atomic pilot-promotion boundary existed.
- The expanded recurrence migration suite reported **3 passed / 5 failed**
  before pending staging could recur, the finalizer could preserve a current
  review across later outcomes, obsolete approval was tied to the authoritative
  link, and an exact-five pilot handoff existed.
- A promoted-identity seed fixture failed before the persisted handoff marker
  was included in the card/parser exclusion.

### Fixes

- A terminal scheduled `staged` job now receives normal cadence, requeues under
  the same bounded lock, and can be claimed while retaining its current
  `staging_id`. Task 3 remains the sole ordered supersession path: a later
  complete material/removal observation rejects older pending staging and
  moves the authoritative job link; history is retained.
- The finalizer derives an effective terminal status under the locked job row.
  When the authoritative linked staging is still pending, later no-change or
  failed observations return the row to reviewable `staged`, keep the link,
  append the observation, and schedule the appropriate long/short cadence.
  Task 4 approval still requires that exact authoritative link and staged job;
  an obsolete staging approval raises and its transaction rolls back.
- Added a service-only, security-invoker pilot promotion RPC. It locks exactly
  five qualifying pilot rows, rejects mixed/duplicate card-parser identities,
  and changes those same rows to `scheduled` with a durable
  `pilot_qualified` marker. It inserts no job, is idempotent, and its repeated
  path does not reschedule or requalify ordinary queued/processing recurrence.
- Scheduled gate reads and seeding include the persisted marker. Exactly five
  promoted identities keep the gate passed regardless of later scheduled job
  state, preventing requeue-before-gate self-deadlock while continuing to
  exclude duplicate card/parser seeds. A later completed admin rejection is
  still re-evaluated and blocks the gate.
- Pilot projection now carries `successful_no_change`, `review_status`, and all
  Task 4 decision counts. Completed no-change and zero-rejection approved
  reviews pass. Fully rejected, mixed/partially rejected, missing, negative,
  and malformed review metadata fail closed. Quarantine still requires a
  non-empty justification.
- Added apply-time assertions for staged recurrence, pending-review effective
  terminal state, completed no-change, approved review, fully rejected review,
  partial rejection, malformed counts, and justified quarantine. No Task 3 or
  Task 4 RPC was copied or redefined, and no business table/column was added.

### Green verification

- Exact Task 6 Deno command — **93 passed, 0 failed**.
- Exact Task 6 migration command — **28 passed, 0 failed**.
- Total named behavioral/static tests — **121 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all changed production TypeScript
  files — passed.
- `deno fmt --check` on all changed TypeScript files — passed.
- `git diff --check` — passed.

Migration remains
`supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`.
Review-fix-round-2 SHA-256 before commit:
`9c405adbd2a752057c2a847e6e4ab5cb5a79392cd0d88a8fc9c1cf1a5aaaf6a7`.

Live applied: **no**. No Docker, local database/PostgreSQL/Supabase runtime,
linked Supabase command, migration apply/push/dry-run, external network,
production data, or live write was used. Ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction verification remains the explicit unresolved gate.
