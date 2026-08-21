# Task 11 Report — Consolidated Remediation and Guarded Live Verification

Date: 2026-08-21

## Outcome

The consolidated implementation and credential-free verification are complete
and independently review-clean. The guarded live database phase started only
after the exact linked target was proven to be `cardcompass`
(`prbcoxqobhjnnfnxevxf`). It is **partially applied and blocked**, not complete:

- `20260819112813_card_ingestion_lifecycle_hardening.sql` applied.
- `20260819122252_supersede_stale_benefit_staging.sql` applied.
- `20260819163046_review_card_benefit_enrichment_v2.sql` failed in an
  apply-time assertion and was rolled back.
- No later migration ran in that push.
- The Task 4 assertion was fixed and independently reviewed, but the next
  bounded linked dry run hung for 60 seconds at `Initialising login role`.
  It was terminated with exit 130 and no further write.

Per the Task 11 stop rule, no additional linked write was attempted. Hosted
RPC integration, advisors, two-session concurrency checks, `EXPLAIN`, and the
verified `schema.sql` dump remain pending until linked database access is
stable. Task 12 deployment, secrets, workflows, pilot traffic, and rollout
were not started.

## Consolidated closure

### Phase A — publication, completeness, and pilot residuals

- Flat comparison terms survive structured value-config projection.
- Composite scalar values fail before subset selection.
- Whole-array canonical duplicates fail before publication.
- Required terms/support/help links remain decisive crawl evidence.
- Single-token contextual person data fails at Edge and SQL boundaries while
  exact issuer/card identities remain allowed.
- Every Task 6 public helper has explicit ACL intent.
- Edge and Task 4 now share prefix/suffix `INR`, `Rs.`, and `₹` numeric
  normalization without rewriting nonnumeric prose.

Phase A final follow-up: `04291ee`; independent review clean.

### Phase B — lifecycle and issuer discovery

- Lifecycle semantics ignore transport-only churn but bind source identity.
- Wrapped or quoted foreign-card subjects cannot discontinue the target.
- Only the exact durable issuer anchor shape can be quarantined.
- Deadline checks occur after awaited pages and before mutation.
- Producer history uses deterministic keyset pagination.
- Quarantine episodes deduplicate concurrently and version after Retry.
- Persisted fence reason drives response accounting.
- Legacy pre-episode quarantine stays wholly legacy: producer `episode` and
  staged `episode_identity` are both null, so Task 7 Retry/Reject remains
  actionable and replay is write-free.

Phase B final follow-up: `55ff41b`; independent review clean.

### Phase C — admin decision parity

- Conflicts disable generic bulk Apply and require an exact per-group action.
- Canonical, current, and global rejects use distinct fail-closed wire shapes.
- Canonical/live target uniqueness is checked even with empty staged decisions.
- Decisions bind the full immutable commercial/source projection; only the
  documented material edit fields vary.
- Reduced published approve/edit audits require live UUID plus dedupe key.
- V5 parity, presenter null padding, nested/top-level aliases, and all carrier
  combinations fail closed without breaking normal presenter output.

Phase C final follow-up: `8e17a47`; independent review clean.

### Phase D — hosted harness

- Exact ref/name/URL and explicit opt-in are mandatory.
- Run/parser/auth fixtures are collision-gated and unique.
- Cleanup is exact-ID-led, dependency ordered, and attempts every step.
- Both active and staged-proposal benefit dedupe keys are independently
  preflighted, recovered into the exact ledger, deleted by ID, and checked for
  residue.
- The claim RPC uses a randomized isolated parser before one exact leased row
  transitions to v5.

Phase D final follow-up: `cdeb249`; independent review clean. The hosted test
remained explicitly skipped because the full database migration set is not yet
applied.

## Phase E — fresh credential-free verification

Run from combined HEAD before the guarded live attempt:

```text
Deno shared/batch/admin/catalog: 380 passed, 0 failed
Node Supabase/benefit/GTM:       307 passed, 0 failed
Flutter admin:                    54 passed, 0 failed
Flutter analyzer:                 exit 0, 12 existing informational lints
Hosted harness safety:            12 passed, hosted group skipped
Movie repository:                 15 passed, 0 failed
git diff --check:                 passed
```

