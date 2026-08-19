# Task 5 Report — Preserve HTTP and Product-Page Lifecycle Semantics

Date: 2026-08-20

## Outcome

Task 5 now preserves issuer HTTP/source lifecycle evidence end to end without
turning a fetch result into acquisition discontinuation or benefit retirement.
The implementation adds a structured official fetch contract, a bounded retry
orchestrator, conditional-validator compatibility, redirect/DNS/content safety,
sanitized observation summaries, refresh eligibility for actively held
discontinued cards, and the carried Task 3/4 source-privacy boundary. No schema
or migration change was required.

## Red proof

The contracts were introduced and run before their implementation:

- The official-fetch Node suite failed at module load because
  `OfficialFetchError` and the structured observation/retry API did not exist.
- The focused privacy suite reported **20 passed / 2 failed** for deeply mixed
  structural encoding and secret-bearing object keys.
- The first enrichment Deno run failed type checking because the pure
  `refreshEligibleCard` contract did not exist.
- An unusable-304 regression made five requests instead of the required two;
  the focused redirect fixture also classified a carrier-grade-NAT destination
  as `redirect_rejected` instead of `private_address`.
- The actively held discontinued-card identity fixture failed because the
  discontinued target was omitted from the active issuer variant set.
- The supporting-crawl fixture marked an outstanding optional browser/PDF
  fallback complete.
- The final source-summary audit failed type checking because
  `sourceObservationReviewSummary` did not exist; this proved that a successful
  HTTP response rejected by the later card-identity gate could lose its
  dedicated source-observation summary.

All of those reds were retained as regression coverage and are green below.

## Implementation

### Official fetch and retry semantics

- Added the public `OfficialFetchError`, `OfficialFetchResult`, attempt, and
  observation contracts. Results preserve status, not-modified state, bounded
  validators, exact submitted identity transiently, transient final identity,
  and a query/userinfo/fragment-free canonical display URL.
- Added deterministic injected fetch, DNS, robots, clock, delay, parser/cache,
  and retry inputs. No test uses the external network.
- Validators are sent only for a same-parser prior observation. A reusable 304
  completes without staging; an unusable 304 performs exactly one unconditional
  fetch. Parser changes suppress conditional headers.
- First 404/soft-404 retries once; persistent 404/soft-404 and 410 require
  review; 401/403/challenge/empty shell/robots/private or unapproved destinations
  are blocked; 429 honors bounded seconds or HTTP-date `Retry-After`; 5xx,
  timeout, DNS, and network errors use bounded retry. Every attempt is retained.
- Every redirect hop is issuer-allowlisted and publicly resolved immediately
  before request. Loops, excess hops, generic application/login/index targets,
  cross-issuer targets, and private/reserved answers fail closed. The fetched
  document still passes the existing exact-card identity gate before staging.
- MIME, charset, advertised bytes, streamed/decompressed bytes, PDF inflate,
  soft-404, challenge, and empty-JavaScript-shell contracts are bounded. Raw
  response bodies are not placed in summaries or staging.

### Observation and lifecycle integration

- The batch now uses the structured observation fetcher and persists only a
  bounded source summary in existing JSON: terminal disposition/status,
  sanitized URLs, hashes, validators, parser version, attempts, completeness,
  and review reason. Identity review preserves the prior HTTP attempts while
  marking the source incomplete.
- Compatible 304 observations reuse the prior source-manifest/canonical-benefit
  hashes, create no staging row, and schedule normally. Raw-only source changes
  with the same canonical benefit hash likewise avoid new staging.
- Fetch/retry outcomes never mutate `card_catalog.is_discontinued`, benefits,
  or mappings. Failed, blocked, and review-required outcomes remain incomplete
  evidence.
- The pure refresh contract keeps an acquisition-discontinued card eligible
  when an active `user_cards` row references it. The queue and exact identity
  loader honor that contract; unheld discontinued inventory remains excluded.
- Primary and supporting retry attempts are retained together. Outstanding
  required or optional browser/PDF fallback makes the crawl incomplete.

### Carried privacy prerequisite

- Shared bounded probing handles absolute, protocol-relative, relative,
  bare-host, entity-encoded, percent-encoded, repeated/mixed encoded,
  credential/userinfo, query, and fragment variants across extractor evidence,
  current-row reconstruction, staging, observations, and admin DTO keys/values.
