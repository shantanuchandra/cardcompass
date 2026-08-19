# Contextual Feedback Capture & Triage — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-contextual-feedback-capture-triage.md`
- Base: `729d811`
- Status: active

## Preflight

- Admin2 foundation and cutover release candidate are complete and reviewed; feedback/evals remain additive and undeployed.
- Feedback is always bound to a server-resolvable AI output; global/general feedback is excluded.
- User text is stored for this MVP, but raw email/PDF/history/provider credentials remain prohibited.

Ruling: Implement Tasks 1–3 as one review unit because private storage and narrow RPCs have no user value until the authenticated ownership-resolving endpoint consumes them. Cost if wrong: the first feedback commit spans SQL plus one Edge boundary, but no unused private schema lands alone.

Ruling: Carry the Cutover final-fix adjudication into the Tasks 1–3 code-bearing commit. Cost if wrong: completed-plan bookkeeping shares a commit with feedback code and has no runtime effect.

## Tasks

- Tasks 1–3: complete — private storage/RPCs and authenticated endpoint
- Task 4: complete — asynchronous tool-free LLM triage
- Task 5: complete — reusable Flutter feedback surface
- Task 6: complete — attach three product families
- Task 7: complete — Admin2 review and Inbox integration
- Task 8: complete — full verification and local recovery evidence

## Tasks 1–3 evidence

- RED: the migration contract failed with `ENOENT`, and the focused Deno suite failed because the endpoint and validation modules did not exist.
- GREEN: private RLS-backed trace, feedback, and versioned eval-case storage now exposes only narrow service-role RPCs. User writes are UUID-idempotent with collision detection; triage claims use a five-minute recoverable lease; human review and case actions are atomic with audit receipts and observed-version checks.
- The endpoint uses verified end-user authentication and the shared active-profile gate before any service operation, strict exact-key parsing, a 64 KiB whole-body cap, safe ownership projections, active recommendation catalog validation, client-reported provenance, stable errors, and injected `waitUntil` background scheduling.
- Focused Node contracts pass 3/3, endpoint Deno tests pass 3/3, `deno check` passes, and the disposable PostgreSQL suite passes 2/2 including compile, replay/collision/concurrency, claim recovery, human revision/versioning, browser denial, and audit rollback.

Ruling: Represent a review action named `dismiss` as the persisted terminal status `dismissed`; keep the action vocabulary distinct from the row-state vocabulary. Cost if wrong: consumers that incorrectly equate action and status must map this one terminal transition explicitly.

### Tasks 1–3 review corrections

- Recommendation traces now carry bounded server-resolved active card and benefit facts through resolution, feedback persistence, triage fixtures, and eval-case input fixtures. The captured recommendation remains explicitly `client_reported`; engine/model/prompt metadata is preserved without trusting client-supplied catalog facts.
- Trace replay equality covers safe input, client-reported output, authoritative facts, engine/model/prompt metadata, feature, and normalized expiry. Any changed provenance under one request ID is a collision.
- Triage claims now issue a rotated UUID lease token. Completion requires the current token and `triaging` state; expiry/reclaim rotates the token and stale completion fails with `state_conflict`.
- Eval-case content is immutable on every update. A trigger permits only RPC-marked `draft → approved` and `approved → retired` lifecycle updates; revision creates a new draft row, and direct ground-truth mutation fails and rolls back.
- Real resolver/query tests cover foreign transaction, statement, user-card, and trace ownership; expired traces; inactive catalog references; exact safe projections; and authoritative-context propagation.

Ruling: Make the triage claim token part of the Task 4 persistence interface: `claim_ai_feedback_triage(id)` returns `claim_token`, and `complete_ai_feedback_triage(id, claim_token, succeeded, result, failure_category)` rejects stale workers. Cost if wrong: every triage caller must carry one additional UUID, but delayed workers cannot overwrite a newer claim.

Ruling: Store recommendation authoritative facts separately from the client-reported output and combine them only in the immutable eval input fixture. Cost if wrong: fixture consumers must read two named branches instead of one flattened object, preserving trust provenance.

## Task 4 evidence

