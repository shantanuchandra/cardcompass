# Task 8 Report — Separate and Rotate Issuer Discovery

## Outcome

Task 8 is implemented as an explicit authenticated issuer-discovery action,
separate from scheduled benefit processing. A daily workflow calls
`{"action":"issuer_discovery","runMode":"scheduled"}` through the existing
benefit-enrichment authentication boundary. Benefit enrichment and issuer
discovery share one non-cancelling repository concurrency lane.

Issuer selection is deterministic by UTC date over a sorted, distinct issuer set
loaded from the complete reviewed credit-card catalog with explicit pagination.
One stable service-owned `card_discovery_jobs` anchor per normalized issuer now
provides cross-day run identity, lease, progress, retry, bounded history, and
completion state. No cursor table, issuer business column, or migration was
added.

Every candidate reaches durable central publication/review or a bounded
sanitized terminal outcome before the crawler requests the next candidate.
Candidate progress is keyed, bounded, replace-on-retry, and resumable. Terminal
known, new, ambiguous, quarantined, and rejected outcomes are skipped on resume;
transient fetch failures remain retryable. Complete directory absence can stage
review only after every selected root, nested source, and candidate has a
positive terminal result.

Live applied: **no**.

## Files

Created:

- `.github/workflows/card-discovery-schedule.yml`
- `test/gtm/card-discovery-schedule.test.js`
- this report

Modified:

- `.github/workflows/benefit-enrichment-schedule.yml`
- `lib/features/admin/screens/card_catalog_review_screen.dart`
- `supabase/functions/benefit-enrichment-batch/index.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`
- `supabase/functions/_shared/issuer_card_crawl.ts`
- `supabase/functions/_shared/catalog_identity_publication.ts`
- `supabase/functions/_shared/catalog_identity_publication_test.ts`
- `supabase/migrations/20260819231435_publish_reviewed_card_identity.sql`
- `test/features/admin/benefit_enrichment_review_test.dart`
- `test/gtm/benefit-enrichment-schedule.test.js`
- `test/supabase/card_discovery_rules.test.mjs`
- `test/supabase/issuer_card_crawl_rules.test.mjs`
- `test/supabase/issuer_card_discovery_rules.test.mjs`
- `test/supabase/publish_reviewed_card_identity_migration_test.js`

No table, column, index, constraint, or new migration was added. The existing
unapplied Task 7 publication migration was updated in place to make quarantine
retry/reject transactional. Its reviewed SHA-256 is
`d7a1323ef0c2fc2e6020a791a51462afc0e311f6424745d8e0defac5bae47755`.

## Scheduler and action boundary

- The new workflow runs daily at `02:17 UTC`, also permits bounded operator
  dispatch, has a five-minute job timeout, and uses `curl --fail-with-body`, a
  10-second connect timeout, a 240-second total timeout, and two retries.
- It references only the existing `SUPABASE_FUNCTION_URL` and
  `BENEFIT_ENRICHMENT_CRON_SECRET` secrets and validates the returned action and
  run UUID.
- Both workflows use `group: cardcompass-issuer-crawl` and
  `cancel-in-progress: false`; issuer crawling cannot overlap or cancel benefit
  crawling.
- The Edge action accepts only explicit `scheduled` or `manual` issuer modes
  after the existing constant-time cron/service credential check.
- The former benefit-job-empty issuer-discovery branch is removed. Benefit
  backlog size, including an empty backlog, cannot invoke discovery.

## Rotation and persistence decisions

- The catalog loader pages in batches of 200 until the final short page, so a
  default 1,000-row Data API window cannot hide an issuer.
- Eligible production state is the reviewed `card_catalog` credit-card set plus
  the existing official issuer-domain allowlist. This includes an issuer when
  all its cards are discontinued. The current schema has no issuer-level
  approved/enabled columns; therefore Task 8 deliberately adds none. The pure
  selector also fails closed on explicit false approved/enabled flags if such
  state is supplied by a caller.
- Issuer identity is normalized case-insensitively, its deterministic canonical
  URL is the lexical minimum approved URL, and issuer keys are sorted once.
  Selection is `UTC epoch day modulo issuer count`, providing restart stability
  and consecutive-day rotation without mutable cursor state.
