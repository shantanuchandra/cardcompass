# Admin2 Customer Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe customer diagnosis, queued customer-owned Gmail recovery, account containment, and deletion-request tracking without exposing customer content or OAuth credentials.

**Architecture:** Customer reads and mutations pass through `admin-operator`. Account containment is enforced immediately by user-data RLS checking `public.users.is_active`; the Edge Function separately applies a Supabase Auth ban to prevent future authentication and refresh. Gmail recovery is a server-recorded request that the customer's authenticated app claims and executes with that customer's provider token—the admin never impersonates Gmail access.

**Tech Stack:** Flutter/Riverpod, Supabase Auth and Edge Functions/Deno, PostgreSQL RLS, Node migration contracts.

**Spec:** `docs/superpowers/specs/2026-08-19-admin-operator-console-design.md`

## Global Constraints

- Complete `docs/superpowers/plans/2026-08-19-admin2-foundation.md` first.
- Do not return email subjects, senders, attachments, statement rows, transaction rows, provider tokens, credentials, or raw failure payloads.
- Search accepts an exact UUID or a normalized email fragment of at least three characters, is capped at 25 rows, and returns normalized identity metadata only.
- `is_active` becomes server-governed; authenticated clients cannot set it on insert or update.
- Disabling a profile blocks data access through RLS even while an issued access JWT remains unexpired. Do not claim the JWT itself has been revoked.
- Admin-triggered Gmail recovery creates a request for the user's next authenticated session. It never obtains or stores the user's Google token.
- Actual account-data deletion is excluded. V1 records request progress only.

---

## File structure

- `supabase/migrations/20260819090300_admin_customer_ops.sql` — active-user policies, operation requests, deletion tracking, and audited RPCs.
- `test/supabase/admin_customer_ops_migration_test.js` — grants, RLS coverage, and service/user RPC contract.
- `supabase/functions/admin-operator/customers.ts` — sanitized search/detail and mutation handlers.
- `supabase/functions/admin-operator/customers_test.ts` — bounded search, audit-before-read, and Auth-ban tests.
- `supabase/functions/admin-operator/router.ts` — customer action registration.
- `lib/features/auth/providers/auth_provider.dart` — active-profile gate.
- `lib/features/dashboard/providers/gmail_sync_provider.dart` — claims and reports queued recovery.
- `lib/features/admin2/customers/customer_models.dart` — typed summary/detail/action DTOs.
- `lib/features/admin2/customers/customer_repository.dart` — gateway adapter.
- `lib/features/admin2/customers/customers_section.dart` — search and detail UI.
- `lib/features/admin2/screens/admin_operator_screen.dart` — replaces Customers placeholder.
- `test/features/auth/auth_provider_test.dart` — inactive-profile behavior.
- `test/features/dashboard/gmail_sync_provider_test.dart` — queued request behavior.
- `test/features/admin2/customer_repository_test.dart` — request/response contract.
- `test/features/admin2/customers_section_test.dart` — search and confirmation behavior.

---

### Task 1: Make `is_active` a real server-owned access block

**Files:**
- Create: `supabase/migrations/20260819090300_admin_customer_ops.sql`
- Create: `test/supabase/admin_customer_ops_migration_test.js`

**Interfaces:**
- Produces `public.current_user_is_active(): boolean`.
- Replaces user-owned RLS policies for `users`, `user_cards`, `transactions`, `statements`, `statement_milestone_cache`, `emails`, and `benefit_platform_confirmations`.

- [ ] **Step 1: Write the failing migration security contract**

The test must assert that the migration:

```js
const protectedTables = [
  'users', 'user_cards', 'transactions', 'statements',
  'statement_milestone_cache', 'emails', 'benefit_platform_confirmations',
];
for (const table of protectedTables) {
  assert.match(sql, new RegExp(`on public\\.${table.replaceAll('_', '\\_')}`));
}
assert.match(sql, /create or replace function public\.current_user_is_active\(\)/);
assert.match(sql, /security definer/);
assert.match(sql, /set search_path = ''/);
assert.match(sql, /revoke insert, update on table public\.users from authenticated/);
assert.doesNotMatch(sql, /grant (insert|update) \([^)]*is_active/);
assert.doesNotMatch(sql, /grant (insert|update) \([^)]*is_admin/);
```

