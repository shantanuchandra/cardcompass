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
it seeds uniquely named cards, benefits, crawler review work, enrichment jobs,
and an auth user, then removes those fixtures. In addition to the anon key it
requires the local service-role key and refuses any `SUPABASE_URL` whose host is
not `localhost`, `127.0.0.1`, or `::1`. Never point it at a hosted project.

Reset the local database and serve the four functions before running it:

```bash
supabase db reset
supabase functions serve \
  card-discovery catalog-enrichment benefit-enrichment-batch admin-catalog-entry \
  --env-file supabase/.env.local

flutter test test/supabase/benefit_enrichment_integration_test.dart \
  --dart-define=RUN_SUPABASE_INTEGRATION=true \
  --dart-define=SUPABASE_ANON_KEY=<local anon key> \
  --dart-define=SUPABASE_SERVICE_ROLE_KEY=<local service-role key>
```

The test checks that the local function routes enforce authentication, anon
clients cannot read service queues, crawler-only work remains in review,
service work deduplicates, expired leases recover, identical enrichment output
reuses one staging row, rejection leaves live benefit/mapping counts unchanged,
and approval creates exactly one benefit and one mapping.

The deterministic HTML server binds only to loopback. The integration test uses
its exact fixture bytes and hashes to drive the real staging/approval RPCs. The
production official-issuer fetcher intentionally rejects loopback/private
addresses as an SSRF defense, so the served batch function must not be given the
loopback fixture URL or a test-only production bypass. A separate trusted HTTPS
fixture host would be required to exercise the fetch hop itself; ordinary unit
tests cover fetch and extraction behavior with injected transports.

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
