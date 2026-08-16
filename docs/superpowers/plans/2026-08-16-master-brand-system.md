# CardCompass Master Brand System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the obsolete cyberpunk Flutter identity with the approved editorial Ink/Paper/Ledger master brand system and deliver a complete local preview of every product screen.

**Architecture:** A versioned token manifest is the cross-platform source of truth. Flutter semantic tokens and landing CSS variables mirror that manifest, while temporary legacy aliases preserve compilation during screen-by-screen migration. Shared Material themes land before feature screens; each screen migration receives focused widget, accessibility, and responsive verification before the legacy aliases are removed.

**Tech Stack:** Flutter 3 / Dart, Material 3, Riverpod, Google Fonts, HTML/CSS landing assets, Node test runner, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-08-16-master-brand-system-design.md`

## Global Constraints

- Rollback baseline is tag `v1_b4_redesign` at production commit `ff342c2`.
- Ink `#0B1015` is the master application background; Pure black and pure white are not page backgrounds.
- Signal `#3FE0D0` means action; Reward `#FFB547` means value; Ledger `#DDE7E1` means calculated or recommended; Error `#FF7163` means error or destructive action.
- Magenta and violet are permitted only inside the official compass mark.
- Manrope replaces Inter and Space Grotesk; Fraunces is reserved for important decisions and outcomes; IBM Plex Mono is used for amounts and evidence metadata.
- No neon glow, glassmorphism, general-purpose cyan–violet gradients, or looping decorative motion.
- Issuer and network colors remain factual identifiers.
- OAuth scopes, Supabase contracts, recommendation calculations, and persisted data behavior must not change.
- Each task follows strict RED → GREEN → REFACTOR and commits only its owned files.
- Existing unrelated worktree changes must be preserved.

---

### Task 1: Cross-platform brand token foundation

**Files:**
- Create: `assets/brand/cardcompass.tokens.json`
- Create: `lib/core/theme/brand_tokens.dart`
- Create: `landing/brand-tokens.css`
- Modify: `landing/style.css:1-24`
- Modify: `landing/resources.css:1-16`
- Test: `test/brand/brand_tokens.test.js`
- Test: `test/core/theme/brand_tokens_test.dart`

**Interfaces:**
- Produces: `BrandColors`, `BrandSpacing`, `BrandRadius`, `BrandMotion`, and canonical CSS custom properties.
- Consumes: exact primitive values and rules from the approved specification.

- [ ] **Step 1: Write the failing cross-platform token tests**

```js
test('landing tokens match the canonical manifest', () => {
  const manifest = JSON.parse(readFileSync('assets/brand/cardcompass.tokens.json'));
  const css = readFileSync('landing/brand-tokens.css', 'utf8');
  assert.match(css, new RegExp(`--brand-reward:\\s*${manifest.color.reward}`, 'i'));
  assert.doesNotMatch(css, /#00f5ff|#8b5cf6/i);
});
```

