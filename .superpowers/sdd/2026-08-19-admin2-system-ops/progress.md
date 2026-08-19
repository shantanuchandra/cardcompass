# Admin2 System Ops — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-system-ops.md`
- Base: `e493e5174b56e842dd186815323e836303249dbf`
- Status: active

## Preflight

- Foundation and Inbox & Card Data prerequisites are complete and independently reviewed.
- V1 has exactly one control: `benefit_enrichment_scheduled`; it affects scheduled orchestration only.
- Mutations stay single-target, audited, idempotent, observed-version gated, and server-confirmed.

Ruling: Implement Tasks 1 and 2 as one review unit because the plan explicitly requires the runtime-control schema to ship with its first worker consumer. Cost if wrong: review scope spans SQL plus one worker branch, but prevents an unused control or an unguarded worker from landing alone.

Ruling: Carry the prior plan's final adjudication ledger update into the Tasks 1–2 code-bearing commit, honoring the instruction not to commit documentation alone. Cost if wrong: the commit includes bookkeeping from the completed plan with no runtime effect.

## Tasks

- Tasks 1–2: implementation complete, pending review — runtime control and scheduled worker enforcement
- Task 3: pending — sanitized System gateway
- Task 4: pending — typed System workspace
- Task 5: pending — paused-pipeline Inbox item
- Task 6: pending — whole-phase verification

## Tasks 1–2 evidence

- RED: `node --test test/supabase/admin_runtime_controls_migration_test.js` failed 2/2 with `ENOENT` because the runtime-control migration did not exist.
- GREEN: foundation plus runtime-control migration contracts passed 4/4; the focused benefit-enrichment worker suite passed 20/20.
- The plan's nested Deno config path does not exist in this repository; the reviewed root `deno.json` dependency map was used instead.

Ruling: Serialize each `(actor_id, request_id)` before receipt lookup and persist the complete normalized request beside the bounded result; return a receipt only for direct canonical JSONB equality and reject changed semantics as `request_id_collision`. Cost if wrong: every control mutation takes one transaction-scoped advisory lock and older receipts lacking the canonical request cannot replay through this RPC.

Ruling: Require a non-null observed timestamp even for idempotent state assignments and advance `updated_at` monotonically by at least one microsecond while holding the control row lock. Cost if wrong: an operator refreshing at an unusually coarse timestamp boundary may need one extra reload, but stale concurrent writes cannot silently win.

Ruling: Check the named control after request authorization and run-mode parsing but before pilot status, catalog inventory, queue seeding, job counts, or claims; missing, errored, and malformed reads return the single safe `503 runtime_control_unavailable`. Cost if wrong: a transient control-store read failure pauses scheduled throughput until the next invocation rather than risking uncontrolled work.

Ruling: Keep pilot and manual modes outside the runtime-control query entirely, preserving explicit recovery during a scheduled pause. Cost if wrong: recovery traffic can still consume provider capacity during an outage and remains an intentional operator action rather than an automatic scheduler action.
