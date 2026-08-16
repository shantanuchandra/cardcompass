# CardCompass UI/UX QA Remediation Design

**Date:** 16 August 2026

**Status:** Approved for planning

**Source audit:** `docs/ui-ux-qa-2026-08-16.md`

## Objective

Bring the approved editorial CardCompass identity to release quality across the public website and Flutter application. The work must improve accessibility, interaction integrity, responsive hierarchy, and page consistency without changing authentication, recommendation calculations, statement processing, or persisted user data.

## Product principles

1. Every page has one unmistakable primary task.
2. Evidence supports a decision instead of competing with it.
3. Ink frames navigation and marketing; Paper supports focused work; Ledger marks calculated or recommended outcomes; Signal marks primary action; Reward marks realized or potential value.
4. Visible interactive affordances must work. Unavailable functionality is either clearly labelled or absent.
5. Text remains readable at browser and operating-system scaling up to 200%.
6. Mobile layout follows reading order and may stack content instead of preserving desktop rows.

## Wave 1 — Foundation and core product

### Typography and accessibility

- Bundle Manrope, Fraunces, and IBM Plex Mono as local Flutter assets with declared weights.
- Remove the fixed `TextScaler.linear(1.0)` override and respect the user’s scale preference.
- Use 12 logical pixels as the minimum non-decorative text size. Body and actionable copy use at least 14 logical pixels.
- Preserve a minimum 44×44 logical-pixel interactive target.
- Maintain visible keyboard focus and semantic labels for navigation, buttons, inputs, dialogs, filters, and expandable evidence.
- At 200% text scale, content may reflow or scroll but must not clip, overlap, or become unreachable.

### Theme architecture

- Replace the single contradictory dark `ThemeData` with two semantic contexts:
  - `AppTheme.work`: light Material scheme for authenticated Paper surfaces.
  - `AppTheme.marketing`: dark Material scheme for login, splash, and Ink surfaces.
- Preserve the approved brand tokens and issuer colors.
- Theme controls, dialogs, snackbars, sheets, focus rings, and system overlays according to their actual surface.
- Do not introduce gradients, glow, excessive shadows, or large-radius generic SaaS cards.

### Shared components

Create focused reusable components rather than a general widget framework:

- `BrandPageHeader`: title, optional eyebrow, explanation, and one action.
- `BrandSurface`: Paper/Ledger surface with semantic border and density variants.
- `BrandMetric`: one primary metric or compact supporting metric.
- `BrandActionRow`: working navigation/action row with optional unavailable state.
- `BrandStateView`: standardized loading, empty, error, and recovery states.
- `BrandEvidence`: source, verification date, cap, rule, or calculation explanation.
- `ResponsiveValueRow`: stacks when text scale or width makes a row unsafe.

Shared components own typography, target size, surface semantics, and responsive behavior. Pages own domain copy and data.

### Navigation and interaction integrity

- Use the same language across public and authenticated surfaces: `Dashboard`, `Cards`, `Transactions`, `Movies`, and `Settings`.
- Keep five desktop rail destinations. On mobile, use concise labels and preserve accessible names.
- Dashboard `View all` actions navigate to the corresponding destination.
- Settings destinations must work where a destination already exists. Functionality not implemented in this cycle uses a clearly disabled `Coming soon` treatment without a chevron.
- Add working external routes for Privacy, Data & Security, Terms, Help/contact, and About/version information.
- Preserve the current Google OAuth implementation and redirect behavior.

### Page contracts

#### Login and splash

- Keep the approved left-side login card and landing-matched rotating recommendation proof on the right.
- Google sign-in remains the sole primary action.
- Increase evidence/legal text to the typography floor and simplify nonessential receipt rows.
- Show sign-in progress and failure inside the login card without layout movement.
- Splash/auth callback exposes meaningful progress stages and a timed recovery action.

#### Dashboard

- First viewport order: greeting/context, primary recommendation or next action, primary spend metric, supporting rewards/limit metrics.
- Supporting KPIs stack or scroll safely on narrow widths and at enlarged text scale.
- Cards, bills, and recent transactions remain subordinate sections with working destinations.
- Empty data emphasizes the next setup action rather than zero-valued KPI cards.

#### Cards and add card

- Card list prioritizes card identity, issuer, last-four where available, and sync/status; credit limit is secondary.
- Use catalogue/issuer visual identity where safely available, with a deterministic monogram fallback.
- Add-card flow exposes `1 Search` and `2 Confirm` progress.
- Explain why last four and cardholder name are optional, validate last four inline, and preserve search state when returning to step one.

#### Card detail

- Header summarizes card identity, current statement state, and one primary action.
- Order content as: best uses, milestone progress, current bill, rewards/fees, statement/transaction history.
- Secondary detail uses tabs or disclosure sections; collapsed content remains accessible to keyboard and assistive technology.

#### Transactions

- Spend is the primary metric; rewards and top category are supporting metrics.
- Filters open in a responsive sheet/dialog and summarize their active state in one control.
- Transaction rows prioritize merchant, amount, card, date, and category; secondary metadata does not force dense multi-line rows.
- Never display raw exception text. Errors explain what failed and offer retry or support.

#### Movie optimizer and results

