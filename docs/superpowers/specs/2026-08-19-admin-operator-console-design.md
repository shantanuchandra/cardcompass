# CardCompass Admin Operator Console Design

**Date:** 2026-08-19

## Summary

CardCompass will add a founder-operated workspace at `/app/admin2`. Its purpose is to surface operational exceptions, let the operator resolve routine failures safely, and protect the accuracy of card and benefit data without requiring direct SQL or engineering intervention.

The console is for one trusted operator. Access is governed by `public.users.is_admin`, checked from the database on every privileged server request. The initial operator is `shantanu.msp@gmail.com`; migration `20260819063836_add_admin_flag_to_public_users.sql` has already added the flag, seeded that account, and blocked authenticated users from assigning the flag to themselves.

## Goals

- Give the operator one prioritized view of issues that require action.
- Make routine customer, card-data, and pipeline recovery possible without SQL.
- Keep privileged data and service credentials out of the Flutter client.
- Record every privileged mutation and customer-detail access.
- Preserve the existing catalog-review route until the new workspace reaches parity.
- Make admin revocation effective on the next privileged request.

## Non-goals

- Multiple admin roles, assignments, or team workflows.
- User impersonation.
- Bulk approval of card or benefit proposals.
- Raw SQL, unrestricted table editing, or arbitrary configuration.
- Growth analytics, campaigns, messaging, or CRM features.
- Displaying raw email bodies, statement PDFs, credentials, or complete transaction histories.
- Replacing specialist observability or analytics tools.

## Operator and success criteria

The only initial operator is the verified account associated with `shantanu.msp@gmail.com`. The console succeeds when:

- the highest-priority actionable issue can be identified in under one minute;
- at least 80% of routine operational failures can be recovered without SQL or code changes;
- every privileged mutation has an audit record;
- customer-detail access is auditable;
- no prohibited raw financial or email content reaches the console; and
- changing `public.users.is_admin` to `false` blocks the next privileged request.

## Architecture

### Flutter workspace

`/app/admin2` is a new desktop-first workspace inside the existing Flutter application. It uses a navigation rail on wide screens and a compact navigation pattern on smaller screens. The four sections are:

1. Action Inbox
2. Customers
3. Card Data
4. System

The Action Inbox is the default section. The existing `/app/admin/catalog-review` route remains intact during rollout. The ordinary app navigation only shows the admin entry point after a successful access check, but hiding the route is not an authorization control.

The new feature lives under `lib/features/admin2/` so it can be developed and tested without destabilizing the existing review screen. Existing card-identity and benefit-review models or repositories may be adapted behind narrow interfaces; the new workspace must not copy business rules into widgets.

### Server boundary

A new `admin-operator` Supabase Edge Function is the only API boundary for `/app/admin2`. It is a modular monolith: one deployed function with focused modules for access, inbox, customers, card data, system operations, audit, validation, and response presentation.

Every request follows this sequence:

1. Require a bearer token and resolve it through Supabase Auth.
2. Read `public.users` by the authenticated user ID through the server-side client.
3. Require `is_active = true` and `is_admin = true`.
4. Parse and validate an allowlisted action payload.
5. Execute only the handler registered for that action.
6. Return a sanitized response with a stable error code on failure.

Email, client-provided claims, `user_metadata`, route visibility, and request parameters never grant admin access. A missing profile row, inactive profile, or false admin flag returns `403`. An absent, expired, or invalid session returns `401`.

The service-role key stays inside the Edge Function. Browser roles have no direct read or write access to private operational tables, audit rows, review queues, or runtime controls.

### Data structures

#### `public.users.is_admin`

The applied migration defines the authorization flag as `boolean NOT NULL DEFAULT false`. Authenticated clients retain ordinary profile insert and update privileges for allowlisted columns but cannot insert or update `is_admin`.

#### `public.admin_audit_log`

Add an append-only, service-role-only table with:

- `id uuid primary key`;
- `actor_id uuid not null` referencing the authenticated operator;
- `action text not null`;
- `target_type text not null`;
- `target_id text` for sanitized identifiers;
- `reason text` where the action requires justification;
- `request_id uuid not null` for request correlation and idempotency;
- `outcome text not null` constrained to `succeeded` or `failed`;
- `details jsonb not null default '{}'` containing only allowlisted, sanitized metadata; and
- `created_at timestamptz not null default now()`.

The table has RLS enabled and grants no browser access. Admin mutations use narrow database functions that perform the state change and successful audit insert atomically. A failed mutation records only a safe failure category where doing so does not create a second failure path. Customer-detail reads are denied if their audit record cannot be written.

