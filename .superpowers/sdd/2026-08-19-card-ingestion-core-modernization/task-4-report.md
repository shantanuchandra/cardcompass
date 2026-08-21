# Task 4 implementation report

## Outcome

Implemented the schema-preserving v2 `approve_card_benefit_enrichment(uuid, uuid, jsonb)` transaction and the corresponding admin/card-diff boundaries. Publication now derives canonical SHA-256 card-scoped identity from the locked staging row's actual `card_id`, inserts immutable benefit versions, retires only an exact card+benefit mapping, and appends decisions/evidence atomically. No business table or column was added.

## Red proof

Before implementation:

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js`
  - 0 passed, 5 failed because no v2 migration existed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
  - type checking failed on the missing `sanitizeAdminDto` export and missing locked-card argument to v6 approval validation.

The migration was then generated locally with `supabase migration new review_card_benefit_enrichment_v2`; this created `20260819163046_review_card_benefit_enrichment_v2.sql` without contacting or mutating a Supabase project.

## Implemented contracts

- Locks the official staging row before status, parser, proposal, identity, or eligibility validation.
- Accepts only rollback-window `benefits-v5` and current `benefits-v6`; both publish through one server-canonical card-scoped path.
- Recomputes canonical terms, condition hash, and `card-benefit-v2:<locked-card-id>:<sha256>` key; v6 staged/client identity mismatch fails closed.
- Binds decisions by the locked proposal index/key, rejects duplicate/unknown/malformed proposal selections, and allows edits only to the explicit flat commercial field allowlist.
- Inserts benefit versions with `ON CONFLICT (dedupe_key) DO NOTHING`; it never updates the old benefit row or global `benefits.is_active`.
- Derives replacement mapping UUIDs from the locked staged diff and scopes every lifecycle update by both `card_id` and `benefit_id`, leaving another card's shared legacy row/mapping unchanged.
- Maps future replacements immediately, schedules only the old mapping at the future UTC `valid_from` boundary, and retires immediate/retroactive replacements at review time.
- Requires locked Task 3 `retirementEligible`/`retirementReason` evidence before a reviewed retirement.
- Serializes concurrent review on the staging row, returns an identical result for an identical payload replay, rejects other completed reviews, and rejects superseded staging.
- Appends bounded server-side source evidence and reviewed decisions without deleting history; completes the linked job and sets the temporary 30-day `next_run_at`.
- Keeps `SECURITY INVOKER`, fixed search path, and service-role-only execute grants with no `auth.role()` authorization.
- Recursively redacts URL credentials/query/fragment data in admin DTO scalar, list, nested value, and object-key positions while retaining raw locked evidence only on the server.
- Carries the existing live `benefits.benefit_id` UUID as `liveBenefitId` through current-benefit reconstruction and staged diffs.

## Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 5 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 21 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/benefit-enrichment-batch/index_test.ts` — 56 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed.
- Total named behavioral/static tests: 111 passed, 0 failed.
- `deno check --node-modules-dir=auto` on all four changed TypeScript/test files — passed.
- `deno fmt --check` on all four changed TypeScript/test files — passed.
- `git diff --check` — passed.

No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, repair, workflow, or secret operation was used.

## Files

- `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`
- `test/supabase/review_card_benefit_enrichment_v2_migration_test.js`
- `supabase/functions/admin-catalog-entry/benefit_admin.ts`
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
- `supabase/functions/_shared/benefit_enrichment.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`

Migration SHA-256 before commit: `05b9837904aecc8fd082ae3da251bfe15f82f4856f8968cdcf19c8ddde2ce446`.

## Live gate

Live applied: **no**.

The exact-project read-only audit and ordered Task 2/3/4 migration parse/apply/lint/integration gates remain queued. The linked Supabase CLI control plane previously stalled at `Initialising login role...`; this task intentionally performed no live or network operation.

## Review fix round 1/5 — 2026-08-19

### Red proof

The review contracts were first exercised against `096ae7afa8bb00b7dcecaae74670b53cddf7d0f0`:

