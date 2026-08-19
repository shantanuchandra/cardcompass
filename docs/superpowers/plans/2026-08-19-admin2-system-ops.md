# Admin2 System Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the founder-operator a bounded System workspace for pipeline health, single-job recovery, and one worker-enforced pause control.

**Architecture:** The admin gateway derives health from existing job tables and exposes only allowlisted mutations. PostgreSQL owns the runtime control and its atomic audit receipt; the benefit-enrichment worker checks that control before scheduled work. Manual and pilot runs remain available for controlled recovery.

**Tech Stack:** Flutter/Riverpod, Supabase Edge Functions/Deno, PostgreSQL, Node contract tests.

**Spec:** `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-08-19-admin2-foundation.md` and `docs/superpowers/plans/2026-08-19-admin2-inbox-card-data.md` first.
- V1 exposes exactly one runtime control: `benefit_enrichment_scheduled`.
- A pause affects only scheduled orchestration; authenticated pilot and manual recovery paths remain explicit.
- Every mutation requires `request_id`, an observed version, and a server-confirmed audit receipt.
- The API returns sanitized failure categories, never provider payloads, fetched documents, secrets, or unrestricted logs.
- Job actions target one job. Bulk retries and arbitrary configuration are excluded.

---

## File structure

- `supabase/migrations/20260819090200_admin_runtime_controls.sql` — named control and atomic audited mutation.
- `test/supabase/admin_runtime_controls_migration_test.js` — service-only and idempotency contract.
- `supabase/functions/admin-operator/system.ts` — status, history, single-job, and control handlers.
- `supabase/functions/admin-operator/system_test.ts` — sanitization, validation, and partial-source tests.
- `supabase/functions/admin-operator/router.ts` — System action registration.
- `supabase/functions/benefit-enrichment-batch/index.ts` — scheduled control check.
- `supabase/functions/benefit-enrichment-batch/index_test.ts` — paused scheduled-run tests.
- `lib/features/admin2/system/system_models.dart` — typed summaries, jobs, and controls.
- `lib/features/admin2/system/system_repository.dart` — gateway adapter.
- `lib/features/admin2/system/system_section.dart` — health and recovery UI.
- `lib/features/admin2/inbox/action_inbox_section.dart` — critical paused-pipeline item support.
- `test/features/admin2/system_repository_test.dart` — request and DTO contracts.
- `test/features/admin2/system_section_test.dart` — confirmation and refresh behavior.

---

### Task 1: Add the service-only runtime control

**Files:**
- Create: `supabase/migrations/20260819090200_admin_runtime_controls.sql`
- Create: `test/supabase/admin_runtime_controls_migration_test.js`

**Interfaces:**
- Produces table `public.admin_runtime_controls` with one seeded key.
- Produces RPC `public.admin_set_runtime_control(uuid, uuid, text, boolean, text, timestamptz): jsonb`.

- [ ] **Step 1: Write the failing migration contract**

```js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090200_admin_runtime_controls.sql',
  import.meta.url,
);

test('runtime controls are named, audited and service-only', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  assert.match(sql, /create table public\.admin_runtime_controls/);
  assert.match(sql, /check \(control_key in \('benefit_enrichment_scheduled'\)\)/);
  assert.match(sql, /insert into public\.admin_runtime_controls/);
  assert.match(sql, /create or replace function public\.admin_set_runtime_control/);
  assert.match(sql, /for update/);
  assert.match(sql, /insert into public\.admin_audit_log/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on public\.admin_runtime_controls from public, anon, authenticated/);
  assert.match(sql, /grant execute on function public\.admin_set_runtime_control[\s\S]*to service_role/);
});
```

- [ ] **Step 2: Run the focused contract**

Run: `node --test test/supabase/admin_runtime_controls_migration_test.js`

Expected: FAIL with `ENOENT`.

- [ ] **Step 3: Implement the named control and atomic receipt**

Create the table with `control_key text primary key`, `is_paused boolean not null default false`, `reason text`, `updated_by uuid references auth.users(id)`, and `updated_at timestamptz not null default now()`. Seed `benefit_enrichment_scheduled` with `ON CONFLICT DO NOTHING`, enable RLS, and revoke browser access.

Implement the RPC with this validation and locking contract:

```sql
if _control_key <> 'benefit_enrichment_scheduled'
   or _actor_id is null or _request_id is null
   or length(trim(coalesce(_reason, ''))) < 2 then
  raise exception 'invalid_request';
end if;

select to_jsonb(control) into prior_result
from public.admin_audit_log as log
cross join lateral jsonb_to_record(log.details -> 'result') as control(
  control_key text, is_paused boolean, updated_at timestamptz
)
where log.actor_id = _actor_id and log.request_id = _request_id;
if found then return prior_result; end if;

select updated_at into current_updated_at
from public.admin_runtime_controls
where control_key = _control_key
for update;
if not found then raise exception 'not_found'; end if;
if _observed_updated_at is null or current_updated_at <> _observed_updated_at then
  raise exception 'state_conflict';
end if;
```