#### Runtime controls

System-wide pause or resume controls are not arbitrary key/value settings. If a worker needs an operator-controlled pause, add one allowlisted row per supported pipeline in a service-role-only runtime-control table. Workers must explicitly opt into a named control. V1 exposes only controls that an existing worker actually checks.

#### No inbox table

The Action Inbox is derived at request time from authoritative operational sources. It does not copy job or review state into another queue. Items disappear when their source is resolved or moves to a non-actionable state. Manual dismissal is excluded from V1.

## API contract

The Edge Function accepts `POST` requests with an `action` discriminator. Initial action families are:

- `access`: returns whether the current session has database-backed admin access;
- `inbox-list`: returns ranked actionable exceptions and counts;
- `customer-search` and `customer-detail`: return sanitized account and processing metadata;
- `customer-retry`: retries one allowlisted, idempotent operation;
- `customer-disable`: disables the app account and revokes active access through the approved server path;
- `card-review-list` and `card-review-action`: expose and mutate card identity or benefit proposals;
- `system-status` and `system-jobs`: return pipeline summaries and sanitized job history;
- `system-retry`, `system-quarantine`, and `system-control`: perform narrow recovery actions.

List actions are paginated and have bounded filters. Search requires an exact user ID or a normalized email fragment with a minimum length; it never supports arbitrary column queries. Mutation payloads include a client-generated request ID. Repeating a request ID returns the recorded result rather than applying the action twice.

Responses use stable codes such as `authentication_required`, `administrator_access_required`, `invalid_request`, `not_found`, `state_conflict`, `operation_in_progress`, and `request_failed`. Internal SQL, stack traces, credentials, raw provider responses, and customer content are never returned.

## Section behavior

### Action Inbox

The inbox presents a single ranked list with item type, severity, title, concise explanation, source status, age, and destination. Ranking is deterministic:

1. **Critical:** customer-blocking failures, stuck processing that cannot self-recover, or a disabled core pipeline.
2. **High:** failed or quarantined jobs, ambiguous data conflicts, and proposals blocking downstream processing.
3. **Normal:** routine pending reviews and stale-data warnings.

The server performs bounded source queries and merges their sanitized results. Each item links to the relevant customer, card-data, or system detail. Resolving the source removes the item on refresh.

### Customers

Customer Ops shows only the metadata needed to diagnose support issues:

- user ID, masked or normalized identity, account creation time, active state, and last activity;
- Gmail connection and last sync status;
- statement-processing counts, latest timestamps, and sanitized failure categories;
- counts of owned cards and processed statements; and
- consent and deletion-request status where available.

It does not expose raw emails, attachments, PDFs, passwords, access tokens, full transaction lists, or unmasked financial identifiers.

Initial actions are retrying a specifically failed sync or processing operation, disabling an account through a server-owned operation, and recording deletion-request progress. A retry is unavailable while the same operation is running. Account disablement requires a reason, confirmation, session revocation, and an audit record. Destructive data deletion remains outside the console until a separately approved retention and deletion design exists.

### Card Data

Card Data combines card-identity and benefit-enrichment review into one section with distinct filters. Every proposal shows its current state, proposed state, confidence, warnings, official source, retrieval time, parser version, and field-level evidence where available.

Supported actions are approve, edit and approve, merge, reject with reason, retry, quarantine, and unquarantine. The console reuses the existing locked resolution and approval paths rather than directly updating catalog or benefit tables. Bulk approval is excluded. Actions are unavailable when the source item is no longer in an eligible state.

### System

System Ops shows pipeline health, last successful run, queued/running/failed/quarantined counts, sanitized failure categories, attempt count, and next retry time. It supports retrying eligible jobs, quarantining with a reason, unquarantining, and operating only the explicit runtime controls implemented by the relevant workers.

The console never exposes secrets, raw fetched content, authorization headers, provider payloads, or unrestricted log search. A system action that would affect multiple jobs requires a separate future design; V1 actions target one job or one named control.

## Interaction design

