import 'dart:async';

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
  final completions =
      <({String id, String token, bool succeeded, String? category})>[];
  final renewals = <({String id, String token})>[];
  Object? renewError;
  @override
  Future<AdminOperationRequest?> claimNext() async {
    claims++;
    await onClaim?.call();
    return requests.isEmpty ? null : requests.removeAt(0);
  }

  @override
  Future<void> complete({
    required String requestId,
    required String claimToken,
    required bool succeeded,
    String? safeFailureCategory,
  }) async {
    completions.add((
      id: requestId,
      token: claimToken,
      succeeded: succeeded,
      category: safeFailureCategory,
    ));
  }

  @override
  Future<void> renew({
    required String requestId,
    required String claimToken,
  }) async {
    renewals.add((id: requestId, token: claimToken));
    if (renewError case final error?) throw error;
  }
}

class _LeasedRequests implements AdminOperationRequestRepository {
  _LeasedRequests({required this.currentUserId, this.afterFirstClaim});

  final String? Function() currentUserId;
  final void Function()? afterFirstClaim;
  var queued = true;
  var claimed = false;
  var expired = false;
  var completed = false;
  var claims = 0;
  var _attempt = 0;
  String? currentToken;
  var renewals = 0;

  @override
  Future<AdminOperationRequest?> claimNext() async {
    claims++;
    if (currentUserId() != 'user-a' || completed) return null;
    if (!queued && !(claimed && expired)) return null;
    queued = false;
    claimed = true;
    expired = false;
    currentToken = 'lease-${++_attempt}';
    if (_attempt == 1) afterFirstClaim?.call();
    return AdminOperationRequest(
      id: 'leased-request',
      operationType: 'gmail_sync',
      claimToken: currentToken!,
    );
  }

  @override
  Future<void> complete({
    required String requestId,
    required String claimToken,
    required bool succeeded,
    String? safeFailureCategory,
  }) async {
    if (currentUserId() != 'user-a' ||
        requestId != 'leased-request' ||
        !claimed ||
        claimToken != currentToken) {
      throw StateError('state_conflict');
    }
    claimed = false;
    completed = true;
    currentToken = null;
  }

  void expire() => expired = true;

  @override
  Future<void> renew({
    required String requestId,
    required String claimToken,
  }) async {
    if (currentUserId() != 'user-a' ||
        requestId != 'leased-request' ||
        !claimed ||
        expired ||
        claimToken != currentToken) {
      throw StateError('state_conflict');
    }
    renewals++;
    expired = false;
  }
}

class _FakeHeartbeatHandle implements LeaseHeartbeatHandle {
  _FakeHeartbeatHandle(this.onCancel);
  final void Function() onCancel;
  var active = true;

  @override
  void cancel() {
    if (!active) return;
    active = false;
    onCancel();
  }
}

class _FakeHeartbeatScheduler implements LeaseHeartbeatScheduler {
  Future<void> Function()? callback;
  _FakeHeartbeatHandle? handle;
  var schedules = 0;
  var cancellations = 0;

  @override
  LeaseHeartbeatHandle periodic(
    Duration interval,
    Future<void> Function() callback,
  ) {
    expect(interval, const Duration(minutes: 2));
    schedules++;
    this.callback = callback;
    return handle = _FakeHeartbeatHandle(() => cancellations++);
  }

