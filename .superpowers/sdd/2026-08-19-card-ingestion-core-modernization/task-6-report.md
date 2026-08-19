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

## Review fix round 5/5 — 2026-08-20

### Red proof

- The new enqueue tests first failed TypeScript checking because both enqueue
  helpers returned `void`; the scheduled-seed fixture then showed that
  candidate count, rather than the RPC's inserted count, was being reported.
- The discovery/v5 contract failed before the production caller captured the
  legacy insert count and verified an exact pre-existing job on a zero insert.
- The focused material-finalization interleaving case reported **0 passed / 1
  failed** because a sibling approval remained staged and a sibling rejection
  caused the simulated finalizer to error.
- The recurrence/discovery static run reported **35 passed / 6 failed** before
  the finalizer joined the Task 3/4 lock namespace, audit identity was separated
  from terminal state, authoritative enqueue checks existed, numeric `1.0`
  matched TypeScript, and future v6 identity uniqueness was enforced.
- Three subsequent focused reds each reported **0 passed / 1 failed** before
  pending identity-review rows were locked before revalidation, parser identity
  locks were normalized, and a database unique-index backstop protected direct
  concurrent service-role inserts.

### Fixes

- The finalizer now pre-reads only the immutable job/card identity, acquires the
  exact `card_benefit_enrichment_review:<card-id>` transaction advisory lock,
  then locks and revalidates the leased job followed by its exact card/parser
  staging row. Staging status is derived once from that locked row; no unlocked
  or cached `EXISTS` decision remains.
- Final state and audit identity are separate. Pending authoritative staging
  produces `staged`; approved or rejected returned staging produces `completed`
  while retaining the audit link; completed/304 with a valid prior reviewed
  staging keeps that link without reopening review. Invalid or obsolete staged
  input becomes terminal `review_required`, clears its unsafe link, records an
  explicit failure category, and releases the lease. Apply-time truth tables
  and a real process-to-finalizer fixture cover pending, sibling approval,
  sibling rejection, prior approved 304, and invalid obsolete staging.
- Restored v5 rollback behavior in TypeScript: non-v6 enrichment uses the
  legacy `job_key` conflict-ignore upsert and returns the actual inserted row
  count, so a changed source/job key is not suppressed by v6 card/parser
  uniqueness. Card discovery accepts a zero insert only after verifying the
  exact existing v5 job before marking discovery resolved.
- V6 enqueue is service-role-only through ACLs and returns the exact inserted
  count. After deterministic shared card/parser locks it row-locks one
  authoritative catalog snapshot, stabilizes active-holder and matching pending
  identity-review rows, and revalidates credit type, current issuer/HTTPS URL
  identity and digest, held-discontinued policy, and unresolved-review exclusion.
  Changed-key conflicts fail the whole transaction; exact repeats return zero;
  valid mixed existing/new batches return their explicit partial count. The
  scheduled caller now reports the database count rather than candidate count.
- A non-destructive migration preflight raises
  `duplicate_v6_card_parser_preflight` if historical normalized v6 duplicates
  exist. A shared-lock trigger protects every future direct identity mutation,
  and a partial unique expression index on normalized v6 card/parser identity
  is the concurrency backstop. No historical row is deleted or merged and no
  business table or column was added.
- SQL review counts now require JSON numbers and validate numeric integrality
  and the exact `0..999,999,999` range before `bigint` conversion/summing.
  Consequently `1.0` and exponent-equivalent integers match JavaScript, while
  fractions, negatives, strings, ten-digit values, and overflows fail closed.

### Green verification

- Exact Task 6 Deno command — **101 passed, 0 failed**.
- Exact Task 6 migration command — **29 passed, 0 failed**.
- Expanded affected Task 4 migration command — **41 passed, 0 failed**.
- Affected admin benefit suite — **40 passed, 0 failed**.
- Card-discovery/v5 caller suite — **32 passed, 0 failed**.
- Additional legacy v5 worker/migration/rules suites — **28 passed, 0 failed**.
- Primary Task 6 total — **130 passed, 0 failed**; expanded affected total —
  **242 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all changed production TypeScript and
  the v5 production caller — passed.