- The shared contract suite failed type checking because `canonicalBenefitCategory` did not exist; reward extraction still emitted `rewards`, which could not resolve to the live `POINTS` category.
- The admin suite failed on the missing pure retirement validator/privacy cases. Subsequent focused reds proved that an otherwise valid history which omitted the locked current observation was accepted, and that approve+approve / approve+reject identities did not consistently return `duplicate_benefit_decision`.
- The migration suite initially reported 3 passed / 5 failed against the old general-purpose SQL normalizer and boolean-only retirement path. After narrowing the contracts, it deliberately reported 7 passed / 1 failed until exact reject binding and migration-time publication/retirement assertions were added.
- The existing Node golden suite reported 28 passed / 1 failed after the intentional reward alias correction, proving the v6 reward condition/key changed from `rewards` to canonical `points`; the golden fixture was updated while the explicit v5 rollback golden stayed unchanged.

### Fixes

- Added one shared TS category alias contract (`reward`, `rewards`, `point`, `points` → `points`) used by extraction, canonical hashing, admin publication, and the authoritative active DB category lookup (`POINTS`). Other categories remain unchanged.
- Replaced the divergent SQL commercial normalizer with a structural canonical JSON serializer and a server-created publication envelope. The Edge handler builds the envelope from raw locked staging; SQL verifies its exact JSONB proposal binding, recomputes staged/condition SHA-256 values and the card-scoped key with the locked `card_id`, validates bounded shapes/dates/category, and ignores client/staged IDs as publication authority.
- Recomputed retirement eligibility from the locked complete crawl, exact absent card-scoped/legacy identity, a bounded 1–24 timestamp history containing the current observation, two complete observations at least seven days apart, or an official past end date. Malformed evidence and staged eligibility/reason drift fail closed in both pure TS and SQL.
- Completed recursive admin privacy coverage for protocol-relative, bare-host, relative query/fragment, userinfo, percent-encoded, and entity-encoded secret-bearing forms in values and object keys while preserving ordinary partner text. Raw staging remains internal to the Edge→service-role RPC binding only.
- Scoped linked job completion by staging ID + locked card + parser + staged status, intentionally completing every matching same-card reused-staging job, with a first-review row-count assertion.
- Added stable duplicate guards before any mutation for approve, edit, reject, keep, and retire, including cross-action identities and direct-RPC reject proposal/current binding.
- Rejected title/description-only edits as `non_material_edit`; preserved explicit null date clears, rejected invalid ranges, carried display changes on material immutable versions, and made a pre-existing condition row require identical display/content before replay selection so accepted display changes cannot be silently discarded.
- Added pure canonical/decision/retirement behavior tests and migration apply-time assertions for canonical digest/card-key recomputation, cross-card rejection, live `POINTS` lookup, incomplete/mismatched/short/missing-current retirement evidence, exact threshold eligibility, reason consistency, and explicit termination. The SQL assertion blocks do not mutate business rows.

### Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 8 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 26 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/benefit-enrichment-batch/index_test.ts` — 56 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/_shared/benefit_contract_test.ts` — 7 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed.
- Total named behavioral/static tests in the fix gate: **126 passed, 0 failed** (the original documented four suites are **119 passed, 0 failed**; the added shared canonical parity suite contributes 7).
- `deno check --node-modules-dir=auto` on all seven changed TypeScript/test files — passed.
- `deno fmt --check` on all changed TypeScript/JSON files — passed.
- `git diff --check` — passed.

Migration remains `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`; review-fix SHA-256 before commit: `b5fe0abab22fb67f773ede3ecd8c3999bd8b797b80411342c80c271bf75eb780`.

Live applied: **no**. No Docker, local PostgreSQL/Supabase, external network, production data, linked command, migration apply/push/dry-run, reset, or repair was used. Transactional live fixtures (real PostgreSQL execution, concurrent reviewers, Card B byte-for-byte checks, future-boundary visibility, job fan-out, and ordered Task 2/3/4 apply/lint/integration) remain an explicit unresolved live gate; static/pure tests are not represented as covering them.