- RED: shared triage/transport tests first failed because the modules and injectable proxy handler did not exist; the all-keys-429 regression test then caught an initial extraction that stopped before model fallback.
- GREEN: the shared transport preserves proxy key/model fallback, per-attempt 25-second timeout, upstream status/body, and safe internal failures. The public proxy retains its authentication, active-profile, quota, 100,000-character serialized-payload boundary, allowlist, CORS, and safe server errors.
- Triage uses the existing supported server-pinned `gemini-3.6-flash`, a fixed injection-resistant system instruction, no tool channel, a closed bounded schema, and rotated claim tokens. Feedback submission schedules the real worker with `waitUntil` and still returns `202` independently of triage success.
- Focused tests pass 18/18 across transport, parser/worker, proxy compatibility, context resolution, and endpoint async behavior. The complete Edge Function suite passes 174/174; both changed function entry points pass `deno check`.

Ruling: Cap each proposed triage object at 8 KiB and the complete triage JSON at 15,000 UTF-8 bytes so validated output remains below the database's 16 KiB jsonb text constraint after jsonb normalization. Cost if wrong: unusually large advisory proposals are rejected for manual triage instead of consuming the database's full theoretical boundary.

### Task 4 review corrections

- Restored exact legacy fallback sequencing: every configured key is attempted for the current unavailable model before advancing to the next supported model; 429 key rotation and upstream status/body behavior remain intact.
- Model-failure completion now gets one bounded recovery attempt using `triage_persistence_failed`. A stale claim conflict is ignored without overwrite, while two persistence failures leave the lease for the existing five-minute database recovery path.

Ruling: Limit triage completion recovery to two total attempts and then rely on the database claim lease timeout. Cost if wrong: a transient second persistence failure delays retry until lease expiry, avoiding an unbounded Edge background loop.

## Task 5 evidence

- RED: focused Flutter tests first failed on the absent feedback feature, then caught missing whole-request bounds, malformed output references, keyboard focus competition, and off-screen mobile action interaction before the implementation was accepted.
- GREEN: sealed transaction, statement, user-card, and recommendation-trace targets make feature/reference mismatches unrepresentable. The injected repository emits exact Edge payloads, validates UUIDs and the 32 KiB UTF-8 request boundary, maps strict responses to safe errors, creates server-issued recommendation traces, and never accepts client context/model metadata during feedback submission.
- The reusable button and sheet bind feedback to a concise caller preview, require 10–2,000 characters, expose a live count and accessible 44 px action, autofocus the field, support Escape, preserve text and request identity on retry, allocate a new identity after edits, and render without overflow at 390 logical pixels / 2x.
- Focused feedback tests pass 11/11 and scoped static analysis is clean.

Ruling: Provide feedback transport through an explicit `FeedbackRepositoryScope` so product attachment points own their Supabase boundary and widget tests remain backend-free. Cost if wrong: each supported screen must install one small scope instead of reading a global client singleton.

Ruling: Enforce a 32 KiB UTF-8 limit over the complete client request even though the Edge transport also carries independent nested-object bounds. Cost if wrong: a trace near the server's per-object maximum may be rejected client-side once envelope overhead is included, favoring a predictable transport ceiling.

### Task 5 review corrections

- Submission now freezes the visible text and request ID for the full in-flight interval. The field and dismissal paths are disabled while sending; success and failure apply only to that frozen snapshot, and failure restores the exact text for an idempotent retry.
- Successful feedback and trace responses now require UUID-shaped `feedback_id` and `trace_id` values before constructing typed results; malformed identifiers map to the stable `request_failed` category.
- Controlled-completion widget tests exercise attempted edits and Escape during flight, success association, and failure retry identity. Focused coverage now passes 14/14.

Ruling: Treat an in-flight feedback submission as an immutable UI transaction: freeze text/request identity and block editing or dismissal until the endpoint settles. Cost if wrong: users cannot abandon a slow request mid-flight, but the displayed outcome can never describe a different payload than the one actually sent.

## Task 6 evidence

