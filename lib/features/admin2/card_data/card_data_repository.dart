import 'package:uuid/uuid.dart';

import '../data/admin_operator_repository.dart';
import 'card_data_models.dart';

typedef RequestIdFactory = String Function();
typedef AdminClock = DateTime Function();

final class CardDataRepository {
  CardDataRepository(
    this._operator, {
    RequestIdFactory? requestIds,
    AdminClock? now,
  }) : _requestIds = requestIds ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final AdminOperatorRepository _operator;
  final RequestIdFactory _requestIds;
  final AdminClock _now;

  Future<CardReviewPage> list(
    CardReviewLane lane, {
    int page = 1,
    int limit = 25,
    String? status,
  }) async {
    try {
      final body = <String, dynamic>{
        'lane': lane.wireValue,
        'page': page,
        'limit': limit,
        'status': ?status,
      };
      final json = await _operator.invoke('card-review-list', body);
      final responseLane = CardReviewLane.parse(json['lane']);
      if (responseLane != lane) throw const FormatException('Lane mismatch');
      final pageValue = json['page'];
      final limitValue = json['limit'];
      final hasMore = json['has_more'];
      if (pageValue is! int || limitValue is! int || hasMore is! bool) {
        throw const FormatException('Invalid pagination');
      }
      final items = strictJsonList(json['items'])
          .map(strictJsonMap)
          .map((item) => CardReviewItem.fromJson(lane, item))
          .toList();
      return CardReviewPage(
        lane: lane,
        items: items,
        page: pageValue,
        limit: limitValue,
        hasMore: hasMore,
        refreshedAt: _now().toUtc(),
      );
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    } on TypeError {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<Map<String, dynamic>> act(CardReviewAction action) async {
    _validateAction(action);
    final requestId = _requestIds();
    if (!_uuid.hasMatch(requestId)) _invalidAction();
    final json = await _operator.invoke('card-review-action', {
      'lane': action.lane.wireValue,
      'operation': action.operation.wireValue,
      'target_id': action.targetId,
      'request_id': requestId,
      'observed_updated_at': action.observedUpdatedAt,
      if (action.stagingId != null) 'staging_id': action.stagingId,
      if (action.reason != null) 'reason': action.reason,
      ...action.payload,
    });
    try {
      return strictJsonMap(json['result']);
    } on FormatException {
      throw const AdminRequestFailed('request_failed');
    }
  }
}

const _identityFields = {
  'id',
  'bank',
  'issuer',
  'card_name',
  'name',
  'network',
  'card_type',
  'annual_fee',
  'currency',
  'official_url',
  'image_url',
};
const _decisionFields = {
  'action',
  'reason',
  'change_type',
  'changeType',
  'dedupe_key',
  'dedupeKey',
  'display_priority',
  'is_primary',
  'benefit',
  'proposed',
  'edited_benefit',
  'editedBenefit',
};
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _sensitiveKey = RegExp(
  r'raw|body|statement|secret|token|password|authorization|provider_response|headers',
  caseSensitive: false,
);

Never _invalidAction() => throw const AdminRequestFailed('invalid_request');

void _validateAction(CardReviewAction action) {
  if (!_uuid.hasMatch(action.targetId) ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T',
        caseSensitive: false,
      ).hasMatch(action.observedUpdatedAt) ||
      DateTime.tryParse(action.observedUpdatedAt) == null) {
    _invalidAction();
  }
  final reason = action.reason?.trim();
  if (reason != null && (reason.isEmpty || reason.length > 1000)) {
    _invalidAction();
  }
  final requiresReason =
      action.operation == CardReviewOperation.reject ||
      action.operation == CardReviewOperation.quarantine;
  if (requiresReason && (reason == null || reason.length < 2)) {
    _invalidAction();
  }

  if (action.lane == CardReviewLane.identity) {
    if (action.stagingId != null ||
        action.operation == CardReviewOperation.quarantine ||
        action.operation == CardReviewOperation.unquarantine) {
      _invalidAction();
    }
    switch (action.operation) {
      case CardReviewOperation.editApprove:
        if (!_hasOnly(action.payload, {'proposed_fields'})) _invalidAction();
        final proposed = action.payload['proposed_fields'];
        if (proposed is! Map ||
            proposed.keys.any((key) => !_identityFields.contains(key)) ||
            proposed.entries.any(
              (entry) => !_validIdentityValue(entry.key, entry.value),
            )) {
          _invalidAction();
        }
      case CardReviewOperation.merge:
        if (!_hasOnly(action.payload, {'merge_card_id'}) ||
            action.payload['merge_card_id'] is! String ||
            !_uuid.hasMatch(action.payload['merge_card_id'] as String)) {
          _invalidAction();
        }
      case CardReviewOperation.approve:
      case CardReviewOperation.reject:
      case CardReviewOperation.retry:
        if (action.payload.isNotEmpty) _invalidAction();
      case CardReviewOperation.quarantine:
      case CardReviewOperation.unquarantine:
        _invalidAction();
    }
    return;
  }

  if (action.operation == CardReviewOperation.merge) _invalidAction();
  switch (action.operation) {
    case CardReviewOperation.approve:
    case CardReviewOperation.editApprove:
    case CardReviewOperation.reject:
      if (action.stagingId == null ||
          !_uuid.hasMatch(action.stagingId!) ||
          !_hasOnly(action.payload, {'decisions'})) {
        _invalidAction();
      }
      final decisions = action.payload['decisions'];
      if (decisions is! List || decisions.isEmpty || decisions.length > 50) {
        _invalidAction();
      }
      final accepted = switch (action.operation) {
        CardReviewOperation.approve => {'approve', 'keep_existing'},
        CardReviewOperation.editApprove => {'edit', 'keep_existing'},
        CardReviewOperation.reject => {'reject'},
        _ => const <String>{},
      };
      for (final decision in decisions) {
        if (decision is! Map ||
            decision.keys.any((key) => !_decisionFields.contains(key)) ||
            !accepted.contains(decision['action']) ||
            !_validDecisionValue(decision)) {
          _invalidAction();
        }
      }
    case CardReviewOperation.retry:
    case CardReviewOperation.quarantine:
    case CardReviewOperation.unquarantine:
      if (action.stagingId != null || action.payload.isNotEmpty) {
        _invalidAction();
      }
    case CardReviewOperation.merge:
      _invalidAction();
  }
}

bool _hasOnly(Map<String, dynamic> payload, Set<String> keys) =>
    payload.length == keys.length && payload.keys.toSet().containsAll(keys);

bool _validIdentityValue(Object? key, Object? value) {
  if (value is num) return value.isFinite;
  if (value is! String) return false;
  if (key is String && key.endsWith('_url')) return _safeHttpsUrl(value);
  return true;
}

bool _safeHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      value.length <= 2048;
}

bool _validDecisionValue(Object? value, [String key = '', int depth = 0]) {
  if (depth > 6 || _sensitiveKey.hasMatch(key)) return false;
  if (value == null || value is bool) return true;
  if (value is num) return value.isFinite;
  if (value is String) {
    if (value.length > 2000) return false;
    return key.toLowerCase().contains('url') ? _safeHttpsUrl(value) : true;
  }
  if (value is List) {
    return value.length <= 50 &&
        value.every((item) => _validDecisionValue(item, key, depth + 1));
  }
  if (value is Map) {
    return value.entries.every(
      (entry) =>
          entry.key is String &&
          _validDecisionValue(entry.value, entry.key as String, depth + 1),
    );
  }
  return false;
}
