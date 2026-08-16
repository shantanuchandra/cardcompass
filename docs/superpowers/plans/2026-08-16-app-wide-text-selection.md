# App-Wide Text Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all text on every page of the CardCompass Flutter app selectable, by wrapping the app once at its root instead of per-screen.

**Architecture:** One `SelectionArea` around the router's `child` in `CardCompassApp.build`'s `builder` (`lib/app.dart`) makes every screen's text selectable. The two existing narrower `SelectionArea`s (in `BrandSectionHeader` and the login screen) are removed so they don't silo their own text into a disconnected selectable island once nested inside the new root wrap.

**Tech Stack:** Flutter (`package:flutter/material.dart`'s `SelectionArea`), existing `flutter_test` static source-assertion convention (see `test/core/router/app_shell_brand_test.dart`).

**Spec:** `docs/superpowers/specs/2026-08-16-app-wide-text-selection-design.md`

**Note on testing approach:** The spec's testing section described "pumping `CardCompassApp`" — but `test/core/router/app_shell_brand_test.dart` (the file it names to extend) doesn't pump widgets at all; it reads source files as strings and asserts on their content (`File(...).readAsStringSync()` + `expect(source, contains(...))`). This plan follows that actual, established, working convention instead — it verifies the same thing (SelectionArea exists in exactly one place) without needing to mock Supabase auth/Riverpod state to render the full app tree.

---

### Task 1: Add the app-root `SelectionArea` wrap

**Files:**
- Modify: `lib/app.dart`
- Test: `test/core/router/app_shell_brand_test.dart`

- [x] **Step 1: Write the failing test**

Replace the full contents of `test/core/router/app_shell_brand_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/core/router/app_router.dart').readAsStringSync();
  final appSource = File('lib/app.dart').readAsStringSync();

  test('desktop and mobile navigation use semantic brand roles', () {
    expect(source, contains('BrandColors.inkSoft'));
    expect(source, contains('BrandColors.signal'));
    expect(source, contains('BrandColors.mutedPaper'));
    expect(source, isNot(contains('AppColors.neonCyan')));
  });

  test('shell identity uses the shared compass mark', () {
    expect(source, contains('BrandCompassMark'));
  });

  test('navigation keeps existing routing behavior and accessible targets', () {
    expect(
      source,
      contains("window.history.replaceState(null, '', '#\${_kTabPaths[i]}')"),
    );
    expect(source, contains('height: 68'));
    expect(source, contains('Semantics('));
  });

  test('app root wraps every screen in a single SelectionArea', () {
    expect(appSource, contains('SelectionArea('));
  });
}
```

This adds one new test (`app root wraps every screen in a single SelectionArea`) reading `lib/app.dart` — a second source file alongside the existing `app_router.dart` check — and keeps all three pre-existing tests unchanged.

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/router/app_shell_brand_test.dart`
Expected: 3 tests pass, 1 fails — `app root wraps every screen in a single SelectionArea` fails because `lib/app.dart` doesn't contain `SelectionArea` yet.

- [x] **Step 3: Implement the minimal change**

In `lib/app.dart`, the current `builder` callback is:

```dart
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
```

Replace it with:

```dart
      builder: (context, child) => SelectionArea(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        ),
      ),
