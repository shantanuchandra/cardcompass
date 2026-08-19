# Admin2 foundation final-review fix report

## Findings addressed

1. Returned Supabase Auth errors now map recognized credential/session failures to `authentication_required`; server-side, unknown, and rejected Auth operations map to sanitized `request_failed` responses. Tests cover invalid and expired tokens, returned server errors, unknown returned errors, and rejected calls.
2. `AdminActionContext.db` now has a narrow typed `rpc(name, args)` contract. `AdminHttpErrorCode` includes the approved downstream handler codes `invalid_request`, `not_found`, `state_conflict`, and `reason_required` while preserving the foundation codes.
3. Root Deno dependency discovery keeps lock enforcement enabled. The tracked `deno.lock` was refreshed with the pinned Admin Operator JSR and npm graph, and the config regression checks both import resolution and lock entries.
4. The migration contract independently scopes and verifies `find_admin_request` as `SECURITY DEFINER` with a fixed empty `search_path`, revoked public/browser execution, and service-role-only execution grant.

## Verification

- `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/auth_test.ts supabase/functions/admin-operator/types_test.ts` — 15 passed.
- `deno check --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/index.ts` — passed.
- `deno test --config supabase/functions/admin-operator/deno.json supabase/functions/admin-operator/` — 26 passed.
- `deno test --config deno.json --allow-env --allow-read --allow-net supabase/functions/` — 83 passed.
- `deno fmt --check` on changed TypeScript — passed.
- `node --test test/supabase/*migration_test.js test/supabase/admin_operator_deno_config_test.js` — 26 passed.
- `flutter test test/features/admin2` — 27 passed.
- `git diff --check` — passed.

## Residual risk

Auth error classification intentionally treats only recognized Supabase credential/session codes and HTTP authentication statuses as session failures. New future Auth error codes without those signals will fail safely as retryable `request_failed` until explicitly classified, avoiding unnecessary operator sign-out.
