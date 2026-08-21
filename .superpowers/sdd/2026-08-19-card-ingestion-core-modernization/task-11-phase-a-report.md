# Task 11 Phase A — Benefit publication and pilot residuals

## Scope and safety

This slice implements only Phase A items 1–7 from `task-11-brief.md` against
baseline `5d4c10f`. It did not use Docker, a local or linked database, the
network, function serving, or any production action. The two amended migrations
were locally unapplied inputs; they were not executed by this slice. No business
table or column changed.

## Closure matrix

| Item | Closure | Proof |
| --- | --- | --- |
| 1. Flat comparison terms | Comparison identities always retain `value`, `rate`, `cap`, `threshold`, `frequency`, and `period`, including alongside structured config. Persisted legacy movie aliases reconstruct the same flat projection, so unchanged percent/BOGO rows remain unchanged while 5→10 remains a material modification. | New shared behavioral test; inherited identical percent/BOGO controls. |
| 2. Composite scalar config | Edge and SQL now inspect every scalar `valueConfig` entry in the whole locked proposal array, including unselected proposals. Objects/arrays fail; the documented `restrictions` array and `exclusions` object remain valid. | New Edge field-matrix behavioral test; Task4 apply-time unselected object/array assertions. |
| 3. Duplicate locked targets | Edge and Task4 project every locked raw proposal to its parser-specific canonical publication condition, normalizing flat terms, category aliases, commercial config, term arrays, exclusions, semantic key, and validity, then reject duplicate targets before subset validation or mutation. V5 ignores the optional non-published `offerSubject` lane. The SQL numeric candidate now uses one named global currency-marker contract matching Edge for prefix/suffix INR, Rs., and ₹ forms in config and flat lanes while unrelated prose retains its original normalized text. | Edge v5 behavior; shared prefix/suffix/prose controls; Task4 twelve-variant apply-time whole-array assertion; focused migration regression. |
| 4. Required sources | No new production change was necessary. Task10 already retains/fetches central `/support/...terms.pdf`, unsafe/invalid required links, functional-query resources, budget/depth/deadline failures, and explicit selection overflow. Missing required evidence keeps completeness false. | Existing `supporting_documents_test.ts`: 33/33, including central support, rejected query, exact functional query, priority, budget/depth/deadline, and overflow cases. |
| 5. Single-token privacy | Edge and SQL contextual-person detection now accept zero continuation tokens after the first name token. Lowercase, mixed-case, and Unicode examples fail closed; exact issuer/card labels and `cardholders` remain allowed. | Shared behavioral test and Task6 apply-time privacy assertions. |
| 6. Task6 ACL residual | Both missing helper signatures receive explicit `REVOKE ... FROM PUBLIC, anon, authenticated` and service-only `GRANT`. An apply-time ACL inventory covers every Task6 public signature and distinguishes two trigger-only helpers. | Task6 focused migration regression and `$task6_acl_assertions$`. |
| 7. Task10 regressions | Required-source, replay, functional-query, timestamp, pilot, and recurrence suites remain in the affected gates. | Supporting 33/33; Task6 Node 16/16; integrated shared + batch + supporting 210/210. |

## Red → green record

The required production behavior was first exercised as failing tests:

- Shared comparison/privacy: **0/2**, with 5→10 mislabeled as identity migration
  and lowercase single-token context retained.
- Admin locked-array scalar matrix: **0/1**, with an object-valued unselected
  scalar surviving validation.
- Task4/Task6 focused migration tests: **0/2**, with no locked canonical-target
  check, no zero-continuation SQL privacy behavior, and no complete ACL intent.
- Independent review red: a v5 duplicate with a distinct optional
  `offerSubject` was accepted (**0/1**) and the SQL trim-parity fixture would
  abort apply. The Edge test passed after its parser-specific projection fix;
  the strengthened apply-time SQL fixture now covers alias/case/edge-space,
  duplicate-term, null, and numeric-string normalization.
- Consolidated review red: SQL's prefix-only currency expression failed the
  focused parity contract (**0/1**) while the shared Edge controls passed.
  SQL now globally removes currency markers only from its numeric parse
  candidate; twelve prefix/suffix config/flat locked-array variants collapse to
  the numeric targets, while `first purchase` and `10 INR bonus` stay prose.

After implementation:

