# Admin2 Action Inbox and Card Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first useful admin workflow: a ranked Action Inbox backed by the existing card-identity and benefit-enrichment queues, plus complete card-data review inside `/app/admin2`.

**Architecture:** The new gateway presents typed, sanitized card-data DTOs while the old and new endpoints share the existing locked catalog-resolution paths. One service-only PostgreSQL function applies each approved mutation and inserts its `admin_audit_log` receipt in the same transaction; reads remain derived from authoritative queue tables.

**Tech Stack:** Flutter/Riverpod, Supabase Edge Functions/Deno, PostgreSQL, existing `card_catalog_review_queue`, `card_discovery_jobs`, `card_catalog_enrichment_jobs`, and `card_benefits_staging` tables.

**Spec:** `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-08-19-admin2-foundation.md` first.
- Bulk approval, arbitrary table updates, and optimistic mutations remain prohibited.
- Inbox items are derived; this plan does not add an inbox table or manual dismissal.
- The old `/app/admin/catalog-review` route and `admin-catalog-entry` endpoint remain functional.
- Every list is paginated, every mutation includes `request_id`, and stale states return `state_conflict`.
- Official source URLs and bounded evidence may be returned; raw fetched pages, statement text, secrets, and provider responses may not.

---

## File structure

- `supabase/migrations/20260819090100_admin_card_data_operations.sql` — atomic audited identity/benefit mutation wrapper.
- `test/supabase/admin_card_data_operations_migration_test.js` — wrapper/grant/idempotency contract.
- `supabase/functions/admin-operator/card_data.ts` — list/present/mutate handlers.
- `supabase/functions/admin-operator/inbox.ts` — deterministic severity mapping and bounded merge.
- `supabase/functions/admin-operator/card_data_test.ts` — DTO and mutation validation tests.
- `supabase/functions/admin-operator/inbox_test.ts` — ordering and partial-source tests.
- `supabase/functions/admin-operator/router.ts` — registers `card-review-list`, `card-review-action`, and `inbox-list`.
- `lib/features/admin2/card_data/card_data_models.dart` — typed lane, item, evidence, page, and action types.
- `lib/features/admin2/card_data/card_data_repository.dart` — card gateway adapter.
- `lib/features/admin2/card_data/card_data_section.dart` — filters and list/detail review UI.
- `lib/features/admin2/inbox/inbox_models.dart` — typed ranked item.
- `lib/features/admin2/inbox/inbox_repository.dart` — inbox adapter.
- `lib/features/admin2/inbox/action_inbox_section.dart` — priority list and navigation.
- `lib/features/admin2/screens/admin_operator_screen.dart` — replaces the two relevant placeholders.
- `test/features/admin2/card_data_repository_test.dart` — mapping and request contract.
- `test/features/admin2/card_data_section_test.dart` — review behavior.
- `test/features/admin2/action_inbox_test.dart` — ranking, partial failure, and navigation.

---

### Task 1: Add one atomic audited card-data mutation RPC

**Files:**
- Create: `supabase/migrations/20260819090100_admin_card_data_operations.sql`
- Create: `test/supabase/admin_card_data_operations_migration_test.js`

**Interfaces:**
- Consumes: existing `review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)`, `approve_card_benefit_enrichment(uuid, uuid, jsonb)`, and `admin_audit_log`.
- Produces: `public.admin_card_data_action(uuid, uuid, text, text, uuid, uuid, jsonb, text, timestamptz): jsonb`.

- [ ] **Step 1: Write the failing static security contract**

```js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090100_admin_card_data_operations.sql',
  import.meta.url,
);

test('card data actions are allowlisted, idempotent and service-only', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  assert.match(sql, /create or replace function public\.admin_card_data_action/);
  assert.match(sql, /_lane not in \('identity', 'benefit'\)/);
  assert.match(sql, /_operation not in \('approve', 'edit_approve', 'merge', 'reject', 'retry', 'quarantine', 'unquarantine'\)/);
  assert.match(sql, /from public\.admin_audit_log/);
  assert.match(sql, /insert into public\.admin_audit_log/);
  assert.match(sql, /for update/);
  assert.match(sql, /security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function public\.admin_card_data_action/);
  assert.match(sql, /grant execute on function public\.admin_card_data_action[\s\S]*to service_role/);
});
```

