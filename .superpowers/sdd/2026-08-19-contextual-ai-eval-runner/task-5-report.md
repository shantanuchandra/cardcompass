# Eval Task 5 report

Implemented deterministic structured scoring and randomized blind A/B explanation comparison.

- Structured assertions use exact root-relative paths and typed operators for equality, one-paisa money/currency tolerance, transaction exactly once, catalog identity, grounded benefit values/limits/periods/eligibility/sources, and must-not paths or claims.
- Baseline and candidate are independently evaluated. A regression requires a passing baseline and failing candidate, or a confident blind judgment that the candidate explanation worsened.
- Schema invalidity, materially wrong financial values, incorrect identity, unsupported claims, explicit must-not violations, and reviewed severe assertion keys are severe only when newly regressed.
- Recommendation scoring checks the approved fixed card/benefit IDs and arithmetic deterministically. It makes no selection or ranking claim.
- Blind orientation is reproducible from SHA-256 of `run_id:case_id:revision`. The judge sees only A/B explanation text in explicit untrusted-data delimiters plus the reviewed rubric; it has a pinned code-owned model, no tools, and an exact bounded response schema.
- Invalid output, ties, and confidence below 0.70 require review and never select the candidate.

Verification:

```text
deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/scorers_test.ts
10 passed, 0 failed

deno test --config supabase/functions/ai-eval-runner/deno.json supabase/functions/ai-eval-runner/
25 passed, 0 failed

deno check + deno fmt --check + git diff --check
pass
```

Residual risk: draft rubrics are stored as JSON without a database-level typed assertion schema. A malformed or legacy free-form rubric therefore produces schema-only evidence until an operator revises the case, rather than allowing the runner to infer ground truth.