## Review fix round 2/5 — 2026-08-19

### Red proof

The new review contracts were first exercised on `55559bfb45fcb61e65215a39a569ba911a8a5344`:

- `benefit-enrichment-batch/index_test.ts` failed type checking because the lifecycle reader was private and still queried unfiltered `card_benefit_mapping`; the new DB-category replay also exposed raw upper-case category reconstruction.
- `benefit_admin_test.ts` failed type checking because the closed canonical-envelope validator did not exist. The added cases cover double/triple/mixed structural encodings, numeric boundaries, immutable taxonomy edits, oversized decisions, and exact pre-alias rewards identity migration.
- `review_card_benefit_enrichment_v2_migration_test.js` reported **4 passed / 4 failed** before implementation. The missing contracts were monotonic retirement, bounded/once-only evidence and decisions, exact envelope key closure/numeric parity, and migration-time legacy rewards assertions.

### Fixes

- Canonicalized DB-shaped V6 category codes through the same shared category alias contract used by extraction and publication. `POINTS` and `CASHBACK` approved rows now reconstruct to their exact condition identities while V5 behavior remains unchanged.
- Replaced the raw mapping read with the Task 2 `active_card_benefits` UTC lifecycle view and retained its flat live benefit UUID. Future replacements remain hidden, and an old mapping scheduled to retire at the replacement boundary remains current until then.
- Made explicit retirement monotonic with `coalesce(retired_at, statement_timestamp())`, so a later retire review cannot move an already scheduled future boundary earlier.
- Added bounded four-pass structural decoding with a 16 KiB input cap. Double/triple percent encoding, nested entities, and mixed entity/percent credentials, query strings, and fragments redact recursively in DTO values and object keys while ordinary percent prose is unchanged.
- Closed the server-created canonical publication envelope with exact root/condition/benefit/value-config/exclusion/migration key allowlists, primitive shape checks, a 64-decision/256 KiB review limit, 500-character reasons, bounded evidence, and one evidence copy per audit append. Review replay hashes exclude non-authoritative presentation copies and unknown decision fields fail closed.
- Defined a conservative cross-runtime numeric domain in Edge and SQL: zero is allowed; non-zero absolute values must be at least `0.000001`, below `1e21`, use at most six decimal places without exponent notation, and have a coefficient no greater than `Number.MAX_SAFE_INTEGER`. The rule covers locked staging, conditions, nested configuration/exclusions, and persisted benefit terms; values are rejected rather than rounded.
- Removed category and value type from editable fields. Changed taxonomy attempts fail with `immutable_benefit_taxonomy`; material commercial edits still create immutable versions and may carry display changes.
- Added an audited compatibility path for already-pending pre-alias V6 `rewards` proposals. Edge and SQL independently require the exact old rewards condition hash/card-scoped key, convert only that identity to canonical `points`, publish the new key, and append `category_alias_identity_migration`. Tampered old identity fails, and replay is deterministic.
- Extended migration self-assertions for unknown keys, unsafe numeric values, exact legacy alias migration, locked-card hash/key recomputation, and service-role-only helper grants. No business table or column was added.

### Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 8 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 29 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/benefit-enrichment-batch/index_test.ts` — 58 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/_shared/benefit_contract_test.ts` — 7 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed.
- Total named behavioral/static tests: **131 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all six changed TypeScript/test files — passed.
- `deno fmt --check` on all six changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration remains `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`; fix-round-2 SHA-256 before commit: `5bc1106051c0c515194cb61b3cd06cabedd4dd71733056cb781c3f9cc445e4ad`.

Live applied: **no**. No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, or repair was used. Real PostgreSQL parse/apply and transactional fixtures for concurrency, Card B byte-for-byte immutability, UTC future-boundary visibility, job fan-out, replay, and the ordered Task 2/3/4 integration remain the explicit unresolved live gate; static and pure tests do not claim to cover that gate.

## Review fix round 3/5 — 2026-08-19

### Red proof

The new review contracts were first exercised against `d1e039677eff58dad4ca34cfc2f4fa823986a63c`:

- `benefit_admin_test.ts` reported **29 passed / 4 failed**. The failures reproduced username-only userinfo disclosure, partial presentation of oversized staging without an invalid marker, an accepted canonical-envelope boundary overflow, and unbounded work over 10,000 proposals. A later lane-specific red proved 33 evidence records and 65 decisions/proposals must fail before mapping.
- `benefit-enrichment-batch/index_test.ts` reported **58 passed / 1 failed** because real uppercase `CASHBACK` V5 DB rows did not replay unchanged. Additional focused fixtures failed for live category names such as `Cashback Rewards` before the shared aliases were added.
- `review_card_benefit_enrichment_v2_migration_test.js` reported **9 passed / 1 failed** because there was no shared Edge/SQL publication-limit module or equality contract.
- The Node golden suite deliberately changed from **29 passed / 0 failed** to **28 passed / 1 failed** when semantic category normalization was initially applied to extraction identity. Splitting comparison normalization from extraction identity restored the exact V5 golden while retaining uppercase DB replay.

### Fixes

- Extended bounded, iterative structural secret detection to redact username-only and username/password userinfo for dotted hosts, IPv4, bracketed IPv6, localhost, and single-label hosts when URL path/port/query/fragment structure is present. Encoded and mixed entity/percent variants redact in real admin DTO values and object keys; ordinary email prose and percent text remain intact.
- Canonicalized every reconstructed current DB category through the shared alias contract for semantic comparison, including uppercase codes and human-readable names for cashback, points, and lounge. Legacy V5 identifiers and hashes remain the extraction authority and exact replay is unchanged.
- Added one shared TypeScript publication-limits contract and mirrored its named values exactly in SQL: 64 decisions/array items/staged proposals, 500-character canonical strings, 32 KiB conditions/evidence, 64 KiB benefits, 128 KiB envelopes, 256 KiB reviews, depth 8, and 256 aggregate canonical keys. Edge validates these inclusive boundaries before hashing/RPC; SQL validates the same closed envelope and the migration asserts exact pass/fail boundaries.
- Bounded admin presentation independently by recursion depth, object keys, array items, strings/keys, total work, and 128 KiB serialized output. Oversized, deeply nested, cyclic, or lane-overflow input returns an explicit `presentation_truncated` + `presentation_invalid` marker; approval still validates the untouched locked staging and cannot approve a displayed subset.
- Kept lifecycle claims precise: the scheduled reader test now states it verifies view selection and returned UUID only, while a static contract verifies Task 2's `active_card_benefits` UTC `valid_from`, `valid_until`, and `retired_at` predicates. Real database-boundary execution remains pending.
- Added an invoker-only bounded JSON-shape helper with service-role execution only and apply-time assertions. No business schema/table/column changes were introduced.

### Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 10 passed, 0 failed.
- `deno test --allow-env --allow-read --allow-net=0.0.0.0:8000 --node-modules-dir=auto supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 33 passed, 0 failed.
- `deno test --allow-env --allow-read --node-modules-dir=auto supabase/functions/benefit-enrichment-batch/index_test.ts` — 59 passed, 0 failed.
- `deno test --allow-env --allow-read --node-modules-dir=auto supabase/functions/_shared/benefit_contract_test.ts` — 7 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed.
- Total named behavioral/static tests: **138 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all seven changed TypeScript/test files — passed.
- `deno fmt --check` on all seven changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration remains `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`; fix-round-3 SHA-256 before commit: `562113c472106a9a8058fe8df50e3252f07dca84019efd2189639a80c8fb3bb0`.

Live applied: **no**. No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, or repair was used. Real PostgreSQL parse/apply plus transactional fixtures for concurrent review, Card B byte-for-byte immutability, UTC lifecycle boundaries, linked-job fan-out, exact replay, and ordered Task 2/3/4 integration remain the explicit unresolved live gate; static/pure tests do not claim database-boundary coverage.

## Review fix round 4/5 — 2026-08-19

### Red proof

The review contracts were first exercised against `7c448949e924612e4f68de1d67fa6a5586ab64b7`:

- `benefit-enrichment-batch/index_test.ts` failed type checking because diff modifications had no `changeType`. The exact-one assertion later exposed a residual empty semantic-map conflict after a migration match.
- `benefit_admin_test.ts` reported **33 passed / 4 failed** for no-tail userinfo disclosure, Edge/SQL title/type/key mismatch, corrupt unselected proposals, and missing server-derived legacy replacement binding.
- `review_card_benefit_enrichment_v2_migration_test.js` reported **7 passed / 4 failed** because there was no locked-array validator, service-path proposal-bound contract, shared new limits, or locked-diff migration binding.
- The focused pending-V5 approval fixture failed type checking until the pure V5 decision validator was made testable and routed through the same server-derived migration contract.

### Fixes

- Legacy current rows now derive offer subjects with the parser's existing finite qualifier vocabulary while ignoring persisted legacy `offer_subject` text. Canonical category aliases preserve reward subject compatibility. Exact semantic+condition matches from a legacy key to a V2-publishing V6 or rollback V5 proposal produce one `identity_migration` modification containing the live UUID, with no add/remove/conflict tail; genuine term changes remain ordinary modifications.
- Admin presentation exposes the server-derived modification type, while both V5 and V6 approval reject client `change_type`, bind the locked modification/current UUID, and send only an internal decision type. SQL independently rebinds the exact locked proposed JSON, verifies `existing_benefit_id` and `change_type`, publishes the card-scoped row, maps it, and retires only that card's legacy mapping at the existing immediate/future replacement boundary. Replacement retirement does not use disappearance evidence; explicit disappearance retirement still does.
- Added complete locked-proposal validation before presentation, Edge approval, and under the SQL row lock: 64 proposals, 128 KiB total, depth 8, 256 keys, 64 array items, 500-character keys, 8,000-character staged strings, safe numeric domain, exact proposal-field allowlist, required V5/V6 fields, parser binding, and duplicate legacy/V2 identities. A corrupt unselected proposal invalidates the whole review.
- Extended no-tail privacy handling: password-bearing userinfo redacts for plausible hosts; username-only redacts for explicit port, IP, bracketed IPv6, localhost, or single-label hosts. Ordinary dotted-host email prose remains unchanged. Structural percent/entity decoding is now a detection probe and returns the original bytes unless it finds a URL/userinfo secret.
- Aligned Edge and SQL on nonempty two-character-minimum titles, nonempty benefit types, and recursive 500-character key limits. Migration-time assertions cover exact key/string/array/depth/count boundaries and valid/oversized/unknown/malformed/duplicate/deep/wide multi-proposal arrays.
- Added only invoker/service-role helper functions; no business table or column changed.

### Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 11 passed, 0 failed.
- `deno test --allow-env --allow-read --allow-net=0.0.0.0:8000 --node-modules-dir=auto supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 38 passed, 0 failed.
- `deno test --allow-env --allow-read --node-modules-dir=auto supabase/functions/benefit-enrichment-batch/index_test.ts` — 60 passed, 0 failed.
- `deno test --allow-env --allow-read --node-modules-dir=auto supabase/functions/_shared/benefit_contract_test.ts` — 7 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed, including unchanged V5/V6 goldens.
- Total named behavioral/static tests: **145 passed, 0 failed**.
- `deno check --node-modules-dir=auto` on all six changed TypeScript/test files — passed.
- `deno fmt --check` on all six changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration remains `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`; fix-round-4 SHA-256 before commit: `4c308c0154ef407d7b3da84d327c094954bcb5af77df16dbfccd96b93d9dcfc4`.

Live applied: **no**. No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, or repair was used. Real PostgreSQL parse/apply plus transactional fixtures for concurrent review, Card B byte-for-byte immutability, UTC replacement boundaries, locked-row replay, linked-job fan-out, and ordered Task 2/3/4 integration remain the explicit unresolved live gate; static/pure tests do not claim database execution.

## Review fix round 5/5 — 2026-08-19

