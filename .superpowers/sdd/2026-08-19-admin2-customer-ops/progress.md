# Admin2 Customer Ops — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-customer-ops.md`
- Base: `c226598`
- Status: implementation complete; Task 6 verified, pending independent review

## Preflight

- Foundation, Inbox/Card Data, and System Ops are complete and reviewed.
- Customer content, provider credentials, OAuth tokens, statement/transaction/email rows, and raw failures remain outside all admin DTOs and audits.
- Account disable means immediate database containment plus a separate Auth ban attempt; it does not claim issued JWT revocation.

Ruling: Implement Tasks 1–3 as one review unit because the plan explicitly holds the access/deletion schema until its first Flutter consumers; review SQL containment, profile gating, and queued Gmail recovery together. Cost if wrong: the review unit is broader, but no server boundary lands without its consumer.

Ruling: Carry the System plan's final adjudication ledger update into the Tasks 1–3 code-bearing commit, honoring the instruction not to commit documentation alone. Cost if wrong: the commit includes completed-plan bookkeeping with no runtime effect.

## Tasks

- Tasks 1–3: implementation complete, pending review — RLS containment, operation records, active profile gate, queued Gmail recovery
- Task 4: implementation complete, pending review — sanitized customer gateway
- Task 5: complete — typed, responsive Customers workspace
- Task 6: complete — end-to-end verification

## Task 6 evidence

- Customer-scoped Dart formatting is stable (`25 files`, `0 changed`) and Admin Operator Deno formatting is stable (`18 files` checked). The plan's broader `test/features` formatter identifies seven pre-existing Movie Deals test files that are not currently formatted; those incidental rewrites were reverted.
- Exact `flutter analyze` reports 12 pre-existing `info` diagnostics outside Customer Ops and exits nonzero. `flutter analyze --no-fatal-infos` exits 0 with the same 12 infos, and scoped Customer Ops/Auth/Dashboard analysis reports `No issues found`.
- Full Flutter passes `653` tests with `25` explicitly skipped local-Supabase integrations. Full static Node migration coverage passes `43/46` with the three opt-in disposable PostgreSQL tests skipped. The complete Deno Edge Function suite passes `146/146`.
- All credential-safe disposable PostgreSQL suites pass individually against the loopback server: Card Data `5/5`, Runtime Controls `5/5`, and Customer Ops `5/5`. Running all three opt-ins concurrently exposes a test-harness teardown collision on shared cluster roles; product assertions still pass and sequential execution leaves no disposable databases behind.
- Customer containment was exercised at the PostgreSQL/RLS/RPC layer: an authenticated-role session keyed by the same `request.jwt.claim.sub` reads its owned row, browser mutation of `is_active` is denied, unchanged-session reads/inserts are denied after deactivation, the audited idempotent Customer RPC disables the profile, and the audit receipt exists. Gateway unit coverage separately proves customer detail returns only bounded metadata and no customer content.
- A local Supabase Auth/API stack was not available (`supabase status` unavailable and Docker daemon not running), so actual access-token issuance, Edge Function HTTP invocation, and a fresh-sign-in rejection after the Auth ban were not exercised. No hosted/remote service was contacted or mutated.
- `git diff --check` passes, generated root `node_modules/` from Deno dependency discovery was removed exactly, and the worktree is clean before this documentation-only verification record.

Ruling: Treat the disposable PostgreSQL harness as proof of immediate database containment for an unchanged authenticated identity, but not as proof of Supabase Auth token revocation or fresh-sign-in banning. Cost if wrong: release confidence in the Auth-ban side effect remains dependent on the mocked Admin API contract until a disposable local Supabase Auth stack is available.

Ruling: Run the three opt-in disposable PostgreSQL suites sequentially because they share cluster-global Supabase role names and concurrent cleanup races across otherwise isolated databases. Cost if wrong: CI gains a few seconds of serial verification time, while the product paths and each isolated database test remain unchanged.

## Tasks 1–3 evidence