- If the bounded probe budget is exhausted while a recoverable URL/credential
  candidate remains, the value fails closed to a bounded marker. Ordinary
  percent, math, and email prose remains byte-for-byte unchanged.
- Sanitized anchor labels and queryless host/path displays are used for
  classification. Raw query identity survives only transiently to derive the
  opaque source digest; token-only URL changes do not affect canonical benefit
  identifiers.

## Changed files

- `supabase/functions/_shared/official_issuer_fetch.ts`
- `supabase/functions/_shared/benefit_source_privacy.ts`
- `supabase/functions/_shared/issuer_card_crawl.ts`
- `supabase/functions/_shared/issuer_card_crawl_test.ts`
- `supabase/functions/benefit-enrichment-batch/index.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`
- `supabase/functions/benefit-enrichment-batch/supporting_documents.ts`
- `supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts`
- `supabase/functions/benefit-enrichment-batch/crawl_policy.ts`
- `supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts`
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts` was exercised
  unchanged as the integrated recursive-privacy regression gate.
- `test/supabase/official_issuer_fetch_rules.test.mjs`
- `test/supabase/benefit_enrichment_rules.test.mjs`
- `test/supabase/issuer_card_crawl_rules.test.mjs`

## Green verification

- `node --test test/supabase/official_issuer_fetch_rules.test.mjs` — **28
  passed, 0 failed**.
- `deno test --node-modules-dir=auto --allow-env --frozen
  supabase/functions/benefit-enrichment-batch/index_test.ts
  supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts` —
  **85 passed, 0 failed**.
- `deno test --node-modules-dir=auto --allow-env --frozen
  supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts` — **35
  passed, 0 failed**.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs
  test/supabase/issuer_card_crawl_rules.test.mjs` — **46 passed, 0 failed**.
- `deno test supabase/functions/_shared/issuer_card_crawl_test.ts` — **1 passed,
  0 failed**.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — **40 passed,
  0 failed**. The only granted network capability is the unchanged unit test's
  loopback listener.
- Total named behavioral/static tests: **235 passed, 0 failed**.
- `deno check` on all changed TypeScript source files — passed.
- `deno fmt --check` on all changed TypeScript/test files — passed.
- `git diff --check` — passed.

## Scope and remaining gate

No migration was added. Live applied: **no**.

No Docker, local database/PostgreSQL, local or linked Supabase command,
production data, external network request, migration apply/push/dry-run, or live
write was used. All fetch/DNS/clock/delay/robots behavior was injected.

The still-pending integration gate is the ordered Task 2–5 migration/application
chain and real database-boundary verification against an explicitly authorized
environment. This task's source-observation JSON uses existing columns and is
offline-verified; it does not claim live PostgreSQL execution or live issuer-site
behavior.

## Review fix round 1/5 — 2026-08-20

### Red proof

The 14 review findings were reproduced against `b6ce384` before their fixes:

- The whole production-caller `deno check` reported **8 errors**: discovery and
  catalog callers consumed optional body/text/hash fields without narrowing a
  possible 304 result.
- The expanded official-fetch suite initially reported **28 passed / 9 failed**
  for mapped/reserved DNS, query exposure/filtering, reusable validator
  evidence, 304 content evidence, absolute deadlines, production robots,
  checkpoint detection, invalid `Retry-After`, and BOM decoding. A later focused
  robots-cache red proved two `/robots.txt` requests across one logical retry.
- Supporting collection reported **20 passed / 2 failed** when a
  Privilege→Regalia redirect completed and a test fixture still used a non-SHA
  content hash. The retained behavior test separately covers same-card pass,
  different-card failure, and generic redirect failure.
- Focused source-privacy testing failed because redacting one encoded credential
  candidate decoded unrelated `20%25`/`3%3A` prose. The unchanged admin suite
  then exposed two mixed entity/percent IPv6 userinfo regressions during the
  candidate-local refactor (**38 passed / 2 failed**, then **39 / 1**).
- Discovery and catalog tests failed first for missing recursive evidence
  sanitization, query-bearing classification URLs, encoded heading identity,
  unsanitized current-row conflicts, and the missing exact catalog-card identity
  contract.
- Crawl-policy and batch tests failed type checking before bounded nested retry
  history and prior content-hash cache evidence existed.

### Fixes

