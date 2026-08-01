# Ledger Transactions & Spend Analytics Feature


---
## Sub-Component: 2026-07-14-ledger-spend-trend-panel.md

# Ledger Spend Trend Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible, filter-aware spend-trend chart panel to the Ledger Txns page, showing a daily (or monthly, for "All Time") spend line chart plus daily-average / period-over-period-change / peak-day quick stats.

**Architecture:** Pure aggregation logic (bucketing, daily average, period comparison, peak-day detection) lives on `TransactionsViewState` in `transactions_viewmodel.dart`, alongside its existing `perCardSummary()`/`groupedTransactions()` methods — unit-testable, no widget dependency. The chart UI is a new, separate stateful widget file (`spend_trend_panel.dart`) rather than more methods bolted onto the already-573-line `transactions_screen.dart`, keeping the collapse/expand UI state isolated from the screen's own state.

**Tech Stack:** Flutter, `fl_chart: ^1.2.0` (already a dependency, precedent in `financial_insights_widget.dart` using `PieChart` — this plan is the first `LineChart` usage in the repo), Riverpod, `google_fonts`.

---

## File Structure

- **Modify:** `lib/features/transactions/viewmodels/transactions_viewmodel.dart` — add `TrendPoint`, `TrendBucketing` enum, `SpendTrendSummary` classes and a `spendTrend()` method on `TransactionsViewState`. This is where all new aggregation logic lives, matching the existing pattern (`perCardSummary`, `groupedTransactions`).
- **Create:** `lib/features/transactions/presentation/widgets/spend_trend_panel.dart` — the collapsible panel widget (collapsed pill + expanded chart/stats), a private `StatefulWidget` owning its own expand/collapse bool. Takes `TransactionsViewState` and a caption string as input; has no direct viewmodel/provider dependency itself, keeping it a pure, testable-by-inspection presentation widget.
- **Modify:** `lib/features/transactions/presentation/screens/transactions_screen.dart` — insert `SpendTrendPanel(...)` into the `ListView` between the tile row and the grouping toggle/list, and add a small helper to build the filter-scope caption string ("This Month · All Cards", etc.) since only the screen knows how to turn `selectedCardId`/`dateRange` into a human label (it already does this for `_buildDateRangeControl`'s label).
- **Test:** `test/transactions_viewmodel_test.dart` — extend the existing file with a new `group('TransactionsViewState.spendTrend', ...)` block, following the same style as the `perCardSummary`/`groupedTransactions` groups already there.

---

## Task 1: Add trend-bucketing data classes and `spendTrend()` aggregation to the viewmodel

**Files:**
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart`
- Modify: `test/transactions_viewmodel_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `test/transactions_viewmodel_test.dart` (inside the existing `main()`, after the `TransactionsViewState.groupedTransactions` group — the file already has a `_tx()` helper you should reuse, with signature `_tx({required String id, required String? userCardId, required double amount, TransactionType type = TransactionType.debit, TransactionCategory category = TransactionCategory.food, double? rewardEarned, DateTime? date})`):

```dart
  group('TransactionsViewState.spendTrend', () {
    test('buckets by day and computes daily average, peak day, and no prior-period comparison for All Time', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: null, // All Time
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 1)),
          _tx(id: '2', userCardId: 'cardA', amount: 50, date: DateTime(2026, 7, 1)),
          _tx(id: '3', userCardId: 'cardA', amount: 300, date: DateTime(2026, 7, 2)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend.bucketing, TrendBucketing.byMonth);
      expect(trend.points.length, 1);
      expect(trend.points.first.total, 450);
      expect(trend.dailyAverage, closeTo(225, 0.01));
      expect(trend.peakLabel, isNotNull);
      expect(trend.percentVsPriorPeriod, isNull);
    });

    test('buckets by day within an explicit date range and computes prior-period comparison', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 9)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 300, date: DateTime(2026, 7, 9)),
          // prior period (2026-07-06 to 2026-07-07, same length) — total 200
          _tx(id: '3', userCardId: 'cardA', amount: 200, date: DateTime(2026, 7, 6)),
        ],
        transactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 300, date: DateTime(2026, 7, 9)),
          _tx(id: '3', userCardId: 'cardA', amount: 200, date: DateTime(2026, 7, 6)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend.bucketing, TrendBucketing.byDay);
      expect(trend.points.length, 2);
      expect(trend.points[0].total, 100);
      expect(trend.points[1].total, 300);
      expect(trend.dailyAverage, closeTo(200, 0.01));
      // (400 - 200) / 200 * 100 = 100% increase
      expect(trend.percentVsPriorPeriod, closeTo(100, 0.01));
      expect(trend.peakLabel, isNotNull);
    });

    test('returns null when there are fewer than 2 distinct buckets of data', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 8)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend, isNull);
    });

    test('returns null when there is no filtered data at all', () {
      final state = const TransactionsViewState().copyWith(filteredTransactions: []);

      final trend = state.spendTrend();

      expect(trend, isNull);
    });

    test('excludes non-debit transactions from bucket totals', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 9)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 500, type: TransactionType.credit, date: DateTime(2026, 7, 9)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend!.points[1].total, 0);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: FAIL — `spendTrend`, `TrendBucketing`, `SpendTrendSummary`, `TrendPoint` undefined.

- [ ] **Step 3: Implement the data classes and `spendTrend()` method**

Add near the top of `lib/features/transactions/viewmodels/transactions_viewmodel.dart`, after the existing `TransactionGroup` class and before `_debitAmount`:

```dart
/// How [SpendTrendSummary.points] are bucketed.
enum TrendBucketing { byDay, byMonth }

/// One bucket's total debit spend, labeled for chart display.
class TrendPoint {
  final DateTime bucketStart;
  final double total;
  final String label;

  const TrendPoint({
    required this.bucketStart,
    required this.total,
    required this.label,
  });
}

/// Aggregated trend data for the spend-trend panel. Null (via
/// [TransactionsViewState.spendTrend]) when there isn't enough data to plot
/// a meaningful trend.
class SpendTrendSummary {
  final TrendBucketing bucketing;
  final List<TrendPoint> points;
  final double dailyAverage;
  final String peakLabel;

  /// Percentage change in total spend vs. the immediately preceding period
  /// of equal length. Null when there's no prior-period data to compare
  /// against (e.g. "All Time" is selected, or there's no history before the
  /// current range).
  final double? percentVsPriorPeriod;

  const SpendTrendSummary({
    required this.bucketing,
    required this.points,
    required this.dailyAverage,
    required this.peakLabel,
    required this.percentVsPriorPeriod,
  });
}
```

Add this method inside `TransactionsViewState`, after `groupedTransactions()`:

```dart
  /// Aggregates [filteredTransactions] into a spend trend, bucketed by day
  /// for an explicit [dateRange] or by month when "All Time" (no range) is
  /// selected — a multi-year day-by-day chart isn't readable or worth
  /// computing. Returns null if there are fewer than 2 distinct buckets of
  /// data, since a single point isn't a trend.
  SpendTrendSummary? spendTrend() {
    if (filteredTransactions.isEmpty) return null;

    final bucketing =
        dateRange == null ? TrendBucketing.byMonth : TrendBucketing.byDay;

    DateTime bucketKeyFor(DateTime date) {
      return bucketing == TrendBucketing.byDay
          ? DateTime(date.year, date.month, date.day)
          : DateTime(date.year, date.month);
    }

    String labelFor(DateTime bucketStart) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return bucketing == TrendBucketing.byDay
          ? '${months[bucketStart.month - 1]} ${bucketStart.day}'
          : '${months[bucketStart.month - 1]} ${bucketStart.year}';
    }

    final totalsByBucket = <DateTime, double>{};
    for (final t in filteredTransactions) {
      final key = bucketKeyFor(t.transactionDate);
      totalsByBucket[key] = (totalsByBucket[key] ?? 0) + _debitAmount(t);
    }

    if (totalsByBucket.length < 2) return null;

    final sortedKeys = totalsByBucket.keys.toList()..sort();
    final points = sortedKeys
        .map((key) => TrendPoint(
              bucketStart: key,
              total: totalsByBucket[key]!,
              label: labelFor(key),
            ))
        .toList();

    final grandTotal = points.fold<double>(0, (sum, p) => sum + p.total);
    final dayCount = bucketing == TrendBucketing.byDay
        ? sortedKeys.last.difference(sortedKeys.first).inDays + 1
        : sortedKeys.length * 30;
    final dailyAverage = grandTotal / dayCount;

    final peakPoint = points.reduce((a, b) => a.total >= b.total ? a : b);

    return SpendTrendSummary(
      bucketing: bucketing,
      points: points,
      dailyAverage: dailyAverage,
      peakLabel: peakPoint.label,
      percentVsPriorPeriod: _percentVsPriorPeriod(
        bucketing: bucketing,
        currentRangeStart: sortedKeys.first,
        currentRangeEnd: sortedKeys.last,
        currentTotal: grandTotal,
      ),
    );
  }

  /// Compares the current range's total debit spend to the immediately
  /// preceding period of equal length, computed from the FULL [transactions]
  /// list (not [filteredTransactions]) so the prior period isn't itself
  /// restricted by the active filter's date bound. Returns null if there's
  /// no data in the prior period to compare against.
  double? _percentVsPriorPeriod({
    required TrendBucketing bucketing,
    required DateTime currentRangeStart,
    required DateTime currentRangeEnd,
    required double currentTotal,
  }) {
    final rangeLength = bucketing == TrendBucketing.byDay
        ? currentRangeEnd.difference(currentRangeStart).inDays + 1
        : 30;
    final priorEnd = currentRangeStart.subtract(const Duration(days: 1));
    final priorStart = priorEnd.subtract(Duration(days: rangeLength - 1));

    final cardFilter = selectedCardId.isEmpty
        ? null
        : selectedCardId;
    final categoryFilter =
        selectedCategory == 'All' ? null : selectedCategory;

    final priorTotal = transactions
        .where((t) =>
            (cardFilter == null || t.userCardId == cardFilter) &&
            (categoryFilter == null || t.category.name == categoryFilter) &&
            !t.transactionDate.isBefore(priorStart) &&
            t.transactionDate.isBefore(priorEnd.add(const Duration(days: 1))))
        .fold<double>(0, (sum, t) => sum + _debitAmount(t));

    if (priorTotal == 0) return null;
    return (currentTotal - priorTotal) / priorTotal * 100;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: PASS (all new tests, plus all prior tests in the file still passing).

- [ ] **Step 5: Run `flutter analyze` on the changed files**

Run: `flutter analyze lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart
git commit -m "feat: add spend-trend aggregation (day/month bucketing, peak day, period comparison)"
```

---

## Task 2: Build the collapsible `SpendTrendPanel` widget

**Files:**
- Create: `lib/features/transactions/presentation/widgets/spend_trend_panel.dart`

- [ ] **Step 1: Write the widget**

```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../viewmodels/transactions_viewmodel.dart';

/// Collapsible spend-trend chart panel for the Ledger Txns page. Starts
/// collapsed; tapping the pill expands it in place. Renders nothing if
/// [state.spendTrend()] has no data to show (mirrors the page's existing
/// "no matching transactions" handling — this panel doesn't compete with
/// that empty state).
class SpendTrendPanel extends StatefulWidget {
  final TransactionsViewState state;
  final String filterScopeCaption;

  const SpendTrendPanel({
    super.key,
    required this.state,
    required this.filterScopeCaption,
  });

  @override
  State<SpendTrendPanel> createState() => _SpendTrendPanelState();
}

class _SpendTrendPanelState extends State<SpendTrendPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final trend = widget.state.spendTrend();
    if (trend == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            _buildChart(trend),
            const SizedBox(height: AppSpacing.md),
            _buildStatsRow(trend),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'SPEND TREND',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.filterScopeCaption,
                style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: AppTheme.primaryColor,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(SpendTrendSummary trend) {
    final spots = [
      for (var i = 0; i < trend.points.length; i++)
        FlSpot(i.toDouble(), trend.points[i].total),
    ];

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: null,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (trend.points.length / 3).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= trend.points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      trend.points[index].label,
                      style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.primaryColor,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, barData) =>
                    spot.x == spots.length - 1,
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.3),
                    AppTheme.primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(SpendTrendSummary trend) {
    final percent = trend.percentVsPriorPeriod;
    final isIncrease = (percent ?? 0) > 0;

    return Row(
      children: [
        Expanded(
          child: _stat(
            'DAILY AVG',
            '₹${trend.dailyAverage.toStringAsFixed(0)}',
            AppTheme.primaryColor,
          ),
        ),
        Expanded(
          child: _stat(
            'VS LAST PERIOD',
            percent == null
                ? '—'
                : '${isIncrease ? '↑' : '↓'} ${percent.abs().toStringAsFixed(0)}%',
            percent == null
                ? Colors.white54
                : (isIncrease ? AppTheme.errorColor : AppTheme.successColor),
          ),
        ),
        Expanded(
          child: _stat('PEAK DAY', trend.peakLabel, Colors.white),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze` on the new file**

Run: `flutter analyze lib/features/transactions/presentation/widgets/spend_trend_panel.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/transactions/presentation/widgets/spend_trend_panel.dart
git commit -m "feat: add collapsible SpendTrendPanel widget"
```

---

## Task 3: Wire the panel into the Ledger Txns screen with a filter-scope caption

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`

- [ ] **Step 1: Add the import**

Add to the imports at the top of `lib/features/transactions/presentation/screens/transactions_screen.dart`:

```dart
import 'widgets/spend_trend_panel.dart';
```

- [ ] **Step 2: Insert the panel into the `ListView`**

In `build()`, insert `SpendTrendPanel(...)` (plus spacing) between `_buildTileRow` and the grouping/list section:

```dart
                children: [
                  _buildFilterBar(state, notifier),
                  const SizedBox(height: AppSpacing.md),
                  _buildTileRow(state, notifier),
                  const SizedBox(height: AppSpacing.md),
                  SpendTrendPanel(
                    state: state,
                    filterScopeCaption: _filterScopeCaption(state),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (state.filteredTransactions.isEmpty)
                    _buildNoResultsState(notifier)
                  else
                    ..._buildTransactionSections(state),
                ],
```

- [ ] **Step 3: Add the `_filterScopeCaption` helper**

Add this method to `_TransactionsScreenState` (near `_buildDateRangeControl`, which already has similar date-label logic to mirror):

```dart
  String _filterScopeCaption(TransactionsViewState state) {
    final dateLabel = state.dateRange == null
        ? 'All Time'
        : '${_shortDate(state.dateRange!.start)} - ${_shortDate(state.dateRange!.end)}';

    final cardLabel = state.selectedCardId.isEmpty
        ? 'All Cards'
        : state.userCards
            .firstWhere(
              (c) => c.id == state.selectedCardId,
              orElse: () => state.userCards.first,
            )
            .cardName;

    return '$dateLabel · $cardLabel';
  }
```

Note: this reuses the existing private `_shortDate` method already defined in this file (used by `_buildDateRangeControl`) — do not redefine it.

- [ ] **Step 4: Run `flutter analyze` on the full file**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No issues found.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: wire SpendTrendPanel into the ledger txns page"
```

---

## Task 4: Manual verification in a running app

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Use `flutter run -d chrome --web-port <port>` and open it in Comet per the user's standing preference for live testing there, sign in, navigate to Ledger Txns.

- [ ] **Step 2: Verify the golden path**

Confirm: the panel renders collapsed by default below the tile row; tapping it expands to show the line chart with a cyan gradient fill and sparse date labels, plus the Daily Avg / vs Last Period / Peak Day stats row; tapping again collapses it. Confirm the caption text updates when changing the card/date filter (e.g. "This Month · All Cards" → "This Month · <Card Name>").

- [ ] **Step 3: Verify edge cases**

Confirm: selecting "All Time" switches the chart to month buckets with month/year labels; selecting a narrow custom range with only one day of transactions makes the panel disappear entirely (not a broken 1-point chart) since `spendTrend()` returns null; a card/category/date combination that yields zero transactions also hides the panel (no competing empty-state text).

- [ ] **Step 4: Report results**

Note any visual issues and fix them in the relevant task's file before considering the plan complete — any fix gets its own commit, not a rewrite of an already-committed task.


---
## Sub-Component: 2026-07-14-ledger-txns-tiles-filters.md

# Ledger Txns Tiles, Filters, and Grouped Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Ledger Txns page from a flat, category-only-filtered list into a filterable (card + date + category) page with summary tiles (spend, rewards, top category, per-card, card benefits) and a grouping toggle (flat/card/category/date), so users can see where their money went, by which card, and how that ties to card benefits.

**Architecture:** Rewire `TransactionsScreen` off its local `_categoryFilter` state and onto the existing (currently unused) `TransactionsViewModelController`, which already has card/date/category filter state and `applyFilters()`/`getTransactionSummary()`. Add pure-Dart helper methods on the viewmodel for per-card summaries and date/category grouping (unit-testable), then build the screen's UI (filter bar, tile row, grouped list) on top of that state. No new backend calls — `loadTransactions` already fetches the full transaction + card list once; all filtering/grouping is client-side.

**Tech Stack:** Flutter, Riverpod (`@riverpod` code-gen), Hive/Supabase-backed models already in place, `google_fonts`, `flutter_animate`. Test with `flutter test` (pure-Dart unit tests only — this codebase has no widget-test precedent, so UI is verified via manual run per the `verify` skill instead of widget tests).

---

## File Structure

- **Modify:** `lib/features/transactions/viewmodels/transactions_viewmodel.dart` — add `getPerCardSummary()`, `getGroupedTransactions(TransactionGrouping)` methods and a `TransactionGrouping` enum. This is where all new filtering/grouping/summary math lives, so it stays unit-testable independent of widgets.
- **Modify:** `lib/features/transactions/presentation/screens/transactions_screen.dart` — full rebuild of `build()` to read from `TransactionsViewModelController` instead of local state; add filter bar, tile row, grouping toggle, grouped list rendering, card badge per row.
- **Create:** `test/transactions_viewmodel_test.dart` — unit tests for filtering, per-card summary, and grouping logic.

No other files change. The benefits card-summary widget is *replicated* (small, page-specific `_buildCardBenefitsTile` in the screen file) rather than extracted into a shared widget — it's a 15-line presentational block, not worth a cross-feature abstraction (YAGNI).

---

## Task 1: Add `TransactionGrouping` enum and per-card summary to the viewmodel

**Files:**
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart`
- Test: `test/transactions_viewmodel_test.dart`

- [ ] **Step 1: Write the failing test for per-card summary**

Create `test/transactions_viewmodel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/transactions/viewmodels/transactions_viewmodel.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({
  required String id,
  required String userCardId,
  required double amount,
  TransactionType type = TransactionType.debit,
  TransactionCategory category = TransactionCategory.food,
  double? rewardEarned,
  DateTime? date,
}) {
  return Transaction(
    id: id,
    userId: 'u1',
    userCardId: userCardId,
    amount: amount,
    description: 'test',
    category: category,
    type: type,
    transactionDate: date ?? DateTime(2026, 7, 10),
    rewardEarned: rewardEarned,
    createdAt: DateTime(2026, 7, 10),
  );
}

void main() {
  group('TransactionsViewState.perCardSummary', () {
    test('sums spend and rewards per card from filteredTransactions', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, rewardEarned: 5),
          _tx(id: '2', userCardId: 'cardA', amount: 50, rewardEarned: 2),
          _tx(id: '3', userCardId: 'cardB', amount: 200),
          _tx(id: '4', userCardId: 'cardA', amount: 30, type: TransactionType.credit),
        ],
      );

      final summary = state.perCardSummary();

      expect(summary['cardA']!.totalSpend, 150);
      expect(summary['cardA']!.totalRewards, 7);
      expect(summary['cardB']!.totalSpend, 200);
      expect(summary['cardB']!.totalRewards, 0);
      expect(summary.containsKey('cardA'), isTrue);
    });

    test('excludes transactions with null userCardId', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: '', amount: 100),
        ],
      );
      final summary = state.perCardSummary();
      expect(summary.isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: FAIL — compile error, `perCardSummary` and `CardSpendSummary` undefined.

- [ ] **Step 3: Implement `CardSpendSummary` and `perCardSummary()` on `TransactionsViewState`**

In `lib/features/transactions/viewmodels/transactions_viewmodel.dart`, add near the top (after imports, before `TransactionsViewState`):

```dart
/// Aggregated spend/reward totals for one card within the current filter.
class CardSpendSummary {
  final String cardId;
  final double totalSpend;
  final double totalRewards;

  const CardSpendSummary({
    required this.cardId,
    required this.totalSpend,
    required this.totalRewards,
  });
}
```

Add this method inside `TransactionsViewState` (after the `copyWith` method, before the closing brace):

```dart
  /// Per-card spend + reward totals, computed from [filteredTransactions].
  /// Transactions with a null/empty userCardId are excluded.
  Map<String, CardSpendSummary> perCardSummary() {
    final spendByCard = <String, double>{};
    final rewardsByCard = <String, double>{};

    for (final t in filteredTransactions) {
      final cardId = t.userCardId;
      if (cardId == null || cardId.isEmpty) continue;

      if (t.type == TransactionType.debit) {
        spendByCard[cardId] = (spendByCard[cardId] ?? 0) + t.amount.abs();
      } else {
        spendByCard.putIfAbsent(cardId, () => 0);
      }
      rewardsByCard[cardId] = (rewardsByCard[cardId] ?? 0) + (t.rewardEarned ?? 0);
    }

    return {
      for (final cardId in spendByCard.keys)
        cardId: CardSpendSummary(
          cardId: cardId,
          totalSpend: spendByCard[cardId] ?? 0,
          totalRewards: rewardsByCard[cardId] ?? 0,
        ),
    };
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart
git commit -m "feat: add per-card spend/reward summary to transactions viewmodel"
```

---

## Task 2: Add `TransactionGrouping` enum and grouped-transactions method

**Files:**
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart`
- Test: `test/transactions_viewmodel_test.dart`

- [ ] **Step 1: Write the failing test for grouping**

Append to `test/transactions_viewmodel_test.dart` (inside `main()`, after the existing `group`):

```dart
  group('TransactionsViewState.groupedTransactions', () {
    test('flat grouping returns a single group with all filtered transactions, newest first', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 7, 1)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 10)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.flat);

      expect(groups.length, 1);
      expect(groups.first.key, 'All Transactions');
      expect(groups.first.transactions.map((t) => t.id).toList(), ['2', '1']);
    });

    test('byCard grouping buckets by userCardId with per-group subtotal', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10),
          _tx(id: '2', userCardId: 'cardB', amount: 20),
          _tx(id: '3', userCardId: 'cardA', amount: 5),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCard);
      final byKey = {for (final g in groups) g.key: g};

      expect(byKey.keys.toSet(), {'cardA', 'cardB'});
      expect(byKey['cardA']!.transactions.length, 2);
      expect(byKey['cardA']!.subtotal, 15);
      expect(byKey['cardB']!.subtotal, 20);
    });

    test('byCategory grouping buckets by category name', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, category: TransactionCategory.food),
          _tx(id: '2', userCardId: 'cardA', amount: 20, category: TransactionCategory.fuel),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCategory);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'food', 'fuel'});
    });

    test('byDate grouping buckets by year-month', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 6, 15)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 1)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byDate);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'2026-06', '2026-07'});
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: FAIL — `TransactionGrouping`, `groupedTransactions` undefined.

