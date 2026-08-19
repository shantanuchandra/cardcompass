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

final class CardIdentityCandidate {
  CardIdentityCandidate({
    required this.id,
    this.bank,
    this.issuer,
    this.cardName,
    this.network,
    this.confidence,
  });

  final String id;
  final String? bank;
  final String? issuer;
  final String? cardName;
  final String? network;
  final double? confidence;

  factory CardIdentityCandidate.fromJson(Map<String, dynamic> json) =>
      CardIdentityCandidate(
        id: _requiredString(json['id']),
        bank: _optionalString(json['bank']),
        issuer: _optionalString(json['issuer']),
        cardName: _optionalString(json['card_name']),
        network: _optionalString(json['network']),
        confidence: _optionalNumber(json['confidence']),
      );
}

enum BenefitProposalKind { addition, modification, removal, unchanged }

final class BenefitReviewProposal {
  BenefitReviewProposal({
    required this.key,
    required this.kind,
    required Map<String, dynamic> current,
    required Map<String, dynamic> proposed,
  }) : current = _deepFreezeMap(current),
       proposed = _deepFreezeMap(proposed);

  final String key;
  final BenefitProposalKind kind;
  final Map<String, dynamic> current;
  final Map<String, dynamic> proposed;

  String get title =>
      _optionalString(proposed['title']) ??
      _optionalString(current['title']) ??
      key;

  bool get canApprove {
    final category = proposed['category'] ?? proposed['benefit_category'];
    return key.trim().length >= 3 &&
        (proposed['title']?.toString().trim().length ?? 0) >= 2 &&
        (category?.toString().trim().length ?? 0) >= 2;
  }

  Map<String, dynamic> decision(String action, {Map<String, dynamic>? edited}) {
    final result = <String, dynamic>{
      'action': action,
      'change_type': kind.name,
      'dedupe_key': key,
    };
    if (action == 'approve' && proposed.isNotEmpty) {
      result['proposed'] = proposed;
    }
    if (action == 'reject' && current.isNotEmpty) result['benefit'] = current;
    if (action == 'edit') result['edited_benefit'] = edited ?? proposed;
    return result;
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
    List<CardIdentityCandidate> identityCandidates = const [],
    List<BenefitReviewProposal> benefitProposals = const [],
    List<String> benefitConflictCodes = const [],
    this.confidence,
    this.stagingId,
    this.parserVersion,
    this.bank,
    this.cardName,
    this.retrievedAt,
  }) : evidence = List.unmodifiable(evidence),
       warningCodes = List.unmodifiable(warningCodes),
       proposedFields = _deepFreezeMap(proposedFields),
       identityCandidates = List.unmodifiable(identityCandidates),
       benefitProposals = List.unmodifiable(benefitProposals),
       benefitConflictCodes = List.unmodifiable(benefitConflictCodes);

  final String id;
  final CardReviewLane lane;
  final String status;
  final DateTime updatedAt;
  final List<CardEvidence> evidence;
  final List<String> warningCodes;
  final Map<String, dynamic> proposedFields;
  final List<CardIdentityCandidate> identityCandidates;
  final List<BenefitReviewProposal> benefitProposals;
  final List<String> benefitConflictCodes;
  final double? confidence;
  final String? stagingId;
  final String? parserVersion;
  final String? bank;
  final String? cardName;
  final DateTime? retrievedAt;

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
    final candidates = json['existing_candidates'];
    if (candidates != null && candidates is! List) {
      throw const FormatException('Invalid identity candidates');
    }
    final identityCandidates = candidates is List
        ? candidates
              .map((value) => CardIdentityCandidate.fromJson(_map(value)))
              .toList()
        : <CardIdentityCandidate>[];
    final staging = lane == CardReviewLane.benefit
        ? _nullableMap(json['staging'])
        : null;
    final extracted = _nullableMap(staging?['extracted_data']);
    final diff = _nullableMap(extracted?['diff']);
    final benefitProposals = diff == null
        ? <BenefitReviewProposal>[]
        : _parseBenefitProposals(diff);
    if (benefitProposals.map((value) => value.key).toSet().length !=
        benefitProposals.length) {
      throw const FormatException('Duplicate benefit proposal key');
    }
    final conflicts = diff?['conflicts'];
    final benefitConflictCodes = conflicts == null
        ? <String>[]
        : _list(conflicts)
              .map(_map)
              .map((value) => _optionalString(value['code']))
              .whereType<String>()
              .toList();
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
      identityCandidates: identityCandidates,
      benefitProposals: benefitProposals,
      benefitConflictCodes: benefitConflictCodes,
      confidence: (confidence as num?)?.toDouble(),
      stagingId: _optionalString(json['staging_id']),
      parserVersion: _optionalString(json['parser_version']),
      bank: _optionalString(card?['bank']),
      cardName: _optionalString(card?['card_name']),
      retrievedAt: _optionalDate(extracted?['retrieved_at']),
    );
  }
}

