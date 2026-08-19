import 'dart:collection';

enum CardReviewLane {
  identity('identity'),
  benefit('benefit');

  const CardReviewLane(this.wireValue);
  final String wireValue;

  static CardReviewLane parse(Object? value) => switch (value) {
    'identity' => identity,
    'benefit' => benefit,
    _ => throw const FormatException('Invalid card review lane'),
  };
}

enum CardReviewOperation {
  approve('approve'),
  editApprove('edit_approve'),
  merge('merge'),
  reject('reject'),
  retry('retry'),
  quarantine('quarantine'),
  unquarantine('unquarantine');

  const CardReviewOperation(this.wireValue);
  final String wireValue;
}

final class CardEvidence {
  const CardEvidence({
    this.officialUrl,
    this.sourceUrl,
    this.excerpt,
    this.retrievedAt,
  });

  final String? officialUrl;
  final String? sourceUrl;
  final String? excerpt;
  final DateTime? retrievedAt;

  factory CardEvidence.fromJson(Map<String, dynamic> json) {
    return CardEvidence(
      officialUrl: _optionalString(json['official_url']),
      sourceUrl: _optionalString(json['source_url']),
      excerpt: _optionalString(json['source_excerpt'] ?? json['excerpt']),
      retrievedAt: _optionalDate(json['retrieved_at']),
    );
  }
}

final class CardReviewItem {
  CardReviewItem({
    required this.id,
    required this.lane,
    required this.status,
    required this.updatedAt,
    required List<CardEvidence> evidence,
    required List<String> warningCodes,
    required Map<String, dynamic> proposedFields,
    this.confidence,
    this.stagingId,
    this.parserVersion,
    this.bank,
    this.cardName,
  }) : evidence = List.unmodifiable(evidence),
       warningCodes = List.unmodifiable(warningCodes),
       proposedFields = UnmodifiableMapView(Map.of(proposedFields));

  final String id;
  final CardReviewLane lane;
  final String status;
  final DateTime updatedAt;
  final List<CardEvidence> evidence;
  final List<String> warningCodes;
  final Map<String, dynamic> proposedFields;
  final double? confidence;
  final String? stagingId;
  final String? parserVersion;
  final String? bank;
  final String? cardName;

  factory CardReviewItem.fromJson(
    CardReviewLane lane,
    Map<String, dynamic> json,
  ) {
    final evidence = <CardEvidence>[];
    if (lane == CardReviewLane.identity) {
      final value = json['source_evidence'];
      if (value is! Map) throw const FormatException('Invalid evidence');
      evidence.add(CardEvidence.fromJson(_map(value)));
    } else {
      final staging = _nullableMap(json['staging']);
      final sourceEvidence = staging?['source_evidence'];
      if (sourceEvidence != null && sourceEvidence is! List) {
        throw const FormatException('Invalid source evidence');
      }
      if (sourceEvidence is List) {
        evidence.addAll(
          sourceEvidence.map((value) => CardEvidence.fromJson(_map(value))),
        );
      }
      final sourceUrl = staging?['source_url'];
      if (evidence.isEmpty && sourceUrl is String) {
        evidence.add(CardEvidence(sourceUrl: sourceUrl));
      }
    }
    final warnings = json['validation_warnings'];
    final warningCodes = warnings == null
        ? <String>[]
        : _list(
            warnings,
          ).map(_map).map((item) => _requiredString(item['code'])).toList();
    final card = _nullableMap(json['card']);
    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw const FormatException('Invalid confidence');
    }
    return CardReviewItem(
      id: _requiredString(json['id']),
      lane: lane,
      status: _requiredString(json['status']),
      updatedAt: _requiredDate(json['updated_at']),
      evidence: evidence,
      warningCodes: warningCodes,
      proposedFields: json['proposed_fields'] == null
          ? const {}
          : _map(json['proposed_fields']),
      confidence: (confidence as num?)?.toDouble(),
      stagingId: _optionalString(json['staging_id']),
      parserVersion: _optionalString(json['parser_version']),
      bank: _optionalString(card?['bank']),
      cardName: _optionalString(card?['card_name']),
    );
  }
}

final class CardReviewPage {
  CardReviewPage({
    required this.lane,
    required List<CardReviewItem> items,
    required this.page,
    required this.limit,
    required this.hasMore,
    required this.refreshedAt,
  }) : items = List.unmodifiable(items);

  final CardReviewLane lane;
  final List<CardReviewItem> items;
  final int page;
  final int limit;
  final bool hasMore;
  final DateTime refreshedAt;
}

final class CardReviewAction {
  CardReviewAction({
    required this.lane,
    required this.operation,
    required this.targetId,
    required this.observedUpdatedAt,
    this.stagingId,
    this.reason,
    Map<String, dynamic> payload = const {},
  }) : payload = UnmodifiableMapView(Map.of(payload));

  final CardReviewLane lane;
  final CardReviewOperation operation;
  final String targetId;
  final String observedUpdatedAt;
  final String? stagingId;
  final String? reason;
  final Map<String, dynamic> payload;
}

Map<String, dynamic> strictJsonMap(Object? value) => _map(value);
List<dynamic> strictJsonList(Object? value) => _list(value);
String strictJsonString(Object? value) => _requiredString(value);
DateTime strictJsonDate(Object? value) => _requiredDate(value);

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw const FormatException('Expected string keys');
  }
}

Map<String, dynamic>? _nullableMap(Object? value) =>
    value == null ? null : _map(value);

List<dynamic> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected list');
  return List<dynamic>.from(value);
}

String _requiredString(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Expected string');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  return _requiredString(value);
}

DateTime _requiredDate(Object? value) {
  final parsed = DateTime.tryParse(_requiredString(value));
  if (parsed == null) throw const FormatException('Expected timestamp');
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : _requiredDate(value);
