import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/features/transactions/data/transactions_repository.dart';

part 'transactions_viewmodel.g.dart';

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

/// The single authoritative definition of "debit spend" for a transaction:
/// its absolute amount if it's a debit, otherwise zero.
double _debitAmount(Transaction t) {
  return t.type == TransactionType.debit ? t.amount.abs() : 0;
}

double _debitTotal(List<Transaction> transactions) {
  return transactions.fold<double>(0, (sum, t) => sum + _debitAmount(t));
}

List<Transaction> _sortedNewestFirst(List<Transaction> transactions) {
  final sorted = List<Transaction>.from(transactions);
  sorted.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  return sorted;
}

/// Transactions view state
class TransactionsViewState {
  final List<Transaction> transactions;
  final List<Transaction> filteredTransactions;
  final List<CreditCard> userCards;
  final bool isLoading;
  final String? error;
  final String selectedCardId;
  final String selectedCategory;
  final DateRange? dateRange;

  const TransactionsViewState({
    this.transactions = const [],
    this.filteredTransactions = const [],
    this.userCards = const [],
    this.isLoading = false,
    this.error,
    this.selectedCardId = '',
    this.selectedCategory = 'All',
    this.dateRange,
  });

  TransactionsViewState copyWith({
    List<Transaction>? transactions,
    List<Transaction>? filteredTransactions,
    List<CreditCard>? userCards,
    bool? isLoading,
    String? error,
    String? selectedCardId,
    String? selectedCategory,
    DateRange? dateRange,
  }) {
    return TransactionsViewState(
      transactions: transactions ?? this.transactions,
      filteredTransactions: filteredTransactions ?? this.filteredTransactions,
      userCards: userCards ?? this.userCards,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      selectedCardId: selectedCardId ?? this.selectedCardId,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      dateRange: dateRange ?? this.dateRange,
    );
  }

  /// Per-card spend + reward totals, computed from [filteredTransactions].
  /// Transactions with a null/empty userCardId are excluded.
  Map<String, CardSpendSummary> perCardSummary() {
    // Every card that has at least one transaction gets an entry, even if
    // its only transactions are non-debit (e.g. credit/refund) — such a
    // card still appears in the summary with totalSpend: 0.
    final transactionsByCard = <String, List<Transaction>>{};
    for (final t in filteredTransactions) {
      final cardId = t.userCardId;
      if (cardId == null || cardId.isEmpty) continue;
      transactionsByCard.putIfAbsent(cardId, () => []).add(t);
    }

    return transactionsByCard.map((cardId, transactions) {
      final totalRewards = transactions.fold<double>(
        0,
        (sum, t) => sum + (t.rewardEarned ?? 0),
      );
      return MapEntry(
        cardId,
        CardSpendSummary(
          cardId: cardId,
          totalSpend: _debitTotal(transactions),
          totalRewards: totalRewards,
        ),
      );
    });
  }

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

  /// Aggregates [filteredTransactions] into a spend trend, bucketed by day
  /// for an explicit [dateRange] or by month when "All Time" (no range) is
  /// selected. Returns null if there are fewer than 2 distinct buckets.
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

    // Only count buckets that have actual debit spend; credit-only days produce
    // zero-total buckets that don't constitute meaningful trend points.
    final nonZeroBucketCount =
        totalsByBucket.values.where((v) => v > 0).length;
    if (nonZeroBucketCount < 2) return null;

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
        ? dateRange!.end.difference(dateRange!.start).inDays + 1
        : () {
            // Compute days from start of first month to end of last month
            final firstDay = sortedKeys.first;
            final lastMonth = sortedKeys.last;
            final endOfLastMonth = DateTime(lastMonth.year, lastMonth.month + 1, 0);
            return endOfLastMonth.difference(firstDay).inDays + 1;
          }();
    final dailyAverage = grandTotal / dayCount;

    final peakPoint = points.reduce((a, b) => a.total >= b.total ? a : b);

