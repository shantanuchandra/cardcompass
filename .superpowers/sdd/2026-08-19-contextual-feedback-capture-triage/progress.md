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
- Task 4: pending — asynchronous tool-free LLM triage
- Task 5: pending — reusable Flutter feedback surface
- Task 6: pending — attach three product families
- Task 7: pending — Admin2 review and Inbox integration
- Task 8: pending — full verification

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
