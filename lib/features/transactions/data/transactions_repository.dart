import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';

/// Repository for managing transaction data
class TransactionsRepository {
  final SupabaseTransactionRepository _transactionRepo = SupabaseTransactionRepository();
  final SupabaseCardRepository _cardRepo = SupabaseCardRepository();

  /// Get user transactions
  Future<List<Transaction>> getUserTransactions(String userId) async {
    try {
      return await _transactionRepo.getUserTransactions(userId, limit: 100);
    } catch (e) {
      // Return mock data for now if database fails
      print('Error fetching user transactions: $e');
      return [];
    }
  }

  /// Get user cards
  Future<List<CreditCard>> getUserCards(String userId) async {
    try {
      return await _cardRepo.getUserCards(userId);
    } catch (e) {
      // Return empty list if database fails
      return [];
    }
  }
}