- A SHA-256 key over normalized issuer, independent of run date, uses the
  existing unique service-owned `(discovery_source, dedupe_key)` boundary.
  Insert races recover by loading the winner; an active five-minute lease fences
  every UTC date and manual invocation for that issuer. A resolved anchor is
  same-slot idempotent and starts the next selected UTC slot on that same row.
  Evidence records the current slot, attempt, and sanitized newest-24 run
  history; candidate progress resets only for a new positively completed slot.
- Legacy date-keyed rows are scanned separately from candidate-outcome jobs in
  deterministic 100-row pages, up to 1,000 rows, on every issuer claim. The
  query is case-insensitive and results are normalized again in process; no
  permanent reconciliation marker is trusted during mixed deployment. One due
  row is migrated by CAS to the stable key, any active legacy lease blocks the
  stable holder, and multiple due rows fail closed into review work. An
  exhausted 1,000-row scan fails closed without crawling.
- Before selecting the current UTC day slot, the scheduler scans eligible
  service-owned failed/budget-exhausted and expired-discovering runs in stable
  `created_at,id` pages, then orders the bounded result by persisted run date.
  The oldest run is claimed first with its original issuer, date, canonical URL,
  candidate summaries, and last position. Multiple unfinished dates drain in
  order without a manual action. Five unsuccessful attempts terminalize a run as
  operator-visible `resume_attempts_exhausted`, so permanently bad work cannot
  starve fresh day-slot rotation forever. Legacy conflict review creation is
  capped at 20 separate exact-anchor-reference jobs per invocation and drains
  later.
- Each claim installs an opaque UUID lease token inside the existing bounded run
  evidence. Every progress/final compare-and-set requires the exact current
  token and rotates it, returning the next token to the holder. An expired
  holder cannot overwrite candidate position or finalize after another
  invocation reclaims the row. This adds fencing without a schema column.
- Progress retains at most 200 unique candidate summaries, matching the source
  cap. A retried candidate replaces its old summary and moves to the end, so one
  retry cannot evict unrelated completed progress and cause an oscillating
  recrawl.
- Only a positively complete result (`complete`, no budget exhaustion, and no
  incomplete reasons) resolves. Every crawler, candidate-persistence,
  progress-PostgREST, publication, or final-write exception that still owns the
  lease finalizes as failed with retained evidence and exponential five-minute
  to six-hour backoff. Exact token loss returns `lost_lease` without a stale
  write.
- A failed anchor with a future `next_retry_at` returns `backoff` from backlog,
  fresh-slot, and manual claim paths without incrementing attempts or mutating
  its lease.
- Attempt-ceiling, invalid retained evidence, anchor identity disagreement, and
  legacy-anchor conflicts keep the private producer row `failed` with explicit
  `issuer_discovery_quarantined` state. Task 7's transactional staging boundary
  creates a separate deterministic service job/review containing only bounded
  classification, reason, issuer, and anchor ID. It never carries a lease token,
  outcome history, producer evidence, or an admin link on the anchor.
- Admin `retry` locks both review and referenced producer in the unapplied Task 7
  RPC, audits an explicit `attempt_count = 0` policy, makes the producer due, and
  resolves the operator item atomically. The next claim starts attempt one.
  Admin `reject` rejects only the separate review job and leaves the producer
  failed/quarantined and unclaimable. The admin card shows only retry/keep
  actions for this classification.
- Stable anchor validation derives authority from the locked row issuer and
  requires normalized selected issuer, evidence issuer, stable dedupe hash, and
  approved official URL issuer to agree. A mismatch quarantines that exact row;
  it cannot route or create a crawl for another issuer.
- Discovery responses always return `staged`, `quarantined`, and `conflicts`
  counts. Review-only work sets `noWork=false` even when no crawl seed is issued.

## Deadline, resume, and completeness decisions

- The crawler checks the shared absolute 180-second internal deadline before
  delay and immediately before every network request. It does not start a new
  request when the remaining budget is insufficient.
- An in-flight deadline failure is recorded as an attempted transient outcome; a
  pre-request deadline leaves the candidate unattempted. Both make the run
  `budget_exhausted` and resumable.
- At most 40 new candidate page requests run per invocation. Persisted terminal
  keys are reconstructed without network work on later invocations, allowing a
  bounded run to progress through the full 200-candidate directory.