- [ ] **Step 2: Run the test and verify the migration is missing**

Run: `node --test test/supabase/admin_card_data_operations_migration_test.js`

Expected: FAIL with `ENOENT`.

- [ ] **Step 3: Implement the transactional wrapper**

Create the function with this signature and control flow:

```sql
create or replace function public.admin_card_data_action(
  _actor_id uuid,
  _request_id uuid,
  _lane text,
  _operation text,
  _target_id uuid,
  _staging_id uuid default null,
  _payload jsonb default '{}'::jsonb,
  _reason text default null,
  _observed_updated_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_result jsonb;
  result jsonb;
  current_updated_at timestamptz;
begin
  if _actor_id is null or _request_id is null or _target_id is null then
    raise exception 'invalid_request';
  end if;
  if _lane not in ('identity', 'benefit') then
    raise exception 'invalid_request';
  end if;
  if _operation not in (
    'approve', 'edit_approve', 'merge', 'reject',
    'retry', 'quarantine', 'unquarantine'
  ) then
    raise exception 'invalid_request';
  end if;

  select details -> 'result' into prior_result
  from public.admin_audit_log
  where actor_id = _actor_id and request_id = _request_id;
  if found then return coalesce(prior_result, '{}'::jsonb); end if;

  if _lane = 'identity' then
    if _operation in ('quarantine', 'unquarantine') then
      raise exception 'invalid_request';
    end if;
    select updated_at into current_updated_at
    from public.card_catalog_review_queue
    where id = _target_id
    for update;
    if current_updated_at is null then raise exception 'not_found'; end if;
    if _observed_updated_at is not null and current_updated_at <> _observed_updated_at then
      raise exception 'state_conflict';
    end if;
    select to_jsonb(resolution) into result
    from public.review_card_catalog_discovery(
      _target_id,
      _actor_id,
      _operation,
      nullif(_payload -> 'proposed_fields', 'null'::jsonb),
      nullif(_payload ->> 'merge_card_id', '')::uuid,
      _reason
    ) as resolution;
  else
    select updated_at into current_updated_at
    from public.card_catalog_enrichment_jobs
    where id = _target_id and parser_version <> 'catalog-v1'
    for update;
    if current_updated_at is null then raise exception 'not_found'; end if;
    if _observed_updated_at is not null and current_updated_at <> _observed_updated_at then
      raise exception 'state_conflict';
    end if;

    if _operation in ('approve', 'edit_approve', 'reject') then
      if _staging_id is null or jsonb_typeof(_payload -> 'decisions') <> 'array' then
        raise exception 'invalid_request';
      end if;
      select to_jsonb(resolution) into result
      from public.approve_card_benefit_enrichment(
        _staging_id, _actor_id, _payload -> 'decisions'
      ) as resolution;
    elsif _operation = 'retry' then
      update public.card_catalog_enrichment_jobs
      set status = 'queued', failure_category = null, next_retry_at = now(),
          lease_token = null, lease_expires_at = null, updated_at = now()
      where id = _target_id
        and status in ('failed', 'review_required', 'quarantined')
        and parser_version <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := jsonb_build_object('job_id', _target_id, 'resulting_status', 'queued');
    elsif _operation = 'quarantine' then
      if length(trim(coalesce(_reason, ''))) < 2 then raise exception 'reason_required'; end if;
      update public.card_catalog_enrichment_jobs
      set status = 'quarantined', failure_category = 'manual_quarantine',
          next_retry_at = null, lease_token = null, lease_expires_at = null,
          result_summary = coalesce(result_summary, '{}'::jsonb) ||
            jsonb_build_object('quarantine_reason', left(trim(_reason), 500)),
          updated_at = now()
      where id = _target_id and status not in ('completed', 'quarantined')
        and parser_version <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := jsonb_build_object('job_id', _target_id, 'resulting_status', 'quarantined');
    else
      update public.card_catalog_enrichment_jobs
      set status = 'queued', failure_category = null, next_retry_at = now(),
          lease_token = null, lease_expires_at = null, updated_at = now()
      where id = _target_id and status = 'quarantined'
        and parser_version <> 'catalog-v1';
      if not found then raise exception 'state_conflict'; end if;
      result := jsonb_build_object('job_id', _target_id, 'resulting_status', 'queued');
    end if;
  end if;

  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, reason,
    request_id, outcome, details
  ) values (
    _actor_id, 'card_data.' || _lane || '.' || _operation,
    _lane || '_review', _target_id::text, nullif(trim(_reason), ''),
    _request_id, 'succeeded', jsonb_build_object('result', result)
  );
  return result;
end;
$$;

revoke all on function public.admin_card_data_action(
  uuid, uuid, text, text, uuid, uuid, jsonb, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.admin_card_data_action(
  uuid, uuid, text, text, uuid, uuid, jsonb, text, timestamptz
) to service_role;
```

