# Task 11 Phase D Report — Guarded Hosted Integration Harness

Date: 2026-08-21

## Outcome

Phase D replaces the destructive local/Edge integration workflow with a
fail-closed hosted database harness for the single CardCompass project. The
harness validates already-applied REST, RPC, RLS, active-view, staging,
finalization, and rejection behavior only. It does not apply a migration,
deploy or invoke an Edge Function, crawl an issuer, reset or seed a database,
run a production pilot, or change `schema.sql`.

Live database/network execution in this phase: **none**. The hosted test remains
an explicit Task 11 Phase F gate after the guarded database apply.

## Red-to-green evidence

The first offline test run failed at compile time because the exact-hosted
configuration validator, deterministic run-ID builder, and ID-only fixture
ledger did not exist. After the first implementation, the focused test exposed
two concrete defects:

- the UTC run marker retained microseconds but accidentally dropped the
  millisecond component;
- one SHA-256 round constant was transposed, producing the wrong RPC identity
  hash.

Both were fixed from the failing literal expectations. A second red checkpoint
then required collision-gated marker recovery and a valid-length randomized
auth email. It failed because the recovery gate API did not exist; the original
email local part was also longer than 64 characters. The retained regressions
now prove recovery is disabled before a clear collision preflight and the email
is a short hash of the randomized run ID. A final response-loss red failed to
compile until a bounded paginated Auth lookup existed; its injected page loader
proves that only the case-normalized exact randomized email contributes a
recoverable ID.

A consolidated review then exposed a second benefit-marker gap: the staged
proposal uses its own dedupe key, but only the pre-created active benefit key
was collision-checked, recovered after a possible response loss, and asserted
absent after cleanup. Three injected regressions failed against no-op safety
boundaries: either occupied key was accepted, neither key contributed a
recoverable ID, and a proposal-key orphan passed the residue check. One shared
two-key contract now queries both exact keys at preflight, records only IDs
returned by each exact-key recovery query after the recovery gate opens, and
requires both keys to be absent after dependency-ordered ID cleanup.

Final focused offline result:

```text
flutter test --no-pub test/supabase/benefit_enrichment_integration_test.dart
12 passed, 0 failed, 1 hosted integration skipped with the exact missing-gate list
```

## Exact target and opt-in

The harness accepts only all of the following together:

- `RUN_HOSTED_CARD_INGESTION_INTEGRATION=true`
- `SUPABASE_URL=https://prbcoxqobhjnnfnxevxf.supabase.co`
- `SUPABASE_PROJECT_REF=prbcoxqobhjnnfnxevxf`
- `SUPABASE_PROJECT_NAME=cardcompass`
- nonempty, distinct anon/publishable and service-role/secret credentials

The URL validator rejects a different host, non-HTTPS scheme, explicit port,
userinfo, non-root path, query, or fragment. Without the complete contract, the
hosted group skips before any `SupabaseClient` is constructed.

## Fixture ownership and cleanup

Each live invocation will generate a UTC-microsecond marker plus 128 bits of
`Random.secure()` entropy. The marker scopes issuer, card, source URL, benefit
dedupe, proposal dedupe, evidence, and a hashed confirmed auth identity.

Before the first mutation, exact database-marker queries—including independent
queries for the active-benefit and staged-proposal dedupe keys—and a bounded
Auth admin scan for the exact randomized email prove there is no collision.
Only then is marker recovery enabled. Every returned card, benefit, mapping,
enrichment-job, staging, URL-key, and auth-user identity is recorded. If a
database response is lost after a commit, exact unique-marker queries recover
IDs; both benefit keys are recovered independently into that exact-ID ledger.
An Auth response loss is recovered through bounded pagination retaining only
the exact randomized email match. Recovery never deletes by a marker or email.
Deletes use only the recorded IDs in dependency order:

1. `card_benefit_mapping.mapping_id`
2. `card_catalog_enrichment_jobs.id`
3. `card_benefits_staging.id`
4. `card_catalog_url_keys.url_hash`
5. `benefits.benefit_id`
6. `card_catalog.id`
7. exact Auth user ID

