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
- Task 3: implementation complete, pending review — sanitized System gateway
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

## Tasks 1–2 review fix

- Added a shared, loopback-only PostgreSQL harness that starts from an environment allowlist, carries credentials only through libpq environment variables, rejects unsupported URL options, supports TCP and local socket connections, and cleans an exact generated database plus only roles it created.
- The opt-in disposable PostgreSQL run applies the foundation and runtime-control migrations and verifies exact replay, changed-request collision, missing/stale observed versions, monotonic timestamps, concurrent serialization to one receipt, browser denial, and rollback when audit insertion is forced to fail.
- Live local socket execution passed 4/4 and removed the disposable database and temporary roles. The live compile check exposed and fixed required parentheses around the replay action's PL/pgSQL `CASE` expression.

Ruling: Share the hardened PostgreSQL connection/process primitives while keeping each migration's schema fixtures and behavioral assertions local to its contract test. Cost if wrong: future harness hardening must preserve the shared helper API or update both integration suites together.

## Tasks 1–2 re-review fix

- The live collision case now preserves the same pause action and target while changing only the reason, proving rejection occurs at direct canonical-request comparison rather than the earlier action discriminator.
- Partial shared-role setup is exception-safe inside `ensureRoles`: roles are recorded immediately after creation and removed in reverse order before the original setup error is rethrown. A simulated failure after the first creation proves zero retained ownership and the exact cleanup command.

Ruling: Make shared role provisioning own cleanup until it successfully transfers the complete created-role list to its caller. Cost if wrong: a cleanup failure can mask the original provisioning error, but cannot silently return incomplete role ownership to the caller.

## Task 3 evidence

- RED: the focused Deno test failed type checking because `system.ts` did not exist.
- GREEN: the full admin-operator gateway suite passed 57/57 after implementation.
- Status reads isolate the two bounded job sources and the named control source, construct exact DTOs, and mark an unavailable pipeline `unknown` without leaking its database error.
- Job history permits one allowlisted family per request, strict family-specific statuses, exact UUID targeting, limits up to 50, deterministic `updated_at` then `id` descending order, and a single lookahead row.
- Recovery is limited to benefit-enrichment states actually accepted by `admin_card_data_action`; control changes use the one named key and `admin_set_runtime_control`. Both paths pass actor, request UUID, observed timestamp, and bounded reasons exactly.

Ruling: Treat `card_discovery` as status/history-only in System V1 because `admin_card_data_action` accepts discovery review IDs rather than discovery job IDs; exposing a job mutation would target the wrong aggregate. Cost if wrong: discovery recovery remains in its existing review workflow until a dedicated atomic job RPC exists.

Ruling: Represent unquarantine as `action: system-quarantine` plus the exact `operation: unquarantine`, keeping the published three-action System mutation surface while mapping to the existing audited RPC operation. Cost if wrong: clients must include one additional discriminator for unquarantine instead of calling a fourth action name.

Ruling: Read at most 1,000 rows per pipeline status source and return `unknown` on source failure; the operator gets bounded latency and partial health rather than an unbounded scan. Cost if wrong: counts on a pipeline with more than 1,000 recent rows are capped and should later move to a dedicated aggregate RPC.