- `deno fmt --check` on all changed TypeScript/test files — passed.
- `git diff --check` — passed.

Only the Task 6 migration changed in this round. Final pre-commit SHA-256 values:

- Task 3 unchanged: `e294fd029a2aaf30ce98764b44ce41652b8e02d19783618111cb0d3754ea2876`
- Task 4 unchanged: `ae8f21413add67fece38ae8e90e7a6ecfdbc1a526edfecec0ed95919b7e4f2ca`
- Task 6: `6cda51f2d52454e1535353c737a2a69eb046fcdb13d9cbfebf58fb14c62b6a32`

Live applied: **no**. No Docker, database/PostgreSQL/Supabase runtime, linked
Supabase command, migration apply/push/dry-run, external network, production
data, or live write was used. Ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction and concurrent-lock verification remains the
explicit unresolved gate.

## Review fix round 4/5 — 2026-08-20

### Red proof

- The focused stable-HTTP-200 process fixture reported **0 passed / 1 failed**
  while the worker read pending staging before finalization and sent that stale
  staging identity back to SQL.
- The focused enqueue contract reported **0 passed / 1 failed** while scheduled
  seeding still used a direct job-key upsert with no atomic card/parser
  exclusion shared with pilot initialization.
- The focused pilot projection contract reported **0 passed / 1 failed** while
  ten-digit review counts could unlock rollout.
- The recurrence migration suite reported **7 passed / 1 failed** before the
  initializer locked one authoritative catalog snapshot, local enqueue paths
  shared its identity serialization, and SQL enforced the exact review boundary.

### Fixes

- Stable canonical HTTP 200 now follows the established 304 contract: the
  worker always finalizes it as `completed` with a null staging argument and
  performs no pre-finalizer staging-status read. Under the locked job row, the
  finalizer alone preserves a link that is actually pending at that instant;
  approved, rejected, absent, or mismatched links are cleared. This closes the
  read-to-finalize race without changing Task 3 material supersession.
- Added one service-role-only, security-invoker enqueue RPC used by both local
  production enqueue callers. It validates and deterministically advisory-locks
  every card/parser identity before checking absence, so concurrent different-
  job-key inserts cannot create a second identity while pilot initialization is
  selecting the same card.
- Pilot initialization acquires those same identity locks, row-locks the exact
  five catalog candidates, and captures profile, issuer, URL, availability, and
  card type in one materialized authoritative snapshot. Eligibility, issuer
  diversity, absence, and insertion all derive from that snapshot; a concurrent
  catalog or enqueue change either precedes the locked snapshot or blocks until
  the transaction finishes and then fails closed. No table, business column, or
  index was added.
- TypeScript and SQL now require the same complete review metadata shape and an
  explicit `approved` status. Each decision count is a JSON number integer in
  `0..999,999,999`; missing, null, wrong-case, ten-digit, overflow, negative,
  fractional, and string values fail closed. TypeScript verifies safe-integer
  addition and SQL casts only the bounded values to `bigint` before summing.
  Migration-time assertions cover every boundary and the maximum accepted sum.

### Green verification

- Exact Task 6 Deno command — **97 passed, 0 failed**.
- Exact Task 6 migration command — **28 passed, 0 failed**.
- Expanded affected Task 4 migration command — **40 passed, 0 failed**.
- Affected admin benefit suite — **40 passed, 0 failed**.
- Primary Task 6 total — **125 passed, 0 failed**; expanded affected total —
  **177 passed, 0 failed**.
- `deno check --node-modules-dir=auto` passed for both changed production files
  and the `card-discovery` production caller.
- `deno fmt --check` on all changed TypeScript/test files — passed.
- `git diff --check` — passed.

Only the Task 6 migration changed in this round:
`supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`.
Final pre-commit SHA-256:
`b53c2c56c0bf6caa805aa442e03b7214fd73d841b450b7aa64ffdb39c4ea8232`.

Live applied: **no**. No Docker, database/PostgreSQL/Supabase runtime, linked
Supabase command, migration apply/push/dry-run, external network, production
data, or live write was used. Ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction and concurrent-lock verification remains the
explicit unresolved gate.