- RED: the migration contract failed 4/4 with `ENOENT`; the focused Flutter suites failed to compile because the profile/session and queued-operation boundaries did not exist.
- GREEN: focused Flutter passed 9/9; migration contracts passed 5/5 including the opt-in disposable local PostgreSQL behavior test; scoped Flutter analysis reported no issues.
- The disposable loopback PostgreSQL run compiled the foundation plus Customer Ops migration and proved unchanged-session RLS containment, browser denial of `is_active`, concurrent request replay to one audit receipt, collision rejection, one-request claiming, safe completion, stale observed-state rejection, disablement, and cleanup.
- Broader dashboard and Admin2 shell regression coverage passed 36/36; the combined focused Flutter run passed 45/45.

Ruling: Expose `current_user_is_active()` as the narrow profile-reader source instead of selecting `users.is_active` directly, because the intended inactive-user RLS policy hides the row that the Flutter gate needs to classify before signing out. Cost if wrong: each authenticated auth-state rebuild performs one RPC rather than one table projection, while the RPC reveals only the caller's boolean state.

Ruling: Serialize each admin request key before receipt lookup, compare the complete normalized request exactly, require observed profile/deletion versions for existing state, and return only canonical bounded receipts. Cost if wrong: stale clients must refresh before retrying and older receipts without the normalized request cannot replay through this RPC.

Ruling: Keep queued Gmail requests credential-free and user-free beyond their server-owned target; the authenticated dashboard supplies only its current in-memory session user and provider token to the existing sync executor, then completes the request with one closed safe category. Cost if wrong: recovery waits for the customer's next authenticated dashboard session and cannot be executed centrally by an operator.

Ruling: Treat absent or malformed profile state as an authentication error, but sign out only a definite inactive boolean to avoid an error-driven sign-out loop during transient database failure. Cost if wrong: a transient profile outage blocks app entry until retry without destroying the local session.

## Tasks 1–3 review fix

- Removed the cached one-time claim from `GmailSyncNotifier.build`; queued recovery now starts only through an explicit dashboard-entry API.
- The Dashboard mount invokes initialization, and every navigation back to the persistent Dashboard tab invokes it again. There is no timer or background polling.
- Initialization is keyed to an opaque in-memory session identity, coalesces duplicate concurrent calls for the same session, resets stale UI generations on auth identity/session changes, and captures the current snapshot before claim/execution.
- A new dashboard entry retries after an earlier empty claim, while sequential users and sign-out/sign-in sessions in one provider container execute only with their own current in-memory tokens.
- Focused provider and dashboard lifecycle coverage passed 30/30, including an identity change during the claim await that cannot execute with the stale token.

Ruling: Treat dashboard entry—not provider construction—as the queued-recovery trigger, because the app shell retains Dashboard in an `IndexedStack` and a provider build can outlive many visits. Cost if wrong: each deliberate Dashboard entry performs one cheap claim RPC even when no request exists.

Ruling: Coalesce only concurrent initializations for the same opaque session key and clear the coalescing handle after completion; do not memoize an empty result across entries. Cost if wrong: rapid duplicate entry signals share one claim, while a later entry intentionally issues another bounded claim.

Ruling: Derive the session key only from the live in-memory Supabase session object and user ID, never from a request row or persisted token, and suppress stale-generation UI writes after an identity change. Cost if wrong: a token refresh creates a new recovery generation and may issue one additional claim, but cannot reuse another user's captured provider token.

## Tasks 1–3 lease fix

- Added a ten-minute server lease and rotated opaque UUID claim token to each customer operation attempt.
- The claim RPC atomically selects the oldest queued or owner-scoped expired claim with `FOR UPDATE SKIP LOCKED`; completion requires the current `auth.uid()`, request ID, current claim token, and claimed state, then clears the lease.
- Owner completion remains valid just after expiry until a reclaim rotates the token. After reclaim, an older attempt cannot complete.
- On a Flutter identity change during claim, no new-user completion is attempted and no stale token executes; the original owner can reclaim on a later Dashboard entry after expiry.
- Disposable PostgreSQL passed 5/5 including cross-user completion denial, expiry/reclaim token rotation, stale-token denial, current-token completion, and concurrent single claiming. Focused Flutter lifecycle passed 31/31.

