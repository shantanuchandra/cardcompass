# Admin2 Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/app/admin2` the only operator UI after proving parity, move the legacy endpoint to database-backed authorization, and expose a discoverable admin entry without weakening server authorization.

**Architecture:** A parity contract first maps every supported legacy workflow to the new gateway. The old route then redirects to Card Data, while `admin-catalog-entry` adopts the shared database `is_admin` check during its compatibility window. Ordinary app navigation renders the admin entry only after a successful `access` response; route visibility never grants access.

**Tech Stack:** Flutter/go_router/Riverpod, Supabase Edge Functions/Deno, repository smoke tests.

**Spec:** `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Prerequisites

- Complete the Foundation, Inbox/Card Data, System Ops, and Customer Ops plans.
- Feedback/eval plans are independent and are not required for catalog-review parity.
- Do not remove the legacy endpoint in this phase; only remove its email allowlist and redirect its UI route.
- Do not deploy, push, or delete environment secrets as part of this plan.

---

## File structure

- `test/features/admin2/admin2_parity_test.dart` — executable UI/action parity matrix.
- `supabase/functions/admin-catalog-entry/index.ts` — shared database-backed admin authorization.
- `supabase/functions/admin-catalog-entry/benefit_admin_test.ts` — authorization compatibility tests.
- `supabase/functions/_shared/admin_access.ts` — reusable authenticated actor lookup.
- `supabase/functions/_shared/admin_access_test.ts` — database flag and active-state tests.
- `supabase/functions/admin-operator/auth.ts` — delegates to the shared access module.
- `supabase/functions/admin-operator/auth_test.ts` — regression tests.
- `lib/core/router/app_router.dart` — legacy redirect plus the current `_AppShell` admin entry.
- `lib/features/admin2/screens/admin_operator_screen.dart` — allowlisted initial section from route state.
- `lib/features/admin2/providers/admin_access_provider.dart` — cached access state.
- `lib/features/settings/screens/settings_screen.dart` — compact/mobile admin entry.
- `test/core/router/app_router_test.dart` — route and redirect behavior.
- `test/features/settings/settings_screen_test.dart` — entry visibility.
- `docs/operations/admin2-cutover-checklist.md` — production smoke and rollback checklist.

---

### Task 1: Freeze parity as an executable contract

**Files:**
- Create: `test/features/admin2/admin2_parity_test.dart`

- [ ] **Step 1: Add the failing parity matrix**

Define this exact required set in the test:

```dart
const requiredAdmin2Actions = <String>{
  'identity.list',
  'identity.approve',
  'identity.editApprove',
  'identity.merge',
  'identity.reject',
  'identity.retry',
  'benefit.list',
  'benefit.approve',
  'benefit.editApprove',
  'benefit.reject',
  'benefit.retry',
  'benefit.quarantine',
  'benefit.unquarantine',
};
```

Build a fake `AdminOperatorRepository` that records actions. Drive the Card Data UI and assert every required action maps to one typed gateway call and a server-confirmed refresh. Also assert no bulk approval action exists.

- [ ] **Step 2: Run the parity test**

Run: `flutter test test/features/admin2/admin2_parity_test.dart`

Expected: FAIL until every supported action from the earlier plans is wired.

- [ ] **Step 3: Fill any parity gaps in Card Data code**

Modify only the exact Card Data model/repository/widget files identified by the failing action. Do not expand the action set or add direct Supabase table writes.

- [ ] **Step 4: Re-run and commit parity fixes**

Run: `flutter test test/features/admin2/admin2_parity_test.dart test/features/admin2/card_data_section_test.dart`

Expected: PASS.

```bash
git add test/features/admin2/admin2_parity_test.dart lib/features/admin2/card_data
git commit -m "test(admin2): lock catalog review parity"
```

### Task 2: Share database-backed authorization with the legacy endpoint

**Files:**
- Create: `supabase/functions/_shared/admin_access.ts`
- Create: `supabase/functions/_shared/admin_access_test.ts`
- Modify: `supabase/functions/admin-operator/auth.ts`
- Modify: `supabase/functions/admin-operator/auth_test.ts`
- Modify: `supabase/functions/admin-catalog-entry/index.ts`
- Modify: `supabase/functions/admin-catalog-entry/benefit_admin_test.ts`

**Interfaces:**
- Produces `resolveAdminActor(request, authDb, serviceDb): Promise<{ id: string }>`.

- [ ] **Step 1: Add failing shared-access tests**

Cover missing/invalid bearer token (`401`), missing profile (`403`), inactive profile (`403`), non-admin (`403`), active admin success, and a database read on every request. Assert email and metadata are never consulted.

- [ ] **Step 2: Add a failing legacy regression test**

Delete email-allowlist assumptions from the test fixture and prove an active database admin succeeds regardless of email while a verified email with `is_admin = false` fails.

- [ ] **Step 3: Run focused Deno tests**

Run: `deno test supabase/functions/_shared/admin_access_test.ts supabase/functions/admin-operator/auth_test.ts supabase/functions/admin-catalog-entry/benefit_admin_test.ts`

Expected: FAIL until the shared module is used.

- [ ] **Step 4: Extract and adopt the shared check**

Move the already-tested Foundation algorithm without changing stable error codes. Both endpoints construct a request-scoped Auth client from the caller bearer token and a service client for the profile read. Remove all `ADMIN_EMAIL`, allowlist, verified-email, and user-metadata authorization branches.

- [ ] **Step 5: Re-run and commit**

Run: `deno test supabase/functions/_shared/admin_access_test.ts supabase/functions/admin-operator/auth_test.ts supabase/functions/admin-catalog-entry/benefit_admin_test.ts`

Expected: PASS.

```bash
git add supabase/functions/_shared/admin_access.ts supabase/functions/_shared/admin_access_test.ts supabase/functions/admin-operator/auth.ts supabase/functions/admin-operator/auth_test.ts supabase/functions/admin-catalog-entry/index.ts supabase/functions/admin-catalog-entry/benefit_admin_test.ts
git commit -m "refactor(admin): share database-backed access control"
```

### Task 3: Redirect the legacy route and expose the conditional entry

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/admin2/screens/admin_operator_screen.dart`
- Modify: `lib/features/admin2/providers/admin_access_provider.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Modify: `test/core/router/app_router_test.dart`
- Create or modify: `test/features/settings/settings_screen_test.dart`

- [ ] **Step 1: Write failing route and visibility tests**

Assert `/app/admin/catalog-review` redirects to `/app/admin2?section=card-data`; `/app/admin2` still mounts for a direct URL so the server check can render denial; the navigation entry is absent while access is loading/denied; and it appears in Settings plus the wide shell only after access is allowed.

- [ ] **Step 2: Run focused tests**

Run: `flutter test test/core/router/app_router_test.dart test/features/settings/settings_screen_test.dart`

Expected: FAIL on redirect and entry visibility.

- [ ] **Step 3: Implement the redirect and conditional entry**

Use a route redirect for the legacy location. Update `AdminOperatorScreen` to parse only the allowlisted `section=card-data` query value and otherwise default to Inbox. Reuse the Foundation access provider; do not decode JWT claims or query `users` directly from widgets. Add Admin as a secondary `_AppShell` action in `app_router.dart`, not a sixth primary consumer tab. Preserve keyboard, semantic-label, and small-screen behavior.

- [ ] **Step 4: Run UI tests and commit**

Run: `flutter test test/core/router/app_router_test.dart test/features/settings/settings_screen_test.dart test/features/admin2`

Expected: PASS.

```bash
git add lib/core/router/app_router.dart lib/features/admin2/screens/admin_operator_screen.dart lib/features/admin2/providers/admin_access_provider.dart lib/features/settings/screens/settings_screen.dart test/core/router/app_router_test.dart test/features/settings/settings_screen_test.dart
git commit -m "feat(admin2): cut over operator navigation"
```

### Task 4: Write and execute the cutover smoke checklist

**Files:**
- Create: `docs/operations/admin2-cutover-checklist.md`

- [ ] **Step 1: Write the checklist**

Include exact checks for: founder access; non-admin `403`; toggling `is_admin` false blocks the next request; all Card Data parity actions; customer read audit; account-disable RLS block with an existing token; scheduled pause/resume; idempotent retry; sanitized responses; legacy redirect; legacy endpoint database authorization; and rollback by restoring the previous application deployment without reverting additive tables.

- [ ] **Step 2: Run local smoke checks and record evidence**

Add date, environment, commit SHA, tester, and pass/fail per item. Never paste tokens, email contents, statement data, or provider output.

- [ ] **Step 3: Run complete verification**

Run: `dart format lib test && deno fmt supabase/functions && flutter analyze && flutter test && node --test test/supabase/*.js && deno test --allow-env --allow-net --allow-read supabase/functions`

Expected: format/analyze clean and every test passes; existing opt-in integration skips remain explicit.

- [ ] **Step 4: Inspect configuration references**

Run: `rg -n "ADMIN_EMAIL|ADMIN_ALLOWLIST|shantanu\.msp@gmail\.com" lib supabase/functions`

Expected: no runtime authorization reference remains. The founder email may remain only in the already-applied database seed migration and documentation.

- [ ] **Step 5: Inspect diff and commit the checklist**

Run: `git diff --check && git status --short`

Expected: clean diff and only intentional cutover files.

```bash
git add docs/operations/admin2-cutover-checklist.md
git commit -m "docs(admin2): record cutover verification"
```

### Task 5: Stop at the deployment boundary

- [ ] **Step 1: Report the release candidate**

Provide the commit SHA, migration order (`20260819090000` through `20260819090300`), Edge Functions requiring deployment, Flutter build artifact, full test results, and rollback checklist location.

- [ ] **Step 2: Request explicit deployment/push authorization**

Do not push, deploy Edge Functions, apply new migrations to production, remove environment variables, or delete legacy code without a new explicit user instruction.