List<BenefitReviewProposal> _parseBenefitProposals(Map<String, dynamic> diff) {
  final proposals = <BenefitReviewProposal>[];
  void addSimple(String field, BenefitProposalKind kind) {
    final values = diff[field];
    if (values == null) return;
    for (final value in _list(values)) {
      final row = _map(value);
      final benefit = kind == BenefitProposalKind.removal
          ? _map(row['benefit'])
          : row;
      final key = _benefitKey(benefit);
      if (key == null) continue;
      proposals.add(
        BenefitReviewProposal(
          key: key,
          kind: kind,
          current: kind == BenefitProposalKind.removal ? benefit : const {},
          proposed: kind == BenefitProposalKind.addition ? benefit : const {},
        ),
      );
    }
  }

  addSimple('additions', BenefitProposalKind.addition);
  final modifications = diff['modifications'];
  if (modifications != null) {
    for (final value in _list(modifications)) {
      final row = _map(value);
      final current = _map(row['current']);
      final proposed = _map(row['proposed']);
      final key = _benefitKey(proposed) ?? _benefitKey(current);
      if (key == null) continue;
      proposals.add(
        BenefitReviewProposal(
          key: key,
          kind: BenefitProposalKind.modification,
          current: current,
          proposed: proposed,
        ),
      );
    }
  }
  addSimple('possibleRemovals', BenefitProposalKind.removal);
  final unchanged = diff['unchanged'];
  if (unchanged != null) {
    for (final value in _list(unchanged)) {
      final row = _map(value);
      final current = _map(row['current']);
      final proposed = _map(row['proposed']);
      final key = _benefitKey(proposed) ?? _benefitKey(current);
      if (key == null) continue;
      proposals.add(
        BenefitReviewProposal(
          key: key,
          kind: BenefitProposalKind.unchanged,
          current: current,
          proposed: proposed,
        ),
      );
    }
  }
  return proposals;
}

String? _benefitKey(Map<String, dynamic> benefit) =>
    _optionalString(benefit['dedupeKey'] ?? benefit['dedupe_key']);

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
  }) : payload = _deepFreezeMap(payload);

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
  return _deepFreezeMap(value);
}

Map<String, dynamic>? _nullableMap(Object? value) =>
    value == null ? null : _map(value);

List<dynamic> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected list');
  return List<dynamic>.unmodifiable(value.map(_deepFreezeJson));
}

Map<String, dynamic> _deepFreezeMap(Map<dynamic, dynamic> value) {
  final copied = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) throw const FormatException('Expected string keys');
    copied[key] = _deepFreezeJson(entry.value);
  }
  return UnmodifiableMapView(copied);
}

Object? _deepFreezeJson(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) throw const FormatException('Expected finite number');
    return value;
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepFreezeJson));
  }
  if (value is Map) return _deepFreezeMap(value);
  throw const FormatException('Expected JSON value');
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

double? _optionalNumber(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value.toDouble();
}
