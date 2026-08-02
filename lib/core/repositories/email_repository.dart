import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/email_repository_interface.dart';

/// Repository for managing email records in the database
class EmailRepository implements EmailRepositoryInterface {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Store email record in the database
  @override
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
  @override
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
    String? bankDetected,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'processed': processed,
      };

      if (statementId != null) {
        updateData['statement_id'] = statementId;
      }
      if (bankDetected != null) {
        updateData['bank_detected'] = bankDetected;
      }

      await _supabase
          .from('emails')
          .update(updateData)
          .eq('user_id', userId)
          .eq('email_id', emailId);
    } catch (e) {
      throw Exception('Failed to update email status: $e');
    }
  }

  /// Check if email already exists
  @override
  Future<bool> emailExists(String userId, String emailId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('id')
          .eq('user_id', userId)
          .eq('email_id', emailId)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get emails with attachments that haven't been processed into a
  /// statement yet, for the given user.
  @override
  Future<List<Map<String, dynamic>>> getUnprocessedEmails(String userId) async {
    try {
      final response = await _supabase
          .from('emails')
          .select('*')
          .eq('user_id', userId)
          .eq('processed', false)
          .eq('has_attachments', true)
          .order('received_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch unprocessed emails: $e');
    }
  }

  /// Looks up which card the user has previously assigned emails from this
  /// bank to, by joining already-resolved emails to their statement's card.
  /// Returns null if this bank has never been resolved before, meaning the
  /// caller should ask the user to clarify instead of guessing.
  Future<String?> findPreviouslyAssignedCard({
    required String userId,
    required String bankDetected,
  }) async {
    final rows = await _supabase
        .from('emails')
        .select('statement_id, statements!inner(user_card_id)')
        .eq('user_id', userId)
        .eq('bank_detected', bankDetected)
        .eq('processed', true)
        .not('statement_id', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    final statement = rows.first['statements'] as Map<String, dynamic>?;
    return statement?['user_card_id'] as String?;
  }

  /// Marks an email as needing the user to manually pick which card its
  /// statement belongs to (its bank didn't match any card on file, and no
  /// prior resolution for that bank exists yet).
  Future<void> markNeedsCardAssignment({
    required String userId,
    required String emailId,
    required String bankDetected,
  }) async {
    await _supabase
        .from('emails')
        .update({
          'processed': false,
          'bank_detected': bankDetected,
          'metadata': {'needsCardAssignment': true},
        })
        .eq('user_id', userId)
        .eq('email_id', emailId);
  }

  /// Emails whose statement bank couldn't be matched to any card and has
  /// never been resolved before — surfaced to the user for one-time
  /// clarification (see [markNeedsCardAssignment]).
  Future<List<Map<String, dynamic>>> getEmailsNeedingCardAssignment(String userId) async {
    final response = await _supabase
        .from('emails')
        .select('*')
        .eq('user_id', userId)
        .eq('processed', false)
        .contains('metadata', {'needsCardAssignment': true})
        .order('received_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}
