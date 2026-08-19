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
- Task 4: pending — code-owned configs and executors
- Task 5: pending — deterministic and blind scoring
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
