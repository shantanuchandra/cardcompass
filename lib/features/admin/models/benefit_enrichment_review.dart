typedef JsonMap = Map<String, dynamic>;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

num? _number(Object? value) => value is num ? value : null;

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<JsonMap> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false)
    : const <JsonMap>[];

class BenefitEnrichmentReviewPage {
  const BenefitEnrichmentReviewPage({
    required this.items,
    required this.counts,
    required this.page,
    required this.limit,
    required this.hasMore,
    this.history = const [],
    this.movieMappingHealth = const MovieBenefitMappingHealth(),
  });

  factory BenefitEnrichmentReviewPage.fromJson(JsonMap json) {
    return BenefitEnrichmentReviewPage(
      items: _maps(
        json['items'],
      ).map(BenefitEnrichmentReview.fromJson).toList(growable: false),
      counts: BenefitEnrichmentCounts.fromJson(
        _map(json['counts'] ?? json['run_counts']),
      ),
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 25,
      hasMore: json['has_more'] == true,
      history: _maps(
        json['history'],
      ).map(BenefitJobHistory.fromJson).toList(growable: false),
      movieMappingHealth: MovieBenefitMappingHealth.fromJson(
        _maps(json['movie_mapping_health']),
      ),
    );
  }

  final List<BenefitEnrichmentReview> items;
  final BenefitEnrichmentCounts counts;
  final int page;
  final int limit;
  final bool hasMore;
  final List<BenefitJobHistory> history;
  final MovieBenefitMappingHealth movieMappingHealth;

  BenefitEnrichmentReviewPage copyWith({
    List<BenefitEnrichmentReview>? items,
    BenefitEnrichmentCounts? counts,
    List<BenefitJobHistory>? history,
    MovieBenefitMappingHealth? movieMappingHealth,
  }) => BenefitEnrichmentReviewPage(
    items: items ?? this.items,
    counts: counts ?? this.counts,
    page: page,
    limit: limit,
    hasMore: hasMore,
    history: history ?? this.history,
    movieMappingHealth: movieMappingHealth ?? this.movieMappingHealth,
  );
}

class MovieBenefitMappingHealth {
  const MovieBenefitMappingHealth({
    this.active = 0,
    this.mapped = 0,
    this.orphaned = 0,
  });

  factory MovieBenefitMappingHealth.fromJson(List<JsonMap> rows) {
    final values = <String, int>{};
    for (final row in rows) {
      final metric = _text(row['metric']);
      if (metric != null) values[metric] = (row['value'] as num?)?.toInt() ?? 0;
    }
    return MovieBenefitMappingHealth(
      active: values['active_movie_benefits'] ?? 0,
      mapped: values['mapped_active_movie_benefits'] ?? 0,
      orphaned: values['orphaned_active_movie_benefits'] ?? 0,
    );
  }

  final int active;
  final int mapped;
  final int orphaned;
}

class BenefitEnrichmentCounts {
  const BenefitEnrichmentCounts({
    required this.total,
    required this.byStatus,
    required this.byRunMode,
  });

  factory BenefitEnrichmentCounts.fromJson(JsonMap json) =>
      BenefitEnrichmentCounts(
        total: (json['total'] as num?)?.toInt() ?? 0,
        byStatus: _numberMap(json['by_status']),
        byRunMode: _numberMap(json['by_run_mode']),
      );

  final int total;
  final Map<String, int> byStatus;
  final Map<String, int> byRunMode;

  static Map<String, int> _numberMap(Object? value) => _map(
    value,
  ).map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
}

class BenefitEnrichmentReview {
  const BenefitEnrichmentReview({
    required this.id,
    required this.cardId,
    required this.issuer,
    required this.cardName,
    required this.canonicalUrl,
    required this.parserVersion,
    required this.status,
    required this.runMode,
    required this.attemptCount,
    required this.stagingId,
    required this.failureCategory,
    required this.nextRetryAt,
    required this.proposedCount,
    required this.summary,
    required this.staging,
    required this.crawlerDiscoveredWithoutStatementSignal,
  });