- [ ] **Step 3: Implement `TransactionGrouping`, `TransactionGroup`, and `groupedTransactions()`**

Add after the `CardSpendSummary` class in `lib/features/transactions/viewmodels/transactions_viewmodel.dart`:

```dart
/// How the transaction list should be sectioned in the UI.
enum TransactionGrouping { flat, byCard, byCategory, byDate }

/// One section of grouped transactions with a display key and subtotal.
class TransactionGroup {
  final String key;
  final List<Transaction> transactions;
  final double subtotal;

  const TransactionGroup({
    required this.key,
    required this.transactions,
    required this.subtotal,
  });
}

double _debitTotal(List<Transaction> transactions) {
  return transactions
      .where((t) => t.type == TransactionType.debit)
      .fold<double>(0, (sum, t) => sum + t.amount.abs());
}

List<Transaction> _sortedNewestFirst(List<Transaction> transactions) {
  final sorted = List<Transaction>.from(transactions);
  sorted.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return sorted;
}
```

Add this method inside `TransactionsViewState` (after `perCardSummary()`):

```dart
  /// Sections [filteredTransactions] per [grouping], each section newest-first,
  /// sections ordered by first-seen key.
  List<TransactionGroup> groupedTransactions(TransactionGrouping grouping) {
    if (grouping == TransactionGrouping.flat) {
      final sorted = _sortedNewestFirst(filteredTransactions);
      return [
        TransactionGroup(
          key: 'All Transactions',
          transactions: sorted,
          subtotal: _debitTotal(sorted),
        ),
      ];
    }

    String keyFor(Transaction t) {
      switch (grouping) {
        case TransactionGrouping.byCard:
          return (t.userCardId == null || t.userCardId!.isEmpty) ? 'Unknown Card' : t.userCardId!;
        case TransactionGrouping.byCategory:
          return t.categoryString;
        case TransactionGrouping.byDate:
          return '${t.transactionDate.year}-${t.transactionDate.month.toString().padLeft(2, '0')}';
        case TransactionGrouping.flat:
          return 'All Transactions';
      }
    }

    final buckets = <String, List<Transaction>>{};
    for (final t in filteredTransactions) {
      buckets.putIfAbsent(keyFor(t), () => []).add(t);
    }

    return buckets.entries.map((entry) {
      final sorted = _sortedNewestFirst(entry.value);
      return TransactionGroup(
        key: entry.key,
        transactions: sorted,
        subtotal: _debitTotal(sorted),
      );
    }).toList();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transactions_viewmodel_test.dart`