Then update the row, build a bounded result containing only the key, paused state, reason, and new timestamp, and insert `system.control.pause` or `system.control.resume` into `admin_audit_log` in the same transaction.

- [ ] **Step 4: Run migration contracts**

Run: `node --test test/supabase/admin_operator_foundation_migration_test.js test/supabase/admin_runtime_controls_migration_test.js`

Expected: PASS.

- [ ] **Step 5: Commit the runtime control with its code consumer in Task 2**

Do not commit this documentation-only state. Include these files in the Task 2 code commit.

### Task 2: Make scheduled benefit enrichment honor the control

**Files:**
- Modify: `supabase/functions/benefit-enrichment-batch/index.ts`
- Modify: `supabase/functions/benefit-enrichment-batch/index_test.ts`
- Add from Task 1: migration and contract test.

**Interfaces:**
- Produces `scheduledPipelinePaused(db, "benefit_enrichment_scheduled"): Promise<boolean>`.
- Changes only the `mode === "scheduled"` branch.

- [ ] **Step 1: Add failing worker tests**

Add tests proving:

```ts
Deno.test("scheduled runs return paused before seeding or claiming jobs", async () => {
  const calls: string[] = [];
  const response = await handleBenefitEnrichmentBatch(
    scheduledRequest(),
    batchDependencies({
      runtimeControl: { is_paused: true },
      onTable: (name) => calls.push(name),
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { status: "paused", control: "benefit_enrichment_scheduled" });
  assertEquals(calls.includes("card_catalog_enrichment_jobs"), false);
});

Deno.test("pilot runs ignore the scheduled-only pause", async () => {
  const response = await handleBenefitEnrichmentBatch(
    pilotRequest(),
    batchDependencies({ runtimeControl: { is_paused: true } }),
  );
  assertEquals(response.status, 200);
});
```

Keep `scheduledRequest`, `pilotRequest`, and `batchDependencies` in the existing test helper section and give each a concrete `Request`/dependency return type.

- [ ] **Step 2: Run the focused worker tests**

Run: `deno test --config supabase/functions/benefit-enrichment-batch/deno.json supabase/functions/benefit-enrichment-batch/index_test.ts`

Expected: FAIL because scheduled orchestration does not read the control.

- [ ] **Step 3: Add a fail-closed scheduled check**

Implement:

```ts
export async function scheduledPipelinePaused(
  db: UntypedSupabaseClient,
  controlKey: "benefit_enrichment_scheduled",
): Promise<boolean> {
  const { data, error } = await db.from("admin_runtime_controls")
    .select("is_paused").eq("control_key", controlKey).single();
  if (error || typeof data?.is_paused !== "boolean") {
    throw new Error("runtime_control_unavailable");
  }
  return data.is_paused;
}
```

Call it after scheduled authorization and before inventory, seeding, or job claims. Return the stable paused response when true. Map an unreadable control to a safe `503` rather than silently running.

- [ ] **Step 4: Run worker and migration tests**

Run: `deno test --config supabase/functions/benefit-enrichment-batch/deno.json supabase/functions/benefit-enrichment-batch/index_test.ts && node --test test/supabase/admin_runtime_controls_migration_test.js`

Expected: PASS.

- [ ] **Step 5: Commit the first functional system change**

```bash
git add supabase/migrations/20260819090200_admin_runtime_controls.sql test/supabase/admin_runtime_controls_migration_test.js supabase/functions/benefit-enrichment-batch/index.ts supabase/functions/benefit-enrichment-batch/index_test.ts docs/superpowers/plans/2026-08-19-admin2-system-ops.md
git commit -m "feat(admin2): add scheduled pipeline control"
```

### Task 3: Add sanitized System gateway actions

**Files:**
- Create: `supabase/functions/admin-operator/system.ts`
- Create: `supabase/functions/admin-operator/system_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`

**Interfaces:**
- `system-status` returns bounded pipeline summaries and named controls.
- `system-jobs` returns one paginated, allowlisted job family.
- `system-retry`, `system-quarantine`, and `system-control` invoke existing atomic RPCs.

- [ ] **Step 1: Write failing status and mutation tests**

Test that status remains usable when one source fails, raw result/provider fields are absent, job family is one of `benefit_enrichment|card_discovery`, retry/quarantine delegates to `admin_card_data_action`, and control mutation delegates to `admin_set_runtime_control` with the authenticated actor.

- [ ] **Step 2: Run the focused test**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/system_test.ts`

Expected: FAIL because `system.ts` does not exist.

- [ ] **Step 3: Implement exact DTOs and validators**

Define these exported types in `system.ts`:

```ts
export type PipelineSummary = Readonly<{
  key: "benefit_enrichment" | "card_discovery";
  status: "healthy" | "degraded" | "paused" | "unknown";
  queued: number;
  running: number;
  failed: number;
  quarantined: number;
  last_success_at: string | null;
  source_error: "source_unavailable" | null;
}>;

