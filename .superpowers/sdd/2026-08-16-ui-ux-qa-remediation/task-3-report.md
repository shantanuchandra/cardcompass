# Task 3 report — Navigation, auth, splash, and settings

## Completed

- Renamed the shell’s visible destinations to **Transactions** and **Movies** while preserving the existing fragment-backed tab paths.
- Added `AppTab` and `AppTabSelection` in `lib/core/router/app_tab_selection.dart`. Dashboard consumers can call `AppTabSelection.of(context).select(AppTab.transactions)` (or another typed tab) without issuing a new route.
- Replaced Settings placeholder taps with explicit `BrandActionRow` outcomes: public-root Privacy, Data & Security, and Terms links; support email; and an About version dialog. Notifications is correctly marked unavailable.
- Applied the marketing theme to login and splash, made compact login copy at least 12 px, added visible signing-in/failure feedback, and retained the existing scenario rotation.
- Added splash progress status and an 8-second recovery state with Retry and Back to sign in. Retry invalidates the auth notifier; Back uses the existing `/login` route.

## Tests

Passed:

```text
flutter test test/core/oauth_redirect_test.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart
flutter analyze lib/core/router/app_router.dart lib/core/router/app_tab_selection.dart lib/features/auth/screens/login_screen.dart lib/features/auth/screens/splash_screen.dart lib/features/settings/screens/settings_screen.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart
```

## Notes

- OAuth redirect values and redirects are unchanged; the OAuth redirect contract passed unchanged.
- Host-root external links are resolved from `Uri.base`, which preserves the deployed site origin while keeping `/privacy/`, `/data-security/`, and `/terms/` as the canonical paths.

## Review round 1

- Wired the Dashboard **Manage** and **View All** actions to `AppTabSelection`, selecting the Cards and Transactions tabs respectively.
- Raised the desktop rail and mobile bottom-navigation labels to 14 px. The bottom bar is 76 px high and the rail text is flexible, so the larger labels retain their target sizes without overflow.
- Replaced the source-only mobile-label assertion with rendered widget tests. They verify all five 14 px labels, tap Transactions, and observe the rendered destination. A second rendered test taps Dashboard Manage and View All actions through `AppTabSelection` and observes Cards then Transactions.
- Moved browser history mutation behind a web-only adapter. Browser behavior is unchanged (`history.replaceState` still receives the same `#/app…` fragments), and this permits the shell widgets to run in VM widget tests.

### Command evidence

```text
$ flutter test test/core/oauth_redirect_test.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart test/features/dashboard/dashboard_brand_test.dart
00:01 +29: All tests passed!

$ flutter analyze lib/core/router/app_router.dart lib/core/router/app_tab_selection.dart lib/core/router/browser_history.dart lib/core/router/browser_history_stub.dart lib/core/router/browser_history_web.dart lib/features/auth/screens/login_screen.dart lib/features/auth/screens/splash_screen.dart lib/features/settings/screens/settings_screen.dart lib/features/dashboard/screens/dashboard_screen.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart test/features/dashboard/dashboard_brand_test.dart
Analyzing 13 items...
No issues found!

$ git diff --check
(no output; passed)

$ flutter build web --no-wasm-dry-run
✓ Built build/web
```

## Review round 2

- The 14 px mobile labels now allow two lines instead of using ellipsis. The bottom-navigation height grows with the active text scale, preserving the icon, full label, and tap target at large accessibility text sizes.
- Navigation item semantics exclude the visual child labels, so the action node announces exactly `Transactions` rather than a duplicated label.
- Added a 390 px, 2× text-scale rendered geometry test. It asserts that the Transactions label remains 14 px, occupies both needed text boxes, is not ellipsized, has sufficient height, and retains the exact semantic label without rendering exceptions.

### Command evidence

```text
$ flutter test test/core/router/app_shell_brand_test.dart
00:00 +7: All tests passed!

$ flutter analyze lib/core/router/app_router.dart lib/core/router/app_tab_selection.dart lib/core/router/browser_history.dart lib/core/router/browser_history_stub.dart lib/core/router/browser_history_web.dart test/core/router/app_shell_brand_test.dart
Analyzing 6 items...
No issues found!

$ flutter build web --no-wasm-dry-run
✓ Built build/web

$ git diff --check
(no output; passed)
```
