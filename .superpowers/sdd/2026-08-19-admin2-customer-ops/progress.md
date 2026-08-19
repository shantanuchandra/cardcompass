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