- `benefit_enrichment_test.ts`: **3/3**.
- Inherited identical v6/percent/BOGO comparison controls: **3/3**.
- `supporting_documents_test.ts`: **33/33**.
- `benefit_admin_test.ts`: **62/62**.
- Fresh no-network recheck at the consolidated-review HEAD: all three affected
  locked-proposal/admin cases passed **3/3**. The wider admin command passed
  **61/62** before the sole unrelated loopback-auth case was permission-denied;
  no loopback listener was permitted under this slice's no-network constraint.
- Task4 + Task6 Node migration suites: **33/33**.
- Deno check: **4/4 files**; Deno format check: **5/5 files**;
  scoped `git diff --check`: pass.

After the concurrent Phase-B owner stabilized its owned issuer paths, the fresh
integrated shared + batch + supporting gate passed **210/210**. Phase A did not
edit or commit the concurrent Phase-B files.

The earlier independent fix round was clean before consolidated review exposed
the suffix-currency residual. The residual is now covered by the focused red and
the current full gates above. PostgreSQL apply remains intentionally deferred.

## Migration hashes

- `20260819163046_review_card_benefit_enrichment_v2.sql`:
  `72dbddb0db4df682ce007a32a026cf5bb8cc6f8595b82b4bb61884393119c23f`
- `20260819205037_recur_card_enrichment_jobs.sql`:
  `6789a78b7e3dff9008623fae2de2a1446ee1369aa2a3c018f8ece3ef6bee3ba2`

These hashes are local source hashes, not remote migration-history claims.

## Function signatures and ACL intent

Task4 adds one public invoker/immutable helper with fixed
`search_path = public, pg_temp`:

- `canonical_locked_benefit_condition(jsonb,text)`: revoke `PUBLIC`, `anon`,
  and `authenticated`; grant `service_role`.

Task6's exhaustive apply-time inventory asserts no `anon` or `authenticated`
execute privilege on any created public function. The 32 internal callable
signatures are granted only to `service_role`:

```text
card_enrichment_jitter_days(uuid,integer)
canonical_card_enrichment_timestamp(text)
card_enrichment_pilot_timestamp(text)
next_card_enrichment_observation_at(uuid,text,boolean,boolean,text)
bounded_card_enrichment_timestamp(text,timestamptz)
sanitize_card_enrichment_source_attempt(jsonb,timestamptz)
sanitize_card_enrichment_observation(jsonb,timestamptz)
normalize_card_enrichment_observation_history(jsonb,jsonb,timestamptz)
sanitize_card_enrichment_result_summary(jsonb)
card_has_unresolved_catalog_identity(uuid,text)
card_enrichment_job_has_pending_staging(uuid,uuid,text)
card_enrichment_requeue_action(text,text,timestamptz,timestamptz,boolean,boolean)
card_enrichment_pilot_job_is_qualified(text,text,jsonb)
card_enrichment_enqueue_catalog_eligible(uuid,text,text,text,text,text,text,boolean,boolean,boolean)
card_enrichment_enqueue_count_is_valid(integer,integer)
enforce_card_benefit_enrichment_identity()
enqueue_card_benefit_enrichment_jobs(jsonb)
card_enrichment_pilot_cohort_action(integer,integer,boolean)
initialize_card_benefit_enrichment_pilot(jsonb,text)
card_enrichment_pilot_snapshot_rows(jsonb)
card_enrichment_pilot_live_state_snapshot(uuid)
card_enrichment_pilot_source_identity_hash(text)
card_enrichment_pilot_queryless_display_url(text)
card_enrichment_pilot_has_contextual_person(text,jsonb)
card_enrichment_pilot_source_manifest_hash(jsonb)
card_enrichment_pilot_evidence_is_qualified(card_catalog_enrichment_jobs,card_benefits_staging)
promote_qualified_card_benefit_enrichment_pilot(text)
requeue_due_card_catalog_enrichment_jobs(text,integer,timestamptz)
claim_card_catalog_enrichment_jobs(integer,integer,text,text)
card_enrichment_effective_terminal_status(text,boolean)
card_enrichment_final_staging_state(text,uuid,uuid,uuid,text,boolean)
finalize_card_catalog_enrichment_job(uuid,uuid,text,uuid,text,jsonb,jsonb,text,timestamptz)
```

The trigger-only signatures are revoked from all three client roles and are not
granted to `service_role`:

- `schedule_terminal_card_enrichment_observation()`
- `capture_card_enrichment_pilot_publication_snapshot()`

## Deferred verification

Real PostgreSQL parsing, apply-time self-assertions, direct role execution,
privilege catalog inspection, and migration-history/hash verification remain in
Task11's guarded hosted database phases. This Phase-A slice deliberately makes
no live verification claim.
