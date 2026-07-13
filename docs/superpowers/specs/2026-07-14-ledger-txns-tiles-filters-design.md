# Ledger Txns Tiles, Filters, and Grouped Views Design

## Purpose

The Ledger Txns page (`TransactionsScreen`) currently renders a flat, unfiltered-except-by-category list of transactions with no summary tiles, no card/date filtering, and no way to see spend grouped by card or category. Filter and data-loading plumbing for card/date/category already exists end-to-end (`TransactionRepository.getUserTransactions`, `TransactionsViewModelController`) but is unused by the screen. This design wires that plumbing in and adds summary tiles, a real filter bar, and a grouping toggle so a user can answer "how much did I spend on which card, in which category, over what period" without leaving this page.

## Scope

This work changes `TransactionsScreen` and its supporting viewmodel/providers only. It does not add export/report generation, does not add a calendar view, and does not create any new link between individual transactions and specific benefits (the benefits pipeline stays card-level). It does not touch the benefits extraction/staging pipeline.

## Data & state

Replace the screen's local `TransactionCategory? _categoryFilter` state with the existing `TransactionsViewModelController` (`lib/features/transactions/viewmodels/transactions_viewmodel.dart`), which already models `selectedCardId`, `selectedCategory`, `dateRange`, and produces `filteredTransactions` via `applyFilters()`. This becomes the single source of truth driving both the tiles and the list — satisfying "filters affect tiles too."

The viewmodel's `loadTransactions(userId)` loads the user's cards (`userCards`) and full transaction set once; filtering happens client-side via `applyFilters()`, consistent with how the rest of the viewmodel already works. This avoids a round-trip to Supabase on every filter change, at the cost of loading the full transaction history up front (acceptable at current expected data volumes; revisit with pagination if this page is later found slow).

`getTransactionSummary()` (already on the viewmodel) supplies `totalAmount`, `totalCount`, `topCategory`, `topCategoryAmount`. This is extended (see Tiles below) rather than replaced.

## Filter bar

A persistent filter bar directly under the app bar (replacing the current single filter icon button):

- **Card selector** — horizontally scrollable chip row: "All Cards" chip plus one chip per active card (`activeCardsProvider`), labeled by `cardName` + masked last 4. Selecting a card sets `selectedCardId`.
- **Date range** — a compact control opening a bottom sheet with presets (This Month, Last Month, Last 3 Months, All Time) and a custom range option (start/end date pickers). Sets `dateRange` (`DateRange{start, end}`). Default on first load: "This Month."
- **Category** — kept as a chip/dropdown similar to the card selector, using `TransactionCategory.values`; replaces the current bottom-sheet-only interaction to sit alongside card/date. Sets `selectedCategory`.

All three write into `TransactionsViewModelController` and immediately call `applyFilters()`, which recomputes `filteredTransactions` — both tiles and the list reread from this same state.

## Tiles

A horizontally scrollable row of tiles above the list, all computed from `filteredTransactions` (i.e., they honor the active filters):

1. **Total Spend** — sum of `amount` where `type == debit`, from `getTransactionSummary()['totalAmount']` (adjusted to debit-only, matching `monthlySpending`'s existing convention).
2. **Rewards Earned** — sum of `rewardEarned` across `filteredTransactions` (mirrors `monthlyRewards` provider logic, but scoped to the active filter rather than hardcoded to "this month").
3. **Top Category** — `topCategory` + `topCategoryAmount` from `getTransactionSummary()`.
4. **Per-card tile(s)** — computed from `filteredTransactions` grouped by `userCardId`, each showing that card's spend total + rewards total for the current filter window:
   - If "All Cards" is selected: one tile per card with any matching transactions, in a scrollable strip.
   - If a specific card is selected: a single tile for that card (the strip collapses to one entry).
5. **Card Benefits Summary** — shown only when a specific card is selected (a card-level concept, not meaningful for "All Cards"). Reuses the `_buildBenefitsSummaryCard`/`_buildSummaryItem` visual pattern from `benefits_screen.dart`, sourced from that same card's `CardBenefit` list via the existing `benefitsViewModelProvider.getCardBenefits(cardId)` — showing counts only (e.g. "Benefits Available", "Active Offers"), no evidence/verification status, since that machinery is staging-only and not attached to production `CardBenefit` records.

Tiles use the existing dark-card visual language (`Color(0xFF0C152B)` background, neon border) consistent with the rest of the page and with `benefits_screen.dart`'s summary card.

## List and grouping

Each transaction row gains a small card badge (card name or masked last-4, resolved via `userCardId` → `userCards` lookup) so the source card is visible per-transaction, addressing "show which card was it spent from" directly in the list as well as in tiles.

A segmented control above the list toggles grouping mode, applied client-side over `filteredTransactions`:

- **Flat** (current behavior) — single chronological list, newest first.
- **By Card** — section per card (header = card name/last4 + subtotal), transactions within each section sorted newest first.
- **By Category** — section per `TransactionCategory` present in the filtered set, with subtotal.
- **By Date** — section per month (or week if the filtered range is short), with subtotal.

Grouping state is local UI state (not persisted), defaulting to Flat. Subtotals reuse the same summation logic as the tiles to stay consistent.

## Error/empty states

Existing `EmptyState` widget is reused for "no transactions match the current filters," distinguished from "no transactions at all" (the latter keeps its current copy; the former gets a "no results for these filters" message with a way to clear filters, calling `clearFilters()` on the viewmodel).

## Out of scope (explicitly deferred)

- CSV/PDF export or report generation for this page.
- Calendar view.
- Per-transaction benefit attribution (would require new data model work in the benefits pipeline).
- Server-side filtering/pagination (current transaction volumes don't require it; flagged for future revisit).
