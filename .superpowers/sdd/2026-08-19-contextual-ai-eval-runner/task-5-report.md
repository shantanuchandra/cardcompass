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

Review corrections:

- Rubric parsing is exact and fail closed. Every malformed, incomplete, unknown, or legacy free-form shape emits `rubric_contract_invalid`, fails both sides, and requires review; nothing is silently discarded.
- Scoring imports the executor's exact fixture-grounded output validator. Baseline and candidate schema assertions therefore cannot drift from executable output contracts, and an invalid baseline also requires review.
- The executor's recursive equality is exported and shared. Object field order is immaterial, while array order, number values, and primitive types remain significant.
- Deterministic recommendation failure always requires review and suppresses the explanation judge, so a subjective result can never rescue invalid IDs, arithmetic, schema, or rubric evidence.
- Frozen root verification passed all 222 Edge Function tests. The root lock's wildcard assert entry is required by two existing versionless Feedback imports and resolves to the existing pinned `1.0.19`; frozen verification left the lock hash unchanged.

Residual risk: draft rubrics are stored as JSON without a database-level typed assertion schema. Malformed or legacy cases now fail safely at scoring and require operator revision, but database creation does not yet reject them earlier.

Captured-card baseline correction:

- New `user_card` feedback fixtures explicitly select catalog-identity validation from their contextual target; no expected result or rubric selects the mode.
- Captured production card DTOs normalize into the same discriminated, grounded identity/benefit output contract used by candidates. Answer values come from captured catalog/benefit rows; official sources attach citations and validate provenance without rewriting those values.
- Ambiguous historical modes, missing required fields, absent citations, or source mismatches return `insufficient_fixture` before scoring.
- Focused Eval and Feedback coverage passes 42 tests, including real identity/benefit normalization and scorer regression behavior.

Citation-consensus correction:

- Every emitted identity or benefit citation now individually validates the complete captured answer for its selected mode.
- Conflicting applicable identity evidence, benefit evidence linked to another card, or disagreement with captured values fails closed as `insufficient_fixture` even when another valid source exists.
- Sources for the other explicit evaluation mode remain unrelated, are ignored safely, and are never emitted.

Candidate citation-completeness correction:

- Candidate citations must exactly cover every official source applicable to the selected evaluation mode; citing only a favorable subset is invalid model output.
- All applicable sources then pass the same identity/benefit/card-link consensus checks used by captured normalization. Other-mode sources remain ignored by discriminant.
- Explicit tests reject identity and benefit candidates that omit conflicting applicable evidence while citing a valid source.