```dart
test('Flutter primitives match the approved brand values', () {
  expect(BrandColors.ink, const Color(0xFF0B1015));
  expect(BrandColors.reward, const Color(0xFFFFB547));
  expect(BrandRadius.control, 4);
  expect(BrandMotion.standard, const Duration(milliseconds: 180));
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `node --test test/brand/brand_tokens.test.js && flutter test test/core/theme/brand_tokens_test.dart`

Expected: FAIL because the token manifest, CSS, and Dart types do not exist.

- [ ] **Step 3: Implement the canonical manifest and mirrors**

Define primitive colors, semantic surface/content/action aliases, spacing `4/8/12/16/24/32/48/64`, radii `2/4/8/12/999`, and motion `120/180/240/1200ms`. Make `landing/style.css` and `landing/resources.css` import `brand-tokens.css` and remove duplicated root primitives.

- [ ] **Step 4: Run focused and landing suites**

Run: `node --test test/brand/brand_tokens.test.js test/landing/*.test.js && flutter test test/core/theme/brand_tokens_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/brand lib/core/theme/brand_tokens.dart landing/brand-tokens.css landing/style.css landing/resources.css test/brand test/core/theme/brand_tokens_test.dart
git commit -m "feat: establish editorial brand tokens"
```

### Task 2: Flutter theme and shared component states

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Create: `lib/core/theme/brand_components.dart`
- Test: `test/core/theme/app_theme_test.dart`
- Test: `test/core/theme/brand_components_test.dart`

**Interfaces:**
- Consumes: `BrandColors`, `BrandSpacing`, `BrandRadius`, `BrandMotion` from Task 1.
- Produces: `AppTheme.editorial`, compatibility `AppTheme.dark`, `BrandSurface`, `BrandSectionHeader`, `BrandEvidenceStrip`, and `BrandStatusChip`.

- [ ] **Step 1: Write failing theme behavior tests**

```dart
test('editorial theme assigns stable semantic control colors', () {
  final theme = AppTheme.editorial;
  expect(theme.scaffoldBackgroundColor, BrandColors.ink);
  expect(theme.colorScheme.primary, BrandColors.signal);
  expect(theme.cardTheme.color, BrandColors.paper);
  expect(theme.inputDecorationTheme.fillColor, BrandColors.white);
});
```

Add widget tests that assert primary, secondary, disabled, focus, error, and status components expose text plus non-color state cues and minimum 44px targets.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test test/core/theme/app_theme_test.dart test/core/theme/brand_components_test.dart`

Expected: FAIL because `AppTheme.editorial` and brand components do not exist.

- [ ] **Step 3: Implement the editorial Material theme**

Use Manrope for the base `TextTheme`, Fraunces only for explicit editorial helpers, and IBM Plex Mono for evidence helpers. Replace glow/gradient component defaults with rules, paper surfaces, 4px controls, and 8px cards. Keep legacy `AppColors` names as deprecated aliases mapped to semantic tokens so unmigrated screens compile.

- [ ] **Step 4: Implement shared components and rerun tests**

Run: `flutter test test/core/theme/app_theme_test.dart test/core/theme/brand_components_test.dart`

Expected: PASS with no overflow or semantics failures.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart lib/core/theme/brand_components.dart test/core/theme
git commit -m "feat: add editorial Flutter theme"
```

### Task 3: Finish authentication and official identity

**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `web/index.html`
- Modify: `web/manifest.json`
- Create: `assets/icons/cardcompass-mark.svg`
- Create: `web/icons/cardcompass-mark.svg`
- Test: `test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: editorial theme and shared tokens from Tasks 1–2.
- Preserves: `LoginView.onGoogleSignIn`, `LoginView.onOpenLegal`, and current Riverpod OAuth flow.
- Produces: animated vector header mark, Reward-highlighted `CardCompass` headline, folio sign-in surface, and functioning legal destinations.

- [ ] **Step 1: Add the failing headline and identity assertions**

```dart
testWidgets('login reserves reward color for the CardCompass word', (tester) async {
  await tester.pumpWidget(testLogin());
  final brand = tester.widget<Text>(find.text('CardCompass'));
  expect(brand.style?.color, BrandColors.reward);
  expect(find.byKey(const Key('cardcompass-mark')), findsOneWidget);
});
```

Retain the existing legal-destination, Google-loading, scenario rotation, reduced-motion, selection, and exact receipt-position tests.

- [ ] **Step 2: Run the login suite and verify RED**

Run: `flutter test test/features/auth/login_screen_test.dart`

Expected: FAIL because the headline is still a single warm-white text block.

- [ ] **Step 3: Implement tokenized rich headline and finalize identity assets**

Use `Text.rich`/`RichText` with the exact three-line structure; only the `CardCompass` span uses `BrandColors.reward`. Replace remaining login hardcoded colors with semantic tokens without changing geometry or OAuth callbacks.

- [ ] **Step 4: Verify login and web metadata**

Run: `flutter test test/features/auth/login_screen_test.dart && flutter analyze lib/features/auth/screens/login_screen.dart && python3 -m json.tool web/manifest.json >/dev/null`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/screens/login_screen.dart test/features/auth/login_screen_test.dart assets/icons web/icons web/index.html web/manifest.json pubspec.yaml pubspec.lock
git commit -m "feat: complete editorial authentication experience"
```

### Task 4: Application shell and navigation

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Test: `test/core/router/app_shell_brand_test.dart`

**Interfaces:**
- Consumes: `AppTheme.editorial` and semantic navigation tokens.
- Preserves: tab indices, `window.history.replaceState`, authentication redirects, and route paths.
- Produces: identical semantic states for desktop rail and mobile navigation.

- [ ] **Step 1: Write failing desktop/mobile navigation tests**

Build authenticated shell fixtures at 1280px and 390px. Assert Ink Soft navigation, Signal active destination, readable inactive state, 44px targets, and unchanged tab selection/history callbacks.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/core/router/app_shell_brand_test.dart`

Expected: FAIL on legacy cyan/neon surface values.

- [ ] **Step 3: Implement shell styling without routing changes**

Remove glow and pill styling. Apply Ink/Ink Soft surfaces, restrained rules, Manrope labels, and the official compass mark at the shell identity point.

- [ ] **Step 4: Verify routing and shell tests**

Run: `flutter test test/core/router/app_shell_brand_test.dart test/core/oauth_redirect_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/app_router.dart test/core/router/app_shell_brand_test.dart
git commit -m "feat: migrate application shell to editorial brand"
```

### Task 5: Dashboard wallet briefing

**Files:**
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart`
- Test: `test/features/dashboard/dashboard_brand_test.dart`

**Interfaces:**
- Consumes: `BrandSurface`, `BrandSectionHeader`, `BrandEvidenceStrip`, and dashboard providers unchanged.
- Produces: wallet briefing hierarchy for spend, rewards, milestones, and recommendations.

- [ ] **Step 1: Write failing dashboard hierarchy tests**

Create provider-backed fixtures for loading, populated, empty, and error states. Assert Paper work surfaces, Reward-only value emphasis, Ledger recommendation surface, actionable errors, and no gradient statistic cards.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/dashboard/dashboard_brand_test.dart`

Expected: FAIL on legacy gradient cards and typography.

- [ ] **Step 3: Implement the wallet briefing composition**

Keep provider reads and callbacks intact. Recompose existing information using the shared surface components; use Fraunces only for the main briefing/outcome, mono for values/dates, and Manrope elsewhere.

- [ ] **Step 4: Verify dashboard and provider behavior**

Run: `flutter test test/features/dashboard/dashboard_brand_test.dart test/features/dashboard 2>/dev/null || flutter test test/features/dashboard/dashboard_brand_test.dart`

Expected: PASS with desktop and mobile fixtures free of overflow.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/screens/dashboard_screen.dart test/features/dashboard/dashboard_brand_test.dart
git commit -m "feat: redesign dashboard as wallet briefing"
```

### Task 6: Wallet cards and card detail flows

**Files:**
- Modify: `lib/features/cards/screens/cards_screen.dart`
- Modify: `lib/features/cards/screens/card_detail_screen.dart`
- Modify: `lib/features/cards/screens/add_card_screen.dart`
- Test: `test/features/cards/cards_brand_test.dart`

**Interfaces:**
- Consumes: semantic surfaces, form theme, and factual issuer/network colors.
- Preserves: add, edit, delete, detail navigation, and repository callbacks.
- Produces: indexed wallet collection, neutral issuer cards, and paper detail/forms.

- [ ] **Step 1: Write failing wallet flow tests**

Exercise empty wallet, populated wallet, card detail, add form, validation, and destructive confirmation. Assert issuer color is limited to an identifying stripe and all actions remain reachable by keyboard/touch.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/cards/cards_brand_test.dart`

Expected: FAIL on full-card gradients, legacy radii, or missing semantic surfaces.

- [ ] **Step 3: Implement wallet collection and forms**

Replace decorative bank gradients in app UI with neutral Paper cards plus issuer stripe; do not alter factual bank-color lookup. Apply shared input, dialog, status, and evidence components.

- [ ] **Step 4: Verify card flows**

Run: `flutter test test/features/cards/cards_brand_test.dart && flutter analyze lib/features/cards`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cards test/features/cards/cards_brand_test.dart
git commit -m "feat: redesign wallet card flows"
```

### Task 7: Transaction ledger and spend evidence

**Files:**
- Modify: `lib/features/transactions/screens/transactions_screen.dart`
- Modify: `lib/features/transactions/widgets/spend_trend_panel.dart`
- Test: `test/features/transactions/transactions_brand_test.dart`

**Interfaces:**
- Consumes: transaction providers unchanged, ledger rules, mono amount styles, status components.
- Produces: scannable transaction ledger, filters, states, and evidence-oriented spend trend.

- [ ] **Step 1: Write failing ledger tests**

Cover loading, empty, populated, filtered, uncategorized, and error states. Assert aligned amounts/dates, rule-separated rows, text-plus-color status, and unchanged filter/provider callbacks.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/transactions/transactions_brand_test.dart test/features/transactions/transactions_state_test.dart`

Expected: FAIL on legacy floating-row presentation.

- [ ] **Step 3: Implement ledger-first transaction UI**

Use Paper/Ink hierarchy, mono numeric columns, Ledger for calculated categorization evidence, and Reward only for reward values.

- [ ] **Step 4: Verify transaction behavior**

Run: `flutter test test/features/transactions && flutter analyze lib/features/transactions`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions test/features/transactions
git commit -m "feat: migrate transactions to editorial ledger"
```

### Task 8: Movie offers and settings

**Files:**
- Modify: `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_brand_test.dart`
- Test: `test/features/settings/settings_brand_test.dart`

**Interfaces:**
- Consumes: existing movie-deal evaluation results and settings callbacks unchanged.
- Produces: evidence-led offer tickets and quiet privacy/account settings forms.

- [ ] **Step 1: Write failing movie and settings state tests**

For movies, cover eligible, ineligible, limit/cap, empty, and error states with source dates visible. For settings, cover data/privacy controls, destructive actions, loading, and keyboard order.

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_brand_test.dart test/features/settings/settings_brand_test.dart`

Expected: FAIL on legacy surfaces and component shapes.

- [ ] **Step 3: Implement both bounded screen migrations**

Use ticket/receipt styling only for genuine offer mechanics. Keep settings quiet and Paper-based; use Error only for destructive account/data actions.

- [ ] **Step 4: Run UI and domain regressions**

Run: `flutter test test/features/benefits/movie_deals test/features/settings/settings_brand_test.dart`

Expected: PASS; evaluator/repository outcomes remain unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/screens/movie_deals_screen.dart lib/features/settings/screens/settings_screen.dart test/features/benefits/movie_deals/movie_deals_brand_test.dart test/features/settings
git commit -m "feat: redesign offers and settings surfaces"
```

### Task 9: Remove legacy identity and replace design-system documentation

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Rewrite: `landing/design-system.html`
- Rewrite: `landing/design-system.css`
- Test: `test/brand/legacy_brand_audit.test.js`

**Interfaces:**
- Consumes: every migrated screen and canonical manifest.
- Produces: zero compatibility aliases, zero prohibited legacy UI accents, and current brand documentation.

- [ ] **Step 1: Write the failing legacy audit**

```js
test('product UI contains no legacy cyberpunk identity', () => {
  const dart = readProductDartSources();
  assert.doesNotMatch(dart, /neonGlow|cyanGradient|#00F5FF|#8B5CF6/i);
  assert.doesNotMatch(dart, /GoogleFonts\.(inter|spaceGrotesk)/);
});
```

Exclude the protected SVG mark from spectrum-color scanning.

- [ ] **Step 2: Run the audit and verify RED**

Run: `node --test test/brand/legacy_brand_audit.test.js`

Expected: FAIL with remaining aliases/usages.

- [ ] **Step 3: Remove compatibility aliases and rewrite documentation**

Delete obsolete neon helpers and aliases after all callers have migrated. Replace the cyberpunk design-system page with manifest-backed Ink/Paper/Ledger guidance, logo exception, components, accessibility, and examples.

- [ ] **Step 4: Run brand and landing suites**

Run: `node --test test/brand/*.test.js test/landing/*.test.js && flutter analyze`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart landing/design-system.html landing/design-system.css test/brand
git commit -m "docs: replace legacy brand system"
```

### Task 10: Full local acceptance and keep/revert checkpoint

**Files:**
- Modify only if verification exposes a failing requirement.
- Create: `docs/brand-redesign-verification.md`

**Interfaces:**
- Consumes: completed Tasks 1–9.
- Produces: evidence for the user's keep/revert decision; no deployment.

- [ ] **Step 1: Run automated verification**

Run:

```bash
node --test test/brand/*.test.js test/landing/*.test.js
flutter test test/core test/features/auth test/features/dashboard test/features/cards test/features/transactions test/features/benefits/movie_deals test/features/settings
flutter analyze
flutter build web --release --no-wasm-dry-run --base-href /app/ --dart-define-from-file=dart_defines.json
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 2: Run browser acceptance at desktop and mobile sizes**

At `http://localhost:8080/app/#/login`, verify login, legal destinations, OAuth initiation without completing an external account action, scenario rotation, reduced motion, and responsive layout. With a local authenticated fixture/session, verify dashboard, cards, transactions, movies, settings, keyboard order, focus visibility, errors, empties, and no horizontal overflow at 390px and 1440px.

- [ ] **Step 3: Validate brand invariants**

Confirm Reward is never a generic CTA, Signal always means action/selection, Ledger always means calculated/recommended, logo spectrum colors do not leak into UI, and issuer colors remain identifiers only.

- [ ] **Step 4: Record results and commit**

```bash
git add docs/brand-redesign-verification.md
git commit -m "test: record editorial redesign verification"
```

- [ ] **Step 5: User keep/revert gate**

Show the complete local application to the user. Do not merge or deploy. If approved, prepare the requested integration separately. If rejected, restore from `v1_b4_redesign` using a non-destructive branch or revert workflow that preserves the redesign commits for comparison.