  factory BenefitEnrichmentReview.fromJson(JsonMap json) {
    final card = _map(json['card']);
    return BenefitEnrichmentReview(
      id: _text(json['id']) ?? '',
      cardId: _text(json['card_id']) ?? _text(card['id']) ?? '',
      issuer: _text(json['issuer']) ?? _text(card['bank']) ?? 'Unknown issuer',
      cardName: _text(card['card_name']) ?? 'Unknown card',
      canonicalUrl: _text(json['canonical_url']),
      parserVersion: _text(json['parser_version']),
      status: _text(json['status']) ?? 'unknown',
      runMode: _text(json['run_mode']) ?? 'unknown',
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      stagingId: _text(json['staging_id']),
      failureCategory: _text(json['failure_category']),
      nextRetryAt: _text(json['next_retry_at']),
      proposedCount:
          (_map(json['normalized_fields'])['proposed_count'] as num?)
              ?.toInt() ??
          0,
      summary: BenefitRunSummary.fromJson(_map(json['result_summary'])),
      staging: BenefitStaging.fromJson(_map(json['staging'])),
      crawlerDiscoveredWithoutStatementSignal:
          json['crawler_discovered_without_statement_signal'] == true,
    );
  }

  final String id;
  final String cardId;
  final String issuer;
  final String cardName;
  final String? canonicalUrl;
  final String? parserVersion;
  final String status;
  final String runMode;
  final int attemptCount;
  final String? stagingId;
  final String? failureCategory;
  final String? nextRetryAt;
  final int proposedCount;
  final BenefitRunSummary summary;
  final BenefitStaging staging;
  final bool crawlerDiscoveredWithoutStatementSignal;

  bool get canReview =>
      status == 'staged' && staging.id != null && staging.status == 'pending';
  bool get isQuarantined => status == 'quarantined';
  bool get canQuarantine =>
      status == 'queued' || status == 'failed' || status == 'review_required';
}

class BenefitRunSummary {
  const BenefitRunSummary({
    this.runId,
    this.additions = 0,
    this.modifications = 0,
    this.possibleRemovals = 0,
    this.conflicts = 0,
    this.evidencePassed,
  });

  factory BenefitRunSummary.fromJson(JsonMap json) => BenefitRunSummary(
    runId: _text(json['run_id']),
    additions: (json['additions'] as num?)?.toInt() ?? 0,
    modifications: (json['modifications'] as num?)?.toInt() ?? 0,
    possibleRemovals: (json['possible_removals'] as num?)?.toInt() ?? 0,
    conflicts: (json['conflicts'] as num?)?.toInt() ?? 0,
    evidencePassed: json['evidence_passed'] as bool?,
  );

  final String? runId;
  final int additions;
  final int modifications;
  final int possibleRemovals;
  final int conflicts;
  final bool? evidencePassed;
}

class BenefitStaging {
  const BenefitStaging({
    this.id,
    this.status,
    this.sourceUrl,
    this.calculatedConfidence,
    this.validationWarnings = const [],
    this.sourceEvidence = const [],
    this.extractedData = const BenefitExtraction(),
    this.decisions = const [],
  });

  factory BenefitStaging.fromJson(JsonMap json) => BenefitStaging(
    id: _text(json['id']),
    status: _text(json['status']),
    sourceUrl: _text(json['source_url']),
    calculatedConfidence: _number(json['calculated_confidence']),
    validationWarnings: _maps(json['validation_warnings'])
        .map((row) => _text(row['code']) ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false),
    sourceEvidence: _maps(
      json['source_evidence'],
    ).map(BenefitSourceEvidence.fromJson).toList(growable: false),
    extractedData: BenefitExtraction.fromJson(_map(json['extracted_data'])),
    decisions: _maps(
      json['benefit_decisions'],
    ).map(BenefitReviewDecision.fromJson).toList(growable: false),
  );

  final String? id;
  final String? status;
  final String? sourceUrl;
  final num? calculatedConfidence;
  final List<String> validationWarnings;
  final List<BenefitSourceEvidence> sourceEvidence;
  final BenefitExtraction extractedData;
  final List<BenefitReviewDecision> decisions;

  bool get lacksStatementEvidence => validationWarnings.any(
    (warning) =>
        warning == 'crawler_discovered' ||
        warning == 'crawler_discovered_without_statement_signal',
  );
}

class BenefitExtraction {
  const BenefitExtraction({
    this.parserVersion,
    this.diff = const BenefitDiff(),
  });

  factory BenefitExtraction.fromJson(JsonMap json) => BenefitExtraction(
    parserVersion: _text(json['parser_version']),
    diff: BenefitDiff.fromJson(_map(json['diff'])),
  );

  final String? parserVersion;
  final BenefitDiff diff;
}

class BenefitDiff {
  const BenefitDiff({
    this.additions = const [],
    this.modifications = const [],
    this.possibleRemovals = const [],
    this.unchanged = const [],
    this.conflicts = const [],
  });

