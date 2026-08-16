# CardCompass UI/UX QA Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CardCompass public site and Flutter application accessible, responsive, interaction-complete, and visually consistent with the approved editorial brand system.

**Architecture:** Establish semantic work/marketing themes and a small set of responsive brand primitives first. Migrate authenticated journeys page-by-page without changing their domain providers, then shorten and improve the public experience while preserving SEO, privacy, attribution, analytics, and OAuth contracts.

**Tech Stack:** Flutter 3.44+, Dart 3.12+, Material 3, Riverpod, GoRouter, static HTML/CSS/JavaScript, Node `node:test`.

**Spec:** `docs/superpowers/specs/2026-08-16-ui-ux-qa-remediation-design.md`

## Global Constraints

- Preserve Ink `#0B1015`, Paper `#F4F0E6`, Ledger `#DDE7E1`, Signal `#3FE0D0`, and Reward `#FFB547` semantics.
- Preserve the current Google OAuth implementation and redirect behavior.
- Do not change recommendation, reward, milestone, or movie-offer calculations.
- Do not change database schema, statement processing, Gmail sync, or data retention.
- Respect user text scaling through 200%; minimum non-decorative text is 12 logical/CSS pixels and actionable/body copy is at least 14.
- Interactive targets are at least 44×44 logical/CSS pixels.
- Preserve landing SEO, attribution, privacy-safe analytics, waitlist behavior, and natural-aspect-ratio imagery.
- Allow full-width authenticated data views when the extra space improves comparison, charts, tables, or card scanning; keep prose, forms, legal copy, and explanations on readable measures.
- Do not modify or commit `lib/core/services/gmail_sync_service.dart` or `test/core/services/gmail_sync_service_test.dart`.
- Each task uses test-first red/green verification and commits only its owned files.

## File structure

| File | Responsibility |
|---|---|
| `lib/core/theme/app_theme.dart` | Semantic work and marketing Material themes |
| `lib/core/theme/brand_components.dart` | Reusable accessible page, surface, metric, state, action, evidence, and responsive components |
| `lib/core/router/app_router.dart` | Consistent navigation labels, working Dashboard/Settings destinations |
| `lib/features/**/screens/*.dart` | Domain-specific page composition and copy only |
| `assets/fonts/**` | Bundled Manrope, Fraunces, and IBM Plex Mono font assets |
| `landing/style.css` | Landing composition and responsive disclosure |
| `landing/resources.css` | Utilities/legal reading and calculator layout |
| `landing/index.html` | Reduced landing narrative while retaining required contracts |
| `landing/tools/**/index.html` | Utility action-first composition |
| `test/core/theme/**` | Theme, typography, scaling, and component contracts |
| `test/features/**` | Page hierarchy, interaction, responsiveness, and state contracts |
| `test/landing/**` | Public layout, accessibility, and preserved funnel contracts |

---

### Task 1: Local typography and semantic themes

**Files:**
- Create: `assets/fonts/manrope/Manrope-Regular.ttf`
- Create: `assets/fonts/manrope/Manrope-SemiBold.ttf`
- Create: `assets/fonts/manrope/Manrope-Bold.ttf`
- Create: `assets/fonts/fraunces/Fraunces-SemiBold.ttf`
- Create: `assets/fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf`
- Create: `assets/fonts/ibm-plex-mono/IBMPlexMono-SemiBold.ttf`
- Modify: `pubspec.yaml`
- Modify: `lib/app.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart`

**Interfaces:**
- Produces: `AppTheme.work`, `AppTheme.marketing`, and locally declared font families `Manrope`, `Fraunces`, `IBM Plex Mono`.
- Consumes: existing `BrandColors`, `BrandRadius`, and `BrandSpacing`.

- [ ] **Step 1: Write failing theme and scaling tests**

```dart
testWidgets('app respects platform text scaling', (tester) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: const ProviderScope(child: CardCompassApp()),
    ),
  );
  expect(MediaQuery.textScalerOf(tester.element(find.byType(MaterialApp))),
      const TextScaler.linear(2));
});

test('work theme is light and marketing theme is dark', () {
  expect(AppTheme.work.brightness, Brightness.light);
  expect(AppTheme.marketing.brightness, Brightness.dark);
});
```

- [ ] **Step 2: Run the focused tests and verify red**

Run: `flutter test test/core/theme/app_theme_test.dart`

Expected: FAIL because the fixed scaler remains and `work`/`marketing` do not exist.

