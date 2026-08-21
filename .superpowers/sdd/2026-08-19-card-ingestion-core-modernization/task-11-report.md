# Task 11 Report — Hosted Migration and Concurrency Gate Complete

Date: 2026-08-21

## Outcome

Task 11 is **complete**. The exact hosted project `cardcompass`
(`prbcoxqobhjnnfnxevxf`) contains every local migration through
`20260821153000`; the final dry run reports `Remote database is up to date`.
The guarded hosted harness passed the required isolated two-session
publication/enqueue, review locking, retry/quarantine, lease/finalizer,
rollback, and deadlock matrix with zero fixture residue. `schema.sql` is a
fresh schema-only PostgreSQL 17 dump of `public`.

Task 12 is no longer blocked by the database concurrency gate. Task 12 itself
has not started: no Edge function, client, workflow, schedule, or pilot traffic
was deployed or enabled by this work.

No Docker/local Supabase, reset, seed, migration-history repair, broad cleanup,
Edge deployment, issuer crawl, secret mutation, workflow dispatch, pilot
traffic, or Task 12 rollout action was used.

## Consolidated implementation

The Phase A–D remediation commits remain intact:

- Phase A publication/completeness/privacy: `04291ee`.
- Phase B lifecycle/issuer state: `55ff41b`.
- Phase C admin decision parity: `8e17a47`.
- Phase D safe hosted harness: `cdeb249`.

The combined implementation preserves the staged-review-publication boundary,
card-scoped benefit identities, exact reject/edit/retire targets, bounded public
evidence, retryable issuer quarantine episodes, run-scoped hosted fixtures, and
exact-ID-led cleanup.

## Guarded target and connection evidence

```text
project name: cardcompass
project ref:  prbcoxqobhjnnfnxevxf
project URL:  https://prbcoxqobhjnnfnxevxf.supabase.co
status:       ACTIVE_HEALTHY
database:     PostgreSQL 17.6
```

The direct IPv6 endpoint was unreachable on the current network and the
session-pooler endpoint timed out. The transaction pooler at port 6543 was
reachable. PostgreSQL commands used ordinary simple queries. Supabase CLI
validation used `default_query_exec_mode=simple_protocol`, which is required
because transaction pooling does not support prepared statements. The password
came from the user's untracked define file and was never committed or included
in captured output.

## Migration apply and recovery

The initial linked push applied the first two migrations and then stopped at
Task 4. Every later failed attempt was transactional and left neither schema nor
history residue.

Before the affected migrations were installed, real PostgreSQL preflights found
and the repository fixed:

- Task 4 JSONB subtraction needed an explicit text operator and parentheses.
- Task 6 pilot variables were undeclared; trigger-only helper ACLs retained a
  stale service grant; timestamp/history assertions used stale serialization.
- Task 7 needed CASE parentheses and post-advisory row-lock audit positions.

Task 4, Task 6, Task 7, and the forward movie correction were then applied one
at a time through `psql`, each as one transaction containing both the exact
migration SQL and its `supabase_migrations.schema_migrations` row. This was an
ordinary additive migration apply, not migration repair. Each file first passed
a rollback-only PostgreSQL preflight.

Post-apply lint exercised lazily checked PL/pgSQL paths and exposed four runtime
definition defects. Because the source migrations were already installed, each
was repaired with a new forward migration:

- `20260821130000_fix_ingestion_function_operator_precedence.sql`
- `20260821131500_fix_catalog_identity_lifecycle_reference.sql`
- `20260821133000_fix_catalog_identity_alias_conflict_target.sql`
- `20260821134500_fix_catalog_identity_block_qualification.sql`

Security advisors then found policies on two tables whose RLS flag was disabled.
`20260821140000_enable_user_owned_table_rls.sql` validated the existing exact
owner policies and enabled RLS on `user_cards` and
`statement_milestone_cache`.

The isolated concurrency rehearsal then found three defects that sequential
and static lock-order checks could not expose:

- title-cased strong networks were stripped before lowercasing (`Visa` became
  `isa`);
- the page-move conflict check evaluated effective-network logic on unrelated
  same-issuer rows before narrowing to the destination product family;
- a publication waiter acquired the advisory lock but evaluated replay against
  its pre-lock job/review snapshot.

Each defect was repaired with an additive forward migration. The migrations
normalize case before filtering, materialize the exact product-family candidate
set before evaluating strong identity, and refresh immutable publication replay
state immediately after the advisory lock:

- `20260821150000_fix_card_catalog_network_case_normalization.sql`
- `20260821151500_fix_catalog_identity_conflict_candidate_scope.sql`
- `20260821153000_fix_catalog_publication_post_lock_replay.sql`

Each migration passed a rollback-only PostgreSQL preflight and was applied as
one transaction together with its exact migration-history row. The transaction
pooler rejected one CLI prepared-statement attempt before SQL execution; the
ledger confirmed no partial migration, and the established simple-query psql
path completed the atomic apply.

Final migration history contains one matching local/remote entry for every
migration. The final CLI dry run through the transaction pooler returned:

```text
DRY RUN: migrations will not be pushed to the database.
Remote database is up to date.
```

## Hosted behavioral verification

The final guarded harness was run after all forward fixes and RLS enablement:

```text
17 passed, 0 failed
```

It proved the exact project guard, collision-free randomized fixtures, Auth and
table RLS, queue claim/staging/finalization RPCs, v5 compatibility, approval,
rejection, active benefit reads, exact benefit/mapping identity, and aggregate
best-effort cleanup. It also ran real isolated two-session interleavings behind
a transaction-scoped advisory-lock holder that was deliberately rolled back:

