import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Requests implements AdminOperationRequestRepository {
  _Requests([AdminOperationRequest? request]) : onClaim = null {
    if (request != null) requests.add(request);
  }

  _Requests.withOnClaim(AdminOperationRequest request, this.onClaim) {
    requests.add(request);
  }
  final requests = <AdminOperationRequest>[];
  final Future<void> Function()? onClaim;
  int claims = 0;
  final completions = <({String id, bool succeeded, String? category})>[];
  @override
  Future<AdminOperationRequest?> claimNext() async {
    claims++;
    await onClaim?.call();
    return requests.isEmpty ? null : requests.removeAt(0);
  }

  @override
  Future<void> complete({
    required String requestId,
    required bool succeeded,
    String? safeFailureCategory,
  }) async {
    completions.add((
      id: requestId,
      succeeded: succeeded,
      category: safeFailureCategory,
    ));
  }
}

const _result = GmailSyncResult(
  foundCount: 0,
  newlyStoredCount: 0,
  skippedCount: 0,
  failedCount: 0,
);

const _session = GmailSessionSnapshot(
  userId: 'current-user',
  sessionKey: 'session-1',
  providerToken: 'memory-token',
);

void main() {
  test(
    'dashboard initialization claims at most one request and completes its sync',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'request-1',
          operationType: 'gmail_sync',
        ),
      );
      final calls = <GmailSessionSnapshot>[];
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue((session, _) async {
            calls.add(session);
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      await Future.wait([
        container.read(gmailSyncProvider.notifier).initializeQueuedRecovery(),
        container.read(gmailSyncProvider.notifier).initializeQueuedRecovery(),
      ]);
      expect(requests.claims, 1);
      expect(calls.single.userId, 'current-user');
      expect(calls.single.providerToken, 'memory-token');
      expect(requests.completions.single, (
        id: 'request-1',
        succeeded: true,
        category: null,
      ));
    },
  );

  test(
    'queued request without current provider token reports reauthentication',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'request-1',
          operationType: 'gmail_sync',
        ),
      );
      var executions = 0;
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(
            const GmailSessionSnapshot(
              userId: 'current-user',
              sessionKey: 'session-1',
              providerToken: null,
            ),
          ),
          gmailSyncExecutorProvider.overrideWithValue((_, _) async {
            executions++;
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      expect(executions, 0);
      expect(requests.completions.single, (
        id: 'request-1',
        succeeded: false,
        category: 'reauthentication_required',
      ));
    },
  );

  test('queued row contains no user or token authority', () {
    const request = AdminOperationRequest(
      id: 'request-1',
      operationType: 'gmail_sync',
    );
    expect(request.toString(), isNot(contains('token')));
    expect(request.toString(), isNot(contains('userId')));
  });

  test(
    'provider outage is completed with only the safe unavailable category',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'request-1',
          operationType: 'gmail_sync',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _) async => throw const GmailUnavailableException(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      expect(requests.completions.single, (
        id: 'request-1',
        succeeded: false,
        category: 'gmail_unavailable',
      ));
    },
  );

  test(
    'processing failure is reported in finally and remains an error',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'request-1',
          operationType: 'gmail_sync',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _) async => throw StateError('raw provider detail'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      expect(container.read(gmailSyncProvider).error, isA<StateError>());
      expect(requests.completions.single, (
        id: 'request-1',
        succeeded: false,
        category: 'processing_failed',
      ));
    },
  );

  test(
    'a new dashboard initialization claims work queued after an empty entry',
    () async {
      final requests = _Requests();
      var executions = 0;
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue((_, _) async {
            executions++;
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gmailSyncProvider.notifier);
      await notifier.initializeQueuedRecovery();
      requests.requests.add(
        const AdminOperationRequest(id: 'later', operationType: 'gmail_sync'),
      );
      await notifier.initializeQueuedRecovery();
      expect(requests.claims, 2);
      expect(executions, 1);
    },
  );

  test(
    'sequential users and sessions use only their own current snapshot',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(id: 'one', operationType: 'gmail_sync'),
      );
      var snapshot = _session;
      final calls = <GmailSessionSnapshot>[];
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
          gmailSyncExecutorProvider.overrideWithValue((value, _) async {
            calls.add(value);
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gmailSyncProvider.notifier);
      await notifier.initializeQueuedRecovery();
      snapshot = const GmailSessionSnapshot(
        userId: 'user-two',
        sessionKey: 'session-2',
        providerToken: 'token-two',
      );
      container.invalidate(gmailSessionSnapshotProvider);
      requests.requests.add(
        const AdminOperationRequest(id: 'two', operationType: 'gmail_sync'),
      );
      await notifier.initializeQueuedRecovery();
      expect(calls.map((value) => '${value.userId}:${value.providerToken}'), [
        'current-user:memory-token',
        'user-two:token-two',
      ]);
    },
  );

  test(
    'sign-out then sign-in with a new session retriggers recovery',
    () async {
      final requests = _Requests();
      var snapshot = _session;
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
          gmailSyncExecutorProvider.overrideWithValue((_, _) async => _result),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gmailSyncProvider.notifier);
      await notifier.initializeQueuedRecovery();
      snapshot = const GmailSessionSnapshot(
        userId: null,
        sessionKey: null,
        providerToken: null,
      );
      container.invalidate(gmailSessionSnapshotProvider);
      await notifier.initializeQueuedRecovery();
      snapshot = const GmailSessionSnapshot(
        userId: 'current-user',
        sessionKey: 'session-new',
        providerToken: 'token-new',
      );
      container.invalidate(gmailSessionSnapshotProvider);
      requests.requests.add(
        const AdminOperationRequest(
          id: 'new-session',
          operationType: 'gmail_sync',
        ),
      );
      await notifier.initializeQueuedRecovery();
      expect(requests.claims, 2);
      expect(requests.completions.single.id, 'new-session');
    },
  );

  test(
    'identity changing during claim never executes with the stale token',
    () async {
      var snapshot = _session;
      late ProviderContainer container;
      final requests = _Requests.withOnClaim(
        const AdminOperationRequest(id: 'changed', operationType: 'gmail_sync'),
        () async {
          snapshot = const GmailSessionSnapshot(
            userId: 'user-two',
            sessionKey: 'session-2',
            providerToken: 'token-two',
          );
          container.invalidate(gmailSessionSnapshotProvider);
        },
      );
      var executions = 0;
      container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
          gmailSyncExecutorProvider.overrideWithValue((_, _) async {
            executions++;
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      expect(executions, 0);
      expect(requests.completions.single, (
        id: 'changed',
        succeeded: false,
        category: 'reauthentication_required',
      ));
    },
  );
}
