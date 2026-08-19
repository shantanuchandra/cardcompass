import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/repositories/email_repository.dart';
import '../../../core/services/email_discovery_persister.dart';
import '../../../core/services/gmail_sync_service.dart';
import '../../../core/services/statement_processing_service.dart'
    show
        StatementProcessingService,
        StatementProcessingIssue,
        EmailOutcome,
        metadataAfterCardAssignment;

const gmailSyncLookbackDays = <String, int>{
  '7d': 7,
  '30d': 30,
  '60d': 60,
  '90d': 90,
  '8mo': 240,
  '1yr': 365,
};

/// Outcome of one Gmail sync run, shown to the user as a summary.
class GmailSyncResult {
  final int foundCount;
  final int newlyStoredCount;
  final int repairedCount;
  final int skippedCount;
  final int failedCount;
  final int processedAttempted;
  final int processedSucceeded;
  final int processedNeedsPassword;
  final int processedNeedsCardAssignment;
  final int processedCardDiscoveryQueued;
  final int processedFailed;
  final List<StatementProcessingIssue> issues;

  const GmailSyncResult({
    required this.foundCount,
    required this.newlyStoredCount,
    this.repairedCount = 0,
    required this.skippedCount,
    required this.failedCount,
    this.processedAttempted = 0,
    this.processedSucceeded = 0,
    this.processedNeedsPassword = 0,
    this.processedNeedsCardAssignment = 0,
    this.processedCardDiscoveryQueued = 0,
    this.processedFailed = 0,
    this.issues = const [],
  });

  String get summaryMessage {
    final discoveryParts = <String>[
      '$newlyStoredCount new',
      if (repairedCount > 0) '$repairedCount repaired',
      if (failedCount > 0) '$failedCount could not be saved',
    ];
    final processingParts = <String>[
      '$processedSucceeded succeeded',
      if (processedNeedsPassword > 0)
        '$processedNeedsPassword ${processedNeedsPassword == 1 ? 'needs' : 'need'} a password',
      if (processedNeedsCardAssignment > 0)
        '$processedNeedsCardAssignment ${processedNeedsCardAssignment == 1 ? 'needs' : 'need'} a card assigned',
      if (processedCardDiscoveryQueued > 0)
        '$processedCardDiscoveryQueued ${processedCardDiscoveryQueued == 1 ? 'card is' : 'cards are'} being identified',
      if (processedFailed > 0) '$processedFailed failed',
    ];
    final details = issues.isEmpty ? '' : ' View bank/card details.';
    return 'Found $foundCount statement emails: ${discoveryParts.join(', ')}. '
        'Processed $processedAttempted: ${processingParts.join(', ')}.$details';
  }
}

/// Thrown when there is no usable Google access token to call Gmail with.
class NoGmailTokenException implements Exception {
  final String message;
  const NoGmailTokenException(this.message);
  @override
  String toString() => message;
}

class GmailUnavailableException implements Exception {
  const GmailUnavailableException();
}

class AdminOperationRequest {
  const AdminOperationRequest({
    required this.id,
    required this.operationType,
    required this.claimToken,
  });
  final String id;
  final String operationType;
  final String claimToken;
}

abstract interface class AdminOperationRequestRepository {
  Future<AdminOperationRequest?> claimNext();
  Future<void> complete({
    required String requestId,
    required String claimToken,
    required bool succeeded,
    String? safeFailureCategory,
  });
  Future<void> renew({required String requestId, required String claimToken});
}

class _SupabaseAdminOperationRequestRepository
    implements AdminOperationRequestRepository {
  const _SupabaseAdminOperationRequestRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<AdminOperationRequest?> claimNext() async {
    final value = await _client.rpc(
      'claim_my_admin_operation_request',
      params: const {'_operation_type': 'gmail_sync'},
    );
    if (value == null) return null;
    if (value is! Map ||
        value['id'] is! String ||
        value['operation_type'] != 'gmail_sync' ||
        value['claim_token'] is! String ||
        (value['claim_token'] as String).isEmpty) {
      throw const FormatException('Malformed operation request.');
    }
    return AdminOperationRequest(
      id: value['id'] as String,
      operationType: value['operation_type'] as String,
      claimToken: value['claim_token'] as String,
    );
  }

  @override
  Future<void> complete({
    required String requestId,
    required String claimToken,
    required bool succeeded,
    String? safeFailureCategory,
  }) async {
    await _client.rpc(
      'complete_my_admin_operation_request',
      params: {
        '_request_id': requestId,
        '_claim_token': claimToken,
        '_succeeded': succeeded,
        '_safe_failure_category': safeFailureCategory,
      },
    );
  }

  @override
  Future<void> renew({
    required String requestId,
    required String claimToken,
  }) async {
    await _client.rpc(
      'renew_my_admin_operation_request',
      params: {'_request_id': requestId, '_claim_token': claimToken},
    );
  }
}

