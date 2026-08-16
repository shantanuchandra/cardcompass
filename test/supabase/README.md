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
