# Task 9 Report — Admin Review and Active Consumer Reads

## Outcome

Task 9 is implemented without a schema change. Admin reads now return bounded,
redacted operator DTOs; normal authorization is a confirmed Supabase identity
whose own `public.users.is_admin` value is true; and the email allowlist is a
logged, diagnosed break-glass fallback only. The service-role client is created
only after that authorization boundary.

Flutter preserves the server's job, card, staging, live-benefit, canonical
benefit, dedupe, condition, source, and change identities through parse, edit,
and submit. Malformed v6 identity fails closed visibly, while legacy review rows
remain readable. Benefit and catalog review expose bounded evidence,
completeness, attempts, before/after values, and separate reviewed lifecycle
actions. Issuer quarantine pagination is lossless, bounded, deduplicated, and
fails honestly instead of returning a partial list.

The movie-deals consumer now reads both benefit terms and mappings through
`active_card_benefits`; the scheduled enrichment consumer already did so. No
app/server benefit reader found by inventory remains on a base benefit/mapping
table. Eligibility continues to be owned by PostgreSQL UTC date/current-instant
semantics in the existing security-invoker view.

Live applied: **no**.

## Mandatory pre-edit inventory

The exact required commands run before editing were:

```sh
rg -n "card_benefit_mapping|active_card_benefits|benefits\(|valid_from|valid_until|retired_at|is_active" lib test supabase/functions
rg -n "is_admin|CARD_CATALOG_ADMIN_EMAILS|email_confirm|confirmed_at|admin-catalog-entry" lib test supabase/functions supabase/migrations
```

The first command's production hits resolved to these paths and meanings:

- `lib/core/repositories/movie_deals_repository.dart` was the only app benefit
  query consumer. Before Task 9 it selected movie-like rows from `benefits`
  using global `is_active=true`, then mappings from `card_benefit_mapping`.
- `supabase/functions/benefit-enrichment-batch/index.ts` was the only server
  query consumer. Its `readCurrentBenefits` already selected
  `active_card_benefits` by `card_id`, so it required no production change.
- `lib/core/repositories/cards_repository.dart` and
  `lib/shared/models/user_card.dart` hits concern user-card ownership
  `is_active`, not benefit eligibility.
- `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart` is a domain
  comment/value carrier for validity dates, not a database query.
- `_shared/benefit_contract.ts`, `_shared/benefit_enrichment.ts`, and
  `admin-catalog-entry/benefit_admin.ts` normalize/present proposal fields; they
  do not perform live consumer benefit reads. Remaining hits were tests.

After the change, the production inventory has exactly two live benefit-read
implementations and both use the view:

1. `SupabaseMovieDealsDataSource.loadMovieRelatedBenefits` and
   `loadMappings` — `active_card_benefits`.
2. `readCurrentBenefits` in `benefit-enrichment-batch` —
   `active_card_benefits`.

The second command found these authorization paths:

- Flutter's `AdminCatalogEntryApi.invoke` sends benefit-review actions to the
  `admin-catalog-entry` Edge function.
- `CardCatalogReviewScreen` sends catalog/quarantine/access actions to that
  same Edge function. There is no second client-side authorization route.
- `handleAdminCatalogEntry` authenticates the JWT and is the single Edge
  authorization/service-role boundary; `benefit_admin.ts` dispatches actions
  only after that boundary.
- Existing publication RPC boundaries in
  `20260819231435_publish_reviewed_card_identity.sql` independently require a
  locked `public.users.is_admin=true` actor for reviewed publication.
- Existing migration `20260819063836_add_admin_flag_to_public_users.sql`
  revokes table-wide authenticated INSERT/UPDATE and restores an explicit
  column allowlist that excludes `is_admin`. The existing own-row RLS policy
  therefore cannot be used for self-escalation. No new migration was needed.

## Query and eligibility decisions

- Movie benefit discovery and mapping lookup both select the central active
  view. A concrete loopback Supabase/PostgREST boundary test asserts both actual
  request paths and prevents a mock-only query regression.
- The contract test inspects the existing lifecycle migration and asserts
  `security_invoker=true`, mapping `retired_at > now()`, and explicit
  `timezone('UTC', statement_timestamp())::date` validity comparisons.
- Its pure boundary matrix covers expired validity, future validity, past
  retirement, future scheduled retirement, inclusive `valid_until`, and null
  validity.
- Device-local calendar logic is not used to determine database eligibility.
  One mapping is retired through its exact live benefit/mapping identity; the
  UI/repository do not reinterpret global `benefits.is_active` as a per-card
  retirement switch.

