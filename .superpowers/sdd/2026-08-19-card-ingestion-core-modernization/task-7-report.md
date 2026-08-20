# Task 7 Report — Unified Reviewed Card Identity Publication

## Outcome

Task 7 is implemented as one reviewed, transactional catalog-identity
publication boundary. Statement/user discovery, issuer crawler discovery,
catalog enrichment, lifecycle observations, and legacy manual catalog entry no
longer write canonical card rows from Edge code. Reviewed publication now owns
strong identity resolution, URL keys, append-only provenance, audit, lifecycle
state, and the exactly-one benefits-v6 recurring job outcome. The review
hardening pass also removes existing-card bypasses, binds reviewed changes to a
catalog baseline, and turns recurring 410/explicit-discontinuation/reappearance
observations into bounded review work without changing acquisition state. The
second hardening pass versions review work by resource/content identity, keeps
terminal decisions immutable, serializes identity at issuer/product-family
scope, and preserves network/tier variants throughout discovery, recurrence,
and publication. The third hardening pass makes terminal user-URL submissions
fetch-first and observation-versioned, puts every worker state transition behind
compare-and-set ownership, revalidates trusted observations under publication
locks, and makes every authoritative lifecycle observation advance one
chronological per-card latest-evidence contract.
The fourth hardening pass moves all non-lifecycle review creation, refresh, and
job linkage into one service-only transaction; makes reviewed inputs
server-authoritative; separates semantic product versions from raw transport
provenance; and keeps user URL request anchors stable across identical replay,
content change, and fetch failure. Complete issuer-directory absence is now
review evidence only when directory completeness is proven, while issuers whose
known cards are all discontinued remain discoverable for reappearance.

Live applied: **no**.

## Files changed

Created:

- `supabase/migrations/20260819231435_publish_reviewed_card_identity.sql`
- `supabase/functions/_shared/catalog_identity_publication.ts`
- `supabase/functions/_shared/catalog_identity_publication_test.ts`
- `supabase/functions/card-discovery/index_test.ts`
- `test/supabase/publish_reviewed_card_identity_migration_test.js`
- this report

Modified:

- `supabase/functions/_shared/card_discovery.ts`
- `supabase/functions/_shared/issuer_card_crawl.ts`
- `supabase/functions/_shared/issuer_card_crawl_test.ts`
- `supabase/functions/_shared/official_issuer_fetch.ts`
- `supabase/functions/admin-catalog-entry/index.ts`
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
- `supabase/functions/benefit-enrichment-batch/index.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`
- `supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts`
- `supabase/functions/card-discovery/index.ts`
- `supabase/functions/catalog-enrichment/index.ts`
- `supabase/functions/catalog-enrichment/index_test.ts`
- `test/supabase/card_catalog_enrichment_rules.test.mjs`
- `test/supabase/card_discovery_rules.test.mjs`
- `test/supabase/issuer_card_discovery_rules.test.mjs`
- `test/supabase/official_issuer_fetch_rules.test.mjs`

No earlier migration was modified.

## Migration

- File: `20260819231435_publish_reviewed_card_identity.sql`
- SHA-256: `fc41f4d7d1bfab96536bc04197321130f640aa9c1094725c6e22de306daca631`
- Created with `supabase migration new publish_reviewed_card_identity`.
- Project-ref preflight remained exactly `prbcoxqobhjnnfnxevxf`.

## Interfaces and authority

- Hardened the same-signature
  `resolve_card_catalog_identity(text,text,text,text,text,text)` function.
- Added
  `publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)`
  returning `(card_id, job_id, resulting_status)`.
- Kept
  `review_card_catalog_discovery(uuid,uuid,text,jsonb,uuid,text)` as a thin
  30-day compatibility wrapper.
- Added the internal page-move boundary
  `adopt_reviewed_card_enrichment_source(uuid,text,text,text,text,text)` and the
  service-only, transactional non-lifecycle review boundary
  `stage_card_catalog_identity_review(uuid,text,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb,numeric,text,timestamptz)`,
  service-only lifecycle-review boundary
  `stage_card_catalog_lifecycle_review(uuid,text,jsonb,text,text,text,text)` and
  a nullable-version-safe full catalog snapshot comparator, plus the
  retained-history cleanup boundary
  `terminalize_calculator_review_rows(uuid,integer,boolean)`.
- Resolver, publisher, wrapper, and internal helpers are `SECURITY INVOKER`,
  have fixed search paths, are revoked from public application roles, and are
  executable only by `service_role` where needed.
