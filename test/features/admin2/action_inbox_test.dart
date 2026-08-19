import 'dart:async';

import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_section.dart';
import 'package:cardcompass/features/admin2/models/admin_access.dart';
import 'package:cardcompass/features/admin2/providers/admin_access_provider.dart';
import 'package:cardcompass/features/admin2/screens/admin_operator_screen.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:cardcompass/features/admin2/inbox/inbox_models.dart';
import 'package:cardcompass/features/admin2/inbox/inbox_repository.dart';
import 'package:cardcompass/features/admin2/inbox/action_inbox_section.dart';
import 'package:cardcompass/features/admin2/system/system_models.dart';
import 'package:cardcompass/features/admin2/system/system_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _Api implements AdminOperatorApi {
  _Api(this.response, {this.error});
  final AdminOperatorResponse response;
  final Object? error;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    bodies.add(body);
    if (error != null) throw error!;
    return response;
  }
}

void main() {
  test(
    'maps ranked inbox destinations, partial failures and refresh time',
    () async {
      final api = _Api(
        const AdminOperatorResponse(200, {
          'items': [
            {
              'id': 'benefit-enrichment:job-1',
              'type': 'benefit_enrichment_review',
              'severity': 'high',
              'title': 'Recover benefits',
              'explanation': 'Needs recovery.',
              'source_status': 'failed',
              'age_seconds': 7200,
              'destination': {
                'section': 'cardData',
                'lane': 'benefit',
                'target_id': 'job-1',
              },
            },
          ],
          'partial_failures': ['card_identity'],
          'refreshed_at': '2026-08-19T09:00:00.000Z',
        }),
      );

      final snapshot = await InboxRepository(
        AdminOperatorRepository(api),
      ).load();

      expect(snapshot.partialFailures, [InboxSource.cardIdentity]);
      expect(snapshot.refreshedAt, DateTime.utc(2026, 8, 19, 9));
      expect(snapshot.items.single.severity, AdminInboxSeverity.high);
      expect(snapshot.items.single.destination.lane, CardReviewLane.benefit);
      expect(snapshot.items.single.destination.targetId, 'job-1');
      expect(api.bodies.single, {'action': 'inbox-list'});
    },
  );

  test(
    'maps a paused pipeline to the exact System control destination',
    () async {
      final api = _Api(
        const AdminOperatorResponse(200, {
          'items': [
            {
              'id': 'system:benefit_enrichment_scheduled:paused',
              'type': 'paused_pipeline',
              'severity': 'critical',
              'title': 'Scheduled benefit enrichment is paused',
              'explanation': '17 queued jobs are waiting.',
              'source_status': 'paused',
              'age_seconds': 60,
              'destination': {
                'section': 'system',
                'control_key': 'benefit_enrichment_scheduled',
              },
            },
          ],
          'partial_failures': ['system_operations'],
          'refreshed_at': '2026-08-19T09:00:00.000Z',
        }),
      );

      final snapshot = await InboxRepository(
        AdminOperatorRepository(api),
      ).load();
      expect(snapshot.partialFailures, [InboxSource.systemOperations]);
      expect(snapshot.items.single.destination.section, 'system');
      expect(
        snapshot.items.single.destination.controlKey,
        'benefit_enrichment_scheduled',
      );
    },
  );

  test('rejects malformed inbox data without a dynamic crash', () async {
    final api = _Api(
      const AdminOperatorResponse(200, {
        'items': [
          {'id': 'x', 'severity': 'urgent'},
        ],
        'partial_failures': [],
        'refreshed_at': 'not-a-date',
      }),
    );

    expect(
      InboxRepository(AdminOperatorRepository(api)).load(),
      throwsA(isA<AdminRequestFailed>()),
    );
  });

  for (final status in [401, 403, 409, 500]) {
    test('$status uses the common stable error mapping', () async {
      final api = _Api(
        AdminOperatorResponse(status, {
          'error': status == 409 ? 'state_conflict' : 'request_failed',
        }),
      );
      final matcher = switch (status) {
        401 => isA<AdminAuthenticationRequired>(),
        403 => isA<AdminAccessDenied>(),
        409 => isA<AdminStateConflict>(),
        _ => isA<AdminRequestFailed>(),
      };
      expect(
        InboxRepository(AdminOperatorRepository(api)).load(),
        throwsA(matcher),
      );
    });
  }

  test('FunctionException conflict uses the common state mapping', () async {
    final api = _Api(
      const AdminOperatorResponse(500, {}),
      error: const FunctionException(
        status: 409,
        details: {'error': 'state_conflict'},
      ),
    );

    expect(
      InboxRepository(AdminOperatorRepository(api)).load(),
      throwsA(isA<AdminStateConflict>()),
    );
  });

  test('unknown invocation failure is sanitized without raw detail', () async {
    final api = _Api(
      const AdminOperatorResponse(500, {}),
      error: StateError('socket leaked-internal-host.example'),
    );

    try {
      await InboxRepository(AdminOperatorRepository(api)).load();
      fail('expected a safe failure');
    } on AdminRequestFailed catch (error) {
      expect(error.message, 'request_failed');
      expect(error.toString(), isNot(contains('leaked-internal-host')));
    }
  });

  group('ActionInboxSection', () {
    testWidgets(
      'keeps server order inside severity groups and partial results',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpInbox(
          tester,
          _snapshot(
            items: [
              _item('normal-1', AdminInboxSeverity.normal, 'Normal first'),
              _item(
                'critical-1',
                AdminInboxSeverity.critical,
                'Critical first',
              ),
              _item('high-1', AdminInboxSeverity.high, 'High first'),
              _item(
                'critical-2',
                AdminInboxSeverity.critical,
                'Critical second',
              ),
            ],
            partialFailures: [InboxSource.benefitEnrichment],
          ),
        );

        expect(
          find.text('Benefit enrichment is temporarily unavailable.'),
          findsOneWidget,
        );
        expect(find.text('Critical first'), findsOneWidget);
        final labels = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data)
            .whereType<String>()
            .toList();
        expect(
          labels.indexOf('Critical first'),
          lessThan(labels.indexOf('Critical second')),
        );
        expect(
          labels.indexOf('Critical second'),
          lessThan(labels.indexOf('High first')),
        );
        expect(
          labels.indexOf('High first'),
          lessThan(labels.indexOf('Normal first')),
        );
      },
    );

    testWidgets('opens exact destination reliably on repeated selections', (
      tester,
    ) async {
      final opened = <AdminInboxDestination>[];
      await _pumpInbox(
        tester,
        _snapshot(
          items: [
            _item('one', AdminInboxSeverity.critical, 'Identity conflict'),
            _item(
              'two',
              AdminInboxSeverity.high,
              'Benefit recovery',
              lane: CardReviewLane.benefit,
            ),
          ],
        ),
        onOpen: opened.add,
      );

      await tester.tap(find.text('Identity conflict'));
      await tester.pump();
      await tester.tap(find.text('Benefit recovery'));
      await tester.pump();
      await tester.tap(find.text('Identity conflict'));
      await tester.pump();

      expect(opened.map((value) => value.targetId), ['one', 'two', 'one']);
      expect(opened[1].lane, CardReviewLane.benefit);
    });

    testWidgets('shows safe type and destination labels without record IDs', (
      tester,
    ) async {
      await _pumpInbox(
        tester,
        _snapshot(
          items: [
            _item(
              'private-identity-id',
              AdminInboxSeverity.critical,
              'Identity conflict',
              type: 'card_identity_review',
            ),
            _item(
              'private-benefit-id',
              AdminInboxSeverity.high,
              'Benefit recovery',
              lane: CardReviewLane.benefit,
              type: 'future_unrecognized_work',
            ),
          ],
        ),
      );

      expect(
        find.text('Card identity review · Card Data / Identity'),
        findsOneWidget,
      );
      expect(
        find.text('Operator action · Card Data / Benefits'),
        findsOneWidget,
      );
      final semantics = tester.getSemantics(
        find.byKey(const Key('inbox-item-private-benefit-id')),
      );
      expect(
        semantics.label,
        contains('Operator action. Card Data. Benefits.'),
      );
      expect(semantics.label, isNot(contains('private-benefit-id')));
    });

    testWidgets('shows a safe paused-pipeline System destination label', (
      tester,
    ) async {
      await _pumpInbox(tester, _snapshot(items: [_systemItem()]));

      expect(
        find.text('Paused pipeline · System / Scheduled enrichment control'),
        findsOneWidget,
      );
      final semantics = tester.getSemantics(
        find.byKey(
          const Key('inbox-item-system:benefit_enrichment_scheduled:paused'),
        ),
      );
      expect(
        semantics.label,
        contains('System. Scheduled enrichment control.'),
      );
      expect(semantics.label, isNot(contains('benefit_enrichment_scheduled')));
    });

    testWidgets('deep-links repeatedly to the exact System control on mobile', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAccessProvider.overrideWith(
              (_) async => const AdminAccess(isAdmin: true),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.work,
            home: AdminOperatorScreen(
              inboxLoader: () async => _snapshot(items: [_systemItem()]),
              systemSource: _RecordingSystemSource(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Scheduled benefit enrichment is paused'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('system-control-action')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('system-control-action')),
              )
              .focusNode
              ?.hasFocus,
          isTrue,
        );
        if (attempt == 0) {
          await tester.tap(find.byKey(const Key('admin-section-inbox')));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('refresh retains items and reports a safe retryable failure', (
      tester,
    ) async {
      final refresh = Completer<InboxSnapshot>();
      var calls = 0;
      await _pumpInbox(
        tester,
        _snapshot(items: [_item('one', AdminInboxSeverity.high, 'Keep me')]),
        loader: () {
          calls++;
          if (calls == 1) {
            return Future.value(
              _snapshot(
                items: [_item('one', AdminInboxSeverity.high, 'Keep me')],
              ),
            );
          }
          return refresh.future;
        },
      );

      await tester.tap(find.byTooltip('Refresh inbox'));
      await tester.pump();
      expect(find.text('Keep me'), findsOneWidget);
      refresh.completeError(const AdminRequestFailed('request_failed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Refresh failed. Showing the last loaded inbox.'),
        findsOneWidget,
      );
      expect(find.text('Keep me'), findsOneWidget);
    });

    testWidgets('fits a 390px viewport with accessible item targets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(780, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await _pumpInbox(
        tester,
        _snapshot(
          items: [_item('one', AdminInboxSeverity.high, 'Compact item')],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('inbox-item-one'))).height,
        greaterThanOrEqualTo(44),
      );
      final semantics = tester.getSemantics(
        find.byKey(const Key('inbox-item-one')),
      );
      expect(semantics.label, contains('Compact item'));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    });

    testWidgets('workspace deep-link loads the exact lane and target', (
      tester,
    ) async {
      final cards = _RecordingCardSource();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAccessProvider.overrideWith(
              (_) async => const AdminAccess(isAdmin: true),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.work,
            home: AdminOperatorScreen(
              inboxLoader: () async => _snapshot(
                items: [
                  _item(
                    'benefit-job-7',
                    AdminInboxSeverity.high,
                    'Review benefit recovery',
                    lane: CardReviewLane.benefit,
                  ),
                  _item(
                    'identity-review-8',
                    AdminInboxSeverity.normal,
                    'Review identity match',
                    type: 'card_identity_review',
                  ),
                ],
              ),
              cardDataSource: cards,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review benefit recovery'));
      await tester.pumpAndSettle();

      expect(cards.queries.last.lane, CardReviewLane.benefit);
      expect(cards.queries.last.targetId, 'benefit-job-7');
      expect(find.text('Deep-linked Benefit Card'), findsWidgets);
      expect(find.text('Back to review queue'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin-section-inbox')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review identity match'));
      await tester.tap(find.text('Review identity match'));
      await tester.pumpAndSettle();

      expect(cards.queries.last.lane, CardReviewLane.identity);
      expect(cards.queries.last.targetId, 'identity-review-8');
      expect(find.text('Deep-linked Identity Card'), findsWidgets);
      expect(find.text('Back to review queue'), findsOneWidget);
    });
  });
}