Ruling: Use a ten-minute database lease plus a rotated UUID claim token as the attempt capability, returning only request ID, operation type, and that opaque token. Cost if wrong: an interrupted recovery waits up to ten minutes before the same user can reclaim it, while no provider credential or customer content is stored.

Ruling: Allow the owning attempt to complete after nominal lease expiry only while its token remains current; reclaim atomically rotates the token and makes every older completion fail `state_conflict`. Cost if wrong: a just-finished long sync can commit without racing the clock, but the first reclaim decisively supersedes it.

Ruling: If auth identity changes while claim is awaiting, suppress execution and do not attempt completion as the new user; leave the owner-scoped lease to expire. Cost if wrong: the original owner may wait one lease interval, but another identity cannot alter or execute that request.

## Tasks 1–3 lease-fencing fix

- Added the narrow authenticated `renew_my_admin_operation_request` RPC. It derives the active owner from `auth.uid()`, locks the claimed Gmail row, requires its current opaque claim token, and extends the ten-minute lease.
- A queued recovery starts a two-minute heartbeat only after a successful claim. It renews at each Gmail discovery/persistence/processing boundary and once more immediately before success completion.
- Renewal/token loss fences the next processing boundary, suppresses success and all stale completion writes, and cannot escape as an unhandled timer error. Dispose or auth-session change cancels the heartbeat immediately.
- Deterministic Flutter coverage simulates more than one lease duration, duplicate dashboard initialization, renewal loss, session replacement, and idle dashboards. Disposable PostgreSQL proves active renewal blocks reclaim and stale/cross-user tokens cannot renew or complete.

Ruling: Renew every two minutes against a ten-minute lease and at meaningful write-phase boundaries, then require a final renewal before reporting success. Cost if wrong: a transient renewal failure abandons the current attempt conservatively; the same owner can reclaim after expiry instead of risking two live writers.

Ruling: Do not poll when there is no claimed request, and swallow only the heartbeat callback's expected lease-loss signal while retaining the shared fence. Cost if wrong: recovery has no background database cost while idle, and a lost lease may finish its current indivisible phase but cannot enter the next phase or report success.

## Dashboard test-boundary fix

- `DashboardScreen` now accepts an optional queued-recovery initializer. The production default still resolves the real authenticated notifier; isolated widget harnesses inject a no-op without constructing Supabase.
- The default-path widget test continues to prove Dashboard entry invokes the notifier, while the responsive harness explicitly proves its injected initializer runs without touching Supabase.
- All Dashboard tests pass 56/56, removing the prior eight harness-only Supabase initialization failures without catching or suppressing production errors.

Ruling: Put the injection seam at the Dashboard side-effect boundary rather than weakening the provider or catching an uninitialized Supabase assertion. Cost if wrong: one optional constructor dependency exists solely for embedding/tests, while production behavior remains unchanged and directly covered.

## Task 4 evidence

- RED: focused Deno compilation failed because `customers.ts` did not exist.
- GREEN: focused Customer Ops gateway coverage passed 9/9; the complete `admin-operator` suite passed 81/81.
- Search accepts only an exact UUID or an escaped, normalized email fragment of at least three characters, caps results at 25, orders by normalized email then ID, and audits only the safe query kind before reading.
- Detail writes `record_admin_read` before touching any customer or Auth source, then returns only exact bounded counts, safe statuses/categories, safe timestamps, normalized identity fields, and a provider-connection boolean.
- Disablement invokes the idempotent audited database RPC first and validates its canonical containment receipt before attempting the 100-year Auth ban. Ban failure returns only `auth_ban_pending`; replay revalidates the existing database receipt and retries the ban.
- Adversarial tests prove strict action keys, wildcard escaping, malformed receipt rejection, frozen prototype-safe registration, and stable non-leaking handler-through-router failures.