- The legacy service-role grant on `create_or_get_card_catalog(...)` is revoked,
  removing the remaining alternate canonical writer without changing the v5
  benefit rollback lane.
- `resolve_verified` accepts only independently verified statement jobs with no
  actor/review item. `observe_existing` is limited to service-role execution,
  an already exact credit-card target, issuer/family/tier/network/hash
  compatibility, validated official HTML with HTTP 200, and no mutable catalog
  changes. New crawler/user identities still require pending review and an
  authenticated actor whose authoritative `public.users.is_admin` flag is
  true.

## Identity, URL, and artifact decisions

- Submitted and final hashes are reconciled independently across URL keys and
  provenance. Multiple bindings or two different bound cards fail with
  `conflicting_url_identity` before durable mutation.
- Bound URLs are revalidated against issuer, normalized product/tier, and
  payment network. Weak standalone aliases such as Visa, Gold, Platinum,
  Infinite, Signature, and World cannot resolve or create a product.
- Identity resolution takes its advisory lock at issuer/product-family scope,
  independently of whether the request supplied a network or tier. If a
  same-issuer/family candidate exists but no candidate is compatible with all
  authoritative network/tier/type evidence, resolution raises
  `strong_catalog_identity_conflict`; it never inserts a weaker duplicate.
- Product classification retains family variants such as Gold, Platinum,
  World, World Elite, Signature, and Infinite end to end. Historical aliases
  may prove family membership without matching the current display name, but
  they cannot weaken a stored network/tier or the credit-card type constraint.
- Production loaders now carry stored network evidence and fail closed on
  absent-network, absent-tier, non-credit, cross-network, or ambiguous hash/body
  matches. Ordinary fees/terms/benefits prose is excluded from competing title
  identity.
- Stored network authority is derived from both the catalog network column and
  the product name. A disagreement is a hard identity conflict; a null legacy
  column cannot make a name-encoded Visa/Mastercard/RuPay/Amex variant a
  wildcard. American Express tier-only products retain the same strong
  issuer/network/tier treatment as other network variants.
- SQL and TypeScript retain only approved functional query keys, preserve
  query ordering/duplicates/encoding, remove tracking and fragments, reject
  credentials/sensitive keys, and enforce issuer-domain ownership and the
  Task 5 size/count bounds.
- Task 5 display URLs remain queryless. New `submittedResourceUrl` and
  `finalResourceUrl` values carry only the exact already-approved request URLs
  used for opaque hashing and Task 7 publication. This prevents a functional
  query hash from being paired with a different queryless URL.
- Publication atomically writes aliases, submitted/final URL keys, append-only
  provenance, content hash, retrieval/status evidence, reviewed before/after
  audit, terminal review/job state, and the v6 enqueue/adoption result.
- The old provenance uniqueness/upsert contract was removed so later source
  observations never rewrite earlier evidence. Exact publisher replay checks
  the original actor/action/fields and returns without a second audit or
  provenance row.
- Crawler deduplication includes both the exact submitted selector identity and
  final resource identity. Two submitted selectors that share one redirect
  remain separate review jobs. Submitted and final domains are each validated.
- Submitted and final legacy bindings are reconciled independently before body
  selection. If they bind different cards, discovery produces one bounded,
  actionable conflict review carrying both identities and their evidence; it
  cannot degrade into a status-only failure.
- Replayed exact trusted observations re-enter publication, deduplicate only the
  exact same provenance observation, and still verify the existing v6 job.
  Changed retrieval/content evidence appends history; it is never rewritten.
- Issuer-crawl and legacy catalog-enrichment work is versioned by submitted and
  final resource identity, semantic product identity, sanitized source
  observation, and catalog baseline. Raw content hashes remain provenance but
  retrieval time, nonces, and footer churn do not manufacture a new review. A
  pending review may refresh only through a null-safe optimistic compare-and-set
  and appends bounded observation history. A terminal review is immutable;
  materially new identity, field, or lifecycle evidence creates a new service
  job/review unit.
- User `resolve_url` submissions also fetch and revalidate before returning a
  terminal result. The submitted resource, final resource, and semantic product
  hash form the immutable observation version; retrieval/transport timestamps
  and raw page churn do not. The request anchor remains stable and is not a
  queued per-call artifact. An identical observation returns the existing
  terminal work, a fetch failure returns the retained terminal result, and a
  corrected rejected page or repurposed resolved URL creates a new reviewable
  version without rewriting the old job, review, or provenance.