Also constrain benefit `reject` payload decisions to the `reject` action in the Edge validator; the underlying approval RPC derives a rejected staging status when every decision is rejected.

- [ ] **Step 4: Run migration contracts**

Run: `node --test test/supabase/admin_operator_foundation_migration_test.js test/supabase/admin_card_data_operations_migration_test.js test/supabase/automated_benefit_enrichment_migration_test.js`

Expected: PASS.

- [ ] **Step 5: Commit the atomic operation**

```bash
git add supabase/migrations/20260819090100_admin_card_data_operations.sql test/supabase/admin_card_data_operations_migration_test.js
git commit -m "feat(admin2): audit card data operations atomically"
```

### Task 2: Add sanitized Card Data gateway actions

**Files:**
- Create: `supabase/functions/admin-operator/card_data.ts`
- Create: `supabase/functions/admin-operator/card_data_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`

**Interfaces:**
- Consumes: `AdminActionContext` and `admin_card_data_action` from Task 1.
- Produces: `card-review-list` and `card-review-action` handlers with `lane: identity|benefit`.

- [ ] **Step 1: Write failing handler tests**

```ts
const identityRows = [{
  id: "11111111-1111-4111-8111-111111111111",
  status: "pending",
  source_evidence: { official_url: "https://issuer.example/card", raw_body: "excluded" },
  updated_at: "2026-08-19T09:00:00Z",
}];

function fakeContext(rows: unknown[]): AdminActionContext {
  const db = {
    from: (_table: string) => createReadQueryForRows(rows),
    rpc: (_name: string, _args: Record<string, unknown>) =>
      Promise.resolve({ data: {}, error: null }),
  };
  return {
    actor: { id: "admin-1" },
    requestId: null,
    db: db as AdminActionContext["db"],
  };
}

Deno.test("card list returns only bounded identity fields", async () => {
  const output = await handleCardReviewList(
    { lane: "identity", page: 1, limit: 25, status: "pending" },
    fakeContext(identityRows),
  );
  assertEquals(output.items[0].source_evidence.raw_body, undefined);
  assertEquals(output.page, 1);
  assertEquals(output.has_more, false);
});

Deno.test("card mutation requires request id and observed timestamp", async () => {
  await assertRejects(
    () => handleCardReviewAction(
      { lane: "benefit", operation: "retry", target_id: "job-1" },
      fakeContext([]),
    ),
    AdminHttpError,
    "invalid_request",
  );
});
```

Define `createReadQueryForRows` in the test file as the concrete chain used by the identity and benefit list queries (`select`, `eq`, `order`, and `range`), returning `{data: rows, error: null}` at `range`. This helper contains no production behavior.

- [ ] **Step 2: Run the test and verify failure**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/card_data_test.ts`

Expected: FAIL because the handlers do not exist.

- [ ] **Step 3: Implement lane-specific queries, presenters, and mutation validation**

```ts
function requiredUuid(value: unknown): string {
  const text = typeof value === "string" ? value : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)) {
    throw new AdminHttpError("invalid_request", 400);
  }
  return text;
}

function optionalUuid(value: unknown): string | null {
  return value == null ? null : requiredUuid(value);
}

function requiredTimestamp(value: unknown): string {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    throw new AdminHttpError("invalid_request", 400);
  }
  return value;
}