Ruling: Audit customer search before querying while recording only `user_id` versus `email_fragment`, never the fragment itself; exact UUID searches may use that UUID as the audit target. Cost if wrong: every operator search consumes one append-only audit row, but sensitive search text does not enter the audit trail.

Ruling: Treat any unavailable or malformed customer-detail source as a closed `request_failed` response rather than returning ambiguous partial metadata, while preserving the stronger audit-before-read invariant. Cost if wrong: one unavailable count or Auth identity lookup temporarily blocks the whole detail panel instead of showing stale or incomplete diagnosis.

Ruling: Derive Gmail connection only from whether Auth Admin returns a Google identity, discard the identity objects immediately, and expose one boolean. Cost if wrong: provider connection diagnosis depends on Auth Admin availability, but no identity metadata or provider credential can cross the gateway.

Ruling: Reinvoke the idempotent database RPC on disable replay to validate the original target, action, request payload, and canonical containment receipt before retrying Auth ban; never trust a client claim that containment already happened. Cost if wrong: a pending Auth ban costs one receipt lookup per retry, while collision or target drift fails safely before Auth mutation.

## Task 4 review fix

- Added `confirmation_user_id` to the exact `customer-deletion-status` gateway contract, matching the existing disablement confirmation boundary required by the interaction spec.
- Missing, null, malformed, or target-mismatched confirmation now returns `invalid_request` before the audited mutation RPC is invoked.
- The validated confirmation is intentionally not copied into `_payload`; the audited RPC already binds the canonical target user ID and needs only the requested deletion status.
- Direct handler and full HTTP-router regressions cover absent, null, mismatched, and valid exact confirmation. The complete `admin-operator` suite passes 84/84.

Ruling: Require the same exact typed target UUID confirmation for deletion-progress transitions as for account disablement, validate it before any RPC, and discard the redundant confirmation after validation. Cost if wrong: clients must type the full user UUID for each deletion status change, but a stale or mistargeted confirmation cannot create an audited transition and redundant sensitive identifiers do not enter the audit payload.

## Task 5 evidence

- RED: the focused Flutter suites failed to compile because the Customer DTO, repository, and workspace files did not exist.
- GREEN: Customer repository and widget coverage passes 13/13; the full Admin2 suite passes 139/139; scoped analysis has no warnings or errors.
- The repository accepts only an exact UUID or normalized three-character email fragment, generates request UUIDs, bounds the complete encoded request to 32 KiB, strictly decodes exact safe response shapes, and validates canonical mutation receipts.
- Wide layouts provide search/list/detail at 1024 logical pixels and above. Compact layouts provide a 390-pixel drill-in. Results remain visible during refresh, and generation fencing prevents older search or detail responses from replacing newer operator intent.
- Gmail recovery explicitly states that execution is queued for the customer's next authenticated session. Account disablement and deletion progress require a reason and exact typed target UUID. Actions are server-confirmed, double submission is disabled, conflicts refresh the latest state, and `auth_ban_pending` distinguishes immediate database containment from the outstanding Auth ban.

Ruling: Preserve `auth_ban_pending` in the shared operator repository's stable-code allowlist because the Customer UI must communicate partial containment accurately instead of collapsing it to a generic request failure. Cost if wrong: one additional server code crosses the typed boundary, but it contains no raw provider detail and is covered by an exact regression.

Ruling: Fence Customer search and detail loads with a monotonically increasing generation while retaining the last successful list during refresh. Cost if wrong: an obsolete response is discarded and the operator must repeat that search, rather than letting stale identity or activity metadata replace the latest request.

Ruling: Use the profile `last_activity_at` and deletion `updated_at` values returned by the audited detail as the exact observed versions for profile and deletion mutations. Cost if wrong: concurrent state changes return `state_conflict` and force one refresh instead of applying against stale support context.

## Task 5 review fix