- [ ] **Step 3: Add licensed local font assets and declarations**

Declare exact families and weights in `pubspec.yaml`:

```yaml
fonts:
  - family: Manrope
    fonts:
      - asset: assets/fonts/manrope/Manrope-Regular.ttf
        weight: 400
      - asset: assets/fonts/manrope/Manrope-SemiBold.ttf
        weight: 600
      - asset: assets/fonts/manrope/Manrope-Bold.ttf
        weight: 700
```

Add equivalent Fraunces 600 and IBM Plex Mono 400/600 declarations. Record each font’s upstream license beside the assets.

- [ ] **Step 4: Implement semantic themes and remove the scaler override**

Use a private builder so control styling remains shared:

```dart
abstract final class AppTheme {
  static ThemeData get work => _build(brightness: Brightness.light);
  static ThemeData get marketing => _build(brightness: Brightness.dark);
}
```

Set `MaterialApp.router(theme: AppTheme.work)` and apply `Theme(data: AppTheme.marketing, child: ...)` only to login/splash/Ink surfaces. Delete the `MediaQuery.copyWith(textScaler: ...)` builder.

- [ ] **Step 5: Verify theme tests and font asset resolution**

Run: `flutter pub get && flutter test test/core/theme/app_theme_test.dart`

Expected: PASS; no missing-font warnings.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock assets/fonts lib/app.dart lib/core/theme/app_theme.dart test/core/theme/app_theme_test.dart
git commit -m "feat: add accessible semantic app themes"
```

### Task 2: Accessible shared page primitives

**Files:**
- Modify: `lib/core/theme/brand_components.dart`
- Test: `test/core/theme/brand_components_test.dart`
- Test: `test/core/theme/brand_responsive_test.dart`

**Interfaces:**
- Produces: `BrandPageHeader`, `BrandMetric`, `BrandActionRow`, `BrandStateView`, `BrandEvidenceStrip`, and `ResponsiveValueRow`.
- Produces: `BrandContentFrame` with constrained and full-width data modes.
- Consumes: `AppTheme.work`, brand tokens, and Material semantics.

- [ ] **Step 1: Write failing component tests**

```dart
testWidgets('ResponsiveValueRow stacks at 390px and 200 percent text',
    (tester) async {
  await pumpBrand(tester, width: 390, textScale: 2,
      child: ResponsiveValueRow(children: const [Text('One'), Text('Two')]));
  expect(tester.getTopLeft(find.text('Two')).dy,
      greaterThan(tester.getTopLeft(find.text('One')).dy));
});

testWidgets('disabled action row announces unavailable and has no chevron',
    (tester) async {
  await pumpBrand(tester,
      child: const BrandActionRow(title: 'Notifications', unavailable: true));
  expect(find.text('Coming soon'), findsOneWidget);
  expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
});

testWidgets('content frame can expand data views without stretching prose',
    (tester) async {
  await pumpBrand(tester, width: 1600,
      child: const BrandContentFrame(
        mode: BrandContentMode.fullWidthData,
        child: Text('Data view'),
      ));
  expect(tester.getSize(find.byType(BrandContentFrame)).width, greaterThan(1200));
});
```

- [ ] **Step 2: Run tests and verify red**

Run: `flutter test test/core/theme/brand_components_test.dart test/core/theme/brand_responsive_test.dart`

Expected: FAIL because the interfaces do not exist.

- [ ] **Step 3: Implement the focused primitives**

`ResponsiveValueRow` chooses `Column` when `maxWidth < 600` or `MediaQuery.textScalerOf(context).scale(14) >= 21`. `BrandActionRow` requires exactly one of `onTap` or `unavailable`. `BrandStateView` accepts `title`, `message`, `icon`, `actionLabel`, and `onAction` and never renders raw exceptions.

- [ ] **Step 4: Raise evidence typography and target sizes**

Update `BrandEvidenceStrip` labels from 9 to 12, body values to at least 14, and ensure link/action hit regions use `BoxConstraints(minWidth: 44, minHeight: 44)`.

- [ ] **Step 5: Run component tests at all target sizes**

Run: `flutter test test/core/theme/brand_components_test.dart test/core/theme/brand_responsive_test.dart`

Expected: PASS at widths 390, 768, 1280 and scale factors 1, 1.5, 2.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/brand_components.dart test/core/theme/brand_components_test.dart test/core/theme/brand_responsive_test.dart
git commit -m "feat: add accessible brand page primitives"
```

