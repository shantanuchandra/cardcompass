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