- Selection now immediately clears the prior detail and actions, shows a keyed loading state, and accepts a detail response only when its generation, selected target, and decoded customer ID all match. Stale failures cannot invoke authentication or authorization effects.
- Every mutation is a replayable `CustomerOperation` carrying its generated request UUID. Read calls continue generating independent audit request IDs.
- `auth_ban_pending` becomes a typed partial-containment result carrying the exact `DisableCustomer` operation. The UI refreshes to show the database-confirmed inactive state and offers one locked `Retry Auth ban` action that resends the same request ID and complete body; success removes the retry.
- Gmail retry eligibility is now closed to only active, Gmail-connected customers whose latest operation is `failed` with one actual allowlisted safe failure category.
- Focused Customer coverage passes 17/17, the full Admin2 suite passes 143/143, and scoped analysis reports no issues.

Ruling: Bind rendered customer detail to the selected user ID, the latest load generation, and the decoded detail ID, clearing prior actions while a new target loads. Cost if wrong: the operator briefly sees a loading surface instead of stale metadata, but can never submit customer A's action after selecting customer B.

Ruling: Make request identity part of the immutable Customer operation before invocation and retain the exact disable operation on `auth_ban_pending`. Cost if wrong: each new intentional mutation allocates its UUID slightly earlier, while retries can safely re-enter the server's idempotent receipt path without creating a second disable action.

Ruling: Treat `auth_ban_pending` as successful database containment plus an incomplete Auth side effect, refresh server detail immediately, and expose only an exact-request Auth-ban retry. Cost if wrong: the operator must explicitly retry the ban, but the console never misstates database access as active or generates a conflicting disable request.

Ruling: Permit queued Gmail recovery only when the latest operation is failed and carries one allowlisted safe failure category, in addition to an active profile and connected Gmail identity. Cost if wrong: ambiguous null or completed states require fresh diagnosis rather than enqueueing an unnecessary customer-session operation.

## Task 5 residual review fix

- Pending Auth-ban recovery now survives refresh, a same-query search that returns the same target, detail reload, and transient read failures without changing its immutable request ID or body.
- When search results temporarily omit the contained customer, a dedicated banner names the exact target, states that database access is already blocked, and retains the exact-request retry action.
- An explicit tap on a different customer intentionally clears pending recovery before loading that customer's detail, so a retry can never cross customer context. Automatic search selection does not silently discard it.
- Regression coverage proves the same operation object and request ID survive same-target search/refresh and clear only after canonical replay success; focused Customer passes 18/18, full Admin2 passes 144/144, and scoped analysis is clean.

Ruling: Preserve a pending Auth-ban operation across automatic refresh/search/detail state changes and surface it independently when its target is absent; clear it only after confirmed replay success or an explicit operator selection of another customer. Cost if wrong: the operator may see a persistent recovery banner during unrelated automatic results, but the exact incomplete side effect cannot be silently orphaned or replayed against the wrong target.

## Final security-review superseding fixes

- Every authenticated function grant is now enumerated by a failing inventory contract. User-owned transaction/payment paths run as `SECURITY INVOKER`; the private reset definer checks the active caller before deletion; the queued-operation definers retain their explicit active check. Disposable PostgreSQL proves inactive unchanged identities cannot read, insert, or invoke the deletion reset.
- `card-discovery`, `request-card-catalog-entry`, and `gemini-proxy` share one service-role active-profile gate after capturing the verified Auth user ID and before privileged work. The gate distinguishes active, inactive, missing, and unavailable without leaking dependency errors; the inventory contract makes new user-token/service-role gateways opt in explicitly.
- Account disablement now creates a durable `admin_auth_ban_requests` outbox record in the same database transaction. The service-only claim/complete RPCs lease attempts, reconstruct retries by target, remain idempotent under a lost response or concurrent operator, and append completion/failure audit events. Customer detail returns only safe ban state/timestamps and the UI reconstructs a dedicated retry after reload instead of retaining the original disable request in widget memory.
- The Flutter access gate uses a typed database classifier (`active|inactive|missing`) and rechecks the captured Auth identity before any sign-out, so a late inactive read cannot sign out a replacement session.
- Creating the first deletion-progress row now locks the profile and requires its observed `users.updated_at`; subsequent transitions remain fenced by the deletion row's `updated_at`. The disposable PostgreSQL suite proves a stale first create is rejected.