  factory BenefitDiff.fromJson(JsonMap json) => BenefitDiff(
    additions: _maps(
      json['additions'],
    ).map(BenefitProposal.fromJson).toList(growable: false),
    modifications: _maps(
      json['modifications'],
    ).map(BenefitModification.fromJson).toList(growable: false),
    possibleRemovals: _maps(json['possibleRemovals'])
        .map((row) => BenefitProposal.fromJson(_map(row['benefit'] ?? row)))
        .toList(growable: false),
    unchanged: _maps(
      json['unchanged'],
    ).map(BenefitModification.fromJson).toList(growable: false),
    conflicts: _maps(
      json['conflicts'],
    ).map(BenefitConflict.fromJson).toList(growable: false),
  );

  final List<BenefitProposal> additions;
  final List<BenefitModification> modifications;
  final List<BenefitProposal> possibleRemovals;
  final List<BenefitModification> unchanged;
  final List<BenefitConflict> conflicts;
}

class BenefitProposal {
  const BenefitProposal({
    this.dedupeKey,
    this.title,
    this.description,
    this.category,
    this.valueType,
    this.value,
    this.rate,
    this.cap,
    this.threshold,
    this.frequency,
    this.period,
    this.restrictions = const [],
    this.exclusions = const [],
    this.effectiveFrom,
    this.effectiveTo,
    this.sourceUrl,
    this.sourceUrls = const [],
    this.sourceExcerpt,
    this.contentHash,
    this.parserVersion,
    this.confidence = const {},
    this.evidence = const {},
    this.warnings = const [],
  });