- RED: focused transaction, owned-card, and movie-result widget tests first failed because the rendered outputs had no contextual actions.
- GREEN: every rendered transaction row submits its exact transaction UUID with only a short merchant/amount preview; Card Detail submits the loaded owned `user_card` UUID rather than its catalog-card identity; each movie candidate lazily creates an exact recommendation trace only when feedback opens.
- Recommendation traces contain allowlisted ticket request fields, the selected card/benefit IDs, and a bounded selected-output snapshot only. No candidate list, rejected history, provider token, raw context metadata, or unrelated user history enters the client payload.
- Expired recommendation traces recreate once inside the open sheet while preserving entered text; the refreshed trace/request becomes the retryable submission if its send fails. Other trace/open failures render a safe retry message.
- The authenticated `/app` subtree installs a real repository through the Riverpod-provided Supabase client, while focused widget tests explicitly install backend-free repositories.
- The three focused feature suites plus all feedback tests pass 62/62; the expiry regression passes in the 8-test sheet suite; scoped analysis is clean and repository-wide analysis has only the 12 pre-existing unrelated info diagnostics.
- The broader Admin2 regression run exposed eager Supabase resolution on a non-feedback route. Repository construction is now lazy until a feedback control actually opens; all 152 Admin2 tests and all 15 feedback tests pass.

Ruling: Create recommendation traces per selected rendered candidate, only when its feedback control opens, and capture only that candidate's card/benefit IDs and displayed monetary result. Cost if wrong: cross-candidate comparison context is intentionally unavailable to eval triage, preventing unrelated catalog/history leakage.

Ruling: Install the production feedback repository only beneath authenticated `/app` routes while keeping `FeedbackRepositoryScope` as the explicit widget-test override seam. Cost if wrong: a future non-`/app` authenticated route must opt into the scope before showing contextual feedback.

### Task 6 review corrections

- A recreated recommendation trace is now promoted to the sheet's effective target. If submission against the refreshed trace fails and the user edits, the new request ID remains bound to the refreshed trace; the expired ID is never reused and recreation remains limited to one automatic attempt.
- Card Detail now bounds the complete composed preview, including bank text, to 120 Unicode code points and 256 UTF-8 bytes before the same value reaches visible content and derived semantics. A long multilingual-bank regression covers both ceilings.
- Focused attachment, feedback, and Admin2 suites pass 245/245 after the corrections. Repository analysis is back to the 12 unrelated pre-existing informational diagnostics.

Ruling: Promote a successfully recreated recommendation trace to the sheet's effective target for the rest of that sheet session. Cost if wrong: later edited submissions intentionally stay attached to the refreshed output rather than attempting another server trace.

Ruling: Bound feedback previews at the shared presentation boundary to 120 Unicode code points and 256 UTF-8 bytes. Cost if wrong: extremely long display metadata is truncated in the feedback sheet and semantic label, while the underlying product data remains unchanged.

## Task 7 evidence

- RED: new gateway and Flutter tests failed on the absent feedback registry, review handlers, typed models, detail surface, and feedback Inbox adapter.
- GREEN: the frozen gateway now exposes exact feedback list/detail/review/retry and eval-case actions with bounded filters, deterministic pagination, safe DTOs, UUID request receipts, audit-before-detail reads, human-authored ground truth, observed-version lifecycle actions, and typed confirmations. Draft receipts are enriched with the authoritative case version needed for a separate approval.
- Failed triage alone can be reset to `awaiting_triage`; the retry is audited, claim-token processing is scheduled with `waitUntil`, and a scheduling exception leaves the row in the retryable state.
- Pending feedback is a distinct, fail-isolated Inbox source. Critical/high advisory severity affects rank only; review remains pending and deep-links by exact feedback ID.
- Admin2 distinguishes user text, captured safe fixture, advisory LLM text, and operator ground truth. The proposal is editable, required human fields gate draft creation, approval requires a second typed confirmation, and reasoned data/product/dismiss routes remain explicit.
- All 91 Admin gateway tests and all 154 Admin2 tests pass. Focused feedback/Inbox coverage passes 20 Deno and 19 Flutter tests; scoped analysis and `git diff --check` are clean.

Ruling: Keep LLM triage strictly advisory and require a separately persisted operator draft plus typed `APPROVE` confirmation before dataset admission. Cost if wrong: the founder performs one additional confirmation step, but no model-authored proposal can become ground truth autonomously.

### Task 7 review corrections

