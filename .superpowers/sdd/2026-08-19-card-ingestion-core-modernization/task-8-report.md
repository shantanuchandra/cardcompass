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
- `supabase/functions/benefit-enrichment-batch/index.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`
- `supabase/functions/_shared/issuer_card_crawl.ts`
- `supabase/functions/_shared/catalog_identity_publication.ts`
- `supabase/functions/_shared/catalog_identity_publication_test.ts`
- `test/gtm/benefit-enrichment-schedule.test.js`
- `test/supabase/card_discovery_rules.test.mjs`
- `test/supabase/issuer_card_crawl_rules.test.mjs`
- `test/supabase/issuer_card_discovery_rules.test.mjs`

No schema or migration file changed.

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
  deterministic 100-row pages, up to 1,000 rows. One due row is migrated by CAS
  to the stable key; an active row blocks a new-day claim; multiple rows fail
  closed into exact linked review work. A completed reconciliation marker avoids
  rescanning historical rows, while a late legacy backlog row explicitly forces
  reconciliation. An exhausted 1,000-row scan fails closed without crawling.
- Before selecting the current UTC day slot, the scheduler scans eligible
  service-owned failed/budget-exhausted and expired-discovering runs in stable
  `created_at,id` pages, then orders the bounded result by persisted run date.
  The oldest run is claimed first with its original issuer, date, canonical URL,
  candidate summaries, and last position. Multiple unfinished dates drain in
  order without a manual action. Five unsuccessful attempts terminalize a run as
  operator-visible `resume_attempts_exhausted`, so permanently bad work cannot
  starve fresh day-slot rotation forever. Legacy conflict review creation is
  capped at 20 exact linked jobs per invocation and drains later.
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
- Attempt-ceiling, invalid retained evidence, and legacy-anchor conflicts use
  Task 7's transactional `stage_card_catalog_identity_review` boundary with
  classification `issuer_discovery_quarantine`, a deterministic semantic hash,
  bounded private evidence, and the exact discovery-job link. They never mutate
  `card_catalog`; operators receive pending work that can be inspected, retried,
  or rejected.

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

Final GREEN commands:

- Plan Task 8 command (`2` workflow plus `45` issuer-crawl tests): **47 passed,
  0 failed**.
- Batch/Task 6 Deno suite (`recurrence`, `batch`, `crawl`, supporting documents,
  and batch entry): **205 passed, 0 failed**.
- Shared publication, shared issuer crawl, and card-discovery Deno suites: **32
  passed, 0 failed**.
- Repository-wide Node static and migration suite: **291 passed, 0 failed**.
- The four reported local gate executions cover **575 passing checks, 0
  failures**.
- Production `deno check` passed for the batch function, card discovery, issuer
  crawler, and catalog identity publication.
- Changed-surface `deno fmt --check`: passed.
- `git diff --check`: passed.

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
