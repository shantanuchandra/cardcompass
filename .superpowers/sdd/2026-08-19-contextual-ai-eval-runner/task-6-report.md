# Eval Task 6 report

Implemented the private, bounded, resumable AI evaluation worker.

- Timing-safe service-role authorization precedes body parsing and database access; user/admin JWTs cannot run evaluations.
- Strict request and claim validation, immutable revision loading, status/lease checks between cases, and fenced sequential result writes preserve exact-run integrity.
- Each invocation processes at most five cases. Full batches yield the lease and schedule exactly one background continuation; scheduler failures keep the run safely resumable.
- Baseline, candidate, and judge usage is persisted with safe execution/scoring failures. Responses expose only run receipts, statuses, counts, and stable failure categories.
- The new service-only `yield_ai_eval_run` RPC closes the active-lease gap required for immediate continuation, and recommendation cost projection now reserves the judge ceiling.

Verification:

```text
deno test --frozen --config supabase/functions/ai-eval-runner/deno.json \
  supabase/functions/ai-eval-runner/worker_test.ts \
  supabase/functions/ai-eval-runner/index_test.ts \
  supabase/functions/ai-eval-runner/scorers_test.ts
51 passed, 0 failed

deno test --frozen --allow-env --allow-net --allow-read supabase/functions
246 passed, 0 failed

deno check --frozen --config supabase/functions/ai-eval-runner/deno.json \
  supabase/functions/ai-eval-runner/index.ts \
  supabase/functions/ai-eval-runner/worker_test.ts
pass

deno fmt --check supabase/functions/ai-eval-runner supabase/config.toml
pass
```

No live provider call, deployment, or production migration was performed.
