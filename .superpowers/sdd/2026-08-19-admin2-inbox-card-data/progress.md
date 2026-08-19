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
- Task 5: implementation complete, pending review — Card Data review workspace
- Task 6: implementation complete, pending review — Action Inbox and deep-linking

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

## Task 5 evidence

- RED 1: the focused widget suite failed to compile because `CardDataSection`, `CardDataSource`, and `CardReviewQuery` did not exist.
- GREEN 1: the new queue/detail surface passed identity and benefit lanes, exact initial selection, pagination, reason-gated server-confirmed rejection, conflict reload, 401/403 effects, and the 390-pixel/2.0-text drill-in.
- RED 2: the refresh-failure test retained the stale item but could not find a visible stale-data warning.
- GREEN 2: refresh failure now keeps the prior queue visible and announces “Refresh failed. Showing the last loaded queue.”
- Regression: focused Card Data, admin shell, and typography-floor coverage passed 24/24; targeted analysis is clean after formatting.

Ruling: Use an operations-ledger hierarchy with the queue as the index, evidence as the decision record, and one compact state rail that binds lane, current state, freshness, confidence, and parser provenance. Cost if wrong: the detail view spends a small amount of vertical space on repeated state context in exchange for safer single-item decisions.

Ruling: Keep the prior page on refresh failures and mutations until the server confirms success; surface stale-state and refresh notices as live regions rather than clearing useful review context. Cost if wrong: an operator may briefly see an older row alongside an explicit warning instead of an empty error state.

Ruling: Adapt the existing `CardDataRepository` behind the view-owned `CardDataSource` boundary so Task 4's reviewed transport contract remains untouched and widget tests remain deterministic. Cost if wrong: a later shared provider may move this small adapter into the Card Data module without changing behavior.

## Task 5 review fixes

- Replaced first-page deep-link fallback with a validated, lane-scoped `target_id` gateway query; target requests are fixed to one row, and invalid target IDs fail before client invocation.
- Added typed identity candidates and benefit diff proposals, current-versus-proposed editing, safe actionable evidence links, extraction/evidence freshness, complete per-proposal decisions, and staging-level action derivation.
- Actions now derive from exact lane and status: pending identity review; staged/review-required benefit decisions only with complete staging data; failed/review-required recovery; quarantined unquarantine; terminal and in-flight states have no mutations.
- Conflicts reload the exact target. A disappeared target retains the prior detail and shows an explicit gone/latest-state message instead of selecting another row.
- Removed the broad `AssertionError` catch. `AdminOperatorScreen` now accepts an explicit `CardDataSource` for tests and deep-link inputs carry both lane and target ID; production resolves the reviewed repository provider normally.
- Verification: combined Admin2, legacy admin, and typography suite passed 95/95; complete admin-operator Deno suite passed 47/47; targeted analysis reported no issues.

Ruling: Model benefit review inputs from the server's sanitized staging diff and submit exactly one keyed decision per surfaced proposal; proposals without a stable dedupe key are not made actionable, and removal/unchanged choices exclude database-invalid approvals. Cost if wrong: malformed upstream proposals are visible only through warnings/evidence and must be retried or quarantined instead of being repaired through an incomplete client-generated decision.

Ruling: Represent mixed benefit outcomes as `edit_approve`, while all-approve/keep-existing maps to `approve` and all-reject maps to `reject`; the Edge and Flutter allowlists accept the full four-action decision vocabulary only for the mixed/edit path. Cost if wrong: a future server operation dedicated to mixed decisions would require renaming this transport operation while retaining the same audited decision array.

Ruling: Resolve deep links with the pair `(lane, target_id)` using a server-side exact-ID filter, and retain the prior selected DTO if a conflict refresh no longer finds that target. Cost if wrong: one targeted read is spent per deep-link refresh, and removed records remain visible as explicitly stale context until the operator leaves the target.

## Task 5 review fixes — eligibility and complete editing

- Matched visible recovery actions to the database predicates: identity retry remains available for existing review rows; benefit retry is limited to failed/review-required/quarantined; quarantine is available for queued/failed/review-required/staged, including incomplete or conflicted staging; unquarantine is limited to quarantined.
- Expanded the sanitized benefit projection and edit form across the accepted safe schema: identity/title/description/category/type, numeric value/rate/cap/limit/threshold, currency/unit, frequency/period, eligibility, partner(s), redemption rules, notes, restrictions/exclusions, effective/start/end dates, and bounded value-config numbers.
- Edit decisions start from and preserve the complete safe proposal. Typed number/date/list conversion occurs locally, bounded inputs reject malformed values, and the exact complete `edited_benefit` is submitted without raw or unknown fields.
- Form and decision controllers now reset when either target ID or `updatedAt` changes. Conflict coverage proves a stale edit/choice is replaced by the refreshed server version before another submission.

