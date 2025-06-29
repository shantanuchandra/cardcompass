import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/features/transactions/data/transactions_repository.dart';

/// Provider for transactions view model
final transactionsViewModelProvider = StateNotifierProvider<TransactionsViewModel, TransactionsViewState>((ref) {
  return TransactionsViewModel(ref);
});

/// Provider for transactions repository
final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  return TransactionsRepository();
});

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
}

/// Date range for filtering
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});
}

/// Transactions view model
class TransactionsViewModel extends StateNotifier<TransactionsViewState> {
  final Ref _ref;

  TransactionsViewModel(this._ref) : super(const TransactionsViewState());

  /// Load transactions for user
  Future<void> loadTransactions(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      final repository = _ref.read(transactionsRepositoryProvider);
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