  factory BenefitProposal.fromJson(JsonMap json) => BenefitProposal(
    dedupeKey: _text(json['dedupeKey']),
    title: _text(json['title']),
    description: _text(json['description']),
    category: _text(json['category']),
    valueType: _text(json['valueType']),
    value: json['value'],
    rate: json['rate'],
    cap: json['cap'],
    threshold: json['threshold'],
    frequency: _text(json['frequency']),
    period: _text(json['period']),
    restrictions: (json['restrictions'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    exclusions: (json['exclusions'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    effectiveFrom: _text(json['effectiveFrom']),
    effectiveTo: _text(json['effectiveTo']),
    sourceUrl: _text(json['sourceUrl']),
    sourceUrls: (json['sourceUrls'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    sourceExcerpt: _text(json['sourceExcerpt']),
    contentHash: _text(json['contentHash']),
    parserVersion: _text(json['parserVersion']),
    confidence: _map(
      json['confidence'],
    ).map((key, value) => MapEntry(key, value as num? ?? 0)),
    evidence: _map(
      json['evidence'],
    ).map((key, value) => MapEntry(key, value.toString())),
    warnings: (json['warnings'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
  );

  final String? dedupeKey;
  final String? title;
  final String? description;
  final String? category;
  final String? valueType;
  final Object? value;
  final Object? rate;
  final Object? cap;
  final Object? threshold;
  final String? frequency;
  final String? period;
  final List<String> restrictions;
  final List<String> exclusions;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String? sourceUrl;
  final List<String> sourceUrls;
  final String? sourceExcerpt;
  final String? contentHash;
  final String? parserVersion;
  final Map<String, num> confidence;
  final Map<String, String> evidence;
  final List<String> warnings;

  String get label => title ?? dedupeKey ?? 'Untitled benefit';

  BenefitProposal copyWith({String? title, String? description}) =>
      BenefitProposal(
        dedupeKey: dedupeKey,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category,
        valueType: valueType,
        value: value,
        rate: rate,
        cap: cap,
        threshold: threshold,
        frequency: frequency,
        period: period,
        restrictions: restrictions,
        exclusions: exclusions,
        effectiveFrom: effectiveFrom,
        effectiveTo: effectiveTo,
        sourceUrl: sourceUrl,
        sourceUrls: sourceUrls,
        sourceExcerpt: sourceExcerpt,
        contentHash: contentHash,
        parserVersion: parserVersion,
        confidence: confidence,
        evidence: evidence,
        warnings: warnings,
      );

  JsonMap toJson() => {
    if (dedupeKey != null) 'dedupeKey': dedupeKey,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    if (valueType != null) 'valueType': valueType,
    if (value != null) 'value': value,
    if (rate != null) 'rate': rate,
    if (cap != null) 'cap': cap,
    if (threshold != null) 'threshold': threshold,
    if (frequency != null) 'frequency': frequency,
    if (period != null) 'period': period,
    if (restrictions.isNotEmpty) 'restrictions': restrictions,
    if (exclusions.isNotEmpty) 'exclusions': exclusions,
    if (effectiveFrom != null) 'effectiveFrom': effectiveFrom,
    if (effectiveTo != null) 'effectiveTo': effectiveTo,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (sourceUrls.isNotEmpty) 'sourceUrls': sourceUrls,
    if (sourceExcerpt != null) 'sourceExcerpt': sourceExcerpt,
    if (contentHash != null) 'contentHash': contentHash,
    if (parserVersion != null) 'parserVersion': parserVersion,
    if (confidence.isNotEmpty) 'confidence': confidence,
    if (evidence.isNotEmpty) 'evidence': evidence,
    if (warnings.isNotEmpty) 'warnings': warnings,
  };
}

class BenefitModification {
  const BenefitModification({required this.current, required this.proposed});

  factory BenefitModification.fromJson(JsonMap json) => BenefitModification(
    current: BenefitProposal.fromJson(_map(json['current'])),
    proposed: BenefitProposal.fromJson(_map(json['proposed'])),
  );

  final BenefitProposal current;
  final BenefitProposal proposed;
}

class BenefitConflict {
  const BenefitConflict({
    this.code,
    this.current = const [],
    this.proposed = const [],
  });
  factory BenefitConflict.fromJson(JsonMap json) => BenefitConflict(
    code: _text(json['code']),
    current: _maps(
      json['current'],
    ).map(BenefitProposal.fromJson).toList(growable: false),
    proposed: _maps(
      json['proposed'],
    ).map(BenefitProposal.fromJson).toList(growable: false),
  );
  final String? code;
  final List<BenefitProposal> current;
  final List<BenefitProposal> proposed;
}

class BenefitSourceEvidence {
  const BenefitSourceEvidence({
    this.dedupeKey,
    this.sourceUrl,
    this.sourceExcerpt,
    this.evidence = const {},
  });
  factory BenefitSourceEvidence.fromJson(JsonMap json) => BenefitSourceEvidence(
    dedupeKey: _text(json['dedupe_key']),
    sourceUrl: _text(json['source_url']),
    sourceExcerpt: _text(json['source_excerpt']),
    evidence: _map(
      json['evidence'],
    ).map((key, value) => MapEntry(key, value.toString())),
  );
  final String? dedupeKey;
  final String? sourceUrl;
  final String? sourceExcerpt;
  final Map<String, String> evidence;
}

class BenefitReviewDecision {
  const BenefitReviewDecision({
    required this.action,
    this.reason,
    this.changeType,
    this.dedupeKey,
    this.displayPriority,
    this.isPrimary,
    this.benefit,
    this.proposed,
    this.editedBenefit,
  });
  factory BenefitReviewDecision.fromJson(JsonMap json) => BenefitReviewDecision(
    action: _text(json['action']) ?? '',
    reason: _text(json['reason']),
    changeType: _text(json['change_type'] ?? json['changeType']),
    dedupeKey: _text(json['dedupe_key'] ?? json['dedupeKey']),
    displayPriority: (json['display_priority'] as num?)?.toInt(),
    isPrimary: json['is_primary'] as bool?,
    benefit: json['benefit'] is Map
        ? BenefitProposal.fromJson(_map(json['benefit']))
        : null,
    proposed: json['proposed'] is Map
        ? BenefitProposal.fromJson(_map(json['proposed']))
        : null,
    editedBenefit: json['edited_benefit'] is Map
        ? BenefitProposal.fromJson(_map(json['edited_benefit']))
        : null,
  );
  final String action;
  final String? reason;
  final String? changeType;
  final String? dedupeKey;
  final int? displayPriority;
  final bool? isPrimary;
  final BenefitProposal? benefit;
  final BenefitProposal? proposed;
  final BenefitProposal? editedBenefit;

  JsonMap toJson() => {
    'action': action,
    if (reason != null) 'reason': reason,
    if (benefit != null) 'benefit': benefit!.toJson(),
    if (proposed != null) 'proposed': proposed!.toJson(),
    if (editedBenefit != null) 'edited_benefit': editedBenefit!.toJson(),
    if (changeType != null) 'change_type': changeType,
    if (dedupeKey != null) 'dedupe_key': dedupeKey,
    if (displayPriority != null) 'display_priority': displayPriority,
    if (isPrimary != null) 'is_primary': isPrimary,
  };
}

class BenefitJobHistory {
  const BenefitJobHistory({
    required this.jobId,
    required this.status,
    required this.runMode,
    this.updatedAt,
    this.runId,
  });
  factory BenefitJobHistory.fromJson(JsonMap json) => BenefitJobHistory(
    jobId: _text(json['job_id']) ?? '',
    status: _text(json['status']) ?? 'unknown',
    runMode: _text(json['run_mode']) ?? 'unknown',
    updatedAt: _text(json['updated_at']),
    runId: _text(json['run_id']),
  );
  final String jobId;
  final String status;
  final String runMode;
  final String? updatedAt;
  final String? runId;
}
