import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository for managing email records in the database
class EmailRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Store email record in the database
  Future<String> storeEmail({
    required String userId,
    required String emailId,
    required String subject,
    required String sender,
    required DateTime receivedDate,
    required bool hasAttachments,
    String? bankDetected,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final emailData = {
        'user_id': userId,
        'email_id': emailId,
        'subject': subject,
        'sender': sender,
        'received_date': receivedDate.toIso8601String(),
        'has_attachments': hasAttachments,
        'processed': false,
        'bank_detected': bankDetected,
        'metadata': metadata ?? {},
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('emails')
          .insert(emailData)
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      throw Exception('Failed to store email: $e');
    }
  }

  /// Update email processing status
  Future<void> updateEmailStatus({
    required String emailId,
    required bool processed,
    String? statementId,
  }) async {    try {
      final updateData = <String, dynamic>{
        'processed': processed,
      };

      if (statementId != null) {
        updateData['statement_id'] = statementId;
      }

      await _supabase
          .from('emails')
          .update(updateData)
          .eq('email_id', emailId);
    } catch (e) {
      throw Exception('Failed to update email status: $e');
    }
  }

  /// Get emails for a user
  Future<List<Map<String, dynamic>>> getUserEmails(String userId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('*')
          .eq('user_id', userId)
          .order('received_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch user emails: $e');
    }
  }

  /// Check if email already exists
  Future<bool> emailExists(String emailId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('id')
          .eq('email_id', emailId)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get unprocessed emails
  Future<List<Map<String, dynamic>>> getUnprocessedEmails(String userId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('*')
          .eq('user_id', userId)
          .eq('processed', false)
          .order('received_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch unprocessed emails: $e');
    }
  }

  /// Get emails by bank
  Future<List<Map<String, dynamic>>> getEmailsByBank({
    required String userId,
    required String bankName,
  }) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('*')
          .eq('user_id', userId)
          .eq('bank_detected', bankName)
          .order('received_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch emails by bank: $e');
    }
  }
}