Also assert every replacement policy contains `public.current_user_is_active()` and the relevant ownership predicate.

- [ ] **Step 2: Run the contract**

Run: `node --test test/supabase/admin_customer_ops_migration_test.js`

Expected: FAIL with `ENOENT`.

- [ ] **Step 3: Add the active-user helper and replace policies**

Implement:

```sql
create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users
    where id = (select auth.uid()) and is_active = true
  );
$$;

revoke all on function public.current_user_is_active() from public, anon;
grant execute on function public.current_user_is_active() to authenticated;
```

Replace `users_own_data_policy` with separate policies:

- SELECT/UPDATE/DELETE: `auth.uid() = id AND public.current_user_is_active()`;
- INSERT: `auth.uid() = id` with `WITH CHECK (auth.uid() = id)` so a first profile row can be created with the database default.

Replace the all-command policies on the five `user_id` tables with `USING` and `WITH CHECK` clauses combining ownership and `public.current_user_is_active()`. Replace the confirmation INSERT policy with the same active check.

Revoke `INSERT, UPDATE` on `public.users`, then re-grant the exact existing profile columns except `is_active` and `is_admin`: `id`, `email`, `full_name`, `avatar_url`, `phone`, `created_at`, `updated_at`, `preferences`, `given_name`, `family_name`, `date_of_birth`, and `profile_data`.

- [ ] **Step 4: Add a local RLS integration test**

Extend `test/supabase/admin_customer_ops_migration_test.js` with the repository's opt-in Supabase integration helper. Create an active test user and a user-card fixture, obtain an access token, disable the profile through the service client without refreshing the token, and assert the existing token can no longer select or insert user data. Assert a browser-role update of `is_active` is denied.

- [ ] **Step 5: Run contracts and the opt-in integration test**

Run: `node --test test/supabase/admin_customer_ops_migration_test.js`

Expected: static contract PASS; integration is PASS when local Supabase credentials are enabled or reports the repository-standard explicit skip.

### Task 2: Add customer-operation and deletion-progress records

**Files:**
- Modify: `supabase/migrations/20260819090300_admin_customer_ops.sql`
- Modify: `test/supabase/admin_customer_ops_migration_test.js`

**Interfaces:**
- Tables: `public.admin_customer_operation_requests`, `public.account_deletion_requests`.
- User RPCs: `claim_my_admin_operation_request(text): jsonb`, `complete_my_admin_operation_request(uuid, boolean, text): void`.
- Admin RPC: `admin_customer_action(uuid, uuid, text, uuid, jsonb, text, timestamptz): jsonb`.

- [ ] **Step 1: Add failing table and RPC assertions**

Assert both tables have RLS enabled and no browser table grants; user RPCs are executable only by `authenticated`; the admin RPC only by `service_role`; request types are constrained to `gmail_sync`; mutation types are `request_gmail_sync|disable_account|set_deletion_status`; and every successful admin action inserts one audit receipt.

- [ ] **Step 2: Run the focused contract**

Run: `node --test test/supabase/admin_customer_ops_migration_test.js`

Expected: FAIL on the missing structures.

- [ ] **Step 3: Implement the tables**

`admin_customer_operation_requests` has `id`, `user_id`, `operation_type`, `status` (`queued|claimed|completed|failed`), `requested_by`, `request_id`, `safe_failure_category`, `claimed_at`, `completed_at`, `created_at`, and `updated_at`; enforce unique `(requested_by, request_id)` and one unfinished `gmail_sync` request per user with a partial unique index.

`account_deletion_requests` has `id`, `user_id`, `status` (`requested|verified|scheduled|completed|cancelled`), `operator_note`, `updated_by`, `created_at`, and `updated_at`; enforce one current row per user. The table records progress only and has no delete cascade that performs account deletion.

- [ ] **Step 4: Implement narrow user and admin RPCs**

The claim RPC derives `auth.uid()`, requires `current_user_is_active()`, locks the oldest queued matching request, and returns `{id, operation_type}`. The completion RPC requires the same user ID and a `claimed` row, then records `completed` or `failed` plus an allowlisted safe category.