Ruling: Supersede the boolean-only profile-reader boundary with the typed `current_user_access_profile_state()` classifier and a second captured-identity check immediately before sign-out. Cost if wrong: one narrow definer reveals only the caller's own profile-state category, while missing profiles and transient failures remain blocked without destroying a newer session.

Ruling: Supersede widget-owned Auth-ban replay with a database outbox and a dedicated target-only retry action; a two-minute processing lease permits safe recovery after an ambiguous gateway loss. Cost if wrong: an ambiguous attempt can remain visibly `processing` for up to two minutes before reclaim, but navigation, reload, and concurrent admins cannot orphan or duplicate the authoritative side effect.

Ruling: Classify account disablement audit outcome as `database_contained` until the separate Auth-ban completion event is appended. Cost if wrong: audit consumers must accept one additional explicit outcome, but the trail no longer overstates a partially completed containment workflow as fully succeeded.

Ruling: Run authenticated user-data RPCs as `SECURITY INVOKER` wherever active-owner RLS supplies the required privilege, retaining a definer only for the narrow reset operation with an explicit active check. Cost if wrong: a future policy regression would fail closed or surface in the grant/integration contracts instead of silently bypassing RLS.

Ruling: Fence an initial deletion-status create with the observed profile `updated_at`, and fence later transitions with the existing deletion row `updated_at`. Cost if wrong: an operator must refresh after any concurrent profile or deletion change, avoiding the first-row stale-create gap.

## Residual security-review superseding fixes

- Every Auth-ban claim now receives a rotated opaque UUID token and a five-minute lease. Completion requires the matching current token and `processing` state; PostgreSQL coverage proves one concurrent owner, expiry/reclaim token rotation, stale completion rejection, and current completion success. The external Auth request is bounded to 30 seconds.
- Retry attempts persist the current operator and request UUID. Exact completed replays return the authoritative receipt without another Auth call; identity reuse against another target fails as `request_id_collision`. Final attempt audits belong to the retrying operator/request and retain the originating disable identity only as linked details.
- The authenticated-definer contract now derives final function state repository-wide from every migration, including default `PUBLIC` execute, grants, revokes, replacements, drops, and later security-mode changes. A tiny documented exemption set remains, and synthetic ungated/revoked fixtures exercise the analyzer itself.
- The Edge gateway contract now recursively discovers end-user JWT plus service-role functions and requires the shared active gate before privileged database, storage, or RPC access. Synthetic fixtures prove an ungated gateway fails while internal admin/cron functions remain out of scope.

Ruling: Fence each leased Auth-ban attempt with a newly rotated claim token, a five-minute database lease, and a 30-second outbound Auth timeout. Cost if wrong: an ambiguous provider attempt waits at most five minutes before reclaim, while stale workers can never finalize a newer attempt.

Ruling: Attribute every retry attempt and final audit to the operator and request UUID that actually claimed it, preserving the original disable identity only as provenance. Cost if wrong: the initial disable uses the durable ban-row UUID as its internal attempt request identity, while exact replay is safe and cross-target reuse fails closed.

Ruling: Derive privileged-path inventories from repository state instead of hand-maintained function lists. Cost if wrong: unconventional future SQL or gateway syntax may require extending the deliberately conservative analyzer, but a new exposed definer or ungated user gateway fails review by default.

## Final adjudication

- The single final-fix owner resolved all whole-plan findings in `090441a`; the scoped re-review's four valid residuals were resolved by the same owner in `2599974`.
- Controller verification passed repository-wide privileged-boundary inventories (9 passed, 1 opt-in skip) and 14 focused Customer gateway tests, including token-fenced ban replay attribution. No unresolved Customer Ops finding remains; the plan is approved to continue.
