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
- Task 4: complete — cutover checklist and full local verification
- Task 5: complete — release inventory recorded; stopped before deploy/push

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

## Task 4 and Task 5 evidence

- `docs/operations/admin2-cutover-checklist.md` records exact production smoke steps, evidence-safe result fields, all 13 Card Data parity actions, account-switch behavior, and an application/function rollback that preserves additive database evidence.
- Full Flutter tests pass 668 with 25 explicit live-Supabase skips; Node contract tests pass 48 with the three opt-in PostgreSQL cases skipped in the aggregate run; Deno Edge Function tests pass 156.
- All three opt-in isolated PostgreSQL suites were then run sequentially and pass 5/5 each, including unchanged-token RLS containment, idempotency/concurrency, and service-only grant boundaries.
- Candidate-changed Dart and TypeScript files pass formatter check without changes. The repository-wide formatting command exposes 31 unrelated baseline changes, which were discarded. Admin2 scoped analysis is clean. Full `flutter analyze` has no errors or warnings and reports 12 pre-existing info diagnostics outside Admin2; its default exit is non-zero because infos are fatal.
- The runtime authorization scan is empty across `lib` and `supabase/functions`. Founder references are limited to historical documentation and seed/data migrations.
- The configured npm release command cannot run in this worktree because ignored `dart_defines.json` is absent. A non-deployable release compile with placeholder public values succeeds; its generated artifact and dependency directory were removed.
- The local Docker daemon is unavailable, so the live Supabase Auth/Edge production smoke items are explicitly Not Run. No remote system was contacted or mutated.
- Release inventory correction: the coordinated deploy contains six changed functions since foundation base `3a46e82`: `benefit-enrichment-batch`, `card-discovery`, `gemini-proxy`, `request-card-catalog-entry`, `admin-catalog-entry`, and `admin-operator`. Shared active-profile, admin-access, discovery, and batch-policy code must ship in the importing bundles.
- The checklist now records per-function candidate/previous versions, ordered health checks, matching six-function rollback, and Not Run smoke coverage. It explicitly calls out partial-deploy hazards: unenforced scheduled pause, inactive-user service-role bypass, and mismatched Admin endpoint authorization.

Ruling: Treat the successful placeholder-configured web release compile as build-target verification, not a deployable artifact; require a fresh build with the deployment environment's real public Dart defines after authorization. Cost if wrong: release packaging must be repeated, but no placeholder-configured artifact can be deployed accidentally.

Ruling: Deploy and roll back all six changed Edge Functions as a version-recorded coordinated set, with worker/profile gateways before Admin exposure. Cost if wrong: partial rollout can make pause state cosmetic, preserve inactive-user privileged access, or split authorization semantics between Admin endpoints.

## Final-review corrections

- Founder access smoke now asserts the actual `is_admin: true` response contract.
- Identity retry now specifies a pending review with a failed, retry-eligible discovery job rather than describing the review itself as failed.
- The legacy-route regression now drives the real `GoRouter`, asserts the exact final URI and selected Card Data content, and settles without a redirect loop. Direct `/app/admin2` still proves Action Inbox is the rendered default.
- Focused router and Admin2 screen tests pass 22/22; the complete router plus Admin2 suite passes 155/155; scoped analysis and diff checks are clean.

## Final adjudication

- The single final-fix owner resolved all whole-cutover findings in `729d811`; the scoped re-review approved the corrected runbook fields and real-router navigation coverage with no residual.
- The cutover is an approved release candidate at the deployment boundary. All production/Auth smoke items remain mandatory Not Run gates, and no push, deployment, production migration, or remote mutation has occurred.