function safeCardActionPayload(body: Record<string, unknown>): Record<string, unknown> {
  return {
    proposed_fields: body.proposed_fields ?? null,
    merge_card_id: body.merge_card_id ?? null,
    decisions: body.decisions ?? null,
  };
}

function mapDatabaseError(error: { message?: string }): AdminHttpError {
  const code = ["invalid_request", "not_found", "state_conflict", "reason_required"]
    .find((candidate) => error.message?.includes(candidate)) ?? "request_failed";
  const status = code === "not_found" ? 404
    : code === "state_conflict" ? 409
    : code === "request_failed" ? 500
    : 400;
  return new AdminHttpError(code, status);
}

export async function handleCardReviewAction(body: Record<string, unknown>, context: AdminActionContext) {
  const lane = body.lane;
  const operation = body.operation;
  const targetId = requiredUuid(body.target_id);
  const requestId = requiredUuid(body.request_id);
  const observed = requiredTimestamp(body.observed_updated_at);
  if (lane !== "identity" && lane !== "benefit") {
    throw new AdminHttpError("invalid_request", 400);
  }
  if (!["approve", "edit_approve", "merge", "reject", "retry", "quarantine", "unquarantine"].includes(String(operation))) {
    throw new AdminHttpError("invalid_request", 400);
  }
  const reason = typeof body.reason === "string" ? body.reason.trim() : null;
  if (["reject", "quarantine"].includes(String(operation)) && (!reason || reason.length < 2)) {
    throw new AdminHttpError("invalid_request", 400);
  }
  const { data, error } = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
    _request_id: requestId,
    _lane: lane,
    _operation: operation,
    _target_id: targetId,
    _staging_id: optionalUuid(body.staging_id),
    _payload: safeCardActionPayload(body),
    _reason: reason,
    _observed_updated_at: observed,
  });
  if (error) throw mapDatabaseError(error);
  return { result: data };
}
```

`safeCardActionPayload` must also reject serialized payloads above 32 KiB. For identity actions it permits only `proposed_fields` and `merge_card_id`; for benefit actions it permits only `decisions` and validates each decision action as `approve|edit|reject|keep_existing`. Reject lane/operation combinations that the SQL branch does not implement.

Identity list selects at most `limit + 1` rows from `card_catalog_review_queue` joined to `card_discovery_jobs`. Benefit list delegates to the existing `presentBenefitJob` projection from `admin-catalog-entry/benefit_admin.ts`, retaining its raw-body and secret exclusions. Clamp `page` to `1..10000` and `limit` to `1..50`.

Export the Card Data registry and merge it immutably in `router.ts`:

```ts
// card_data.ts
export const cardDataActionHandlers: Readonly<Record<string, AdminActionHandler>> = {
  "card-review-list": handleCardReviewList,
  "card-review-action": handleCardReviewAction,
};

// router.ts
import { accessActionHandlers } from "./access.ts";
import { cardDataActionHandlers } from "./card_data.ts";
export const actionHandlers = Object.freeze({
  ...accessActionHandlers,
  ...cardDataActionHandlers,
});
```

- [ ] **Step 4: Run new and legacy card review tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/card_data_test.ts && deno test --node-modules-dir=auto --allow-env --allow-read --allow-net supabase/functions/admin-catalog-entry/`

Expected: PASS with identical locked resolution behavior and sanitized DTOs.

- [ ] **Step 5: Commit the gateway actions**

```bash
git add supabase/functions/admin-operator/card_data.ts supabase/functions/admin-operator/card_data_test.ts supabase/functions/admin-operator/router.ts
git commit -m "feat(admin2): expose card review gateway"
```

### Task 3: Derive and rank the card-data Action Inbox

**Files:**
- Create: `supabase/functions/admin-operator/inbox.ts`
- Create: `supabase/functions/admin-operator/inbox_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`

**Interfaces:**
- Consumes: pending identity reviews and staged/failed/review-required/quarantined benefit jobs.
- Produces: `InboxItem` with `id`, `type`, `severity`, `title`, `explanation`, `source_status`, `age_seconds`, and `destination`.

