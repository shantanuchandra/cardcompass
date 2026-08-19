# Admin2 production cutover checklist

This is the operator runbook and evidence record for `/app/admin2`. It deliberately contains no bearer tokens, customer content, statement data, provider responses, or secret values.

## Verification record

| Field | Value |
|---|---|
| Date | 2026-08-20 |
| Environment | Local worktree; isolated ephemeral PostgreSQL for opt-in database tests; no local Supabase Auth/Edge stack |
| Tested code HEAD | `codex/admin2-operator-console` Task 8 candidate; record immutable commit after verification |
| Tester | Codex |
| Production deployment | Not performed |
| Overall status | Candidate-scoped release checks pass; repository-wide formatting has one unrelated baseline-drift TypeScript file and analysis has 12 pre-existing info diagnostics; deployed Auth/PostgREST/provider smokes are Not Run pending deployment and spend authorization |

## Local release evidence

| Check | Result | Evidence |
|---|---:|---|
| Formatting | Candidate pass; baseline drift recorded | Candidate-scoped Dart and TypeScript files pass formatter check with no changes. The prescribed repository-wide Deno check identifies one unrelated pre-existing file, `_shared/card_catalog_enrichment.ts`; it was not changed. |
| Admin2 scoped analysis | Pass | `flutter analyze --no-fatal-infos lib/features/admin2 lib/core/router/app_router.dart lib/features/settings test/features/admin2 test/core/router/app_router_test.dart test/features/settings` reported no issues. |
| Full Flutter analysis | Pass with baseline notices | `flutter analyze` found 12 info-level diagnostics in pre-existing non-Admin2 files and no errors or warnings. The command exits 1 because infos are fatal by default. |
| Full Flutter tests | Pass | 717 passed; 25 explicitly skipped because the deployed/local Supabase stack and service-role test defines were unavailable. |
| Node migration/contract tests | Pass | 55 passed; 0 skipped; every opt-in disposable PostgreSQL suite ran sequentially against loopback PostgreSQL. |
| Deno Edge Function tests | Pass | 262 passed; 0 failed; 1 opt-in lifecycle smoke ignored in the network-capable full run and then passed separately with only loopback PostgreSQL plus injected no-network adapters. |
| Contextual eval lifecycle smoke | Pass | A loopback disposable PostgreSQL database plus the real `ai-eval-runner` handler processed statement, card-data, and fixed-selection recommendation runs with injected no-network model/judge adapters. A seven-case run used the production dispatcher request and `waitUntil` path after five exactly once. Complete run aggregates plus stored result token, cost, latency, attempt, clean-improvement, and severe-regression evidence were checked exactly. |
| Eval dataset authority | Pass | A disposable loopback PostgreSQL run proved explicit fresh version 0, approve/revise/approve/retire advancement, retired-lineage exclusion, exact current-version start fencing, and one durable run under concurrent replay. |
| Live provider pilot | Not Run | No explicit authorization for provider spend was supplied. No provider endpoint was contacted. |
| Opt-in Card Data PostgreSQL | Pass | 5 passed; isolated local PostgreSQL; no skips. |
| Opt-in runtime-control PostgreSQL | Pass | 5 passed; isolated local PostgreSQL; no skips. |
| Opt-in customer containment PostgreSQL | Pass | 5 passed; isolated local PostgreSQL; no skips, including unchanged-token RLS denial. |
| Runtime authorization reference scan | Pass | No `ADMIN_EMAIL`, `ADMIN_ALLOWLIST`, or founder-email reference exists in `lib` or `supabase/functions`. Founder references remain only in historical docs and seed/data migrations. |
| Web release compilation | Pass, non-deployable fixture build | `flutter build web --release --base-href /app/` completed with non-secret placeholder public configuration. The ephemeral 43 MB `build/web` output was removed after verification. A deployable artifact must be rebuilt with the deployment environment's real public defines. |
| Direct web paths | Pass | A real HTTP server test serves `/app/admin2`, nested Admin2 paths, and queries from the Flutter index; redirects `/app` canonically and the legacy catalog URL exactly; and keeps missing/lookalike assets, API-like paths, and encoded traversal out of SPA fallback. A release build loaded in headless Chrome proves `/app/login`, `/app/admin2`, `/app/cards`, `/app/settings`, and the legacy redirect render Flutter with exactly one `/app/` prefix. Hash routes are not part of the PathUrlStrategy contract. |
| Repository hygiene | Pass | Generated `node_modules` and placeholder build output removed; `git diff --check` passes before commit. |

