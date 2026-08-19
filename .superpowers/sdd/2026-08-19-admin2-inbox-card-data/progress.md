# Admin2 Inbox & Card Data — SDD Progress

- Plan: `docs/superpowers/plans/2026-08-19-admin2-inbox-card-data.md`
- Base: `ab3f5937a53e7a552159fe7eff90ffaf8ec9a367`
- Status: active

## Preflight

- Foundation dependency is complete and independently reviewed.
- Existing `/app/admin/catalog-review` and `admin-catalog-entry` behavior must remain unchanged.
- Each task receives a fresh implementer and independent review; the final branch delta receives a whole-plan review.

Ruling: Treat the plan's SQL and handler snippets as behavioral scaffolding, not permission to weaken existing database constraints or duplicate locked catalog-resolution behavior. Cost if wrong: implementation may need a narrow adapter revision while preserving public behavior.

Ruling: Include the foundation's final adjudication ledger update in Task 1's code-bearing commit, honoring the operator's instruction not to commit documentation alone. Cost if wrong: Task 1's commit includes one prior-plan bookkeeping line with no runtime effect.

## Tasks

- Task 1: implementation complete, pending review — atomic audited card-data mutation RPC
- Task 2: implementation complete, pending review — sanitized Card Data gateway actions
- Task 3: implementation complete, pending review — derived ranked Action Inbox
- Task 4: implementation complete, pending review — typed Flutter repositories
- Task 5: pending — Card Data review workspace
- Task 6: pending — Action Inbox and deep-linking

## Task 1 evidence

- RED: `node --test test/supabase/admin_card_data_operations_migration_test.js` failed 3/3 with `ENOENT` because the migration did not exist.
- GREEN: the named foundation, card-data, and benefit-enrichment migration contracts passed 13/13.

Ruling: Serialize each `(actor_id, request_id)` with a transaction-scoped advisory lock and persist the canonical normalized request JSONB, returning the prior result only when direct JSONB equality proves an exact replay and raising `request_id_collision` for changed request semantics. Cost if wrong: request processing takes one additional transaction lock, audit receipts are larger, and older receipts without the canonical request object cannot be replayed through this new RPC.

Ruling: Bind benefit approvals to the locked job's exact staging row and card, then mark that job completed in the same transaction after the existing approval RPC succeeds; quarantine excludes actively processing jobs. Cost if wrong: a future queue design that intentionally permits cross-job staging approval or live-job quarantine would require a narrow eligibility change.

- Task 1 review fix: replaced MD5-only replay comparison with direct canonical request JSONB equality. Added opt-in isolated PostgreSQL execution coverage that applies the real migration and verifies exact replay, changed-request collision, stale timestamps, staging ownership, audit-failure rollback, and concurrent identical calls. Local PostgreSQL: 4/4 passed; the disposable database and any temporary roles were removed.
- Task 1 review fix follow-up: PostgreSQL credentials are now passed only through protected libpq environment variables, never process arguments; the disposable connection replaces only the database name on the same validated loopback server, cleanup revalidates the generated database name, and errors redact both the source URL and password. Connection unit/static plus isolated PostgreSQL tests: 5/5 passed with no database or role residue.
- Task 1 review fix follow-up 2: the child process environment is now allowlisted, clearing inherited libpq host/address/port/database/user/password/service/SSL/options selectors before applying only validated URL-derived values. URL-less socket mode is pinned to `/tmp:5432`, password/service files are disabled, unsupported URL options are rejected, and hostile-inheritance plus socket regressions pass. Explicit TCP and socket opt-in PostgreSQL runs each passed 5/5 with no residue.

## Task 2 evidence

- RED 1: the focused Deno test failed type-checking because `card_data.ts` did not exist.
- GREEN 1: 10/10 Card Data handler tests passed after adding lane-specific queries, bounded presenters, strict mutation validation, stable error mapping, and frozen router registration.
- RED 2: two handler tests failed because identity proposal and benefit-decision payloads still accepted nested raw content and unsafe URLs.
- GREEN 2: 10/10 handler tests passed after rejecting non-allowlisted identity fields, sensitive decision fields, unsafe URL schemes, excessive nesting/arrays/strings, and over-32-KiB UTF-8 payloads.
- RED 3: the list validation test failed because syntactically safe but cross-lane statuses were accepted.
- GREEN 3: 10/10 handler tests passed after adding exact lane-specific status sets.
- Regression: 11/11 admin router tests and 15/15 legacy `admin-catalog-entry` tests passed.

Ruling: Map the mutation RPC's `request_id_collision` to the public `state_conflict` code because the API contract does not expose a collision-specific code and the safe operator response is to refresh and issue a new request ID. Cost if wrong: clients cannot distinguish a stale transition from request-ID reuse without server-side logs.

Ruling: Permit only HTTPS URLs without embedded credentials at the new Card Data boundary, while returning `null` for unsafe stored read URLs and rejecting unsafe mutation URLs. Cost if wrong: a legitimate issuer resource available only over HTTP would be hidden until upgraded or explicitly allowlisted.

