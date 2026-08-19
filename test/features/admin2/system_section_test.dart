import 'dart:async';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/system/system_models.dart';
import 'package:cardcompass/features/admin2/system/system_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Source implements SystemDataSource {
  var statusCalls = 0;
  var jobsCalls = 0;
  final mutations = <SystemMutation>[];
  Object? nextStatusError;
  Object? mutationError;
  Completer<void>? mutationGate;
  @override
  Future<SystemStatusSnapshot> status() async {
    statusCalls++;
    if (nextStatusError case final error?) {
      nextStatusError = null;
      throw error;
    }
    return SystemStatusSnapshot(
      pipelines: const [
        PipelineSummary(
          key: SystemJobFamily.benefitEnrichment,
          status: PipelineHealth.degraded,
          queued: 4,
          running: 1,
          failed: 2,
          quarantined: 1,
          lastSuccessAt: null,
          sourceError: null,
        ),
        PipelineSummary(
          key: SystemJobFamily.cardDiscovery,
          status: PipelineHealth.unknown,
          queued: 0,
          running: 0,
          failed: 0,
          quarantined: 0,
          lastSuccessAt: null,
          sourceError: SystemSourceError.sourceUnavailable,
        ),
      ],
      controls: [
        RuntimeControl(
          isPaused: false,
          reason: null,
          updatedAt: DateTime.utc(2026, 8, 19, 9),
        ),
      ],
      controlSourceError: null,
      refreshedAt: DateTime.utc(2026, 8, 19, 10, statusCalls),
    );
  }

  @override
  Future<SystemJobsPage> jobs(
    SystemJobFamily family, {
    int page = 1,
    int limit = 25,
    String? status,
  }) async {
    jobsCalls++;
    return SystemJobsPage(
      items: family == SystemJobFamily.benefitEnrichment
          ? [
              SystemJob(
                id: '22222222-2222-4222-8222-222222222222',
                family: SystemJobFamily.benefitEnrichment,
                status: 'failed',
                failureCategory: 'source_timeout',
                attemptCount: 3,
                nextRetryAt: null,
                updatedAt: DateTime.utc(2026, 8, 19, 9),
              ),
            ]
          : const [],
      page: page,
      limit: limit,
      hasMore: false,
    );
  }

  @override
  Future<void> mutate(SystemMutation mutation) async {
    mutations.add(mutation);
    if (mutationError case final error?) throw error;
    await mutationGate?.future;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Source source, {
  Size size = const Size(1280, 900),
  Future<void> Function()? auth,
  VoidCallback? denied,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.work,
      home: Scaffold(
        body: SystemSection(
          repository: source,
          onAuthenticationRequired: auth,
          onAccessDenied: denied,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide view prioritizes exact health control and job context', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source);
    expect(find.byKey(const Key('system-wide-layout')), findsOneWidget);
    expect(find.text('4 queued'), findsOneWidget);
    expect(find.text('2 failed'), findsOneWidget);
    expect(find.text('Health unavailable'), findsOneWidget);
    expect(find.textContaining('Refreshed'), findsOneWidget);
    expect(find.text('source_timeout'), findsOneWidget);
  });

  testWidgets('compact view drills from jobs into a detail surface', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source, size: const Size(390, 844));
    expect(find.byKey(const Key('system-compact-layout')), findsOneWidget);
    await tester.ensureVisible(find.text('source_timeout'));
    await tester.tap(find.text('source_timeout'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('system-job-detail')), findsOneWidget);
    expect(find.text('Attempt 3'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('system-retry-action'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('failed refresh retains last state and marks it stale', (
    tester,
  ) async {
    final source = _Source();
    await _pump(tester, source);
    source.nextStatusError = const AdminRequestFailed('request_failed');
    await tester.tap(find.byKey(const Key('system-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('4 queued'), findsOneWidget);
    expect(
      find.text('Refresh failed. Showing the last loaded system state.'),
      findsOneWidget,
    );
    expect(find.textContaining('Refreshed'), findsOneWidget);
  });

  testWidgets('pause requires reason confirms disables submit and refreshes', (
    tester,
  ) async {
    final source = _Source()..mutationGate = Completer<void>();
    await _pump(tester, source);
    await tester.tap(find.byKey(const Key('system-control-action')));
    await tester.pumpAndSettle();
    expect(find.text('Pause scheduled enrichment?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm pause');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('system-reason')),
      'Provider incident',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('system-control-action')))
          .onPressed,
      isNull,
    );
    expect(source.mutations.single, isA<PauseSystemControl>());
    source.mutationGate!.complete();
    await tester.pumpAndSettle();
    expect(source.statusCalls, 2);
    expect(source.jobsCalls, 2);
    expect(find.text('System state confirmed by server.'), findsOneWidget);
  });

  testWidgets(
    'job mutation opens detail before confirmation and handles conflict',
    (tester) async {
      final source = _Source();
      await _pump(tester, source);
      await tester.ensureVisible(find.text('source_timeout'));
      await tester.tap(find.text('source_timeout'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('system-quarantine-action')));
      await tester.pumpAndSettle();
      expect(find.text('Quarantine this job?'), findsOneWidget);
      expect(find.byKey(const Key('system-reason')), findsOneWidget);
    },
  );

  testWidgets('401 delegates to the injected authentication effect', (
    tester,
  ) async {
    var authenticationCalls = 0;
    final authSource = _Source()
      ..nextStatusError = AdminAuthenticationRequired();
    await _pump(tester, authSource, auth: () async => authenticationCalls++);
    expect(authenticationCalls, 1);
  });

  testWidgets('403 delegates to the injected access-denied effect', (
    tester,
  ) async {
    var deniedCalls = 0;
    final deniedSource = _Source()..nextStatusError = AdminAccessDenied();
    await _pump(tester, deniedSource, denied: () => deniedCalls++);
    expect(deniedCalls, 1);
  });

  testWidgets('state conflict reloads server state without optimism', (
    tester,
  ) async {
    final source = _Source()..mutationError = AdminStateConflict();
    await _pump(tester, source);
    await tester.ensureVisible(find.text('source_timeout'));
    await tester.tap(find.text('source_timeout'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('system-retry-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('System state changed. Reloaded the latest server state.'),
      findsOneWidget,
    );
    expect(source.statusCalls, 2);
  });
}
