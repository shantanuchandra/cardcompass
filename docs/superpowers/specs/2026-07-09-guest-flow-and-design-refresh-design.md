# Guest Flow Fix & Design System Refresh

Date: 2026-07-09

## Problem

`cardcompass` is a Flutter/Riverpod app backed by Supabase. The Supabase project is expired/dead. "Continue as Guest" creates a fake local `User(id: 'guest')` but every screen still calls Supabase-backed repositories, which fail silently (`catch (e) { print(...); return []; }`), leaving guest users with empty lists, hardcoded placeholder numbers (₹100,000 credit limit, ₹412 rewards), "Coming Soon" stubs, and ~25 dead TODO buttons across Home, Transactions, Analytics, Recommendations, Statements, Profile, and Settings screens.

Separately, `login_screen.dart` navigates to `HomeScreen` directly on auth success, while the named route `/home` resolves to a different screen, `DashboardScreenRefactored` — two divergent "home" implementations reachable depending on entry path. `home_screen.dart` also declares a second, shadowing set of `activeCardsProvider`/`recentTransactionsProvider`/etc. at file-bottom that silently overrides the "real" ones in `cards_provider.dart`.

The visual design is default Material3 (`ColorScheme.fromSeed(primaryColor)`, no custom typography, inconsistent use of the app's own `AppSpacing`/`AppBorderRadius` tokens) and needs a deliberate fintech-grade redesign.

## Goals

1. Guest mode is fully functional and realistic: every guest-reachable screen shows populated, internally-consistent data with no reliance on Supabase.
2. Every button/action on guest-reachable screens does something real (navigate, toggle, filter, confirm) — no silent no-ops.
3. Resolve the home-screen/provider duplication bug so there is one canonical home/dashboard.
4. Apply a cohesive "modern fintech" design system (navy/gold palette, Inter typography, consistent spacing/elevation) across the guest-reachable screens, then sweep remaining screens for consistency.
5. Ship on a feature branch, merged into `main`.

## Non-goals

- Fixing/renewing the actual Supabase project (explicitly out of scope — treated as permanently unavailable for this pass).
- Building real backend-integration features (Gmail sync, PDF statement parsing accuracy, etc.) — those remain as-is; only their guest-mode presentation/data path is touched.
- Comprehensive redesign of screens with zero guest-flow relevance beyond a visual consistency pass (e.g. deep email-sync configuration screens) — light-touch only.

## Architecture

### Mock data layer (`lib/core/mock/`)

- `mock_data.dart` — single static, internally-consistent dataset: 3 `CreditCard`s (HDFC Regalia Gold / Axis Ace / ICICI Amazon Pay Card — real bank names, since the repo already references real Indian banks in `assets/enhanced_credit_cards.csv`), ~25 `Transaction`s spanning the last 2 months across varied categories with `rewardEarned` populated, 3 `RewardBalance`s (one per card), 3 `Statement`s (mixed `PaymentStatus`), a handful of `CardBenefit`/`BenefitUsageRecord` per card, 4-5 `AppNotification`s.
- All IDs/dates are computed relative to a fixed reference (no `DateTime.now()` baked into static const data — computed once at access time so "last 2 months" stays current).
- This becomes the **single source of truth** for guest fixtures, replacing the scattered generators in `statements_viewmodel.dart` (`_generateMockStatements`, `_generateMockCards`), `benefits_viewmodel.dart` (`_loadMockData`, `_getMockCards`, `_generateMockUsageData`), and `notifications_viewmodel.dart` (`_createMockNotifications`), which get deleted in favor of reading through the repository layer like real data does.

### Mock repositories

- `MockCardRepository implements CardRepository`, `MockTransactionRepository implements TransactionRepository`, `MockStatementRepository implements StatementRepository` — read/write against in-memory copies of the mock dataset (writes like `addUserCard` mutate the in-memory list so the session feels real, but nothing persists across app restarts).
- `benefits`, `notifications`, and `user-profile` repositories currently have no abstract interface (concrete Supabase-only classes). Extract minimal interfaces (`BenefitsRepository`, `NotificationRepository`, `UserProfileRepository` — just the methods each viewmodel actually calls) so a `Mock*` implementation can substitute cleanly, matching the existing pattern for the other four.

### Wiring: guest/live switch

In `lib/core/providers/service_providers.dart`, each repository provider becomes guest-aware:

```dart
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.user?.id == 'guest' ? MockCardRepository() : SupabaseCardRepository();
});
```

Same pattern for transaction/statement/benefits/notifications/user-profile repository providers. This is the single switch point — screens and viewmodels are unchanged, since they already go through these providers.

### Home screen / routing fix

- Delete the shadowing provider block at `home_screen.dart:1123-1187`; the canonical providers live in `cards_provider.dart` / `transactions_provider.dart`.
- `login_screen.dart`'s `ref.listen` on auth success navigates via `Navigator.of(context).pushReplacementNamed(AppRoutes.home)` instead of constructing `HomeScreen` directly, so there is exactly one resolved home screen (`DashboardScreenRefactored`, since that's what `/home` and `/dashboard` both already resolve to).
- Remove the placeholder-number fallbacks (`total > 0 ? total : 100000.0`, `totalRewards > 0 ? totalRewards : 412.0`) now that mock data always yields realistic non-zero values; real (Supabase) empty states should show a genuine empty state, not a fake number.

