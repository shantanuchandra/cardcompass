/// Repository interface for the subset of email-record operations
/// [DataPipelineDebugService] depends on. Lets tests substitute a fake
/// without touching a real Supabase client.
abstract class EmailRepositoryInterface {
  /// Check if email already exists
  Future<bool> emailExists(String userId, String emailId);

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
  });

  /// Update email processing status
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
  });
}