## Review fix round 3/5 — 2026-08-20

### Red proof

- The worker suite reported **72 passed / 2 failed** before missing pilot safety
  metadata failed closed and a stable canonical observation stopped being
  restaged merely because its prior staging link was absent.
- A real process-to-finalizer fixture then failed while a stable HTTP 200 with
  pending staging retained the old count-level `material` disposition instead
  of deriving no-change/reviewability from canonical materiality and locked
  staging status. The final fixture covers pending, approved, rejected, and no
  linked staging, plus a raw-only body/hash change.
- The three affected migration suites reported **25 passed / 4 failed** before
  the Task 3/Task 4 functions shared one advisory-lock namespace/order, expired
  pending-review work selected failure cadence, pilot evidence was strict, and
  initialization recognized the promoted exact-five cohort.
- Apply-time cohort and qualification cases were added before their helpers:
  partial, mixed 5+5, duplicate, missing/null/string/negative/noninteger safety
  metadata, unsafe true raw-body storage, and exact promoted return.

### Fixes

- A stable canonical HTTP 200 now reads the exact linked staging row by
  staging/card/parser/request identity. Pending remains `staged` and reviewable;
  approved, rejected, missing, or mismatched staging completes as successful
  no-change without presenting a reviewed row as a new proposal. A real
  material canonical change still delegates exclusively to Task 3, which
  deterministically supersedes an older pending proposal.
- Task 3 and Task 4 now pre-read only immutable card identity, acquire the same
  `card_benefit_enrichment_review:<card-id>` transaction advisory lock, and
  then lock and revalidate their authoritative job/staging row. This removes
  the former job-to-staging versus staging-to-job lock inversion while keeping
  stale/superseded approval fail-closed.
- Expired processing with pending staging retains its reviewable `staged`
  state and link but records `worker_resource_limit`, forcing the explicit
  seven-day failed-observation cadence rather than the 30-day staged-success
  cadence. It cannot busy-loop and Task 4 can still resolve the proposal.
- Pilot projection and SQL qualification require explicitly present,
  correctly typed `unsafe_mutation_count` and `raw_body_stored`; count must be
  a nonnegative integer equal to zero and raw-body storage must be false.
  Idempotency/evidence/review fields remain strict. Quarantine remains eligible
  only with an explicit lowercase bounded reason code; missing or malformed
  evidence fails closed.
- The authoritative same-signature initializer is versioned in the Task 6
  migration. It and promotion use one parser-scoped advisory lock. An exact
  five-row promoted marker cohort is returned idempotently; an exact active
  pilot cohort is returned unchanged; partial, mixed, 5+5, and duplicate
  card/parser states reject before insertion. Initial creation also refuses a
  candidate with any existing same-card/parser job. No job, business table, or
  column was added.

### Green verification

- Exact Task 6 Deno command — **96 passed, 0 failed**.
- Exact Task 6 migration command — **28 passed, 0 failed**.
- Expanded affected Task 3/4 migration command — **40 passed, 0 failed**.
- Affected admin benefit suite — **40 passed, 0 failed**.
- Primary Task 6 total — **124 passed, 0 failed**; expanded affected total —
  **176 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on changed production TypeScript —
  passed.
- `deno fmt --check` on changed TypeScript/test files — passed.
- `git diff --check` — passed.

Changed migration sources:

- `supabase/migrations/20260819122252_supersede_stale_benefit_staging.sql`
- `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`
- `supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql`

Final pre-commit SHA-256 values, in the same order:

- `e294fd029a2aaf30ce98764b44ce41652b8e02d19783618111cb0d3754ea2876`
- `ae8f21413add67fece38ae8e90e7a6ecfdbc1a526edfecec0ed95919b7e4f2ca`
- `4c556cae302b0447ad6b991c0dfba16361c07446f8c34325f8d2793a432f878b`

Live applied: **no**. No Docker, database/PostgreSQL/Supabase runtime, linked
Supabase command, migration apply/push/dry-run, external network, production
data, or live write was used. Ordered Task 2–6 real PostgreSQL
parse/apply/lint/transaction and concurrent-lock verification remains the
explicit unresolved gate.

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
