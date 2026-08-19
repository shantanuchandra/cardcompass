# Task 7 Report — Unified Reviewed Card Identity Publication

## Outcome

Task 7 is implemented as one reviewed, transactional catalog-identity
publication boundary. Statement/user discovery, issuer crawler discovery,
catalog enrichment, lifecycle observations, and legacy manual catalog entry no
longer write canonical card rows from Edge code. Reviewed publication now owns
strong identity resolution, URL keys, append-only provenance, audit, lifecycle
state, and the exactly-one benefits-v6 recurring job outcome.

Live applied: **no**.

## Files changed

Created:

- `supabase/migrations/20260819231435_publish_reviewed_card_identity.sql`
- `supabase/functions/_shared/catalog_identity_publication.ts`
- `supabase/functions/_shared/catalog_identity_publication_test.ts`
- `test/supabase/publish_reviewed_card_identity_migration_test.js`
- this report

Modified:

- `supabase/functions/_shared/card_discovery.ts`
- `supabase/functions/_shared/issuer_card_crawl.ts`
- `supabase/functions/_shared/issuer_card_crawl_test.ts`
- `supabase/functions/_shared/official_issuer_fetch.ts`
- `supabase/functions/admin-catalog-entry/index.ts`
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
- `supabase/functions/card-discovery/index.ts`
- `supabase/functions/catalog-enrichment/index.ts`
- `test/supabase/card_catalog_enrichment_rules.test.mjs`
- `test/supabase/card_discovery_rules.test.mjs`
- `test/supabase/issuer_card_discovery_rules.test.mjs`
- `test/supabase/official_issuer_fetch_rules.test.mjs`

No earlier migration was modified.

## Migration

- File: `20260819231435_publish_reviewed_card_identity.sql`
- SHA-256: `7dfdd0603061d45663016d5e8c97131a7298b28bd30cccc91ba01475fe2f862a`
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
  retained-history cleanup boundary
  `terminalize_calculator_review_rows(uuid,integer)`.
- Resolver, publisher, wrapper, and internal helpers are `SECURITY INVOKER`,
  have fixed search paths, are revoked from public application roles, and are
  executable only by `service_role` where needed.
- The legacy service-role grant on `create_or_get_card_catalog(...)` is revoked,
  removing the remaining alternate canonical writer without changing the v5
  benefit rollback lane.
- `resolve_verified` accepts only independently verified statement jobs with no
  actor/review item. Crawler and user-request paths require a pending review and
  authenticated admin actor.

## Identity, URL, and artifact decisions

- Submitted and final hashes are reconciled independently across URL keys and
  provenance. Multiple bindings or two different bound cards fail with
  `conflicting_url_identity` before durable mutation.
- Bound URLs are revalidated against issuer, normalized product/tier, and
  payment network. Weak standalone aliases such as Visa, Gold, Platinum,
  Infinite, Signature, and World cannot resolve or create a product.
- Production loaders now carry stored network evidence and fail closed on
  cross-network or ambiguous hash/body matches. Ordinary fees/terms/benefits
  prose is excluded from competing title identity.
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

## Lock order and page moves

The shared order is:

1. publication-job advisory lock;
2. ordered submitted/final URL advisory locks;
3. strong identity advisory lock;
4. Task 6 card/parser advisory lock;
5. catalog card row;
6. discovery job and review row;
7. v6 enqueue/adoption, which re-enters the same Task 6 advisory lock.

Rows are first observed without locks and then re-read/revalidated under the
canonical locks. Stale job evidence, stale review evidence, and stale terminal
state fail the transaction. Apply-time assertions verify signatures, grants,
lock namespaces/order, invoker mode, and presence of the Task 6 enqueue lane.

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
  suggested action, exact source observation, and a locked explicit card. They
  update only `is_discontinued` and write before/after audit.
- Successful exact-card reappearance proposes reactivation. Explicit 410
  evidence may suggest discontinuation. 404, redirect, and identity failures
  produce weaker retained review evidence and cannot authorize a lifecycle
  action. No HTTP status directly mutates acquisition state.
- Actively held discontinued cards continue through the Task 6 recurring
  eligibility boundary.
- Calculator cleanup now terminalizes and audits review/job rows instead of
  deleting them. Review/audit/provenance/URL/enrichment foreign keys no longer
  cascade-delete identity history; user deletion de-identifies statement jobs.

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

## Green verification

- `deno test --node-modules-dir=auto --allow-env --frozen` across every Edge
  test except the separately permissioned admin listener suite: **193 passed,
  0 failed**.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts`: **41 passed,
  0 failed**. The only network permission is the unchanged local test listener.
- `node --test` across every `test/supabase/*_test.js` and
  `test/supabase/*.test.mjs`: **226 passed, 0 failed**.
- `flutter test --no-pub test/supabase/card_catalog_url_identity_test.dart`:
  **2 passed, 0 failed**.
- Total unique named offline tests: **462 passed, 0 failed**.
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
