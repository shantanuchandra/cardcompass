# App-Wide Text Selection Design

**Date:** 16 August 2026

**Status:** Approved for planning

## Objective

Let the user select and copy any text on any page of the app. Today selection only works on the login screen and inside the shared `BrandSectionHeader` component — every other screen (dashboard, cards, transactions, settings, movie deals) has no selectable text, because plain Flutter `Text` widgets aren't selectable unless an ancestor `SelectionArea` registers them.

## Approach

Wrap the whole app once, at the root, instead of extending the existing per-screen/per-component pattern. A single `SelectionArea` around the router's `child` in `CardCompassApp.build`'s `builder` (`lib/app.dart`) makes every current and future screen selectable automatically. The alternative — adding `SelectionArea` to each screen individually — is functionally identical but requires touching every screen file today and remembering to do it again for every screen added later, for no behavioral difference.

Selection applies uniformly to all text, including button captions and navigation labels — not narrowed to "content" text only. Flutter's `SelectionArea` coordinates with tap/gesture handling, so buttons keep working as buttons.

Selection highlight color stays the platform default (no `textSelectionTheme` override) — explicitly out of scope for this change.

## Components

1. **Root wrap** (`lib/app.dart`): `SelectionArea` around the `builder` callback's `child`, above the existing `MediaQuery` text-scale override.
2. **Remove the two existing narrower wraps**:
   - `BrandSectionHeader` (`lib/core/theme/brand_components.dart:115`)
   - Login screen body (`lib/features/auth/screens/login_screen.dart:106`)

   Once nested inside the new root `SelectionArea`, each of these would keep acting as its own independent selection boundary — walling its text off from the rest of the screen (e.g. you couldn't drag-select from a section header into the paragraph below it). Removing them merges everything into one continuous selectable region per screen, which is what "select the text in any of the pages" means in practice.

## Data flow / error handling

None — this is purely a widget-tree change with no state, persistence, or network involved. There's nothing to fail at runtime beyond a normal widget build.

## Testing

Extend `test/core/router/app_shell_brand_test.dart` (it already exercises app-shell-level structure) with an assertion that pumps `CardCompassApp` and checks:
- Exactly one `SelectionArea` exists in the tree at the app-shell level.
- `BrandSectionHeader` and the login screen no longer introduce their own nested `SelectionArea` (regression guard against reintroducing a siloed island).

## Out of scope

- Selection highlight color (stays default per explicit direction).
- Any change to what text exists on each screen, or to non-text content (icons, images).