- Rejected query resources, hard negatives, fetch failures, cross-host
  responses, identity mismatches, ambiguous pages, supporting documents,
  existing cards, and new-card review work are awaited durably before the next
  candidate fetch.
- A nested sitemap-index child is always treated as a directory source even when
  its path does not look like a sitemap. Rejected/unapproved children, malformed
  or cross-host sources, source/candidate/depth caps, unattempted
  sources/candidates, fetch failures, quarantines, and deadline exhaustion all
  force `complete=false` with bounded reasons.
- An empty inventory is complete only after all selected directory sources parse
  positively with no cap, truncation, or failure and at least one successful
  source is explicitly product-directory scoped. A generic empty sitemap cannot
  prove inventory. A terms/supporting-document-only listing persists its
  evidence but remains `product_inventory_unproven`; a mixed product plus terms
  listing can be complete. Only proven inventory then loads all known issuer
  cards with pagination and passes them to the existing exact
  family+tier+effective-network/card-type absence review boundary.
- Product-directory proof requires the requested URL and both fetched final and
  canonical URLs to remain on the same approved issuer directory scope. A
  redirect to a generic sitemap, home page, unrelated directory, or product
  detail child adds bounded `product_directory_scope_mismatch` evidence and
  cannot prove absence.
- Explicit approved layouts `/credit-card-sitemap.xml`,
  `/credit-cards-sitemap.xml`, and `/cards/credit-cards.xml` are recognized as
  product-directory sources, but redirects from any of them to a generic
  sitemap/home scope remain incomplete.
- Incomplete issuer work does not alter or suppress Task 6 recurring benefit
  scheduling.

## Carried Task 7 identity and lifecycle findings

- Crawler publication reconciles current submitted, current final, legacy
  display submitted, and legacy display final URL hashes before identity
  resolution. A different-card binding fails closed and becomes actionable
  bounded central review evidence.
- Approved functional query resource URLs and hashes remain distinct from
  sanitized display URLs.
- Discontinuation scope derives short sibling product identities such as
  `My Zone` even when their headings omit `card`, while normal `Availability`,
  `Status`, `Fees`, `Benefits`, and `Eligibility` headings remain inside the
  target section. Table/product-card boundaries stop scope, and the old global
  fallback cannot cross an excluded sibling section. Existing target-specific
  table/card evidence and bounded matched excerpts remain intact. Headingless
  evidence is accepted only when one bounded sentence contains the exact target
  discontinuation and no competing/related/successor product context.
- `Product Status`, `Product Update`, `Important Notice`, and `Discontinuation
  Notice` remain normal target sections. Comparison/versus/replacement/
  successor/alternative prose, related-product anaphora without the literal word
  `card`, and multi-product status rows fail closed.
- Status evidence is additionally clause-bound: same-cell `Neo and My Zone` or
  comma variants, competitor-named status/availability elements, and generic
  `this card` after a competing product subject are rejected. Target-only
  status cells, elements, and scoped containers remain valid.

## Red-to-green evidence

Initial RED checkpoints:

- `deno test ... benefit-enrichment-batch/index_test.ts` failed type checking
  because paginated loading, rotation, explicit action/auth, and same-day claim
  interfaces did not exist.
- Workflow contract tests: **0 passed, 2 failed** because the discovery workflow
  was absent and the workflows did not share a concurrency group.
- Issuer crawl contract tests: **29 passed, 5 failed** for rejected nested-child
  completeness, awaited outcome persistence, pre-request deadline cutoff,
  normal-heading discontinuation scope, and current-plus-legacy identity
  reconciliation.
- Focused follow-up tests separately failed for scheduler-auth export,
  path-agnostic sitemap-index children, in-flight deadline persistence,
  rejected-outcome resume, transient-failure retry, and bounded retry-summary
  replacement. Each failure was observed before its production change.
- Correction-round RED tests then failed on all four review findings: the
  backlog/lease APIs and token were absent (six type errors), supporting-only
  and generic-empty sources incorrectly reported complete, `My Zone` without
  `card` did not end target scope, global fallback crossed sibling sections, and
  competing/related product sentences were accepted. The exact behavioral tests
  were green only after their production boundaries changed.