## Transactional review staging

- User discovery, issuer crawling, and catalog enrichment call one shared Edge
  helper that invokes `stage_card_catalog_identity_review(...)`; none performs
  review-insert followed by discovery-job update/link writes.
- The RPC takes the canonical review-stage advisory lock, the publication-job
  advisory lock, the job row `FOR UPDATE`, and then the review row `FOR UPDATE`.
  It owns job creation, exact status/`updated_at` CAS, bounded history refresh,
  terminal immutability, version-conflict signaling, pending review creation,
  and the final `review_required` job link in one transaction.
- Apply-time assertions prove the signature, invoker mode, service-only grant,
  and lock order. Mock databases implement the RPC result/CAS behavior instead
  of emulating the removed split Edge writes.
- The specialized lifecycle RPC remains separate because it also owns the
  chronological per-card latest-evidence/supersession contract; it is likewise
  service-only and transactional.

## Lock order and page moves

The shared order is:

1. review-stage identity advisory lock when staging review work;
2. publication-job advisory lock;
3. review staging locks the discovery job row and then review row;
4. reviewed publication takes ordered submitted/final URL advisory locks;
5. strong identity advisory lock;
6. Task 6 card/parser advisory lock;
7. catalog card row, discovery job, and review row;
8. v6 enqueue/adoption, which re-enters the same Task 6 advisory lock.

Rows are first observed without locks and then re-read/revalidated under the
canonical locks. Stale job evidence, stale review evidence, and stale terminal
state fail the transaction. Apply-time assertions verify signatures, grants,
lock namespaces/order, invoker mode, and presence of the Task 6 enqueue lane.
`observe_existing` rechecks the job status, review link, and pending-review
absence only after taking the shared job advisory and row locks. A reviewed
rename takes the old and new family advisory locks in lexical order and rechecks
the destination family before resolver/catalog mutation. Legacy page-move
backfill always records a deterministic non-null observation timestamp while
the optimistic baseline comparison remains null-aware.

For a reviewed same-card page move:

- the existing benefits-v6 row keeps its `id`, status, attempts, staging link,
  result/observation history, and `next_run_at`;
- its approved canonical URL, final hash, content hash, and derived job key are
  adopted in place;
- old URL-key and provenance rows remain queryable;
- completed, staged, quarantined, review-required, and failed-without-active-
  retry jobs are adoptable only when unleased;
- queued, processing, actively retrying failed, or leased jobs raise SQLSTATE
  `40001`, roll back the whole publication, and surface as HTTP 409
  `publication_busy`;
- exact replay is a no-op; same URL with newly reviewed content refreshes only
  the job content identity under the same terminal/unleased rule;
- the Task 6 scheduling trigger intentionally excludes source-only columns, so
  the next recurrence retains its existing clock and fetches the new URL.

## Mutable fields, lifecycle, and retention

- Only `edit_approve` changes an existing card's name, network, fees, APR, or
  canonical URL. Missing/unparseable values preserve live non-null values.
- A reviewed rename/network/page move is first bound to its explicit existing
  card under the old strong identity; old approved names become aliases.
- `mark_discontinued` and `reactivate` require actor, reason, matching stored
  suggested action, exact source observation, and a locked explicit card. The
  SQL boundary independently requires either a 410 strong-gone observation, a
  validated 200 explicit card-discontinuation statement, or a validated 200
  exact-card reappearance. They update only `is_discontinued` and write
  before/after audit.
- Successful exact-card reappearance proposes reactivation. Explicit 410
  evidence may suggest discontinuation. 404, redirect, and identity failures
  produce weaker retained review evidence and cannot authorize a lifecycle
  action. No HTTP status directly mutates acquisition state.
- Explicit current discontinuation evidence always takes precedence over a
  nominal 200 reappearance. Reactivation requires positive exact-card
  reappearance evidence and the explicit absence of discontinuation language,
  consistently across issuer crawl, recurring ingestion, and publication.
- Actively held discontinued cards continue through the Task 6 recurring
  eligibility boundary.
- Recurring benefits-v6 410 and strong explicit discontinuation observations
  upsert one exact-card lifecycle review. Later exact reappearance proposes
  reactivation; issuer crawl includes discontinued rows for this identity
  match. A 404, redirect, directory absence, missing network/tier, or debit row
  cannot authorize lifecycle publication.
