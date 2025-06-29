import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for deleting all user data from the database
class UserDataDeletionService {

  static final SupabaseClient _supabase = Supabase.instance.client;  /// Delete all user data from all tables
  static Future<bool> deleteAllUserData(String userId) async {
    try {
      print('🗑️ Starting deletion of all user data for user: $userId');
      
      // Delete in reverse dependency order to avoid foreign key constraints
      
      // 1. Delete transactions first (they reference user_cards)
      final transactionResult = await _supabase.from('transactions').delete().eq('user_id', userId);
      print('✅ Deleted transactions: ${transactionResult}');
      
      // 2. Delete emails (they reference statements via statement_id)
      final emailResult = await _supabase.from('emails').delete().eq('user_id', userId);
      print('✅ Deleted emails: ${emailResult}');
      
      // 3. Delete statements (they reference user_cards)
      final statementResult = await _supabase.from('statements').delete().eq('user_id', userId);
      print('✅ Deleted statements: ${statementResult}');
      
      // 4. Delete user_cards relationship table (links user to card catalog)
      final userCardResult = await _supabase.from('user_cards').delete().eq('user_id', userId);
      print('✅ Deleted user_cards relationships: ${userCardResult}');
      
      // Note: We do NOT delete from card_catalog as those are shared reference cards
      // Note: User profile is NOT deleted as per requirements
      
      print('🎉 Successfully deleted all user data (user profile preserved)');
      return true;
      
    } catch (error) {
      print('❌ Error deleting user data: $error');
      print('❌ Stack trace: ${StackTrace.current}');
      return false;
    }
  }
  /// Get count of user data for confirmation dialog
  static Future<Map<String, int>> getUserDataCounts(String userId) async {
    try {
      final counts = <String, int>{};
      
      // Count transactions
      final transactionsResponse = await _supabase
          .from('transactions')
          .select('id')
          .eq('user_id', userId);
      counts['transactions'] = (transactionsResponse as List).length;
      
      // Count statements
      final statementsResponse = await _supabase
          .from('statements')
          .select('id')
          .eq('user_id', userId);
      counts['statements'] = (statementsResponse as List).length;
      
      // Count emails
      final emailsResponse = await _supabase
          .from('emails')
          .select('id')
          .eq('user_id', userId);
      counts['emails'] = (emailsResponse as List).length;
      
      // Count user cards (user's card associations)
      final userCardsResponse = await _supabase
          .from('user_cards')
          .select('id')
          .eq('user_id', userId);
      counts['user cards'] = (userCardsResponse as List).length;
      
      return counts;
      
    } catch (error) {
      print('Error getting user data counts: $error');
      return {};
    }
  }
}