```

No new import is needed — `lib/app.dart` already imports `package:flutter/material.dart`, which exports `SelectionArea`.

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/router/app_shell_brand_test.dart`
Expected: PASS (4 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/app.dart test/core/router/app_shell_brand_test.dart
git commit -m "feat: make all app text selectable via a root SelectionArea"
```

---

### Task 2: Remove the two now-redundant nested `SelectionArea`s

**Files:**
- Modify: `lib/core/theme/brand_components.dart:115-163` (`BrandSectionHeader.build`)
- Modify: `lib/features/auth/screens/login_screen.dart:106-180` (`LoginView.build`)
- Test: `test/core/router/app_shell_brand_test.dart`

- [x] **Step 1: Write the failing tests**

In `test/core/router/app_shell_brand_test.dart`, add two more file reads and two more tests. The file should now read:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/core/router/app_router.dart').readAsStringSync();
  final appSource = File('lib/app.dart').readAsStringSync();
  final brandComponentsSource = File(
    'lib/core/theme/brand_components.dart',
  ).readAsStringSync();
  final loginScreenSource = File(
    'lib/features/auth/screens/login_screen.dart',
  ).readAsStringSync();

  test('desktop and mobile navigation use semantic brand roles', () {
    expect(source, contains('BrandColors.inkSoft'));
    expect(source, contains('BrandColors.signal'));
    expect(source, contains('BrandColors.mutedPaper'));
    expect(source, isNot(contains('AppColors.neonCyan')));
  });

  test('shell identity uses the shared compass mark', () {
    expect(source, contains('BrandCompassMark'));
  });

  test('navigation keeps existing routing behavior and accessible targets', () {
    expect(
      source,
      contains("window.history.replaceState(null, '', '#\${_kTabPaths[i]}')"),
    );
    expect(source, contains('height: 68'));
    expect(source, contains('Semantics('));
  });

  test('app root wraps every screen in a single SelectionArea', () {
    expect(appSource, contains('SelectionArea('));
  });

  test('BrandSectionHeader does not nest its own SelectionArea', () {
    expect(brandComponentsSource, isNot(contains('SelectionArea(')));
  });

  test('login screen does not nest its own SelectionArea', () {
    expect(loginScreenSource, isNot(contains('SelectionArea(')));
  });
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/router/app_shell_brand_test.dart`
Expected: 4 tests pass, 2 fail — `BrandSectionHeader does not nest its own SelectionArea` and `login screen does not nest its own SelectionArea` both fail, because both files still contain `SelectionArea(` from before this task's changes.

- [x] **Step 3: Remove `SelectionArea` from `BrandSectionHeader`**

In `lib/core/theme/brand_components.dart`, the current method (lines 114-164) is:

```dart
  @override
  Widget build(BuildContext context) => SelectionArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: BrandColors.mutedInk,
          ),
        ),
        const SizedBox(height: BrandSpacing.sm),
        Text(
          title,
          style: editorial
              ? TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.08,
                  color: BrandColors.ink,
                )
              : TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: BrandColors.ink,
                ),
        ),
        if (description != null) ...[
          const SizedBox(height: BrandSpacing.sm),
          Text(
            description!,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1.5,
              color: BrandColors.mutedInk,
            ),
          ),
        ],
      ],
    ),
  );
}
```

Change only the opening and closing lines — the `Column(...)` and everything inside it is untouched:
- Replace `Widget build(BuildContext context) => SelectionArea(\n    child: Column(` with `Widget build(BuildContext context) => Column(`
- Replace the closing `    ),\n  );\n}` (which closes `Column`, then `SelectionArea`, ending the statement) with `  );\n}` (just `Column`'s own closing)

- [x] **Step 4: Remove `SelectionArea` from the login screen**

In `lib/features/auth/screens/login_screen.dart`, `LoginView.build`'s `Stack` currently has (lines 103-181):

```dart
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SelectionArea(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  ...
                },
              ),
            ),
          ),
        ],
      ),
```

Change only the `SelectionArea`/`SafeArea` boundary — everything inside `LayoutBuilder` is untouched:
- Replace `          SelectionArea(\n            child: SafeArea(` with `          SafeArea(`
- Replace the closing `            ),\n          ),\n        ],` (which closes `SafeArea`, then `SelectionArea`, then the `Stack`'s `children` list) with `          ),\n        ],` (just `SafeArea`'s own closing, then the list close)

- [x] **Step 5: Reformat both files**

The body content in both files is now under-indented by one level (2 spaces) relative to standard Dart style, since it used to sit inside a `child:` parameter. Fix this mechanically rather than by hand:

Run: `dart format lib/core/theme/brand_components.dart lib/features/auth/screens/login_screen.dart`
Expected: Both files reported as formatted (or already-formatted if the tool settles them silently).

- [x] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/router/app_shell_brand_test.dart`
Expected: PASS (6 tests, 0 failures)

- [x] **Step 7: Run the full test suite and analyzer**

Run: `flutter test`
Expected: Same pass count as the pre-existing baseline, no new failures (the known `test/supabase/*` failures against local Supabase are pre-existing and unrelated — see `[[project-no-docker-environment]]`).

Run: `flutter analyze lib test/core test/features`
Expected: `No issues found!`

- [x] **Step 8: Commit**

```bash
git add lib/core/theme/brand_components.dart lib/features/auth/screens/login_screen.dart test/core/router/app_shell_brand_test.dart
git commit -m "refactor: remove now-redundant nested SelectionAreas"
```

---

## Self-Review

**Spec coverage:**
- Root wrap in `lib/app.dart` → Task 1. ✓
- Remove `BrandSectionHeader`'s `SelectionArea` → Task 2, Step 3. ✓
- Remove login screen's `SelectionArea` → Task 2, Step 4. ✓
- Selection applies to all text uniformly (no exclusions) → satisfied by construction: a single root `SelectionArea` with no exclusion logic added anywhere. ✓
- Selection color stays default → no `textSelectionTheme` change appears anywhere in this plan. ✓
- Testing → Task 1 Step 1 and Task 2 Step 1, using the corrected (actual, established) static-source-assertion convention. ✓
- Out of scope items (highlight color, non-text content) → correctly absent from every task. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete, exact code; no "similar to Task N" shorthand.

**Type/consistency check:** Both tasks use the same file (`test/core/router/app_shell_brand_test.dart`) and Task 2's full-file replacement is a strict superset of Task 1's — same `source`/`appSource` variable names carried through, same test names for the pre-existing three cases, so nothing drifts between tasks.

---

## Execution Record

Both tasks were implemented via subagent-driven development (fresh implementer subagent per task, followed by independent spec-compliance and code-quality review subagents for each) in the `worktree-app-wide-text-selection` worktree branch:

- Task 1: commit `b76636a` — reviewed, spec compliant, code quality approved (no issues).
- Task 2: commit `2015798` — reviewed, spec compliant (including judging that two additional test-file fixes, in `test/core/theme/brand_components_test.dart` and `test/features/auth/login_screen_test.dart`, were a necessary consequence of the removal rather than scope creep), code quality approved (no issues).
- Final holistic review across both commits combined: approved with minor, non-blocking notes (durability of the static-source test approach against a hypothetical future screen adding its own `SelectionArea`; this documentation-commit reconciliation, addressed here).
