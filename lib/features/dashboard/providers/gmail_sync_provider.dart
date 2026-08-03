import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/repositories/email_repository.dart';
import '../../../core/services/gmail_sync_service.dart';
import '../../../core/services/statement_processing_service.dart' show StatementProcessingService, EmailOutcome;

/// Outcome of one Gmail sync run, shown to the user as a summary.
class GmailSyncResult {
  final int foundCount;
  final int newlyStoredCount;
  final int skippedCount;
  final int failedCount;
  final int processedAttempted;
  final int processedSucceeded;
  final int processedNeedsPassword;
  final int processedNeedsCardAssignment;
  final int processedFailed;

  const GmailSyncResult({
    required this.foundCount,
    required this.newlyStoredCount,
    required this.skippedCount,
    required this.failedCount,
    this.processedAttempted = 0,
    this.processedSucceeded = 0,
    this.processedNeedsPassword = 0,
    this.processedNeedsCardAssignment = 0,
    this.processedFailed = 0,
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

  Future<void> syncGmail({int lookbackDays = 30}) async {
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
        final after = DateTime.now().subtract(Duration(days: lookbackDays));
        final results = await gmailService.searchStatementEmails(after: after);

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

        final userName =
            session!.user.userMetadata?['full_name'] as String? ?? 'there';

        final processingService = StatementProcessingService(
          gmailService: gmailService,
          supabaseClient: ref.read(supabaseClientProvider),
          userId: userId,
          userEmail: session.user.email ?? '',
          userName: userName,
        );
        final processingResult = await processingService.processUnprocessedEmails();

        state = AsyncValue.data(GmailSyncResult(
          foundCount: results.length,
          newlyStoredCount: newlyStored,
          skippedCount: skipped,
          failedCount: failed,
          processedAttempted: processingResult.totalAttempted,
          processedSucceeded: processingResult.succeeded,
          processedNeedsPassword: processingResult.needsPassword,
          processedNeedsCardAssignment: processingResult.needsCardAssignment,
          processedFailed: processingResult.failed,
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

/// Emails whose statement bank couldn't be matched to a card and needs the
/// user to pick one before it can be parsed and stored.
final pendingCardAssignmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return [];
  return EmailRepository().getEmailsNeedingCardAssignment(userId);
});

/// Assigns a previously-ambiguous bank's statement email to a card, then
/// reprocesses just that email so it's parsed and stored immediately.
/// Future emails from the same bank will auto-resolve to this same card.
class CardAssignmentNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Resolves a pending email using a card_catalog entry rather than an
  /// existing user_card: reuses the user's matching card if they already
  /// have one for that exact catalog product, otherwise adds it as a new
  /// card first (so the statement always attaches to a real, trackable
  /// card of the correct variant, not a guess).
  Future<void> resolveWithCatalogEntry({
    required Map<String, dynamic> email,
    required String catalogCardId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final userId = ref.read(supabaseClientProvider).auth.currentSession?.user.id;
      if (userId == null) {
        throw const NoGmailTokenException('No session found. Please sign back in.');
      }

      final cardsRepo = ref.read(cardsRepositoryProvider);
      final existingCards = await cardsRepo.getUserCards(userId);
      final existing = existingCards.where((c) => c.catalogCardId == catalogCardId).firstOrNull;

      final userCardId = existing?.id ??
          (await cardsRepo.addUserCard(userId: userId, catalogCardId: catalogCardId)).id;

      await resolve(email: email, userCardId: userCardId);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> resolve({
    required Map<String, dynamic> email,
    required String userCardId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      final accessToken = session?.providerToken;
      final userId = session?.user.id;
      if (accessToken == null || userId == null) {
        throw const NoGmailTokenException(
          'No Google session token found. Please sign out and sign back in.',
        );
      }

      final emailRepo = EmailRepository();
      final bankDetected = email['bank_detected'] as String? ?? '';

      // Clear the needsCardAssignment flag and let the next processing pass
      // pick this email back up now that its bank has a resolution on file.
      await emailRepo.updateEmailStatus(
        userId: userId,
        emailId: email['email_id'] as String,
        processed: false,
        bankDetected: bankDetected,
      );

      final gmailService = GmailSyncService(accessToken);
      try {
        final userName = session!.user.userMetadata?['full_name'] as String? ?? 'there';
        final processingService = StatementProcessingService(
          gmailService: gmailService,
          supabaseClient: ref.read(supabaseClientProvider),
          userId: userId,
          userEmail: session.user.email ?? '',
          userName: userName,
        );
        final outcome = await processingService.processSpecificEmail(
          emailId: email['email_id'] as String,
          userCardId: userCardId,
        );
        if (outcome != EmailOutcome.succeeded && outcome != EmailOutcome.needsPassword) {
          throw Exception('Failed to reprocess statement (outcome: $outcome)');
        }
      } finally {
        gmailService.dispose();
      }

      state = const AsyncValue.data(null);
      ref.invalidate(pendingCardAssignmentsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final cardAssignmentProvider =
    AsyncNotifierProvider<CardAssignmentNotifier, void>(CardAssignmentNotifier.new);
