# Admin2 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the database-authorized, audited `/app/admin2` shell and the modular `admin-operator` Edge Function that every later admin workflow uses.

**Architecture:** A service-role Edge Function authenticates the bearer token with Supabase Auth, then reads `public.users.is_active` and `public.users.is_admin` for every request. Flutter calls that gateway through a typed repository and renders an internal four-section workspace, while the database stores append-only audit receipts for idempotent privileged operations.

**Tech Stack:** Flutter 3.44+, Dart 3.12+, Riverpod 2.6, GoRouter 14.8, Supabase Flutter 2.10+, Supabase Edge Functions/Deno, PostgreSQL 17, Node test runner.

**Spec:** `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- The only route introduced by this plan is `/app/admin2`; the existing `/app/admin/catalog-review` route remains functional.
- `public.users.is_admin` and `public.users.is_active` are checked from the database on every privileged request; email and client claims never authorize access.
- Browser roles receive no direct audit-table privileges and never receive a service-role key.
- Every response uses a stable safe error code and omits SQL, stack traces, credentials, provider payloads, and customer content.
- Mutations use a client-generated UUID request ID; one actor and request ID can produce one recorded result.
- Do not commit the plan/spec documents by themselves; include them in the first code-bearing commit.
- Preserve the existing admin catalog implementation until the cutover plan explicitly retires it.

---

## File structure

### Database and server

- `supabase/migrations/20260819090000_admin_operator_foundation.sql` — append-only audit table, idempotency constraint, and service-only audit functions.
- `test/supabase/admin_operator_foundation_migration_test.js` — static migration security contract.
- `supabase/functions/admin-operator/deno.json` — function imports and test configuration.
- `supabase/functions/admin-operator/types.ts` — request, actor, action-context, and safe error types.
- `supabase/functions/admin-operator/http.ts` — CORS, JSON responses, payload bounds, and stable error mapping.
- `supabase/functions/admin-operator/auth.ts` — bearer validation and database-backed admin authorization.
- `supabase/functions/admin-operator/access.ts` — the first registered action.
- `supabase/functions/admin-operator/router.ts` — allowlisted action registry.
- `supabase/functions/admin-operator/index.ts` — dependency construction and `Deno.serve` entry point.
- `supabase/functions/admin-operator/auth_test.ts` — authentication and authorization unit tests.
- `supabase/functions/admin-operator/router_test.ts` — action and response-boundary unit tests.
- `supabase/config.toml` — local function registration.

### Flutter

- `lib/features/admin2/models/admin_access.dart` — immutable access response model.
- `lib/features/admin2/data/admin_operator_api.dart` — Edge Function transport and stable exception mapping.
- `lib/features/admin2/data/admin_operator_repository.dart` — typed `access()` boundary and future action hook.
- `lib/features/admin2/providers/admin_access_provider.dart` — live repository/access providers.
- `lib/features/admin2/screens/admin_operator_screen.dart` — access-state coordinator and four-section shell.
- `lib/features/admin2/widgets/admin_workspace_navigation.dart` — responsive rail/compact navigation.
- `lib/core/router/app_router.dart` — `/app/admin2` route only; no visible navigation entry yet.
- `test/features/admin2/admin_operator_repository_test.dart` — mapping/error tests.
- `test/features/admin2/admin_operator_screen_test.dart` — authorization, navigation, layout, and accessibility tests.
- `test/core/router/app_route_refresh_test.dart` — refresh contract for `/app/admin2`.

---

### Task 1: Create the append-only audit and idempotency foundation

**Files:**
- Create: `supabase/migrations/20260819090000_admin_operator_foundation.sql`
- Create: `test/supabase/admin_operator_foundation_migration_test.js`

**Interfaces:**
- Consumes: `public.users.is_admin` from `20260819063836_add_admin_flag_to_public_users.sql`.
- Produces: `public.admin_audit_log`, `public.find_admin_request(uuid, uuid)`, and `public.record_admin_read(uuid, text, text, text, uuid, jsonb)`.

- [ ] **Step 1: Write the failing migration contract test**

```js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationUrl = new URL(
  '../../supabase/migrations/20260819090000_admin_operator_foundation.sql',
  import.meta.url,
);