The live Supabase stack was unavailable because the local Docker daemon was not running. Therefore every production/Auth smoke item below is explicitly **Not Run** rather than inferred from unit or isolated-PostgreSQL evidence.

## Pre-deployment gate

- [ ] Record the production app deployment identifier that currently serves `/app/`; this is the rollback target.
- [ ] Confirm a current database backup or point-in-time recovery window without copying data into this record.
- [ ] Apply additive migrations in this exact order: `20260819090000_admin_operator_foundation.sql`, `20260819090100_admin_card_data_operations.sql`, `20260819090200_admin_runtime_controls.sql`, `20260819090300_admin_customer_ops.sql`, `20260819090400_contextual_ai_feedback.sql`, `20260819090500_contextual_ai_eval_runs.sql`, `20260819090600_ai_eval_dataset_authority.sql`, `20260819132439_harden_inactive_customer_boundaries.sql`.
- [ ] Record both the current and immediately previous deployment version for every Edge Function in the coordinated deployment table below.
- [ ] Deploy all eight changed Edge Functions from the same candidate commit in the listed order. Shared modules are not independently deployable; confirm each importing function bundles the candidate versions.
- [ ] Build the web app with the deployment environment's real public Dart defines and deploy it only after all eight Edge Functions are healthy.
- [ ] Keep the legacy endpoint deployed. Do not remove old environment variables or additive tables during this cutover.
- [ ] Use two test accounts: the founder operator and a known active non-admin. Record only opaque test labels, never identities or credentials.

### Coordinated Edge deployment

Migrations must finish before step 1. For every row, record the candidate commit, new function deployment version, previous function deployment version, deployer, time, and health result. A missing-auth request is a health probe only; it must not perform application work or expose configuration.

| Order | Function | Candidate version | Previous version | Candidate bundle dependency | Immediate health check |
|---:|---|---|---|---|---|
| 1 | `benefit-enrichment-batch` | Record: ______ | Record: ______ | Changed `batch_policy.ts`; migration `20260819090200` runtime control | Missing/invalid scheduler authorization returns the stable 401. Then use smoke 8 to prove a scheduled invocation returns `paused` before inventory access and resumes afterward. |
| 2 | `card-discovery` | Record: ______ | Record: ______ | `_shared/active_profile.ts`, `_shared/card_discovery.ts`, and changed batch policy import | Missing/invalid user authorization returns 401. Then confirm an active user reaches validation and an inactive user gets `account_inactive` before service-role work. |
| 3 | `gemini-proxy` | Record: ______ | Record: ______ | `_shared/active_profile.ts` | Missing/invalid user authorization returns 401. Then confirm an inactive user gets `account_inactive` and forced upstream failure returns only `request_failed`. |
| 4 | `request-card-catalog-entry` | Record: ______ | Record: ______ | `_shared/active_profile.ts` | Missing/invalid user authorization returns 401. Then confirm an inactive user gets `account_inactive` before catalog service-role work. |
| 5 | `admin-catalog-entry` | Record: ______ | Record: ______ | `_shared/admin_access.ts` | Missing bearer credentials return the legacy endpoint's stable unauthorized response. Then run smoke 12 to prove database-backed authorization. |
| 6 | `feedback-submit` | Record: ______ | Record: ______ | Migration `20260819090400`; bounded contextual fixture capture and validation modules | Missing/invalid user authorization returns stable 401. Then submit one bounded contextual record and confirm no raw statement, history, email, token, or provider payload is stored. |
| 7 | `ai-eval-runner` | Record: ______ | Record: ______ | Migration `20260819090500`; `_shared/gemini_generate.ts` and `_shared/ai_eval_runner_receipt.ts` | Missing or ordinary user/admin bearer credentials return stable 401 before body/DB access. Invoke only with the service-role secret and a server-created run ID. |
| 8 | `admin-operator` | Record: ______ | Record: ______ | `_shared/admin_access.ts`, `_shared/feedback_triage.ts`, `_shared/ai_eval_runner_receipt.ts`, all Admin2 handlers, and the private runner | Missing bearer credentials return stable 401. Then run smokes 1–15 and confirm all four operator sections, feedback triage, and eval controls load. |

