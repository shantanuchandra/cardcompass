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
