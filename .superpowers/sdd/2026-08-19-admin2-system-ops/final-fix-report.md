# Admin2 System Ops final-review fix report

## Findings addressed

1. The Flutter and gateway retry contracts now agree exactly: retry omits `operation`; quarantine/unquarantine use a required discriminator on `system-quarantine`. The registered handler is exercised with complete request bodies.
2. Both job families sanitize `failure_category` through a closed allowlist, with adversarial database strings mapped to `unknown_failure`. Dart uses a strict enum and fixed display labels.
3. The paused-pipeline Inbox source now mirrors scheduled-worker eligibility for `queued` and `failed` jobs, validates each exact count, and safely sums them.
4. System UI loads use family/page-aware generations so old responses cannot commit. Refresh blocks mutations while navigation reads remain safely supersedable.

## Focused evidence

- Deno System + Inbox: 28 passed, 0 failed.
- Flutter repository + System section: 23 passed, 0 failed.
- Adversarial failure strings, only-failed backlog, mixed eligibility exclusions, partial count failure, mutation body-through-handler, family races, and pagination races are covered.

## Whole-repository evidence

- Scoped Admin2 Flutter analysis: no issues.
- Production Admin Operator and benefit batch Deno entry points: type checks passed.
- Node Supabase contracts: 39 passed, 2 documented opt-in PostgreSQL skips.
- All Deno functions: 134 passed, 0 failed.
- All Flutter tests: 615 passed, 25 documented opt-in integration skips, 0 failed.

## Residuals

- Follow-up review found and fixed producer-vocabulary omissions, stale auth effects, and explicit-null retry ambiguity.
- Canonical producer code lists are exported and parity-tested; every established code has a stable Dart/operator label. Future unknown raw strings still render as `Unknown failure` until deliberately reviewed.
- Stale 401/403 races and current 401/403 effects are both covered.
- Retry requires `operation` to be structurally absent, including through the complete HTTP handler.
- No known residuals remain.