Shared files such as `_shared/admin_access.ts`, `_shared/active_profile.ts`, and `_shared/card_discovery.ts` ship inside importing function bundles. Record their source commit once, but record a separate deployed and previous version for every function above.

Do not expose the new operator UI until all eight functions pass health checks. A partial deployment creates four material hazards:

- An old `benefit-enrichment-batch` ignores the new scheduled pause control, so the UI can report paused while scheduled work continues.
- Old `card-discovery`, `gemini-proxy`, or `request-card-catalog-entry` bundles do not apply the active-profile gate, so an inactive user's unchanged token can still reach service-role work.
- Deploying only one Admin endpoint creates authorization mismatch: one endpoint trusts fresh database flags while the other may still use legacy email authorization, producing inconsistent founder/non-admin access.
- Deploying Admin2 eval controls without the matching private runner, receipt contract, feedback schema, and run lifecycle migration can create queued runs that cannot execute or evidence that cannot be interpreted safely.

## Production smoke

For each row, record the deployed app ID, function versions, tester, time, and Pass/Fail in the deployment log. Never paste response bodies beyond the listed stable status/code, or any user/provider content.

| # | Smoke test and exact expected result | Status | Local evidence |
|---:|---|---:|---|
| 1 | Sign in as the founder operator, open `/app/admin2`, and invoke `access`. Expect the four-section workspace and HTTP 200 with `is_admin: true`. | Not Run — no deployed/local Auth stack | Shared database-auth and access UI tests pass. |
| 2 | Sign in as the active non-admin and call `admin-operator` directly. Expect HTTP 403 with the stable forbidden response; no privileged query or mutation runs and the Admin entry stays hidden. | Not Run — no deployed/local Auth stack | Authorization and conditional-entry tests pass. |
| 3 | While the founder session remains signed in, set that profile's `is_admin` false through an approved database operator path, then make the next privileged request with the unchanged token. Expect HTTP 403 immediately. Restore the flag through the same approved path and verify a fresh request succeeds. | Not Run — production DB mutation requires authorization | Fresh-per-request database authorization tests pass. |
| 4 | Execute the 13 Card Data parity actions below one at a time. For each mutation, expect one stable receipt, disabled controls while pending, and a server-confirmed list refresh only after success. Confirm no bulk-approval control exists. | Not Run — needs deployed data fixtures | Exact executable parity suite passes. |
| 5 | Open a customer detail record. Verify an append-only `customer.read` audit row exists before any customer data source is read; simulate/read an audit failure and expect the detail request to fail closed. | Not Run — needs deployed audit inspection | Audit-first handler tests pass. |
| 6 | With an already-issued ordinary-user token, disable that account. Reuse the unchanged token to query each protected user-data surface. Expect RLS/RPC denial immediately; do not depend on token expiry or refresh. | Not Run — needs deployed Auth/RLS stack | Isolated customer PostgreSQL suite passes, including unchanged-token denial. |
| 7 | Trigger an Auth-ban dependency failure after database containment. Expect `auth_ban_pending`, preserved containment, and a durable pending attempt. Retry with the dedicated action; expect either the same retryable state or a completed receipt, never a second containment mutation. | Not Run — needs deployed Auth dependency | Durable retry/fencing tests pass. |
| 8 | Pause `benefit_enrichment_scheduled` with the current observed version and a reason. Invoke a scheduled run and expect a stable paused response before inventory/job access. Resume with the new observed version; expect scheduling to proceed. | Not Run — needs deployed scheduler | Runtime-control and batch policy tests pass. |
| 9 | Replay the same request ID and payload for one Card Data mutation and one runtime-control mutation. Expect the original receipt and no duplicate audit or state transition. Then reuse the ID with a different payload and expect rejection. | Not Run — needs deployed persistence | Isolated PostgreSQL idempotency suites pass. |
| 10 | Submit malformed, unauthorized, stale-version, and forced dependency-failure requests to both Admin endpoints. Expect only documented status/code vocabulary; verify logs and client responses do not contain SQL, stack traces, tokens, emails, statement data, or provider output. | Not Run — needs deployed endpoints/logs | Gateway and legacy error-sanitization tests pass. |
| 11 | Visit `/app/admin2` and `/app/admin/catalog-review` directly without a hash. Expect Admin2 to render and the legacy URL to redirect exactly to `/app/admin2?section=card-data`; malformed or non-allowlisted Admin2 section values must open Action Inbox. | Not Run — needs deployed router | Flutter router and real HTTP server direct-path tests pass. |
| 12 | Call the still-deployed `admin-catalog-entry` endpoint as an active database admin whose email is not allowlisted; expect authorization success. Call as a verified founder-email identity with `is_admin = false`; expect denial. | Not Run — needs deployed legacy endpoint | Shared legacy authorization suite passes. |
| 13 | In one browser/provider lifetime, switch admin A → signed out → non-admin B, then B → admin A. Expect the entry and workspace to disappear on sign-out/non-admin frames, no response reused across identities, and fresh access checks on each direct mount. | Not Run — needs deployed Auth/browser stack | Account-partition regression tests pass. |
| 14 | Submit bounded contextual feedback for each feature family, triage it into an approved versioned case, and verify the stored fixture excludes raw statement lines/history, email, bearer/provider tokens, prompts, rubrics, expected output, and captured answer from candidate input. | Not Run — needs deployed Auth/data fixtures | Feedback capture/triage and leakage contract suites pass. |
| 15 | Start a sanitized eval run from Admin2, confirm the private worker processes at most five cases per lease, continuation completes each manifest case once, and cancel/resume receipts remain audited. Candidate support must require full completion, improved pass rate, zero severe regressions, no review, and cost/latency within ceilings; recommendation scope must say fixed-selection explanation/arithmetic, not ranking. | Not Run — no deployed runner/provider authorization | No-network real PostgreSQL/worker lifecycle smoke and Admin handler/UI contract suites pass. Live provider pilot remains Not Run. |

