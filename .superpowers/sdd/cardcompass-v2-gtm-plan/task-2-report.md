# Task 2 report — landing experience and qualified waitlist funnel

## Delivered

- Rebuilt `landing/index.html` and `landing/style.css` around the locked thesis,
  palette, typography, split hero, receipt/ledger signature, alternating evidence
  bands, and Founding 100 application.
- Used `app-dashboard.png` and `app-recommendations.png` as current product
  captures. The interactive decision receipt is repeatedly and explicitly
  labelled illustrative, including its source and disclaimer.
- Replaced direct waitlist-table writes with the exact two-step RPC flow:
  `join_waitlist` returns the one-time enrichment token and
  `enrich_waitlist` submits the required card-count, spend-band, and goal fields.
- Added optional name, problem detail, marketing consent, and a keyboard-usable
  two-card catalog autocomplete. `landing/card-catalog.json` contains 178 rows
  derived from the `card_catalog` COPY seed in
  `20260711043900_restore_reference_data.sql`.
- Added durable first-touch UTM/referrer-path/landing-variant capture in local
  storage with server-compatible length and slug validation.
- Added cookie-free Plausible events through a strict event-name and property
  allowlist. Event payloads cannot include email, name, qualification answers,
  card names, problem detail, or UTM values.
- Added visible focus states, semantic landmarks, live errors/status, native
  labels, keyboard autocomplete controls, mobile layouts without horizontal
  overflow, and reduced-motion behavior.
- Added the required privacy, terms, data-security, and recommendation-disclaimer
  destinations to the footer and consent copy without creating those pages.

## TDD record

- Red: `node --test test/landing/*.test.js` first failed because the new helper
  module did not exist. An importable throwing shell was added, and the second
  red run produced 13 expected `waitlist helper is not implemented` failures.
- Green: implemented the pure helpers in `landing/waitlist.js`; all 13 tests
  passed. Tests cover exact RPC payloads, enum/limit validation, token response
  validation, first-touch persistence, attribution sanitisation, analytics
  privacy, and catalog search/exclusion/limits.

## Verification

- `node --test test/landing/*.test.js`: 13 passed, 0 failed.
- `node --check landing/waitlist.js` and `node --check landing/script.js`: passed.
- Catalog verification: 178 complete `id`/`bank`/`card_name` rows.
- `git diff --check` across owned implementation/test files: passed.
- In-app browser checks at desktop and a 390 px mobile override: rendered
  correctly, mobile had no horizontal overflow, empty-submit errors were
  announced, and receipt scenario/value updates worked.
- Browser console: no application errors; Plausible emitted only its expected
  warning that it ignores localhost.

## Commit

- `a25b6b3` — `feat: rebuild qualified landing waitlist`

## Concerns / limitations

- The browser smoke test did not send either public RPC because the local dev
  server had no configured post-migration Supabase environment. The browser
  correctly showed the unavailable-state path; payload and response contracts
  are covered by the browser-independent tests.
- The two required existing screenshot files have `.png` names but JPEG file
  contents. They render in the tested browser; they were preserved unchanged as
  required.