test('admin audit storage is append-only and browser-inaccessible', async () => {
  const sql = (await readFile(migrationUrl, 'utf8')).toLowerCase();
  assert.match(sql, /create table public\.admin_audit_log/);
  assert.match(sql, /unique \(actor_id, request_id\)/);
  assert.match(sql, /alter table public\.admin_audit_log enable row level security/);
  assert.match(sql, /revoke all on public\.admin_audit_log from public, anon, authenticated/);
  assert.match(sql, /outcome text not null check \(outcome in \('succeeded', 'failed'\)\)/);
  assert.match(sql, /create or replace function public\.record_admin_read/);
  assert.match(sql, /security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function public\.record_admin_read/);
});
```

- [ ] **Step 2: Run the test and verify the missing migration fails**

Run: `node --test test/supabase/admin_operator_foundation_migration_test.js`

Expected: FAIL with `ENOENT` for `20260819090000_admin_operator_foundation.sql`.

- [ ] **Step 3: Add the migration with explicit grants and safe receipt lookup**

Create `20260819090000_admin_operator_foundation.sql` and place this SQL in it:

```sql
create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (length(action) between 1 and 100),
  target_type text not null check (length(target_type) between 1 and 100),
  target_id text,
  reason text check (reason is null or length(reason) between 1 and 1000),
  request_id uuid not null,
  outcome text not null check (outcome in ('succeeded', 'failed')),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  unique (actor_id, request_id)
);

create index admin_audit_log_created_at_idx
  on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;

create or replace function public.find_admin_request(
  _actor_id uuid,
  _request_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'action', log.action,
    'outcome', log.outcome,
    'result', coalesce(log.details -> 'result', '{}'::jsonb)
  )
  from public.admin_audit_log as log
  where log.actor_id = _actor_id and log.request_id = _request_id;
$$;

create or replace function public.record_admin_read(
  _actor_id uuid,
  _action text,
  _target_type text,
  _target_id text,
  _request_id uuid,
  _details jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_id uuid;
begin
  insert into public.admin_audit_log (
    actor_id, action, target_type, target_id, request_id, outcome, details
  ) values (
    _actor_id, _action, _target_type, _target_id, _request_id,
    'succeeded', coalesce(_details, '{}'::jsonb)
  )
  returning id into inserted_id;
  return inserted_id;
end;
$$;

revoke all on function public.find_admin_request(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.record_admin_read(uuid, text, text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.find_admin_request(uuid, uuid) to service_role;
grant execute on function public.record_admin_read(uuid, text, text, text, uuid, jsonb)
  to service_role;
```

- [ ] **Step 4: Run the contract test and migration parser tests**

Run: `node --test test/supabase/admin_operator_foundation_migration_test.js test/supabase/admin_user_flag_migration_test.js`

Expected: PASS with no direct browser grant and no self-assignment regression.

- [ ] **Step 5: Commit the database foundation with the approved design documents**

```bash
git add supabase/migrations/20260819090000_admin_operator_foundation.sql test/supabase/admin_operator_foundation_migration_test.js docs/superpowers/specs/2026-08-19-admin-operator-console-design.md docs/superpowers/specs/2026-08-19-contextual-ai-feedback-evals-design.md docs/superpowers/plans/2026-08-19-admin2-foundation.md
git commit -m "feat(admin2): add audited operator foundation"
```

### Task 2: Build database-backed Edge authorization

**Files:**
- Create: `supabase/functions/admin-operator/deno.json`
- Create: `supabase/functions/admin-operator/types.ts`
- Create: `supabase/functions/admin-operator/auth.ts`
- Create: `supabase/functions/admin-operator/auth_test.ts`

**Interfaces:**
- Consumes: a bearer token, a request-scoped Auth client, and a service-role database client.
- Produces: `requireAdmin(request, authDb, serviceDb): Promise<AdminActor>` and `AdminHttpError` with stable codes.

- [ ] **Step 1: Write failing authorization tests with injected clients**

```ts
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { requireAdmin } from "./auth.ts";
import { AdminHttpError } from "./types.ts";

Deno.test("admin auth rejects a missing bearer token before database reads", async () => {
  let reads = 0;
  await assertRejects(
    () => requireAdmin(new Request("http://local"), {} as never, {
      from: () => { reads += 1; return {} as never; },
    } as never),
    AdminHttpError,
    "authentication_required",
  );
  assertEquals(reads, 0);
});

Deno.test("admin auth reads active and admin flags by authenticated user id", async () => {
  const actor = await requireAdmin(
    new Request("http://local", { headers: { Authorization: "Bearer valid" } }),
    { auth: { getUser: () => Promise.resolve({ data: { user: { id: "user-1" } }, error: null }) } } as never,
    {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: () => Promise.resolve({
              data: { id: "user-1", is_active: true, is_admin: true },
              error: null,
            }),
          }),
        }),
      }),
    } as never,
  );
  assertEquals(actor, { id: "user-1" });
});
```

- [ ] **Step 2: Run the focused Deno test and verify failure**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/auth_test.ts`