### Not Run smoke-to-deployment mapping

| Smoke items | Required deployed components |
|---|---|
| 1–5, 7, 9–10, 13 | `admin-operator` and its bundled shared/handler modules; deployed web app for UI checks |
| 3, 10, 12 | Both `admin-operator` and `admin-catalog-entry` from one commit to detect authorization mismatch |
| 6 | `admin-operator`, `card-discovery`, `gemini-proxy`, and `request-card-catalog-entry`, plus migration `20260819090300`, to prove inactive profiles cannot reach any changed service-role gateway |
| 8 | `admin-operator`, `benefit-enrichment-batch`, and migration `20260819090200`, to prove scheduled pause is enforced by the worker rather than only displayed by the console |
| 11 | Deployed web app; retain deployed `admin-catalog-entry` for endpoint compatibility after the UI redirect |
| 14 | `feedback-submit`, `admin-operator`, migration `20260819090400`, and deployed web app |
| 15 | `admin-operator`, `ai-eval-runner`, `gemini-proxy`, migrations `20260819090400`–`20260819090500`, and deployed web app; a live-provider pilot additionally requires explicit spend authorization |

All mapped checks remain Not Run until every listed component is deployed from the candidate and its version is recorded. Passing a newer function against an older dependent bundle is not equivalent evidence.

### Card Data parity matrix (13 exact actions)