### Task 3: Navigation, login, splash, and interaction integrity

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `lib/features/auth/screens/splash_screen.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/core/router/app_shell_brand_test.dart`
- Test: `test/features/auth/login_screen_test.dart`
- Test: `test/features/settings/settings_brand_test.dart`

**Interfaces:**
- Consumes: `AppTheme.marketing`, `BrandActionRow`, existing auth notifier and OAuth callbacks.
- Produces: consistent `Transactions`/`Movies` navigation and explicit Settings action states.

- [ ] **Step 1: Add failing interaction tests**

```dart
testWidgets('every enabled settings row has an action', (tester) async {
  await pumpSettings(tester);
  for (final title in ['Privacy', 'Data & Security', 'Terms', 'About']) {
    final row = find.widgetWithText(BrandActionRow, title);
    expect(tester.widget<BrandActionRow>(row).onTap, isNotNull);
  }
});

testWidgets('mobile navigation uses concise consistent labels', (tester) async {
  await pumpShell(tester, width: 390);
  for (final label in ['Dashboard', 'Cards', 'Transactions', 'Movies', 'Settings']) {
    expect(find.text(label), findsOneWidget);
  }
});
```

- [ ] **Step 2: Run focused tests and verify red**

Run: `flutter test test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart`

Expected: FAIL for legacy labels, tiny copy, or empty callbacks.

- [ ] **Step 3: Repair navigation and Settings actions**

Route Dashboard section actions through the shell’s tab-selection interface. Use `url_launcher` for `/privacy/`, `/data-security/`, `/terms/`, and a `mailto:` support route. Render Notifications as `unavailable: true` unless a real stateful destination exists. About opens a version dialog.

- [ ] **Step 4: Improve login and splash without changing OAuth**

Apply the marketing theme, raise all 8–11 px content to the typography floor, retain the approved split-screen rotation, and expose `Signing in…`/failure in the login card. Splash shows `Securing your session` then `Loading your wallet`; after the existing timeout it displays Retry and Back to sign in.

- [ ] **Step 5: Verify OAuth contract and focused UI tests**

Run: `flutter test test/core/oauth_redirect_test.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart`