## Authorization and privacy decisions

- The request-scoped anon client authenticates the Bearer token first and reads
  only the authenticated user's own `public.users.is_admin` row through RLS.
- A confirmed identity plus database admin flag is the normal path. A submitted
  or known email cannot authorize a normal user. Unconfirmed identities are
  denied before database-admin or allowlist evaluation.
- A confirmed allowlisted user without the database flag is admitted only as
  `break_glass`; each action emits a bounded warning containing user ID and
  action, never the allowlist. The access response identifies
  `database_admin` or `break_glass` without exposing configured emails.
- The privileged service-role client is created only after authorization and
  request parsing. List actions issue selects only.
- Catalog/quarantine rows pass through a strict presenter. It exposes bounded
  reviewed fields, baseline, target excerpt, public source observation,
  candidates, and a small public job-evidence allowlist, then recursively
  redacts URL secrets. Lease tokens, full producer evidence, and unknown
  internal fields are omitted.
- Quarantine status, classification, and limit are allowlisted/bounded. Its
  cursor accepts only a PostgreSQL timestamp with at most six fractional digits
  plus a UUID. `Date` validates the instant but the original timestamp text is
  retained in the exclusive `(created_at DESC, id DESC)` predicate.

## Flutter DTO, action, and UI decisions

- v6 parsing retains staging/card/parser identity, canonical benefit ID,
  dedupe key, condition hash, live benefit ID, source identity/identities,
  content hash, change type, value configuration, exclusions, attempts,
  completeness, observation time, and retirement proof. Job/staging/card
  disagreements and missing/malformed canonical proposal identity throw a
  visible `FormatException` state. Legacy data is unaffected.
- Edits replace only editable title/description terms on the preserved server
  decision/proposal. Immutable identity/evidence fields survive `copyWith` and
  serialization. The v6 wire deliberately omits client `change_type` because
  the locked server validator derives it; the DTO still preserves/displays it.
  Exact server IDs and dedupe keys are submitted.
- Benefit review shows retrieved/crawl observation times, incomplete reason,
  every bounded source attempt/outcome, old-to-new terms, identity migration,
  live/canonical IDs, dedupe/condition/source identities, evidence hashes, and
  retirement eligibility/proof. `Retire benefit` is separate from rejection,
  hidden when ineligible, and requires a confirmation plus a nonempty reason.
- Catalog lifecycle review shows baseline to proposal for card name, network,
  joining fee, annual fee, APR, and canonical URL. Missing proposal values are
  rendered `No proposal`; edit serialization sends only nonempty explicitly
  editable name/network fields, so absent fields cannot become implicit clears.
- `Mark discontinued` requires a target-scoped strong gone/explicit
  discontinuation observation. `Reactivate` requires reviewed exact-card
  reappearance. Raw HTTP status/error alone exposes neither action. Both require
  reason and confirmation.
- Quarantine shows only bounded public evidence. Retry appears only for the
  server's exact retryable classification/reason; otherwise the card explains
  manual repair/keep-quarantined. Retry/reject require reasons.
- Flutter follows every quarantine `has_more` cursor up to 20 pages/500 rows,
  rejects repeated/missing cursors, deduplicates by stable review ID, gives new
  quarantine rows precedence over the older general list, and throws an
  operator-visible error on a page/row bound or page failure.

## Schema and migration decision

No migration was created or modified. The reviewed existing admin-hardening
migration is:

```text
82df4f501eb24f5e88be6080b66c5c296f95bb4d68a7cd4b5f3c1a44a015980e  supabase/migrations/20260819063836_add_admin_flag_to_public_users.sql
```

This is the minimum-schema outcome: existing column grants already deny
authenticated `is_admin` assignment, and existing RPC checks consume the flag.

## Red-to-green evidence

Initial RED checkpoints:

- The admin Flutter suite failed to compile with 14 expected missing v6 DTO,
  crawl, retirement, lifecycle, and pagination APIs.
- The concrete movie query boundary failed because requests used
  `/rest/v1/benefits` and `/rest/v1/card_benefit_mapping`; its 14 existing
  repository tests remained green.
- Focused widget reds then demonstrated missing catalog presenter/lifecycle
  controls, visible malformed-data handling, safe edit projection, source
  attempt/evidence fields, old/new term display, condition identity, and
  retirement eligibility.