- [ ] **Step 1: Write failing deterministic ranking tests**

```ts
Deno.test("inbox ranks customer blockers, failures, then routine reviews", () => {
  const ranked = rankInboxItems([
    inboxItem("pending-benefit", "normal", 100),
    inboxItem("failed-job", "high", 20),
    inboxItem("blocked", "critical", 5),
  ]);
  assertEquals(ranked.map((item) => item.id), ["blocked", "failed-job", "pending-benefit"]);
});

Deno.test("same-severity items rank oldest first then stable id", () => {
  const ranked = rankInboxItems([
    inboxItem("b", "high", 60),
    inboxItem("a", "high", 60),
    inboxItem("c", "high", 120),
  ]);
  assertEquals(ranked.map((item) => item.id), ["c", "a", "b"]);
});
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/inbox_test.ts`

Expected: FAIL because ranking is undefined.

- [ ] **Step 3: Implement bounded source adapters and partial failures**

```ts
const severityOrder = { critical: 0, high: 1, normal: 2 } as const;

export function rankInboxItems(items: InboxItem[]): InboxItem[] {
  return [...items].sort((left, right) =>
    severityOrder[left.severity] - severityOrder[right.severity] ||
    right.age_seconds - left.age_seconds ||
    left.id.localeCompare(right.id)
  );
}

export async function handleInboxList(_: Record<string, unknown>, context: AdminActionContext) {
  const results = await Promise.allSettled([
    loadIdentityInbox(context.db, 100),
    loadBenefitInbox(context.db, 100),
  ]);
  const items = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
  return {
    items: rankInboxItems(items).slice(0, 100),
    partial_failures: results.flatMap((result, index) =>
      result.status === "rejected"
        ? [index === 0 ? "card_identity" : "benefit_enrichment"]
        : []
    ),
    refreshed_at: new Date().toISOString(),
  };
}
```

Map `review_required`, `failed`, and `quarantined` to `high`; map pending/staged review to `normal`; reserve `critical` for later customer-blocking and disabled-pipeline adapters. Destinations are `{ section: "cardData", lane, target_id }`.

- [ ] **Step 4: Run inbox and gateway tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/inbox_test.ts supabase/functions/admin-operator/router_test.ts`

Expected: PASS for source failure isolation, 100-item cap, deterministic ordering, and sanitized destinations.

- [ ] **Step 5: Commit the inbox source**

```bash
git add supabase/functions/admin-operator/inbox.ts supabase/functions/admin-operator/inbox_test.ts supabase/functions/admin-operator/router.ts
git commit -m "feat(admin2): derive ranked card action inbox"
```

### Task 4: Add typed Flutter repositories for Card Data and Inbox

**Files:**
- Create: `lib/features/admin2/card_data/card_data_models.dart`
- Create: `lib/features/admin2/card_data/card_data_repository.dart`
- Create: `lib/features/admin2/inbox/inbox_models.dart`
- Create: `lib/features/admin2/inbox/inbox_repository.dart`
- Create: `test/features/admin2/card_data_repository_test.dart`
- Create: `test/features/admin2/action_inbox_test.dart`

**Interfaces:**
- Consumes: `AdminOperatorRepository.invoke(action, body)` added here as the common transport hook.
- Produces: `CardReviewPage`, `CardReviewItem`, `CardReviewAction`, `InboxSnapshot`, and `AdminInboxItem`.

- [ ] **Step 1: Write failing DTO and request tests**

```dart
test('benefit retry includes request id and observed state', () async {
  final api = RecordingAdminOperatorApi(response: const AdminOperatorResponse(200, {'result': {}}));
  final repository = CardDataRepository(AdminOperatorRepository(api), requestIds: () => '11111111-1111-4111-8111-111111111111');
  await repository.act(
    const CardReviewAction(
      lane: CardReviewLane.benefit,
      operation: CardReviewOperation.retry,
      targetId: '22222222-2222-4222-8222-222222222222',
      observedUpdatedAt: '2026-08-19T09:00:00Z',
    ),
  );
  expect(api.bodies.single['action'], 'card-review-action');
  expect(api.bodies.single['request_id'], '11111111-1111-4111-8111-111111111111');
});
```

- [ ] **Step 2: Run repository tests and verify failure**

Run: `flutter test test/features/admin2/card_data_repository_test.dart test/features/admin2/action_inbox_test.dart`

Expected: FAIL because the DTOs and repositories do not exist.

- [ ] **Step 3: Implement immutable DTOs and action mapping**

```dart
enum CardReviewLane { identity, benefit }
enum CardReviewOperation { approve, editApprove, merge, reject, retry, quarantine, unquarantine }