The final consolidated reviewer reported CLEAN after independently repeating
the same cross-slice gates.

## Guarded live evidence

### Exact target

```text
linked ref: prbcoxqobhjnnfnxevxf
project:    cardcompass
status:     ACTIVE_HEALTHY
database:   PostgreSQL 17
```

### Read-only inventory and audit

`supabase migration list --linked` showed every migration through
`20260819063836` applied and the Task 11 chain unapplied. It also exposed two
local files sharing version `20260817020000`. A read-only history query proved
the remote version is named `card_discovery_queue`. The unrelated movie-benefit
correction was moved to the unique forward version
`20260821060017_movie_benefit_platform_and_cap_corrections_forward.sql`; no
history repair or rewrite was used. The live movie rows were already in the
correct District/cap state, so the forward update remains idempotent.

The read-only audit completed. Relevant release observations included:

- 186 current catalog rows;
- 499 benefit rows (493 object exclusions, 6 legacy arrays);
- no active user card on a discontinued catalog row;
- no benefit mapped to multiple cards;
- no duplicate mapping or submitted/final URL-key conflict;
- one normalization-only catalog collision: AU `Zenith` and `Zenith+`, which
  are distinct products and URLs.

The pre-write dry run listed exactly these six migrations:

```text
20260819112813_card_ingestion_lifecycle_hardening.sql
20260819122252_supersede_stale_benefit_staging.sql
20260819163046_review_card_benefit_enrichment_v2.sql
20260819205037_recur_card_enrichment_jobs.sql
20260819231435_publish_reviewed_card_identity.sql
20260821060017_movie_benefit_platform_and_cap_corrections_forward.sql
```

No pending migration contains `pg_cron`, workflow enablement, secret mutation,
or external HTTP scheduling.

### Apply failure and recovery state

The push applied the first two migrations, then PostgreSQL rejected Task 4's
array-boundary assertion because `generate_series` output had no explicit
`value` alias. The Task 4 transaction rolled back. Commit `8905ab4` aliases
both series as `AS item(value)` and retains a red-to-green migration test;
Task 4 passed 18/18 and independent review was clean. Current Task 4 SHA-256 is
listed below.

The immediately following guarded dry run did not reach a migration prompt or
execute SQL. It hung for 60 seconds at login-role initialization and was
terminated. The CLI advised supplying `SUPABASE_DB_PASSWORD`; no credential was
invented, printed, or changed.

## Migration hashes

```text
20260819112813  0be0ce483cc1610e85fe4059e7317c1d93bff90230b1834bc6c698f8b46ffc5d
20260819122252  e294fd029a2aaf30ce98764b44ce41652b8e02d19783618111cb0d3754ea2876
20260819163046  9fed09b8e2f450e981a07a758ef7c6a740b985be2223a44fa50d59455f960cd0
20260819205037  6789a78b7e3dff9008623fae2de2a1446ee1369aa2a3c018f8ece3ef6bee3ba2
20260819231435  bc4518cd4ba5ca1e9000ad07cf36cb7b2a667bedba520eee8efaf2d17f2b0dc9
20260821060017  0376d136fa11a2ef62f73d293ba710e8207e1075e0ecfbfdf26f93b28de56626
admin flag      82df4f501eb24f5e88be6080b66c5c296f95bb4d68a7cd4b5f3c1a44a015980e
```

## Exact continuation gate

Do not run Task 12. Restore a stable linked PostgreSQL credential/control-plane
path, then repeat the exact project guard and:

1. `supabase migration list --linked` — confirm only Task4, Task6, Task7, and
   the forward correction remain pending.
2. `supabase db push --linked --dry-run` — require that exact four-file list.
3. Apply, then run lint/advisors/RPC/RLS/ACL/two-session/active-view/v5/
   run-scoped hosted cleanup/`EXPLAIN` verification.
4. Dump verified `public` schema to `schema.sql` with no data or secrets.

Task 11 remains blocked until those steps complete.