- Fix-round-2 RED tests reproduced all five new findings: incomplete outcomes
  resolved; injected candidate/progress/publication/final failures were not
  resumable; lease loss attempted stale finalization; cross-date and late legacy
  rows bypassed issuer fencing; product-directory redirects proved empty
  inventory; common lifecycle headings ended target scope while ambiguous
  competitor evidence matched; and attempt ceilings had no review item. Extra
  reds covered malformed retained attempts/counters, unknown history fields,
  legacy rows hidden beyond two pages or behind 200 candidate outcomes, bounded
  conflict draining, and retry-stable quarantine identity.
- Fix-round-3 RED tests reproduced all eight findings: immediate workflow retry
  reclaimed a future-backoff anchor; mixed-case late legacy leases bypassed the
  stable holder; quarantine exposed the producer row; stable issuer/dedupe/URL
  mismatches spawned or routed crawls; handler review work reported no-work;
  competitor-bound discontinuation clauses matched; common product-sitemap
  filenames were rejected; and the Task 7 RPC had no quarantine retry contract.
  A separate widget RED showed generic catalog approval actions for quarantine.

Final GREEN commands:

```sh
node --test test/gtm/card-discovery-schedule.test.js test/gtm/benefit-enrichment-schedule.test.js test/supabase/issuer_card_crawl_rules.test.mjs
```

Plan Task 8 workflow plus issuer-crawl checks: **48 passed, 0 failed**.

```sh
deno test supabase/functions/benefit-enrichment-batch/index_test.ts supabase/functions/benefit-enrichment-batch/recurrence_policy_test.ts supabase/functions/benefit-enrichment-batch/batch_policy_test.ts supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts
```

Batch/Task 6 checks: **212 passed, 0 failed**.

```sh
deno test supabase/functions/_shared/catalog_identity_publication_test.ts supabase/functions/_shared/issuer_card_crawl_test.ts supabase/functions/card-discovery/index_test.ts
```

Shared publication, issuer crawl, and card discovery: **33 passed, 0 failed**.

```sh
node --test --test-concurrency=1 $(find test -type f \( -name '*.test.js' -o -name '*.test.mjs' -o -name '*_test.js' \) -print | sort)
```

