# Supabase integration tests

Tests in this directory require a **live local Supabase instance** — they
are never run as part of the regular unit-test suite in `test/features/...`.

A bare `flutter test` (no path argument) will discover and attempt to run
every `*_test.dart` file under `test/`, including these — and each will fail
immediately in `setUpAll` if no local Supabase instance is running, since
there is no `SUPABASE_ANON_KEY` and nothing listening at
`http://127.0.0.1:54321`.

To run these tests:

```bash
supabase start
flutter test test/supabase/ --dart-define=SUPABASE_ANON_KEY=<the anon key printed by supabase start>
```

To run only the pure-Dart unit suite (the common case, e.g. before a
commit), scope the invocation to exclude this directory:

```bash
flutter test test/features/
```
