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

## Review fix round 2/5 — 2026-08-20

### Red proof

The eight second-round findings were reproduced against `c0c7d43` before
production changes:

- Official-fetch rules reported **38 passed / 7 failed**. The reds proved that a
  White Reserve validator was forwarded to a redirected League Platinum
  resource, robots used prefix-only matching and accepted invalid 200 HTML,
  `3fff::/20` was treated as global, unknown queries were silently changed,
  retry delay crossed an absolute deadline, and zero backoff terminated instead
  of retrying.
- Supporting/crawl/batch rules reported **123 passed / 5 failed**, plus four
  compile-time failures for missing prior submitted/final/card identity fields.
  The behavior reds covered nested/curated identity shortcuts, missing explicit
  functional-query approval, recompaction erasing `[503,503,200]`, and nested
  timestamps changing manifest evidence.
- Discovery/catalog/issuer rules reported **53 passed / 4 failed** for a Regalia
  body returned at a Privilege URL, a delay that slept beyond the remaining
  budget, missing query-key derivation, and absent discovery/catalog invocation
  deadlines.

### Fixes

- Conditional validators and 304 reuse now require the prior parser, reusable
  extraction, source content and canonical-benefit hashes, canonical submitted
  digest, validated queryless final resource, exact final-resource digest, and
  successful card identity. Validators are calculated per hop, so a permanent
  redirect can reuse the same final resource while a changed redirect target is
  fetched unconditionally and revalidated.
- Robots evaluation now selects the named user-agent group with `*` fallback,
  implements `Allow`/`Disallow`, `*`, terminal `$`, normalized percent/path
  matching, longest specificity, and Allow tie precedence. Robots responses are
  bounded by bytes, lines, line length, UTF-8 text MIME, and grammar; invalid
  200/HTML becomes `robots_invalid` review evidence. Only a real 404 permits a
  missing policy; transport and other status failures remain documented
  fail-closed outcomes.
- Address validation now parses IPv4 and IPv6 into BigInt values and applies
  exact CIDRs, including mapped IPv4, CGNAT, documentation, benchmark,
  multicast, unspecified, `2001:db8::/32`, and `3fff::/20`. Adjacent global
  ranges, `192.0.1.1`, the globally reachable `192.0.0.9/.10` exceptions, and
  `64:ff9b::/96` remain usable.
- Query-dependent resources are never silently rewritten. Only named functional
  keys from the shared safe policy and the explicit caller-approved stored/link
  resource are requested. Unknown and sensitive keys fail closed; exact values
  remain transient for request/source digests while every display/provenance URL
  remains queryless.
- Supporting sources no longer pass through same-path or curated-URL shortcuts.
  Visible HTML or extracted PDF text must prove the expected card identity;
  opaque documents remain required but incomplete. Issuer discovery also binds
  the requested product tokens to parsed response identity, while catalog
  enrichment retains its exact target-card gate.
- The fetch controller uses the smaller of its timeout and remaining invocation
  budget. Deadline checks surround robots, DNS, hops, body reads, retry delays,
  and requests. An intended delay larger than the remaining budget is not
  started; valid zero-second retries remain immediate and bounded. Discovery
  and catalog callers now propagate one invocation deadline.
- Attempt compaction now flattens existing bounded histories, avoids duplicating
  the terminal entry, retains overflow as incomplete, and is idempotent through
  `buildCrawlObservation`. Manifest hashing removes timestamps recursively while
  preserving ordered status, code, and HTTP semantics.

No fetch, redirect, 304, robots, identity, query, timeout, or compaction outcome
mutates acquisition discontinuation, benefits, or mappings.

### Green verification

- `node --test test/supabase/official_issuer_fetch_rules.test.mjs` — **45
  passed, 0 failed**.
- `deno test --node-modules-dir=auto --allow-env --frozen` for benefit batch,
  supporting documents, and crawl policy — **128 passed, 0 failed**.
- `node --test` for card discovery, issuer-card discovery, issuer crawl,
  catalog enrichment, and benefit-enrichment rules — **91 passed, 0 failed**.
- Direct issuer-crawl and catalog caller Deno tests — **4 passed, 0 failed**.
- Admin privacy/integration regression gate — **40 passed, 0 failed**, with only
  its unchanged loopback listener permission.