## Task 3 evidence

- RED: the focused Deno test failed type-checking because `inbox.ts` did not exist.
- GREEN: 17/17 focused inbox and router tests passed after adding bounded identity and benefit adapters, exact sanitized DTOs, deterministic ranking, partial-source isolation, and immutable null-prototype registration.
- Regression: the complete `admin-operator` Deno suite passed 44/44.

Ruling: Use fixed operator-safe titles and explanations rather than interpolating issuer, card, failure, or evidence fields from source rows; only the source record ID, allowlisted status, safe age, and typed Card Data destination cross the inbox boundary. Cost if wrong: the operator must open the Card Data detail to identify the exact card, trading one click for a substantially smaller leakage surface.

Ruling: Treat malformed, future, or missing source timestamps as age zero while retaining the actionable item, so bad metadata cannot incorrectly elevate priority or hide work. Cost if wrong: malformed old items rank as newest until their source timestamp is corrected.

- Task 3 review fix: split benefit reads into separately bounded high-severity and routine tiers so staged volume cannot starve failed, review-required, or quarantined work. Added deterministic `created_at, id` database ordering before every range, sanitized catalog/discovery labels with short-reference fallback, and preserved successful tiers when a sibling tier fails. Focused inbox/router: 19/19 passed; full admin-operator: 46/46 passed.

Ruling: Revise the earlier generic-title decision after review: expose only control-character-stripped, whitespace-normalized, length-bounded issuer plus product labels from the explicit discovery/catalog relations, falling back to an eight-character safe record reference. Cost if wrong: an upstream issuer or product label could still be misleading, though no raw evidence, provider, or customer-content columns are selected or interpolated.

Ruling: Spend at most three bounded inbox reads (identity, high-priority benefits, routine benefits) and preserve fulfilled tiers independently; any failed benefit tier emits the single stable `benefit_enrichment` partial-failure name. Cost if wrong: the extra bounded benefit query adds one database round trip per inbox refresh in exchange for preventing priority starvation.

## Task 4 evidence

- RED 1: the focused Flutter repository suite failed to compile because the Card Data and Inbox DTO/repository files did not exist.
- GREEN 1: 16/16 focused DTO, pagination, evidence, partial-failure, action-serialization, and HTTP error-mapping tests passed.
- RED 2: the invocation-time `FunctionException` conflict test received `AdminRequestFailed` instead of the typed conflict.
- GREEN 2: 19/19 focused Card Data and Inbox tests passed after mapping invocation-time 409 responses to `AdminStateConflict`.
- Regression: focused repository plus foundation repository/screen coverage passed 44/44; targeted analysis reported no issues.

Ruling: Attach a client-observed UTC refresh timestamp to Card Data pages because the gateway page response has no server `refreshed_at`, while retaining the server timestamp for Inbox snapshots. Cost if wrong: Card Data's visible freshness reflects response receipt time rather than database snapshot time.

Ruling: Preserve allowlisted server validation codes inside `AdminRequestFailed`, but promote authentication, authorization, and state-conflict responses to dedicated exception types for shared UI handling. Cost if wrong: future UI code may need one additional typed exception when another stable code gains bespoke recovery behavior.

- Task 4 review RED: 13 focused failures proved invalid cross-lane actions were reaching the gateway, nested payload/DTO aliases remained mutable, non-JSON values were accepted, and unexpected invocation failures leaked their original exception.
- Task 4 review GREEN: exact bodies pass for all 11 valid lane-operation combinations; 11 invalid contract combinations are rejected before invocation; nested action/DTO JSON is recursively copied and frozen; unknown transport/runtime failures become `request_failed`. The full Admin2 suite passed 63/63 and targeted analysis reported no issues.

Ruling: Mirror the gateway's lane-operation and nested field allowlists at the Flutter repository boundary so invalid operator intents never consume a request ID or reach the network. Cost if wrong: gateway contract changes must update the typed client validation and server validator together.

Ruling: Recursively copy and freeze JSON-like action and DTO collections, rejecting non-JSON values at construction/parsing time. Cost if wrong: very large nested payloads incur an additional linear copy, bounded in practice by the gateway's 32-KiB mutation limit and list limits.

- Task 4 boundary follow-up RED: a 32,769-byte UTF-8 payload containing a multibyte character was sent to the gateway instead of failing locally.
- Task 4 boundary follow-up GREEN: 32,767- and 32,768-byte payloads pass, 32,769 bytes fail before invocation, normalized reject payload growth is included, timestamps over 100 characters fail even when parseable, and identity text/reason limits match the Edge validator. Focused repositories passed 41/41, the full Admin2 suite passed 68/68, and targeted analysis reported no issues.

Ruling: Measure both the submitted mutation payload and its operation-normalized safe form with `utf8.encode(jsonEncode(...))`, enforcing the gateway's inclusive 32,768-byte ceiling before allocating a request ID. Cost if wrong: JSON encoder escaping differences across runtimes could require a shared canonical byte-count fixture, though ASCII and multibyte boundary tests currently match the Edge contract.