Repository-wide Node/static/migration checks: **386 passed, 0 failed**.

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
```

Focused admin presentation checks: **11 passed, 0 failed**.

The five reported local gate executions cover **690 passing checks, 0
failures**. Production `deno check` passed for the batch function, card
discovery, issuer crawler, catalog identity publication, and admin entry point.
Changed-surface Deno/Dart formatting checks and `git diff --check` passed.

All verification used local mocks/static files only. No Docker, local or linked
Supabase/Postgres, issuer/network request, production data, secret mutation,
workflow enablement/dispatch, or live write was used.

## Remaining live-only rollout gates

These remain intentionally unexecuted:

1. verify the two existing repository secrets in the target environment;
2. deploy the reviewed Edge function revision with scheduling still disabled;
3. issue one bounded manual smoke request for an allowlisted issuer and verify
   claim/progress evidence without approving publication;
4. observe same-day overlap/lease recovery and real issuer rate-limit duration;
5. enable the daily workflow only through the Task 12 staged rollout gate, then
   monitor one issuer slot before expanding coverage.

## Fix round 4/5 — projection-realistic quarantine and bounded repair

This round closes the fourth scoped-review findings without adding a migration
or business column.

- Every issuer `card_discovery_jobs` PostgREST projection now explicitly selects
  `failure_category`. The scheduler fake applies the requested projection rather
  than returning full rows, so an omitted field can no longer make a test pass.
- Every claim performs bounded, paginated discovery of all stable-anchor-kind
  rows whose row issuer normalizes to the selected issuer. Corrupt stable keys,
  evidence, URLs, attempts, or UTC run dates are quarantined even when the row is
  future-backoff or resolved; no replacement anchor is inserted.
- Legacy reconciliation uses a tokenized broad `ilike` search followed by exact
  whitespace/case-normalized post-filtering. Active late legacy leases remain a
  claim fence on every invocation.
- Quarantine first CAS-transitions the private producer to
  `failed/issuer_discovery_quarantined` with a due retry marker, then stages the
  separate bounded review. A staging or final clear failure therefore remains
  self-fenced and resumable. Review identity is stable anchor ID plus semantic
  reason and no longer contains mutable `updated_at`; retry reuses the same
  review. A fully staged producer clears the retry marker and later invocations
  do not restage it.
- Review observations explicitly carry bounded `retryable` and
  `retryability_reason`. Only attempt exhaustion or a typed transient producer
  state can be retried. Identity/evidence/key/URL/run-date corruption is marked
  `manual_repair_required`; the admin surface hides Retry, explains the manual
  repair requirement, and retains only Keep quarantined. The Task 7 RPC validates
  this policy server-side and rejects Retry for nonretryable reviews.
- Retry and Keep quarantined requests both require a trimmed operator reason.
  The request-envelope helper and widget tests cover the exact payload and
  presentation behavior.
- Quarantine transition/staging uses one shared per-invocation budget of 20 and
  checks the internal deadline before every row. Responses include exact
  `staged`, `quarantined`, `conflicts`, and `remaining` counts. A 1,000-corrupt-
  anchor fixture stages 20, reports 980, and never starts seed crawl work.
- Target-only neutral lifecycle text such as `Status: discontinued effective
  DATE`, a neutral status element, and `Due to a portfolio review, this card...`
  is accepted. Competing proper-product subjects remain rejected, including
  competitor-named status/availability elements and anaphora.

### Fix-round-4 red and green evidence

The first combined focused Deno RED run reported **137 passed / 11 failed**.
The failures covered whitespace-normalized legacy fencing, future/resolved
corrupt stable rows, staging/clear quarantine recovery, retryability metadata,
exact bounded remaining counts, the 1,000-row cap, response accounting, and
neutral lifecycle wording. The projection-aware fake also exposed prior
quarantine/reject behavior that had depended on unselected fields. SQL and
Flutter contract/widget repros were added for server-enforced retryability,
required reasons, request payloads, and nonretryable presentation.

Fresh final commands and exact counts:

```sh
node --test test/gtm/card-discovery-schedule.test.js test/gtm/benefit-enrichment-schedule.test.js test/supabase/issuer_card_crawl_rules.test.mjs
```

Workflow/crawler checks: **48 passed, 0 failed**.

```sh
deno test supabase/functions/benefit-enrichment-batch/index_test.ts supabase/functions/benefit-enrichment-batch/recurrence_policy_test.ts supabase/functions/benefit-enrichment-batch/batch_policy_test.ts supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts
```

Batch/Task 6 checks: **218 passed, 0 failed**.

```sh
deno test supabase/functions/_shared/catalog_identity_publication_test.ts supabase/functions/_shared/issuer_card_crawl_test.ts supabase/functions/card-discovery/index_test.ts
```

Shared publication, issuer crawl, and card discovery: **34 passed, 0 failed**.

```sh
node --test --test-concurrency=1 $(find test -type f \( -name '*.test.js' -o -name '*.test.mjs' -o -name '*_test.js' \) -print | sort)
```

Repository Node/static/migration checks: **386 passed, 0 failed**.

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
```

Focused admin checks: **12 passed, 0 failed**.

The corrected fix-round-3 baseline was **689**, not 690: its Flutter command
contained 10 tests, while the prior report counted 11. Fix round 4 adds six
batch tests, one shared lifecycle test, and two Flutter tests, for **698 passing
checks, 0 failures** across the five non-overlapping reported executions.

Production `deno check` passed for the batch function, card discovery, shared
issuer crawler, catalog identity publication, and admin entry point. Focused
Flutter analysis returned no issues. Changed-surface Deno/Dart formatting and
`git diff --check` passed.

The existing unapplied Task 7 migration changed from SHA-256
`d7a1323ef0c2fc2e6020a791a51462afc0e311f6424745d8e0defac5bae47755` to
`8e0dd3ac01346d5ec7531be906bc974480e0e93c8f8d9f482b6010323e06a3a7`.
No migration or schema object was added.

Live applied: **no**. No Docker, database/Postgres/Supabase runtime, linked or
live command, issuer/external network, production data, secret change, remote
workflow enablement/dispatch, or live write was used. The existing live-only
rollout gates above remain pending.