- Replace technical language with plain questions: ticket count, price per ticket, booking platform, and cinema.
- Fields stack on narrow widths and remain paired only when width and text scale permit.
- The result begins with one recommended route, expected saving, effective ticket price, and a plain-language reason.
- Alternatives use a compact comparison table/list. Caps, eligibility, and calculation detail sit behind `Why this?` or `Show calculation`.

#### Settings

- Group account, communications, data/privacy, support, and application information.
- Show the actual state of notification controls; do not use navigable styling for unavailable features.
- Provide working Privacy, Data & Security, Terms, About/version, and sign-out actions.
- Data export/deletion may be a labelled support/contact route if self-service backend capability does not exist; it must not imply an unavailable automated operation.

### State system

Every data-backed page defines:

- initial loading with stable layout;
- empty state with one primary setup action;
- recoverable error with human-readable message and retry;
- unavailable/unsupported state distinct from technical failure;
- success feedback for mutations without exposing internal identifiers.

## Wave 2 — Public experience

### Landing page

- Preserve the approved 1440-pixel maximum layout, three-line hero, waitlist flow, recommendation rotation, trust language, and illustrative labels.
- Reduce the core narrative to: hero/application, recommendation proof, how it works, trust/privacy, and final waitlist CTA.
- Combine or progressively disclose secondary proof so the mobile page is materially shorter than the current approximately 7,500-pixel composition.
- Do not remove indexable product copy, legal links, attribution capture, or analytics safeguards.
- Preserve natural image aspect ratios and no-crop presentation.

### Utility pages

- Move the first calculator inputs and/or a result preview into the initial desktop viewport.
- On mobile, place the calculator immediately after one short introductory paragraph.
- Lead results with the decision/value; place methodology, assumptions, and FAQs after it.
- Preserve client-only calculation behavior, attribution, structured data, canonical metadata, and waitlist entry points.

### Legal and trust pages

- Raise body copy to 15–16 CSS pixels with a 65–75 character reading measure.
- Add a local contents navigator on long pages; it may become a compact disclosure on mobile.
- Make last-updated, data-category, retention, deletion, and contact information easy to scan.
- Copy must remain reconciled with implemented data flows and deployment gates.

### Public shared states

- 404 exposes Home and Sign in as obvious exits.
- Waitlist errors retain entered email locally, explain the next step, and never leak server details.
- Reduced-motion mode disables automatic transitions while preserving manual controls.

## Responsive model

| Range | Behavior |
|---|---|
| `< 600` | Single reading column; fields and metrics stack; bottom navigation; disclosures compact |
| `600–1023` | One or two columns based on content measure; no forced three-up financial metrics |
| `≥ 1024` | Persistent app rail; split views where tasks benefit; content still uses readable maximum measures |
| `≥ 1440` | Extra width becomes gutters or supporting context, never excessively long text lines |

Responsiveness uses both available width and effective text scale. A desktop-width viewport at 200% scale may choose a narrower composition.

Authenticated data-heavy surfaces may offer a full-width presentation when horizontal space materially improves comparison, charts, tables, or multi-card scanning. Reading, form, legal, and recommendation-explanation content keeps a readable maximum measure inside that full-width shell. Full-width behavior must be automatic where clearly beneficial or exposed through one persistent user control; it must never stretch prose indiscriminately.

## Error handling and content rules

- User-facing errors state the problem, consequence, and next action.
- Raw exceptions, backend table names, provider payloads, and stack traces are never rendered.
- Financial values use Indian number formatting consistently.
- Recommendation language distinguishes live data, estimated value, illustrative examples, and unavailable rules.
- Public and authenticated terminology must match.

## Testing and verification

### Automated

- Theme tests verify local font declarations, correct light/dark schemes, and absence of a fixed text scaler.
- Widget tests cover 390-, 768-, and 1280-pixel widths and 1.0/1.5/2.0 text scales for shared components and core screens.
- Interaction tests assert that every visible Dashboard and Settings action either works or is explicitly disabled.
- State tests cover loading, empty, error, unsupported, and populated views.
- Landing tests verify retained metadata/analytics/privacy contracts and reduced-motion behavior.

### Browser and visual

- Inspect all public routes at mobile and desktop sizes.
- Inspect authenticated routes with a seeded account containing long names, multiple cards, statements, transactions, missing data, and unsupported rules.
- Verify keyboard-only navigation, focus visibility, screen-reader labels, no horizontal overflow, no clipped 200% text, and safe-area behavior.
- Verify OAuth entry and callback without altering the approved flow.

### Regression gates

- Existing Flutter unit/widget tests pass.
- Existing landing/Node tests pass.
- Flutter web release build succeeds for `/app/`.
- No unrelated Gmail-sync files are modified or committed.

## Delivery and review

1. Implement Wave 1 foundation and core screens.
2. Implement Wave 2 public pages.
3. Run automated and browser verification across both waves.
4. Present the complete localhost experience for user review.
5. Commit product changes only after approval; deployment remains a separate explicit action.

## Out of scope

- Authentication provider or OAuth-flow redesign.
- Recommendation, reward, milestone, or movie-offer calculation changes.
- Database schema, statement-processing, Gmail-sync, or retention changes.
- New notification backend, self-service deletion backend, or support-ticket system.
- Paid plans, acquisition campaigns, or production deployment.