Expected: FAIL because `auth.ts`, `types.ts`, and `deno.json` do not exist.

- [ ] **Step 3: Implement stable errors and the database flag check**

```ts
// types.ts
export type AdminActor = Readonly<{ id: string }>;
export type AdminActionContext = Readonly<{
  actor: AdminActor;
  requestId: string | null;
  db: any;
}>;

export class AdminHttpError extends Error {
  constructor(public code: string, public status: number) {
    super(code);
  }
}

// auth.ts
import { AdminHttpError, type AdminActionContext, type AdminActor } from "./types.ts";

export async function requireAdmin(
  request: Request,
  authDb: any,
  serviceDb: any,
): Promise<AdminActor> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new AdminHttpError("authentication_required", 401);
  }
  const token = authorization.slice("Bearer ".length);
  const { data: authData, error: authError } = await authDb.auth.getUser(token);
  if (authError || !authData.user) {
    throw new AdminHttpError("authentication_required", 401);
  }
  const { data: profile, error: profileError } = await serviceDb
    .from("users")
    .select("id,is_active,is_admin")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (profileError) throw new AdminHttpError("request_failed", 500);
  if (!profile?.is_active || !profile?.is_admin) {
    throw new AdminHttpError("administrator_access_required", 403);
  }
  return { id: authData.user.id };
}
```

Create `deno.json` with pinned imports:

```json
{
  "imports": {
    "@supabase/supabase-js": "npm:@supabase/supabase-js@2.95.0",
    "@std/assert": "jsr:@std/assert@1"
  },
  "nodeModulesDir": "auto"
}
```

- [ ] **Step 4: Run authorization tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/auth_test.ts`

Expected: PASS for missing, invalid, inactive, non-admin, database-error, and active-admin cases.

- [ ] **Step 5: Commit the authorization boundary**

```bash
git add supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/types.ts supabase/functions/admin-operator/auth.ts supabase/functions/admin-operator/auth_test.ts
git commit -m "feat(admin2): authorize operators from database flags"
```

### Task 3: Add the modular gateway and stable response contract

**Files:**
- Create: `supabase/functions/admin-operator/http.ts`
- Create: `supabase/functions/admin-operator/access.ts`
- Create: `supabase/functions/admin-operator/router.ts`
- Create: `supabase/functions/admin-operator/index.ts`
- Create: `supabase/functions/admin-operator/router_test.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- Consumes: `requireAdmin()` from Task 2 and an object request body no larger than 32 KiB.
- Produces: `handleAdminOperator(request, deps): Promise<Response>`, `AdminActionHandler`, and the `access` response `{ is_admin: true }`.

- [ ] **Step 1: Write failing handler tests**

```ts
import { assertEquals } from "jsr:@std/assert";
import { handleAdminOperator } from "./index.ts";

const deps = {
  authorize: () => Promise.resolve({ id: "admin-1" }),
  db: {},
};

Deno.test("gateway serves access only after authorization", async () => {
  const response = await handleAdminOperator(
    new Request("http://local", {
      method: "POST",
      body: JSON.stringify({ action: "access" }),
    }),
    deps as never,
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { is_admin: true });
});

Deno.test("gateway returns a stable code for unknown actions", async () => {
  const response = await handleAdminOperator(
    new Request("http://local", {
      method: "POST",
      body: JSON.stringify({ action: "raw-sql" }),
    }),
    deps as never,
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/router_test.ts`

Expected: FAIL because `handleAdminOperator` is undefined.

