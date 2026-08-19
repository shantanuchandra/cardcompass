# SDD ledger — plan: docs/superpowers/plans/2026-08-19-admin2-foundation.md

## Baseline

- Worktree: `/Users/shantanuchandra/Downloads/Personal/cardcompass/.worktrees/admin2-operator-console`
- Branch: `codex/admin2-operator-console`
- Start commit: `3a46e82e8b494d87df08c0891740bff18ba442b1`
- Flutter: 488 passed, 25 expected opt-in integration skips.
- Node migration contracts: 27 passed.
- Deno Edge tests: 57 passed with `--node-modules-dir=auto`.

## Pre-flight interface scan

| Tasks | Producer → consumer | Finding / ruling |
|---|---|---|
| Task 1 self | Migration test → audit table/functions | Finding: the supplied SQL calls the table append-only but does not explicitly remove service-role UPDATE/DELETE. Ruling: revoke all table privileges from `service_role`, then grant only SELECT/INSERT; SECURITY DEFINER functions retain owned insert access. This strengthens the binding spec; if wrong, service-side direct audit maintenance would need a later narrow RPC. |
| Task 2 self | Auth tests → `types.ts`/`auth.ts` | Clean: tests cover missing/invalid/inactive/non-admin/database-error/admin cases and the implementation checks database flags by authenticated user ID. |
| Tasks 1 → 2 | Existing `users.is_admin` → per-request authorization | Clean: Task 2 consumes the applied flag but does not expose audit storage or service credentials. |
| Task 3 self | Router tests → HTTP/access/router/index/config | Finding: the snippet uses `AdminActionContext` without importing it, maps malformed JSON to `request_failed`, and counts UTF-16 characters instead of payload bytes. Ruling: import the type, map JSON syntax failures to `invalid_request`, and enforce 32 KiB with `TextEncoder`; if wrong, only the error classification or exact non-ASCII bound would differ. |
| Tasks 2 → 3 | `requireAdmin` and safe errors → gateway | Clean after the Task 3 ruling: authorization remains before every handler lookup/invocation and stable errors stay sanitized. |
| Task 4 self | Repository tests → API/model/repository/provider | Finding: the example model silently maps malformed `is_admin` values to false while the task requires malformed-response failure mapping. Ruling: require `is_admin` to be a boolean and map missing/non-boolean data to `AdminRequestFailed('request_failed')`; if wrong, a future intentional nullable response would need a contract revision. |
| Tasks 3 → 4 | `access` response/errors → typed Flutter boundary | Clean: Task 4 consumes only `{is_admin: true}` plus stable status/error codes and uses injected Supabase client providers. |
| Task 5 self | Route/screen tests → protected responsive shell | Finding: the snippet renders errors but the task's acceptance text and spec require 401 local sign-out/re-auth and 403 return to the ordinary app. Ruling: implement these through injectable/testable callbacks or router/auth providers without authorizing in UI; if wrong, navigation wiring may require a small follow-up refactor. |
| Tasks 4 → 5 | Access provider/exceptions → screen coordinator | Clean after the Task 5 ruling: the provider remains the only client access source; route visibility is not authorization. |
| Tasks 3 → 6 | Edge gateway/config → verification | Clean: focused and legacy suites are explicitly re-run with auto npm dependency installation. |
| Tasks 1–5 → 6 | All foundation deliverables → final verification | Finding: six later approved plan files would otherwise remain untracked, contradicting the clean handoff. Ruling: include all approved 2026-08-19 admin/feedback plan and spec documents in Task 1's first code-bearing commit, satisfying the user's no-doc-only rule; if wrong, history has broader documentation scope in the first feature commit but no runtime impact. |

## Task status

- Task 1: minor (deferred): static migration test does not independently assert `find_admin_request` SECURITY DEFINER/search-path/revoke/service-role grant hardening; migration code is correct and final review must triage coverage.
- Task 1: complete (commits `3a46e82..49e0d70`, review clean; one deferred minor)
- Task 2: fix round 1/5 (2 addressed, 0 open — sanitized rejected Auth/database operations and added missing-profile/rejection coverage; commits `c48b532..7ac3988`)
- Task 2: complete (commits `49e0d70..7ac3988`, review clean)
- Task 3: fix round 1/5 (2 addressed, 0 open — rejected inherited action names and added prototype-chain regression coverage; commits `f7454bf..a38793c`)
- Task 3: complete (commits `7ac3988..a38793c`, review clean)
- Task 4: fix round 1/5 (2 addressed, 0 open — normalized malformed invocation responses and added FormatException/403 coverage; commits `192b6fb..19b8c04`)
- Task 4: complete (commits `a38793c..19b8c04`, review clean)
- Task 5: Ruling: Task 4 created only `adminOperatorRepositoryProvider` and omitted the plan-required `adminAccessProvider`; Task 5 may add the missing `FutureProvider<AdminAccess>` to `lib/features/admin2/providers/admin_access_provider.dart` as the smallest load-bearing prerequisite. If wrong, provider ownership shifts by one task but runtime architecture and public contract remain unchanged.
- Task 5: complete (commits `19b8c04..1d9c969`, review clean)
- Task 6: complete (commits `1d9c969..6c22764`, review clean; full verification green)
- Final review: fix round 1/1 complete — returned Auth errors now distinguish recognized invalid/expired credentials from retryable dependency failures; shared gateway types expose the planned RPC contract and stable handler codes; root Deno dependency discovery retains a refreshed tracked lock graph; and `find_admin_request` hardening has independent migration-contract coverage. Targeted Deno tests: 15 passed. Admin Operator Deno suite: 26 passed. Full Edge-function Deno suite: 83 passed. Migration/config Node suite: 26 passed. Admin2 Flutter suite: 27 passed.
