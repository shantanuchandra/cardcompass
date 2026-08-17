# Supabase integration tests

Tests in this directory require a **live local Supabase instance** — they
are never run as part of the regular unit-test suite in `test/features/...`.

A bare `flutter test` (no path argument) discovers these files, but the live
integration groups skip unless `RUN_SUPABASE_INTEGRATION=true` and
`SUPABASE_ANON_KEY` are explicitly provided. Tests use `SUPABASE_URL` when it
is set and otherwise default to local Supabase at `http://127.0.0.1:54321`.
The explicit flag prevents mutating tests from accidentally targeting a hosted
project merely because app credentials are present.

To run these tests:

```bash
supabase start
flutter test test/supabase/ \
  --dart-define=RUN_SUPABASE_INTEGRATION=true \
  --dart-define=SUPABASE_ANON_KEY=<the anon key printed by supabase start>
```

### Automated benefit-enrichment safety workflow

`benefit_enrichment_integration_test.dart` is destructive local verification:
it seeds uniquely named cards, benefits, enrichment jobs, and an auth user,
then removes those fixtures. It invokes the real locally served batch function;
the function, not the test, must create crawler discovery/review rows. In
addition to the anon key it requires the local service-role key and refuses any
`SUPABASE_URL` whose host is not `localhost`, `127.0.0.1`, or `::1`. Never point
it at a hosted project.

Create `supabase/.env.local` locally (it is ignored by Git) with placeholder
names replaced by local-only values. Do not commit the values:

```dotenv
BENEFIT_ENRICHMENT_CRON_SECRET=<local-only-random-secret>
CARD_CATALOG_ADMIN_EMAILS=<confirmed-local-test-user@example.test>
```

The Supabase CLI injects its local `SUPABASE_URL`, anon key, and service-role
key into served functions; do not copy hosted credentials into this file.

The full live test also requires two explicitly selected, stable official
fixtures. These values are not secrets, but they are opt-in because the test's
local Edge Function will fetch those public issuer pages:

```bash
export SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER='<supported issuer>'
export SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL='<public HTTPS product URL>'
export SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME='<exact known product name>'
export SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER='<different supported issuer>'
export SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL='<public HTTPS trigger product URL>'
export SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_CARD_NAME='<exact trigger product name>'
export SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT='<new sitemap product name>'
```

Both product pages must contain concrete, parseable benefit terms. The benefit
fixture must yield at least one benefit absent from reset reference data. The
discovery fixture's origin must serve `/sitemap.xml`, and that sitemap must lead
to the expected new product, which must also be absent from reset catalog data.
The production batch currently derives `/sitemap.xml` from the trigger URL; it
does not accept a separate sitemap/root override.

Reset the local database and serve the local functions before running it:

```bash
supabase db reset
supabase functions serve --env-file supabase/.env.local

flutter test test/supabase/benefit_enrichment_integration_test.dart \
  --dart-define=RUN_SUPABASE_INTEGRATION=true \
  --dart-define=SUPABASE_ANON_KEY=<local anon key> \
  --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key> \
  --dart-define=SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER="$SUPABASE_OFFICIAL_BENEFIT_FIXTURE_ISSUER" \
  --dart-define=SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL="$SUPABASE_OFFICIAL_BENEFIT_FIXTURE_URL" \
  --dart-define=SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME="$SUPABASE_OFFICIAL_BENEFIT_FIXTURE_CARD_NAME" \
  --dart-define=SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER="$SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_ISSUER" \
  --dart-define=SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL="$SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_URL" \
  --dart-define=SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_CARD_NAME="$SUPABASE_OFFICIAL_DISCOVERY_FIXTURE_CARD_NAME" \
  --dart-define=SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT="$SUPABASE_OFFICIAL_DISCOVERY_EXPECTED_NEW_PRODUCT"
```

The test checks local function authentication, anon queue denial, expired lease
recovery, real batch-produced staging, repeat-run staging reuse, and background
issuer discovery producing one deduplicated service job plus pending review. It
also compares all benefit and mapping IDs: rejection changes neither set, while
one approval adds exactly one benefit ID and one mapping ID without replacing
unrelated rows.

Official fixture URLs must be public HTTPS. Static checks reject loopback and
literal private addresses, and the production fetcher still performs issuer
allowlisting plus DNS/private-address validation. There is no local/private
bypass or test-only production backdoor.

If Docker is unavailable, the command without `RUN_SUPABASE_INTEGRATION=true`
still compiles the file and reports the live group as skipped. That is only a
compile check, not an integration pass.

To run only the pure-Dart unit suite (the common case, e.g. before a
commit), scope the invocation to exclude this directory:

```bash
flutter test test/features/
```

## Known gap: re-running against a persistent local instance

`benefit_platform_confirmations_permissions_test.dart`'s `setUpAll` signs up
a hardcoded test email (`movie-deals-permissions-test@example.com`) with no
error handling. Local Supabase auth persists across `supabase start`/`stop`
cycles (it's a real Postgres volume, not in-memory), so re-running this file
against the SAME local instance a second time will hit "email already
registered" in `signUp` — which fails `setUpAll` and takes down all 3 tests
with a confusing setup error, not a clear per-test failure. If you hit this,
either `supabase db reset` first (wipes local data, including this test
user) or manually delete the `movie-deals-permissions-test@example.com` auth
user before re-running. This was found during review and deliberately left
unfixed in the test file to keep it matching the plan's spec exactly, since
this environment has no Docker and could never confirm a randomized-email
fix actually works end to end — fix it in the test file itself (e.g.
randomize the email per run) the first time you run this for real, once you
can verify the fix against a live instance.
