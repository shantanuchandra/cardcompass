import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/shared/models/transaction.dart';

class MockTransactionRepository implements TransactionRepository {
  final List<Transaction> _transactions = MockData.transactions()
    ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

  @override
  Future<List<Transaction>> getUserTransactions(
    String userId, {
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? userCardId,
  }) async {
    var results = _transactions.where((t) {
      if (startDate != null && t.transactionDate.isBefore(startDate)) return false;
      if (endDate != null && t.transactionDate.isAfter(endDate)) return false;
      if (category != null && t.categoryString != category) return false;
      if (userCardId != null && t.userCardId != userCardId) return false;
      return true;
    }).toList();
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<void> addTransaction(Transaction transaction) async {
    _transactions.insert(0, transaction);
  }

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    final index = _transactions.indexWhere((t) => t.id == transaction.id);
    if (index != -1) _transactions[index] = transaction;
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    _transactions.removeWhere((t) => t.id == transactionId);
  }

  @override
  Future<Transaction?> getTransactionById(String transactionId) async {
    final matches = _transactions.where((t) => t.id == transactionId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<Transaction>> getTransactionsByCategory(
    String userId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return getUserTransactions(userId, category: category, startDate: startDate, endDate: endDate);
  }

  @override
  Future<Map<String, double>> getSpendingSummary(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate);
    final summary = <String, double>{};
    for (final t in txns.where((t) => t.type == TransactionType.debit)) {
      summary[t.categoryString] = (summary[t.categoryString] ?? 0) + t.amount;
    }
    return summary;
  }

  @override
  Future<List<Map<String, dynamic>>> getMonthlySpendingTrend(String userId, int months) async {
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (var i = months - 1; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(now.year, now.month - i + 1, 1);
      final spend = _transactions
          .where((t) =>
              t.type == TransactionType.debit &&
              !t.transactionDate.isBefore(monthDate) &&
              t.transactionDate.isBefore(nextMonth))
          .fold<double>(0.0, (sum, t) => sum + t.amount);
      result.add({'month': '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}', 'total': spend});
    }
    return result;
  }

  @override
  Future<double> getTotalSpending(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate, userCardId: userCardId);
    return txns.where((t) => t.type == TransactionType.debit).fold<double>(0.0, (sum, t) => sum + t.amount);
  }

  @override
  Future<double> getTotalRewards(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    final txns = await getUserTransactions(userId, startDate: startDate, endDate: endDate, userCardId: userCardId);
    return txns.fold<double>(0.0, (sum, t) => sum + (t.rewardEarned ?? 0));
  }

  @override
  Future<List<Transaction>> importTransactions(String userId, List<Map<String, dynamic>> transactionData) async {
    return [];
  }

  @override
  Future<void> syncTransactions(String userId) async {}

  @override
  Future<List<Transaction>> getRecentTransactions(String userId, {int limit = 10}) async {
    return getUserTransactions(userId, limit: limit);
  }
}