  Future<void> tick() async {
    if (handle?.active ?? false) await callback?.call();
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
          claimToken: 'claim-1',
        ),
      );
      final calls = <GmailSessionSnapshot>[];
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue((
            session,
            _,
            guard,
          ) async {
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
        token: 'claim-1',
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
          claimToken: 'claim-1',
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
          gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
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
        token: 'claim-1',
        succeeded: false,
        category: 'reauthentication_required',
      ));
    },
  );

  test('queued row contains no user or token authority', () {
    const request = AdminOperationRequest(
      id: 'request-1',
      operationType: 'gmail_sync',
      claimToken: 'claim-1',
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
          claimToken: 'claim-1',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _, guard) async => throw const GmailUnavailableException(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      expect(requests.completions.single, (
        id: 'request-1',
        token: 'claim-1',
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
          claimToken: 'claim-1',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _, guard) async => throw StateError('raw provider detail'),
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
        token: 'claim-1',
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
          gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
            executions++;
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gmailSyncProvider.notifier);
      await notifier.initializeQueuedRecovery();
      requests.requests.add(
        const AdminOperationRequest(
          id: 'later',
          operationType: 'gmail_sync',
          claimToken: 'claim-later',
        ),
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
        const AdminOperationRequest(
          id: 'one',
          operationType: 'gmail_sync',
          claimToken: 'claim-one',
        ),
      );
      var snapshot = _session;
      final calls = <GmailSessionSnapshot>[];
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
          gmailSyncExecutorProvider.overrideWithValue((value, _, guard) async {
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
        const AdminOperationRequest(
          id: 'two',
          operationType: 'gmail_sync',
          claimToken: 'claim-two',
        ),
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
          gmailSyncExecutorProvider.overrideWithValue(
            (_, _, guard) async => _result,
          ),
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
          claimToken: 'claim-new',
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
        const AdminOperationRequest(
          id: 'changed',
          operationType: 'gmail_sync',
          claimToken: 'claim-changed',
        ),
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
          gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
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
      expect(requests.completions, isEmpty);
    },
  );

  test('original owner re-entry reclaims an expired stranded lease', () async {
    var snapshot = const GmailSessionSnapshot(
      userId: 'user-a',
      sessionKey: 'a-1',
      providerToken: 'token-a',
    );
    late ProviderContainer container;
    late _LeasedRequests requests;
    requests = _LeasedRequests(
      currentUserId: () => snapshot.userId,
      afterFirstClaim: () {
        snapshot = const GmailSessionSnapshot(
          userId: 'user-b',
          sessionKey: 'b-1',
          providerToken: 'token-b',
        );
        container.invalidate(gmailSessionSnapshotProvider);
      },
    );
    final executions = <GmailSessionSnapshot>[];
    container = ProviderContainer(
      overrides: [
        adminOperationRequestRepositoryProvider.overrideWithValue(requests),
        gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
        gmailSyncExecutorProvider.overrideWithValue((session, _, guard) async {
          executions.add(session);
          return _result;
        }),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(gmailSyncProvider.notifier);
    await notifier.initializeQueuedRecovery();
    expect(executions, isEmpty);
    expect(requests.currentToken, 'lease-1');

    snapshot = const GmailSessionSnapshot(
      userId: 'user-a',
      sessionKey: 'a-2',
      providerToken: 'token-a-new',
    );
    container.invalidate(gmailSessionSnapshotProvider);
    await notifier.initializeQueuedRecovery();
    expect(executions, isEmpty, reason: 'an unexpired lease is not duplicated');

    requests.expire();
    await notifier.initializeQueuedRecovery();
    expect(executions.single.providerToken, 'token-a-new');
    expect(requests.completed, isTrue);
    expect(requests.currentToken, isNull);
  });

  test('an empty dashboard entry starts no heartbeat polling', () async {
    final requests = _Requests();
    final scheduler = _FakeHeartbeatScheduler();
    final container = ProviderContainer(
      overrides: [
        adminOperationRequestRepositoryProvider.overrideWithValue(requests),
        gmailSessionSnapshotProvider.overrideWithValue(_session),
        leaseHeartbeatSchedulerProvider.overrideWithValue(scheduler),
        gmailSyncExecutorProvider.overrideWithValue(
          (_, _, guard) async => _result,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(gmailSyncProvider.notifier).initializeQueuedRecovery();

    expect(requests.claims, 1);
    expect(scheduler.schedules, 0);
  });

  test(
    'heartbeat keeps one long recovery fenced across duplicate initialization',
    () async {
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'long-running',
          operationType: 'gmail_sync',
          claimToken: 'long-token',
        ),
      );
      final scheduler = _FakeHeartbeatScheduler();
      final started = Completer<void>();
      final release = Completer<void>();
      var executions = 0;
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWithValue(_session),
          leaseHeartbeatSchedulerProvider.overrideWithValue(scheduler),
          gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
            executions++;
            started.complete();
            await release.future;
            await guard();
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(gmailSyncProvider.notifier);
      final first = notifier.initializeQueuedRecovery();
      await started.future;

      for (var elapsedMinutes = 2; elapsedMinutes <= 12; elapsedMinutes += 2) {
        await scheduler.tick();
      }
      final duplicate = notifier.initializeQueuedRecovery();
      expect(identical(first, duplicate), isTrue);
      expect(executions, 1);
      expect(requests.claims, 1);
      expect(requests.renewals.length, greaterThanOrEqualTo(7));

      release.complete();
      await Future.wait([first, duplicate]);
      expect(requests.completions.single.succeeded, isTrue);
      expect(scheduler.cancellations, 1);
    },
  );

  test('renewal loss fences processing and never reports success', () async {
    final requests = _Requests(
      const AdminOperationRequest(
        id: 'loses-lease',
        operationType: 'gmail_sync',
        claimToken: 'lost-token',
      ),
    );
    final scheduler = _FakeHeartbeatScheduler();
    final started = Completer<void>();
    final release = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        adminOperationRequestRepositoryProvider.overrideWithValue(requests),
        gmailSessionSnapshotProvider.overrideWithValue(_session),
        leaseHeartbeatSchedulerProvider.overrideWithValue(scheduler),
        gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
          started.complete();
          await release.future;
          await guard();
          return _result;
        }),
      ],
    );
    addTearDown(container.dispose);
    final future = container
        .read(gmailSyncProvider.notifier)
        .initializeQueuedRecovery();
    await started.future;
    requests.renewError = StateError('token_replaced');
    await scheduler.tick();
    release.complete();
    await future;

    expect(requests.completions, isEmpty);
    expect(container.read(gmailSyncProvider).value, isNull);
    expect(scheduler.cancellations, 1);
  });

  test(
    'session change cancels heartbeat and suppresses stale completion',
    () async {
      var snapshot = _session;
      final requests = _Requests(
        const AdminOperationRequest(
          id: 'session-change',
          operationType: 'gmail_sync',
          claimToken: 'session-token',
        ),
      );
      final scheduler = _FakeHeartbeatScheduler();
      final started = Completer<void>();
      final release = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          adminOperationRequestRepositoryProvider.overrideWithValue(requests),
          gmailSessionSnapshotProvider.overrideWith((_) => snapshot),
          leaseHeartbeatSchedulerProvider.overrideWithValue(scheduler),
          gmailSyncExecutorProvider.overrideWithValue((_, _, guard) async {
            started.complete();
            await release.future;
            await guard();
            return _result;
          }),
        ],
      );
      addTearDown(container.dispose);
      final future = container
          .read(gmailSyncProvider.notifier)
          .initializeQueuedRecovery();
      await started.future;
      snapshot = const GmailSessionSnapshot(
        userId: 'other-user',
        sessionKey: 'other-session',
        providerToken: 'other-token',
      );
      container.invalidate(gmailSessionSnapshotProvider);
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.cancellations, 1);

      release.complete();
      await future;
      expect(requests.completions, isEmpty);
    },
  );
}
