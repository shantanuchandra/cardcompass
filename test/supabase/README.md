# Supabase verification

This directory contains two different classes of tests. Keep their results
separate in release reports:

- JavaScript/MJS migration and contract tests are credential-free and run with
  `node --test`.
- Dart database tests require Supabase credentials. They are excluded from a
  credential-free result unless their live groups explicitly report a pass.

`benefit_enrichment_integration_test.dart` is the only guarded hosted
card-ingestion harness. It validates the already-applied PostgreSQL, REST, RPC,
RLS, active-view, staging, finalization, and rejection behavior. It does not
apply migrations, invoke or deploy an Edge Function, crawl an issuer, seed
reference data, reset a database, or run the production pilot.

## Credential-free checks

The hosted group is skipped unless every opt-in value is present. This command
therefore compiles the complete harness and runs its pure safety contracts, but
is not a hosted integration pass:

```bash
flutter test --no-pub test/supabase/benefit_enrichment_integration_test.dart
```

Run the full credential-free Supabase static suite from the repository root:

```bash
node --test --test-concurrency=1 \
  test/supabase/*_test.js \
  test/supabase/*.test.mjs
```

Three additional Dart tests are credential-free migration-source checks:

```bash
flutter test --no-pub \
  test/supabase/card_catalog_url_identity_test.dart \
  test/supabase/reset_cardcompass_data_test.dart \
  test/supabase/transaction_mcc_contract_test.dart
```

When reporting analyzer results, preserve the distinction between these two
commands:

```bash
flutter analyze --no-pub
flutter analyze --no-pub --no-fatal-infos
```

Strict analysis may exit 1 on the repository's existing informational lints.
The second command is the no-new-error gate; do not report it as a strict
analyzer pass.

## Guarded hosted card-ingestion harness

The one allowed target is:

- project name: `cardcompass`
- project ref: `prbcoxqobhjnnfnxevxf`
- URL: `https://prbcoxqobhjnnfnxevxf.supabase.co`

Do not run the harness until the release owner has completed the separate
read-only project/name check, migration-history audit, dry run, additive apply,
and post-apply database verification. A different ref, name, URL, or missing
explicit opt-in makes the live group skip before a client is created.

Create an untracked, mode-`0600` define file outside the repository. Do not put
keys in shell history and never commit this file:

```json
{
  "RUN_HOSTED_CARD_INGESTION_INTEGRATION": true,
  "SUPABASE_URL": "https://prbcoxqobhjnnfnxevxf.supabase.co",
  "SUPABASE_PROJECT_REF": "prbcoxqobhjnnfnxevxf",
  "SUPABASE_PROJECT_NAME": "cardcompass",
  "SUPABASE_ANON_KEY": "<cardcompass anon or publishable key>",
  "SUPABASE_SERVICE_ROLE_KEY": "<cardcompass service-role or secret key>"
}
```

The anon and service credentials must be distinct. The service credential is
used only inside this test process to create and remove exact fixtures and must
never be exposed to an app client.

Run exactly the one hosted harness:

```bash
flutter test --no-pub \
  test/supabase/benefit_enrichment_integration_test.dart \
  --dart-define-from-file=/absolute/private/path/cardcompass-hosted-test.json
```

Capture the generated run ID from failures and retain the full command result.
Do not run a broader `flutter test test/supabase/` with hosted credentials.

### Safety and cleanup contract

Each invocation generates a UTC-microsecond run ID plus 128 bits of secure
random entropy. The run ID is embedded in the issuer, card name, source URL,
benefit dedupe key, proposal key, and a hashed randomized confirmed auth email.
The harness first proves those markers are absent. Marker recovery is disabled
until that collision preflight succeeds.

Every returned card, benefit, mapping, enrichment-job, staging, URL-key, and
auth-user identity is recorded. If a database response is lost after a commit,
recovery queries use only the exact unique run markers, convert the results
into exact IDs, and then delete by those IDs. Auth recovery uses bounded admin
pagination, retains only the exact randomized email match, and deletes only its
returned ID. Dependency cleanup order is mapping, job, staging, URL key,
benefit, card, then the exact auth user. The final assertions require zero rows
for every recorded ID, every unique database marker, and the randomized Auth
email.

Claiming never uses the shared `benefits-v5` or `benefits-v6` lane. A
collision-checked randomized parser marker isolates the queue-wide claim RPC;
after the exact returned job ID is proven, only that recorded processing row is
updated to `benefits-v5` for the staging/rejection compatibility check.

Cleanup is best-effort across every exact step: recovery, each table in
dependency order, Auth deletion, residual diagnostics, and client disposal are
all attempted even when an earlier step fails. The test reports the aggregate
of labeled cleanup failures after those safe attempts finish.

The harness never deletes:

- rows created since a baseline timestamp;
- every discovery/crawler row found after a baseline scan;
- all staging rows for a parser version;
- a benefit selected only by a potentially pre-existing dedupe key;
- any row outside the current run's exact recorded IDs.

If marker ownership is ambiguous, cleanup fails closed. Do not compensate with
manual broad SQL. Investigate using the captured run ID and remove only IDs
whose ownership is independently proven.

## Excluded credentialed Dart tests

The credential-free commands above do not execute the live portions of these
files:

- `benefit_enrichment_integration_test.dart` (guarded hosted DB/RPC harness)
- `benefit_platform_confirmations_permissions_test.dart`
- `category_backfill_privileged_test.dart`
- `get_uncategorized_transactions_test.dart`
- `merchant_category_map_permissions_test.dart`
- `transactions_category_check_test.dart`
- `waitlist_security_contract_test.dart`

The latter six retain their older loopback-only support and are not part of the
hosted ingestion rollout. Never summarize a run with any credentialed live
group skipped as “all Supabase tests passed.”