- Advisory expected output is now displayed only in the LLM panel; every operator field starts blank. Draft/revision requests require `ground_truth_confirmed: true` at the gateway plus meaningful non-empty expected output, rubric, and severe-condition objects under the existing byte bounds.
- The detail surface carries generation-scoped load futures into the existing 401 signout/re-auth and 403 ordinary-app return effects. Stable request errors remain retryable, while malformed JSON and state conflicts have distinct messages and conflict refreshes the authoritative version.
- One shared in-flight guard now covers draft, approval, reasoned routing, and triage retry. Every mutation control disables synchronously, repeated activation is ignored, and successful actions refresh server state before further work.
- Bounded source provenance and eval-case lifecycle metadata are visible with explicit unknown/not-applicable labels; no credentials, email, or raw source content are selected or rendered.
- Post-correction verification passes 91/91 Admin gateway tests and 155/155 Admin2 tests; scoped analysis and diff checks are clean.

Ruling: Never seed an operator ground-truth editor from an LLM proposal; require an explicit human-authorship confirmation at the server boundary for both draft creation and revision. Cost if wrong: operators must deliberately enter or paste expected values even when the advisory proposal is correct, preserving provenance over speed.

## Task 8 evidence

- The full Flutter suite passes 691 tests with 25 explicit pre-existing Supabase integration skips. The full Node suite passes 49 tests with four explicit PostgreSQL opt-ins skipped in the ordinary run; all four opt-ins were then run sequentially against one disposable loopback PostgreSQL cluster and passed 17/17 with no skips. The full Edge suite passes 184/184.
- Repository-wide `flutter analyze --no-fatal-infos` exits clean with the same 12 unrelated pre-existing informational diagnostics. Scoped Dart and feedback/Admin Deno format checks are clean; the plan's broad format command identified and then reverted unrelated legacy formatting drift instead of mixing it into this phase.
- The full Node gate exposed a stale authenticated-gateway inventory. The test now includes `feedback-submit/index.ts` and proves it is discovered and active-profile-gated. Additional handler tests prove feedback detail audits before either data read and Admin retry audits, resets, claims, and persists the safe `model_unavailable` category through an injected model with a fail-fast network transport.
- The local recovery evidence covers the real feedback handler's immediate `202`, preserved submitted text, disposable-PostgreSQL `triage_failed` and rotated-token reclaim, validated advisory completion, operator-authored draft, explicit approval, and exactly one dataset-version increment. Feedback mutations touch only `ai_output_traces`, `ai_feedback`, `ai_eval_cases`, and `admin_audit_log`; no production catalog or product-output table is auto-mutated.
- Privacy scans found no persisted or returned email body, PDF bytes, provider/OAuth credential, statement history, or transaction history. The only exact-term matches are Authorization transport/header handling and explicit resolver rejection fixtures. Exact-key parsers are present at the user endpoint and every Admin feedback action.
- A live PostgREST stack was not available because the local Docker daemon was unavailable. The production PostgREST client was exercised directly and serialized the severity containment as `triage_result=cs.{\"severity\":\"high\"}` with deterministic dual ordering and range; database JSONB behavior is separately covered by disposable PostgreSQL, but a live HTTP/PostgREST round trip is Not Run.

Ruling: Inject the Admin retry model, scheduler, and network transport at the handler boundary so unavailable-model recovery is deterministic with no environment permission or external request. Cost if wrong: the handler carries one optional internal dependency seam, but its registered two-argument production contract and default Gemini construction remain unchanged.

## Final-review corrections

- Recommendation traces now use one exact Movie Deals input/output schema at both client and Edge boundaries. Nested or unknown fields and client version spoofing are rejected; engine/model/prompt metadata is pinned by the server.
- Accepted feedback replay is resolved from immutable original intent before mutable context lookup and always returns the original ID with the stable awaiting-triage receipt, even after triage or source expiry/change.
- Admin2 now has a durable Feedback workspace across every review state. Feedback detail exposes authoritative context and complete persisted eval ground truth/lifecycle with Back navigation and linked Card Data routing.
- Admin retry is one service-only transactional reset/idempotency/audit RPC. Its request identity survives transport retry, processing remains lease-recoverable, and every contiguous Gemini key is discovered through one shared helper.
- Data-issue routing requires an exact `card_identity|benefit_enrichment` destination plus optional UUID target and renders a non-mutating Card Data deep link.
- The shared feedback control and sheet independently enforce the 120-code-point/256-byte preview boundary for every caller.