- Total unique named behavioral/static tests: **308 passed, 0 failed**.
- Whole official-fetch production-caller `deno check` — passed.
- `deno fmt --check` on all 10 affected TypeScript source/test files — passed.
- `git diff --check` — passed.

### Scope and remaining gate

This round changes only Task 5 shared fetch/crawl policy, benefit batch and
supporting collection, discovery/catalog production callers, and their focused
tests. No schema or migration changed.

Live applied: **no**. No Docker, local database/PostgreSQL, local or linked
Supabase command, production data, external network request, migration command,
or live write was used. The ordered Task 2–5 database/application verification
and explicitly authorized live issuer behavior remain the unresolved integration
gate.

## Review fix round 3/5 — 2026-08-20

### Red proof

The five third-round findings were reproduced against `941ffaf` before their
production changes:

- Official-fetch and card-discovery rules reported **69 passed / 3 failed**.
  The exact reds showed conflicting title/H1 identities being accepted,
  approved duplicate queries being reordered, and two separate same-crawl
  fetches requesting robots twice.
- Crawl-policy and supporting-document rules reported **62 passed / 2 failed**.
  An attempted optional `identity_mismatch` still allowed complete removal
  evidence, and a supporting page with conflicting strong card labels completed.
- A focused logical-source regression then reported **0 passed / 1 failed**,
  proving that different approved query-key orders collapsed to one digest.

### Fixes

- Optional as well as required fetched identity failures now make the crawl
  incomplete with an explicit `identity_mismatch` or `identity_ambiguous`
  reason. A later successful attempt for the same logical source replaces the
  failure; opaque PDFs without identity remain incomplete.
- One bounded deterministic identity assessment now collects and reconciles
  title, H1/H2, social metadata, JSON-LD name, visible text, and extracted PDF
  candidates. Discovery, issuer crawl, primary enrichment, supporting documents,
  and catalog verification consume that shared decision. Conflicting strong
  candidates fail closed; exact strong aliases and network variants agree; weak
  collision aliases such as `Gold` cannot prove a card by themselves; ordinary
  partner prose is not promoted to a card identity.
- Approved functional queries retain original parameter ordering, duplicates,
  and encoded values for the request and opaque source identity. URLs are capped
  at 2,048 characters, query parameters at eight, keys at 64 characters, and
  values at 512 characters. Unknown, sensitive, oversized, and redirect-added
  keys fail closed, while persisted display URLs remain queryless. Every card
  discovery fetch path now derives its explicit stored-resource key allowlist.
- Robots policy is cached through an opaque per-invocation token with a
  five-minute TTL, 16-entry bound, and scheme/host/port/user-agent key. Primary
  and supporting batch work, issuer sitemap/candidate discovery, card discovery,
  and catalog enrichment pass one crawl-scoped cache. Same-host retries and
  resources reuse one policy; different hosts and invocations remain isolated.

The round does not alter 304 binding, address policy, robots matching, absolute
deadlines, retry compaction, privacy boundaries, acquisition discontinuation,
benefits, or mappings.

### Green verification

- Official-fetch rules — **47 passed, 0 failed**.
- Benefit batch, supporting-document, and crawl-policy rules — **131 passed, 0
  failed**.
- Card discovery, issuer discovery/crawl, catalog, and benefit rules — **92
  passed, 0 failed**.
- Direct issuer-crawl/catalog Deno callers — **4 passed, 0 failed**.
- Admin privacy/integration regression gate — **40 passed, 0 failed**, with only
  its unchanged loopback listener permission.
- Total unique behavioral/static tests: **314 passed, 0 failed**.
- Whole official-fetch production-caller `deno check` — passed.
- All 10 affected TypeScript source/test checks and `deno fmt --check` — passed.
- `git diff --check` — passed.

### Scope and remaining gate

This round changes only Task 5 shared identity/fetch/crawl policy, benefit batch
and supporting collection, discovery/catalog production callers, their focused
tests, and this report. No schema or migration changed.

Live applied: **no**. No Docker, local database/PostgreSQL, local or linked
Supabase command, production data, external network request, migration command,
or live write was used. The ordered Task 2–5 database/application verification
and explicitly authorized live issuer behavior remain the unresolved integration
gate.