- The retirement interaction reproduced a real controller lifecycle failure
  during dialog exit animation. Reason dialogs now capture validated input
  without prematurely disposed controllers.
- The v6 identity test failed to compile until staging card/parser identity was
  represented, then covered cross-card staging mismatch as a fail-closed case.

Final GREEN commands/results:

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
# 25 passed, 0 failed

flutter test --no-pub test/features/benefits/movie_deals/movie_deals_repository_test.dart
# 15 passed, 0 failed

node --test test/supabase/active_benefit_read_rules.test.mjs test/supabase/admin_user_flag_migration_test.js
# 4 passed, 0 failed

deno test --allow-env --allow-net=127.0.0.1 --allow-read --node-modules-dir=auto --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts
# 47 passed, 0 failed

deno test --allow-env --allow-read --node-modules-dir=auto --frozen supabase/functions/benefit-enrichment-batch/index_test.ts
# 129 passed, 0 failed

deno test --allow-env --allow-read --node-modules-dir=auto --frozen supabase/functions/_shared/catalog_identity_publication_test.ts
# 24 passed, 0 failed

node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js test/supabase/publish_reviewed_card_identity_migration_test.js test/supabase/card_catalog_enrichment_rules.test.mjs test/supabase/issuer_card_discovery_rules.test.mjs
# 81 passed, 0 failed

deno check --node-modules-dir=auto --frozen supabase/functions/admin-catalog-entry/index.ts supabase/functions/admin-catalog-entry/benefit_admin.ts
# passed
```

`flutter analyze --no-pub` has no Task 9 diagnostics. The exact command exits 1
because the existing repository baseline contains 12 informational lints in
unmodified service files (initializing formals, `print`, and async
`BuildContext`). `flutter analyze --no-pub --no-fatal-infos` exits 0 with those
same 12 baseline infos. No unrelated service files were changed to mask that
baseline.

Dart and TypeScript format checks, production Deno checks, migration-no-change
check, and `git diff --check` all passed. No Docker, local/linked/live
Supabase/Postgres, external issuer, production data, secret, or workflow action
was used.

## Live-only gates

- Deployment must already contain the Task 2 active view and Task 4 reviewed
  publication RPCs; Task 9 does not mutate or apply them.
- A real operator needs a confirmed Supabase identity and a server-governed
  `public.users.is_admin=true` profile row. Break-glass requires explicit server
  allowlist configuration and produces diagnostic logs.
- Service-role and anon environment variables remain deployment-only inputs;
  no values were read, written, or reported here.
- Live smoke/application and production writes remain deliberately pending.

## Fresh-review fix round 1

The first post-implementation review identified four defects. They were
reproduced before changing production code:

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
# RED: 24 passed, 4 failed
# - production-shaped approved/legacy current v6 rows rejected
# - staging-only v6 corruption parsed as legacy and did not show repair
# - statement last-four/header/customer prose rendered in catalog UI

deno test --allow-env --allow-read --node-modules-dir=auto --frozen \
  --filter 'admin authorization prefers' \
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts
# RED: 0 passed, 1 failed — generic confirmed_at received break-glass

deno test --allow-env --allow-read --node-modules-dir=auto --frozen \
  --filter 'catalog admin DTO' \
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts
# RED: 0 passed, 1 failed — nested DTO retained evidence.last_four
```

Corrections:

- v6 validation now has separate structural lanes. Additions and proposed
  modification/unchanged/conflict rows require exact canonical
  `benefitId == dedupeKey` plus a SHA-256 condition hash. Approved current/live
  rows require their immutable live ID and dedupe key, accept legacy dedupe
  identity, and do not invent a missing condition hash. If a current row does
  supply canonical ID/hash, inconsistency still fails closed. Literal fixtures
  mirror `currentBenefitProposal` for canonical current modification, legacy
  unchanged, and legacy possible-removal rows.
- Any of job, staging, or extraction parser version declaring `benefits-v6`
  enters v6 validation. A staging-only v6 disagreement now reaches the real
  repository/panel malformed-data repair state instead of rendering as legacy.
- Break-glass still requires general confirmed identity at the auth boundary,
  but additionally requires confirmation tied to the exact normalized
  allowlisted `user.email`: either its `email_confirmed_at`, or a verified
  identity whose email equals it. Generic `confirmed_at` and an unrelated
  verified identity cannot authorize break-glass. A loopback-only HTTP matrix
  covers both denials and both exact-email confirmation forms; database-admin
  authorization remains independent and server-governed.
