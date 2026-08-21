import 'dart:async';

import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_models.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_repository.dart';
import 'package:cardcompass/features/admin2/card_data/card_data_section.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_api.dart';
import 'package:cardcompass/features/admin2/data/admin_operator_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const requiredAdmin2Actions = <String>{
  'identity.list',
  'identity.approve',
  'identity.editApprove',
  'identity.merge',
  'identity.reject',
  'identity.retry',
  'benefit.list',
  'benefit.approve',
  'benefit.editApprove',
  'benefit.reject',
  'benefit.retry',
  'benefit.quarantine',
  'benefit.unquarantine',
};

const _identityId = '11111111-1111-4111-8111-111111111111';
const _mergeId = '33333333-3333-4333-8333-333333333333';
const _stagingId = '22222222-2222-4222-8222-222222222222';
const _requestId = '44444444-4444-4444-8444-444444444444';
const _observed = '2026-08-19T09:00:00.000Z';

final class _RecordingApi implements AdminOperatorApi {
  _RecordingApi({required this.lane, required this.item});

  final String lane;
  final Map<String, dynamic> item;
  final calls = <Map<String, dynamic>>[];
  Completer<void>? actionCompletion;
  var listCount = 0;

  @override
  Future<AdminOperatorResponse> invoke(Map<String, dynamic> body) async {
    calls.add(Map<String, dynamic>.from(body));
    if (body['action'] == 'card-review-list') {
      listCount++;
      return AdminOperatorResponse(200, {
        'lane': lane,
        'items': [item],
        'page': 1,
        'limit': 25,
        'has_more': false,
      });
    }
    await actionCompletion?.future;
    return const AdminOperatorResponse(200, {
      'result': {'outcome': 'succeeded'},
    });
  }
}

final class _RepositorySource implements CardDataSource {
  _RepositorySource(_RecordingApi api)
    : _repository = CardDataRepository(
        AdminOperatorRepository(api),
        requestIds: () => _requestId,
        now: () => DateTime.utc(2026, 8, 19, 9, 5),
      );

  final CardDataRepository _repository;

  @override
  Future<CardReviewPage> list(CardReviewQuery query) => _repository.list(
    query.lane,
    page: query.page,
    limit: query.limit,
    status: query.status,
    targetId: query.targetId,
  );

  @override
  Future<void> act(CardReviewAction action) async {
    await _repository.act(action);
  }
}

Map<String, dynamic> _identityItem() => {
  'id': _identityId,
  'status': 'pending',
  'updated_at': _observed,
  'confidence': 0.91,
  'proposed_fields': {
    'bank': 'Example Bank',
    'card_name': 'Regalia Gold',
    'network': 'Visa',
  },
  'source_evidence': {
    'official_url': 'https://issuer.example/cards/regalia-gold',
    'source_excerpt': 'Official premium credit card product page.',
    'retrieved_at': '2026-08-19T08:45:00Z',
  },
  'existing_candidates': [
    {
      'id': _mergeId,
      'bank': 'Example Bank',
      'card_name': 'Regalia Gold Credit Card',
      'network': 'Visa',
      'confidence': 0.88,
    },
  ],
  'validation_warnings': [
    {'code': 'possible_duplicate'},
  ],
};

Map<String, dynamic> _benefitItem({required String status}) => {
  'id': _identityId,
  'status': status,
  'updated_at': _observed,
  'staging_id': _stagingId,
  'parser_version': 'benefits-v3',
  'card': {'bank': 'Example Bank', 'card_name': 'Regalia Gold'},
  'staging': {
    'id': _stagingId,
    'calculated_confidence': 0.84,
    'source_evidence': [
      {
        'source_url': 'https://issuer.example/cards/regalia-gold/benefits',
        'source_excerpt': 'Four complimentary domestic lounge visits.',
        'retrieved_at': '2026-08-19T08:45:00Z',
        'field_evidence': {'frequency': '4 visits per calendar year'},
      },
    ],
    'extracted_data': {
      'retrieved_at': '2026-08-19T08:45:00Z',
      'diff': {
        'additions': [
          {
            'dedupe_key': 'domestic-lounge',
            'title': 'Domestic lounge access',
            'benefit_category': 'travel',
            'benefit_type': 'complimentary_access',
            'value_config': {'unit': 'visits', 'value': 4, 'period': 'year'},
            'source_url': 'https://issuer.example/cards/regalia-gold/benefits',
          },
        ],
        'modifications': [],
        'possibleRemovals': [],
        'unchanged': [],
        'conflicts': [],
      },
    },
    'validation_warnings': [],
    'validation_reasons': [],
    'benefit_decisions': [],
  },
};

