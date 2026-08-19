# Admin2 Customer Ops — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-customer-ops.md`
- Base: `c226598`
- Status: active

## Preflight

- Foundation, Inbox/Card Data, and System Ops are complete and reviewed.
- Customer content, provider credentials, OAuth tokens, statement/transaction/email rows, and raw failures remain outside all admin DTOs and audits.
- Account disable means immediate database containment plus a separate Auth ban attempt; it does not claim issued JWT revocation.

Ruling: Implement Tasks 1–3 as one review unit because the plan explicitly holds the access/deletion schema until its first Flutter consumers; review SQL containment, profile gating, and queued Gmail recovery together. Cost if wrong: the review unit is broader, but no server boundary lands without its consumer.

Ruling: Carry the System plan's final adjudication ledger update into the Tasks 1–3 code-bearing commit, honoring the instruction not to commit documentation alone. Cost if wrong: the commit includes completed-plan bookkeeping with no runtime effect.

## Tasks

- Tasks 1–3: implementation complete, pending review — RLS containment, operation records, active profile gate, queued Gmail recovery
- Task 4: pending — sanitized customer gateway
- Task 5: pending — Customers workspace
- Task 6: pending — end-to-end verification

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
