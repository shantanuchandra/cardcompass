import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/repositories/supabase_helpers.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Supabase implementation of TransactionRepository
class SupabaseTransactionRepository implements TransactionRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
    /// Force refresh schema cache to resolve potential schema cache issues
  Future<void> refreshSchemaCache() async {
    try {
      // Perform a simple query to refresh the schema cache
      await _supabase.rpc('get_schema_version');
    } catch (e) {
      // If the function doesn't exist, do a simple query instead
      try {
        await _supabase.from('transactions').select('id').limit(1);
      } catch (innerError) {
        // Schema cache refresh failed - this is not critical
      }
    }
  }@override
  Future<List<Transaction>> getUserTransactions(String userId, {
    int? limit = 50,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? userCardId,
  }) async {
    try {      // Use RPC function to get user transactions with card details
      final response = await _supabase.rpc('get_user_transactions', params: {
        '_user_id': userId,
        '_limit': limit ?? 50,
      });
      
      final transactions = asListDynamic(response)
          .map((json) => _mapTransactionRpcResponse(json as Map<String, dynamic>))
          .toList();
      // Apply additional filters if needed
      var filteredTransactions = transactions;if (startDate != null) {
        filteredTransactions = filteredTransactions
            .where((t) => t.transactionDate.isAfter(startDate))
            .toList();
      }
      
      if (endDate != null) {
        filteredTransactions = filteredTransactions
            .where((t) => t.transactionDate.isBefore(endDate))
            .toList();
      }
      
      if (category != null) {
        filteredTransactions = filteredTransactions
            .where((t) => t.category.toString().split('.').last == category)
            .toList();
      }

      if (userCardId != null) {
        filteredTransactions = filteredTransactions
            .where((t) => t.userCardId == userCardId)
            .toList();
      }
      
      return filteredTransactions;
    } catch (error) {
      throw Exception('Failed to fetch transactions: $error');
    }
  }

  @override
  Future<void> addTransaction(Transaction transaction) async {
    try {
      // Use the RPC function to add transactions which handles the new schema
      final params = {
        '_user_id': transaction.userId,
        '_user_card_id': transaction.userCardId,
        '_amount': transaction.amount,
        '_description': transaction.description,
        '_transaction_date': transaction.transactionDate.toIso8601String(),
        '_category': transaction.category.toString().split('.').last,
        '_type': transaction.type.toString().split('.').last,
        '_currency': transaction.currency,
        '_merchant_name': transaction.merchantName,
        '_location': transaction.location,
      };
        // Don't remove null values for required parameters - let the database handle defaults
      // Only remove null values for truly optional parameters
      if (params['_location'] == null) {
        params['_location'] = null; // Keep as null, database will handle default
      }
      if (params['_merchant_name'] == null) {
        params['_merchant_name'] = null; // Keep as null, database will handle default  
      }
      
      print('Adding transaction with amount: ${transaction.amount}');
      await _supabase.rpc('add_transaction', params: params);
    } catch (error) {
      throw Exception('Failed to add transaction: $error');
    }
  }  /// Add multiple transactions in batch with duplicate prevention
  Future<void> addTransactionsBatch(List<Transaction> transactions) async {
    try {
      for (final transaction in transactions) {
        try {
          await addTransaction(transaction);
        } catch (error) {
          // Skip duplicate or invalid transactions
        }
      }
    } catch (error) {
      throw Exception('Failed to add transactions batch: $error');
    }
  }

  @override
  Future<void> updateTransaction(Transaction transaction) async {
    try {
      final updateData = transaction.toJson();
      
      // Make sure to remove id and created_at fields which shouldn't be updated
      updateData.remove('id');
      updateData.remove('created_at');
      
      await _supabase
          .from('transactions')
          .update(updateData)
          .eq('id', transaction.id);
    } catch (error) {
      throw Exception('Failed to update transaction: $error');
    }
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _supabase
          .from('transactions')
          .delete()
          .eq('id', transactionId);
    } catch (error) {
      throw Exception('Failed to delete transaction: $error');
    }
  }

  @override
  Future<Transaction?> getTransactionById(String transactionId) async {
    try {
      final response = await _supabase
          .from('user_transactions_view')  // Using the view for complete data
          .select()
          .eq('id', transactionId)
          .single();
      
      return Transaction.fromJson(response);
    } catch (error) {
      return null;
    }
  }

  @override
  Future<List<Transaction>> getTransactionsByCategory(
    String userId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase
          .from('user_transactions_view')
          .select()
          .eq('user_id', userId)
          .eq('category', category);
      
      if (startDate != null) {
        query = query.gte('transaction_date', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('transaction_date', endDate.toIso8601String());
      }
      
      final response = await query.order('transaction_date', ascending: false);
      
      return asList(response)
          .map((json) => Transaction.fromJson(json))
          .toList();
    } catch (error) {
      throw Exception('Failed to fetch transactions by category: $error');
    }
  }

  @override
  Future<Map<String, double>> getSpendingSummary(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Build date filters
      final dateFilters = <String, dynamic>{};
      if (startDate != null) {
        dateFilters['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        dateFilters['end_date'] = endDate.toIso8601String();
      }
      
      final response = await _supabase.rpc(
        'get_spending_summary',
        params: {
          'user_id': userId,
          ...dateFilters,
        },
      );
      
      final summary = <String, double>{};
      for (final item in response) {
        summary[item['category']] = item['total'].toDouble();
      }
      
      return summary;
    } catch (error) {
      throw Exception('Failed to get spending summary: $error');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getMonthlySpendingTrend(
    String userId,
    int months,
  ) async {
    try {
      final response = await _supabase.rpc(
        'get_monthly_spending_trend',
        params: {
          'user_id': userId,
          'months_count': months,
        },
      );
      
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Failed to get monthly spending trend: $error');
    }
  }

  @override
  Future<double> getTotalSpending(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    try {
      // Build filters
      final filters = <String, dynamic>{
        'user_id': userId,
      };
      
      if (startDate != null) {
        filters['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        filters['end_date'] = endDate.toIso8601String();
      }
      if (userCardId != null) {
        filters['p_user_card_id'] = userCardId;
      }
      
      final response = await _supabase.rpc(
        'get_total_spending',
        params: filters,
      );
      
      return (response as num?)?.toDouble() ?? 0.0;
    } catch (error) {
      throw Exception('Failed to get total spending: $error');
    }
  }

  @override
  Future<double> getTotalRewards(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userCardId,
  }) async {
    try {
      // Build filters
      final filters = <String, dynamic>{
        'user_id': userId,
      };
      
      if (startDate != null) {
        filters['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        filters['end_date'] = endDate.toIso8601String();
      }
      if (userCardId != null) {
        filters['p_user_card_id'] = userCardId;
      }
      
      final response = await _supabase.rpc(
        'get_total_rewards',
        params: filters,
      );
      
      return (response as num?)?.toDouble() ?? 0.0;
    } catch (error) {
      throw Exception('Failed to get total rewards: $error');
    }
  }

  @override
  Future<List<Transaction>> importTransactions(
    String userId,
    List<Map<String, dynamic>> transactionData,
  ) async {
    // TODO: Implement transaction importing - needs more RPC functions
    throw UnimplementedError('Transaction import not implemented');
  }

  @override
  Future<void> syncTransactions(String userId) async {
    // TODO: Implement sync with external sources
    throw UnimplementedError('Transaction sync not implemented');
  }

  @override
  Future<List<Transaction>> getRecentTransactions(
    String userId, {
    int limit = 10,
  }) async {
    return getUserTransactions(userId, limit: limit);
  }  /// Map transaction RPC response to Transaction model
  Transaction _mapTransactionRpcResponse(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      userId: json['user_id'],
      userCardId: json['user_card_id'],
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] ?? 'INR',
      description: json['description'] ?? '',
      merchantName: json['merchant_name'],
      category: _parseTransactionCategory(json['category']),
      type: _parseTransactionType(json['transaction_type']),
      transactionDate: DateTime.parse(json['transaction_date']),
      location: json['location'],
      rewardEarned: json['reward_earned']?.toDouble(),
      rewardType: json['reward_type'],
      metadata: json['metadata'] ?? {},
      statementId: json['statement_id']?.toString(),  // Convert UUID to string
      isRecurring: false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  /// Parse transaction category from string
  TransactionCategory _parseTransactionCategory(String? category) {
    if (category == null) return TransactionCategory.other;
    
    try {
      return TransactionCategory.values.firstWhere(
        (e) => e.toString().split('.').last == category.toLowerCase(),
        orElse: () => TransactionCategory.other,
      );
    } catch (_) {
      return TransactionCategory.other;
    }
  }

  /// Parse transaction type from string
  TransactionType _parseTransactionType(String? type) {
    if (type == null) return TransactionType.debit;
    
    try {
      return TransactionType.values.firstWhere(
        (e) => e.toString().split('.').last == type.toLowerCase(),
        orElse: () => TransactionType.debit,
      );
    } catch (_) {
      return TransactionType.debit;
    }
  }
}