- [ ] **Step 3: Implement the registry and dependency-injected handler**

```ts
// access.ts
import type { AdminActionContext } from "./types.ts";
export type AdminActionHandler = (
  body: Record<string, unknown>,
  context: AdminActionContext,
) => Promise<unknown>;

export const accessActionHandlers: Readonly<Record<string, AdminActionHandler>> = {
  access: async () => ({ is_admin: true }),
};

// router.ts
import { accessActionHandlers } from "./access.ts";
export const actionHandlers = Object.freeze({ ...accessActionHandlers });

// http.ts
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const jsonResponse = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: corsHeaders });

// index.ts
import { createClient } from "@supabase/supabase-js";
import { requireAdmin } from "./auth.ts";
import { corsHeaders, jsonResponse } from "./http.ts";
import { actionHandlers } from "./router.ts";
import { AdminHttpError, type AdminActor } from "./types.ts";

type AdminOperatorDependencies = Readonly<{
  authorize: (request: Request) => Promise<AdminActor>;
  db: AdminActionContext["db"];
  authDb: AdminActionContext["db"];
}>;

export async function handleAdminOperator(
  request: Request,
  provided?: Partial<AdminOperatorDependencies>,
) {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "invalid_request" }, 405);
  try {
    const raw = await request.text();
    if (raw.length > 32_768) throw new AdminHttpError("invalid_request", 413);
    const body = JSON.parse(raw) as Record<string, unknown>;
    if (!body || Array.isArray(body) || typeof body.action !== "string") {
      throw new AdminHttpError("invalid_request", 400);
    }
    const db = provided?.db ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const authDb = provided?.authDb ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      request.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } } },
    );
    const actor = provided?.authorize
      ? await provided.authorize(request)
      : await requireAdmin(request, authDb, db);
    const handler = actionHandlers[body.action];
    if (!handler) throw new AdminHttpError("invalid_request", 400);
    const requestId = typeof body.request_id === "string" ? body.request_id : null;
    return jsonResponse(await handler(body, { actor, requestId, db }));
  } catch (error) {
    if (error instanceof AdminHttpError) return jsonResponse({ error: error.code }, error.status);
    return jsonResponse({ error: "request_failed" }, 500);
  }
}

if (import.meta.main) Deno.serve((request) => handleAdminOperator(request));
```

Register the function without disabling JWT verification:

```toml
[functions.admin-operator]
enabled = true
verify_jwt = true
entrypoint = "./functions/admin-operator/index.ts"
```

- [ ] **Step 4: Run gateway and legacy Edge tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/ && deno test --node-modules-dir=auto --allow-env --allow-read --allow-net supabase/functions/admin-catalog-entry/`

Expected: PASS; malformed JSON, oversized bodies, unsupported methods/actions, and thrown internals return stable safe codes.

- [ ] **Step 5: Commit the gateway**

```bash
git add supabase/functions/admin-operator supabase/config.toml
git commit -m "feat(admin2): add modular operator gateway"
```

### Task 4: Add the typed Flutter access repository

**Files:**
- Create: `lib/features/admin2/models/admin_access.dart`
- Create: `lib/features/admin2/data/admin_operator_api.dart`
- Create: `lib/features/admin2/data/admin_operator_repository.dart`
- Create: `lib/features/admin2/providers/admin_access_provider.dart`
- Create: `test/features/admin2/admin_operator_repository_test.dart`

**Interfaces:**
- Consumes: Edge action `{ "action": "access" }`.
- Produces: `AdminOperatorRepository.access(): Future<AdminAccess>`, `AdminAuthenticationRequired`, `AdminAccessDenied`, and `AdminRequestFailed`.

- [ ] **Step 1: Write failing repository tests**

```dart
final class FakeAdminOperatorApi implements AdminOperatorApi {
  FakeAdminOperatorApi(this.response);
  final AdminOperatorResponse response;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    return response;
  }
}

test('access maps the database-backed response', () async {
  final api = FakeAdminOperatorApi(
    const AdminOperatorResponse(200, {'is_admin': true}),
  );
  final access = await AdminOperatorRepository(api).access();
  expect(access.isAdmin, isTrue);
  expect(api.bodies.single, {'action': 'access'});
});

