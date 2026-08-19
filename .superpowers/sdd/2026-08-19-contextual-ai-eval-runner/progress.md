# Contextual AI Eval Runner — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-contextual-ai-eval-runner.md`
- Base: `7527ee1`
- Status: active

## Preflight

- Feedback capture/triage and Admin2 System Ops are complete and reviewed.
- Runs use only approved, version-bounded cases and code-owned config keys; no client prompt/model/provider/key authority.
- Candidate inputs exclude expected output, operator feedback, rubric, and severe conditions; judge is blind, randomized, tool-free, and advisory.

Ruling: Implement Tasks 1–3 as one review unit because immutable run storage and lifecycle RPCs ship with the metered transport they constrain. Cost if wrong: SQL and transport share a review unit, but no unmetered run foundation lands alone.

Ruling: Carry the Feedback plan's final adjudication into the Tasks 1–3 code-bearing commit. Cost if wrong: completed-plan bookkeeping shares a commit with eval code and has no runtime effect.

## Tasks

- Tasks 1–3: complete — immutable run storage/lifecycle and metered transport
- Task 4: complete — code-owned configs and feature-safe executors
- Task 5: complete — deterministic and blind scoring
- Task 6: pending — private bounded resumable worker
- Task 7: pending — Admin2 controls and decision support
- Task 8: pending — full verification and release boundary

## Tasks 1–3 evidence

- RED: the migration contract failed with `ENOENT`; metering tests failed because the transport had no exact model/input/output token fields.
- GREEN: private service-only run/result tables now snapshot approved version-bounded manifests, enforce 100-case/cost/latency ceilings, fence claims with expiring lease tokens, claim at most five via `SKIP LOCKED`, preserve successes, replace failed attempts only while nonterminal, aggregate terminal evidence, and audit idempotent create/cancel/resume mutations.
- The reusable Gemini transport reports selected model, parsed response, input/output tokens, and per-attempt latency while retaining the public proxy's raw status/body behavior, key/model fallback, 25-second timeout, model policy, quota boundary, CORS, and safe error behavior.
- Disposable PostgreSQL passed concurrent creation, stale-token rejection, exact manifest result recording, aggregate completion, and terminal immutability. Focused migration and proxy suites pass; live Feedback PostgreSQL regression coverage also passes.

Ruling: Fence every recorded case with the current run lease token and persist that token on its result row. Cost if wrong: a case already executing when a lease expires is rejected and must be retried, preferring duplicate compute over accepting evidence from an obsolete worker.

Ruling: Retain raw upstream status/body fields as a compatibility intersection on the exact metered Gemini result. Cost if wrong: private eval consumers see the required structured model/response/token/latency contract while the existing public proxy continues byte-for-byte upstream passthrough without a second transport.

### Tasks 1–3 review corrections

- Dataset manifests select the newest revision in each feedback lineage that was approved and not retired at the requested historical version. Version-one runs retain revision one; version-two runs select revision two without rewriting history.
- Per-case maximum cost is derived from the SQL copy of the code-owned configuration allowlist at creation. Claims accept no projected-cost input, clamp to five, and derive their own conservative projection; result persistence atomically rejects actual cumulative spend beyond the ceiling.
- Service role retains read access but all table writes flow through service-only security-definer RPCs. The forgeable custom setting was removed; terminal resume is the exact failed/partial-to-queued transition, while direct service inserts, updates, and deletes remain denied.
- Gemini rejects unknown models and UTF-8 payloads above 100 KB before fetch, and reports candidate plus thought/reasoning tokens exactly once across supported usage field variants.
- Disposable PostgreSQL now covers historical revision selection, exact manifests, the five-case clamp, invalid projection inputs, actual-cost rejection, failed-result replacement, cancel/resume audit idempotency, audit rollback, success preservation, and terminal service-role write denial.

Ruling: Derive the persisted per-case maximum cost from the same finite configuration keys enforced at run creation, rather than accepting worker-supplied projections. Cost if wrong: every new candidate configuration requires a reviewed SQL allowlist/cost update alongside its code registry entry, preventing a caller from weakening the ceiling.

Ruling: Select one latest applicable revision per source feedback lineage for each historical dataset version. Cost if wrong: two unrelated feedback reports remain separate cases even when semantically similar, while revisions of one report never double-weight a run.

### Tasks 1–3 scoped re-review corrections

- Revision ranking now happens before retirement filtering: a selected-version lineage whose newest approved revision is retired at that version disappears instead of falling back to an older revision. Live versions one, two, and retired version three prove the historical behavior.
- The candidate configuration allowlist derives one exact feature family, and run creation filters the manifest to that family. Mixed-feature fixtures cannot enter a card-data run; a supported configuration with no matching cases returns `invalid_request`.
- Typed Gemini transport calls reject empty and whitespace models. The public proxy alone resolves an omitted model to its supported default before calling the strict transport.

