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
- Task 6: complete — private bounded resumable worker
- Task 7: complete — Admin2 controls and decision support
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

### Task 5 captured-card baseline correction

- Card capture now declares `catalog_identity_validation` from the contextual `user_card` target. The mode is fixture metadata, not expected ground truth, and candidate prompts still exclude captured output, expected output, feedback, rubric, and severe conditions.
- `captured-production-v1` normalizes persisted `{user_card,catalog_card,benefits}` into the exact identity or benefit executor output contract selected by fixture mode. Captured fields supply answer values; official evidence supplies only bounded citations and grounding validation.
- Identity maps catalog ID/name/issuer/network/fees. Benefit mode maps persisted benefit ID/title/type/category/value configuration/derived structured limits and attaches official benefit citations. Ambiguous modes, missing captured fields, absent grounding, or mismatched evidence return `insufficient_fixture` before scoring.
- Real normalized identity and benefit baselines validate under the shared executor/scorer contract. A normalized passing identity baseline produces a severe reviewed regression for an invalid candidate identity.

Ruling: Set the current `user_card` feedback fixture to `catalog_identity_validation`; support `benefit_extraction` only when the fixture explicitly selects it. Cost if wrong: existing ambiguous card cases remain insufficient until revised, and future benefit-specific capture must set its contextual mode rather than inferring it from expected output.

Ruling: Normalize captured card answer values into the selected evaluator schema, then use source evidence only for citations and validation. Cost if wrong: a persisted answer that lacks matching official provenance becomes `insufficient_fixture` instead of a schema-invalid baseline or a source-rewritten answer.

### Task 5 citation-consensus correction

- Every citation emitted by captured identity or benefit normalization now independently supports the complete normalized answer. Identity sources must agree on catalog reference, issuer, name, network, and fees. Benefit sources must agree on captured card linkage and the full normalized benefit set.
- Any applicable source that conflicts with the captured answer or another applicable source causes `insufficient_fixture`, including a valid benefit source accompanied by benefit evidence for another card.
- Sources discriminated for the other evaluation mode are ignored and never emitted. Existing identity and benefit normalization tests prove their unrelated counterpart source is absent from citations.
- The same per-citation agreement checks strengthen candidate output validation, so an output cannot cite a conflicting applicable source merely because another source supports it.

Ruling: Require unanimous support from every official source applicable to the explicitly selected card evaluation mode; ignore only sources with a different mode discriminant. Cost if wrong: partial/conflicting provenance reduces runnable coverage, but no citation can imply support it does not provide.

### Task 5 candidate citation-completeness correction

- Candidate Card Data validation now derives the complete same-mode official-source set from the fixture and requires the candidate citation IDs to match it exactly. A candidate cannot omit adverse applicable evidence while citing only an agreeing source.
- Every applicable identity or benefit source is then checked through the same consensus rules as captured normalization. Identity conflicts and wrong-card benefit linkage produce `invalid_model_output`; other-mode evidence remains outside the applicable set.
- Explicit regressions cover an identity candidate cherry-picking one agreeing source while omitting a second conflicting source, and a benefit candidate omitting applicable evidence linked to another card.

Ruling: Require candidate Card Data citations to equal the full applicable same-mode fixture source set, then validate every source. Cost if wrong: redundant applicable sources must all be cited, trading payload brevity for complete and non-cherry-picked provenance.

### Task 5 canonical citation-path correction

- Captured normalization and candidate validation now share one canonical mode-specific grounding-path helper. Identity citations bind catalog ID and fees plus provenance name, issuer, and network; benefit citations bind both catalog card linkage and the complete official benefit facts.
- Merely resolvable paths are insufficient. Candidate citations using `url`, a generic provenance object, an unrelated fact, reordered paths, or partial support return `invalid_model_output`.
- The fixed candidate prompt publishes the same exact canonical arrays, preventing a hidden validator-only convention. Positive identity/benefit cases and normalized captured baselines use the identical path contract.

Ruling: Require exact ordered canonical grounding paths per Card Data mode, shared by prompts, captured normalization, and candidate validation. Cost if wrong: adding a newly scored card field requires an explicit reviewed path-contract update, preventing generic citations from masquerading as field support.

### Task 5 effective-network evidence correction

- Identity normalization and validation now take the asserted network exclusively from `catalog_reference.network`, and the canonical citation binds that exact field.
- `provenance_claims.network` remains a consistency signal: null/absent provenance is accepted when catalog network is present, while any conflicting non-null provenance network fails closed.
- The shared canonical helper, fixed candidate prompt, normalized outputs, scorer fixtures, and real Feedback integration all use `facts.catalog_reference.network`.

