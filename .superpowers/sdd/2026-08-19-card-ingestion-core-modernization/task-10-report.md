# Task 10 Report — Truthful Pilot Evidence and Operational Metrics

## Outcome

Task 10 is implemented without a schema or migration change. The current
`benefits-v6` pilot no longer qualifies from caller-written success booleans.
The worker computes replay, source-manifest, live-state, completeness,
suppression, conflict, and privacy evidence from the run that actually
executed. The Edge promotion path re-reads the cohort and fails closed before
calling the existing promotion RPC.

The gate now also rechecks the initializer's cohort invariants: exactly five
cards, all five distinct profiles, at least three case-normalized issuers, and
no pending, rejected, partially rejected, malformed, or unresolved review.
`staged` pilot work remains `running`; it does not unlock scheduled rollout.

Live applied: **no**.

## Computed evidence design

For a pilot run, the worker:

1. Captures bounded pre-run counts and canonical row hashes for the exact
   `card_catalog` card, its `card_benefit_mapping` rows, and mapped `benefits`.
2. Fetches each selected source once through the existing safe fetcher.
3. Retains at most nine immutable in-memory documents. Overflow throws instead
   of truncating verification input.
4. Runs two independent `benefits-v6` extractions over separate clones of that
   same retained snapshot.
5. Retains and hashes both independently produced canonical verification
   envelopes containing parser, job, card, run mode, source
   manifest/resources, the independently classified expected-required-source
   set, its explicit selection-overflow fact, and proposal order/terms.
6. Captures the same three live-table projections after processing and derives
   mutation count from their counts/hashes.
7. At qualification, re-reads current live rows and authoritative staging
   identity/status/decisions/proposals. Pre-publication and no-change rows must still
   match the post-run snapshot; reviewed material work must match its exact
   same-card/parser/content staging row and decision counts.
8. Recursively inspects persistable artifacts and retained envelopes for
   raw-body, statement/customer, credential, token, lease, signed-query, and
   secret-bearing fields. Cache validators are omitted from pilot evidence.

The bounded result is stored in existing
`card_catalog_enrichment_jobs.normalized_fields`:

- `pilot_profile` retains the database-validated initializer profile.
- `pilot_evidence` contains exact binding fields, both replay hashes and the
  separately retained envelopes, source manifest/attempts, the sorted expected
  required-source identities and
  `required_source_selection_overflow` fact, proposal
  disposition/staging identity,
  completeness, suppression/conflict counts, pre/post snapshots, computed
  mutation/privacy proof, and observation time.
- `operational_metrics` contains exact attempt/diff/action counts, rates,
  suppression reasons, replay/side-effect results, and processing time.

This location is intentional. The existing finalizer sanitizes
`result_summary` to an older allowlist, while `normalized_fields` already
persists a bounded object without requiring a new column. Backward-compatible
summary aliases remain for current consumers, but the pilot gate reads and
validates computed normalized evidence rather than trusting those aliases.

## Fail-closed boundary

`projectPilotJobEvidence` rejects:

- missing/extra evidence fields, unknown nested attempt fields, nonhex or
  uppercase hashes, strings in place of booleans, and negative/fractional or
  unbounded counts;
- cross-job, cross-card, cross-parser, cross-mode, and cross-source evidence;
- a primary logical source that does not hash to the job's exact canonical URL;
- a recomputed source manifest mismatch, missing decisive primary, failed or
  omitted required source, mismatch with the explicit expected-required-source
  set, required-source selection overflow, retry-history overflow, or incomplete
  crawl;
- a replay hash that cannot be recomputed from both bounded retained envelopes,
  or caller-written equal constants without those envelopes;
- replay mismatch, suppressed removals, proposal/catalog conflicts, missing
  conflict proof, live-state mutation, raw-body evidence, or future/unbounded
  timestamps;
- no-change with staging/review metadata, proposal-count/disposition mismatch,
  current pre-publication state that differs from the recorded post-run state,
  or staging identity/status/extracted proposals/decision totals that differ
  from the authoritative row;
- fewer/more than five cohort rows, duplicate/missing profiles, fewer than
  three issuers, pending review, quarantine, rejection, partial rejection, or
  malformed review totals.

