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
    const reserved = {
      'action',
      'lane',
      'operation',
      'target_id',
      'request_id',
      'observed_updated_at',
      'staging_id',
      'reason',
    };
    if (action.payload.keys.any(reserved.contains)) {
      throw const AdminRequestFailed('invalid_request');
    }
    final json = await _operator.invoke('card-review-action', {
      'lane': action.lane.wireValue,
      'operation': action.operation.wireValue,
      'target_id': action.targetId,
      'request_id': _requestIds(),
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
