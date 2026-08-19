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
- Task 4: implementation complete, pending review — typed System workspace
- Task 5: implementation complete, pending review — paused-pipeline Inbox item and exact System control deep link
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

## Task 3 review fix

- Replaced the capped row sample with bounded exact PostgREST count queries for each operational status and one deterministically ordered latest-success row per family. Malformed or failed counts make only that pipeline unavailable.
- A failed, missing, or malformed named-control read now returns `control_source_error: source_unavailable` and makes benefit enrichment `unknown`, matching the worker's fail-closed behavior.
- Mutation receipts must match the requested job and exact resulting status. Control receipts must match the key, state, normalized reason, and contain a valid version strictly newer than the observed version.
- Full admin-operator suite passed 61/61 and the production entry point passed `deno check`.

Ruling: Supersede the 1,000-row sampling decision with exact `head: true, count: exact` queries per relevant status plus a one-row ordered success query. Cost if wrong: System status issues more small database requests per refresh, but counts remain correct at any row volume without transferring job records.

Ruling: Treat named-control unavailability as benefit-pipeline unavailability and expose only the stable `control_source_error` category. Cost if wrong: a transient control read failure hides otherwise valid benefit counts behind `unknown`, deliberately matching scheduled-worker fail-closed semantics.

Ruling: Reject successful RPC responses unless their bounded receipt proves the exact requested target, state, and a newer control version. Cost if wrong: an older RPC implementation returning incomplete receipts will fail safely until its response contract is upgraded.

## Task 4 evidence

- RED: the repository suite failed to compile because the typed System models/repository did not exist; the widget suite then failed to compile because the System section and injected data-source seam did not exist.
- GREEN: the focused repository, section, and shell suites passed 31/31; the full Admin2 Flutter suite passed 111/111; targeted analysis reported no issues.
- The repository strictly decodes exact status, control, job, pagination, and mutation receipt fields; rejects malformed/coercible values and mismatched receipts; bounds complete UTF-8 requests to 32 KiB; and generates one fresh UUID for each operator submission.
- The workspace retains prior data during failed refreshes, marks it stale with its server-refresh time, exposes source/control uncertainty, and separates compact job browsing from detail/recovery.
- Mutations begin from a detail/confirmation surface, require bounded reasons for quarantine/pause/resume, disable duplicate submission, await server confirmation, and reload after success or state conflict. Authentication and authorization failures use the shell's injected effects.

Ruling: Keep System status and job history in one injected `SystemDataSource` owned by the section, with the production shell adapting `SystemRepository`; this avoids hidden provider reads inside the operational UI and makes 401/403, stale refresh, and mutation behavior deterministic in tests. Cost if wrong: future caching shared across admin sections requires an adapter/provider above this seam rather than adding Riverpod dependencies directly inside the section.

Ruling: Treat only benefit-enrichment jobs as mutable in the Dart repository, matching the gateway's existing atomic job RPC, while continuing to render card-discovery health and history as read-only. Cost if wrong: a future discovery recovery RPC needs a deliberate new mutation type and allowlist change before the UI can expose it.

Ruling: Validate successful mutation receipts again at the client boundary and require job target/result or control key/state/reason/newer-version equality before refreshing the workspace. Cost if wrong: a temporarily skewed older backend response fails safely as `request_failed` even if the server-side mutation committed, requiring an operator refresh before another action.

Ruling: Use 1024 logical pixels as the System master-detail breakpoint and a single scrollable compact drill-in below it, preserving minimum 44-pixel controls and exact operational context at 390 pixels. Cost if wrong: medium-width tablets use the compact navigation pattern rather than a denser split view.

## Task 4 review fix

- Added one typed `SystemJobPolicy` consumed by both repository preflight and UI rendering. Its complete matrix mirrors the gateway: benefit retry from failed/review-required/quarantined, quarantine from queued/failed/review-required/staged, unquarantine only from quarantined, and no card-discovery mutations.
- Added policy-matrix, repository rejection, read-only discovery detail, contradictory control DTO, and unavailable-control UI coverage.
- A status response that combines `control_source_error` with an actionable control now fails as malformed; an injected unavailable snapshot always displays uncertainty without Pause/Resume.

Ruling: Centralize job recovery eligibility in the typed Dart model layer and require both presentation and repository serialization to consult it. Cost if wrong: any future gateway status expansion requires a deliberate one-line policy and matrix-test update before the client can expose or submit the action.

Ruling: Reject contradictory control status DTOs at the repository boundary, while independently suppressing control actions whenever the rendered snapshot reports source uncertainty. Cost if wrong: a partially compatible backend response produces a retryable failed refresh instead of showing possibly stale control state, favoring operational safety over availability.

## Task 5 evidence

- RED: the focused Deno suite failed because `loadSystemInbox` did not exist; the focused Flutter suite failed because System destinations, source failures, safe labels, and the exact control callback were not modeled.
- GREEN: the focused Inbox suites passed 11/11 Deno and 17/17 Flutter; the full admin-operator gateway passed 64/64; the full Admin2 Flutter suite passed 119/119; scoped analysis reported no issues.
- The derived source reads only `benefit_enrichment_scheduled` plus an exact, head-only count of `queued` benefit-enrichment jobs. It emits one deterministic critical item only for paused plus nonzero queued work and caps the displayed count without exposing records.
- Missing, errored, malformed, or contradictory source results report only `system_operations` as a partial failure and do not remove independently loaded card work.
- Typed System destinations render safe labels, never speak the control key, and repeatedly select the System section plus focus its exact pause/resume control at compact width.

Ruling: Model System Inbox work as a named-control destination rather than overloading card lanes or record IDs, and remount the System section for every deep-link selection so repeated compact navigation restores exact focus. Cost if wrong: each Inbox-to-System selection reloads bounded System status/history instead of preserving the prior local System view.

Ruling: Count only jobs in the exact `queued` state for the paused-pipeline alert and cap the human-readable count at `999,999+` while retaining critical priority. Cost if wrong: other recoverable states remain represented by their existing Inbox items, and extremely large queued backlogs lose numeric precision in display only.

## Task 5 review fix

- Scoped the alert count to the scheduler's exact current queued population: `run_mode = scheduled`, `parser_version = benefits-v5`, `status = queued`, and `next_retry_at` absent or due at the same server snapshot time.
- Added an exact query-operation contract and a mixed-population semantic test proving pilot, manual, legacy-parser, and deferred scheduled rows neither trigger nor inflate the alert.
- Focused Inbox tests passed 13/13; the full admin-operator gateway passed 66/66; the production gateway entry point passed type checking.

Ruling: Define “queued while scheduled processing is paused” as queued work eligible for the current scheduled worker population, including its run mode, parser generation, and due-time gate. Cost if wrong: deferred retries and non-current parser generations do not appear in this critical count until they become eligible for this scheduler.
