import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/system/eval_models.dart';
import 'package:cardcompass/features/admin2/system/eval_runs_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const runId = '00000000-0000-4000-8000-000000000010';
EvalConfig config() => const EvalConfig(
  key: 'gemini-3.6-flash-recommendation-v1',
  role: EvalConfigRole.candidate,
  feature: EvalFeature.recommendation,
  provider: 'gemini',
  model: 'gemini-3.6-flash',
  promptVersion: 'recommendation-v1',
  taskScope: 'fixed_selection_explanation_and_arithmetic',
  estimatedMaximumCostUsd: .03,
  scopeNote: 'Does not evaluate ranking.',
);
EvalRun run({String status = 'completed', String id = runId}) => EvalRun(
  id: id,
  datasetVersion: 12,
  feature: EvalFeature.recommendation,
  taskScope: 'fixed_selection_explanation_and_arithmetic',
  scopeNote: 'Does not evaluate ranking.',
  baselineConfigKey: 'captured-production-v1',
  candidateConfigKey: config().key,
  judgeConfigKey: 'gemini-3.6-flash-blind-judge-v1',
  status: status,
  maximumCaseCount: 10,
  costCeilingUsd: .4,
  latencyCeilingMs: 5000,
  aggregateMetrics: const {
    'case_count': 2,
    'regressions': 0,
    'severe_regressions': 0,
  },
  tokenUsage: const {'candidate_input': 10, 'candidate_output': 4},
  estimatedCostUsd: .02,
  safeFailureCategory: null,
  createdAt: DateTime.utc(2026, 8, 19),
  startedAt: DateTime.utc(2026, 8, 19),
  completedAt: DateTime.utc(2026, 8, 19, 0, 2),
  updatedAt: DateTime.utc(2026, 8, 19, 0, 2),
);
EvalRunDetail runDetail() => EvalRunDetail(
  run: run(),
  metrics: const EvalMetrics(
    baselinePassRate: .5,
    candidatePassRate: 1,
    p95CandidateLatencyMs: 30,
    manualReviewCount: 0,
  ),
  decision: EvalDecision.candidateSupported,
  blockers: const [],
  results: const [],
  resultPage: 1,
  resultLimit: 25,
  resultTotal: 0,
);

final class EvalTestSource implements EvalDataSource {
  int runsCalls = 0;
  final starts = <EvalStartRequest>[];
  int cancels = 0;
  int resumes = 0;
  String? lastStatus;
  Object? nextError;
  final detailRequests = <(String, int)>[];
  String currentRunId = runId;
  bool emptyCandidates = false;
  bool pageSpecificRuns = false;
  @override
  Future<EvalConfigCatalog> configs() async => EvalConfigCatalog(
    datasetVersion: 12,
    baseline: const EvalConfig(
      key: 'captured-production-v1',
      role: EvalConfigRole.baseline,
      feature: EvalFeature.all,
      provider: 'captured',
      model: 'captured-production',
      promptVersion: 'captured-production-v1',
      taskScope: 'captured_production_output',
      estimatedMaximumCostUsd: 0,
      scopeNote: null,
    ),
    judge: const EvalConfig(
      key: 'gemini-3.6-flash-blind-judge-v1',
      role: EvalConfigRole.judge,
      feature: EvalFeature.recommendation,
      provider: 'gemini',
      model: 'gemini-3.6-flash',
      promptVersion: 'blind-judge-v1',
      taskScope: 'blind_output_comparison',
      estimatedMaximumCostUsd: .01,
      scopeNote: null,
    ),
    candidates: emptyCandidates
        ? []
        : [
            const EvalConfig(
              key: 'gemini-statement',
              role: EvalConfigRole.candidate,
              feature: EvalFeature.statementProcessing,
              provider: 'gemini',
              model: 'flash',
              promptVersion: 's1',
              taskScope: 'statement_classification',
              estimatedMaximumCostUsd: .01,
              scopeNote: null,
            ),
            const EvalConfig(
              key: 'gemini-card',
              role: EvalConfigRole.candidate,
              feature: EvalFeature.cardData,
              provider: 'gemini',
              model: 'flash',
              promptVersion: 'c1',
              taskScope: 'catalog_identity_and_benefit_extraction',
              estimatedMaximumCostUsd: .02,
              scopeNote: null,
            ),
            config(),
          ],
  );
  @override
  Future<EvalRunsPage> runs({
    int page = 1,
    int limit = 20,
    String? status,
    EvalFeature? feature,
  }) async {
    runsCalls++;
    lastStatus = status;
    if (nextError case final e?) {
      nextError = null;
      throw e;
    }
    final id = pageSpecificRuns
        ? '00000000-0000-4000-8000-${page.toString().padLeft(12, '0')}'
        : currentRunId;
    return EvalRunsPage(
      items: [run(id: id)],
      page: page,
      limit: limit,
      total: pageSpecificRuns ? 41 : 1,
    );
  }