- Catalog/quarantine presentation removes `last_four` and
  `pdf_header_excerpt` from the strict job-evidence allowlist, recursively drops
  customer/statement keys outside that allowlist, and verifies that injected
  digits, customer name, and private statement prose are absent. Flutter no
  longer renders either statement field even if an unsafe raw map bypasses the
  Edge presenter. Target-specific public issuer evidence remains bounded and
  visible.

Fresh full GREEN results after the correction:

```text
Flutter admin review                         28 passed, 0 failed
Flutter movie consumer                      15 passed, 0 failed
Edge admin (includes loopback auth matrix)  48 passed, 0 failed
Ingestion + publication Deno regressions   153 passed, 0 failed
Node active/security/catalog/migrations     85 passed, 0 failed
Deno production checks                       passed
Flutter analysis (infos non-fatal)           passed; same 12 baseline infos
```

No migration was created or modified. The existing admin-hardening migration
remains SHA-256
`82df4f501eb24f5e88be6080b66c5c296f95bb4d68a7cd4b5f3c1a44a015980e`.
The auth-matrix HTTP server bound only to ephemeral `127.0.0.1`; no external
network, Docker, local/linked/live Supabase/Postgres, production data/write,
secret, or workflow action was used. Live applied: **no**.

## Fresh-review fix round 2

The second post-implementation review found that Flutter still conflated the
canonical proposed identity contract with the producer's decorated legacy
removal contract, and did not bind canonical proposal IDs to the review card
and condition hash. Both failures were reproduced before production changes:

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
# RED: 23 passed, 7 failed
# - withCardScopedRemovalIds-shaped legacy removals were rejected as malformed
#   current identity in DTO, repository, and widget paths
# - cross-card, mismatched-hash, and malformed-prefix canonical proposal IDs
#   parsed successfully instead of throwing FormatException
# - those malformed proposals rendered through the real repository/panel path
#   instead of showing the visible malformed-data repair state
```

Corrections:

- Canonical proposed additions and the proposed sides of modification,
  unchanged, and conflict rows now require the exact identity
  `card-benefit-v2:<review.cardId>:<conditionHash>`, with
  `benefitId == dedupeKey` and a 64-hex condition hash. Cross-card IDs,
  digest mismatches, and malformed prefixes fail closed in both DTO and visible
  repository/panel tests.
- Current/live validation remains a separate structural lane. Every row still
  requires its server-issued live ID and dedupe key. Canonical current rows
  require an exact card-scoped v2 ID equal to their dedupe key. Legacy current
  rows may omit canonical identity, while `withCardScopedRemovalIds` output may
  retain its legacy dedupe key and carry the server-decorated exact card-scoped
  v2 benefit ID. Malformed/cross-card decorated IDs and inconsistent supplied
  condition hashes still fail closed.
- Retirement serialization is exercised with the producer-equivalent decorated
  removal and preserves the exact live UUID, legacy dedupe key, and decorated
  benefit ID; Flutter neither reconstructs nor normalizes those server values.
- Non-production fake suffixes in v6 fixtures were replaced with canonical
  64-hex production-shape identities so validation tests exercise the real
  contract rather than a weakened test-only format.

Fresh full GREEN results after this correction:

```text
Flutter admin review                         30 passed, 0 failed
Flutter movie consumer                       15 passed, 0 failed
Edge admin (includes loopback auth matrix)   48 passed, 0 failed
Ingestion + publication Deno regressions    153 passed, 0 failed
Node active/security/catalog/migrations      85 passed, 0 failed
Total                                       331 passed, 0 failed
Deno production checks                        passed
Dart and Deno format checks                   passed
Flutter analysis (infos non-fatal)            passed; same 12 baseline infos
git diff --check                              passed
```

No migration was created or modified relative to fix-round-1 commit
`eae56443a645de7f6e4e679e3f7b85a07a4250d9`. The existing admin-hardening
migration remains SHA-256
`82df4f501eb24f5e88be6080b66c5c296f95bb4d68a7cd4b5f3c1a44a015980e`.
The round-2 pre-commit production/test hashes were respectively
`6135918e68ef5abc6f9edfcfc17a9ab30ec3bb62f91a3213879b5956b2e8da17` and
`4195a9b4efa9555c1b21cfa5a2919b751864c4ba549294cf21110385f7b1e260`.

Only the existing auth-matrix test used an ephemeral `127.0.0.1` listener. No
external network, Docker, local/linked/live Supabase/Postgres, production
data/write, secret, or workflow action was used. Live applied: **no**.
