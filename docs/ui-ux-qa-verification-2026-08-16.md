# UI/UX remediation verification — 16 August 2026

## Outcome

**Status: conditional local-review build; not release-ready.** The final review's six Important findings, three minor evidence/copy gaps, and both async navigation review rounds are repaired in five implementation commits:

- `4aea3d6 fix: make add card navigation race safe`
- `629af63 fix: enforce accessible controls and type floors`
- `adc4ba5 fix: complete recoverable loading and empty states`
- `cee8ab0 fix: close async navigation races`
- `fix: reconcile async mutations outside disposable UI` (architectural follow-up)

These commits keep OAuth, calculator/evaluator behavior, provider calculations, waitlist, Gmail/backend, and schema contracts intact. No deployment, push, or merge was performed.

Branch-owned gates are green: all changed Dart files format cleanly and analyze without a new finding; the 322-test non-Supabase Flutter suite, 145-test focused final-review fixture suite, static Supabase Node contracts, 96-test landing/GTM/brand Node suite, full-cycle rendered public-page keyboard regression, release build, and changed-file audit pass.

Release-blocking gates remain unmet outside Task 10's authorized scope:

- The controller baseline rules that the 11 Supabase failures are environment-bound, predate the UI work, and cannot become green in this local environment without PostgREST, platform storage/PKCE support, and valid local credentials. Full `flutter test` green is therefore impossible locally.
- Repository-wide formatting and analysis retain pre-existing, out-of-scope debt (48 formatter rewrites and 36 analyzer findings). Those files were not changed.
- Live authenticated-route acceptance cannot be performed without a configured local Supabase instance and seeded account.
- Public-page browser text at 200% and live Flutter-app keyboard/reduced-motion behavior remain **NOT VERIFIED**. Exact manual follow-up is recorded below; public HTML keyboard traversal itself is now verified through every focus stop.

Accordingly, plan Step 1 did **not** fully pass. The successful branch-owned checks are evidence for this UI branch only; they are not a release waiver for the unmet gates.

## Automated verification

| Check | Result |
|---|---|
| Changed Dart files through `dart format` | 0 changes after formatting. Repository-wide formatting remains the recorded pre-existing limitation because it would rewrite unrelated Gmail/backend/Supabase files. |
| `flutter analyze` | Baseline limitation unchanged: 36 existing findings (3 warnings, 33 infos), all outside the final-fix implementation/test set. Repeated analysis of the owned product/test files reported `No issues found`. |
| `flutter test` | **Not green:** 323 passed, 4 skipped, 11 failed. All 11 remaining failures are the recorded environment-bound Supabase cases: the local static endpoint is not PostgREST and VM storage/PKCE plugins or live credentials are unavailable. No UI test remains failed. |
| `flutter test test/core test/features test/shared test/widget_test.dart` | 322 passed, 0 failed. |
| Focused final-review Flutter selection (theme, auth, dashboard, cards, transactions, movie deals, settings) | 145 passed, 0 failed. |
| `node --test test/landing/*.test.js test/gtm/*.test.js test/brand/*.test.js` | 96 passed, 0 failed, including every-stop rendered Chrome focus/reduced-motion/viewport-overflow regression. |
| `node --test test/supabase/*_test.js` | 8 static Supabase migration-contract tests passed, 0 failed across `card_data_hardening_migration_test.js` and `waitlist_launch_hardening_test.js`. |
| Brief's exact Node command ending in `test/supabase/*.test.js` | Does not start in zsh: that glob has no match. The two existing Supabase Node files end in `_test.js`, not `.test.js`. The two successful commands above are the exact replacements. |
| `node --test test/landing/public-reading-browser.test.js` | 1 rendered Chrome test passed: 9 public HTML routes × 390/1440, a complete real-Tab cycle through every browser focus stop with each stop visible and visibly focused, and `document.documentElement.scrollWidth === window.innerWidth`; reduced-motion behavior also remains green at both viewports. |
| Chrome-target OAuth tests | 4 passed. `app_shell_brand_test.dart` still cannot load on Chrome because the test itself reads source with `dart:io File` (`Unsupported operation: _Namespace`); its VM run passes in the 322-test suite. |
| `npm run build:app` | Not runnable locally because ignored `dart_defines.json` is intentionally absent. No secret or production define file was created. |
| `flutter build web --release --base-href /app/` | Exit 0. `build/web/index.html` contains `<base href="/app/">` and no unexpected root-relative app asset reference. |
| `git diff --check` | Clean before and after the repair. |