## Review fix round 4/5 — 2026-08-20

### Red proof

Nine exact failure assertions were reproduced against `5398b01` before their
corresponding production changes:

- Card identity rules reported **25 passed / 2 failed**: conflicting Visa
  Infinite/Mastercard World headings were accepted, while ordinary Primary,
  Supplementary, and partner-card terms prevented a valid target match.
- Supporting collection reported **25 passed / 1 failed** and issuer crawl
  reported **27 passed / 1 failed** because both paths sorted duplicate query
  values and keys before the fetch boundary.
- Focused follow-up reds proved that URL-hash catalog candidates could resolve
  without fetched-body agreement, a crawler URL hash could select the wrong
  catalog card, unknown query resources discovered through an index vanished
  instead of being quarantined, a valid explicit network alias failed the
  automatic gate, and the reconciled result discarded its stronger network
  signal.

### Fixes

- A shared request canonicalization path now normalizes only the HTTPS
  origin/path, drops tracking parameters, validates the bounded explicit safe
  functional-key policy, and retains original approved query ordering,
  duplicates, and encoded value bytes. Supporting queues and issuer sitemap or
  index discovery use that request identity before deduplication; identical
  requests collapse, distinct encoded/query-order resources do not. Unknown or
  sensitive resources are quarantined without fetching a rewritten URL.
- Query-bearing submitted and final resources remain transient and are bound by
  the fetcher's opaque SHA-256 identities. Discovery lookup and new provenance
  use `sourceIdentityHash` and `finalResourceIdentityHash`, while display,
  staging, catalog, and provenance URLs stay queryless. Legacy queryless hashes
  are compatibility candidates only: fetched content must prove the catalog
  card, and a mismatched legacy key cannot block a new exact query resource.
- Neither submitted URL resolution nor issuer-crawler persistence trusts a URL
  hash alone. Hash matches load the catalog name and aliases, reconcile them
  against the fetched body, and resolve only one exact identity; mismatches and
  ambiguity fail closed. Gold and Platinum query variants therefore retain
  separate opaque resource identities and are selected by their bodies.
- Shared identity reconciliation now treats explicit Visa, Mastercard, RuPay,
  and Amex families and tiers as strong variant signals. Conflicting strong
  networks are ambiguous, compatible generic/specific signals agree, and the
  strongest unambiguous signal is retained. The automatic catalog gate treats
  an explicit network spelling as an alias of the same product without
  collapsing different product names.
- Untargeted discovery no longer promotes arbitrary body phrases ending in
  `Card` into products. Target validation uses bounded exact expected phrases
  plus conservative named-card conflict evidence, ignores relationship labels
  such as Primary/Supplementary/add-on/companion/partner, accepts opaque-text
  target labels, and still rejects a genuinely different named product.

No fetch, query, redirect, identity, or hash outcome changes acquisition
discontinuation, benefit state, or mappings.

### Green verification

- Official-fetch rules — **47 passed, 0 failed**.
- Benefit batch, supporting-document, and crawl-policy rules — **132 passed, 0
  failed**.
- Card discovery, issuer discovery/crawl, catalog, and benefit rules — **98
  passed, 0 failed**.
- Direct issuer-crawl/catalog Deno callers — **4 passed, 0 failed**.
- Admin privacy/integration regression gate — **40 passed, 0 failed**, with only
  its unchanged loopback-listener permission.
- Total unique behavioral/static tests: **321 passed, 0 failed**.
- Whole official-fetch production-caller `deno check` — passed.
- All affected TypeScript source/test checks and `deno fmt --check` — passed.
- `git diff --check` — passed.

### Scope and remaining gate

This round changes only Task 5 shared fetch/request and identity policy,
supporting collection, issuer crawl, card-discovery production persistence, and
their focused tests. No schema or migration changed.

Live applied: **no**. No Docker, local database/PostgreSQL, local or linked
Supabase command, production data, external network request, migration command,
or live write was used. The ordered Task 2–5 database/application verification
and explicitly authorized live issuer behavior remain the unresolved integration
gate.

## Review fix round 5/5 — 2026-08-20

### Red proof

