import '../repositories/email_repository_interface.dart';
import 'gmail_sync_service.dart';

class EmailDiscoveryPersistenceResult {
  const EmailDiscoveryPersistenceResult({
    required this.newlyStoredCount,
    required this.repairedCount,
    required this.skippedCount,
    required this.failedCount,
  });

  final int newlyStoredCount;
  final int repairedCount;
  final int skippedCount;
  final int failedCount;
}

/// Persists Gmail discovery results and repairs legacy rows that were saved
/// before their PDF attachment identifiers were captured.
class EmailDiscoveryPersister {
  const EmailDiscoveryPersister(this._repository);

  final EmailRepositoryInterface _repository;

  Future<EmailDiscoveryPersistenceResult> persist({
    required String userId,
    required List<GmailSearchResult> results,
  }) async {
    var newlyStored = 0;
    var repaired = 0;
    var skipped = 0;
    var failed = 0;

    for (final result in results) {
      try {
        final existing = await _repository.getEmailById(
          userId: userId,
          emailId: result.messageId,
        );
        if (existing == null) {
          await _repository.storeEmail(
            userId: userId,
            emailId: result.messageId,
            subject: result.subject,
            sender: result.from,
            receivedDate: result.receivedDate,
            hasAttachments: result.hasAttachment,
            metadata: {
              if (result.attachmentId != null)
                'attachmentId': result.attachmentId,
              if (result.attachmentFilename != null)
                'attachmentFilename': result.attachmentFilename,
            },
          );
          newlyStored++;
          continue;
        }

        final metadata = Map<String, dynamic>.from(
          existing['metadata'] as Map<String, dynamic>? ?? const {},
        );
        if (metadata['attachmentId'] == null && result.attachmentId != null) {
          metadata['attachmentId'] = result.attachmentId;
          if (metadata['attachmentFilename'] == null &&
              result.attachmentFilename != null) {
            metadata['attachmentFilename'] = result.attachmentFilename;
          }
          await _repository.updateEmailMetadata(
            userId: userId,
            emailId: result.messageId,
            metadata: metadata,
          );
          repaired++;
        } else {
          skipped++;
        }
      } catch (_) {
        failed++;
      }
    }

    return EmailDiscoveryPersistenceResult(
      newlyStoredCount: newlyStored,
      repairedCount: repaired,
      skippedCount: skipped,
      failedCount: failed,
    );
  }
}