- Every edit/lifecycle proposal stores the old mutable fields, acquisition
  state, canonical URL, and `updated_at` (nullable for legacy rows). Publication
  stores retrieval-time evidence when legacy `updated_at` is null, compares the
  null-aware full snapshot again under the card lock, and returns
  `stale_catalog_baseline` without mutation if another review won first.
- Strong lifecycle evidence now has a per-card chronological contract covering
  both change proposals and no-change current-state observations. Semantic
  identity excludes retrieval and transport time, exact history is
  hash-deduplicated and capped at the newest 24 entries, timestamps more than
  five minutes in the future fail closed, and older evidence cannot supersede a
  newer observation. A newer opposite-state observation rejects pending stale
  work; lifecycle approval proves its job is still the latest under the card
  lock before changing acquisition state.
- Normal user resubmission never resets a terminal review/job to pending. An
  explicit admin `retry` with a non-empty reason may reopen only the retained
  retryable review unit and appends audit history; approved/merged work remains
  immutable. Retry intentionally leaves the job in `review_required` because no
  universal producer can safely reconstruct arbitrary catalog work; the admin
  can immediately re-evaluate the retained pending review. It never requeues a
  discovering/in-flight job. Retry/reject mutation uses exact locked status and
  `updated_at` predicates, and replay equality includes actor, reason, merge
  target, action, and current state.
- `observe_existing` rejects any discovery job already connected to review work
  or marked review-required, even when the card otherwise has a strong official
  binding.
- The only reviewed publication that intentionally yields zero recurring v6
  jobs is an unheld card's approved discontinuation. That exception is assigned
  explicitly and audited; every other publication must retain or enqueue the
  exact one eligible recurring job.
- Calculator cleanup now terminalizes and audits review/job rows instead of
  deleting them. Listing reviews is read-only; cleanup requires an explicit
  admin confirmation and exact calculator classification rather than URL
  `LIKE`. Review/audit/provenance/URL/enrichment foreign keys no longer
  cascade-delete identity history; user deletion de-identifies statement jobs.
- Admin publication ignores no stored authority: `approve`, lifecycle, reject,
  retry, and merge derive immutable proposal/source fields from the locked
  review. Only `edit_approve` accepts the documented mutable catalog fields.
  Existing-card edits require their locked catalog baseline; edited new-card
  proposals require stored semantic/content evidence instead.
- Explicit discontinuation matching is card-heading scoped and retains the
  decisive excerpt. Directory absence never changes lifecycle state; a bounded
  absence review is created only after a proven complete issuer directory and a
  known issuer catalog comparison. Discovery seed selection includes issuers
  with only discontinued cards so later reappearance remains observable.
- Recursive Edge and SQL envelope checks reject credentials, fragments, and
  sensitive query keys even when URLs and key letters are percent-encoded
  through multiple layers.

## Red evidence

The first focused run established these failures before implementation:

- the shared helper import failed with `TS2307` because the central publication
  helper did not exist;
- the Task 7 migration suite had no migration (`0/9` expected contracts);
- the identity suite was `45 passed / 2 failed`: ordinary terms prose created a
  false product ambiguity, and a Mastercard candidate could bind a stored Visa
  card;
- exact functional resource coverage then failed with `TS2353` and three
  official-fetch assertions (`44 passed / 3 failed`) because only queryless
  display URLs were returned while hashes represented queryful resources;
- the retained-history admin cleanup test failed because the old contract
  deleted discovery jobs rather than terminalizing/auditing them.

A page-move mutation test also removed `review_required` from the allowed
terminal states and failed the page-move contract before restoration.

The review-hardening red run then produced the required exact failures:

- shared publication TypeScript failed with `TS2305`/`TS2322` for the missing
  lifecycle, baseline, and `observe_existing` interfaces;
- the combined discovery/crawl/migration run was **50 passed / 19 failed** for
  direct existing-card bypasses, weak identity, exact submitted/final URL
  evidence, lifecycle reviews, admin authorization, and stale baselines;
- the focused existing-card replay test returned `duplicate` instead of
  re-entering publication;
- nullable legacy baseline, weak HTTP-absence authority, rejected-review retry,
  and exact catalog lifecycle-evidence tests each failed before their bounded
  implementations were added.

The second hardening pass began from another exact red TypeScript run:

- `TS2305` proved that the shared bounded catalog-source sanitizer did not yet
  exist;
- `TS2353` proved that nullable legacy catalog baselines did not carry the
  retrieval-time fallback needed for optimistic comparison;
