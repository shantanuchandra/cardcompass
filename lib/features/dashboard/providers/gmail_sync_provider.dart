import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/repositories/email_repository.dart';
import '../../../core/services/gmail_sync_service.dart';

/// Outcome of one Gmail sync run, shown to the user as a summary.
class GmailSyncResult {
  final int foundCount;
  final int newlyStoredCount;
  final int skippedCount;
  final int failedCount;

  const GmailSyncResult({
    required this.foundCount,
    required this.newlyStoredCount,
    required this.skippedCount,
    required this.failedCount,
  });
}

/// Thrown when there is no usable Google access token to call Gmail with.
class NoGmailTokenException implements Exception {
  final String message;
  const NoGmailTokenException(this.message);
  @override
  String toString() => message;
}

class GmailSyncNotifier extends AsyncNotifier<GmailSyncResult?> {
  @override
  Future<GmailSyncResult?> build() async => null;

  Future<void> syncGmail() async {
    state = const AsyncValue.loading();
    try {
      final session =
          ref.read(supabaseClientProvider).auth.currentSession;
      final accessToken = session?.providerToken;
      final userId = session?.user.id;

      if (accessToken == null || userId == null) {
        throw const NoGmailTokenException(
          'No Google session token found. Please sign out and sign back in '
          'to enable Gmail sync.',
        );
      }

      final gmailService = GmailSyncService(accessToken);
      final emailRepo = EmailRepository();

      try {
        final results = await gmailService.searchStatementEmails();

        var newlyStored = 0;
        var skipped = 0;
        var failed = 0;

        for (final result in results) {
          try {
            final exists =
                await emailRepo.emailExists(userId, result.messageId);
            if (exists) {
              skipped++;
              continue;
            }
            await emailRepo.storeEmail(
              userId: userId,
              emailId: result.messageId,
              subject: result.subject,
              sender: result.from,
              receivedDate: result.receivedDate,
              hasAttachments: result.hasAttachment,
              metadata: {
                if (result.attachmentId != null) 'attachmentId': result.attachmentId,
                if (result.attachmentFilename != null) 'attachmentFilename': result.attachmentFilename,
              },
            );
            newlyStored++;
          } catch (_) {
            failed++;
          }
        }

        state = AsyncValue.data(GmailSyncResult(
          foundCount: results.length,
          newlyStoredCount: newlyStored,
          skippedCount: skipped,
          failedCount: failed,
        ));
      } finally {
        gmailService.dispose();
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final gmailSyncProvider =
    AsyncNotifierProvider<GmailSyncNotifier, GmailSyncResult?>(
  GmailSyncNotifier.new,
);