  @override
  Future<EvalRunDetail> detail(
    String id, {
    int resultPage = 1,
    int resultLimit = 25,
  }) async {
    detailRequests.add((id, resultPage));
    final base = runDetail();
    return EvalRunDetail(
      run: base.run,
      metrics: base.metrics,
      decision: base.decision,
      blockers: base.blockers,
      results: base.results,
      resultPage: resultPage,
      resultLimit: resultLimit,
      resultTotal: 126,
    );
  }

  @override
  Future<EvalRunReceipt> start(EvalStartRequest request) async {
    starts.add(request);
    return const EvalRunReceipt(runId: runId, status: 'queued', caseCount: 2);
  }

  @override
  Future<EvalRunReceipt> cancel(String id, String observed) async {
    cancels++;
    return const EvalRunReceipt(runId: runId, status: 'cancelled');
  }

  @override
  Future<EvalRunReceipt> resumeFailed(String id, String observed) async {
    resumes++;
    return const EvalRunReceipt(runId: runId, status: 'queued');
  }
}

Future<void> pump(
  WidgetTester tester,
  EvalTestSource source, {
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
        body: EvalRunsPanel(
          source: source,
          onAuthenticationRequired: auth,
          onAccessDenied: denied,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide decision view shows scope metrics and never deploys', (
    tester,
  ) async {
    final source = EvalTestSource();
    await pump(tester, source);
    expect(find.byKey(const Key('eval-wide-layout')), findsOneWidget);
    expect(find.text('Candidate supported'), findsOneWidget);
    expect(find.text('Does not evaluate ranking.'), findsWidgets);
    expect(find.textContaining('Baseline 50%'), findsOneWidget);
    expect(find.textContaining(r'$0.020000'), findsOneWidget);
    expect(find.textContaining('Deploy'), findsNothing);
  });
  testWidgets('390px drills into selected run and returns', (tester) async {
    final source = EvalTestSource();
    await pump(tester, source, size: const Size(390, 844));
    expect(find.byKey(const Key('eval-compact-layout')), findsOneWidget);
    await tester.tap(find.text('Recommendation').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('eval-detail')), findsOneWidget);
    await tester.tap(find.text('Back to runs'));
    await tester.pumpAndSettle();
    expect(find.text('Start evaluation'), findsOneWidget);
  });
  testWidgets('start confirmation states cases cost latency and refreshes', (
    tester,
  ) async {
    final source = EvalTestSource();
    await pump(tester, source);
    expect(find.text('Start evaluation'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start evaluation'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('eval-config-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommendation').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('fixed_selection_explanation_and_arithmetic'),
      findsOneWidget,
    );
    expect(find.text('Does not evaluate ranking.'), findsWidgets);
    await tester.tap(find.text('Start evaluation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10 cases'), findsWidgets);
    expect(find.textContaining(r'$0.400000'), findsWidgets);
    expect(find.textContaining('5000 ms'), findsWidgets);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Start evaluation').last,
    );
    await tester.pumpAndSettle();
    expect(source.starts, hasLength(1));
    expect(source.starts.single.candidate.key, config().key);
    expect(source.runsCalls, greaterThan(1));
  });
  testWidgets(
    'explicit selector can start every family with its exact config',
    (tester) async {
      for (final label in [
        'Statement processing',
        'Card data',
        'Recommendation',
      ]) {
        final source = EvalTestSource();
        await pump(tester, source, size: const Size(390, 844));
        await tester.tap(find.byKey(const Key('eval-config-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start evaluation'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Start evaluation').last,
        );
        await tester.pumpAndSettle();
        expect(
          source.starts.single.candidate.feature,
          [
            EvalFeature.statementProcessing,
            EvalFeature.cardData,
            EvalFeature.recommendation,
          ][[
            'Statement processing',
            'Card data',
            'Recommendation',
          ].indexOf(label)],
        );
      }
    },
  );
  testWidgets('case result pagination retains run and resets on selection', (
    tester,
  ) async {
    final source = EvalTestSource();
    await pump(tester, source);
    expect(find.text('Results 1–25 of 126'), findsOneWidget);
    await tester.tap(find.byKey(const Key('eval-results-next')));
    await tester.pumpAndSettle();
    expect(source.detailRequests.last, (runId, 2));
    expect(find.text('Results 26–50 of 126'), findsOneWidget);
  });
  testWidgets('implicit run replacement resets case evidence to page one', (
    tester,
  ) async {
    final source = EvalTestSource();
    await pump(tester, source);
    await tester.tap(find.byKey(const Key('eval-results-next')));
    await tester.pumpAndSettle();
    source.currentRunId = '00000000-0000-4000-8000-000000000011';
    await tester.tap(find.byKey(const Key('eval-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queued').last);
    await tester.pumpAndSettle();
    expect(source.detailRequests.last, (source.currentRunId, 1));
    expect(find.text('Results 1–25 of 126'), findsOneWidget);
  });
  testWidgets('run-list pagination selects new run at result page one', (
    tester,
  ) async {
    final source = EvalTestSource()..pageSpecificRuns = true;
    await pump(tester, source);
    await tester.tap(find.byKey(const Key('eval-results-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next evaluation runs'));
    await tester.pumpAndSettle();
    expect(source.detailRequests.last, (
      '00000000-0000-4000-8000-000000000002',
      1,
    ));
    await tester.tap(find.byTooltip('Previous evaluation runs'));
    await tester.pumpAndSettle();
    expect(source.detailRequests.last, (
      '00000000-0000-4000-8000-000000000001',
      1,
    ));
  });
  testWidgets('catalog removal clears stale candidate and disables start', (
    tester,
  ) async {
    final source = EvalTestSource();
    await pump(tester, source);
    await tester.tap(find.byKey(const Key('eval-config-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card data').last);
    await tester.pumpAndSettle();
    source.emptyCandidates = true;
    await tester.tap(find.byKey(const Key('eval-refresh')));
    await tester.pumpAndSettle();
    expect(
      find.text('Select an available candidate to preflight the run.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start evaluation'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'stale refresh retains loaded run and auth effects are forwarded',
    (tester) async {
      final source = EvalTestSource();
      var auth = 0;
      await pump(tester, source, auth: () async => auth++);
      source.nextError = AdminAuthenticationRequired();
      await tester.tap(find.byKey(const Key('eval-refresh')));
      await tester.pumpAndSettle();
      expect(auth, 1);
      expect(find.text('Recommendation'), findsWidgets);
      expect(find.textContaining('last loaded'), findsOneWidget);
    },
  );
  testWidgets('status filter reloads from the server', (tester) async {
    final source = EvalTestSource();
    await pump(tester, source);
    await tester.tap(find.byKey(const Key('eval-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queued').last);
    await tester.pumpAndSettle();
    expect(source.lastStatus, 'queued');
    expect(source.runsCalls, greaterThan(1));
  });
}
