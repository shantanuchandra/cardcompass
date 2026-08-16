# UI/UX remediation verification — 16 August 2026

## Outcome

**Status: conditional local-review build; not release-ready.** The Task 1–9 UI remediation is available for localhost review with one Task 9 repair committed during whole-application QA:

- `0f99d31 fix: prevent legal page mobile overflow`
- `/data-security/` and `/privacy/` originally expanded past 390 CSS px because the mobile grid used an intrinsic `1fr` track; Data Security also contained an unbreakable inline migration filename.
- The repair uses `minmax(0, 1fr)` for the mobile content track and allows inline legal-page code to wrap. A red/green regression contract was added before the production change.

No deployment, push, or merge was performed.

Branch-owned gates are green: the 34 Task 1–9 Dart files format cleanly; the scoped non-Supabase Flutter suite, seeded UI fixtures, static Supabase Node contracts, landing/GTM/brand Node suites, rendered public-page browser regression, release build, route/link checks, and changed-file audit pass.

Release-blocking gates remain unmet outside Task 10's authorized scope:

- The controller baseline rules that the 11 Supabase failures are environment-bound, predate the UI work, and cannot become green in this local environment without PostgREST, platform storage/PKCE support, and valid local credentials. Full `flutter test` green is therefore impossible locally.
- Repository-wide formatting and analysis retain pre-existing, out-of-scope debt (48 formatter rewrites and 36 analyzer findings). Those files were not changed.
- Live authenticated-route acceptance cannot be performed without a configured local Supabase instance and seeded account.
- Public-page browser text at 200% and live Flutter-app keyboard/reduced-motion behavior are not faithfully emulatable with the available browser controls and remain **NOT VERIFIED**. Exact manual follow-up is recorded below.

Accordingly, plan Step 1 did **not** fully pass. The successful branch-owned checks are evidence for this UI branch only; they are not a release waiver for the unmet gates.

