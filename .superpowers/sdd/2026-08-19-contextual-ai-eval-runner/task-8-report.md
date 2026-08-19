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