The verified release build used no define file and succeeds; its runtime environment validator intentionally stops before `runApp` when required public Supabase and Google compile-time values are absent. The earlier screenshot artifacts used non-secret loopback placeholders only. No production credential or user data was used, and this final fix wave did not create the ignored `dart_defines.json` file.

## Public route evidence

Screenshots are stored as ignored review artifacts under `.superpowers/sdd/2026-08-16-ui-ux-qa-remediation/task-10-evidence/`. DOM viewport measurements are authoritative: the in-app screenshot exporter applies the host's 1.1 device scale again and writes a narrower physical bitmap, while `innerWidth` and `scrollWidth` were measured at the requested CSS viewport.

| Route | Viewport | State | Keyboard | Text scaling / motion | Overflow | Interaction result | Screenshot |
|---|---:|---|---|---|---|---|---|
| `/` | 390×844 | default | live Chrome: complete focus cycle; every stop visible with indicator | reduced motion live at 390: auto-rotation static beyond 4s, manual Dining selection works, receipt/button transition durations 0.01ms; 200% text: **NOT VERIFIED** | automated none (`390/390`) | Waitlist rejects blank email/consent, then reports configuration unavailable for synthetic valid data without transmission | `home-390x844.png` |
| `/` | 1440×900 | default | live Chrome: complete focus cycle; every stop visible with indicator | reduced motion live at 1440: auto-rotation static beyond 4s, manual Dining selection works, receipt/button transition durations 0.01ms; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | Scenario controls and waitlist contracts pass | `home-1440x900.png` |
| `/tools/best-card/` | 390×844 | default inputs | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | `3% card` leads at ₹120 vs capped ₹100 | `best-card-390x844.png` |
| `/tools/best-card/` | 1440×900 | default inputs | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `best-card-1440x900.png` |
| `/tools/milestone-tracker/` | 390×844 | default inputs | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | projected gap ₹20,000; daily pace ₹1,428.57 | `milestone-tracker-390x844.png` |
| `/tools/milestone-tracker/` | 1440×900 | default inputs | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `milestone-tracker-1440x900.png` |
| `/tools/movie-offers/` | 390×844 | default BOGO | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | estimated saving ₹300; payable ₹670 | `movie-offers-390x844.png` |
| `/tools/movie-offers/` | 1440×900 | default BOGO | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `movie-offers-1440x900.png` |
| `/data-security/` | 390×844 | long table/code | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none after repair (`390/390`); table retains internal auto-scroll | all internal anchors present | `data-security-390x844.png` |
| `/data-security/` | 1440×900 | desktop reading layout | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `data-security-1440x900.png` |
| `/privacy/` | 390×844 | long legal content | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none after repair (`390/390`) | all internal anchors present | `privacy-390x844.png` |
| `/privacy/` | 1440×900 | desktop reading layout | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `privacy-1440x900.png` |
| `/terms/` | 390×844 | mobile legal | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | all internal anchors present | `terms-390x844.png` |
| `/terms/` | 1440×900 | desktop legal | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `terms-1440x900.png` |
| `/recommendation-disclaimer/` | 390×844 | mobile legal | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | all internal anchors present | `recommendation-disclaimer-390x844.png` |
| `/recommendation-disclaimer/` | 1440×900 | desktop legal | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `recommendation-disclaimer-1440x900.png` |
| `/404.html` | 390×844 | not found | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`390/390`) | home and sign-in exits resolve | `404-390x844.png` |
| `/404.html` | 1440×900 | not found | live Chrome Tab traversal and visible focus pass | reduced-motion media/root behavior live; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | home and sign-in exits resolve | `404-1440x900.png` |
| `/login` | 390×844 | redirect | **NOT VERIFIED live**; widget semantics cover Google/legal actions | **NOT VERIFIED live**; reduced-motion widget tests only | measured none (`390/390`) | 302 to `/app/#/login` | `login-redirect-390x844-seeded.png` |
| `/login` | 1440×900 | redirect | **NOT VERIFIED live**; widget semantics cover Google/legal actions | **NOT VERIFIED live**; reduced-motion widget tests only | measured none (`1440/1440`) | 302 to `/app/#/login` | `login-redirect-1440x900-seeded.png` |
| `/app/#/login` | 390×844 | loopback-seeded public config | **NOT VERIFIED live**; fixture verifies single-fire/disabled/loading and legal actions | **NOT VERIFIED live**; fixture covers reduced motion and mobile layout | measured none (`390/390`) | local OAuth callback contract is `http://localhost:4174/app/`; external flow not launched against fake Supabase | `app-login-390x844-seeded.png` |
| `/app/#/login` | 1440×900 | loopback-seeded public config | **NOT VERIFIED live**; fixture evidence only | **NOT VERIFIED live**; fixture evidence only | measured none (`1440/1440`) | production callback contract remains `https://cardcompass.in/app/` | `app-login-1440x900-seeded.png` |