class GmailSessionSnapshot {
  const GmailSessionSnapshot({
    required this.userId,
    required this.sessionKey,
    required this.providerToken,
  });
  final String? userId;
  final String? sessionKey;
  final String? providerToken;
}

typedef OperationLeaseGuard = Future<void> Function();
typedef GmailSyncExecutor =
    Future<GmailSyncResult> Function(
      GmailSessionSnapshot session,
      int lookbackDays,
      OperationLeaseGuard leaseGuard,
    );

abstract interface class LeaseHeartbeatHandle {
  void cancel();
}

abstract interface class LeaseHeartbeatScheduler {
  LeaseHeartbeatHandle periodic(
    Duration interval,
    Future<void> Function() callback,
  );
}

class _TimerHeartbeatHandle implements LeaseHeartbeatHandle {
  const _TimerHeartbeatHandle(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}

class _TimerHeartbeatScheduler implements LeaseHeartbeatScheduler {
  const _TimerHeartbeatScheduler();
  @override
  LeaseHeartbeatHandle periodic(
    Duration interval,
    Future<void> Function() callback,
  ) {
    return _TimerHeartbeatHandle(
      Timer.periodic(interval, (_) => unawaited(callback())),
    );
  }
}

final leaseHeartbeatSchedulerProvider = Provider<LeaseHeartbeatScheduler>(
  (_) => const _TimerHeartbeatScheduler(),
);

class OperationLeaseLostException implements Exception {
  const OperationLeaseLostException();
}

class _LeaseAttempt {
  bool lost = false;
  LeaseHeartbeatHandle? heartbeat;

  void fenceAndCancel() {
    lost = true;
    heartbeat?.cancel();
    heartbeat = null;
  }
}

final adminOperationRequestRepositoryProvider =
    Provider<AdminOperationRequestRepository>(
      (ref) => _SupabaseAdminOperationRequestRepository(
        ref.watch(supabaseClientProvider),
      ),
    );

final gmailSessionSnapshotProvider = Provider<GmailSessionSnapshot>((ref) {
  ref.watch(authStateProvider);
  final session = ref.watch(supabaseClientProvider).auth.currentSession;
  return GmailSessionSnapshot(
    userId: session?.user.id,
    sessionKey: session == null
        ? null
        : '${session.user.id}:${identityHashCode(session)}',
    providerToken: session?.providerToken,
  );
});

final gmailSyncExecutorProvider = Provider<GmailSyncExecutor>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (session, lookbackDays, leaseGuard) => _executeGmailSync(
    client: client,
    session: session,
    lookbackDays: lookbackDays,
    leaseGuard: leaseGuard,
  );
});

