# Cutover Task 3 Report

## Result

- Replaced the legacy catalog-review UI route with an exact redirect to `/app/admin2?section=card-data`.
- Preserved direct `/app/admin2` mounting and its server-backed denial behavior.
- Added strict initial-section parsing: only `card-data` opens Card Data; every other value opens Action Inbox.
- Added cached, gateway-derived Admin entry visibility for wide shell and Settings.
- Kept Admin outside the five primary consumer tabs and out of compact bottom navigation.
- Added semantic, 48px, keyboard-compatible secondary navigation and injectable Settings/shell presentation tests.

## TDD evidence

- RED: new tests failed to compile because `showAdmin`, `onAdminTap`, `onOpenAdmin`, and `initialSectionQuery` did not exist.
- GREEN: focused router, Settings, and Admin operator tests passed after the minimal route, provider, and UI changes.

## Verification

- `flutter test test/core/router/app_router_test.dart test/features/settings/settings_screen_test.dart test/features/admin2` — 156 passed.
- Scoped `flutter analyze` over all changed Dart sources and tests — no issues.
- `git diff --check` — clean.

## Risks

- Conditional discovery adds one cached Admin Operator access call for each authenticated provider lifecycle. The destination still authorizes independently, so hiding or showing the link is never an authorization boundary.
- The legacy route redirect is intentionally exact and does not preserve arbitrary legacy query parameters.

## Account-switch correction

- Reproduced the original scope-wide cache retaining an allowed admin result after sign-out.
- Partitioned access by current authenticated user ID with auto-disposed families.
- Kept discoverability and direct-route access in separate caches, ensuring a route mount always performs a current gateway check.
- Added an A -> sign-out -> B -> A widget regression without restarting `ProviderScope`; it proves the entry disappears, unauthenticated state makes no request, B cannot see A's workspace, and each route check is identity-current.
- Updated focused verification: 157 tests passed; scoped analysis and diff checks remain clean.
