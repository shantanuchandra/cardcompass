import 'dart:convert';

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
    String? targetId,
  }) async {
    try {
      if (targetId != null && !_uuid.hasMatch(targetId)) {
        throw const FormatException('Invalid target');
      }
      final body = <String, dynamic>{
        'lane': lane.wireValue,
        'page': targetId == null ? page : 1,
        'limit': targetId == null ? limit : 1,
        'status': ?status,
        'target_id': ?targetId,
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
    final body = <String, dynamic>{
      'lane': action.lane.wireValue,
      'operation': action.operation.wireValue,
      'target_id': action.targetId,
      'request_id': requestId,
      'observed_updated_at': action.observedUpdatedAt,
      if (action.stagingId != null) 'staging_id': action.stagingId,
      if (action.reason != null) 'reason': action.reason,
      ...action.payload,
    };
    _validateRequestBytes({'action': 'card-review-action', ...body});
    final json = await _operator.invoke('card-review-action', body);
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
const _benefitFields = {
  'dedupe_key',
  'dedupeKey',
  'title',
  'description',
  'benefit_category',
  'category',
  'benefit_type',
  'valueType',
  'value_config',
  'valueConfig',
  'partners',
  'exclusions',
  'regions',
  'source_url',
  'sourceUrl',
  'valid_from',
  'effectiveFrom',
  'valid_until',
  'effectiveTo',
};
const _valueConfigFields = {
  'category',
  'discount_type',
  'unit',
  'currency_unit',
  'discount_percent',
  'discount_amount',
  'max_discount_per_transaction',
  'max_usage_per_month',
  'max_usage_per_period',
  'usage_period',
  'monthly_cap',
  'annual_cap',
  'milestone_type',
  'threshold_amount',
  'reward_value',
  'multiplier',
  'base_rate',
  'platform',
  'value',
  'rate',
  'cap',
  'threshold',
  'frequency',
  'period',
  'restrictions',
};

Never _invalidAction() => throw const AdminRequestFailed('invalid_request');

void _validateAction(CardReviewAction action) {
  if (!_uuid.hasMatch(action.targetId) ||
      action.observedUpdatedAt.length > 100 ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T',
        caseSensitive: false,
      ).hasMatch(action.observedUpdatedAt) ||
      DateTime.tryParse(action.observedUpdatedAt) == null) {
    _invalidAction();
  }
  final reason = action.reason?.trim();
  if (reason != null && reason.length > 1000) {
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
        CardReviewOperation.editApprove => {
          'approve',
          'edit',
          'reject',
          'keep_existing',
        },
        CardReviewOperation.reject => {'reject'},
        _ => const <String>{},
      };
      for (final decision in decisions) {
        if (decision is! Map ||
            decision.keys.any((key) => !_decisionFields.contains(key)) ||
            !accepted.contains(decision['action']) ||
            !_validDecision(decision.cast<Object?, Object?>())) {
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
  return value.length <= 500;
}

bool _safeHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      value.length <= 2048;
}

bool _validScalar(Object? value, String key) {
  if (value == null || value is bool) return true;
  if (value is num) return value.isFinite;
  if (value is! String || value.length > 2000) return false;
  return key.toLowerCase().contains('url') ? _safeHttpsUrl(value) : true;
}

bool _validBenefit(Object? value) {
  if (value is! Map || value.keys.any((key) => !_benefitFields.contains(key))) {
    return false;
  }
  for (final entry in value.entries) {
    final key = entry.key as String;
    if (key == 'value_config' || key == 'valueConfig') {
      if (entry.value is! Map ||
          (entry.value as Map).keys.any(
            (child) => !_valueConfigFields.contains(child),
          ) ||
          !(entry.value as Map).entries.every(
            (child) => child.key == 'restrictions'
                ? child.value is List &&
                      (child.value as List).length <= 50 &&
                      (child.value as List).every(
                        (item) => _validScalar(item, 'restrictions'),
                      )
                : _validScalar(child.value, child.key as String),
          )) {
        return false;
      }
    } else if (key == 'exclusions') {
      if (entry.value is! List ||
          (entry.value as List).length > 50 ||
          !(entry.value as List).every(
            (item) => _validScalar(item, 'exclusions'),
          )) {
        return false;
      }
    } else if (key == 'partners' || key == 'regions') {
      if (entry.value is! List ||
          (entry.value as List).length > 50 ||
          !(entry.value as List).every((item) => _validScalar(item, key))) {
        return false;
      }
    } else if (!_validScalar(entry.value, key)) {
      return false;
    }
  }
  return true;
}

bool _validDecision(Map<Object?, Object?> decision) {
  for (final key in [
    'benefit',
    'proposed',
    'edited_benefit',
    'editedBenefit',
  ]) {
    if (decision.containsKey(key) && !_validBenefit(decision[key])) {
      return false;
    }
  }
  for (final entry in decision.entries) {
    if ([
      'benefit',
      'proposed',
      'edited_benefit',
      'editedBenefit',
    ].contains(entry.key)) {
      continue;
    }
    if (entry.key is! String ||
        !_validScalar(entry.value, entry.key as String)) {
      return false;
    }
  }
  return true;
}

void _validateRequestBytes(Map<String, dynamic> request) {
  if (utf8.encode(jsonEncode(request)).length > 32768) _invalidAction();
}