Ruling: Use catalog-reference network as the identity network oracle and citation target; treat a non-null provenance network only as a required consistency check. Cost if wrong: provenance cannot independently override the selected catalog network, preventing a null or contradictory extraction from becoming ambiguous evidence.

## Task 6 evidence

- RED: the worker suite first failed because the private entrypoint did not exist. Subsequent red cycles proved the missing lease-yield RPC, explicit private function configuration, safe scoring-failure persistence, and recovery when background-task registration throws.
- GREEN: service-role authorization uses fixed-length SHA-256 comparison and occurs before method handling, body reads, or database access. The body is the exact bounded `{run_id}` schema; user/admin bearer tokens are rejected.
- Each invocation claims at most five manifest entries, reloads the immutable case revision, checks run status and lease ownership between cases, executes baseline/candidate and scoring sequentially, and persists outputs, assertions, verdict, regression flags, latency, tokens, and cost through the fenced result RPC.
- A five-case batch yields its lease while preserving `running`, then schedules one self-continuation with `EdgeRuntime.waitUntil`. Promise rejection or synchronous scheduler registration failure leaves the run unleased and resumable. Smaller/empty final batches finish through the existing terminal RPC.
- Candidate and blind-judge metering are aggregated into the candidate-side persistence fields. Recommendation per-case cost projection includes the judge ceiling. Provider/executor/scoring failures persist only stable categories and metering; responses contain only run/status/count receipts.
- Focused Eval tests pass 51/51. The frozen full Edge Function suite passes 246/246. Deno formatting, type-check, and diff checks pass.

Ruling: Yield a full-batch lease before scheduling continuation while keeping the run in `running`. Cost if wrong: a scheduler failure requires a later retry, but no active lease or false terminal state blocks exact resume.

Ruling: Aggregate blind-judge usage into the candidate token, latency, and cost fields and reserve its reviewed $0.01 ceiling for recommendation cases. Cost if wrong: the schema does not distinguish judge usage from candidate usage, but total metering and ceiling enforcement remain conservative and auditable.

Ruling: Treat unexpected executor or scorer exceptions as a persisted `provider_failed` case with any metering accumulated before failure. Cost if wrong: configuration defects appear as safe reviewed failures rather than leaking internals or abandoning the entire resumable run.

### Task 6 review corrections

- Run and result storage now carry a server-owned retry generation. A result attempted in the current generation, whether succeeded or failed, is no longer eligible for automatic continuation; untouched cases remain eligible and cannot be starved by failed cases.
- `resume_failed` atomically advances the retry generation. This makes prior failed results eligible only after the existing explicit audited operator action, while successful results remain immutable and cumulative attempt metering is preserved on failed-result upsert.
- The fenced yield RPC computes `continuation_required` from authoritative manifest/result state. It releases the lease only when eligible untouched/retry-generation work remains; otherwise the worker retains its lease and finishes. Exactly five successes and five zero-cost failures therefore terminate without a false continuation.
- Worker receipts expose only `continuation_required`, not a claim that asynchronous scheduling succeeded. Promise or background-registration failures leave the database in the authoritative `running`, unleased, resumable state.
- Disposable PostgreSQL lifecycle coverage passed 2/2 against the local server, including first-batch failures followed by untouched cases and explicit failed retry. The frozen Edge suite passed 247/247; migration source suites passed 38 with 5 unrelated opt-in integrations skipped.

Ruling: Use a monotonically increasing retry generation to distinguish untouched work from a terminal failed attempt. Cost if wrong: each explicit retry adds one integer generation and cumulative result update, but automatic continuation cannot loop on failures or starve later cases.

Ruling: Let the fenced database yield receipt be the sole authority for `continuation_required`; never infer remaining work from a five-case batch. Cost if wrong: every processed invocation performs one additional lightweight locked eligibility query before either continuation or finish.

Ruling: Report `continuation_required` rather than asynchronous scheduling success. Cost if wrong: an operator may need to observe/reinvoke a resumable running job after infrastructure failure, but the receipt never overstates delivery.

## Task 7 evidence

