import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to verify database table population
class DatabaseVerificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Check if tables are populated with data
  Future<void> verifyTablesPopulated() async {
    print('\n📊 Verifying Database Table Population');
    print('=====================================');
    
    try {
      // Check users table
      await _checkUsersTable();
      
      // Check card_catalog table
      await _checkCreditCardsTable();
      
      // Check transactions table
      await _checkTransactionsTable();
      
      // Check statements table (if exists)
      await _checkStatementsTable();
      
      print('\n✅ Database verification completed');
      
    } catch (error) {
      print('\n❌ Database verification failed: $error');
      rethrow;
    }
  }

  /// Check users table
  Future<void> _checkUsersTable() async {
    try {
      final response = await _supabase
          .from('users')
          .select('id, email, created_at')
          .limit(5);
      
      final users = response as List;
      print('\n👥 USERS Table:');
      print('   Count: ${users.length} users found');
      
      if (users.isNotEmpty) {
        for (final user in users) {
          print('   - ${user['email']} (ID: ${user['id']?.toString().substring(0, 8)}...)');
        }
      } else {
        print('   ⚠️ No users found in database');
      }
      
    } catch (error) {
      print('\n❌ Error checking users table: $error');
    }
  }

  /// Check card_catalog table
  Future<void> _checkCreditCardsTable() async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('id, user_id, card_name, bank_name, created_at')
          .limit(10);
      
      final cards = response as List;
      print('\n💳 CARD_CATALOG Table:');
      print('   Count: ${cards.length} cards found');
      
      if (cards.isNotEmpty) {
        for (final card in cards) {
          print('   - ${card['card_name']} (${card['bank_name']})');
        }
      } else {
        print('   ⚠️ No credit cards found in database');
      }
      
    } catch (error) {
      print('\n❌ Error checking card_catalog table: $error');
    }
  }
  /// Check transactions table
  Future<void> _checkTransactionsTable() async {
    try {
      // Get recent transactions first
      final response = await _supabase
          .from('transactions')
          .select('id, user_id, card_id, amount, description, transaction_date, created_at')
          .order('created_at', ascending: false)
          .limit(10);
      
      final transactions = response as List;
      
      // Get total count by fetching all ids and counting them
      final allResponse = await _supabase
          .from('transactions')
          .select('id');
      
      final totalCount = (allResponse as List).length;
      
      print('\n💰 TRANSACTIONS Table:');
      print('   Total Count: $totalCount transactions');
      print('   Recent Entries: ${transactions.length}');
      
      if (transactions.isNotEmpty) {
        print('   Latest transactions:');
        for (final tx in transactions) {
          final date = DateTime.parse(tx['transaction_date']).toString().substring(0, 10);
          final amount = double.parse(tx['amount'].toString()).toStringAsFixed(2);
          final desc = tx['description'].toString();
          final truncatedDesc = desc.length > 40 ? '${desc.substring(0, 40)}...' : desc;
          print('     $date | ₹$amount | $truncatedDesc');
        }
      } else {
        print('   ⚠️ No transactions found in database');
      }
      
    } catch (error) {
      print('\n❌ Error checking transactions table: $error');
    }
  }

  /// Check statements table
  Future<void> _checkStatementsTable() async {
    try {
      final response = await _supabase
          .from('statements')
          .select('id, user_id, card_id, statement_date, total_amount, transaction_count, created_at')
          .order('created_at', ascending: false)
          .limit(5);
      
      final statements = response as List;
      print('\n📄 STATEMENTS Table:');
      print('   Count: ${statements.length} statements found');
      
      if (statements.isNotEmpty) {
        for (final stmt in statements) {
          final date = stmt['statement_date'];
          final amount = stmt['total_amount']?.toString() ?? '0';
          final txCount = stmt['transaction_count']?.toString() ?? '0';
          print('   - $date | ₹$amount | $txCount transactions');
        }
      } else {
        print('   ⚠️ No statements found in database');
      }
      
    } catch (error) {
      print('\n❌ Error checking statements table: $error');
      // This table might not exist, which is okay
    }
  }

  /// Get detailed transaction breakdown by category
  Future<void> getTransactionBreakdown() async {
    try {
      print('\n📊 Transaction Analysis:');
      print('======================');
      
      // Get transaction count by category
      final categoryResponse = await _supabase
          .from('transactions')
          .select('category, amount')
          .order('category');
      
      final transactions = categoryResponse as List;
      final categoryTotals = <String, double>{};
      final categoryCounts = <String, int>{};
      
      for (final tx in transactions) {
        final category = tx['category'] as String;
        final amount = double.parse(tx['amount'].toString());
        
        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
      }
      
      if (categoryTotals.isNotEmpty) {
        print('Category breakdown:');
        categoryTotals.forEach((category, total) {
          final count = categoryCounts[category] ?? 0;
          print('   $category: ₹${total.toStringAsFixed(2)} ($count transactions)');
        });
      }
      
      // Get transactions by date range
      final now = DateTime.now();
      final lastMonth = now.subtract(const Duration(days: 30));
      
      final recentResponse = await _supabase
          .from('transactions')
          .select('id')
          .gte('transaction_date', lastMonth.toIso8601String())
          .lte('transaction_date', now.toIso8601String());
      
      final recentCount = (recentResponse as List).length;
      print('\nRecent activity:');
      print('   Last 30 days: $recentCount transactions');
      
    } catch (error) {
      print('\n❌ Error getting transaction breakdown: $error');
    }
  }
}
