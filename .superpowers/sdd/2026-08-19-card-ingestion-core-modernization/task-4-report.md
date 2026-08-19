# Task 4 implementation report

## Outcome

Implemented the schema-preserving v2 `approve_card_benefit_enrichment(uuid, uuid, jsonb)` transaction and the corresponding admin/card-diff boundaries. Publication now derives canonical SHA-256 card-scoped identity from the locked staging row's actual `card_id`, inserts immutable benefit versions, retires only an exact card+benefit mapping, and appends decisions/evidence atomically. No business table or column was added.

## Red proof

Before implementation:

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js`
  - 0 passed, 5 failed because no v2 migration existed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
  - type checking failed on the missing `sanitizeAdminDto` export and missing locked-card argument to v6 approval validation.

The migration was then generated locally with `supabase migration new review_card_benefit_enrichment_v2`; this created `20260819163046_review_card_benefit_enrichment_v2.sql` without contacting or mutating a Supabase project.

## Implemented contracts

- Locks the official staging row before status, parser, proposal, identity, or eligibility validation.
- Accepts only rollback-window `benefits-v5` and current `benefits-v6`; both publish through one server-canonical card-scoped path.
- Recomputes canonical terms, condition hash, and `card-benefit-v2:<locked-card-id>:<sha256>` key; v6 staged/client identity mismatch fails closed.
- Binds decisions by the locked proposal index/key, rejects duplicate/unknown/malformed proposal selections, and allows edits only to the explicit flat commercial field allowlist.
- Inserts benefit versions with `ON CONFLICT (dedupe_key) DO NOTHING`; it never updates the old benefit row or global `benefits.is_active`.
- Derives replacement mapping UUIDs from the locked staged diff and scopes every lifecycle update by both `card_id` and `benefit_id`, leaving another card's shared legacy row/mapping unchanged.
- Maps future replacements immediately, schedules only the old mapping at the future UTC `valid_from` boundary, and retires immediate/retroactive replacements at review time.
- Requires locked Task 3 `retirementEligible`/`retirementReason` evidence before a reviewed retirement.
- Serializes concurrent review on the staging row, returns an identical result for an identical payload replay, rejects other completed reviews, and rejects superseded staging.
- Appends bounded server-side source evidence and reviewed decisions without deleting history; completes the linked job and sets the temporary 30-day `next_run_at`.
- Keeps `SECURITY INVOKER`, fixed search path, and service-role-only execute grants with no `auth.role()` authorization.
- Recursively redacts URL credentials/query/fragment data in admin DTO scalar, list, nested value, and object-key positions while retaining raw locked evidence only on the server.
- Carries the existing live `benefits.benefit_id` UUID as `liveBenefitId` through current-benefit reconstruction and staged diffs.

## Green verification

- `node --test test/supabase/review_card_benefit_enrichment_v2_migration_test.js` — 5 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --allow-net=0.0.0.0:8000 --frozen supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — 21 passed, 0 failed.
- `deno test --node-modules-dir=auto --allow-env --frozen supabase/functions/benefit-enrichment-batch/index_test.ts` — 56 passed, 0 failed.
- `node --test test/supabase/benefit_enrichment_rules.test.mjs test/supabase/automated_benefit_enrichment_migration_test.js` — 29 passed, 0 failed.
- Total named behavioral/static tests: 111 passed, 0 failed.
- `deno check --node-modules-dir=auto` on all four changed TypeScript/test files — passed.
- `deno fmt --check` on all four changed TypeScript/test files — passed.
- `git diff --check` — passed.

No Docker, local PostgreSQL/Supabase, external network, production data, linked Supabase command, migration apply/push/dry-run, reset, repair, workflow, or secret operation was used.

## Files

- `supabase/migrations/20260819163046_review_card_benefit_enrichment_v2.sql`
- `test/supabase/review_card_benefit_enrichment_v2_migration_test.js`
- `supabase/functions/admin-catalog-entry/benefit_admin.ts`
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts`
- `supabase/functions/_shared/benefit_enrichment.ts`
- `supabase/functions/benefit-enrichment-batch/index_test.ts`

Migration SHA-256 before commit: `05b9837904aecc8fd082ae3da251bfe15f82f4856f8968cdcf19c8ddde2ce446`.

## Live gate

Live applied: **no**.

The exact-project read-only audit and ordered Task 2/3/4 migration parse/apply/lint/integration gates remain queued. The linked Supabase CLI control plane previously stalled at `Initialising login role...`; this task intentionally performed no live or network operation.