Expected: PASS (6 tests total)

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/viewmodels/transactions_viewmodel.dart test/transactions_viewmodel_test.dart
git commit -m "feat: add transaction grouping (flat/card/category/date) to viewmodel"
```

---

## Task 3: Wire `TransactionsScreen` onto `TransactionsViewModelController` and add the filter bar

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`

- [ ] **Step 1: Replace state source and load call**

In `lib/features/transactions/presentation/screens/transactions_screen.dart`, replace the whole file with the version below. This step covers filter-bar wiring; tiles and grouped list are added in Tasks 4-5 within the same file, so the full file is given here and refined in place in subsequent tasks (each task's diff is additive on top of this).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/state_widgets.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/credit_card.dart';
import '../../viewmodels/transactions_viewmodel.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionGrouping _grouping = TransactionGrouping.flat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    ref.read(transactionsViewModelProvider.notifier).loadTransactions(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsViewModelProvider);
    final notifier = ref.read(transactionsViewModelProvider.notifier);

    return CardCompassScaffold(
      title: 'Transactions',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: state.transactions.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Transactions from your statements will show up here.',
                )
              : RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF0C152B),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm + 4,
                      AppSpacing.md,
                      80,
                    ),
                    children: [
                      _buildFilterBar(state, notifier),
                      const SizedBox(height: AppSpacing.md),
                      if (state.filteredTransactions.isEmpty)
                        _buildNoResultsState(notifier)
                      else
                        ..._buildTransactionSections(state),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms, curve: Curves.easeOut).slideY(
                    begin: 0.05,
                    end: 0,
                    duration: 250.ms,
                    curve: Curves.easeOut,
                  ),
        ),
      ),
    );
  }

  Widget _buildNoResultsState(TransactionsViewModelController notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No matching transactions',
        message: 'Try widening your filters.',
        buttonText: 'Clear filters',
        onButtonPressed: notifier.clearFilters,
      ),
    );
  }

  Widget _buildFilterBar(TransactionsViewState state, TransactionsViewModelController notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardFilterRow(state, notifier),
        const SizedBox(height: AppSpacing.sm),
        _buildDateRangeControl(state, notifier),
        const SizedBox(height: AppSpacing.sm),
        _buildCategoryFilterRow(state, notifier),
      ],
    );
  }

  Widget _buildCardFilterRow(TransactionsViewState state, TransactionsViewModelController notifier) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            label: 'All Cards',
            selected: state.selectedCardId.isEmpty,
            onTap: () => notifier.setSelectedCard(''),
          ),
          for (final card in state.userCards)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _filterChip(
                label: '${card.cardName} •••${card.cardNumberLast4 ?? ''}',
                selected: state.selectedCardId == card.id,
                onTap: () => notifier.setSelectedCard(card.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterRow(TransactionsViewState state, TransactionsViewModelController notifier) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(
            label: 'All Categories',
            selected: state.selectedCategory == 'All',
            onTap: () => notifier.setSelectedCategory('All'),
          ),
          for (final category in TransactionCategory.values)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _filterChip(
                label: category.name.toUpperCase(),
                selected: state.selectedCategory == category.name,
                onTap: () => notifier.setSelectedCategory(category.name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required bool selected, required VoidCallback onTap}) {
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.black : Colors.white70,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF0C152B),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    );
  }

  Widget _buildDateRangeControl(TransactionsViewState state, TransactionsViewModelController notifier) {
    final label = state.dateRange == null
        ? 'All Time'
        : '${_shortDate(state.dateRange!.start)} - ${_shortDate(state.dateRange!.end)}';

    return InkWell(
      onTap: () => _showDateRangeSheet(context, notifier),
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: const Color(0xFF0C152B),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, color: AppTheme.primaryColor, size: 14),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  void _showDateRangeSheet(BuildContext context, TransactionsViewModelController notifier) {
    final now = DateTime.now();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C152B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'FILTER BY DATE',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('All Time', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(null);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('This Month', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month, 1), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Last Month', style: TextStyle(color: Colors.white)),
                onTap: () {
                  final lastMonth = DateTime(now.year, now.month - 1, 1);
                  final endOfLastMonth = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
                  notifier.setDateRange(DateRange(start: lastMonth, end: endOfLastMonth));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Last 3 Months', style: TextStyle(color: Colors.white)),
                onTap: () {
                  notifier.setDateRange(DateRange(start: DateTime(now.year, now.month - 3, now.day), end: now));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Custom Range', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: now,
                  );
                  if (picked != null) {
                    notifier.setDateRange(DateRange(start: picked.start, end: picked.end));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    return [const SizedBox.shrink()]; // replaced in Task 5
  }
}
```

- [ ] **Step 2: Run static analysis to confirm the file compiles**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors (warnings about unused `_grouping`/`CreditCard` import are acceptable at this intermediate step and resolved by Task 5).

- [ ] **Step 3: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: wire ledger txns screen onto shared viewmodel with card/date/category filter bar"
```

---

## Task 4: Add the summary tile row (Total Spend, Rewards Earned, Top Category, per-card, Card Benefits)

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`
- Modify: `lib/features/transactions/viewmodels/transactions_viewmodel.dart` (only if a helper is missing — none expected; `getTransactionSummary()` and `perCardSummary()` already exist)

- [ ] **Step 1: Add imports for benefits viewmodel**

In `lib/features/transactions/presentation/screens/transactions_screen.dart`, add to the imports:

```dart
import '../../../benefits/viewmodels/benefits_viewmodel.dart';
import '../../../../shared/models/benefit.dart';
```

- [ ] **Step 2: Insert the tile row into `build()`**

In the `ListView`'s `children` list built in Task 3, insert `_buildTileRow(state)` right after `_buildFilterBar(state, notifier)`:

```dart
                    children: [
                      _buildFilterBar(state, notifier),
                      const SizedBox(height: AppSpacing.md),
                      _buildTileRow(state),
                      const SizedBox(height: AppSpacing.md),
                      if (state.filteredTransactions.isEmpty)
                        _buildNoResultsState(notifier)
                      else
                        ..._buildTransactionSections(state),
                    ],
```

- [ ] **Step 3: Implement `_buildTileRow` and its sub-widgets**

Add these methods to `_TransactionsScreenState`:

```dart
  Widget _buildTileRow(TransactionsViewState state) {
    final summary = state.getTransactionSummary();
    final perCard = state.perCardSummary();
    final cardsToShow = state.selectedCardId.isEmpty
        ? state.userCards
        : state.userCards.where((c) => c.id == state.selectedCardId).toList();

    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _statTile('TOTAL SPEND', '₹${(summary['totalAmount'] as double).toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, AppTheme.primaryColor),
          _statTile('REWARDS EARNED', '₹${_totalRewards(state).toStringAsFixed(0)}', Icons.stars_outlined, AppTheme.rewardGold),
          _statTile('TOP CATEGORY', '${summary['topCategory']}', Icons.pie_chart_outline, AppTheme.accentColor,
              subtitle: '₹${(summary['topCategoryAmount'] as double).toStringAsFixed(0)}'),
          for (final card in cardsToShow)
            _cardTile(card, perCard[card.id]),
          if (state.selectedCardId.isNotEmpty && cardsToShow.isNotEmpty)
            _cardBenefitsTile(cardsToShow.first.id),
        ],
      ),
    );
  }

  double _totalRewards(TransactionsViewState state) {
    return state.filteredTransactions.fold<double>(0, (sum, t) => sum + (t.rewardEarned ?? 0));
  }

  Widget _statTile(String label, String value, IconData icon, Color color, {String? subtitle}) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle, style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _cardTile(CreditCard card, CardSpendSummary? summary) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: card.networkColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card, color: card.networkColor, size: 18),
          const SizedBox(height: AppSpacing.sm),
          Text('₹${(summary?.totalSpend ?? 0).toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text('+₹${(summary?.totalRewards ?? 0).toStringAsFixed(0)} rewards', style: GoogleFonts.spaceGrotesk(color: AppTheme.rewardGold, fontSize: 11)),
          const SizedBox(height: 2),
          Text(card.cardName.toUpperCase(), style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _cardBenefitsTile(String cardId) {
    return Consumer(
      builder: (context, ref, _) {
        final benefitsState = ref.watch(benefitsViewModelProvider);
        final cardBenefits = benefitsState.userCardBenefits.where((cb) => cb.cardId == cardId).toList();
        final activeCount = cardBenefits.where((cb) => cb.isActive).length;

        return Container(
          width: 160,
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFF0C152B),
            borderRadius: BorderRadius.circular(AppBorderRadius.xl),
            border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.25), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_outlined, color: AppTheme.successColor, size: 18),
              const SizedBox(height: AppSpacing.sm),
              Text('${cardBenefits.length} available', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              Text('$activeCount active', style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 2),
              Text('CARD BENEFITS', style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
            ],
          ),
        );
      },
    );
  }