Expected: PASS with existing OAuth redirect values unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/auth/screens/login_screen.dart lib/features/auth/screens/splash_screen.dart lib/features/settings/screens/settings_screen.dart test/core/router/app_shell_brand_test.dart test/features/auth/login_screen_test.dart test/features/settings/settings_brand_test.dart
git commit -m "feat: complete accessible app navigation"
```

### Task 4: Dashboard decision hierarchy

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Test: `test/features/dashboard/dashboard_brand_test.dart`
- Test: `test/features/dashboard/dashboard_responsive_test.dart`

**Interfaces:**
- Consumes: `BrandPageHeader`, `BrandMetric`, `BrandStateView`, `ResponsiveValueRow`, existing dashboard providers.
- Produces: working section actions and responsive primary/supporting metric hierarchy.

- [ ] **Step 1: Write failing hierarchy and navigation tests**

```dart
testWidgets('monthly spend is primary and supporting metrics stack at scale',
    (tester) async {
  await pumpDashboard(tester, width: 390, textScale: 2, data: fixture);
  expect(find.byKey(const Key('primary-spend-metric')), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('dashboard view-all actions select their destinations',
    (tester) async {
  await pumpDashboard(tester, data: fixture);
  await tester.tap(find.text('View all transactions'));
  expect(selectedAppTab.value, AppTab.transactions);
});
```

- [ ] **Step 2: Verify the tests fail**

Run: `flutter test test/features/dashboard/dashboard_brand_test.dart test/features/dashboard/dashboard_responsive_test.dart`

Expected: FAIL because KPIs are fixed three-up and callbacks are empty.

- [ ] **Step 3: Recompose the first viewport**

Order greeting/context, primary next action/recommendation, primary spend, then supporting rewards and total limit. Use `ResponsiveValueRow` for supporting metrics. Empty data replaces metrics with one setup action.

- [ ] **Step 4: Wire section actions and normalize states**

Cards navigates to Cards; Recent Spend navigates to Transactions; unsupported statements use a neutral unavailable state; errors use `BrandStateView` with Retry and no raw exception.

- [ ] **Step 5: Run Dashboard tests**

Run: `flutter test test/features/dashboard/dashboard_brand_test.dart test/features/dashboard/dashboard_responsive_test.dart`

Expected: PASS at 390/768/1280 and 1×/2× scale.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart test/features/dashboard/dashboard_brand_test.dart test/features/dashboard/dashboard_responsive_test.dart
git commit -m "feat: prioritize dashboard decisions"
```

### Task 5: Cards, add-card, and card-detail journeys

**Files:**
- Modify: `lib/features/cards/screens/cards_screen.dart`
- Modify: `lib/features/cards/screens/add_card_screen.dart`
- Modify: `lib/features/cards/screens/card_detail_screen.dart`
- Test: `test/features/cards/cards_brand_test.dart`
- Create: `test/features/cards/add_card_ux_test.dart`
- Create: `test/features/cards/card_detail_ux_test.dart`

**Interfaces:**
- Consumes: existing card catalogue/repository APIs and shared primitives.
- Produces: `CardIdentityMark` fallback, two-step add-card UI, ordered detail disclosures.

- [ ] **Step 1: Write failing journey tests**

```dart
testWidgets('add card exposes search and confirm progress', (tester) async {
  await pumpAddCard(tester);
  expect(find.text('1 Search'), findsOneWidget);
  expect(find.text('2 Confirm'), findsOneWidget);
});

testWidgets('last four explains optional use and rejects non-four digits',
    (tester) async {
  await reachConfirmStep(tester);
  await tester.enterText(find.byKey(const Key('last-four')), '12');
  await tester.tap(find.text('Add card'));
  expect(find.text('Enter exactly four digits or leave this blank'), findsOneWidget);
});
```

- [ ] **Step 2: Verify tests fail**

Run: `flutter test test/features/cards`

Expected: FAIL for missing progress, validation, and detail hierarchy.

- [ ] **Step 3: Improve card identity and add-card flow**

Show issuer color/monogram, name, issuer, last-four, sync/status, then limit. Add a visible two-step indicator, optional-field rationale, exact four-digit validation, and persistent search query when changing selection.

- [ ] **Step 4: Recompose card detail**

Order summary, best uses, milestone, current bill, rewards/fees, and history. Use accessible `ExpansionTile`/tab semantics for secondary sections, maintaining keyboard access and state.

- [ ] **Step 5: Run card tests and 200% scale checks**

Run: `flutter test test/features/cards`

Expected: PASS with long card names and no overflow at 390 px/2×.

- [ ] **Step 6: Commit**

```bash
git add lib/features/cards/screens test/features/cards
git commit -m "feat: clarify card management journeys"
```

### Task 6: Transactions hierarchy, filters, and safe errors

**Files:**
- Modify: `lib/features/transactions/screens/transactions_screen.dart`
- Modify: `lib/features/transactions/widgets/spend_trend_panel.dart`
- Test: `test/features/transactions/transactions_brand_test.dart`
- Create: `test/features/transactions/transactions_ux_test.dart`

**Interfaces:**
- Consumes: existing `TxnsState`, notifier methods, category display, shared primitives.
- Produces: primary spend metric, responsive filter sheet, simplified transaction rows, mapped error copy.

- [ ] **Step 1: Write failing responsive and error tests**

```dart
testWidgets('ledger does not render raw repository exception', (tester) async {
  await pumpLedgerError(tester, StateError('postgrest table failure'));
  expect(find.textContaining('postgrest'), findsNothing);
  expect(find.text('Try again'), findsOneWidget);
});

testWidgets('filters open in a sheet on narrow screens', (tester) async {
  await pumpLedger(tester, width: 390);
  await tester.tap(find.text('Filters'));
  expect(find.byType(BottomSheet), findsOneWidget);
});
```

- [ ] **Step 2: Verify tests fail**

Run: `flutter test test/features/transactions`

Expected: FAIL for raw error and inline filter panel.

- [ ] **Step 3: Recompose metrics and filters**

Use spend as `BrandMetric(primary: true)`; rewards/top category are supporting metrics. Replace the inline filter expander with a bottom sheet below 600 px and dialog/panel above it. The closed control summarizes active filter count.

- [ ] **Step 4: Simplify rows and map errors**

Rows show merchant/description, amount, date, card, and category in that order. Move supplemental metadata to a detail disclosure. Map repository failures to stable user copy and Retry.

- [ ] **Step 5: Run transaction tests**

Run: `flutter test test/features/transactions`

Expected: PASS at target widths/scales with long merchant names.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions test/features/transactions
git commit -m "feat: simplify the transaction ledger"
```

### Task 7: Movie optimizer question flow and result hierarchy

**Files:**
- Modify: `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`
- Modify: `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_brand_test.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_results_test.dart`
- Create: `test/features/benefits/movie_deals/movie_deals_ux_test.dart`

**Interfaces:**
- Consumes: existing `MovieTicketRequest` and evaluator/provider output unchanged.
- Produces: plain-language responsive form and winner-first result view.

- [ ] **Step 1: Write failing copy, layout, and disclosure tests**

```dart
testWidgets('movie form asks plain-language questions', (tester) async {
  await pumpMovieDeals(tester, width: 390);
  expect(find.text('How many tickets?'), findsOneWidget);
  expect(find.textContaining('TICKET SPECIFICATIONS'), findsNothing);
});

testWidgets('result leads with recommendation and hides calculation detail',
    (tester) async {
  await pumpMovieResult(tester, fixture);
  expect(find.text('Best option'), findsOneWidget);
  expect(find.text('Show calculation'), findsOneWidget);
});
```

- [ ] **Step 2: Verify tests fail**

Run: `flutter test test/features/benefits/movie_deals`

Expected: FAIL for technical copy and always-visible detail.

- [ ] **Step 3: Implement the question-led responsive form**

Use labels `How many tickets?`, `Price per ticket`, `Where are you booking?`, and `Which cinema?`. Stack below 600 px or high text scale. Keep the evaluator input types and values unchanged.

- [ ] **Step 4: Implement winner-first results**

Show recommended route, expected saving, effective ticket price, and reason. Put alternatives in a compact comparison list and cap/eligibility/arithmetic in an accessible disclosure labelled `Show calculation`.

- [ ] **Step 5: Run all movie tests**

Run: `flutter test test/features/benefits/movie_deals`

Expected: PASS with evaluator fixtures unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/features/benefits/movie_deals test/features/benefits/movie_deals
git commit -m "feat: make movie optimization decision-first"
```

### Task 8: Landing narrative and public accessibility

**Files:**
- Modify: `landing/index.html`
- Modify: `landing/style.css`
- Modify: `landing/script.js`
- Test: `test/landing/integration.test.js`
- Test: `test/landing/final-review-contract.test.js`
- Create: `test/landing/accessibility-layout.test.js`

**Interfaces:**
- Consumes: existing waitlist IDs/RPC field names, analytics events, attribution, OAuth links, recommendation rotation.
- Produces: shorter semantic section order and reduced-motion/manual disclosure behavior.

- [ ] **Step 1: Write failing public layout contracts**

```js
test('core landing narrative has five top-level sections or fewer', () => {
  const html = read('landing/index.html');
  assert.ok((html.match(/<section\b/g) || []).length <= 5);
});

test('non-decorative landing type never drops below 12px', () => {
  const css = read('landing/style.css');
  assert.doesNotMatch(css, /font-size:\s*(?:8|9|10|11)px/);
});
```

- [ ] **Step 2: Verify tests fail while existing funnel tests stay green**

Run: `node --test test/landing/accessibility-layout.test.js test/landing/integration.test.js test/landing/final-review-contract.test.js`

Expected: new tests FAIL; existing contracts PASS.

- [ ] **Step 3: Consolidate the landing narrative**

Retain hero/application, recommendation proof, how it works, trust/privacy, and final CTA. Merge secondary proof into disclosures or concise evidence rows. Keep all required legal links, form IDs/names, analytics hooks, attribution, screenshots, natural aspect ratios, and illustrative labels.

- [ ] **Step 4: Implement accessibility and reduced motion**

Raise copy to the typography floor, enforce 44 px controls, improve focus visibility, and stop automatic scenario transitions under `prefers-reduced-motion: reduce` while leaving tabs manually operable.

- [ ] **Step 5: Run the complete landing suite**

Run: `node --test test/landing/*.test.js`

Expected: PASS with waitlist, analytics, OAuth, SEO, and no-JS contracts unchanged.

- [ ] **Step 6: Commit**

```bash
git add landing/index.html landing/style.css landing/script.js test/landing
git commit -m "feat: shorten and clarify the landing journey"
```

### Task 9: Utility, legal, trust, and 404 composition

**Files:**
- Modify: `landing/resources.css`
- Modify: `landing/tools/best-card/index.html`
- Modify: `landing/tools/milestone-tracker/index.html`
- Modify: `landing/tools/movie-offers/index.html`
- Modify: `landing/privacy/index.html`
- Modify: `landing/data-security/index.html`
- Modify: `landing/terms/index.html`
- Modify: `landing/recommendation-disclaimer/index.html`
- Modify: `landing/404.html`
- Test: `test/landing/utility-pages.test.js`
- Test: `test/landing/legal-seo-pages.test.js`
- Create: `test/landing/public-reading-layout.test.js`

**Interfaces:**
- Consumes: existing utility input/result IDs and `landing/tools/tools.js` calculation functions unchanged.
- Produces: action-first utility templates, readable legal template, and two-exit 404.

- [ ] **Step 1: Write failing content-order and readability tests**

```js
test('utility form appears before long-form methodology', () => {
  for (const page of utilityPages) {
    const html = read(page);
    assert.ok(html.indexOf('<form') < html.indexOf('Methodology'));
  }
});

test('404 offers home and sign-in exits', () => {
  const html = read('landing/404.html');
  assert.match(html, /href="\/"/);
  assert.match(html, /href="\/login"/);
});
```

- [ ] **Step 2: Verify focused tests fail**

Run: `node --test test/landing/utility-pages.test.js test/landing/legal-seo-pages.test.js test/landing/public-reading-layout.test.js`

Expected: FAIL for ordering, typography, local contents, or 404 exits.

- [ ] **Step 3: Move utilities to action-first composition**

Place calculator form/result preview in the desktop first viewport and immediately after one short intro on mobile. Preserve all element IDs, field names, client-side calculations, structured data, canonical metadata, and waitlist links.

- [ ] **Step 4: Improve legal/trust readability and 404 recovery**

Use 15–16 px body text, a 65–75 character measure, a desktop sticky contents list/mobile disclosure, and scan-friendly last-updated/data/retention/contact blocks. Add Home and Sign in buttons to 404.

- [ ] **Step 5: Run all public tests**

Run: `node --test test/landing/*.test.js test/gtm/*.test.js test/brand/*.test.js`

Expected: PASS with SEO/privacy claims unchanged.

- [ ] **Step 6: Commit**

```bash
git add landing/resources.css landing/tools landing/privacy landing/data-security landing/terms landing/recommendation-disclaimer landing/404.html test/landing
git commit -m "feat: improve public utility and trust pages"
```

### Task 10: Whole-application verification and localhost review

**Files:**
- Modify only failing files already owned by Tasks 1–9.
- Create: `docs/ui-ux-qa-verification-2026-08-16.md`

**Interfaces:**
- Consumes: all Wave 1 and Wave 2 deliverables.
- Produces: verification evidence and a localhost build ready for user review.

- [ ] **Step 1: Run format, analysis, and full automated tests**

Run:

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
node --test test/landing/*.test.js test/gtm/*.test.js test/brand/*.test.js test/supabase/*.test.js
git diff --check
```

Expected: all tests pass; any pre-existing analyzer exclusions are documented rather than silently ignored.

- [ ] **Step 2: Build the production-shape Flutter web app**

Run: `flutter build web --release --base-href /app/`

Expected: exit 0 and `build/web/index.html` references `/app/` correctly.

- [ ] **Step 3: Start the existing localhost server and inspect every public route**

Test `/`, three `/tools/**` routes, four legal/trust routes, `/404.html`, `/login`, and `/app/#/login` at 390×844 and 1440×900. Verify keyboard focus, 200% text, reduced motion, no horizontal overflow, links, calculator controls, waitlist transitions, and OAuth entry URL.

- [ ] **Step 4: Inspect authenticated routes with seeded states**

Use test fixtures or a local seeded account to inspect Dashboard, Cards, Add Card, Card Detail, Transactions, Movies/results, and Settings with populated, empty, loading, error, long-name, unsupported, and 200%-scale states. Do not use production credentials or transmit user data.

- [ ] **Step 5: Record concise verification evidence**

Create a table containing route/screen, viewport, state, keyboard, text scaling, overflow, interaction result, and screenshot filename. Record any limitation explicitly.

- [ ] **Step 6: Run a final changed-file and unrelated-work audit**

Run:

```bash
git status --short
git diff --name-only HEAD~9..HEAD
git diff --check
```

Expected: Gmail-sync files remain unstaged/uncommitted and no out-of-scope backend files changed.

- [ ] **Step 7: Commit verification evidence**

```bash
git add docs/ui-ux-qa-verification-2026-08-16.md
git commit -m "docs: record ui ux remediation verification"
```

- [ ] **Step 8: Present localhost for user acceptance**

Keep the landing page and `/app/#/login` open for review. Do not deploy, merge, or push until the user explicitly requests it.