Future<GmailSyncResult> _executeGmailSync({
  required SupabaseClient client,
  required GmailSessionSnapshot session,
  required int lookbackDays,
  required OperationLeaseGuard leaseGuard,
}) async {
  final accessToken = session.providerToken;
  final userId = session.userId;
  if (accessToken == null || userId == null) {
    throw const NoGmailTokenException(
      'No Google session token found. Please sign out and sign back in '
      'to enable Gmail sync.',
    );
  }

  final gmailService = GmailSyncService(accessToken);
  final emailRepo = EmailRepository();
  try {
    await leaseGuard();
    final after = DateTime.now().subtract(Duration(days: lookbackDays));
    final results = await gmailService.searchStatementEmails(after: after);
    await leaseGuard();
    final persistence = await EmailDiscoveryPersister(
      emailRepo,
    ).persist(userId: userId, results: results);
    await leaseGuard();
    final authSession = client.auth.currentSession;
    final userName =
        authSession?.user.userMetadata?['full_name'] as String? ?? 'there';
    final processingService = StatementProcessingService(
      gmailService: gmailService,
      supabaseClient: client,
      userId: userId,
      userEmail: authSession?.user.email ?? '',
      userName: userName,
    );
    final processingResult = await processingService.processUnprocessedEmails(
      allowedEmailIds: results.map((result) => result.messageId).toSet(),
    );
    await leaseGuard();
    return GmailSyncResult(
      foundCount: results.length,
      newlyStoredCount: persistence.newlyStoredCount,
      repairedCount: persistence.repairedCount,
      skippedCount: persistence.skippedCount,
      failedCount: persistence.failedCount,
      processedAttempted: processingResult.totalAttempted,
      processedSucceeded: processingResult.succeeded,
      processedNeedsPassword: processingResult.needsPassword,
      processedNeedsCardAssignment: processingResult.needsCardAssignment,
      processedCardDiscoveryQueued: processingResult.discoveryQueued,
      processedFailed: processingResult.failed,
      issues: processingResult.issues,
    );
  } finally {
    gmailService.dispose();
  }
}

class GmailSyncNotifier extends AsyncNotifier<GmailSyncResult?> {
  Future<void>? _queuedInitialization;
  String? _initializingSessionKey;
  String? _activeSessionKey;
  var _generation = 0;
  _LeaseAttempt? _activeLease;

  @override
  Future<GmailSyncResult?> build() async {
    ref.onDispose(_cancelHeartbeat);
    ref.listen<GmailSessionSnapshot>(gmailSessionSnapshotProvider, (
      previous,
      next,
    ) {
      if (previous?.sessionKey != next.sessionKey ||
          previous?.userId != next.userId) {
        _resetForSession(next);
      }
    });
    return null;
  }

  void _resetForSession(GmailSessionSnapshot session) {
    _activeLease?.fenceAndCancel();
    _activeLease = null;
    _generation++;
    _activeSessionKey = session.sessionKey;
    _queuedInitialization = null;
    _initializingSessionKey = null;
    state = const AsyncValue.data(null);
  }

  Future<void> initializeQueuedRecovery() {
    final session = ref.read(gmailSessionSnapshotProvider);
    if (session.userId == null || session.sessionKey == null) {
      if (_activeSessionKey != null) _resetForSession(session);
      return Future.value();
    }
    if (_activeSessionKey != session.sessionKey) {
      _resetForSession(session);
    }
    final existing = _queuedInitialization;
    if (existing != null && _initializingSessionKey == session.sessionKey) {
      return existing;
    }

    final generation = _generation;
    late final Future<void> initialization;
    initialization = _initializeQueuedRecovery(session, generation)
        .whenComplete(() {
          if (identical(_queuedInitialization, initialization)) {
            _queuedInitialization = null;
            _initializingSessionKey = null;
          }
        });
    _initializingSessionKey = session.sessionKey;
    _queuedInitialization = initialization;
    return initialization;
  }