### Red proof

The final review contracts were first exercised against `365375daa46989d179e886e067a3c52cfb47bbc0`:

- `benefit-enrichment-batch/index_test.ts` reported **60 passed / 1 failed**: a generic legacy display description plus a Task 2 structured exclusion object did not match the semantically identical V5 exclusion array as one identity migration.
- `review_card_benefit_enrichment_v2_migration_test.js` reported **10 passed / 2 failed**: replacement retirement still overwrote its prior boundary and no duplicate target-publication guard existed before the first mutation.
- A read-only `deno eval` loaded the exact baseline privacy module from `git show 365375d:...`; **4 of 5** punctuation/encoded credential fixtures still contained `alice`, directly confirming the disclosure without modifying the worktree.
- The first combined Deno invocation omitted the admin handler's localhost-only listener permission, so that file was cancelled before behavioral execution. The exact admin regressions were retained and then run with the documented `--allow-net=0.0.0.0:8000` boundary: punctuation-delimited userinfo, corrupt unselected proposal field types, canonical duplicate targets, and no-RPC failure behavior.

### Fixes

- Added one comparison-only condition projection through the shared canonical benefit contract. Legacy exclusion arrays and Task 2 exclusion objects now compare identically without changing legacy IDs or V5 golden serialization. A legacy-to-v2 replacement becomes `identity_migration` only for one unmatched legacy row and one publishable V5/V6 proposal with the exact same complete canonical condition; same-condition multiplicity and real term changes fail closed into normal review tails/conflicts. The exact live UUID remains the replacement authority.
- Replaced delimiter-sensitive userinfo handling with a bounded candidate scan. Password-bearing userinfo is removed through square/curly/round delimiters, slash prefixes, trailing punctuation, IP/IPv6/localhost hosts, and iterative encoded forms. Username-only values still require the prior structural URL signals, and ordinary email/percent/math text remains byte-for-byte unchanged.
- Made the whole locked proposal array contractual before presentation, approval, or RPC: exact root/config/exclusion fields, required nonempty strings, numeric terms, string arrays, confidence/evidence objects, source hashes, parser-specific exclusion/config shapes, and matching V6 nested subject/restriction/exclusion mirrors. A corrupt unselected proposal invalidates the review. Edge canonicalizes every proposal condition and rejects duplicate canonical publication identities; SQL independently checks every raw field type and rejects duplicate recomputed selected target keys before any insert/update/audit.
- Replacement retirement now uses the earliest boundary: `NULL` accepts the computed boundary and an existing boundary is reduced with `least(existing, computed)`. It cannot be extended by a later review. The mapping predicate remains `card_id + benefit_id`; explicit disappearance retirement keeps its separate absence-proof and monotonic behavior.
- Preserved the locked-diff/server-derived identity-migration decision, V5 rollback, pre-alias rewards compatibility, active lifecycle view, Card B card-scoped isolation, immutable benefit rows, bounded envelope/numeric contract, linked-job fan-out ownership checks, all-action duplicate guards, and service-role-only invoker grants.

### Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 12 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 40 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/benefit-enrichment-batch/index_test.ts` — 61 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/_shared/benefit_contract_test.ts` — 7 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed, including unchanged V5/V6 goldens.
- Total named behavioral/static tests: **149 passed, 0 failed**.
- `deno check --node-modules-dir=auto --frozen` on all five changed TypeScript/test files — passed.
- `deno fmt --check` on all five changed TypeScript/test files — passed.
- `git diff --check` — passed.

Migration remains `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`; final fix-round-5 SHA-256 before commit: `4e126d0d0c221754ed7e03c5d46490cd0c5b76602c20e9d8f4a91072e0f9d2e8`.

Live applied: **no**. No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, or repair was used. Real PostgreSQL parse/apply plus transactional fixtures for concurrent review, Card B byte-for-byte immutability, UTC replacement boundaries, locked-row replay, linked-job fan-out, and ordered Task 2/3/4 integration remain the explicit unresolved live gate; static/pure/apply-time contracts do not claim database execution.