The legacy `idempotency_passed`, `evidence_passed`,
`unsafe_mutation_count`, and `raw_body_stored` values cannot qualify a job by
themselves. `promoteQualifiedPilotJobs` calls `readPilotStatus` immediately
before the RPC and refuses promotion unless this computed gate is `passed`.

## Operational metrics and privacy

Metrics are derived from exact bounded data, not supplied totals:

- retry-aware fetch attempts, success, reusable `304`, blocked, missing,
  failed, incomplete, and history overflow;
- required supporting attempted/succeeded/failed/omitted and success rate;
- additions, modifications, removals, identity migrations, suppression count
  and `incomplete_crawl` reason;
- proposal and catalog identity conflicts;
- approvals, edits, proposal-index-zero-safe targeted rejects, global rejects,
  retirements, and retries;
- replay/side-effect booleans plus bounded UTC start/end/duration.

Admin presentation exposes the computed pilot proof and profile, sanitizes
metrics, derives review action totals from locked staging decisions, and
derives review age from staging timestamps. Structured logs include UUIDs,
bounded scalar metrics, and an allowlisted reason taxonomy only. Raw bodies,
customer/statement data, credentials, signed queries, access/refresh tokens,
and lease tokens are omitted.

## Edge-case coverage

- Same retained documents replay identically; deliberate order/term mutation
  fails.
- A real `processJob` pilot test proves one source fetch and persisted two-pass
  replay/live-state evidence.
- Complete zero-benefit/no-change remains representable by the existing
  completeness/removal tests.
- Required HTML/PDF/supporting failure remains incomplete; possible removals
  are suppressed and counted.
- Changed terms and shared legacy identities continue through the existing
  canonical diff/review tests.
- Any live card, mapped benefit, or mapping hash/count change fails proof;
  staging/audit-only writes are outside the live snapshot.
- The known-invalid/incomplete profile is a negative simulation until corrected
  and rerun; quarantine/incomplete state cannot count as one of five successes.
- Pending admin review cannot promote. A completed no-change observation may
  pass; a proposal-bearing completion needs valid positive review totals and
  zero rejection.
- Later scheduled no-change or material refreshes retain the immutable original
  pilot proof and original staging identity; mutable recurrence state cannot
  invalidate or replace it.

## Red-to-green evidence

Initial Task 10 RED checkpoints, before production edits:

```text
index pilot-focused                       12 passed, 4 failed
operational-metric focused                 0 passed, 1 failed
batch policy focused                       0 passed, 1 failed
admin pilot projection focused             0 passed, 1 failed
```

The failures were the expected missing replay/snapshot/boundary helpers,
self-attested metadata unlocking rollout, and absent admin evidence. Additional
negative checkpoints caught real implementation defects before their fixes:

```text
real pilot processing                      raw_body_stored self-marker false positive
retry-aware metrics                        compacted attempt history undercounted
source binding                             internally consistent foreign source qualified
evidence shape                             missing conflict proof defaulted to zero
privacy/time bounds                        signed query, nested credential, future attempt
attempt overflow                           history overflow survived the boundary
cohort gate                                one issuer / duplicate profile unlocked rollout
review gate                                pending staged work unlocked rollout
retained input bound                       ten documents were silently truncated
metric input bounds                        513-item/future-time inputs were normalized
admin malformed evidence                   boolean strings displayed as computed false
admin metric privacy                       non-UTC credential text survived a timestamp key
retained replay proof                      equal caller-written hashes had no recomputable envelope
required-source proof                      an entirely omitted required source vacuously passed
no-change/staging proof                    summary-only no-change ignored an attached staging row
current-state proof                        historical equal snapshots were not re-read from the DB
retained-envelope privacy                  credential text survived recomputed proposal evidence
authoritative staging proof                staged proposals differed from retained canonical proposals
scheduled recurrence proof                 later scheduled output invalidated immutable pilot evidence
required-source selection                  attempt-derived expectation allowed joint omission
required-source overflow                   capped required selection lacked an explicit blocker
review timestamp                           valid PostgreSQL UTC microseconds were rejected
```

The mandatory independent re-review found the recurrence, required-source,
staging-proposal, review-timestamp, and threat-boundary fixes complete and
returned **Ready to merge: Yes** with no critical or important findings.

Final prescribed command:

```sh
deno test --node-modules-dir=auto --allow-env \
  --allow-net=0.0.0.0:8000 --frozen \
  supabase/functions/benefit-enrichment-batch/index_test.ts \
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts
# 188 passed, 1 environment-permission failure
# Existing loopback auth test binds 127.0.0.1:0, which the prescribed
# 0.0.0.0:8000-only capability does not authorize.
```

The same full suites with only ephemeral loopback authorized:

```sh
deno test --node-modules-dir=auto --allow-env \
  --allow-net=127.0.0.1 --frozen \
  supabase/functions/benefit-enrichment-batch/index_test.ts \
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts
# 189 passed, 0 failed (140 ingestion + 49 admin)
```

Affected shared/policy suites:

```sh
deno test --node-modules-dir=auto --allow-env --frozen \
  supabase/functions/benefit-enrichment-batch/batch_policy_test.ts \
  supabase/functions/benefit-enrichment-batch/crawl_policy_test.ts \
  supabase/functions/benefit-enrichment-batch/supporting_documents_test.ts \
  supabase/functions/benefit-enrichment-batch/recurrence_policy_test.ts \
  supabase/functions/_shared/benefit_contract_test.ts \
  supabase/functions/_shared/catalog_identity_publication_test.ts
# 123 passed, 0 failed
```

Task 9 admin/consumer gates:

```sh
flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart
# 38 passed, 0 failed

flutter test --no-pub test/features/benefits/movie_deals/movie_deals_repository_test.dart
# 15 passed, 0 failed

node --test test/supabase/active_benefit_read_rules.test.mjs \
  test/supabase/admin_user_flag_migration_test.js \
  test/supabase/review_card_benefit_enrichment_v2_migration_test.js \
  test/supabase/publish_reviewed_card_identity_migration_test.js \
  test/supabase/card_catalog_enrichment_rules.test.mjs \
  test/supabase/issuer_card_discovery_rules.test.mjs
# 85 passed, 0 failed
```

Static verification:

```sh
deno check --node-modules-dir=auto --frozen \
  supabase/functions/benefit-enrichment-batch/index.ts \
  supabase/functions/benefit-enrichment-batch/batch_policy.ts \
  supabase/functions/admin-catalog-entry/index.ts \
  supabase/functions/admin-catalog-entry/benefit_admin.ts
# passed

deno fmt --check <eight changed TypeScript files>
# 8 checked, 0 failed

git diff --check
# passed

flutter analyze --no-pub --no-fatal-infos
# exit 0; same 12 pre-existing informational lints in unmodified service files
```

## Documentation

`docs/architecture/card-ingestion-modernization-review.md` now documents:

- depth-1 operator flow;
- depth-2 persisted evidence fields;
- depth-3 fail-closed gate algorithm;
- the five positive profiles plus separate incomplete-source negative phase;
- metric/privacy contracts, exact acceptance thresholds, and a rollout
  checklist;
- the remaining direct service-role SQL promotion residual.

## Schema, migration, and live-action decision

No migration was created or modified. `git diff -- supabase/migrations` is
empty. Relevant existing migration SHA-256 values remain:

```text
6cda51f2d52454e1535353c737a2a69eb046fcdb13d9cbfebf58fb14c62b6a32  supabase/migrations/20260819205037_recur_card_enrichment_jobs.sql
8e0dd3ac01346d5ec7531be906bc974480e0e93c8f8d9f482b6010323e06a3a7  supabase/migrations/20260819231435_publish_reviewed_card_identity.sql
82df4f501eb24f5e88be6080b66c5c296f95bb4d68a7cd4b5f3c1a44a015980e  supabase/migrations/20260819063836_add_admin_flag_to_public_users.sql
```

No Docker, local/linked/live Supabase/Postgres, external issuer/network,
production data/write, secret change, workflow dispatch, or live action was
used. The only network capability used by tests was an ephemeral
`127.0.0.1` loopback server owned by the existing admin auth test.

## Task 11 residual

The service-role-only SQL promotion RPC still validates legacy summary
booleans internally. The production Edge path now makes direct use unsafe and
unnecessary by computing and rechecking evidence first, but a future migration
should move equivalent computed-evidence validation into the locked RPC if
direct database callers must ever be supported. Until then, operators must
promote only through the Edge/API pre-gate.
Direct `service_role` fabrication of job/staging JSON is consequently outside
the trusted-worker threat model for this no-migration task, not a property the
Edge evidence format claims to prevent.