The final six findings were reproduced against `67a8fdb` before their
corresponding production changes:

- Crawl-policy and supporting-document rules reported **66 passed / 4 failed**.
  Required and optional rejected query candidates disappeared or remained
  removal-complete, supporting attempts omitted final-resource identities, and
  compaction erased redirect identity transitions.
- Focused identity rules reported two exact failures for a generic label
  overriding a stored strong network/tier variant and case-sensitive body-only
  evidence. Follow-up reds covered a generic Visa label overriding Visa
  Infinite and malformed percent-encoded query selectors reaching the fetcher.
- Issuer classification/persistence rules reproduced one missing opaque-hash
  classification, one Gold/Platinum query variant dedupe collision, and one
  conflicting same-hash database binding.
- Catalog binding rules reproduced two missing behaviors: submitted and final
  resource hashes were not queried independently, and non-unique/body-mismatched
  bindings did not fail closed before resolution.

### Fixes

- Supporting-link discovery now returns policy-rejected candidates with bounded
  anchor-derived role and reason instead of dropping them. Required and selected
  optional query failures are retained as attempts and block removal evidence.
  Entity-encoded approved selectors retain their exact query bytes; unknown,
  sensitive, malformed UTF-8/percent, oversized, and invalid candidates fail
  closed without persisting query values.
- Exact-card reconciliation now treats the stored strongest network and tier as
  mandatory. A generic label cannot override missing or different Visa,
  Mastercard, RuPay, Amex, or co-brand variants. Tier-named families such as
  American Express Platinum remain valid products. Bounded HTML/PDF body
  candidates are case-insensitive, while Primary, Supplementary, add-on,
  companion, and partner mentions remain contextual rather than competing card
  identities.
- Submitted and final opaque resource hashes are looked up independently. A
  non-unique hash or hashes bound to different card IDs produces
  `identity_conflict` before body resolution or persistence. Every surviving
  URL-hash match is still reconciled against the fetched card body. The legacy
  resolver is invoked once per resource identity with the same hash in both
  compatibility arguments; different submitted/final keys are never passed as
  one first-match set. Resolver/unique-race errors fail closed.
- Issuer page classifications now carry validated bounded submitted/final
  resource identities through sanitization, persistence evidence, and review
  dedupe. Query-selected Gold and Platinum resources therefore remain distinct
  even though their public display URL is queryless. Invalid or raw query
  identities never enter review evidence.
- `SourceAttempt` and bounded retry history now preserve the fetched
  `finalResourceIdentityHash` for primary and supporting successes and failures.
  Retries remain grouped by submitted identity, but a transition between final
  resources is visible and makes the observation incomplete with
  `final_resource_identity_conflict`. Manifest hashing includes the ordered
  opaque transition while continuing to remove timestamps recursively.

No HTTP, query, redirect, identity, hash, or attempt result changes acquisition
discontinuation, benefit state, or mappings.

### Green verification

- Official-fetch rules — **47 passed, 0 failed**.
- Benefit batch, supporting-document, and crawl-policy rules — **136 passed, 0
  failed**.
- Card discovery, issuer discovery/crawl, catalog, and benefit rules — **104
  passed, 0 failed**.
- Direct issuer-crawl/catalog Deno callers — **5 passed, 0 failed**.
- Admin privacy/integration regression gate — **40 passed, 0 failed**, with only
  its unchanged loopback-listener permission.
- Total unique behavioral/static tests: **332 passed, 0 failed**.
- Whole official-fetch production-caller and all changed TypeScript `deno check`
  gates — passed.
- `deno fmt --check` on all changed TypeScript source/test files — passed.
- `git diff --check` — passed.

### Changed files and remaining gate

This final round changes shared official-fetch query validation, card identity
and issuer classification, supporting/crawl evidence, benefit-batch carriage,
card-discovery resource binding, focused tests, and this report. No schema or
migration changed; existing opaque hash, provenance JSON, job evidence, and
result-summary fields are sufficient.

Live applied: **no**. No Docker, local database/PostgreSQL, local or linked
Supabase command, production data, external network request, migration command,
or live write was used. The ordered Task 2–5 database/application verification
and explicitly authorized live issuer behavior remain the unresolved integration
gate.