test('403 maps to AdminAccessDenied', () async {
  final api = FakeAdminOperatorApi(
    const AdminOperatorResponse(403, {'error': 'administrator_access_required'}),
  );
  expect(AdminOperatorRepository(api).access(), throwsA(isA<AdminAccessDenied>()));
});
```

- [ ] **Step 2: Run the focused Flutter test and verify failure**

Run: `flutter test test/features/admin2/admin_operator_repository_test.dart`

Expected: FAIL because the repository types do not exist.

- [ ] **Step 3: Implement the typed boundary**

```dart
class AdminAccess {
  const AdminAccess({required this.isAdmin});
  final bool isAdmin;

  factory AdminAccess.fromJson(Map<String, dynamic> json) =>
      AdminAccess(isAdmin: json['is_admin'] == true);
}

abstract interface class AdminOperatorApi {
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body);
}

class AdminOperatorRepository {
  const AdminOperatorRepository(this._api);
  final AdminOperatorApi _api;

  Future<AdminAccess> access() async {
    final response = await _api.invoke(const {'action': 'access'});
    if (response.status == 401) throw AdminAuthenticationRequired();
    if (response.status == 403) throw AdminAccessDenied();
    if (response.status != 200 || response.data is! Map) {
      throw AdminRequestFailed('request_failed');
    }
    return AdminAccess.fromJson(
      Map<String, dynamic>.from(response.data! as Map),
    );
  }
}
```

The live API invokes `admin-operator` through the injected `SupabaseClient`; the provider constructs it from `supabaseClientProvider` rather than `Supabase.instance` so tests can override it.

- [ ] **Step 4: Run repository tests and formatting**

Run: `dart format lib/features/admin2 test/features/admin2 && flutter test test/features/admin2/admin_operator_repository_test.dart`

Expected: PASS for 200, malformed response, 401, 403, stable server error, and network failure mappings.

- [ ] **Step 5: Commit the client boundary**

```bash
git add lib/features/admin2/models lib/features/admin2/data lib/features/admin2/providers test/features/admin2/admin_operator_repository_test.dart
git commit -m "feat(admin2): add typed operator access client"
```

### Task 5: Build the protected `/app/admin2` workspace shell

**Files:**
- Create: `lib/features/admin2/screens/admin_operator_screen.dart`
- Create: `lib/features/admin2/widgets/admin_workspace_navigation.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `test/core/router/app_route_refresh_test.dart`
- Create: `test/features/admin2/admin_operator_screen_test.dart`

**Interfaces:**
- Consumes: `adminAccessProvider` from Task 4.
- Produces: `AdminOperatorScreen`, `AdminWorkspaceSection`, and responsive selection callbacks for `inbox`, `customers`, `cardData`, and `system`.

- [ ] **Step 1: Write failing route and screen tests**

```dart
test('admin2 survives a browser refresh', () async {
  final match = router.configuration.findMatch(Uri.parse('/app/admin2'));
  expect(match.error, isNull);
  expect(match.uri.path, '/app/admin2');
});

testWidgets('authorized operator opens on Action Inbox', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminAccessProvider.overrideWith((ref) async => const AdminAccess(isAdmin: true))],
      child: const MaterialApp(home: AdminOperatorScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Action Inbox'), findsWidgets);
  expect(find.text('Customers'), findsOneWidget);
  expect(find.text('Card Data'), findsOneWidget);
  expect(find.text('System'), findsOneWidget);
});
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `flutter test test/features/admin2/admin_operator_screen_test.dart test/core/router/app_route_refresh_test.dart`

Expected: FAIL because the screen and route do not exist.

- [ ] **Step 3: Implement the access coordinator and responsive shell**

```dart
enum AdminWorkspaceSection { inbox, customers, cardData, system }

class AdminOperatorScreen extends ConsumerStatefulWidget {
  const AdminOperatorScreen({super.key});

  @override
  ConsumerState<AdminOperatorScreen> createState() => _AdminOperatorScreenState();
}