| Lane | Action | Fixture and expected result |
|---|---|---|
| Identity | `list` | Load a bounded pending-review page; only safe evidence metadata appears. |
| Identity | `approve` | Approve one observed version; receive its audited receipt, then refresh. |
| Identity | `editApprove` | Edit bank/card/network fields, approve the same observed version, then refresh. |
| Identity | `merge` | Supply one explicit destination card UUID; merge only that review item, then refresh. |
| Identity | `reject` | Supply a non-empty operator reason; reject only that item, then refresh. |
| Identity | `retry` | Retry one pending identity review whose discovery job is failed and eligible for retry; do not attach a staging ID; then refresh. |
| Benefit | `list` | Load staged/failed/review-required/quarantined items with bounded safe evidence. |
| Benefit | `approve` | Submit explicit approve decisions tied to the locked staging row, then refresh. |
| Benefit | `editApprove` | Submit complete edited-benefit decisions tied to the staging row, then refresh. |
| Benefit | `reject` | Submit per-proposal rejection reason plus operator reason tied to staging, then refresh. |
| Benefit | `retry` | Retry one failed review item without a staging ID, then refresh. |
| Benefit | `quarantine` | Quarantine one review-required item with a reason and without staging identity, then refresh. |
| Benefit | `unquarantine` | Release one quarantined review item without staging identity, then refresh. |

## Rollback

Rollback is application-only because all eight candidate migrations are additive and may already contain audit, request, containment, feedback, dataset, eval-result, or retry records.

1. Stop operator activity and record the failing deployment/function identifiers without copying request data.
2. Restore the previous web application deployment recorded in the pre-deployment gate.
3. Restore the recorded matching previous versions of all eight functions as one rollback set: `benefit-enrichment-batch`, `card-discovery`, `gemini-proxy`, `request-card-catalog-entry`, `admin-catalog-entry`, `feedback-submit`, `ai-eval-runner`, and `admin-operator`. Never mix candidate shared-module bundles with unmatched previous function versions.
4. Keep `20260819090000` through `20260819090600` and `20260819132439` applied. Do **not** drop or reverse their tables, columns, functions, policies, audit rows, request receipts, runtime controls, containment state, feedback/case history, eval evidence, or retry state.
5. Keep the legacy endpoint available. If safe operation cannot be confirmed, pause operator mutations at the application/function layer; do not delete evidence.
6. Re-run scheduler pause behavior, non-admin denial, founder authorization, unchanged-token containment across all three user service-role gateways, sanitized responses, and legacy-endpoint checks against the restored deployment.
7. Record rollback result, remaining risk, and owner. Escalate any database remediation as a new reviewed forward migration.

## Release candidate inventory

| Component | Candidate |
|---|---|
| Code tested | `codex/admin2-operator-console` Task 8 candidate; record immutable commit after verification |
| Migration order | `20260819090000` → `20260819090100` → `20260819090200` → `20260819090300` → `20260819090400` → `20260819090500` → `20260819090600` → `20260819132439` |
| Edge deployment required | In order: `benefit-enrichment-batch`; `card-discovery`; `gemini-proxy`; `request-card-catalog-entry`; `admin-catalog-entry`; `feedback-submit`; `ai-eval-runner`; `admin-operator` |
| Shared bundle changes | `_shared/active_profile.ts`, `_shared/admin_access.ts`, `_shared/card_discovery.ts`, `_shared/feedback_triage.ts`, `_shared/gemini_generate.ts`, and `_shared/ai_eval_runner_receipt.ts` are bundled by their importing functions; changed batch policy is bundled by batch/discovery and referenced by Admin2 failure vocabulary |
| Flutter target | Web release at base href `/app/` |
| Build evidence | Release compilation passed with placeholder public configuration; ephemeral artifact removed. Rebuild with real deployment public defines before deploy. |
| Rollback target | Previous web deployment plus the recorded matching previous versions of all eight Edge Functions; preserve every additive database object and all feedback/eval evidence |

## Deployment boundary

No push, Edge Function deploy, production migration, environment-variable removal, legacy-code deletion, or production smoke execution is authorized by this checklist. Obtain explicit authorization before any of those actions.
