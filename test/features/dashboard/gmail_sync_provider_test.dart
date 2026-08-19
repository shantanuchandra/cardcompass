import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Requests implements AdminOperationRequestRepository {
  _Requests(this.request);
  final AdminOperationRequest? request;
  int claims = 0;
  final completions = <({String id, bool succeeded, String? category})>[];
  @override
  Future<AdminOperationRequest?> claimNext() async {
    claims++;
    return request;
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
          gmailSessionSnapshotProvider.overrideWithValue(
            const GmailSessionSnapshot(
              userId: 'current-user',
              providerToken: 'memory-token',
            ),
          ),
          gmailSyncExecutorProvider.overrideWithValue((session, _) async {
            calls.add(session);
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gmailSyncProvider.future);
      await container.read(gmailSyncProvider.future);
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
      await container.read(gmailSyncProvider.future);
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
          gmailSessionSnapshotProvider.overrideWithValue(
            const GmailSessionSnapshot(
              userId: 'current-user',
              providerToken: 'memory-token',
            ),
          ),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _) async => throw const GmailUnavailableException(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(gmailSyncProvider.future), isNull);
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
          gmailSessionSnapshotProvider.overrideWithValue(
            const GmailSessionSnapshot(
              userId: 'current-user',
              providerToken: 'memory-token',
            ),
          ),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _) async => throw StateError('raw provider detail'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(gmailSyncProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(requests.completions.single, (
        id: 'request-1',
        succeeded: false,
        category: 'processing_failed',
      ));
    },
  );
}
