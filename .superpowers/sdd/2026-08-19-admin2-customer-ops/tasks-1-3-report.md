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