```

Note: `benefitsViewModelProvider` state is populated by `benefits_screen.dart`'s own `loadBenefitsData` call when that screen has been visited; this tile reads whatever is already loaded and does not trigger its own load, to avoid duplicating data-fetch responsibility across features. If the user hasn't opened Benefits yet in the session, the tile shows 0/0, which is acceptable for this iteration (documented limitation, not a bug — no cross-feature preloading is introduced here per YAGNI).

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: add spend/reward/category/card/benefits summary tiles to ledger txns page"
```

---

## Task 5: Add grouping toggle and render grouped transaction sections with card badges

**Files:**
- Modify: `lib/features/transactions/presentation/screens/transactions_screen.dart`

- [ ] **Step 1: Replace the `_buildTransactionSections` stub with the real implementation**

Replace:

```dart
  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    return [const SizedBox.shrink()]; // replaced in Task 5
  }
```

with:

```dart
  List<Widget> _buildTransactionSections(TransactionsViewState state) {
    final groups = state.groupedTransactions(_grouping);
    final cardsById = {for (final c in state.userCards) c.id: c};

    return [
      _buildGroupingToggle(),
      const SizedBox(height: AppSpacing.md),
      for (final group in groups) ...[
        if (_grouping != TransactionGrouping.flat) _buildGroupHeader(group, state.selectedCardId, cardsById),
        for (final t in group.transactions) _buildTransactionRow(t, cardsById),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  Widget _buildGroupingToggle() {
    const options = {
      TransactionGrouping.flat: 'Flat',
      TransactionGrouping.byCard: 'By Card',
      TransactionGrouping.byCategory: 'By Category',
      TransactionGrouping.byDate: 'By Date',
    };

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: options.entries.map((entry) {
          final selected = _grouping == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(entry.value, style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.black : Colors.white70)),
              selected: selected,
              onSelected: (_) => setState(() => _grouping = entry.key),
              selectedColor: AppTheme.primaryColor,
              backgroundColor: const Color(0xFF0C152B),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGroupHeader(TransactionGroup group, String selectedCardId, Map<String, CreditCard> cardsById) {
    String title = group.key;
    if (_grouping == TransactionGrouping.byCard) {
      title = cardsById[group.key]?.cardName ?? 'Unknown Card';
    } else if (_grouping == TransactionGrouping.byCategory) {
      title = group.key.toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
          Text('₹${group.subtotal.toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Transaction t, Map<String, CreditCard> cardsById) {
    final isCredit = t.type == TransactionType.credit || t.type == TransactionType.refund;
    final categoryColor = _getCategoryColor(t.categoryString);
    final card = cardsById[t.userCardId];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0C152B),
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: categoryColor.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(_categoryIcon(t.category), color: categoryColor, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.merchantName ?? t.description,
                  style: AppTextStyles.body2.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(
                      '${_formatDate(t.transactionDate)} · ${t.categoryString.toUpperCase()}',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                    ),
                    if (card != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: card.networkColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                        ),
                        child: Text(
                          '${card.cardName} •${card.cardNumberLast4 ?? ''}',
                          style: GoogleFonts.spaceGrotesk(color: card.networkColor, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                style: GoogleFonts.spaceGrotesk(color: isCredit ? AppTheme.successColor : Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (t.rewardEarned != null && t.rewardEarned! > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '+₹${t.rewardEarned!.toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(color: AppTheme.rewardGold, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(TransactionCategory category) {
    switch (category) {
      case TransactionCategory.food:
        return Icons.restaurant;
      case TransactionCategory.fuel:
        return Icons.local_gas_station;
      case TransactionCategory.grocery:
        return Icons.shopping_basket;
      case TransactionCategory.entertainment:
        return Icons.movie;
      case TransactionCategory.travel:
        return Icons.flight;
      case TransactionCategory.shopping:
        return Icons.shopping_bag;
      default:
        return Icons.payment;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'food':
        return Colors.orange;
      case 'shopping':
        return AppTheme.primaryColor;
      case 'fuel':
        return AppTheme.errorColor;
      case 'entertainment':
        return Colors.purpleAccent;
      case 'travel':
        return Colors.green;
      case 'grocery':
      case 'groceries':
        return Colors.tealAccent;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
```