export type SystemJobDto = Readonly<{
  id: string;
  family: "benefit_enrichment" | "card_discovery";
  status: string;
  failure_category: string | null;
  attempt_count: number;
  next_retry_at: string | null;
  updated_at: string;
}>;
```

Use explicit `select(...)`, `range(offset, offset + limit - 1)`, a maximum limit of 50, and presenters that construct only these fields. Register handlers in a single immutable registry export:

```ts
export const systemActionHandlers: Readonly<Record<string, AdminActionHandler>> = {
  "system-status": handleSystemStatus,
  "system-jobs": handleSystemJobs,
  "system-retry": handleSystemRetry,
  "system-quarantine": handleSystemQuarantine,
  "system-control": handleSystemControl,
};
```

Merge that registry into `router.ts`; do not mutate an imported `const` registry.

- [ ] **Step 4: Run all gateway tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/`

Expected: PASS.

- [ ] **Step 5: Commit the System API**

```bash
git add supabase/functions/admin-operator/system.ts supabase/functions/admin-operator/system_test.ts supabase/functions/admin-operator/router.ts
git commit -m "feat(admin2): expose safe system operations"
```

### Task 4: Build the System workspace

**Files:**
- Create: `lib/features/admin2/system/system_models.dart`
- Create: `lib/features/admin2/system/system_repository.dart`
- Create: `lib/features/admin2/system/system_section.dart`
- Modify: `lib/features/admin2/screens/admin_operator_screen.dart`
- Create: `test/features/admin2/system_repository_test.dart`
- Create: `test/features/admin2/system_section_test.dart`

- [ ] **Step 1: Write failing model, repository, and widget tests**

Cover strict DTO decoding, persisted content during refresh, last-refreshed display, a required reason and confirmation for quarantine/pause, disabled buttons while submitting, and server-confirmed refresh after success.

- [ ] **Step 2: Run the focused Flutter tests**

Run: `flutter test test/features/admin2/system_repository_test.dart test/features/admin2/system_section_test.dart`

Expected: FAIL because the System feature files do not exist.

- [ ] **Step 3: Implement typed models and the repository**

Use sealed `SystemMutation` values for `retryJob`, `quarantineJob`, `unquarantineJob`, `pauseControl`, and `resumeControl`. The repository must generate a UUID request ID per user action, reuse it only for retrying the same network request, and include `observed_updated_at`.

- [ ] **Step 4: Implement the responsive section**

Show health cards, the explicit runtime control, and a paginated job table/list. Open a detail/confirmation surface before mutation; never mutate from the row itself. Replace the System placeholder in `AdminOperatorScreen`.

- [ ] **Step 5: Run focused Flutter tests**

Run: `flutter test test/features/admin2/system_repository_test.dart test/features/admin2/system_section_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the System UI**

```bash
git add lib/features/admin2/system lib/features/admin2/screens/admin_operator_screen.dart test/features/admin2/system_repository_test.dart test/features/admin2/system_section_test.dart
git commit -m "feat(admin2): add system operations workspace"
```

### Task 5: Surface a disabled pipeline in the Action Inbox

**Files:**
- Modify: `supabase/functions/admin-operator/inbox.ts`
- Modify: `supabase/functions/admin-operator/inbox_test.ts`
- Modify: `lib/features/admin2/inbox/action_inbox_section.dart`
- Modify: `test/features/admin2/action_inbox_test.dart`

- [ ] **Step 1: Add failing inbox tests**

Assert that a paused control with actionable queued jobs creates one `critical` item with destination `system`, while a paused empty pipeline creates no actionable item.

- [ ] **Step 2: Run focused tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/inbox_test.ts && flutter test test/features/admin2/action_inbox_test.dart`

Expected: FAIL on the new source.

- [ ] **Step 3: Add the derived item and deep link**

Use item key `system:benefit_enrichment_scheduled:paused`, deterministic critical rank, sanitized queued count, and route state selecting the System control. Keep partial-source failure behavior.

- [ ] **Step 4: Re-run focused tests and commit**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/inbox_test.ts && flutter test test/features/admin2/action_inbox_test.dart`

Expected: PASS.

```bash
git add supabase/functions/admin-operator/inbox.ts supabase/functions/admin-operator/inbox_test.ts lib/features/admin2/inbox/action_inbox_section.dart test/features/admin2/action_inbox_test.dart
git commit -m "feat(admin2): surface paused pipelines in inbox"
```

### Task 6: Verify the System phase

- [ ] **Step 1: Format changed code**

Run: `dart format lib/features/admin2/system lib/features/admin2/inbox test/features/admin2 && deno fmt supabase/functions/admin-operator supabase/functions/benefit-enrichment-batch`

Expected: formatters exit 0.

- [ ] **Step 2: Run static checks**

Run: `flutter analyze && deno check --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/index.ts && deno check --config supabase/functions/benefit-enrichment-batch/deno.json supabase/functions/benefit-enrichment-batch/index.ts`

Expected: no issues.

- [ ] **Step 3: Run complete test suites**

Run: `flutter test && node --test test/supabase/*.js && deno test --allow-env --allow-net --allow-read supabase/functions`

Expected: all tests pass; existing opt-in integration skips remain documented.

- [ ] **Step 4: Inspect the final diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only intentional System-phase changes remain.
