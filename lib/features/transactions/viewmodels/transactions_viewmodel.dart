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
    final summaryByCard = <String, CardSpendSummary>{};

    for (final t in filteredTransactions) {
      final cardId = t.userCardId;
      if (cardId == null || cardId.isEmpty) continue;

      final existing = summaryByCard[cardId];
      // Every card that has at least one transaction gets an entry, even if
      // its only transactions are non-debit (e.g. credit/refund) — such a
      // card still appears in the summary with totalSpend: 0.
      final spendDelta = t.type == TransactionType.debit ? t.amount.abs() : 0;
      summaryByCard[cardId] = CardSpendSummary(
        cardId: cardId,
        totalSpend: (existing?.totalSpend ?? 0) + spendDelta,
        totalRewards: (existing?.totalRewards ?? 0) + (t.rewardEarned ?? 0),
      );
    }

    return summaryByCard;
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
