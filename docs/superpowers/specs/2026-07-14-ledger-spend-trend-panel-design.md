# Ledger Txns Spend Trend Panel Design

## Purpose

The Ledger Txns page shows spend/reward/category totals as static numbers but gives the user no sense of *trend* — whether spend is accelerating, which days were heaviest, how this period compares to the last. Add a collapsible spend-trend chart panel to the page that answers that at a glance, without pushing the transaction list further down the page for users who don't want it open.

## Scope

This spec covers only the trend chart panel: its collapsed pill, its expanded chart + quick-stats, and the data it's computed from. It does not cover the other UX gaps identified during audit (no per-transaction detail/edit, no merchant search, no manual add/edit transaction, no export) — those are captured as a roadmap below for future rounds, not built now.

## Placement and behavior

The panel sits directly below the existing tile row and above the grouping toggle, spanning the full page width. It starts **collapsed** on every page load (not persisted across sessions — YAGNI, this is a glanceable widget, not a setting worth remembering). Collapsed state is a single pill: a trend icon, "SPEND TREND" label, and a small caption naming the active filter scope (e.g. "This Month · All Cards" or "Last 3 Months · Diners Club Black Metal"). Tapping the pill expands it in place (no navigation, no bottom sheet) with a chevron indicating state; tapping again collapses it.

**Filter-aware, per the approved design:** the panel reads from the same `TransactionsViewState.filteredTransactions` the tiles and list already use — selecting a card, date range, or category re-renders the chart for that slice, keeping the whole page's numbers internally consistent. No separate query or provider is needed; this is pure client-side aggregation over data already loaded.

## Expanded content

1. **Area/line chart** (via `fl_chart`, already a dependency, precedent in `financial_insights_widget.dart`) — one point per day within the active date range, y-axis is that day's total debit spend, cyan line (`AppTheme.primaryColor`) with a soft cyan-to-transparent gradient fill beneath, consistent with the neon aesthetic used elsewhere. X-axis shows sparse date labels (start, midpoint, "today"/end) rather than every day, to avoid clutter. Below the chart, the same tile visual language (`#0C152B` background, `xl` border radius, cyan-tinted border) as the collapsed pill and the rest of the page.
2. **Quick stats row** beneath the chart, three columns matching the mockup:
   - **Daily Avg** — total spend in range ÷ number of days in range
   - **vs Last Period** — percentage change in total spend versus the immediately preceding period of equal length (e.g. "This Month" compares to last month; a custom 10-day range compares to the 10 days before it). Red up-arrow for an increase (more spend is the "bad" direction), green down-arrow for a decrease. Shown as `—` with no arrow when there's no prior-period data to compare against (e.g. "All Time" selected, or the account has no transaction history before the current range).
   - **Peak Day** — the single day with the highest spend in range, shown as a short date.

## Data & edge cases

- If the active range has fewer than 2 days of data (e.g. "Today" isn't a real preset today, but a 1-day custom range is possible), skip the line chart and show a single centered stat instead: "Not enough data for a trend — showing total only," with just the Total Spend figure. No broken/degenerate 1-point chart.
- If the filtered set is empty (0 transactions matching current filters), the panel doesn't render at all — this mirrors the existing "no matching transactions" empty state logic, so there's no redundant "no data" message competing with it.
- "All Time" as the date filter: the trend chart buckets by month instead of by day (otherwise a multi-year day-by-day chart is unreadable and slow to compute) — x-axis shows month labels. "vs Last Period" in this case compares the current calendar month to the previous one, same as the "This Month" behavior, since "previous all-time" isn't a meaningful comparison.
- Computation happens once per `filteredTransactions` change (memoized in the viewmodel, not recomputed on every rebuild) since the transaction list can be in the thousands for power users.

## Roadmap (not built this round)

Captured for prioritization in a future brainstorming round, in rough order of user value observed during this audit:

1. **Tap-to-detail on a transaction row** — currently rows are dead ends. A detail view (full merchant info, editable category, notes field, mark-as-duplicate, split-transaction) is the single biggest interactivity gap on this page.
2. **Merchant/amount search** — no way to jump straight to a known transaction without scrolling or filtering by category/card/date.
3. **Manual add/edit transaction** — the entire app has no UI path to add a transaction by hand or correct a mis-parsed one; `addTransaction`/`updateTransaction` exist only in the repository layer, called solely by background sync jobs.
4. **Export/share** — no CSV/PDF export of the filtered ledger, unlike the export affordance that already exists elsewhere in the app (Settings/Analytics).
5. **Receipt/attachment support** — no way to attach a photo or file to a transaction.

## Testing

Unit tests on the new viewmodel aggregation methods (daily/monthly bucketing, daily average, period-over-period percentage change, peak-day detection, the "not enough data" and "all time buckets by month" edge cases) — this is where the actual logic lives and where regressions would be invisible without tests, consistent with how `perCardSummary`/`groupedTransactions` were tested in the prior round. The chart widget itself is verified via live browser check (per the `verify` skill), not unit-tested, since `fl_chart` rendering isn't meaningfully unit-testable.
