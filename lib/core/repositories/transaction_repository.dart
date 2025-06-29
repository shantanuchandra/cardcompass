import 'package:cardcompass/shared/models/transaction.dart';

/// Repository interface for transaction operations
abstract class TransactionRepository {
  /// Get user's transactions
  Future<List<Transaction>> getUserTransactions(String userId, {
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? userCardId,
  });

  /// Add a new transaction
  Future<void> addTransaction(Transaction transaction);

  /// Update an existing transaction
  Future<void> updateTransaction(Transaction transaction);

  /// Delete a transaction
  Future<void> deleteTransaction(String transactionId);

  /// Get transaction by ID
  Future<Transaction?> getTransactionById(String transactionId);

  /// Get transactions by category
  Future<List<Transaction>> getTransactionsByCategory(
    String userId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get spending summary by category
  Future<Map<String, double>> getSpendingSummary(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get monthly spending trend
  Future<List<Map<String, dynamic>>> getMonthlySpendingTrend(
    String userId,
    int months,
  );

  /// Get total spending for a period
  Future<double> getTotalSpending(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  });

  /// Get total rewards earned for a period
  Future<double> getTotalRewards(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  });

  /// Import transactions from external source
  Future<List<Transaction>> importTransactions(
    String userId,
    List<Map<String, dynamic>> transactionData,
  );

  /// Sync transactions with external sources
  Future<void> syncTransactions(String userId);

  /// Get recent transactions
  Future<List<Transaction>> getRecentTransactions(
    String userId, {
    int limit = 10,
  });
}