class CardReviewAction {
  const CardReviewAction({
    required this.lane,
    required this.operation,
    required this.targetId,
    required this.observedUpdatedAt,
    this.stagingId,
    this.reason,
    this.payload = const {},
  });
  final CardReviewLane lane;
  final CardReviewOperation operation;
  final String targetId;
  final String observedUpdatedAt;
  final String? stagingId;
  final String? reason;
  final Map<String, dynamic> payload;
}

class AdminInboxItem {
  const AdminInboxItem({
    required this.id,
    required this.severity,
    required this.title,
    required this.destination,
  });
  final String id;
  final String severity;
  final String title;
  final Map<String, dynamic> destination;
}
```

Add `AdminOperatorRepository.invoke(String action, Map<String, dynamic> body)` so domain repositories share 401/403/stable-error mapping without sharing DTO parsing.

- [ ] **Step 4: Run mapping tests and formatter**

Run: `dart format lib/features/admin2 test/features/admin2 && flutter test test/features/admin2/card_data_repository_test.dart test/features/admin2/action_inbox_test.dart`

Expected: PASS for both lanes, pagination, partial failures, every action payload, and stable error mapping.

- [ ] **Step 5: Commit the typed repositories**

```bash
git add lib/features/admin2/card_data lib/features/admin2/inbox lib/features/admin2/data/admin_operator_repository.dart test/features/admin2/card_data_repository_test.dart test/features/admin2/action_inbox_test.dart
git commit -m "feat(admin2): model inbox and card data workflows"
```

### Task 5: Build the Card Data list/detail review workspace

**Files:**
- Create: `lib/features/admin2/card_data/card_data_section.dart`
- Modify: `lib/features/admin2/screens/admin_operator_screen.dart`
- Create: `test/features/admin2/card_data_section_test.dart`

**Interfaces:**
- Consumes: `CardDataSource` implemented by `CardDataRepository` and the typed models from Task 4.
- Produces: filtered identity/benefit lanes with review, confirmation, refresh, and conflict behavior.

- [ ] **Step 1: Write failing widget tests for the operator-critical paths**

```dart
final class FakeCardDataRepository implements CardDataSource {
  FakeCardDataRepository({required this.page});
  final CardReviewPage page;
  final actions = <CardReviewAction>[];
  final completion = Completer<void>();

  @override
  Future<CardReviewPage> list(CardReviewQuery query) async => page;

  @override
  Future<void> act(CardReviewAction action) {
    actions.add(action);
    return completion.future;
  }
}