    return SpendTrendSummary(
      bucketing: bucketing,
      points: points,
      dailyAverage: dailyAverage,
      peakLabel: peakPoint.label,
      percentVsPriorPeriod: bucketing == TrendBucketing.byDay
          ? _percentVsPriorPeriod(
              bucketing: bucketing,
              currentRangeStart: dateRange!.start,
              currentRangeEnd: dateRange!.end,
              currentTotal: grandTotal,
            )
          : null,
    );
  }

  /// Compares the current range's total debit spend to the immediately
  /// preceding period of equal length, computed from the FULL [transactions]
  /// list so the prior period isn't restricted by the active date filter.
  double? _percentVsPriorPeriod({
    required TrendBucketing bucketing,
    required DateTime currentRangeStart,
    required DateTime currentRangeEnd,
    required double currentTotal,
  }) {
    if (bucketing == TrendBucketing.byMonth) return null;

    final rangeLength =
        currentRangeEnd.difference(currentRangeStart).inDays + 1;
    final priorEnd = currentRangeStart.subtract(const Duration(days: 1));
    final priorStart = priorEnd.subtract(Duration(days: rangeLength - 1));

    final cardFilter = selectedCardId.isEmpty ? null : selectedCardId;
    final categoryFilter = selectedCategory == 'All' ? null : selectedCategory;

    final priorTotal = transactions
        .where((t) =>
            (cardFilter == null || t.userCardId == cardFilter) &&
            (categoryFilter == null || t.category.name == categoryFilter) &&
            !t.transactionDate.isBefore(priorStart) &&
            t.transactionDate
                .isBefore(priorEnd.add(const Duration(days: 1))))
        .fold<double>(0, (sum, t) => sum + _debitAmount(t));

    if (priorTotal == 0) return null;
    return (currentTotal - priorTotal) / priorTotal * 100;
  }
}

/// Date range for filtering
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});
}

/// Transactions view model
@riverpod
class TransactionsViewModelController extends _$TransactionsViewModelController {
  @override
  TransactionsViewState build() {
    return const TransactionsViewState();
  }

  /// Load transactions for user
  Future<void> loadTransactions(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final repository = ref.read(transactionsRepositoryProvider);
      final transactions = await repository.getUserTransactions(userId);
      final userCards = await repository.getUserCards(userId);
      
      state = state.copyWith(
        transactions: transactions,
        filteredTransactions: transactions,
        userCards: userCards,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load transactions: $e',
      );
    }
  }

  /// Apply filters
  void applyFilters() {
    var filtered = state.transactions;
    // Filter by card
    if (state.selectedCardId.isNotEmpty) {
      filtered = filtered.where((t) => t.userCardId == state.selectedCardId).toList();
    }
    // Filter by category
    if (state.selectedCategory != 'All') {
      filtered = filtered.where((t) => t.category.name == state.selectedCategory).toList();
    }
    
    // Filter by date range
    if (state.dateRange != null) {
      filtered = filtered.where((t) => 
        t.transactionDate.isAfter(state.dateRange!.start) &&
        t.transactionDate.isBefore(state.dateRange!.end.add(const Duration(days: 1)))
      ).toList();
    }
    
    // Sort by date (newest first)
    filtered.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    
    state = state.copyWith(filteredTransactions: filtered);
  }

  /// Set selected card filter
  void setSelectedCard(String cardId) {
    state = state.copyWith(selectedCardId: cardId);
    applyFilters();
  }

  /// Set selected category filter
  void setSelectedCategory(String category) {
    state = state.copyWith(selectedCategory: category);
    applyFilters();
  }

  /// Set date range filter
  void setDateRange(DateRange? dateRange) {
    state = state.copyWith(dateRange: dateRange);
    applyFilters();
  }

  /// Clear all filters
  void clearFilters() {
    state = state.copyWith(
      selectedCardId: '',
      selectedCategory: 'All',
      dateRange: null,
      filteredTransactions: state.transactions,
    );
  }

  /// Refresh transactions
  Future<void> refreshTransactions(String userId) async {
    await loadTransactions(userId);
  }

  /// Get available categories from transactions
  List<String> getAvailableCategories() {
    final categories = state.transactions
        .map((t) => t.category.name)
        .toSet()
        .toList();
    categories.sort();
    return ['All', ...categories];
  }

  /// Get transaction summary
  Map<String, dynamic> getTransactionSummary() {
    final filtered = state.filteredTransactions;
    final totalAmount = filtered.fold<double>(0, (sum, t) => sum + t.amount.abs());
    final totalCount = filtered.length;
    // Group by category
    final categoryTotals = <String, double>{};
    for (final transaction in filtered) {
      categoryTotals[transaction.category.name] = 
          (categoryTotals[transaction.category.name] ?? 0) + transaction.amount.abs();
    }
    
    // Find top category
    String topCategory = 'None';
    double topAmount = 0;
    for (final entry in categoryTotals.entries) {
      if (entry.value > topAmount) {
        topAmount = entry.value;
        topCategory = entry.key;
      }
    }
    
    return {
      'totalAmount': totalAmount,
      'totalCount': totalCount,
      'topCategory': topCategory,
      'topCategoryAmount': topAmount,
      'categoryTotals': categoryTotals,
    };
  }
}

// Alias for compatibility
final transactionsViewModelProvider = transactionsViewModelControllerProvider;

/// Provider for transactions repository
@riverpod
TransactionsRepository transactionsRepository(Ref ref) {
  return TransactionsRepository();
}
