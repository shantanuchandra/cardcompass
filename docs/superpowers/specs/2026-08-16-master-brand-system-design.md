# CardCompass Master Brand System Design

**Status:** Approved design, pending implementation plan

**Date:** 16 August 2026

**Rollback tag:** `v1_b4_redesign` at production commit `ff342c2`

## Purpose

Make the editorial v2 landing-page identity the master visual system for the CardCompass Flutter application. The redesign must make calculations, recommendation evidence, and user controls easier to understand while removing the obsolete neon/cyberpunk language.

The landing page is the visual source of truth. The Flutter application translates its ink, paper, ledger, receipt, and verification vocabulary into durable semantic tokens and shared components.

## Goals

- Present one recognizable CardCompass identity across landing, authentication, and the signed-in product.
- Use surface, typography, and rules to communicate information hierarchy.
- Reserve color for stable meaning: cyan for action, yellow for value, ledger green for calculated recommendations, and coral for errors.
- Keep dense financial information scannable and accessible on desktop and mobile.
- Migrate incrementally without changing authentication, data contracts, recommendation calculations, or Supabase behavior.
- Preserve a tested rollback path to `v1_b4_redesign`.

## Non-goals

- Changing OAuth scopes or callback behavior.
- Changing Supabase schemas, RPCs, or security policies.
- Rewriting recommendation, milestone, transaction, or movie-offer business logic.
- Replacing factual issuer and network colors.
- Introducing a permanent legacy/cyberpunk theme.

## Design principles

1. **Show the working.** Recommendations pair the answer with the inputs, rule source, caveats, and verification date.
2. **Structure before decoration.** Surfaces, rules, spacing, and typography establish hierarchy before color or motion.
3. **Color has one job.** A token keeps the same meaning everywhere.
4. **Editorial, not ornamental.** Fraunces marks important decisions and outcomes; it is not a generic heading font.
5. **Motion explains state.** Movement indicates selection, update, navigation, or progress. It does not create ambient spectacle.

## Color system

### Primitive tokens

| Token | Value | Purpose |
|---|---:|---|
| `ink` | `#0B1015` | Master application background and verification surfaces |
| `inkSoft` | `#172027` | Raised dark navigation and panels |
| `paper` | `#F4F0E6` | Primary cards, forms, and working surfaces |
| `paperDeep` | `#E9E3D5` | Secondary and disabled paper surfaces |
| `ledger` | `#DDE7E1` | Recommendations and calculated outcomes |
| `signal` | `#3FE0D0` | Primary actions, active navigation, selection, and progress |
| `reward` | `#FFB547` | Savings, milestones, rewards, and selective brand emphasis |
| `error` | `#FF7163` | Errors and destructive actions |
| `white` | `#FFFDF7` | Maximum-contrast inputs and paper highlights |
| `mutedInk` | `#465159` | Secondary text on light surfaces |
| `mutedPaper` | `#9CA9A8` | Secondary text on dark surfaces |
| `focusDark` | `#006D64` | Focus indication on light surfaces |

### Semantic rules

- The application canvas is Ink. Pure black and pure white are not page backgrounds.
- Ink Soft provides structural elevation for navigation and dark panels.
- Paper carries work: forms, details, explanations, and records.
- Ledger identifies a calculated recommendation or selected evidence. It is not a generic card fill.
- Signal cyan means action or active state.
- Reward yellow means value. It is never the default CTA color.
- Coral means an error, invalid state, or destructive action.
- Issuer and network colors are factual identifiers and do not replace brand tokens.
- Magenta and violet are permitted only inside the official compass mark.
- Neon glow, glassmorphism, and general-purpose cyan–violet gradients are prohibited.

### Background hierarchy

```text
Ink application canvas
├── Ink Soft navigation and structural panels
├── Paper cards, forms, and detail views
├── Ledger recommendation and calculation surfaces
└── Ink verification and evidence strips
```

A subtle cyan grid may appear only on large orientation surfaces such as authentication, selected dashboard headers, and empty states. It must not sit behind dense data.

## Typography

### Families

- **Fraunces:** recommendations, major outcomes, milestone moments, and editorial introductions.
- **Manrope:** navigation, controls, forms, tables, body copy, and everyday headings.
- **IBM Plex Mono:** money, dates, sources, caps, status labels, and verification metadata.

### Rules

- Manrope replaces Inter and Space Grotesk across the application.
- Fraunces communicates a decision or meaningful outcome, not every heading.
- Monetary values use IBM Plex Mono with tabular figures.
- Uppercase mono labels remain small, purposeful, and legible.
- Headings use controlled negative tracking; body copy prioritizes readability.
- On the login headline, “CardCompass” uses Reward yellow while the surrounding words use Paper.

## Shape, border, and elevation

### Radius scale

- `2px`: receipt tags and evidence labels.
- `4px`: buttons, inputs, tabs, and compact chips.
- `8px`: standard cards and form panels.
- `12px`: dialogs, sheets, and large overlays.
- Full pill: compact status indicators only.

### Elevation rules