- two Task 4 finalizer calls produced exactly one terminal mutation and one
  stale-lease result;
- two identical Task 4 reviewed decisions produced one retained decision;
- a rolled-back Task 7 publication probe left no mutation, and two identical
  page-move publications produced one review audit, both old and new URL keys,
  append-only provenance, and exactly one v6 job;
- two competing Retry calls for each of two immutable quarantine episodes
  produced one audit per episode and the expected final producer fence.

Every waiter completed inside a bounded timeout; no deadlock or orphaned lock
holder remained. Final assertions found no rows for any run-owned card, benefit,
mapping, enrichment job, staging row, URL key, provenance row, discovery job,
catalog review, catalog-review audit, public user, Auth user, unique marker, or
either benefit dedupe key.

The authenticated RLS matrix was also checked directly with an existing JWT
subject: anon saw zero rows, authenticated saw six own `user_cards`, and saw
zero cross-user rows. No customer identifier was printed.

The repository's executable migration contract and the hosted two-session
matrix now agree on the Task 3/4/6/7 lock order and idempotency boundaries.

## Audit, lint, advisors, and query plan

The read-only ingestion audit completed after the final apply. Relevant facts:

- 186 catalog rows;
- 499 benefit rows (493 object exclusions and 6 retained legacy arrays);
- 906 enrichment jobs and 21 pending staging rows;
- zero active user cards on discontinued catalog rows;
- zero orphan or duplicate mappings;
- zero benefits mapped to multiple cards;
- zero submitted/final URL-key conflicts;
- 182 legacy catalog URLs without new provenance;
- one known normalization-only AU `Zenith`/`Zenith+` pair, with distinct product
  names and URLs.

`supabase db lint --level error` reports zero errors. Warning-level lint retains
only volatility and unused-variable diagnostics; there is no unresolved SQL
compile/runtime error.

Security/performance advisors report zero errors. Nine warnings remain: six
legacy `auth_rls_initplan` recommendations and three pre-existing mutable
`search_path` recommendations. They do not broaden the new ingestion RPC or RLS
write boundaries and are retained as follow-up optimization/hardening work.

A representative issuer-anchor scan used six shared buffer hits, no reads,
returned in 6.241 ms, and planned in 0.913 ms. No new index is justified at the
current retained history size.

## Verified schema snapshot

`schema.sql` was regenerated with PostgreSQL 17.10 from the verified live
PostgreSQL 17.6 `public` schema using `--schema-only --no-owner`.

```text
11,959 lines
494,849 bytes
0 COPY statements
0 INSERT statements
0 credential/JWT literals
```

The snapshot intentionally contains effective functions, tables, views,
constraints, indexes, triggers, policies, RLS flags, grants, and default ACLs.
Migrations remain the source of truth.

## Final verification

```text
Node Supabase/GTM contracts:       317 passed, 0 failed
Deno shared/batch/admin/catalog:   380 passed, 0 failed
Flutter admin:                      54 passed, 0 failed
Flutter movie repository:           15 passed, 0 failed
Dart DB-source static contracts:      5 passed, 0 failed
Guarded hosted harness:              17 passed, 0 failed
Deno production checks:               5 passed
Flutter analyze --no-fatal-infos: exit 0; 12 pre-existing info lints
git diff --check:                 passed
```

The generated `pg_dump` form exposed one stale static assertion that recognized
only handwritten `CREATE TABLE IF NOT EXISTS user_cards`; the test now accepts
both qualified pg_dump and legacy forms while still forbidding PAN/expiry
storage.

## Installed migration hashes

```text
20260819112813  0be0ce483cc1610e85fe4059e7317c1d93bff90230b1834bc6c698f8b46ffc5d
20260819122252  e294fd029a2aaf30ce98764b44ce41652b8e02d19783618111cb0d3754ea2876
20260819163046  6138b2b10c97ecf51a3f377e72f3fceb385cbd8a4f33e89e2b7a1f977d6cb80d
20260819205037  7f90b54bbe80ce7931f3df66590dff5216b1e97d356561f8259fbe0b23ad31c5
20260819231435  d62a110d9f1549bbad0c398850073429f24521b5c227000b4c49cbfa6a3cc684
20260821060017  0376d136fa11a2ef62f73d293ba710e8207e1075e0ecfbfdf26f93b28de56626
20260821130000  e196d15c9b7591372ec391dba712348478196db290bbd0dfe2cab35347533ca5
20260821131500  1be99eade03927af0165235ea3c7a06a2173cbc1174d09a8c952bace35a96675
20260821133000  48e2c1c7c2d2e4fbfc1bba5be69f4668622cb1f0c4ffd98c4b060a79105a3708
20260821134500  0a01aac1a62a911965e9485af224e868ef96604ebd0e5e1347ba840e71dd547e
20260821140000  5d2a5ad5226ef804036e0f72efbc36da33cb9993ccec9eb4ce2098960e3263ad
20260821150000  d3bab7b7758f28e50f7536e70444271b3f427eee835ceeef94e940bcbe375bf9
20260821151500  84bc7fdaa34a359bea65d558f28866d9a07314a68a80c1e1c65f2f1edaec12ec
20260821153000  ddfcae4d6fef835741c947c12bb63206aa7dcbef2fe48534dc395e97ac32029e
```

## Rollout boundary

Task 11 did not deploy code or enable schedules. Its required database gate is
now recorded as passed. Task 12 may dark-deploy the already-reviewed Edge code
with schedules disabled and run the manual allowlisted smoke test, following
its separate rollout/approval boundary for secrets, workflows, schedules,
pilot traffic, and ramp decisions.