Ruling: Apply retirement after selecting the newest historically approved revision in a lineage. Cost if wrong: retirement removes the logical case from later datasets instead of resurrecting an older superseded revision.

Ruling: Bind each run manifest to the single feature family derived from its allowlisted candidate configuration. Cost if wrong: cross-feature comparison requires separate runs, ensuring every manifest case is executable by the selected candidate.

## Task 4 evidence

- RED: the focused Deno command failed because the runner modules/config did not exist; the nested-ground-truth test then failed until recursive fixture rejection was implemented.
- GREEN: seven focused tests pass for exact reviewed keys, migration-derived cost parity, pre-model key/feature rejection, zero-cost captured baselines across all three feature families, forbidden-field isolation, prompt delimiting, grounded exact output validation, and metering retention on invalid model output. Deno type-check and formatting pass.
- Candidate prompts contain only the bounded safe fixture and a fixed server-owned schema instruction. Expected outputs, feedback, rubrics, severe conditions, and captured baselines never enter candidate generation.

Ruling: Import the migration SQL as text in the registry test and derive its candidate key/cost mapping for direct parity with the code registry. Cost if wrong: SQL formatting changes may require updating the narrow extractor, but a cost or allowlist drift fails before release.

### Task 4 review corrections

- Feedback capture now builds bounded, reproducible fixtures from the real persisted transaction, statement, user-card, catalog, and mapped-benefit DTOs. It never includes raw statement lines or histories.
- Recommendation traces retain the production-selected card, benefit, savings, final amount, and bounded explanation with server-resolved catalog facts and ownership context.
- Executors consume the migration's real `{safe_input_context, authoritative_context}` fixture envelope and return the application's production output shapes. Empty, foreign-ID, non-finite financial, ungrounded, and under-specified historical cases fail safely; invalid generation retains metering.
- Registry parity covers candidate costs and feature mappings plus the captured baseline and pinned judge keys from SQL.

Ruling: Treat legacy cases without a closed reproducible fixture as `insufficient_fixture`, including captured baselines, rather than accepting unevaluable output. Cost if wrong: older approved cases require a reviewed new revision before they can contribute evidence.

Ruling: Keep statement feedback reproducible at its selected target granularity: one exact transaction or bounded statement metadata, never a full statement history reconstructed from unsafe/raw inputs. Cost if wrong: feedback about an unselected missing transaction remains human-review evidence until a safe selected-transaction fixture is authored.

### Task 4 evaluation-integrity corrections

- Candidate inputs and captured answers are now separated by construction. Transaction evidence excludes production category/type labels; statement metadata and current resolved card snapshots without original source evidence are explicitly non-runnable.
- Card execution supports discriminated identity and benefit outputs. Official source paths must resolve, identity values must equal source facts, and benefit objects must deeply equal bounded sourced facts.
- Fixed-selection recommendation evaluation receives request constraints plus selected authoritative facts, never captured savings/final amount/explanation. Candidate financials must reconcile to the source discount rule and gross ticket amount within one paisa.
- `insufficient_fixture` is accepted by run/result storage, persisted as a failed case, summarized by failure category, and completes an all-incomplete run as `completed_with_failures`. Conditional disposable-PostgreSQL coverage exercises the lifecycle when its admin URL is supplied.

Ruling: Prefer no model call over an answer-contaminated or commercially under-specified fixture. Cost if wrong: current statement-level and card-data feedback may stay in human review until capture has original bounded source evidence, preserving evaluation validity over dataset coverage.

Ruling: Scope recommendation candidates to `explain_fixed_selection` for MVP and validate their money against authoritative offer rules. Cost if wrong: reranking quality requires a later fixture contract containing the full eligible candidate set and ownership constraints, rather than being inferred from one selected trace.

### Task 4 provenance, parity, and scope corrections

- Real user-card feedback becomes runnable only when approved HTTPS catalog provenance or an official benefit URL supplies bounded source facts; otherwise it remains `card_requires_review`. Captured resolved catalog/benefit output stays separate.
- The real query-shaped provenance path is covered end-to-end through context resolution, the immutable draft fixture envelope, and candidate execution for identity; the same official-source contract supports benefit mode.
- Movie Deals normalization now carries `min_transaction` into the production rule and evaluator. Eval arithmetic mirrors percent, fixed/cycle-cap, and BOGO ticket-pair behavior; platform mismatch remains confidence-only and cinema informational, matching production semantics.
- Every registry entry has mandatory `taskScope`; recommendation scope is `fixed_selection_explanation_and_arithmetic`, explicitly excluding selection and ranking.

Ruling: A card case is runnable from stored feedback only when an HTTPS official provenance record or official benefit source supplies the extraction evidence. Cost if wrong: catalog rows without retained provenance remain human-review-only even when their resolved values look plausible.

