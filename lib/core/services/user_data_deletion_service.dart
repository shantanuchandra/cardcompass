import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for deleting all user data from the database
class UserDataDeletionService {

  static final SupabaseClient _supabase = Supabase.instance.client;  /// Delete all user data from all tables
  static Future<bool> deleteAllUserData(String userId) async {
    try {
      print('🗑️ Starting deletion of all user data for user: $userId');

      // Delete in reverse dependency order to avoid foreign key constraints.
      // Chain .select() so Supabase returns the deleted rows (needed to count them).

      // 1. Transactions (reference user_cards and statements)
      final txDeleted = await _supabase
          .from('transactions')
          .delete()
          .eq('user_id', userId)
          .select('id');
      print('✅ Deleted transactions: ${(txDeleted as List).length} rows');

      // 2. Emails
      final emailDeleted = await _supabase
          .from('emails')
          .delete()
          .eq('user_id', userId)
          .select('id');
      print('✅ Deleted emails: ${(emailDeleted as List).length} rows');

      // 3. Statements
      final stmtDeleted = await _supabase
          .from('statements')
          .delete()
          .eq('user_id', userId)
          .select('id');
      print('✅ Deleted statements: ${(stmtDeleted as List).length} rows');

      // 4. User-card associations
      final ucDeleted = await _supabase
          .from('user_cards')
          .delete()
          .eq('user_id', userId)
          .select('id');
      print('✅ Deleted user_cards: ${(ucDeleted as List).length} rows');

      // card_catalog and user profile are intentionally preserved.
      print('🎉 Successfully deleted all user data (user profile preserved)');
      return true;

    } catch (error) {
      print('❌ Error deleting user data: $error');
      return false;
    }
  }

  /// Get count of user data for confirmation dialog
  static Future<Map<String, int>> getUserDataCounts(String userId) async {
    try {
      final counts = <String, int>{};

      // Use count() aggregate so we get an integer, not a list of rows.
      final txResp = await _supabase
          .from('transactions')
          .select('id')
          .eq('user_id', userId);
      counts['transactions'] = (txResp as List).length;

      final stmtResp = await _supabase
          .from('statements')
          .select('id')
          .eq('user_id', userId);
      counts['statements'] = (stmtResp as List).length;

      final emailResp = await _supabase
          .from('emails')
          .select('id')
          .eq('user_id', userId);
      counts['emails'] = (emailResp as List).length;

      final ucResp = await _supabase
          .from('user_cards')
          .select('id')
          .eq('user_id', userId);
      counts['user cards'] = (ucResp as List).length;

      return counts;

    } catch (error) {
      print('Error getting user data counts: $error');
      return {};
    }
  }
}
