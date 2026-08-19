import 'dart:async';
import 'dart:convert';

import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/feedback/contextual_feedback_button.dart';
import 'package:cardcompass/features/feedback/contextual_feedback_sheet.dart';
import 'package:cardcompass/features/feedback/feedback_models.dart';
import 'package:cardcompass/features/feedback/feedback_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const target = TransactionFeedbackTarget(
  '20000000-0000-4000-8000-000000000001',
);

void main() {
  test('shared preview boundary caps code points and UTF-8 bytes', () {
    final bounded = boundedFeedbackPreview(
      '${List.filled(200, '₹').join()}transaction',
    );
    expect(bounded.runes.length, lessThanOrEqualTo(120));
    expect(bounded.codeUnits.length, isPositive);
    expect(
      Uri.encodeComponent(bounded).replaceAll(RegExp(r'%..'), 'x').length,
      isPositive,
    );
    expect(const Utf8Encoder().convert(bounded).length, lessThanOrEqualTo(256));
  });

  testWidgets('button and sheet apply the same shared preview boundary', (
    tester,
  ) async {
    final raw = '${List.filled(200, '₹').join()} · transaction';
    final bounded = boundedFeedbackPreview(raw);
    await _pump(
      tester,
      repository: _FakeRepository(),
      child: ContextualFeedbackButton(target: target, preview: raw),
    );
    expect(
      find.bySemanticsLabel('Give feedback about $bounded'),
      findsOneWidget,
    );
    await tester.tap(find.byType(ContextualFeedbackButton));
    await tester.pumpAndSettle();
    expect(find.text(bounded), findsOneWidget);
    expect(find.text(raw), findsNothing);
  });

  testWidgets('button is accessible and opens feedback for the exact preview', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(),
      child: const ContextualFeedbackButton(
        target: target,
        preview: 'Coffee ¹420 · Food & dining',
      ),
    );

    expect(
      find.bySemanticsLabel('Give feedback about Coffee ¹420'),
      findsOneWidget,
    );
    final size = tester.getSize(find.byType(ContextualFeedbackButton));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(ContextualFeedbackButton));
    await tester.pumpAndSettle();

    expect(find.text('Coffee ¹420 · Food & dining'), findsOneWidget);
    expect(find.text('Tell us what should be different'), findsOneWidget);
    expect(find.textContaining('model'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('requires 10 characters and shows a live count', (tester) async {
    await _pumpSheet(tester, _FakeRepository());

    await tester.enterText(find.byType(TextField), 'Too short');
    await tester.pump();
    expect(find.text('9 / 2000'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send feedback'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'Needs work');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send feedback'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('preserves text and retries the same failed submission', (
    tester,
  ) async {
    final repository = _FakeRepository(failFirst: true);
    await _pumpSheet(tester, repository);
    await tester.enterText(
      find.byType(TextField),
      'This category should be groceries.',
    );
    await _tapAction(tester, 'Send feedback');
    await tester.pumpAndSettle();

    expect(repository.attempts, 1);
    expect(find.text('Feedback could not be sent. Try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('This category should be groceries.'), findsOneWidget);
    await _tapAction(tester, 'Try again');
    await tester.pumpAndSettle();

    expect(find.text('Feedback sent'), findsOneWidget);
    expect(repository.observedRequestIds, [
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
    ]);
  });

  testWidgets('an expired recommendation trace is recreated exactly once', (
    tester,
  ) async {
    final repository = _ExpiredTraceRepository();
    await _pump(
      tester,
      repository: repository,
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showContextualFeedbackSheet(
            context,
            target: const RecommendationFeedbackTarget(
              '70000000-0000-4000-8000-000000000001',
            ),
            preview: 'Movie offer · Save ₹150',
            recreateTarget: repository.recreate,
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'This movie recommendation used the wrong card.',
    );
    await _tapAction(tester, 'Send feedback');
    await tester.pumpAndSettle();

    expect(repository.recreateCalls, 1);
    expect(repository.submissions.map((s) => s.text), [
      'This movie recommendation used the wrong card.',
      'This movie recommendation used the wrong card.',
    ]);
    expect(repository.submissions.map((s) => s.target.outputRefId), [
      '70000000-0000-4000-8000-000000000001',
      '70000000-0000-4000-8000-000000000002',
    ]);
    expect(find.text('Feedback sent'), findsOneWidget);
  });

  testWidgets(
    'editing after refreshed trace failure never returns to the expired trace',
    (tester) async {
      final repository = _RefreshedTraceRetryRepository();
      await _pump(
        tester,
        repository: repository,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showContextualFeedbackSheet(
              context,
              target: const RecommendationFeedbackTarget(
                '70000000-0000-4000-8000-000000000001',
              ),
              preview: 'Movie offer · Save ₹150',
              recreateTarget: repository.recreate,
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'This recommendation selected the wrong card.',
      );
      await _tapAction(tester, 'Send feedback');
      await tester.pumpAndSettle();
      expect(
        find.text('Feedback could not be sent. Try again.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField),
        'This recommendation selected the wrong benefit.',
      );
      await tester.pump();
      await _tapAction(tester, 'Send feedback');
      await tester.pumpAndSettle();

      expect(repository.recreateCalls, 1);
      expect(repository.submissions.map((s) => s.target.outputRefId), [
        '70000000-0000-4000-8000-000000000001',
        '70000000-0000-4000-8000-000000000002',
        '70000000-0000-4000-8000-000000000002',
      ]);
      expect(
        repository.submissions[1].requestId,
        isNot(repository.submissions[2].requestId),
      );
      expect(find.text('Feedback sent'), findsOneWidget);
    },
  );

  testWidgets('editing after failure creates a fresh submission id', (
    tester,
  ) async {
    final repository = _FakeRepository(failFirst: true);
    await _pumpSheet(tester, repository);
    await tester.enterText(
      find.byType(TextField),
      'This category is incorrect.',
    );
    await _tapAction(tester, 'Send feedback');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'This category should be fuel.',
    );
    await tester.pump();
    await _tapAction(tester, 'Send feedback');
    await tester.pumpAndSettle();

    expect(repository.observedRequestIds, [
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',
    ]);
  });

  testWidgets('success stays bound to the frozen in-flight submission', (
    tester,
  ) async {
    final repository = _ControlledRepository();
    await _pumpSheet(tester, repository);
    const original = 'This category should be groceries.';
    await tester.enterText(find.byType(TextField), original);
    await _tapAction(tester, 'Send feedback');
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.enterText(find.byType(TextField), 'A different statement.');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ContextualFeedbackSheet), findsOneWidget);
    expect(find.text(original), findsOneWidget);

    repository.completeSuccess();
    await tester.pumpAndSettle();

    expect(find.text('Feedback sent'), findsOneWidget);
    expect(repository.submissions.single.text, original);
    expect(repository.submissions.single.requestId, _firstRequestId);
  });

  testWidgets('failure retries the exact frozen text and request id', (
    tester,
  ) async {
    final repository = _ControlledRepository();
    await _pumpSheet(tester, repository);
    const original = 'This category should be groceries.';
    await tester.enterText(find.byType(TextField), original);
    await _tapAction(tester, 'Send feedback');
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'A different statement.');
    repository.completeFailure();
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);

    await _tapAction(tester, 'Try again');
    await tester.pump();
    repository.completeSuccess();
    await tester.pumpAndSettle();

    expect(repository.submissions.map((value) => value.text), [
      original,
      original,
    ]);
    expect(repository.submissions.map((value) => value.requestId), [
      _firstRequestId,
      _firstRequestId,
    ]);
  });

  testWidgets('escape closes the sheet and mobile width does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpSheet(tester, _FakeRepository());
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ContextualFeedbackSheet), findsNothing);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  FeedbackRepository repository,
) async {
  await _pump(
    tester,
    repository: repository,
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () => showContextualFeedbackSheet(
          context,
          target: target,
          preview: 'Coffee ¹420 · Food & dining',
        ),
        child: const Text('Open'),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  final action = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
}

Future<void> _pump(
  WidgetTester tester, {
  required FeedbackRepository repository,
  required Widget child,
}) => tester.pumpWidget(
  FeedbackRepositoryScope(
    repository: repository,
    child: MaterialApp(
      theme: AppTheme.work,
      home: Scaffold(body: child),
    ),
  ),
);

class _FakeRepository extends FeedbackRepository {
  _FakeRepository({this.failFirst = false})
    : super(
        _UnusedApi(),
        requestIds: [
          '10000000-0000-4000-8000-000000000001',
          '10000000-0000-4000-8000-000000000002',
        ].iterator,
      );

  final bool failFirst;
  final List<String> observedRequestIds = [];
  int attempts = 0;

  @override
  Future<FeedbackSubmitResult> submit(FeedbackSubmission submission) async {
    observedRequestIds.add(submission.requestId);
    attempts++;
    if (failFirst && attempts == 1) {
      throw const FeedbackFailed('request_failed');
    }
    return const FeedbackSubmitResult('feedback-id', 'awaiting_triage');
  }
}

class _UnusedApi implements FeedbackApi {
  @override
  Future<FeedbackApiResponse> invoke(Map<String, Object?> body) =>
      throw UnimplementedError();
}

class _ExpiredTraceRepository extends FeedbackRepository {
  _ExpiredTraceRepository()
    : super(
        _UnusedApi(),
        requestIds: [
          '80000000-0000-4000-8000-000000000001',
          '80000000-0000-4000-8000-000000000002',
        ].iterator,
      );

  final submissions = <FeedbackSubmission>[];
  int recreateCalls = 0;

  Future<FeedbackTarget> recreate() async {
    recreateCalls++;
    return const RecommendationFeedbackTarget(
      '70000000-0000-4000-8000-000000000002',
    );
  }

  @override
  Future<FeedbackSubmitResult> submit(FeedbackSubmission submission) async {
    submissions.add(submission);
    if (submissions.length == 1) throw const FeedbackFailed('not_found');
    return const FeedbackSubmitResult('feedback-id', 'awaiting_triage');
  }
}

class _RefreshedTraceRetryRepository extends FeedbackRepository {
  _RefreshedTraceRetryRepository()
    : super(
        _UnusedApi(),
        requestIds: [
          '80000000-0000-4000-8000-000000000001',
          '80000000-0000-4000-8000-000000000002',
          '80000000-0000-4000-8000-000000000003',
        ].iterator,
      );

  final submissions = <FeedbackSubmission>[];
  int recreateCalls = 0;

  Future<FeedbackTarget> recreate() async {
    recreateCalls++;
    return const RecommendationFeedbackTarget(
      '70000000-0000-4000-8000-000000000002',
    );
  }

  @override
  Future<FeedbackSubmitResult> submit(FeedbackSubmission submission) async {
    submissions.add(submission);
    if (submissions.length == 1) throw const FeedbackFailed('not_found');
    if (submissions.length == 2) throw const FeedbackFailed('request_failed');
    return const FeedbackSubmitResult('feedback-id', 'awaiting_triage');
  }
}

const _firstRequestId = '10000000-0000-4000-8000-000000000001';

class _ControlledRepository extends FeedbackRepository {
  _ControlledRepository()
    : super(_UnusedApi(), requestIds: [_firstRequestId].iterator);

  final List<FeedbackSubmission> submissions = [];
  Completer<FeedbackSubmitResult>? _pending;

  @override
  Future<FeedbackSubmitResult> submit(FeedbackSubmission submission) {
    submissions.add(submission);
    _pending = Completer<FeedbackSubmitResult>();
    return _pending!.future;
  }

  void completeSuccess() => _pending!.complete(
    const FeedbackSubmitResult(
      '30000000-0000-4000-8000-000000000001',
      'awaiting_triage',
    ),
  );

  void completeFailure() =>
      _pending!.completeError(const FeedbackFailed('request_failed'));
}