The admin RPC first checks `admin_audit_log` for `(actor_id, request_id)`, then locks the target profile or deletion row. `request_gmail_sync` inserts/returns a queued request. `disable_account` requires a reason, rejects `_target_user_id = _actor_id`, and sets `users.is_active = false`. `set_deletion_status` requires a reason and one allowlisted status. Each action inserts its result receipt in the same transaction.

- [ ] **Step 5: Run the migration contract**

Run: `node --test test/supabase/admin_customer_ops_migration_test.js test/supabase/admin_operator_foundation_migration_test.js`

Expected: PASS.

- [ ] **Step 6: Commit with the first consuming code in Task 3**

Keep the migration and plan uncommitted until Task 3 adds functional code.

### Task 3: Enforce active profiles in Flutter and consume queued Gmail recovery

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`
- Modify: `lib/features/dashboard/providers/gmail_sync_provider.dart`
- Modify: `test/features/auth/auth_provider_test.dart`
- Modify: `test/features/dashboard/gmail_sync_provider_test.dart`
- Add from Tasks 1–2: migration and migration test.

- [ ] **Step 1: Write failing auth tests**

Inject a profile reader and prove: missing auth user is unauthenticated; an active profile is authenticated; an inactive profile signs out and becomes unauthenticated; a temporarily unavailable profile read returns an error instead of treating the account as active.

- [ ] **Step 2: Write failing queued-sync tests**

Inject an `AdminOperationRequestRepository`. Prove that the notifier claims one `gmail_sync` request, runs the existing sync only with the current user's provider token, reports completion, reports `reauthentication_required` when that token is absent, and never accepts a token/user ID from the request row.

- [ ] **Step 3: Run focused Flutter tests**

Run: `flutter test test/features/auth/auth_provider_test.dart test/features/dashboard/gmail_sync_provider_test.dart`

Expected: FAIL on the new behavior.

- [ ] **Step 4: Implement the profile gate**

Add a `UserAccessProfileReader` interface returning `Future<bool>` for the current Auth user ID. `AuthNotifier.build` must query `users.is_active`; false triggers local sign-out. Keep a typed `InactiveAccountException` so UI and tests do not parse strings.

- [ ] **Step 5: Implement operation claiming around the existing sync**

Add a repository using only the two user RPCs. On authenticated dashboard initialization, claim at most one request. Call the existing `syncGmail`; in `finally`, complete the request with success or one of `reauthentication_required|gmail_unavailable|processing_failed`. Do not add service keys or provider tokens to database writes.

- [ ] **Step 6: Run tests and commit the functional access boundary**

Run: `flutter test test/features/auth/auth_provider_test.dart test/features/dashboard/gmail_sync_provider_test.dart && node --test test/supabase/admin_customer_ops_migration_test.js`

Expected: PASS.

```bash
git add supabase/migrations/20260819090300_admin_customer_ops.sql test/supabase/admin_customer_ops_migration_test.js lib/features/auth/providers/auth_provider.dart lib/features/dashboard/providers/gmail_sync_provider.dart test/features/auth/auth_provider_test.dart test/features/dashboard/gmail_sync_provider_test.dart docs/superpowers/plans/2026-08-19-admin2-customer-ops.md
git commit -m "feat(auth): enforce active accounts and queued recovery"
```

### Task 4: Add sanitized customer gateway actions

**Files:**
- Create: `supabase/functions/admin-operator/customers.ts`
- Create: `supabase/functions/admin-operator/customers_test.ts`
- Modify: `supabase/functions/admin-operator/router.ts`

**Interfaces:**
- `customer-search`, `customer-detail`, `customer-retry`, `customer-disable`, and `customer-deletion-status`.

- [ ] **Step 1: Write failing search and detail tests**

Cover: fewer than three email characters rejected; UUID exact match; limit clamped to 25; output excludes email rows and customer content; `customer-detail` writes `record_admin_read` before returning data and fails closed if audit insertion fails.

- [ ] **Step 2: Write failing mutation/Auth tests**

Use an injected `AuthAdminClient` interface:

```ts
export type AuthAdminClient = Readonly<{
  updateUserById: (
    userId: string,
    attributes: { ban_duration: string },
  ) => Promise<{ error: { message: string } | null }>;
}>;
```

Prove disable calls `admin_customer_action` first, then `updateUserById(userId, { ban_duration: "876000h" })`; if the ban fails, return `auth_ban_pending` while preserving the database block and audit result. A repeated request ID must retry only the missing Auth ban, not the database mutation.

- [ ] **Step 3: Run focused Deno tests**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/customers_test.ts`