- the new behavioral overlays then failed on terminal review reuse, URL-pair-
  only crawler deduplication, generic aliases claiming network/tier variants,
  reactivation despite explicit discontinuation, user resubmission reopening
  terminal work, and status-only bound-URL conflict handling.

Those reds were kept as behavioral regression tests. The green implementation
adds content/resource-versioned review units, compare-and-set evidence refresh,
strict family/network/tier/type resolution, lifecycle precedence, explicit
admin retry, and independently evidenced submitted/final conflicts.

The third hardening pass began with exact focused reds:

- shared TypeScript failed with three `TS2305` errors and one missing-helper
  export for lifecycle observation actions, semantic history, reviewed-envelope
  bounds, effective network authority, and user observation versioning;
- terminal `resolve_url` still returned before fetch/version comparison;
- an active exact 200 did not record current lifecycle evidence, and a
  retrieval-time-only catalog observation created a second review unit;
- the catalog lifecycle producer failed its new central-boundary test, and the
  migration suite was **20 passed / 8 failed** for locked observation
  revalidation, dual-family rename locks, legacy timestamp fallback,
  chronological lifecycle evidence, effective network/Amex parity,
  retry/reject replay, reviewed-envelope bounds, and empty-query parity.

Those reds are now retained in the affected shared, discovery, crawler,
catalog, recurring, and migration suites. All asynchronous job claims,
terminal catches, review links, and failure writes use non-terminal/status and
version compare-and-set predicates so an admin-approved, rejected, or resolved
row cannot be reopened by a stale worker.

The fourth hardening pass started with exact failures for the remaining review
coordination and authority gaps:

- the migration suite failed five focused contracts because review creation,
  refresh, and job linkage were still split across Edge writes; admin inputs
  could override immutable proposal evidence; retry requeued an unowned producer
  lane; edit conflict checks collapsed sibling variants; and calculator cleanup
  was implicitly triggered while listing;
- the shared helper suite failed three missing exports for transactional review
  staging, semantic product envelopes, and target-scoped discontinuation
  evidence;
- issuer-crawl mocks failed 17 cases until they modeled the central staging RPC,
  its CAS result, terminal immutability, bounded history, and content versions;
- catalog enrichment failed its missing staging-RPC behavior and then one stale
  source-shape assertion, which was replaced by the stronger no-split-write
  transactional contract;
- admin tests failed listing-read-only, explicit cleanup confirmation, and
  immutable override cases;
- user URL tests exposed per-call anchor jobs, raw-content versioning, and a
  transient failure hiding a retained terminal result;
- final migration reds proved retry/reject lacked exact status/timestamp CAS,
  the staging grant was not apply-asserted, and nested SQL privacy decoding did
  not yet decode percent-encoded sensitive-key letters.

The green implementation retains all of those as behavioral or apply-time
regressions. No terminal artifact is deleted or reopened by a stale worker, and
no review/job linkage depends on an Edge multi-write sequence.

## Green verification

- `deno test --node-modules-dir=auto --allow-env --frozen` across every Edge
  test except the separately permissioned admin listener suite: **214 passed,
  0 failed**.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts`: **43 passed,
  0 failed**. The only network permission is the unchanged local test listener.
- `node --test` across every `test/supabase/*_test.js` and
  `test/supabase/*.test.mjs`: **265 passed, 0 failed**.
- `flutter test --no-pub test/supabase/card_catalog_url_identity_test.dart`:
  **2 passed, 0 failed**.
- Total unique named offline tests: **524 passed, 0 failed**.
- `deno check --node-modules-dir=auto --frozen` on all changed production
  TypeScript: passed.
- `deno fmt --check` on the complete changed TypeScript/JavaScript test surface:
  passed.
- `git diff --check`: passed.

The first Flutter invocation printed its dependency-resolution preamble; the
final authoritative rerun used `--no-pub`. No issuer site, linked/live
Supabase, production data, or application write was accessed.

## Remaining live-only gates

These are deliberately not run in Task 7:

- apply the ordered migration to real PostgreSQL and execute its transactional
  self-assertions;
- run real two-session publication/enqueue/page-move interleavings, including
  processing-lease rollback and next-recurrence reuse;
- validate actual RLS/function grants and RPC result codecs after apply;
- run the full linked integration suite and approved issuer fixtures in the
  later deployment tasks.

No Docker, local PostgreSQL/Supabase runtime, linked migration dry-run/push,
live data read/write, external issuer request, schedule change, secret change,
or production mutation was performed.
