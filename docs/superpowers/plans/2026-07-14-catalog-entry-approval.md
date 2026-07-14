# Catalog entry approval implementation plan

**Goal:** Close the black hole where user-submitted new-card requests queue into `card_benefits_staging` but never reach `card_catalog`.

**Architecture:** Keep the existing submit path (`request-card-catalog-entry` edge function → `submit_card_catalog_request` RPC). Add service-role RPCs for list/approve/reject, an `admin-catalog-entry` edge function that calls them with the caller's auth token, a small Dart service + policy layer (TDD), and a third tab on `pm_pruning_debug_screen.dart`. On approve, kick off the same benefit extraction pipeline used by the Card Benefits Refresh tab.

**Tech stack:** Supabase Postgres (SECURITY DEFINER RPCs), Supabase Edge Functions, Flutter/Dart unit tests.

## Approval data path

| Moment | Data stored | Table |
| --- | --- | --- |
| User submits unmatched card URL during sync | `request_type: catalog_entry`, `card_id = NULL`, `status = pending` | `card_benefits_staging` |
| Admin lists pending requests | Read via `admin-catalog-entry` → `list_pending_catalog_entry_requests` | `card_benefits_staging` |
| Admin approves | New or existing catalog row; staging linked with `card_id`, `status = approved` | `card_catalog`, `card_benefits_staging` |
| Admin rejects | `status = rejected`, reviewer metadata | `card_benefits_staging` |
| Post-approve (Flutter) | Benefit extraction staged for PM review | `card_benefits_staging` (benefit workflow) |

## File structure

- `supabase/migrations/20260714130000_catalog_entry_approval.sql` — list/approve/reject RPCs
- `supabase/functions/admin-catalog-entry/index.ts` — authenticated admin proxy
- `lib/core/services/catalog_entry_staging_policy.dart` — row classification + field parsing
- `lib/core/services/catalog_entry_review_service.dart` — edge-function client
- `lib/features/debug/widgets/catalog_entry_requests_panel.dart` — PM tab UI
- `test/catalog_entry_staging_policy_test.dart`
- `test/catalog_entry_review_service_test.dart`

## Tasks

- [x] Confirm approval surface: PM debug screen tab (no new auth gate)
- [x] Confirm post-approval: auto benefit extraction
- [x] Policy + service unit tests (TDD)
- [x] Postgres RPCs (service_role only)
- [x] Edge function
- [x] PM tab UI wired to service + extraction