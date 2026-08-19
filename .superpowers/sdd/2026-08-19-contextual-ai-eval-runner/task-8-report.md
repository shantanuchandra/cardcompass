# Eval Task 8 report

Verified the contextual evaluation loop at the release boundary without provider spend, deployment, push, or remote mutation.

- Added an opt-in deterministic smoke that creates a disposable loopback PostgreSQL database, applies the real foundation/feedback/eval migrations, seeds all three feature families, and invokes the real private worker handler with injected no-network candidate/judge adapters.
- The seven-case statement run processes five cases and yields. The production continuation dispatcher constructs its exact private URL, service authorization, and `{run_id}` body through an injected offline fetch; the test awaits `waitUntil`, routes that captured request into the same real handler/dependencies, and finishes the remaining two without a second dispatch. Every manifest case is stored exactly once with one attempt. Card identity and recommendation fixed-selection explanation/arithmetic also complete through their real executors/scorers.
- Complete run aggregate objects are asserted exactly: case/success/failure/missing/regression/severe counts, failure-category object, average latency, all baseline/candidate/judge-attributed token totals, and decimal cost. Stored result rows independently assert full token, latency, cost, attempt, and row totals; the schema intentionally exposes an aggregate average latency rather than an aggregate total, so the result-row sum proves the latter. Clean baseline-only misses produce complete, no-review improvement evidence. A second historical dataset revision with a passing baseline plus regressing candidate records seven severe regressions and seven review requirements, which blocks support under the separately verified Admin detail decision contract.
- Existing live PostgreSQL lifecycle coverage verifies failed cases are not automatically reclaimed, explicit audited resume advances retry generation, successful evidence is preserved, and retry attempts remain fenced.
- The coordinated cutover inventory now includes seven additive migrations and eight changed Edge Functions, including `feedback-submit`, `ai-eval-runner`, `admin-operator`, and metered `gemini-proxy`. Rollback restores application/function versions while preserving additive feedback/eval evidence.

Fresh verification:

```text
dart format --output=none --set-exit-if-changed lib/features/admin2/system test/features/admin2
21 files, 0 changed

deno fmt --check [candidate eval/feedback/admin/shared scopes]
48 files checked

flutter analyze [Admin2 scope]
No issues found

flutter analyze
12 pre-existing info diagnostics; no errors or warnings

flutter test
709 passed; 25 deployed-stack integration tests skipped

node --test --test-concurrency=1 test/supabase/*.js [all disposable PostgreSQL opt-ins enabled]
55 passed; 0 failed; 0 skipped

deno test --frozen --allow-env --allow-net --allow-read supabase/functions
262 passed; 0 failed; 1 opt-in lifecycle smoke ignored

CONTEXTUAL_EVAL_TEST_ADMIN_URL=[loopback] deno test --allow-env --allow-read --allow-write --allow-run ... lifecycle_smoke_test.ts
1 passed; 0 failed

deno check --frozen ... ai-eval-runner/index.ts lifecycle_smoke_test.ts
pass

git diff --check
pass
```

The repository-wide Deno formatting command still identifies one unrelated pre-existing file, `_shared/card_catalog_enrichment.ts`; all candidate scopes are clean. Docker is installed but its daemon is unavailable, so deployed/local Supabase Auth/PostgREST/browser smokes remain Not Run. The live-provider pilot is Not Run because the user did not authorize provider spend; no provider endpoint was contacted. Static leakage scanning found only intentional environment-variable reads, test sentinel strings, and checklist prohibitions—no credential/customer fixture leakage.

Whole-plan final-review follow-up added explicit dual-mode Card Data capture, explicit candidate/family preflight selection, and independently paged case evidence. Fresh release evidence after those changes: Flutter 712 passed with 25 explicit integration skips; frozen Edge 265 passed with one opt-in lifecycle smoke ignored; all 55 sequential Node migration tests passed after the intentional feedback receipt signature update; live Feedback PostgreSQL passed 2/2; analysis retained only the documented pre-existing info diagnostics. No provider or deployment boundary was crossed.

Scoped re-review follow-up binds result pagination to the resolved run selection with one generation fence, resets implicit run changes to result page 1 across list pages and filters, and clears candidates removed by a catalog refresh. Focused tests cover next/previous run pages, status-driven replacement from result page 2, and empty candidate catalogs.

The final race follow-up extends that fence to explicit selection and busy/error ownership. Controlled completer tests resolve B before A and selection before refresh, proving only the newest matching request commits. Focused panel tests pass 12/12; complete Admin2 passes 178/178; scoped analysis and diff checks are clean.

Final branch-level P1 verification added a transactionally authoritative dataset lifecycle cursor and actual path-based web delivery. A live disposable PostgreSQL suite proves version advancement, current-only starts, retirement filtering, and concurrent replay. A spawned real HTTP server against an isolated fixture build proves direct `/app/admin2`, nested/query navigation, exact legacy redirect, canonical `/app/`, missing-asset/API 404s, and encoded-traversal denial. The release checklist now includes migration `20260819090600_ai_eval_dataset_authority.sql` and the direct-path smoke contract.

The compiled-web follow-up corrected GoRouter to use base-relative internal locations under Flutter's `/app/` base href, preventing `/app/app/...` browser URLs. A separate test-only release entrypoint injects deterministic in-memory authentication, admin authorization, empty cards, and operator responses without initializing Supabase or contacting a network. Headless Chrome waits for each new document and stable Flutter semantics: unauthenticated protected routes end at Login, authenticated Admin2 shows Action Inbox, Cards and Settings show unique headings, and legacy review settles on Card Data with its exact query. The normal production release bundle and production source roots contain no fixture marker or fake-auth seam. Static-host rewrites are exact route families rather than a broad `admin2*` mask, and hash compatibility is no longer claimed under PathUrlStrategy.