final class _RecordingCardSource implements CardDataSource {
  final queries = <CardReviewQuery>[];

  @override
  Future<void> act(CardReviewAction action) async {}

  @override
  Future<CardReviewPage> list(CardReviewQuery query) async {
    queries.add(query);
    return CardReviewPage(
      lane: query.lane,
      items: [
        CardReviewItem(
          id: query.targetId ?? 'fallback',
          lane: query.lane,
          status: query.lane == CardReviewLane.benefit ? 'failed' : 'pending',
          updatedAt: DateTime.utc(2026, 8, 19),
          evidence: const [],
          warningCodes: const [],
          proposedFields: const {},
          cardName: query.lane == CardReviewLane.benefit
              ? 'Deep-linked Benefit Card'
              : 'Deep-linked Identity Card',
          bank: 'Safe Bank',
        ),
      ],
      page: 1,
      limit: 25,
      hasMore: false,
      refreshedAt: DateTime.utc(2026, 8, 19),
    );
  }
}

final class _RecordingSystemSource implements SystemDataSource {
  @override
  Future<SystemJobsPage> jobs(
    SystemJobFamily family, {
    int page = 1,
    int limit = 25,
    String? status,
  }) async =>
      SystemJobsPage(items: const [], page: page, limit: limit, hasMore: false);

