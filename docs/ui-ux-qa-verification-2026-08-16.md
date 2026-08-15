# UI/UX remediation verification — 16 August 2026

## Outcome

The Task 1–9 UI remediation is ready for localhost acceptance with one Task 9 repair committed during whole-application QA:

- `0f99d31 fix: prevent legal page mobile overflow`
- `/data-security/` and `/privacy/` originally expanded past 390 CSS px because the mobile grid used an intrinsic `1fr` track; Data Security also contained an unbreakable inline migration filename.
- The repair uses `minmax(0, 1fr)` for the mobile content track and allows inline legal-page code to wrap. A red/green regression contract was added before the production change.

No deployment, push, or merge was performed.

## Automated verification

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed lib test` | Baseline limitation: would rewrite 48 files outside Tasks 1–9, including Gmail/backend and Supabase tests. Those mechanical changes were restored. The 34 Task 1–9 Dart files pass the formatter with 0 changes. |
| `flutter analyze` | Baseline limitation: 36 existing findings (3 warnings, 33 infos), all outside the Task 1–9 changed-file set. No new UI-remediation analyzer finding. |
| `flutter test` | 289 passed, 4 skipped, 11 failed. All 11 failures are the documented environment-bound Supabase suite: the local static endpoint is not PostgREST and VM storage/PKCE plugins or live credentials are unavailable. |
| `flutter test test/core test/features test/shared test/widget_test.dart` | 288 passed, 0 failed. |
| Seeded UI fixture selection (auth, dashboard, cards, transactions, movie deals, settings) | 92 passed, 0 failed. |
| `node --test test/landing/*.test.js test/gtm/*.test.js test/brand/*.test.js` | 93 passed, 0 failed after the mobile-overflow regression tests. |
| Planned Node command including `test/supabase/*.test.js` | Harness limitation: no files match that stale glob; Supabase integration tests in this repository are Dart files. |
| Chrome-target OAuth tests | 4 passed. `app_shell_brand_test.dart` cannot load on Chrome because the test itself reads source with `dart:io File` (`Unsupported operation: _Namespace`); its VM run passes in the 288-test suite. |
| `flutter build web --release --base-href /app/` | Exit 0. `build/web/index.html` contains `<base href="/app/">` and no unexpected root-relative app asset reference. |
| `git diff --check` | Clean before and after the repair. |

The exact no-define release build intentionally stops before `runApp` when required public Supabase and Google compile-time values are absent. For localhost visual review only, the ignored build artifact was rebuilt with non-secret loopback placeholders (`http://127.0.0.1:54321`, a fake public key, and a fake client ID). No production credential or user data was used.

## Public route evidence

Screenshots are stored as ignored review artifacts under `.superpowers/sdd/2026-08-16-ui-ux-qa-remediation/task-10-evidence/`. DOM viewport measurements are authoritative: the in-app screenshot exporter applies the host's 1.1 device scale again and writes a narrower physical bitmap, while `innerWidth` and `scrollWidth` were measured at the requested CSS viewport.

| Route | Viewport | State | Keyboard | Text scaling / motion | Overflow | Interaction result | Screenshot |
|---|---:|---|---|---|---|---|---|
| `/` | 390×844 | default | Static skip-link/focus contracts pass; live Tab dispatch unavailable in browser harness | 200% browser zoom unavailable; reduced-motion CSS and rotation tests pass | none (`390/390`) | Waitlist rejects blank email/consent, then reports configuration unavailable for synthetic valid data without transmission | `home-390x844.png` |
| `/` | 1440×900 | default | same limitation | same automated coverage | none (`1440/1440`) | Scenario controls and waitlist contracts pass | `home-1440x900.png` |
| `/tools/best-card/` | 390×844 | default inputs | focusable controls exposed | CSS type-floor tests | none (`390/390`) | `3% card` leads at ₹120 vs capped ₹100 | `best-card-390x844.png` |
| `/tools/best-card/` | 1440×900 | default inputs | focusable controls exposed | CSS type-floor tests | none (`1440/1440`) | same result | `best-card-1440x900.png` |
| `/tools/milestone-tracker/` | 390×844 | default inputs | focusable controls exposed | CSS type-floor tests | none (`390/390`) | projected gap ₹20,000; daily pace ₹1,428.57 | `milestone-tracker-390x844.png` |
| `/tools/milestone-tracker/` | 1440×900 | default inputs | focusable controls exposed | CSS type-floor tests | none (`1440/1440`) | same result | `milestone-tracker-1440x900.png` |
| `/tools/movie-offers/` | 390×844 | default BOGO | focusable controls exposed | CSS type-floor tests | none (`390/390`) | estimated saving ₹300; payable ₹670 | `movie-offers-390x844.png` |
| `/tools/movie-offers/` | 1440×900 | default BOGO | focusable controls exposed | CSS type-floor tests | none (`1440/1440`) | same result | `movie-offers-1440x900.png` |
| `/data-security/` | 390×844 | long table/code | mobile contents disclosure exposed | readable text contract | none after repair (`390/390`); table retains internal auto-scroll | all internal anchors present | `data-security-390x844.png` |
| `/data-security/` | 1440×900 | desktop reading layout | side navigation exposed | readable text contract | none (`1440/1440`) | all internal anchors present | `data-security-1440x900.png` |
| `/privacy/` | 390×844 | long legal content | mobile contents disclosure exposed | readable text contract | none after repair (`390/390`) | all internal anchors present | `privacy-390x844.png` |
| `/privacy/` | 1440×900 | desktop reading layout | side navigation exposed | readable text contract | none (`1440/1440`) | all internal anchors present | `privacy-1440x900.png` |
| `/terms/` | 390×844 | mobile legal | mobile contents disclosure exposed | readable text contract | none (`390/390`) | all internal anchors present | `terms-390x844.png` |
| `/terms/` | 1440×900 | desktop legal | side navigation exposed | readable text contract | none (`1440/1440`) | all internal anchors present | `terms-1440x900.png` |
| `/recommendation-disclaimer/` | 390×844 | mobile legal | mobile contents disclosure exposed | readable text contract | none (`390/390`) | all internal anchors present | `recommendation-disclaimer-390x844.png` |
| `/recommendation-disclaimer/` | 1440×900 | desktop legal | side navigation exposed | readable text contract | none (`1440/1440`) | all internal anchors present | `recommendation-disclaimer-1440x900.png` |
| `/404.html` | 390×844 | not found | two exits exposed | reduced-motion CSS present | none (`390/390`) | home and sign-in exits resolve | `404-390x844.png` |
| `/404.html` | 1440×900 | not found | two exits exposed | reduced-motion CSS present | none (`1440/1440`) | home and sign-in exits resolve | `404-1440x900.png` |
| `/login` | 390×844 | redirect | widget semantics cover Google/legal actions | reduced-motion widget tests | none (`390/390`) | 302 to `/app/#/login` | `login-redirect-390x844-seeded.png` |
| `/login` | 1440×900 | redirect | widget semantics cover Google/legal actions | reduced-motion widget tests | none (`1440/1440`) | 302 to `/app/#/login` | `login-redirect-1440x900-seeded.png` |
| `/app/#/login` | 390×844 | loopback-seeded public config | Google action fires once; disabled while loading; legal actions tested | reduced motion, loading, error, and mobile layout tested | none (`390/390`) | local OAuth callback contract is `http://localhost:4174/app/`; external flow not launched against fake Supabase | `app-login-390x844-seeded.png` |
| `/app/#/login` | 1440×900 | loopback-seeded public config | same | same | none (`1440/1440`) | production callback contract remains `https://cardcompass.in/app/` | `app-login-1440x900-seeded.png` |

All required local route requests returned 200 except `/login`, which returned the expected 302. A crawl of public internal `href` targets found no broken local target.

## Authenticated and seeded widget states

Live authenticated browsing was not attempted because no local Supabase instance or seeded account was available, and production credentials/user data were explicitly out of scope. The accepted screens were inspected through deterministic widget/provider fixtures.

| Screen | Viewports / states | Keyboard / action evidence | 200% / overflow evidence | Result | Screenshot |
|---|---|---|---|---|---|
| Login / splash | 390 mobile, 1440 desktop; default, signing-in, error, timeout, reduced motion | Google fires once and disables while loading; legal destinations and recovery actions work | mobile layout has no Flutter exception; motion timers stop | pass | seeded browser screenshots above |
| Dashboard | 390, 768, 1280 at 1×/2×; populated, cardless, repository error, Gmail error | Cards/Transactions actions select the correct tab; retries redact internals | hierarchy and metric stacking remain usable | pass | fixture-only; no live-auth screenshot |
| Cards | 390 at 2×; populated long-name and repository error; source inspection confirms empty and loading branches | retry action exposed; add/detail routes remain wired | complete card identity fits without Flutter exception | pass | fixture-only |
| Add Card | 390 at 2×; search, confirm, invalid last-four, catalogue error | progress and confirm controls work; error is actionable | confirm state has no Flutter exception | pass | fixture-only |
| Card Detail | 390 at 2×; populated long card/merchant names and repository error | decision action precedes disclosures; retry exposed | bill/history/action layout remains usable | pass | fixture-only |
| Transactions | 390, 768, 1280 at 1×/1.5×/2×; populated long merchant, filtered, expanded/reordered, repository error | mobile filter sheet, expansion identity, and recovery actions work | no Flutter exception across the matrix | pass | fixture-only |
| Movie form / results | 390, 768, 1280 at 1×/2×; eligible, potential, unknown platform, no-deal, unavailable/error | recommendation/retry actions and eligibility disclosures work | form and result remain usable; monthly caps remain visible at 390/2× | pass | fixture-only |
| Settings | default plus unsupported Notifications row | every enabled row has an action; public legal routes and version dialog work | shared responsive primitives cover scaling | pass | fixture-only |

## Accessibility limitations

- Live Tab key dispatch did not move focus in the in-app browser harness, even though focusable controls and skip links were exposed in the DOM. Keyboard behavior is therefore supported by static focus contracts and widget action tests, not claimed as a successful live-keyboard pass.
- Browser 200% zoom shortcuts were ignored by the in-app browser. Flutter 200% text scaling is covered by the seeded widget matrix; public pages are covered by responsive/type-floor contracts and exact viewport overflow measurements.
- Reduced-motion emulation was not exposed by the browser. The public CSS contains the reduced-motion override, the landing scenario rotation has a reduced-motion unit test, and Flutter login animation/scenario tests verify `disableAnimations` behavior.
- Screenshot exports are affected by the host device-scale issue described above. DOM width measurements and Flutter test constraints were used for pass/fail decisions.

## Changed-file and unrelated-work audit

- `git status --short` was clean before evidence creation.
- `git diff --check` was clean.
- `git diff --name-only HEAD~9..HEAD` contains only the expected recent Transactions, Movies, landing, utility/legal, 404, and related test files.
- Task 10's product repair touches only Task 9-owned `landing/resources.css` and `test/landing/public-reading-layout.test.js`.
- No Gmail-sync, backend, schema, Supabase migration, credential, or production-data file is staged or committed by Task 10.

## Local acceptance

Review server: `http://localhost:4174/`

Primary pages:

- Landing: `http://localhost:4174/`
- Login: `http://localhost:4174/app/#/login`

The server uses the ignored loopback-seeded build described above and is not a deployment artifact.
