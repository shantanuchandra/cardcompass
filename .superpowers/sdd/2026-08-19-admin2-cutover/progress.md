# Admin2 Cutover — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-cutover.md`
- Base: `2599974`
- Status: active

## Preflight

- Foundation, Inbox/Card Data, System Ops, and Customer Ops are complete and reviewed.
- Cutover redirects only the legacy UI route; the compatibility endpoint remains deployed and moves to database-backed authorization.
- No push, deployment, production migration, secret deletion, or legacy endpoint deletion is authorized.

Ruling: Treat parity as exact executable action coverage plus server-confirmed refresh, not visual similarity to the legacy screen. Cost if wrong: layout may differ while every supported workflow remains test-locked.

Ruling: Carry the Customer plan's final adjudication ledger update into Task 1's code-bearing parity commit, honoring the instruction not to commit documentation alone. Cost if wrong: the commit includes completed-plan bookkeeping with no runtime effect.

## Tasks

- Task 1: complete — executable Card Data parity
- Task 2: complete — shared database-backed legacy authorization
- Task 3: complete — legacy redirect and conditional navigation entry
- Task 4: pending — cutover checklist and full verification
- Task 5: pending — stop at deployment boundary

## Task 1 evidence

- RED: the executable UI/repository parity matrix reached benefit retry but recorded no gateway mutation. The UI attached a staging ID to recovery operations, and the typed repository correctly rejected that invalid request before invocation.
- GREEN: all 13 required identities and benefit action names are driven through the real `CardDataSection` and `CardDataRepository`; each scenario asserts one exact typed gateway mutation between the initial list and a server-confirmed refresh.
- The fixtures cover realistic pending identity evidence, a plausible duplicate merge target, a complete staged lounge proposal, and eligible failed/review-required/quarantined recovery states. Literal assertions cover operation, target, request ID, observed version, reasons, staging boundary, and complete decision payloads.
- Bulk approval controls are absent, and a deferred-action test proves controls stay disabled and no refresh begins until the server confirms success.
- Focused parity plus Card Data widget coverage passes 21/21.
- The complete Admin2 Flutter suite passes 149/149, scoped Admin2 analysis reports no issues, and `git diff --check` is clean.

Ruling: Attach `staging_id` only to benefit approve, edit-and-approve, and reject decisions; recovery operations target the review item itself and must omit staging identity to satisfy the existing typed and server contracts. Cost if wrong: a future recovery endpoint that requires a staging version would need an explicit contract revision instead of inheriting it accidentally from the selected row.

## Task 2 evidence

- RED: the legacy endpoint rejected an active database admin whose identity email was not allowlisted, and the shared access module did not exist. A later malformed-response test also caught the initial extraction classifying malformed Auth data as a credential failure instead of a retryable dependency failure.
- GREEN: `_shared/admin_access.ts` owns caller-token authentication, stable credential/transient classification, and a fresh service-role `users(id,is_active,is_admin)` lookup for every request.
- Both `admin-operator` and `admin-catalog-entry` delegate to that module. The legacy endpoint preserves its existing human-readable authorization responses and action payloads while returning a sanitized retryable `500` for dependency failures.
- Tests prove any-email active admins succeed, verified founder-email and metadata claims cannot bypass `is_admin = false`, an immediate database flag change blocks the next request, malformed/transient dependencies are sanitized, and inherited action names remain rejected by the operator gateway.
- Focused authorization and legacy coverage passes 37/37; the complete Admin Operator plus legacy suite passes 103/103; all Supabase Function Deno tests pass 156/156; `deno check` passes for both entrypoints and the shared module; no runtime or test references to the removed email allowlist remain.

Ruling: Keep each endpoint's established public error vocabulary while sharing only the authorization decision: Admin Operator emits stable machine codes, and the compatibility endpoint retains its human-readable authorization strings. Cost if wrong: legacy clients expecting machine codes would continue receiving the same pre-cutover strings until the compatibility endpoint is retired.

## Task 3 evidence

- RED: focused router, Settings, and Admin shell tests failed on the missing conditional-entry inputs and missing allowlisted initial-section query contract.
- GREEN: `/app/admin/catalog-review` is now a route redirect to the exact `/app/admin2?section=card-data` destination; direct `/app/admin2` remains mounted and continues to enforce its own server-backed access check.
- The operator screen accepts only the literal `card-data` initial section. Missing, empty, traversal-like, and non-allowlisted values default to Action Inbox.
- A cached presentation provider derives visibility only from the existing Admin Operator `access` response. Loading, denied, and error states hide the entry; neither the shell nor Settings decodes claims or queries `users`.
- Wide navigation exposes Admin as a separate secondary 48px semantic action after the five consumer tabs. Compact navigation remains unchanged and authorized operators can use the Settings entry.
- Focused route, Settings, and full Admin2 coverage passes 156/156; scoped analysis reports no issues; `git diff --check` is clean.

Ruling: Resolve conditional discoverability through the cached Admin Operator access request once per provider lifecycle, including for ordinary authenticated shells, and hide the entry for loading, denied, or error states. Cost if wrong: one small gateway access request is added per authenticated app lifecycle; removing it would make the wide entry undiscoverable until Settings or Admin2 had already loaded access.

### Task 3 account-switch correction

- RED: an in-scope widget reproduction kept `entry: true` and the operator workspace after the active session changed from an allowed admin to unauthenticated in the same `ProviderScope`.
- Root cause: both access providers were cached only by provider scope and observed neither auth state nor session identity.
- GREEN: visibility and direct-route access now use separate auto-disposed families partitioned by the captured authenticated user ID. The ID partitions cache only; all authorization remains the gateway's fresh database decision.
- Unauthenticated state hides the entry and renders no workspace without a gateway request. A direct route never reuses the shell visibility response, so it performs a fresh check for the current identity and observes current `is_admin` state.
- Regression covers admin A -> sign-out -> non-admin B and B -> admin A without recreating `ProviderScope`; each identity gets separate visibility and direct-route calls, and no prior admin workspace survives the sign-out frame.
- Focused route, Settings, and full Admin2 coverage passes 157/157; scoped analysis reports no issues; `git diff --check` is clean.

Ruling: Use user ID only to partition two independent auto-disposed caches—one for discoverability and one for a direct Admin2 mount—while the gateway remains the sole authorization authority. Cost if wrong: each entry-to-route transition makes a second small access request, but database flag changes are observed on the route check and cross-account results cannot be reused.