  @override
  Future<void> mutate(SystemMutation mutation) async {}

  @override
  Future<SystemStatusSnapshot> status() async => SystemStatusSnapshot(
    pipelines: const [],
    controls: [
      RuntimeControl(
        isPaused: true,
        reason: 'provider outage',
        updatedAt: DateTime.utc(2026, 8, 19),
      ),
    ],
    controlSourceError: null,
    refreshedAt: DateTime.utc(2026, 8, 19),
  );
}

Future<void> _pumpInbox(
  WidgetTester tester,
  InboxSnapshot initial, {
  Future<InboxSnapshot> Function()? loader,
  ValueChanged<AdminInboxDestination>? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ActionInboxSection(
          loadInbox: loader ?? () async => initial,
          onOpenCardTarget: onOpen ?? (_) {},
          onOpenSystemControl: onOpen ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InboxSnapshot _snapshot({
  List<AdminInboxItem> items = const [],
  List<InboxSource> partialFailures = const [],
}) => InboxSnapshot(
  items: items,
  partialFailures: partialFailures,
  refreshedAt: DateTime.utc(2026, 8, 19, 9),
);

AdminInboxItem _item(
  String id,
  AdminInboxSeverity severity,
  String title, {
  CardReviewLane lane = CardReviewLane.identity,
  String type = 'review',
}) => AdminInboxItem(
  id: id,
  type: type,
  severity: severity,
  title: title,
  explanation: 'Safe operator explanation.',
  sourceStatus: 'review_required',
  ageSeconds: 7200,
  destination: AdminInboxDestination(
    section: 'cardData',
    lane: lane,
    targetId: id,
  ),
);

AdminInboxItem _systemItem() => const AdminInboxItem(
  id: 'system:benefit_enrichment_scheduled:paused',
  type: 'paused_pipeline',
  severity: AdminInboxSeverity.critical,
  title: 'Scheduled benefit enrichment is paused',
  explanation: '17 queued jobs are waiting.',
  sourceStatus: 'paused',
  ageSeconds: 60,
  destination: AdminInboxDestination.system(
    controlKey: 'benefit_enrichment_scheduled',
  ),
);
