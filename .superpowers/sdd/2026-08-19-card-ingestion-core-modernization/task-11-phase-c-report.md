# Task 11 Phase C — Admin decision parity and conflict-safe review

## Scope and safety

This slice implements only Phase C items 1–6 from `task-11-brief.md` against
shared baseline `c95d091`. It did not use Docker, a local or linked database,
the network, function serving, issuer crawling, or any live/production action.
It did not edit a migration, database schema, batch/discovery/shared source,
hosted integration harness, README, or `schema.sql`.

No database change was required. The existing staging `extracted_data`, diff,
and decision JSON retain the additional validation state, so the minimum schema
change is zero tables, columns, constraints, indexes, and migrations.

## Closure matrix

| Item | Closure | Proof |
| --- | --- | --- |
| 1. Conflict-safe review | Flutter disables and defensively rejects generic bulk Apply whenever a conflict exists. Repository bulk derivation no longer emits `keep_existing` plus approvals for every contradictory proposal. Edge v6 and rollback v5 require exactly one approve/edit/targeted-reject resolution for each proposed conflict group, unless the review is rejected globally. | Flutter repository/widget behavioral tests and Edge conflict-selection/v5 parity tests. |
| 2. Reject wire parity | Canonical reject targets serialize under `benefit`; current targets serialize under `current` and carry the exact live UUID; global rejection carries no target. Flutter refuses proposed-only rejection, and Edge v5/v6 rejects proposed-only or mixed targets instead of widening them globally. | Flutter wire/repository tests and Edge canonical/current/global/proposed-only matrix. |
| 3. Global target uniqueness | Flutter visible DTO repair and Edge presentation/approval validation enumerate every canonical and live target across additions, modifications, unchanged, removals, and conflicts before iterating staged decisions. Duplicate targets fail even when `benefit_decisions=[]` or the submitted action is a global reject. | Flutter empty-decision duplicate canonical/live test and Edge global-diff duplicate test. |
| 4. Full decision binding | Approval comparison binds canonical IDs, offer subject, title/description, taxonomy, flat commercial terms, structured config, restrictions, exclusions, partner/region scope, validity, and source identities. Edit comparison preserves every immutable field; only documented title, description, flat commercial-term, frequency/period, and validity edits reach canonical publication. Flutter now retains partner/region fields instead of dropping them. | Flutter staged-decision projection tests and Edge full projection/immutable edit tests; supported rate edit remains green. |
| 5. Reduced published audit rows | Published v6 approve/edit audit decisions require both the resolved live benefit UUID and dedupe key, while a SQL-shaped reduced row remains readable. | Flutter reduced-audit behavioral test. |
| 6. Task 9 regressions | Existing UUID/card/hash/privacy/auth/view/cursor/pagination/retirement and v5 tests remain in the full affected suites. | Flutter 44/44 and Edge admin 55/55, including the inherited Task 9 controls and new v5 parity case. |

## Red → green record

The required behavior was first exercised as behavioral failures:

- Flutter focused additions produced **0/6**: duplicate canonical/live targets
  with empty decisions were accepted; reduced published approval without a live
  UUID was accepted; proposed-only reject serialized; conflict bulk approval
  called the API; repository rejection acquired targets; and the bulk Apply UI
  remained enabled.
- Edge focused additions produced **0/3**: current/proposed/global rejection was
  not distinct, duplicate diff targets survived, and full commercial/source
  projection mutations survived.
- The explicit conflict test showed two contradictory approvals were accepted;
  an additional unresolved-control red showed `keep_existing` could complete a
  proposed conflict without selecting/editing/rejecting one proposal.
- A final Flutter parity red showed partner/region mutations passed because the
  client model did not retain either scope field.

After implementation and formatting, the fresh affected gates passed:

- `flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart`:
  **44/44**.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts`: **55/55**,
  including v5 rollback parity.
- `deno check --node-modules-dir=auto
  supabase/functions/admin-catalog-entry/index.ts
  supabase/functions/admin-catalog-entry/benefit_admin.ts`: pass, **2/2 files**.
- `deno fmt --check` for the owned Edge source/test: pass, **2/2 files**.
- `dart format` for the owned Flutter source/test: pass, **4/4 files**.
- `flutter analyze --no-pub --no-fatal-infos`: pass with the same **12**
  repository-baseline informational lints outside Phase C.
- `git diff --check`: pass.

The earlier fresh cross-slice credential-free gates after the Edge changes also
passed: movie repository **15/15**, batch/publication Deno suites **197/197**,
and active/admin/catalog/migration Node suites **89/89**. Phase C did not edit
those paths.

## Contract details

The client and Edge distinguish three rejection authorities:

- canonical proposal: exact staged projection under `benefit`;
- current row: exact diff row under `current` plus its live `benefit_id`;
- whole review: no proposal, current row, live ID, or dedupe key.

Conflict resolution counts only approve, edit, or canonical-target rejection
against the conflict's proposed keys. Current keep/reject is not a substitute
for resolving a contradictory proposed group. A global rejection remains the
explicit whole-review escape hatch.

The edit allowlist remains the existing documented Edge list: `title`,
`description`, `value`, `rate`, `cap`, `threshold`, `frequency`, `period`,
`effectiveFrom`, and `effectiveTo`. Taxonomy, canonical identity, offer subject,
structured config, restrictions, exclusions, partner/region scope, and source
identity cannot be client-edited.

## Review and deferred verification

An independent scoped review is to be dispatched by the Task 11 controller
against the Phase C commit; any findings will receive a focused fix round before
Task 11 completion. Real PostgreSQL/apply, hosted RPC/RLS behavior, deployment,
and live Edge/client verification remain in the guarded later Task 11/12 gates.
This slice makes no live verification claim.