Ruling: Preserve production Movie Deals platform/cinema semantics in evals: platform mismatch changes confidence and cinema is informational, not an eligibility cutoff. Cost if wrong: stricter platform/cinema evaluation requires a separately reviewed product-behavior change rather than silently changing the evaluator oracle.

Ruling: Publish recommendation scope as fixed-selection explanation and arithmetic, never ranking. Cost if wrong: Task 7 must label these results accordingly and cannot claim recommendation-selection improvement from this configuration.

### Task 4 production-provenance correction

- Card provenance now parses the production discovery schema exactly: `issuer`, `cardName`, `network`, and bounded `aliases`. It never assumes provenance contains catalog IDs or fees.
- Runnable identity evidence explicitly separates `provenance_claims` from a server-selected `catalog_reference`. Its mode and config scope are catalog identity validation, not catalog selection.
- Benefit evidence remains separately discriminated and official-source grounded. The query-shaped integration test uses the exact card-discovery `extracted_fields` payload and validates resolver-to-executor behavior.

Ruling: Card identity eval scope validates an already selected catalog reference against official provenance; it does not measure catalog selection. Cost if wrong: selection quality requires a future fixture with a bounded candidate set and a distinct configuration scope.

## Task 5 evidence

- RED: the focused scorer suite failed because `scorers.ts` did not exist; after the first green pass, schema-focused integration tests exposed that execution status alone could not validate captured-output shape.
- GREEN: structured scoring evaluates approved typed path assertions separately for baseline and candidate, including exact values, one-paisa financial/currency tolerance, exactly-once transactions, catalog identity, grounded benefit fields, prohibited paths/claims, and feature output schemas. Regression is emitted only when a passing baseline becomes a failing candidate; severe status is limited to the approved severe classes.
- Recommendation scoring is explicitly fixed-selection explanation/arithmetic evidence, not ranking. IDs and money are deterministic; only the bounded explanation enters a SHA-256-oriented blind A/B judge with the reviewed rubric, a pinned code-owned configuration, no tools, exact output schema, and untrusted-data delimiters.
- Both A/B orientations and decoding pass. Invalid, tied, or sub-0.70 judgments require review and cannot select the candidate. The full runner Deno suite passes 25 tests.

Ruling: Define the approved scoring rubric as a closed list of typed assertions over exact root-relative paths, while preserving an explicit `assertionKeys` severe override. Cost if wrong: existing free-form draft rubrics must be revised into the typed contract before they yield deterministic evidence, instead of being guessed by the scorer.

Ruling: Judge only fixed-selection explanation text, with the complete reviewed rubric, after deterministic card, benefit, savings, and final-amount checks. Cost if wrong: explanation comparisons cannot support a ranking-quality claim, but expected answers and arithmetic never contaminate the subjective comparison.

Ruling: Derive blind orientation from the first byte of SHA-256 over `run_id:case_id:revision`, using even for baseline A and odd for baseline B. Cost if wrong: the assignment is reproducible rather than nondeterministic, but remains balanced by cryptographic hashing and is recorded for audit/decoding.

### Task 5 review corrections

- Rubrics now use a fail-closed exact contract. Missing assertions, unknown top-level or assertion fields, unsupported operators, malformed paths, duplicate keys, or invalid operator-specific values emit `rubric_contract_invalid`; neither side passes and operator review is mandatory. No assertion is silently dropped.
- Executor and scorer share the exact grounded output validator and recursive structural equality implementation. Objects are key-order independent, arrays remain order-sensitive, and primitive types and numeric values remain exact.
- Invalid baseline schemas require review. Invalid candidate schemas and deterministic failures cannot be rescued by the explanation judge; the judge is not called unless both sides pass every deterministic assertion and the rubric contract is valid.
- Root frozen-lock verification identified the wildcard `@std/assert` entry as required by two existing versionless Feedback imports. It resolves to the already-pinned `1.0.19`, is retained in the code-bearing correction commit, and did not change across frozen eval and complete Edge Function runs.

Ruling: Treat any malformed or legacy free-form rubric as explicit non-passing evidence for both sides and require operator review. Cost if wrong: old cases must receive a reviewed rubric revision before comparison, preventing partial or guessed scoring.

Ruling: Reuse the executor's fixture-grounded output validator for both scorer sides and skip subjective judging unless both deterministic sides pass. Cost if wrong: captured production shapes that do not satisfy the current exact executor contract remain review-only instead of contributing incomparable baseline evidence.

Ruling: Retain the generated root-lock `jsr:@std/assert@*` resolution because existing versionless Feedback imports require it in the complete frozen suite. Cost if wrong: the lock contains one alias resolving to the same pinned version, avoiding future mutation during root verification.