Expected: FAIL because the handlers do not exist.

- [ ] **Step 4: Implement explicit projections and actions**

Return `CustomerSummaryDto` with `id`, normalized email, created/last activity, active state, and counts. Return `CustomerDetailDto` with Gmail connection boolean, last sync timestamps/status, statement-processing counts, owned-card count, and deletion state. Derive failure categories from an allowlist. Query Auth Admin only for provider connection metadata; do not return identities, tokens, or metadata blobs.

Merge an immutable `customerActionHandlers` registry into `router.ts`.

- [ ] **Step 5: Run all gateway tests and commit**

Run: `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/`

Expected: PASS.

```bash
git add supabase/functions/admin-operator/customers.ts supabase/functions/admin-operator/customers_test.ts supabase/functions/admin-operator/router.ts
git commit -m "feat(admin2): add safe customer operations API"
```

### Task 5: Build the Customers workspace

**Files:**
- Create: `lib/features/admin2/customers/customer_models.dart`
- Create: `lib/features/admin2/customers/customer_repository.dart`
- Create: `lib/features/admin2/customers/customers_section.dart`
- Modify: `lib/features/admin2/screens/admin_operator_screen.dart`
- Create: `test/features/admin2/customer_repository_test.dart`
- Create: `test/features/admin2/customers_section_test.dart`

- [ ] **Step 1: Write failing repository and widget tests**

Cover strict DTO mapping, minimum search length, retained results while refresh runs, audit-safe detail loading, disabled concurrent retry, reason plus typed confirmation for disable/deletion status, and `auth_ban_pending` messaging.

- [ ] **Step 2: Run focused Flutter tests**

Run: `flutter test test/features/admin2/customer_repository_test.dart test/features/admin2/customers_section_test.dart`

Expected: FAIL because the feature files do not exist.

- [ ] **Step 3: Implement models and repository**

Use immutable `CustomerSummary`, `CustomerDetail`, `CustomerOperation`, and `DeletionStatus` types. Keep server stable codes as an enum at the repository boundary.

- [ ] **Step 4: Implement the responsive list/detail UI**

Show only the approved metadata. The retry action explains that it is queued for the customer's next authenticated session. Disable and deletion-progress actions open confirmation surfaces and require a reason. Replace the Customers placeholder.

- [ ] **Step 5: Run focused tests and commit**

Run: `flutter test test/features/admin2/customer_repository_test.dart test/features/admin2/customers_section_test.dart`

Expected: PASS.

```bash
git add lib/features/admin2/customers lib/features/admin2/screens/admin_operator_screen.dart test/features/admin2/customer_repository_test.dart test/features/admin2/customers_section_test.dart
git commit -m "feat(admin2): add customer operations workspace"
```

### Task 6: Verify Customer Ops end to end

- [ ] **Step 1: Format and analyze**

Run: `dart format lib/features/auth lib/features/dashboard/providers/gmail_sync_provider.dart lib/features/admin2/customers test/features && deno fmt supabase/functions/admin-operator && flutter analyze`

Expected: formatter and analyzer exit 0.

- [ ] **Step 2: Run all test suites**

Run: `flutter test && node --test test/supabase/*.js && deno test --allow-env --allow-net --allow-read supabase/functions`

Expected: all tests pass; opt-in integration tests are either enabled and passing or explicitly skipped by the existing harness.

- [ ] **Step 3: Perform the local containment smoke test**

With local Supabase, obtain a non-admin user session, read one owned row, disable that user through `admin-operator`, then retry the read with the same access token.

Expected: the second read is denied immediately; a new sign-in/refresh is blocked; the admin audit row exists; no raw content is returned by customer detail.

- [ ] **Step 4: Inspect the final diff**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only intentional Customer Ops changes remain.
