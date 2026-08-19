# System Ops Tasks 1–2 report

## Outcome

- Added the only V1 runtime control, `benefit_enrichment_scheduled`, as an RLS-enabled, browser-inaccessible, service-readable table with an exact one-key constraint and seed.
- Added `admin_set_runtime_control`, a safe-search-path, security-definer RPC with bounded validation, observed-version locking, transaction-scoped request serialization, direct canonical replay equality, collision rejection, and atomic audit insertion.
- Scheduled benefit enrichment now checks the control immediately after authorization/run-mode parsing and before any pilot, inventory, queue, or job access.
- A pause returns stable HTTP 200; missing, errored, or malformed control state fails closed with stable HTTP 503. Pilot and manual recovery do not read the scheduled-only control.

## TDD evidence

- RED: migration contract 2/2 failed with `ENOENT` before the migration existed.
- GREEN: migration/foundation contracts 4/4 passed.
- GREEN: focused benefit-enrichment tests 20/20 passed, including paused ordering, safe fail-closed behavior, strict boolean parsing, and pilot/manual exclusion.

## Risks and follow-up

- The isolated PostgreSQL harness remains opt-in in the adjacent Card Data contract; this slice statically verifies the same hardened serialization/canonical-replay pattern but does not add a second duplicated harness.
- Service-role reads rely on Supabase's `service_role` bypass-RLS role, while browser roles have neither grants nor policies.