- Added an explicit fresh-body narrowing boundary and applied it to every
  official-fetch production caller. Unexpected/not-reusable 304 responses can
  no longer supply invented empty bodies or hashes; same-parser reusable 304
  results carry the prior SHA-256 content evidence through source attempts and
  top-level/nested completeness.
- Replaced address deny snippets with a tested global-unicast policy for IPv4,
  IPv6, and decimal/hex IPv4-mapped IPv6. Loopback, private, link-local, CGNAT,
  reserved/documentation, benchmark, multicast, and unspecified answers are
  rejected immediately before every target and redirect request.
- Public result, catalog, staging, classification, and provenance URLs are HTTPS
  query/userinfo/fragment-free displays. Exact submitted identity exists only
  transiently to derive a SHA-256 digest. Sensitive/tracking query keys are
  always dropped; non-sensitive query keys are sent only through an explicit
  allowlist or the helper used by already-approved stored catalog resources.
- Wired bounded same-host robots evaluation into every production caller. One
  deterministic named-agent parse is cached per host across an observation's
  retries. A missing 404 permits crawling; transport, malformed, redirected,
  oversized, or explicit disallow outcomes fail closed without requesting the
  target.
- Propagated absolute deadlines into primary observations, supporting fetches,
  and issuer crawl requests. Deadline checks occur before delay, robots, DNS,
  redirects, retries, and target requests; sleeps are capped to remaining time.
- Bound supporting documents to expected card labels/path metadata after every
  response. Exact curated SBI metadata remains usable only when the final URL is
  unchanged. Issuer discovery rejects same-host redirects whose requested and
  final product identities diverge; catalog normalization verifies page content
  against the target catalog card before any update/staging.
- Applied shared recursive privacy handling to discovery excerpts, crawler
  evidence, catalog field evidence/conflicts, keys, nested values, headings, and
  persistable URLs. Structural decoding now probes only candidate substrings, so
  unrelated percent/math/email/benefit prose remains byte-for-byte unchanged
  while deep mixed credentials fail closed.
- Compacted logical sources retain a bounded status/error/timestamp retry
  sequence. History overflow is explicit and incomplete; hashes cover the
  retained history. Challenge/soft-404 detection is page-checkpoint scoped,
  invalid/missing 429 delays fall back exponentially, and UTF-8/UTF-16LE/UTF-16BE
  BOMs are honored when charset is absent.

No HTTP, redirect, retry, robots, identity, or content outcome updates
acquisition discontinuation, benefits, or mappings.

### Green verification

- `node --test test/supabase/official_issuer_fetch_rules.test.mjs` — **38
  passed, 0 failed**.
- `deno test --node-modules-dir=auto --allow-env --frozen
  supabase/functions/benefit-enrichment-batch/index_test.ts
  supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts
  supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts` — **124
  passed, 0 failed**.
- `node --test test/supabase/card_discovery_rules.test.mjs
  test/supabase/issuer_card_discovery_rules.test.mjs
  test/supabase/issuer_card_crawl_rules.test.mjs
  test/supabase/card_catalog_enrichment_rules.test.mjs` — **63 passed, 0
  failed**.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs
  test/supabase/issuer_card_crawl_rules.test.mjs` — **49 passed, 0 failed**;
  the 25 issuer-crawl tests overlap the preceding caller gate.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — **40 passed,
  0 failed** with only the unchanged loopback-listener permission.
- `deno test supabase/functions/_shared/issuer_card_crawl_test.ts
  supabase/functions/catalog-enrichment/index_test.ts` — **4 passed, 0
  failed**.
- Total unique named behavioral/static tests: **293 passed, 0 failed**.
- Whole production caller `deno check --node-modules-dir=auto --frozen` for
  card discovery, catalog enrichment, issuer crawl, supporting collection, and
  benefit batch — passed.
- `deno check` on all 14 affected TypeScript source/test files — passed.
- `deno fmt --check` on all 14 affected TypeScript source/test files — passed.
- `git diff --check` — passed.

### Scope and remaining gate

Files changed in this round: shared official fetch, source privacy, card
discovery, catalog normalization, issuer crawl, crawl policy, benefit batch,
supporting collection, the card-discovery/catalog-enrichment production callers,
and their focused tests. No schema or migration changed.

Live applied: **no**. No Docker, local database/PostgreSQL, local or linked
Supabase command, production data, external network request, migration command,
or live write was used. The ordered Task 2–5 database/application verification
and explicitly authorized live issuer behavior remain the unresolved integration
gate.