- [ ] **Step 2: Run static analysis on the full file**

Run: `flutter analyze lib/features/transactions/presentation/screens/transactions_screen.dart`
Expected: No errors, no unused-import/unused-field warnings.

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `flutter test`
Expected: All tests pass, including the 6 new tests from Tasks 1-2.

- [ ] **Step 4: Commit**

```bash
git add lib/features/transactions/presentation/screens/transactions_screen.dart
git commit -m "feat: add grouping toggle and per-transaction card badge to ledger txns list"
```

---

## Task 6: Manual verification in a running app

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Use the `run` skill (or `flutter run`) to launch the app on an available device/emulator, and navigate to the Ledger Txns tab.

- [ ] **Step 2: Verify the golden path**

Confirm: tile row renders (Total Spend, Rewards Earned, Top Category, per-card tiles); filter bar shows card chips, date control, category chips; selecting a card filters both tiles and list; selecting "This Month" narrows the list; grouping toggle switches between Flat/By Card/By Category/By Date with correct section headers and subtotals; each transaction row shows its card badge.

- [ ] **Step 3: Verify edge cases**

Confirm: a user with zero cards/transactions still sees the original "No transactions yet" empty state; applying filters that match nothing shows the new "No matching transactions" state with a working "Clear filters" button; selecting "All Cards" after a specific card was selected collapses the Card Benefits tile away (it's card-specific only).

- [ ] **Step 4: Report results**

Note any visual issues found and fix them in the relevant task's file before considering the plan complete. This step produces no commit by itself — any fix gets its own commit.


---
## Sub-Component: 2026-07-14-ledger-spend-trend-panel-design.md

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


---
## Sub-Component: 2026-07-14-ledger-txns-tiles-filters-design.md

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