class _AdminOperatorScreenState extends ConsumerState<AdminOperatorScreen> {
  var section = AdminWorkspaceSection.inbox;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(adminAccessProvider);
    return access.when(
      loading: () => const Scaffold(
        body: BrandLoadingSkeleton(
          semanticLabel: 'Checking administrator access',
          minHeight: 280,
        ),
      ),
      error: (error, _) => AdminAccessFailureView(error: error),
      data: (value) {
        if (!value.isAdmin) return const AdminAccessDeniedView();
        return AdminWorkspaceNavigation(
          selected: section,
          onSelected: (next) => setState(() => section = next),
          child: switch (section) {
            AdminWorkspaceSection.inbox => const AdminSectionPlaceholder(title: 'Action Inbox'),
            AdminWorkspaceSection.customers => const AdminSectionPlaceholder(title: 'Customers'),
            AdminWorkspaceSection.cardData => const AdminSectionPlaceholder(title: 'Card Data'),
            AdminWorkspaceSection.system => const AdminSectionPlaceholder(title: 'System'),
          },
        );
      },
    );
  }
}

class AdminAccessFailureView extends StatelessWidget {
  const AdminAccessFailureView({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text(error is AdminAuthenticationRequired
        ? 'Sign in again to continue.'
        : 'Administrator access could not be checked.')),
  );
}

class AdminAccessDeniedView extends StatelessWidget {
  const AdminAccessDeniedView({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Administrator access required.')),
  );
}

class AdminSectionPlaceholder extends StatelessWidget {
  const AdminSectionPlaceholder({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Center(child: Text(title));
}
```

Add the route without adding it to `_kTabPaths` or the ordinary navigation:

```dart
GoRoute(
  path: '/app/admin2',
  pageBuilder: (_, _) => const NoTransitionPage(child: AdminOperatorScreen()),
),
```

At widths of at least 1024 pixels, `AdminWorkspaceNavigation` renders a rail and list/detail content. Below that breakpoint it renders a compact top selector and the same content. Every target has a minimum 44-by-44 logical-pixel hit area and a unique semantic label.

- [ ] **Step 4: Run screen, router, accessibility, and analyzer checks**

Run: `dart format lib/features/admin2 lib/core/router/app_router.dart test/features/admin2 test/core/router/app_route_refresh_test.dart && flutter test test/features/admin2/ test/core/router/app_route_refresh_test.dart test/core/theme/typography_floor_contract_test.dart && flutter analyze`

Expected: PASS at 390, 768, and 1280 pixel widths, 2.0 text scale, keyboard focus traversal, 401 sign-out callback, 403 ordinary-app return callback, and retryable network failure.

- [ ] **Step 5: Commit the workspace shell**

```bash
git add lib/features/admin2/screens lib/features/admin2/widgets lib/core/router/app_router.dart test/features/admin2/admin_operator_screen_test.dart test/core/router/app_route_refresh_test.dart
git commit -m "feat(admin2): add protected operator workspace"
```

### Task 6: Verify the complete foundation

**Files:**
- Modify only if a failing verification exposes a foundation defect.

**Interfaces:**
- Consumes: all Task 1-5 deliverables.
- Produces: a green foundation ready for the inbox/card-data, system, customer, and feedback plans.

- [ ] **Step 1: Run every admin and migration contract test**

Run: `flutter test test/features/admin/ test/features/admin2/ test/core/router/ && node --test test/supabase/admin_user_flag_migration_test.js test/supabase/admin_operator_foundation_migration_test.js`

Expected: PASS with the legacy catalog route unchanged.

- [ ] **Step 2: Run all Edge Function unit tests**

Run: `deno test --node-modules-dir=auto --allow-env --allow-read --allow-net supabase/functions`

Expected: PASS for both `admin-catalog-entry` and `admin-operator`.

- [ ] **Step 3: Run the full Flutter suite**

Run: `flutter test`

Expected: PASS; live local-Supabase groups skip unless their explicit integration flags are present.

- [ ] **Step 4: Inspect the final change boundary**

Run: `git diff --check && git status --short && git log --oneline -6`

Expected: no whitespace errors, no generated `node_modules/`, no secret files, and only foundation files in the task commits.

- [ ] **Step 5: Confirm the foundation handoff**

Run: `git status --short --branch`

Expected: the branch is clean and ready for `2026-08-19-admin2-inbox-card-data.md`. If a verification command failed, return to the task that owns that behavior, add its regression test, and repeat that task's commit step before declaring the foundation ready.