- RED: gateway tests failed because no eval actions existed; Flutter repository and panel tests failed because no strict DTOs, controls, or responsive instrument existed. A full Admin Operator run then exposed eager environment access in unrelated routes, which was corrected by constructing the private scheduler only for eval mutations.
- GREEN: frozen, null-prototype handlers now list code-owned configs, filter and paginate runs, audit before detail reads, return only bounded aggregate/per-case summaries, create version-bound runs through the audited RPC, and schedule the private worker through injected `waitUntil`/`fetch`. Response-loss replay accepts every authoritative durable run status and never reschedules a terminal run.
- Cancel and `resume_failed` carry exact request IDs and observed timestamps. The database RPC now compares `updated_at` under its row lock, includes the canonical observed timestamp in replay/collision identity, and returns stable conflicts without a preflight race.
- The System workspace includes a responsive evaluation instrument with server filters/pages, 390px drill-in, exact configuration scope, start cost/case/latency confirmation, refresh-after-mutation, stale retained state, 401/403 effects, and no deploy/publish action.
- Decision support is fail-closed: support requires an improved candidate pass rate, zero severe regressions, actual cost and p95 latency inside run ceilings, a complete run, and no candidate/judge/manual-review blockers. Recommendation evidence is always labeled `fixed_selection_explanation_and_arithmetic` and “Does not evaluate ranking.”
- Focused Flutter tests pass 9/9; complete Admin2 tests pass 171/171; Admin Operator Deno tests pass 102/102; the full frozen Edge suite passes 255/255. Scoped analysis, Deno check, formatting, migration source contract, and diff checks pass. The disposable PostgreSQL test remains opt-in in this task environment.

Ruling: Treat a baseline-only deterministic miss as the measured improvement opportunity, not by itself a manual-review blocker, because candidate support also requires candidate pass rate to improve. Cost if wrong: an operator sees support only when the candidate passes those cases and every independent severe, cost, latency, judge, completion, and review gate also passes.

Ruling: Return a durable start receipt for queued, running, or terminal response-loss replay, and schedule only queued/running receipts. Cost if wrong: a replay never turns a completed run into an error or unnecessary worker call, while the authoritative database status remains visible.

Ruling: Enforce eval cancel/resume optimistic concurrency inside the existing unreleased lifecycle RPC rather than with a gateway preflight. Cost if wrong: callers must send the exact observed `updated_at`, but stale actions cannot race past the row lock.

### Task 7 review corrections

- The scorer-owned `requiresReview` result is now persisted as a safe boolean and read directly by Admin2. Missing verdicts, ties, and confidence below 0.70 therefore retain exact scorer semantics instead of being reconstructed by the gateway.
- Candidate support now requires exact `completed` status, an authoritative complete aggregate, zero failed/missing/insufficient-fixture cases, one represented successful result per manifest case, zero result review flags and severe regressions, an improved pass rate, and cost/latency within ceilings. Partial and `completed_with_failures` runs always require review.
- Admin kickoff validates the private runner's real exact safe receipts: running continuation, not-claimed/cancelled, terminal, and cost-stop. The invented scheduling receipt was removed; durable start replay remains independent of background response delivery.
- Review regression evidence passes: Admin Operator 105/105, runner 52/52, full frozen Edge 258/258, Admin2 171/171, and disposable PostgreSQL 2/2.

Ruling: Persist the scorer's bounded review bit with each result and treat it as authoritative presentation evidence. Cost if wrong: one safe boolean is stored per case, while judge internals and raw output remain private and review semantics cannot drift across layers.

Ruling: Require completed, internally consistent server aggregates and full result representation before supporting a candidate. Cost if wrong: malformed or legacy aggregates remain review-only, preferring operator attention over a false-positive recommendation.

Ruling: Share an exact validator for the runner's existing safe receipt vocabulary. Cost if wrong: a future runner receipt change must update this private contract explicitly, but kickoff cannot mistake an invented delivery acknowledgment for executed work.

### Task 7 re-review corrections

- Structured and recommendation scoring now distinguish a valid baseline-only assertion miss from invalid evidence. A passing candidate is not held merely because it improves a normal deterministic assertion; invalid baseline schema/rubric, candidate misses, regressions, severe failures, and ambiguous judge evidence remain review-only.
- Recommendation scoring invokes the blind judge when the rubric, baseline schema, and candidate are valid even if a normal baseline assertion missed. Only an exact candidate win at confidence >=0.70 can avoid review; baseline wins, ties, low confidence, missing/invalid verdicts remain reviewed.
- A real structured score is carried through the persisted safe fields and Admin2 detail presenter to prove `candidate_supported` is reachable without fabricated scorer semantics.
- The shared private runner receipt validator now accepts only producer-real terminal statuses (`completed`, `completed_with_failures`), plus actual 202 running/not-claimed/cancelled and the exact cost-stop variant. Runner tests validate its own produced bodies through the shared parser.
- Re-review verification passes: full frozen Edge 262/262, Admin2 171/171, live disposable PostgreSQL 2/2, scoped Flutter analysis, Deno check/format, and diff checks.

Ruling: Treat normal baseline-only misses as measurable improvement while retaining review for invalid baseline schema or rubric. Cost if wrong: a valid candidate can be supported against weaker production behavior, but any uncertainty in evidence validity still fails closed.

Ruling: Restrict terminal kickoff receipts to statuses emitted by `finish_ai_eval_run`; reject hypothetical failed/cancelled HTTP 200 shapes. Cost if wrong: adding a future terminal producer status requires an explicit parser and contract-test update.