Future<void> _pump(
  WidgetTester tester,
  _RecordingApi api,
  CardReviewLane lane,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.work,
        home: Scaffold(
          body: CardDataSection(
            repository: _RepositorySource(api),
            initialLane: lane,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  final finder = find.text(label);
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _confirm(
  WidgetTester tester,
  String label, {
  String? input,
  String? inputLabel,
}) async {
  await _tapVisible(tester, label);
  if (input != null) {
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == inputLabel,
      ),
      input,
    );
  }
  final confirmation = switch (label) {
    'Approve' => 'Confirm approval',
    'Edit & approve' => 'Confirm edits',
    'Merge' => 'Confirm merge',
    'Reject' => 'Confirm rejection',
    'Retry' => 'Confirm retry',
    'Quarantine' => 'Confirm quarantine',
    'Unquarantine' => 'Confirm unquarantine',
    'Submit benefit decisions' =>
      find.text('Confirm approval').evaluate().isNotEmpty
          ? 'Confirm approval'
          : find.text('Confirm edits').evaluate().isNotEmpty
          ? 'Confirm edits'
          : 'Confirm rejection',
    _ => throw ArgumentError.value(label),
  };
  await tester.tap(find.text(confirmation).last);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _listCall(String lane) => {
  'action': 'card-review-list',
  'lane': lane,
  'page': 1,
  'limit': 25,
};

Map<String, dynamic> _actionCall(
  String lane,
  String operation, {
  String? reason,
  bool includeStaging = false,
  Map<String, dynamic> payload = const {},
}) => {
  'action': 'card-review-action',
  'lane': lane,
  'operation': operation,
  'target_id': _identityId,
  'request_id': _requestId,
  'observed_updated_at': _observed,
  if (includeStaging) 'staging_id': _stagingId,
  'reason': ?reason,
  ...payload,
};

void main() {
  testWidgets('identity parity maps each UI action to one typed gateway call', (
    tester,
  ) async {
    final observedActions = <String>{};
    final scenarios =
        <
          ({
            String label,
            String operation,
            String? input,
            String? inputLabel,
            String? reason,
            Map<String, dynamic> payload,
          })
        >[
          (
            label: 'Approve',
            operation: 'approve',
            input: null,
            inputLabel: null,
            reason: null,
            payload: const {},
          ),
          (
            label: 'Edit & approve',
            operation: 'edit_approve',
            input: null,
            inputLabel: null,
            reason: null,
            payload: const {
              'proposed_fields': {
                'card_name': 'Regalia Gold',
                'network': 'Visa',
              },
            },
          ),
          (
            label: 'Merge',
            operation: 'merge',
            input: _mergeId,
            inputLabel: 'Merge card ID',
            reason: null,
            payload: const {'merge_card_id': _mergeId},
          ),
          (
            label: 'Reject',
            operation: 'reject',
            input: 'Generic rewards page is not a card product',
            inputLabel: 'Reason',
            reason: 'Generic rewards page is not a card product',
            payload: const {},
          ),
          (
            label: 'Retry',
            operation: 'retry',
            input: null,
            inputLabel: null,
            reason: null,
            payload: const {},
          ),
        ];

    for (final scenario in scenarios) {
      final api = _RecordingApi(lane: 'identity', item: _identityItem());
      await _pump(tester, api, CardReviewLane.identity);
      expect(find.text('Approve all'), findsNothing);
      expect(find.text('Bulk approve'), findsNothing);

      await _confirm(
        tester,
        scenario.label,
        input: scenario.input,
        inputLabel: scenario.inputLabel,
      );

      expect(api.calls, [
        _listCall('identity'),
        _actionCall(
          'identity',
          scenario.operation,
          reason: scenario.reason,
          payload: scenario.payload,
        ),
        _listCall('identity'),
      ]);
      observedActions.add(
        'identity.${switch (scenario.operation) {
          'edit_approve' => 'editApprove',
          final value => value,
        }}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    expect(
      observedActions,
      requiredAdmin2Actions
          .where((a) => a.startsWith('identity.') && a != 'identity.list')
          .toSet(),
    );
  });

  testWidgets('benefit parity maps decisions and recovery to typed calls', (
    tester,
  ) async {
    final observedActions = <String>{};

    Future<void> run({
      required String status,
      required String label,
      required String operation,
      Future<void> Function()? prepare,
      String? dialogReason,
      Map<String, dynamic> payload = const {},
    }) async {
      final api = _RecordingApi(
        lane: 'benefit',
        item: _benefitItem(status: status),
      );
      await _pump(tester, api, CardReviewLane.benefit);
      expect(find.text('Approve all'), findsNothing);
      expect(find.text('Bulk approve'), findsNothing);
      await prepare?.call();
      await _confirm(
        tester,
        label,
        input: dialogReason,
        inputLabel: dialogReason == null ? null : 'Reason',
      );
      expect(api.calls, [
        _listCall('benefit'),
        _actionCall(
          'benefit',
          operation,
          reason: dialogReason,
          includeStaging: {
            'approve',
            'edit_approve',
            'reject',
          }.contains(operation),
          payload: payload,
        ),
        _listCall('benefit'),
      ]);
      observedActions.add(
        'benefit.${switch (operation) {
          'edit_approve' => 'editApprove',
          final value => value,
        }}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    const approvedDecision = {
      'action': 'approve',
      'change_type': 'addition',
      'dedupe_key': 'domestic-lounge',
      'proposed': {
        'dedupe_key': 'domestic-lounge',
        'title': 'Domestic lounge access',
        'benefit_category': 'travel',
        'benefit_type': 'complimentary_access',
        'value_config': {'unit': 'visits', 'value': 4, 'period': 'year'},
        'source_url': 'https://issuer.example/cards/regalia-gold/benefits',
      },
    };
    await run(
      status: 'staged',
      label: 'Submit benefit decisions',
      operation: 'approve',
      payload: const {
        'decisions': [approvedDecision],
      },
    );
    await run(
      status: 'staged',
      label: 'Submit benefit decisions',
      operation: 'edit_approve',
      prepare: () async {
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit proposal').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('benefit-edit-domestic-lounge-title')),
          'Domestic airport lounge access',
        );
      },
      payload: const {
        'decisions': [
          {
            'action': 'edit',
            'change_type': 'addition',
            'dedupe_key': 'domestic-lounge',
            'edited_benefit': {
              'dedupe_key': 'domestic-lounge',
              'title': 'Domestic airport lounge access',
              'benefit_category': 'travel',
              'benefit_type': 'complimentary_access',
              'value_config': {'unit': 'visits', 'value': 4, 'period': 'year'},
              'source_url':
                  'https://issuer.example/cards/regalia-gold/benefits',
            },
          },
        ],
      },
    );
    await run(
      status: 'staged',
      label: 'Submit benefit decisions',
      operation: 'reject',
      dialogReason: 'Latest issuer terms do not support this benefit',
      prepare: () async {
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reject proposal').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Benefit rejection reason',
          ),
          'Official terms omit lounge access',
        );
      },
      payload: const {
        'decisions': [
          {
            'action': 'reject',
            'change_type': 'addition',
            'dedupe_key': 'domestic-lounge',
            'reason': 'Official terms omit lounge access',
          },
        ],
      },
    );
    await run(status: 'failed', label: 'Retry', operation: 'retry');
    await run(
      status: 'review_required',
      label: 'Quarantine',
      operation: 'quarantine',
      dialogReason: 'Conflicting official evidence needs investigation',
    );
    await run(
      status: 'quarantined',
      label: 'Unquarantine',
      operation: 'unquarantine',
    );

    expect(
      observedActions,
      requiredAdmin2Actions
          .where((a) => a.startsWith('benefit.') && a != 'benefit.list')
          .toSet(),
    );
  });

  testWidgets(
    'mutation locks controls until confirmation and refreshes only after success',
    (tester) async {
      final api = _RecordingApi(lane: 'identity', item: _identityItem())
        ..actionCompletion = Completer<void>();
      await _pump(tester, api, CardReviewLane.identity);
      await _tapVisible(tester, 'Approve');
      await tester.tap(find.text('Confirm approval'));
      await tester.pump();

      expect(api.calls, [
        _listCall('identity'),
        _actionCall('identity', 'approve'),
      ]);
      expect(api.listCount, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      api.actionCompletion!.complete();
      await tester.pumpAndSettle();
      expect(api.calls, [
        _listCall('identity'),
        _actionCall('identity', 'approve'),
        _listCall('identity'),
      ]);
      expect(api.listCount, 2);
      expect(find.text('Approve confirmed.'), findsOneWidget);
    },
  );

  test('required parity set is exact and contains no bulk mutation', () {
    expect(requiredAdmin2Actions, hasLength(13));
    expect(requiredAdmin2Actions.where((action) => action.endsWith('.list')), {
      'identity.list',
      'benefit.list',
    });
    expect(
      requiredAdmin2Actions.any((action) => action.contains('bulk')),
      isFalse,
    );
  });
}