  Future<void> _initializeQueuedRecovery(
    GmailSessionSnapshot session,
    int generation,
  ) async {
    try {
      final request = await ref
          .read(adminOperationRequestRepositoryProvider)
          .claimNext();
      if (request == null) return;
      if (!_isCurrent(session, generation)) {
        // The claim belongs to whichever authenticated owner the RPC saw.
        // After an identity change, never complete it as the new user; its
        // short server lease makes it safely reclaimable by the owner.
        return;
      }
      state = const AsyncValue.loading();
      final result = await _runQueued(request, session);
      if (_isCurrent(session, generation)) {
        state = AsyncValue.data(result);
      }
    } catch (error, stackTrace) {
      if (_isCurrent(session, generation)) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  bool _isCurrent(GmailSessionSnapshot session, int generation) {
    return generation == _generation &&
        session.sessionKey == _activeSessionKey &&
        ref.read(gmailSessionSnapshotProvider).sessionKey == session.sessionKey;
  }

  Future<GmailSyncResult?> _runQueued(
    AdminOperationRequest request,
    GmailSessionSnapshot session,
  ) async {
    final repository = ref.read(adminOperationRequestRepositoryProvider);
    var succeeded = false;
    String? category;
    final attempt = _LeaseAttempt();
    _activeLease = attempt;
    Future<void> renewAndFence() async {
      if (attempt.lost ||
          ref.read(gmailSessionSnapshotProvider).sessionKey !=
              session.sessionKey) {
        attempt.lost = true;
        throw const OperationLeaseLostException();
      }
      try {
        await repository.renew(
          requestId: request.id,
          claimToken: request.claimToken,
        );
      } catch (_) {
        attempt.lost = true;
        throw const OperationLeaseLostException();
      }
    }

    Future<void> heartbeat() async {
      try {
        await renewAndFence();
      } on OperationLeaseLostException {
        // The next phase checkpoint fences the active execution. A timer
        // callback must not surface an unhandled asynchronous error.
      }
    }

    attempt.heartbeat = ref
        .read(leaseHeartbeatSchedulerProvider)
        .periodic(const Duration(minutes: 2), heartbeat);
    try {
      if (session.userId == null || session.providerToken == null) {
        category = 'reauthentication_required';
        return null;
      }
      await renewAndFence();
      final result = await ref.read(gmailSyncExecutorProvider)(
        session,
        30,
        renewAndFence,
      );
      await renewAndFence();
      succeeded = true;
      return result;
    } on GmailUnavailableException {
      category = 'gmail_unavailable';
      return null;
    } on GmailAuthException {
      category = 'reauthentication_required';
      return null;
    } on OperationLeaseLostException {
      category = 'processing_failed';
      return null;
    } catch (_) {
      category = 'processing_failed';
      rethrow;
    } finally {
      attempt.heartbeat?.cancel();
      attempt.heartbeat = null;
      if (identical(_activeLease, attempt)) _activeLease = null;
      if (!attempt.lost) {
        await repository.complete(
          requestId: request.id,
          claimToken: request.claimToken,
          succeeded: succeeded,
          safeFailureCategory: category,
        );
      }
    }
  }

  void _cancelHeartbeat() {
    _activeLease?.fenceAndCancel();
    _activeLease = null;
  }

  Future<void> syncGmail({int lookbackDays = 30}) async {
    state = const AsyncValue.loading();
    try {
      final session = ref.read(gmailSessionSnapshotProvider);
      if (session.providerToken == null || session.userId == null) {
        throw const NoGmailTokenException(
          'No Google session token found. Please sign out and sign back in '
          'to enable Gmail sync.',
        );
      }
      state = AsyncValue.data(
        await ref.read(gmailSyncExecutorProvider)(
          session,
          lookbackDays,
          () async {},
        ),
      );
    } catch (e, st) {
      debugPrint('Gmail sync failed: $e');
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
      final userId = ref
          .read(supabaseClientProvider)
          .auth
          .currentSession
          ?.user
          .id;
      if (userId == null) {
        throw const NoGmailTokenException(
          'No session found. Please sign back in.',
        );
      }

      final cardsRepo = ref.read(cardsRepositoryProvider);
      final existingCards = await cardsRepo.getUserCards(userId);
      final existing = existingCards
          .where((c) => c.catalogCardId == catalogCardId)
          .firstOrNull;

      final userCardId =
          existing?.id ??
          (await cardsRepo.addUserCard(
            userId: userId,
            catalogCardId: catalogCardId,
          )).id;

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
      await emailRepo.updateEmailMetadata(
        userId: userId,
        emailId: email['email_id'] as String,
        metadata: metadataAfterCardAssignment(email['metadata'] as Map?),
      );
      await emailRepo.updateEmailStatus(
        userId: userId,
        emailId: email['email_id'] as String,
        processed: false,
        bankDetected: bankDetected,
      );

      final gmailService = GmailSyncService(accessToken);
      try {
        final userName =
            session!.user.userMetadata?['full_name'] as String? ?? 'there';
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
        if (outcome != EmailOutcome.succeeded &&
            outcome != EmailOutcome.needsPassword) {
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
    AsyncNotifierProvider<CardAssignmentNotifier, void>(
      CardAssignmentNotifier.new,
    );