Ruling: Supersede client-supplied recommendation engine metadata with server-pinned `movie-deals-v2`, `deterministic-rule-engine`, and `movie-deals-v2` provenance after validating the exact rendered Movie Deals fixture. Cost if wrong: a new recommendation engine requires a deliberate server allowlist/version change instead of being self-declared by the app.

Ruling: Supersede mutable-fixture replay equality with immutable accepted-intent equality `(user, request_id, feature, ref type, ref id, trimmed text)` and return the original stable awaiting-triage receipt. Cost if wrong: context that changes after acceptance remains historical evidence on the first row and cannot turn a safe transport replay into a new submission.

Ruling: Add Feedback as a fifth Admin2 workspace because completed drafts and lifecycle records must remain discoverable after leaving the pending-only Action Inbox. Cost if wrong: the founder sees one additional navigation destination, while Inbox prioritization remains focused on pending work.

Ruling: Represent data-issue linkage as a validated advisory destination and optional target UUID without mutating catalog data. Cost if wrong: the operator may need to select the exact Card Data record after following a lane-only link, preserving the no-auto-mutation boundary.

Ruling: Queue admin triage retry atomically with a successful mutation receipt whose audit details explicitly record `execution_state: queued`; claim-token execution remains independently recoverable and records its eventual safe failure on the feedback row. Cost if wrong: audit success means durable queue acceptance, not synchronous model completion.

### Final-review follow-up corrections

- Feedback discovery is now a typed, server-paginated workspace with exact page/limit/total metadata, stable status filters, mobile-safe previous/next controls, and retained last-good content when a refresh fails. Exact Inbox deep links continue to load detail independently of the current list page.
- Detail returns, strictly parses, and renders every available case revision in descending revision order, including the complete captured/input/expected/rubric/severe fixtures and approval/retirement lifecycle. The newest revision is explicitly marked current/actionable without hiding history.
- Triage retry identity now belongs to an explicit `FeedbackTriageRetry` mutation created and retained by FeedbackDetail state. Repositories are stateless: repository recreation and parent rebuilds reuse the same mutation body after ambiguous response loss, and only an authoritative success clears it.

Ruling: Page Feedback through deterministic server pages and retain the last successful page during refresh failure. Cost if wrong: operators use explicit Previous/Next controls instead of one unbounded list, keeping memory and gateway response sizes predictable beyond 100 records.

Ruling: Make `FeedbackTriageRetry` the owner of retry request identity and keep it in the detail-state transaction until authoritative success. Cost if wrong: navigating away intentionally abandons the local retry affordance, while server-side receipt replay still prevents duplicate execution if the same mutation is retried by retained state.

## Eval whole-plan integration correction

- Card feedback explicitly distinguishes catalog identity validation from benefit extraction in the contextual sheet and request contract. The server derives both captured answers and mode-applicable official evidence from the owned `user_card`; it never trusts client answer values.
- Mode is persisted in the immutable safe input fixture. Receipt lookup compares it as part of retry intent, so reusing a request ID with a different mode fails as a collision. Approved revisions continue to copy the immutable fixture rather than mutating it.
- Resolver/endpoint/executor tests cover both real captured modes, deterministic source ordering/deduplication, the 20-source ceiling, review-only unavailable evidence, and candidate-input exclusion. Disposable Feedback PostgreSQL passes 2/2.

Ruling: Include Card Data evaluation mode in immutable replay intent and derive all answer/evidence fields server-side. Cost if wrong: old clients must update to send one allowlisted field for card feedback, preventing transport retries from changing the meaning of accepted evidence.

## Final adjudication

- The single final-fix owner resolved all whole-plan findings in `939ea8c`; the scoped re-review's two valid durability residuals were resolved by the same owner in `7527ee1`.
- Controller verification passed five focused Feedback detail tests and seven focused Admin gateway tests, including rebuild-stable retry identity and complete revision history. No unresolved capture/triage finding remains; the plan is approved to continue to the eval runner.