## Automated verification

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed lib test` | Baseline limitation: would rewrite 48 files outside Tasks 1–9, including Gmail/backend and Supabase tests. Those mechanical changes were restored. The 34 Task 1–9 Dart files pass the formatter with 0 changes. |
| `flutter analyze` | Baseline limitation: 36 existing findings (3 warnings, 33 infos), all outside the Task 1–9 changed-file set. No new UI-remediation analyzer finding. |
| `flutter test` | **Not green:** 289 passed, 4 skipped, 11 failed. Per the controller baseline ruling, all 11 are environment-bound Supabase failures that predate the UI work: the local static endpoint is not PostgREST and VM storage/PKCE plugins or live credentials are unavailable. Full green is impossible locally. |
| `flutter test test/core test/features test/shared test/widget_test.dart` | 288 passed, 0 failed. |
| Seeded UI fixture selection (auth, dashboard, cards, transactions, movie deals, settings) | 92 passed, 0 failed. |
| `node --test test/landing/*.test.js test/gtm/*.test.js test/brand/*.test.js` | 94 passed, 0 failed, including the rendered Chrome focus/reduced-motion/viewport-overflow regression. |
| `node --test test/supabase/*_test.js` | 8 static Supabase migration-contract tests passed, 0 failed across `card_data_hardening_migration_test.js` and `waitlist_launch_hardening_test.js`. |
| Brief's exact Node command ending in `test/supabase/*.test.js` | Does not start in zsh: that glob has no match. The two existing Supabase Node files end in `_test.js`, not `.test.js`. The two successful commands above are the exact replacements. |
| `node --test test/landing/public-reading-browser.test.js` | 1 rendered Chrome test passed: 9 public HTML routes × 390/1440, real Tab traversal with a visible focus indicator, reduced-motion media application, and `document.documentElement.scrollWidth === window.innerWidth`. |
| Chrome-target OAuth tests | 4 passed. `app_shell_brand_test.dart` cannot load on Chrome because the test itself reads source with `dart:io File` (`Unsupported operation: _Namespace`); its VM run passes in the 288-test suite. |
| `flutter build web --release --base-href /app/` | Exit 0. `build/web/index.html` contains `<base href="/app/">` and no unexpected root-relative app asset reference. |
| `git diff --check` | Clean before and after the repair. |

The exact no-define release build intentionally stops before `runApp` when required public Supabase and Google compile-time values are absent. For localhost visual review only, the ignored build artifact was rebuilt with non-secret loopback placeholders (`http://127.0.0.1:54321`, a fake public key, and a fake client ID). No production credential or user data was used.

## Public route evidence

Screenshots are stored as ignored review artifacts under `.superpowers/sdd/2026-08-16-ui-ux-qa-remediation/task-10-evidence/`. DOM viewport measurements are authoritative: the in-app screenshot exporter applies the host's 1.1 device scale again and writes a narrower physical bitmap, while `innerWidth` and `scrollWidth` were measured at the requested CSS viewport.

| Route | Viewport | State | Keyboard | Text scaling / motion | Overflow | Interaction result | Screenshot |
|---|---:|---|---|---|---|---|---|
| `/` | 390×844 | default | live Chrome: first and second Tab targets advanced; focused target visible with indicator | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | Waitlist rejects blank email/consent, then reports configuration unavailable for synthetic valid data without transmission | `home-390x844.png` |
| `/` | 1440×900 | default | live Chrome: first and second Tab targets advanced; focused target visible with indicator | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | Scenario controls and waitlist contracts pass | `home-1440x900.png` |
| `/tools/best-card/` | 390×844 | default inputs | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | `3% card` leads at ₹120 vs capped ₹100 | `best-card-390x844.png` |
| `/tools/best-card/` | 1440×900 | default inputs | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `best-card-1440x900.png` |
| `/tools/milestone-tracker/` | 390×844 | default inputs | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | projected gap ₹20,000; daily pace ₹1,428.57 | `milestone-tracker-390x844.png` |
| `/tools/milestone-tracker/` | 1440×900 | default inputs | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `milestone-tracker-1440x900.png` |
| `/tools/movie-offers/` | 390×844 | default BOGO | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | estimated saving ₹300; payable ₹670 | `movie-offers-390x844.png` |
| `/tools/movie-offers/` | 1440×900 | default BOGO | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | same result | `movie-offers-1440x900.png` |
| `/data-security/` | 390×844 | long table/code | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none after repair (`390/390`); table retains internal auto-scroll | all internal anchors present | `data-security-390x844.png` |
| `/data-security/` | 1440×900 | desktop reading layout | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `data-security-1440x900.png` |
| `/privacy/` | 390×844 | long legal content | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none after repair (`390/390`) | all internal anchors present | `privacy-390x844.png` |
| `/privacy/` | 1440×900 | desktop reading layout | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `privacy-1440x900.png` |
| `/terms/` | 390×844 | mobile legal | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | all internal anchors present | `terms-390x844.png` |
| `/terms/` | 1440×900 | desktop legal | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `terms-1440x900.png` |
| `/recommendation-disclaimer/` | 390×844 | mobile legal | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | all internal anchors present | `recommendation-disclaimer-390x844.png` |
| `/recommendation-disclaimer/` | 1440×900 | desktop legal | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | all internal anchors present | `recommendation-disclaimer-1440x900.png` |
| `/404.html` | 390×844 | not found | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`390/390`) | home and sign-in exits resolve | `404-390x844.png` |
| `/404.html` | 1440×900 | not found | live Chrome Tab traversal and visible focus pass | reduced motion: live pass; 200% text: **NOT VERIFIED** | automated none (`1440/1440`) | home and sign-in exits resolve | `404-1440x900.png` |
| `/login` | 390×844 | redirect | **NOT VERIFIED live**; widget semantics cover Google/legal actions | **NOT VERIFIED live**; reduced-motion widget tests only | measured none (`390/390`) | 302 to `/app/#/login` | `login-redirect-390x844-seeded.png` |
| `/login` | 1440×900 | redirect | **NOT VERIFIED live**; widget semantics cover Google/legal actions | **NOT VERIFIED live**; reduced-motion widget tests only | measured none (`1440/1440`) | 302 to `/app/#/login` | `login-redirect-1440x900-seeded.png` |
| `/app/#/login` | 390×844 | loopback-seeded public config | **NOT VERIFIED live**; fixture verifies single-fire/disabled/loading and legal actions | **NOT VERIFIED live**; fixture covers reduced motion and mobile layout | measured none (`390/390`) | local OAuth callback contract is `http://localhost:4174/app/`; external flow not launched against fake Supabase | `app-login-390x844-seeded.png` |
| `/app/#/login` | 1440×900 | loopback-seeded public config | **NOT VERIFIED live**; fixture evidence only | **NOT VERIFIED live**; fixture evidence only | measured none (`1440/1440`) | production callback contract remains `https://cardcompass.in/app/` | `app-login-1440x900-seeded.png` |

All required local route requests returned 200 except `/login`, which returned the expected 302. A crawl of public internal `href` targets found no broken local target.

## Authenticated and seeded widget states

Live authenticated browsing was not attempted because no local Supabase instance or seeded account was available, and production credentials/user data were explicitly out of scope. The accepted screens were inspected through deterministic widget/provider fixtures.

The exact 92-test command was:

```bash
flutter test --reporter json \
  test/features/auth/login_screen_test.dart \
  test/features/dashboard/dashboard_brand_test.dart \
  test/features/dashboard/dashboard_responsive_test.dart \
  test/features/cards/cards_brand_test.dart \
  test/features/cards/add_card_ux_test.dart \
  test/features/cards/card_detail_ux_test.dart \
  test/features/transactions/transactions_brand_test.dart \
  test/features/transactions/transactions_state_test.dart \
  test/features/transactions/transactions_ux_test.dart \
  test/features/benefits/movie_deals/movie_deals_brand_test.dart \
  test/features/benefits/movie_deals/movie_deals_results_test.dart \
  test/features/benefits/movie_deals/movie_deals_ux_test.dart \
  test/features/settings/settings_brand_test.dart
```

It exited 0 with 92 passed. This table maps the requested screen/state evidence to the named tests; a missing state is explicitly not treated as covered.

| Screen | Requested fixture states and named tests | Evidence status | Screenshot |
|---|---|---|---|
| Login / splash | desktop/default: `desktop login keeps authentication left of the product proof`; mobile: `mobile presents authentication before the recommendation proof`; loading: `Google action fires once and is disabled while loading`; signing-in/error: `login card exposes signing-in and failure feedback`; splash timeout/recovery: `splash communicates progress before exposing recovery actions`; reduced motion: `header compass animation becomes static with reduced motion` and `reduced motion leaves scenarios under manual control` | fixture pass | N/A — widget fixture; no rendered screenshot of each state |
| Dashboard | populated hierarchy/long scale matrix: `monthly spend is primary and supporting metrics stack at scale` and six `dashboard hierarchy remains usable at {390,768,1280}px / {1.0,2.0}×` cases; empty/cardless: `cardless dashboard focuses one setup action for Cards`; error: `dashboard failures redact internal details and offer Retry`; Gmail error: `Gmail sync failures never render internal exception text`; actions: `dashboard view-all actions select their destinations` and `primary recent-spending action selects Transactions` | populated, empty, error, actions, and 200% fixture pass; loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Cards | populated/long-name/200%: `card list shows a complete, readable identity at 200% scale`; error: `card load failures keep backend details private and offer retry` | populated, long-name, 200%, and error fixture pass; empty and loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Add Card | initial search/progress: `add card exposes search and confirm progress`; selected/confirm: `progress marks Confirm as the current step after selection`; invalid input: `last four explains optional use and rejects non-four digits` and `last four keeps blank and valid values clear, but marks invalid input inline`; error: `catalogue errors are actionable and do not expose internals`; 390/200%: `confirm step remains usable at 390px and 200% text scale` | listed fixture states pass; asynchronous loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Card Detail | populated/action order: `detail puts decisions before disclosures`; long-name/200%: `detail remains usable with long names at 200% scale`; 390/200% bill/history: `summary action, bill, and history work at 390px and 200% scale`; error: `detail errors redact backend details and provide retry` | populated, long-name, 200%, and error fixture pass; empty and loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Transactions | populated metric: `ledger makes spend the primary metric`; long-name/scale: nine `ledger keeps long merchant names usable at {390,768,1280}px and {1.0,1.5,2.0}x text` cases; filters: `filters open in a sheet on narrow screens` and two active-count scale tests; expanded/reordered: `reordered rows retain their own expanded details state`; error: `ledger redacts repository failures and offers recovery` | populated, long-name, filtered, expanded, error, and 200% fixture pass; empty and loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Movie form / results | form/scale: six `movie form keeps questions usable at {390,768,1280}px / {1.0,2.0}×` cases; populated result/scale: six `movie recommendation remains usable at ...` cases plus `result leads with recommendation and hides calculation detail`; eligible: `shows one best option when the same card wins both guaranteed pools`; potential: `falls back to a labeled potential candidate when no guaranteed winner exists` and `potential alternatives are explicitly separated from eligible options`; unknown platform: `result is honest when an eligible booking platform is unknown`; empty/no-deal: `shows a no-deal message when neither tier has a winner`; unavailable/error: `shows a retryable unavailable message on repository failure`; 390/200% cap disclosure: `potential routes are never presented as verified and disclose monthly caps at 390px / 2x` | populated, empty/no-deal, error, potential, unknown, and 200% fixture pass; loading **NOT VERIFIED** | N/A — widget fixture; no live-auth browser screenshot |
| Settings | enabled actions and unsupported Notifications row: `every enabled settings row has an action`; routes/version: `settings actions use the public routes and version dialog` | default and unsupported fixture pass; 200% and loading/error **NOT VERIFIED** (loading/error are not represented states in this static screen) | N/A — widget fixture; no live-auth browser screenshot |

## Accessibility limitations

- A new local headless-Chrome/CDP regression now dispatches real Tab key events on all nine public HTML routes at 390×844 and 1440×900. It asserts that first and second focus targets advance, the focused target is onscreen, and the computed focus indicator is visible. This is live rendered-browser evidence for the public HTML routes only; `/login` and the Flutter `/app/#/login` remain **NOT VERIFIED** for live keyboard traversal.
- The same rendered test emulates `prefers-reduced-motion: reduce` and asserts the media query matches and the computed root scroll behavior becomes `auto` on every public HTML route at both viewports. Flutter reduced motion remains fixture-only (`disableAnimations` tests), not live-browser verified.
- Public-page text at 200% remains **NOT VERIFIED**. CDP page scale/device scale is not equivalent to browser text zoom, and the in-app browser ignored zoom shortcuts. Manual follow-up: in a normal Chrome profile, set page zoom to 200%, revisit all nine public HTML routes at 390×844 and 1440×900, operate every calculator/waitlist control, record screenshots, and confirm `document.documentElement.scrollWidth === window.innerWidth` except intentional internal table scrolling.
- Live Flutter-app follow-up: start a real local Supabase/PostgREST stack with a seeded non-production account and valid public compile-time values; at both viewports, Tab through `/app/#/login` and each authenticated screen, repeat at 200% text/page zoom, then enable OS/browser reduced motion and confirm animation changes. Record populated, empty, loading, error, long-name, and unsupported screenshots. Until then, those checks remain fixture-only or **NOT VERIFIED** as mapped above.
- Screenshot exports are affected by the host device-scale issue described above. DOM width measurements and Flutter test constraints were used for pass/fail decisions.

## Changed-file and unrelated-work audit

- `git status --short` was clean before evidence creation.
- `git diff --check` was clean.
- `git diff --name-only HEAD~9..HEAD` contains only the expected recent Transactions, Movies, landing, utility/legal, 404, and related test files.
- Task 10's product repair touches only Task 9-owned `landing/resources.css` and `test/landing/public-reading-layout.test.js`; review round 1 adds the Task 9 verification harness `test/landing/public-reading-browser.test.js`.
- No Gmail-sync, backend, schema, Supabase migration, credential, or production-data file is staged or committed by Task 10.

## Local acceptance

Review server: `http://localhost:4174/`

Primary pages:

- Landing: `http://localhost:4174/`
- Login: `http://localhost:4174/app/#/login`

The server uses the ignored loopback-seeded build described above and is not a deployment artifact.