### Button/stub fixes

Every TODO/no-op identified in exploration gets real behavior:
- Navigation stubs (profile avatar → Profile screen, "View All" → Transactions screen) wired to existing routes.
- Filter/export/search actions get real (client-side, against mock or live data) implementations — filter transactions by category/date, export triggers a real CSV share via `share`/`path_provider` (already a dependency) or a clearly-labeled "not available offline" dialog if truly backend-dependent.
- Settings/profile toggles persist via `shared_preferences` and reflect immediately in UI.
- Destructive actions (account deletion, remove card) get confirmation dialogs; in guest mode, account deletion is explicitly "not available in guest mode — sign in to manage your account" rather than either faking success or silently failing.
- Recommendations screen: implement `_loadRecommendations()` against mock/live cards+transactions using the existing `RecommendationService` (already implemented, just never called from this screen).

## Design system

Derived from `/ui-ux-pro-max` design-system search for "fintech credit card rewards tracker, premium, trustworthy":

- **Palette**: primary navy `#0F172A`, secondary deep blue `#1E3A8A`, accent gold `#A16207` (rewards/highlights, contrast-adjusted), destructive `#DC2626`, success `#16A34A`, warning `#D97706`. Light surfaces `#F8FAFC`/white cards; dark mode uses desaturated tonal navy surfaces (not pure black, not inverted light-mode values) — both themes designed together, not derived by mechanical inversion. Existing bank-brand (`hdfcColor`, `sbiColor`, etc.) and network colors (`visaColor`, etc.) are kept as-is since they're already correct per-brand and unrelated to the app chrome palette.
- **Typography**: add `google_fonts` dependency, adopt **Inter** across `AppTextStyles` (heading1-3, body1-2, caption, button), replacing the current unstyled Material default. Keep the same size/weight scale already defined, just apply the real typeface + slightly refined weights (600 for headings instead of bold-700 blanket, per the "precision" fintech mood).
- **Spacing/radius**: keep `AppSpacing`/`AppBorderRadius` token classes; audit guest-reachable screens to replace hardcoded `EdgeInsets`/`BorderRadius.circular(n)` with the token equivalents for consistency.
- **Component language**: "Executive Dashboard"-influenced KPI cards for credit limit/rewards/spend (large numerals, small trend/caption line, subtle 1-2dp elevation, 16px rounded corners) rather than heavy glassmorphism (flagged as poor-performance/low-contrast-risk for this product type). Hero transitions between the card list and card detail screen. Skeleton loading states replacing spinner-only/blank-screen loading. Helpful empty states (icon + message + action) replacing blank white space, used both for genuine no-data cases and as a template for any remaining backend-dependent stub.
- Applies the Flutter stack checklist: theming via `ColorScheme.fromSeed` off the new navy seed + `ThemeData`/`Theme.of(context)` everywhere (no hardcoded ad-hoc colors), light+dark designed together, 44×48pt touch targets, `PopScope` (not deprecated `WillPopScope`) where back-handling is custom.

## Rollout order

1. Mock data layer + mock repositories + interface extraction.
2. Provider wiring (guest/live switch) + home screen/routing bug fixes.
3. Design system: theme.dart overhaul (colors, typography, add `google_fonts`), applied globally via `MaterialApp` theme (light+dark) — this alone updates every screen's default look since screens consume `Theme.of(context)`.
4. Screen-by-screen pass over guest-reachable screens: Login/Splash, Home/Dashboard, Cards list, Card details, Transactions, Analytics, Recommendations, Statements, Benefits, Notifications, Profile, Settings — fix stub buttons, apply spacing tokens, verify against mock data end-to-end.
5. Consistency sweep of remaining screens (Add Card, email-sync/advisor screens) for visual alignment only.
6. Manual verification pass: run the app, walk the full guest flow screen by screen (this is a Flutter mobile app — verification is via `flutter run` on a simulator/emulator, not a web preview tool).
7. Commit in logical chunks on a feature branch (`feature/guest-flow-redesign`), push, merge into `main`.

## Testing

No new automated test suite is in scope beyond what already exists (`test/` — repository/service unit tests per recent commit history). Mock repositories should be simple enough to sanity-check by reading; the real verification is manual, running the guest flow in a simulator per the `run`/`verify` skills available in this environment. If time permits, add lightweight unit tests for the mock data layer's internal consistency (e.g. transaction dates fall within claimed range, reward totals are non-negative) — not full screen/widget tests.

## Risks / open questions

- **Riverpod circular-provider risk**: making `cardRepositoryProvider` watch `authStateProvider` introduces a dependency from the service layer to the auth layer that didn't exist before. Need to confirm this doesn't create a provider cycle (auth provider doesn't itself depend on any repository provider — confirmed clean from `auth_provider.dart` read during exploration).
- **`benefits`/`notifications`/`user-profile` interface extraction** touches existing Supabase-backed concrete classes to have them `implement` a new interface — low risk (additive), but needs care not to break existing call sites.
- Flutter build/run environment (Xcode/Android SDK availability in this sandbox) is unverified — verification step will confirm what's actually runnable here and adjust if only static analysis (`flutter analyze`) is feasible.