Post-cleanup checks require no row for any recorded ID and no row for any exact
run marker, including the cascaded `public.users` identity. A marker collision
never enables recovery, so a pre-existing row cannot be adopted and deleted.

Review found that the claim RPC first performs parser-wide expired-lease work
before selecting a job. The hosted harness therefore never calls it with the
shared `benefits-v5`/`benefits-v6` parsers. It collision-checks a randomized
claim parser, inserts and claims the fixture there, proves the exact returned
job ID, then changes only that recorded processing row to `benefits-v5` under
its exact ID/status/lease token before staging.

Cleanup review also found that a sequential `finally` could stop after one
error. An injected offline regression now proves the cleanup coordinator
continues through all labeled exact steps and returns an aggregate failure only
after recovery, every dependency-ordered table deletion, Auth deletion,
residual diagnostics, and client disposal have been attempted.

Removed unsafe patterns include whole-table before/after ID snapshots,
since-baseline crawler deltas, all-rows-by-parser cleanup, dedupe-only benefit
deletion, and test-driven deletion/recreation of crawler review rows.

## Hosted semantics

The hosted path creates one randomized confirmed reviewer, credit-card row,
active benefit, mapping, and isolated-parser manual job. After claiming the
exact job, it transitions only that leased row to `benefits-v5`. It verifies:

- anonymous and authenticated clients cannot read the private queue or execute
  the claim RPC;
- authenticated consumers can read the fixture through
  `active_card_benefits`;
- service role can claim the exact manual job;
- `stage_card_benefit_enrichment` accepts a bounded official staging payload;
- `finalize_card_catalog_enrichment_job` binds the exact lease and staging row;
- `approve_card_benefit_enrichment` performs a global rejection and completes
  the linked staged job without publishing a new benefit.

No HTTP client or issuer fixture remains in the test, and the test never calls
`/functions/v1`.

## Documentation and exclusions

`test/supabase/README.md` now describes a secret-safe
`--dart-define-from-file` invocation, the exact project/ref/URL guard, the
pre-apply dependency on Task 11 Phase F, the ID-only cleanup contract, and the
credentialed test exclusions. It explicitly distinguishes a passing
credential-free harness compile/safety run from a hosted integration pass.

The documented analyzer contract is also exact: strict `flutter analyze
--no-pub` may exit 1 for repository baseline informational lints, while
`--no-fatal-infos` is only the passing no-new-error gate.

## Files

- `test/supabase/benefit_enrichment_integration_test.dart`
- `test/supabase/README.md`
- `.superpowers/sdd/2026-08-19-card-ingestion-core-modernization/task-11-phase-d-report.md`

`deno.lock`, migrations, production Edge/Flutter code, and `schema.sql` were not
changed by Phase D.

## Independent review

The first scoped review identified two safety issues before completion: the
claim RPC could perform parser-wide lease recovery in a shared parser lane,
and sequential cleanup could stop after the first failure. Both were repaired
with retained offline regressions. The fix-round review reported no critical,
important, or minor findings and marked Phase D ready for the later guarded
live gate. The later consolidated review identified the proposal-dedupe
coverage gap described above; its collision, recovery, and orphan-residue
regressions are now retained in the focused harness.

## Offline verification

```text
flutter analyze --no-pub test/supabase/benefit_enrichment_integration_test.dart
No issues found

flutter test --no-pub test/supabase/card_catalog_url_identity_test.dart \
  test/supabase/reset_cardcompass_data_test.dart \
  test/supabase/transaction_mcc_contract_test.dart
5 passed, 0 failed

node --test --test-concurrency=1 test/supabase/*_test.js \
  test/supabase/*.test.mjs
301 passed, 0 failed, 0 skipped
```

The originally copied `*.test.js` command matched no files under zsh because
this repository uses `*_test.js`. That shell failure ran zero tests; the README
and recorded passing command use the actual repository convention.
