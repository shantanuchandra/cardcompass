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