All required local route requests returned 200 except `/login`, which returned the expected 302. A crawl of public internal `href` targets found no broken local target.

## Authenticated and seeded widget states

Live authenticated browsing was not attempted because no local Supabase instance or seeded account was available, and production credentials/user data were explicitly out of scope. The accepted screens were inspected through deterministic widget/provider fixtures.

The final focused selection was expanded with the theme contracts and add-card route integration test and exited 0 with 145 passed. Its core feature list remains:

```bash
flutter test --reporter compact \
  test/core/theme/app_theme_test.dart \
  test/core/theme/brand_components_test.dart \
  test/core/theme/typography_floor_contract_test.dart \
  test/features/auth/login_screen_test.dart \
  test/features/dashboard/dashboard_brand_test.dart \
  test/features/dashboard/dashboard_responsive_test.dart \
  test/features/cards/cards_brand_test.dart \
  test/features/cards/add_card_ux_test.dart \
  test/features/cards/card_detail_ux_test.dart \
  test/features/cards/cards_add_route_test.dart \
  test/features/transactions/transactions_brand_test.dart \
  test/features/transactions/transactions_state_test.dart \
  test/features/transactions/transactions_ux_test.dart \
  test/features/benefits/movie_deals/movie_deals_brand_test.dart \
  test/features/benefits/movie_deals/movie_deals_results_test.dart \
  test/features/benefits/movie_deals/movie_deals_ux_test.dart \
  test/features/settings/settings_brand_test.dart
```

This table maps the requested screen/state evidence to the named tests; a missing state is explicitly not treated as covered.

| Screen | Requested fixture states and named tests | Evidence status | Screenshot |
|---|---|---|---|
| Login / splash | desktop/default and mobile layout; status: `status space is reserved and the proof heading never scales down text`; controls: `scenario and legal actions keep 44px targets and selected semantics`; signing-in/error and splash recovery; reduced motion | fixture pass, including reserved idle/loading/error space and 200% layout | N/A — widget fixture; no rendered screenshot of each state |
| Dashboard | populated hierarchy/scale, cardless, redacted dashboard/Gmail errors, actions; card control: `dashboard card is a labeled keyboard-sized button`; bank resolution covers redacted retry, Cancel/modal-barrier/Back dismissal, dismissed failure/retry, and two activations before rebuild | populated, empty, errors, actions, bank/card controls, retry, dismissal-race invalidation, zero invalidation on failure, synchronous exactly-once resolution, and 200% fixture pass; loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Cards | populated/long-name/200%, redacted error, loading: `card loading reserves a stable skeleton slot`; empty/back/save/refresh: `cards_add_route_test.dart` covers empty and populated lists | populated, empty, loading, error, route return, and immediate refresh fixture pass | N/A — widget fixture; no live-auth browser screenshot |
| Add Card | progress/validation/error/200%; keyboard result target; out-of-order search, short-query clear, dispose, save-dispose, and pop-failure race tests; route integration covers immediate app-bar and system Back during stalled saves, eventual reconciliation, reopen deduplication, and dismissed failure/retry | listed initial, loading, error, async-race, keyboard, usable Back during save, route-independent persistence/refresh, app-wide exactly-once insert, retry, and 200% states pass | N/A — widget fixture; no live-auth browser screenshot |
| Card Detail | populated/action order, long-name/200%, bill/history, redacted error; `detail loading reserves space and a missing card offers exit` | populated, not-found action, loading, error, and 200% fixture pass | N/A — widget fixture; no live-auth browser screenshot |
| Transactions | populated metric, nine long-name/scale cases, filters/keyboard/geometry/semantics, expanded/reordered with transaction B reintroduced, redacted error; `ledger loading reserves a stable skeleton slot`; `ledger distinguishes dataset-empty from filtered-empty` | populated, data-empty, filtered-empty/action, loading, error, expanded-state, keyboard, and 200% fixture pass | N/A — widget fixture; no live-auth browser screenshot |
| Movie form / results | form/result scale matrix, eligible/potential/unknown/no-deal/error; precise platform-only vs capped-usage uncertainty; `movie search loading reserves a stable result slot` | populated, empty/no-deal, loading, error, precise potential evidence, and 200% fixture pass | N/A — widget fixture; no live-auth browser screenshot |
| Settings | enabled actions and unsupported Notifications row: `every enabled settings row has an action`; routes/version: `settings actions use the public routes and version dialog` | default and unsupported fixture pass; 200% and loading/error **NOT VERIFIED** (loading/error are not represented states in this static screen) | N/A — widget fixture; no live-auth browser screenshot |

