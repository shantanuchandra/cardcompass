# Customer Ops Tasks 1–3 implementation report

## Scope

- Server-owned `users.is_active` privileges and active-owner RLS for all named user-data tables.
- Private customer operation/deletion records and narrow authenticated/service RPCs.
- Canonical, serialized, observed-version customer mutations with atomic successful audit receipts and no deletion path.
- Fail-closed Flutter active-profile gate and customer-owned queued Gmail recovery using only the live in-memory provider token.

## TDD evidence

- RED database: 4 contract failures from the missing `20260819090300` migration.
- RED Flutter: both suites failed compilation on the missing injected boundaries.
- GREEN focused Flutter: 9 passed.
- GREEN migration: 5 passed with live disposable loopback PostgreSQL enabled.
- Regression: dashboard plus Admin2 shell selection/auth tests passed 43/43.
- Scoped analysis: no issues.

## Safety verification

- The integration harness starts from an allowlisted libpq environment, accepts only loopback/socket PostgreSQL, creates one exact disposable database, and removes that database plus only roles it created.
- An authenticated role cannot write `is_active`; an already established claim loses SELECT and INSERT access immediately after server-side disablement.
- Concurrent canonical operation calls produce one request and one audit receipt; changed semantics collide; stale observed state is rejected.
- Concurrent customer claims select at most one request, and completion stores only the closed safe category.
- No OAuth token, Gmail content, user ID from a request payload, service key, or deletion operation was introduced.

## Residual risks

- Actual Supabase Auth banning belongs to Task 4's injected Admin client; this slice establishes the immediate database containment path only.
- The local behavioral test uses a disposable PostgreSQL auth fixture rather than a remote Supabase project, intentionally avoiding any production mutation.
- A customer without a valid current Google provider token receives `reauthentication_required`; recovery waits for a later operator request after the customer reauthenticates.

## Review fix: dashboard/session lifecycle

- Replaced provider-build claiming with `initializeQueuedRecovery()`, called on Dashboard mount and every Dashboard tab entry despite the persistent `IndexedStack`.
- Same-session concurrent entry signals coalesce; completed empty claims are not cached, so a later visit can claim newly queued work.
- Auth identity/session changes invalidate the active generation; stale operations cannot overwrite the new session's UI state or execute using a pre-change token after claim returns.
- Sequential-user, sign-out/sign-in, later-queued, concurrent initialization, completion-category, and real Dashboard mount tests pass without polling or request-supplied identity/token data.

## Review fix: reclaimable operation leases

- `admin_customer_operation_requests` now holds a ten-minute `claim_expires_at` and opaque UUID `claim_token`; reclaim rotates the token under the row lock.
- Completion remains owner-derived through `auth.uid()` and requires the current token. Cross-user, stale-token, and non-claimed completions fail closed; successful completion clears lease state.
- The client carries only the opaque request/token pair. It never completes after identity changes and an ownership-aware fake proves the original user can re-enter and reclaim after expiry.
- Live disposable PostgreSQL validates concurrency, cross-user denial, expiry, rotation, stale denial, and current completion without contacting any remote Supabase project.

## Review fix: live-execution lease fencing

- The authenticated renew RPC is owner- and token-bound, row-locks the current claimed Gmail request, and extends only its short lease. It exposes no provider credential or customer content.
- Flutter schedules a two-minute heartbeat only for active claimed work, cancels it in `finally`, dispose, and session changes, and coalesces duplicate dashboard initialization around the same execution.
- Gmail execution checks the lease before discovery, persistence, processing, after processing, and again before completion. Renewal loss prevents later phases and suppresses completion rather than falsely reporting success.
- Fake-clock lifecycle coverage runs beyond the ten-minute lease with one sync, exercises renewal loss and session replacement, and proves an empty dashboard creates no polling. The disposable local PostgreSQL suite proves renewal/reclaim and stale-token fencing end to end.

Residual boundary: persistence and statement processing are existing indivisible phases. A lease lost during one phase is detected immediately afterward; no subsequent phase or success completion proceeds. Making every individual row write cancellable would require a separate transaction-bound service refactor.