Ruling: Treat the shared legacy benefit presenter's documented scalar/list/value-config schema as the canonical editable surface, preserving all untouched sanitized fields and writing only allowlisted typed controls back into `edited_benefit`. Cost if wrong: adding a future safe benefit field requires one presenter allowlist and field-spec update before operators can edit it, rather than automatically exposing arbitrary parser output.

Ruling: Use the locked SQL status predicates as the UI action matrix even when multiple recoveries are valid (for example, quarantined benefits expose both retry and unquarantine). Cost if wrong: operators see an extra explicitly confirmed recovery choice that the database already accepts, but no invalid transition is offered.

## Task 5 identity retry correction

- Verified the effective contract at the Admin2 RPC boundary: although the legacy resolver contains an unconditional retry branch, `admin_card_data_action` locks the row and rejects every identity operation unless the review status is `pending` before calling that resolver.
- Identity retry is therefore visible for `pending` only and hidden for `approved`, `merged`, and `rejected`; the widget regression now asserts the full status matrix.
- RED: the matrix failed because an approved identity still exposed Retry. GREEN: the focused matrix passed after removing the terminal-state fallback.

Ruling: Gate identity actions on the Task 1 wrapper rather than the less restrictive legacy resolver in isolation, because Admin2 mutations can only reach the resolver through that wrapper. Cost if wrong: a future intentional terminal-state retry requires a coordinated SQL transition change and UI matrix update rather than appearing automatically.

## Task 6 evidence

- RED: the focused Flutter suite failed because `ActionInboxSection` did not exist.
- GREEN: focused Inbox coverage passed 13/13 after ranked grouping, partial-source banners, retained refresh state, responsive semantics, and exact `(lane, target_id)` workspace navigation were implemented.
- Regression: Admin2 plus legacy admin passed 101/101; admin-operator plus legacy catalog Deno passed 62/62; the Card Data migration contract passed 4/4 with its opt-in PostgreSQL test skipped; targeted analysis reported no issues.

Ruling: Preserve the server's stable order within fixed critical, high, and normal presentation groups, without applying a second client-side age or ID sort. Cost if wrong: a future gateway severity outside the three-value contract requires a coordinated DTO and presentation update rather than silently entering an arbitrary group.

Ruling: Recreate the Card Data target view for every inbox selection and pass the exact `(lane, target_id)` pair, so repeated and alternating selections cannot retain stale widget state. Cost if wrong: each inbox selection performs a fresh exact-target read instead of reusing an already-mounted Card Data queue.

Ruling: Keep the last successful inbox snapshot visible during refresh and partial-source failure, with live-region warnings and an explicit retry for initial failure. Cost if wrong: an operator can briefly act from visibly timestamped stale context after a refresh failure, but retains useful work instead of seeing an empty surface.

## Task 6 review fixes

- Compact exact-target loads now open the resolved detail immediately; queue-first behavior remains unchanged for ordinary Card Data entry, and Back returns to the queue.
- A 390-pixel workspace regression proves Inbox navigation renders the exact benefit detail, then a repeated identity selection renders the new exact detail. A direct Card Data regression preserves detail across compact-wide-compact viewport changes.
- Inbox rows and merged semantics now identify the allowlisted work type plus Card Data lane, while unknown future types fall back to “Operator action” and record IDs remain absent from the spoken label.
- Verification: focused Inbox plus Card Data passed 31/31; Admin2 plus legacy admin passed 103/103; Deno admin-operator plus legacy catalog passed 62/62; migration contracts passed 4/4 with the opt-in PostgreSQL test skipped; targeted analysis reported no issues.

Ruling: Enter compact detail mode only after an exact deep-linked target is successfully resolved, preserving ordinary queue-first entry and missing-target behavior. Cost if wrong: a deep-linked item adds one state transition after its server response before detail is rendered.

Ruling: Translate only the two allowlisted inbox work types and typed destinations into human-readable labels, falling back to generic operator-safe wording for future values without deriving labels from IDs. Cost if wrong: a new server work type remains generically labeled until the client allowlist is updated.