## Accessibility limitations

- The local headless-Chrome/CDP regression dispatches real Tab key events on all nine public HTML routes at 390×844 and 1440×900 until focus completes a full cycle. It asserts every actual browser focus stop is onscreen, visibly focused, and does not repeat before returning to the first stop. This is live rendered-browser evidence for the public HTML routes only; `/login` and the Flutter `/app/#/login` remain **NOT VERIFIED** for live keyboard traversal.
- The same rendered test emulates `prefers-reduced-motion: reduce` and asserts the media query matches and the computed root scroll behavior becomes `auto` on every public HTML route at both viewports. At both 390×844 and 1440×900 on the landing page, it also observes the active scenario for 4.25 seconds (longer than the 4-second rotation interval), verifies Groceries remains selected, dispatches a real pointer click to Dining and verifies the receipt updates, and checks representative computed receipt/button transition durations are 0.01ms. No reveal-animation suppression is claimed because the normal UI defines no reveal animation. Flutter reduced motion remains fixture-only (`disableAnimations` tests), not live-browser verified.
- Public-page text at 200% remains **NOT VERIFIED**. CDP page scale/device scale is not equivalent to browser text zoom, and the in-app browser ignored zoom shortcuts. Manual follow-up: in a normal Chrome profile, set page zoom to 200%, revisit all nine public HTML routes at 390×844 and 1440×900, operate every calculator/waitlist control, record screenshots, and confirm `document.documentElement.scrollWidth === window.innerWidth` except intentional internal table scrolling.
- Live Flutter-app follow-up: start a real local Supabase/PostgREST stack with a seeded non-production account and valid public compile-time values; at both viewports, Tab through `/app/#/login` and each authenticated screen, repeat at 200% text/page zoom, then enable OS/browser reduced motion and confirm animation changes. Record populated, empty, loading, error, long-name, and unsupported screenshots. Until then, those checks remain fixture-only or **NOT VERIFIED** as mapped above.
- Screenshot exports are affected by the host device-scale issue described above. DOM width measurements and Flutter test constraints were used for pass/fail decisions.

## Changed-file and unrelated-work audit

- `git diff --check` is clean for both the working diff and `c06b94a..HEAD`.
- The final fix wave changes only router/theme, auth/cards/dashboard/transactions/movie UI, public resource CSS, verification documentation, and their tests.
- No OAuth callback, calculator/evaluator arithmetic, provider calculation, waitlist, Gmail/backend, schema, Supabase migration, credential, or production-data file was changed.

## Historical local acceptance references

No review server was started or left running by the final fix wave. The earlier evidence screenshots used these local references:

Primary pages:

- Landing: `http://localhost:4174/`
- Login: `http://localhost:4174/app/#/login`

The earlier server used the ignored loopback-seeded build described above and was not a deployment artifact.
