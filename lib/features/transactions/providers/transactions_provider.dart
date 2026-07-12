import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import '../../../shared/models/transaction.dart';

part 'transactions_provider.g.dart';

@riverpod
class TransactionsNotifier extends _$TransactionsNotifier {
  late final TransactionRepository _transactionRepository;
  String? _currentUserId;

  @override
  List<Transaction> build() {
    _transactionRepository = ref.watch(transactionRepositoryProvider);
    return [];
  }

  Future<void> loadUserTransactions(String userId, {
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? cardId,
  }) async {
    try {
      _currentUserId = userId;      
      state = await _transactionRepository.getUserTransactions(
        userId,
        limit: limit,
        startDate: startDate,
        endDate: endDate,
        category: category,
        userCardId: cardId,
      );
    } catch (e) {
      print('Error loading user transactions: $e');
      state = [];
    }
  }

  // Automatically refresh transactions when user changes
  void setUserId(String? userId) {
    if (userId != null && userId != _currentUserId) {
      loadUserTransactions(userId);
    } else if (userId == null) {
      // Clear transactions when user logs out
      state = [];
      _currentUserId = null;
    }
  }

  Future<void> addTransaction(Transaction transaction) async {
    try {
      await _transactionRepository.addTransaction(transaction);
      if (_currentUserId != null) {
        await loadUserTransactions(_currentUserId!);
      }
    } catch (e) {
      print('Error adding transaction: $e');
    }
  }

  Future<void> updateTransaction(Transaction updatedTransaction) async {
    try {
      await _transactionRepository.updateTransaction(updatedTransaction);
      if (_currentUserId != null) {
        await loadUserTransactions(_currentUserId!);
      }
    } catch (e) {
      print('Error updating transaction: $e');
    }
  }

  Future<void> removeTransaction(String transactionId) async {
    try {
      await _transactionRepository.deleteTransaction(transactionId);
      if (_currentUserId != null) {
        await loadUserTransactions(_currentUserId!);
      }
    } catch (e) {
      print('Error removing transaction: $e');
    }
  }
}

// Provider for recent transactions (last 7 days)
@riverpod
List<Transaction> recentTransactions(Ref ref) {
  final transactions = ref.watch(transactionsProvider);
  final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
  return transactions.where((transaction) => transaction.transactionDate.isAfter(sevenDaysAgo)).take(3).toList();
}

// Provider for total spending this month
@riverpod
double monthlySpending(Ref ref) {
  final transactions = ref.watch(transactionsProvider);
  final now = DateTime.now();
  final firstDayOfMonth = DateTime(now.year, now.month, 1);
  
  return transactions
      .where((transaction) => 
          transaction.transactionDate.isAfter(firstDayOfMonth) && 
          transaction.type == TransactionType.debit)
      .fold(0.0, (sum, transaction) => sum + transaction.amount);
}

// Provider for total rewards earned this month
@riverpod
double monthlyRewards(Ref ref) {
  final transactions = ref.watch(transactionsProvider);
  final now = DateTime.now();
  final firstDayOfMonth = DateTime(now.year, now.month, 1);
  
  return transactions
      .where((transaction) => 
          transaction.transactionDate.isAfter(firstDayOfMonth) && 
          transaction.rewardEarned != null)
      .fold(0.0, (sum, transaction) => sum + (transaction.rewardEarned ?? 0.0));
}

// Provider for transaction by category
@riverpod
Map<TransactionCategory, double> transactionsByCategory(Ref ref) {
  final transactions = ref.watch(transactionsProvider);
  final Map<TransactionCategory, double> categoryTotals = {};
  
  for (final transaction in transactions) {
    if (transaction.type == TransactionType.debit) {
      categoryTotals[transaction.category] = 
          (categoryTotals[transaction.category] ?? 0.0) + transaction.amount;
    }
  }
  
  return categoryTotals;
}

// Provider that loads user transactions when explicitly requested
@riverpod
List<Transaction> userTransactionsForAnalytics(Ref ref, String? userId) {
  if (userId == null) return [];
  return ref.watch(transactionsProvider);
}