testWidgets('reject requires a reason and waits for server confirmation', (tester) async {
  final repository = FakeCardDataRepository(page: reviewPage());
  await pumpCardData(tester, repository);
  await tester.tap(find.text('Reject'));
  await tester.pumpAndSettle();
  expect(find.text('Reason'), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'Official page is not a card product');
  await tester.tap(find.text('Confirm rejection'));
  await tester.pump();
  expect(repository.actions.single.operation, CardReviewOperation.reject);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget test and verify failure**

Run: `flutter test test/features/admin2/card_data_section_test.dart`

Expected: FAIL because `CardDataSection` does not exist.

- [ ] **Step 3: Implement the lane filters and list/detail surface**

Build `CardDataSection` as a repository-injected `ConsumerStatefulWidget` with:

```dart
abstract interface class CardDataSource {
  Future<CardReviewPage> list(CardReviewQuery query);
  Future<void> act(CardReviewAction action);
}

class CardDataSection extends ConsumerStatefulWidget {
  const CardDataSection({super.key, required this.repository, this.initialTargetId});
  final CardDataSource repository;
  final String? initialTargetId;

  @override
  ConsumerState<CardDataSection> createState() => _CardDataSectionState();
}
```

Keep the current page visible during refresh; show `refreshedAt`; disable actions while submitting; require confirmations for approve, merge, reject, retry, and quarantine; require reasons for reject and quarantine; on `state_conflict`, reload the selected item and show “This review changed. Check the latest state.” Use a two-column list/detail layout above 1024 pixels and single-page drill-in below it.

- [ ] **Step 4: Run Card Data widget and accessibility tests**

Run: `dart format lib/features/admin2/card_data lib/features/admin2/screens/admin_operator_screen.dart test/features/admin2/card_data_section_test.dart && flutter test test/features/admin2/card_data_section_test.dart test/core/theme/typography_floor_contract_test.dart`

Expected: PASS for loading, empty, identity, benefit, pagination, refresh, 401, 403, conflict, required reason, keyboard navigation, 390-pixel/2.0-text layout, and server-confirmed success.

- [ ] **Step 5: Commit the Card Data UI**

```bash
git add lib/features/admin2/card_data/card_data_section.dart lib/features/admin2/screens/admin_operator_screen.dart test/features/admin2/card_data_section_test.dart
git commit -m "feat(admin2): add card data review workspace"
```

### Task 6: Build the Action Inbox and deep-link it into Card Data

**Files:**
- Create: `lib/features/admin2/inbox/action_inbox_section.dart`
- Modify: `lib/features/admin2/screens/admin_operator_screen.dart`
- Modify: `test/features/admin2/action_inbox_test.dart`

**Interfaces:**
- Consumes: `InboxRepository`, `AdminInboxItem.destination`, and the workspace selection callback.
- Produces: default inbox with deterministic priority groups and selected Card Data target navigation.

- [ ] **Step 1: Add failing widget tests for ranking and navigation**

```dart
testWidgets('inbox keeps successful items when one source fails', (tester) async {
  await pumpInbox(tester, snapshot(partialFailures: const ['benefit_enrichment']));
  expect(find.text('Identity conflict'), findsOneWidget);
  expect(find.text('Benefit enrichment is temporarily unavailable'), findsOneWidget);
});

testWidgets('card item opens its exact Card Data target', (tester) async {
  final opened = <String>[];
  await pumpInbox(tester, snapshot(), onOpenCardTarget: opened.add);
  await tester.tap(find.text('Identity conflict'));
  expect(opened, ['review-1']);
});
```

- [ ] **Step 2: Run inbox tests and verify failure**

Run: `flutter test test/features/admin2/action_inbox_test.dart`

Expected: FAIL because the section widget is missing.

- [ ] **Step 3: Implement priority presentation and target navigation**

```dart
class ActionInboxSection extends StatefulWidget {
  const ActionInboxSection({
    super.key,
    required this.repository,
    required this.onOpenCardTarget,
  });
  final InboxRepository repository;
  final ValueChanged<String> onOpenCardTarget;

  @override
  State<ActionInboxSection> createState() => _ActionInboxSectionState();
}
```

Render critical, high, then normal groups without re-sorting the server's stable order. An item displays severity, title, safe explanation, source status, and age. Refresh retains current items. Partial-source banners do not replace successful content. The parent screen sets `section = AdminWorkspaceSection.cardData` and passes `target_id` into `CardDataSection`.

- [ ] **Step 4: Run the complete phase suite**

Run: `dart format lib/features/admin2 test/features/admin2 && flutter test test/features/admin2/ test/features/admin/ && deno test --node-modules-dir=auto --allow-env --allow-read --allow-net supabase/functions/admin-operator supabase/functions/admin-catalog-entry && node --test test/supabase/admin_card_data_operations_migration_test.js`

Expected: PASS; old and new catalog review routes both work.

- [ ] **Step 5: Commit the Action Inbox**

```bash
git add lib/features/admin2/inbox/action_inbox_section.dart lib/features/admin2/screens/admin_operator_screen.dart test/features/admin2/action_inbox_test.dart docs/superpowers/plans/2026-08-19-admin2-inbox-card-data.md
git commit -m "feat(admin2): connect inbox to card review"
```