- `/app/admin2` opens the Action Inbox.
- Wide layouts use a navigation rail and list/detail workspace.
- Small layouts support monitoring and urgent single-item actions without dense desktop tables.
- Current content remains visible during refresh, with a visible last-refreshed time.
- Successful sections remain usable when another source fails.
- Mutations are server-confirmed; approval, disablement, quarantine, and retry are never optimistic.
- An action locks while submitted, and the server also enforces idempotency.
- Reject, disable, quarantine, and deletion-request transitions require a reason and confirmation.
- No irreversible action is available directly from a list row; it opens a review or confirmation surface.
- `401` clears the stale local session and asks the user to sign in.
- `403` removes the admin workspace and returns the user to the ordinary app.
- Success notices are concise. Failures use sanitized, stable codes with an operator-safe explanation.
- Keyboard navigation, visible focus, semantic labels, large text, and reduced-motion behavior follow the app accessibility contract.

## Rollout

### Phase 1: Foundation

Build the `/app/admin2` shell, database-backed authorization, modular Edge Function, audit table, typed repository boundary, and route tests. Exit when non-admin access is blocked and every test mutation is audited.

### Phase 2: Inbox and Card Data

Add the ranked inbox and migrate existing card-identity and benefit-review workflows behind the new gateway. Exit when core data exceptions can be reviewed and resolved without SQL.

### Phase 3: System Ops

Add pipeline status, job detail, retry, quarantine, and only the runtime controls already honored by workers. Exit when common processing failures can be recovered without engineering access.

### Phase 4: Customer Ops

Add user search, metadata timeline, safe retry, account disablement, and deletion-request status. Exit when common support issues can be diagnosed without exposing prohibited customer content.

### Phase 5: Cutover

Expose the admin entry point to database-authorized users, run production smoke tests, compare parity with the existing review route, and retire the old route only after its supported actions are covered.

## Error handling

- Read failures are isolated by section and preserve successfully loaded data.
- Retryable network failures retain current content and offer a manual retry.
- Invalid transitions return `state_conflict` and force a refresh.
- Duplicate request IDs return the original safe outcome.
- Audit failure prevents a mutation from being reported as successful.
- Customer-detail audit failure prevents the detail response.
- Jobs already running return `operation_in_progress` and are not reset.
- Unexpected failures return `request_failed` and log only request IDs and safe failure categories.

## Testing

### Database

- Admin flag defaults false and cannot be assigned by authenticated clients.
- Founder backfill is correct.
- Audit and runtime-control tables deny browser access.
- Mutating functions require the service role, validate state, apply once, and write audit rows atomically.
- Repeated request IDs do not duplicate state changes.

### Edge Function

- Missing, expired, inactive, and non-admin sessions are rejected before domain queries.
- Every action validates its payload and returns only its documented projection.
- Customer and system responses omit prohibited fields.
- Mutation failures expose stable codes and never internal error details.
- Customer-detail access writes an audit record.

### Flutter

- Route and navigation visibility follow the access response without being treated as authorization.
- Inbox ranking, pagination, filtering, refresh, and navigation behave deterministically.
- Each section covers loading, empty, populated, partial failure, `401`, `403`, and stale-data states.
- Confirmation, required-reason, submission lock, success, conflict, and failure paths are covered.
- Desktop, tablet, small-screen, keyboard, semantics, and large-text behavior are verified.

### Integration and production smoke tests

- Founder access succeeds and a normal user is denied.
- Revoking `is_admin` blocks the next request.
- Approve, reject, merge, retry, quarantine, unquarantine, customer retry, and disable operations affect only the intended target and create audit records.
- Refreshing after each action reflects authoritative state.
- The old catalog-review route remains functional until cutover.
- No prohibited raw content appears in responses, UI logs, or audit details.

## Security and operational constraints

- `public.users.is_admin` is the authorization source; email is not.
- Authorization is evaluated from the database on every privileged request.
- No service-role or secret key is shipped to the client.
- New public-schema tables have RLS enabled and explicit grants.
- Browser roles receive no audit, runtime-control, or operational-queue privileges.
- Privileged database functions have explicit search paths and revoked `PUBLIC`, `anon`, and `authenticated` execution unless a narrower grant is documented.
- Sensitive identifiers are masked before response construction and audit insertion.
- Existing unrelated security-advisor findings are not silently folded into this feature; they require separate remediation work.

## Current prerequisite status

Migration `20260819063836_add_admin_flag_to_public_users.sql` is present locally and applied to the linked production project. Remote verification confirmed the secure default, founder assignment, blocked client writes to `is_admin`, preserved ordinary profile updates, and synchronized migration history.

The existing `admin-catalog-entry` Edge Function still uses an email allowlist. It remains unchanged until the new database-backed `admin-operator` gateway and its tests are ready. The old endpoint must not be switched to the new flag in an untested partial rollout.
