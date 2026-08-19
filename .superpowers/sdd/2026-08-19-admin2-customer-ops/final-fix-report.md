# Customer Ops final-review fix report

## Findings closed

1. Authenticated definer bypass: reviewed grant inventory, invoker conversion for transaction/payment RPCs, explicit active reset guard, static future-addition contract, and disposable read/write/delete coverage.
2. User-token Edge bypass: centralized active-profile helper and stable 403/503 gates in all three user JWT/service-role gateways; cron/service/admin gateways remain exempt.
3. Non-durable Auth ban: authoritative outbox, leased service-only claim/complete RPCs, honest containment audit outcome, append-only final attempt audits, safe detail projection, dedicated server-reconstructed retry, and reload-safe UI.
4. Profile ambiguity/race: typed active/inactive/missing state plus fail-closed errors and captured-identity fencing before sign-out.
5. Deletion stale create: first row compares locked profile version; existing row compares deletion version; disposable stale-create coverage passes.

## Verification

- Flutter: `656` passed, `25` expected local-integration skips.
- Deno: `149` passed.
- Node migration/static: `48` passed, `3` opt-in skips in the aggregate run.
- Disposable PostgreSQL, sequential: Card Data `5/5`, Runtime Controls `5/5`, Customer Ops `5/5`.
- `flutter analyze --no-fatal-infos`: pass with the repository's 12 pre-existing unrelated info diagnostics.
- Deno checks, formatters, `git diff --check`: pass.

## Residual verification limitation

The real hosted/local Supabase Auth HTTP service was not mutated or exercised. Auth Admin behavior is covered at the gateway boundary, while durable attempt state, failure/retry transitions, concurrency, RLS containment, and stale versions are exercised in disposable local PostgreSQL.

## Residual review closure

- Auth-ban claims rotate an opaque UUID token under a five-minute lease; completion is token-fenced and outbound Auth work is bounded to 30 seconds. Disposable PostgreSQL covers concurrent ownership, expiry/reclaim, stale-token rejection, and successful current-token completion.
- Claim identity is the retrying operator plus validated request UUID. Exact completed replay avoids another Auth call, cross-target identity reuse collides safely, and final audit attribution reflects the retry operator while linking the originating disable event.
- Both privileged-path inventories are repository-derived rather than hand-maintained: migration-state analysis includes default `PUBLIC` execution and later grant/security changes, while recursive Edge discovery detects end-user JWT plus service-role gateways and enforces an early shared gate. Synthetic fixtures prove each contract catches a newly introduced bypass.