- Use borders, rules, and surface contrast before shadows.
- Standard cards receive a restrained neutral ink shadow.
- Featured financial outcomes may use the landing receipt’s yellow offset shadow.
- Dialogs use a larger neutral shadow and an explicit border.
- Glow and translucent glass elevation are prohibited.

## Motion

| Duration | Use |
|---:|---|
| `120ms` | Selection, receipt update, immediate state feedback |
| `180ms` | Hover, focus, and button response |
| `240ms` | Panels, sheets, and navigation transitions |
| `1200ms` | One-time compass entrance only |

- Recommendations update like a new receipt being issued.
- Ledger rows may reveal in reading order.
- Progress moves only when its value changes.
- Decorative motion does not loop.
- The authentication scenario preview may rotate because it demonstrates product behavior; hover, focus, and reduced-motion preferences pause it.
- Reduced motion removes transformations and auto-rotation while preserving understandable state changes.

## Logo system

- The official compass mark contains the protected magenta–violet–cyan spectrum.
- UI components must not borrow those spectrum colors.
- The login header uses a one-time vector compass animation with a static reduced-motion fallback.
- Browser, manifest, and product iconography use the SVG master or approved raster exports.
- Wordmarks maintain clear space and must not be placed inside unrelated decorative containers.

## Shared component behavior

### Application shell

- Ink canvas with Ink Soft navigation.
- Active destination uses Signal with Ink content.
- Desktop rail and mobile navigation expose the same states and labels.

### Buttons

- Primary: Signal background with Ink content.
- Secondary: transparent or Paper with an explicit rule.
- Destructive: Error only when the action is destructive.
- Loading preserves control dimensions and replaces the action label.

### Cards and panels

- Standard: Paper and Ink.
- Recommendation: Ledger with calculation and source attached.
- Evidence: Ink with Paper copy and Signal metadata.
- Reward outcome: Paper or Ledger with a Reward value.
- Issuer card: neutral structure plus a restrained factual issuer-color identifier.

### Inputs

- White or Paper fill, Ink content, and a 4px radius.
- Labels sit above controls.
- Focus uses Focus Dark plus a contrasting outer ring.
- Errors state what happened and how to correct it.
- Disabled states do not rely on opacity alone.

### Transactions and tables

- Use ledger rules rather than individually floating rounded rows.
- Dates, amounts, and categories align consistently.
- Reward values use Reward on dark surfaces and an accessible darker reward ink on light surfaces.
- Dense information uses Manrope and IBM Plex Mono only.

### Status and feedback

- Status uses text, icon, and color together.
- Snackbars resemble compact evidence strips.
- Empty states explain the next useful action.
- Loading uses restrained skeletons or progress indicators without neon shimmer.

## Screen migration

1. **Authentication:** finish the Reward headline, folio, vector identity, legal links, accessibility, and OAuth interaction checks.
2. **Dashboard:** create a wallet briefing; separate spend, rewards, milestones, and recommendations by semantic surface.
3. **Cards:** present an indexed wallet collection; protect issuer identity without allowing bank colors to dominate.
4. **Transactions:** move to a ledger-first structure with clearer scanning, filtering, and reward attribution.
5. **Movie deals:** use ticket and receipt language only where it reflects real offer mechanics; foreground eligibility, limits, and source dates.
6. **Settings:** use quiet Paper forms with explicit privacy, data, and account controls.

## Technical migration architecture

1. Add primitive, semantic, and component tokens to the Flutter theme.
2. Map legacy color and typography names to temporary compatibility aliases.
3. Rebuild shared Material themes and reusable components from semantic tokens.
4. Migrate screens in the approved order.
5. Add screenshot, widget, keyboard, focus, reduced-motion, and responsive checks per screen.
6. Remove legacy aliases only after static analysis finds no remaining callers.
7. Replace the obsolete landing design-system document with this editorial system and generated token references.

The compatibility layer is temporary. It may preserve compilation but must not be used by new or migrated UI.

## Error handling and accessibility

- Every action has visible hover, focus, pressed, loading, disabled, success, and error states where applicable.
- Keyboard order follows reading order.
- Focus is never indicated by color alone.
- Text and functional controls meet WCAG AA contrast targets.
- Touch targets are at least 44 logical pixels unless a larger component target contains the visual element.
- Reduced motion is honored globally.
- Error messages remain actionable and do not expose sensitive data.

## Verification and acceptance

- Existing business-logic and authentication tests remain green.
- Each migrated screen receives focused widget and responsive tests.
- Desktop and mobile browser walkthroughs cover primary flows and failure states.
- Theme tokens are validated for contrast and prohibited legacy accents.
- No hardcoded legacy neon, violet, or cyberpunk gradient remains outside the protected logo.
- The release web build succeeds at the production `/app/` base path.
- The user reviews the complete local application before any production merge or deployment.

## Rollback

The production version before this redesign is tagged `v1_b4_redesign` at `ff342c2`. The redesign should be developed and reviewed before merging to production. Reverting the redesign must not require database or data migrations because the work is visual and interaction-scoped.
