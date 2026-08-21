# Task 11 Phase C — Admin decision parity and conflict-safe review

## Scope and safety

This slice implements Phase C items 1–6 from `task-11-brief.md` against shared
baseline `c95d091`, with controller-review fix round 1 based on `d8bc400`. It did
not use Docker, a local or linked database,
the external network, function serving, issuer crawling, or any
live/production action. The only network capability granted was the prescribed
`0.0.0.0:8000` loopback listener used by the credential-free auth fixture.
It did not edit a database schema, batch/discovery/shared source, hosted
integration harness, README, or `schema.sql`. Fix round 1 amended only the
locally unapplied Task 4 review function and its focused offline test so exact
conflict-current reject targets use the same locked lookup as Edge.

No database change was required. The existing staging `extracted_data`, diff,
and decision JSON retain the additional validation state, so the minimum schema
change is zero tables, columns, constraints, and indexes. No migration was
added; the existing locally unapplied Task 4 migration was amended and was not
executed by this slice.

## Closure matrix

| Item | Closure | Proof |
| --- | --- | --- |
| 1. Conflict-safe review | Flutter disables generic bulk Apply and provides a required per-group resolver. Every proposed conflict selects one exact unchanged proposal, edits one selected proposal, or rejects one proposed alternative; multiple groups submit together without an artificial edit. A current-only conflict requires one exact live-row rejection, while proposed conflicts may additionally audit-reject exact current rows. Global reject remains a separate action/endpoint. Repository validation rejects missing groups, multiple proposal resolutions, unscoped decisions, duplicate current UUIDs, and unresolved current-only groups before calling Edge. | Three-action, three-group and current-only widget tests; repository incomplete/multi-approve/current-target tests; Edge conflict-selection and endpoint tests. |
| 2. Reject wire parity | Canonical reject targets serialize under `benefit`; current targets serialize under `current` and carry the exact live UUID; global rejection carries no target. Flutter refuses proposed-only rejection. Edge v5/v6 now uses property presence, so present-but-null/empty/wrong-type target keys cannot widen into a global reject. | Flutter wire/repository tests and Edge property-presence canonical/current/global/proposed matrix. |
| 3. Global target uniqueness | Flutter visible DTO repair and Edge presentation/approval validation enumerate every canonical and live target across additions, modifications, unchanged, removals, and conflicts before iterating staged decisions. Duplicate targets fail even when `benefit_decisions=[]` or the submitted action is a global reject. | Flutter empty-decision duplicate canonical/live test and Edge global-diff duplicate test. |
| 4. Full decision binding | Approval comparison binds canonical IDs, offer subject, title/description, taxonomy, flat commercial terms, structured config, restrictions, exclusions, partner/region scope, validity, and source identities. Edit comparison preserves every immutable field; only documented title, description, flat commercial-term, frequency/period, and validity edits reach canonical publication. Flutter now retains partner/region fields instead of dropping them. | Flutter staged-decision projection tests and Edge full projection/immutable edit tests; supported rate edit remains green. |
| 5. Reduced published audit rows | Published v6 approve/edit audit decisions require both the resolved live benefit UUID and dedupe key. Edge preserves Task 4 `proposal_index`, `condition_hash`, and dedupe identity; Flutter binds terminal canonical rejects back to the exact staged proposal and reads current/global audit rows distinctly. | Flutter terminal SQL-shaped audit test, Edge presenter fixture, and Task 4 canonical/current/global audit assertions. |
| 6. Task 9 regressions | Existing UUID/card/hash/privacy/auth/view/cursor/pagination/retirement and v5 tests remain in the full affected suites. | Flutter 48/48 and Edge admin 59/59, including inherited Task 9 controls and v5 reject/current parity. |

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
- Controller review fix round 1 produced real reds for all four findings:
  the repository refused valid multi-group unchanged/targeted resolution while
  the UI had no resolver; null target properties widened into global rejection
  in v5/v6; Task 4 omitted conflict-current rows from its locked lookup; and the
  Edge presenter/Flutter DTO lost terminal canonical reject audit identity.
- A follow-up conflict-current red proved a current-only group could be skipped
  by Edge while Flutter rendered an unusable empty proposal selector and the
  repository refused its exact current UUID. The green path now requires and
  submits one exact live-row rejection without live mapping mutation.

After implementation and formatting, the fresh affected gates passed:

- `flutter test --no-pub test/features/admin/benefit_enrichment_review_test.dart`:
  **48/48**.
- `deno test --node-modules-dir=auto --allow-env
  --allow-net=0.0.0.0:8000 --frozen
  supabase/functions/admin-catalog-entry/benefit_admin_test.ts`: **59/59**,
  including v5 rollback parity.
- `node --test
  test/supabase/review_card_benefit_enrichment_v2_migration_test.js`:
  **16/16**.
- `deno check --node-modules-dir=auto
  supabase/functions/admin-catalog-entry/index.ts
  supabase/functions/admin-catalog-entry/benefit_admin.ts`: pass, **2/2 files**.
- `deno fmt --check` for the owned Edge source/test: pass, **2/2 files**.
- `dart format` for the owned Flutter source/test: pass, **4/4 files**.
- `flutter analyze --no-pub --no-fatal-infos`: pass with the same **12**
  repository-baseline informational lints outside Phase C.
- `git diff --check`: pass.

The final complete credential-free affected story also passed:

- shared + batch + admin + catalog Deno suites: **375/375**;
- Supabase/benefit/GTM Node suites: **306/306**.

## Contract details

The client and Edge distinguish three rejection authorities:

- canonical proposal: exact staged projection under `benefit`;
- current row: exact diff row under `current` plus its live `benefit_id`;
- whole review: no target object or canonical/live/dedupe/index/hash property.

For a conflict with proposed keys, resolution counts only approve, edit, or
canonical-target rejection against exactly one of those keys. A current-target
reject is an optional, separately scoped audit decision for that group. For a
current-only conflict, exactly one scoped current-target rejection is the
required resolution. Global rejection remains the explicit whole-review escape
hatch and is refused by the conflict-resolution endpoint.

The edit allowlist remains the existing documented Edge list: `title`,
`description`, `value`, `rate`, `cap`, `threshold`, `frequency`, `period`,
`effectiveFrom`, and `effectiveTo`. Taxonomy, canonical identity, offer subject,
structured config, restrictions, exclusions, partner/region scope, and source
identity cannot be client-edited.

## Task 4 migration hash

- `20260819163046_review_card_benefit_enrichment_v2.sql`:
  `67b26a48faa5cd49daf48e12d920b6b1501dbbf161fadd9b743cb2528b389d92`

This is a local source hash, not a remote migration-history claim.

## Review and deferred verification

Independent controller review round 1 reported four blockers. This fix round
closes all four with the red/green evidence above and awaits controller re-review.
Real PostgreSQL/apply, hosted RPC/RLS behavior, deployment, and live Edge/client
verification remain in the guarded later Task 11/12 gates. This slice makes no
live verification claim.
