enum SystemJobFamily {
  benefitEnrichment('benefit_enrichment', 'Benefit enrichment'),
  cardDiscovery('card_discovery', 'Card discovery');

  const SystemJobFamily(this.wireValue, this.label);
  final String wireValue;
  final String label;
  static SystemJobFamily parse(Object? value) => switch (value) {
    'benefit_enrichment' => benefitEnrichment,
    'card_discovery' => cardDiscovery,
    _ => throw const FormatException('Invalid system job family'),
  };
}

enum SystemJobAction { retry, quarantine, unquarantine }

enum SystemFailureCategory {
  sourceTimeout('source_timeout', 'Source timeout'),
  providerTimeout('provider_timeout', 'Provider timeout'),
  workerResourceLimit('worker_resource_limit', 'Worker resource limit'),
  manualQuarantine('manual_quarantine', 'Manually quarantined'),
  manualReview('manual_review', 'Manual review required'),
  ambiguousIdentity('ambiguous_identity', 'Ambiguous card identity'),
  fetchFailed('fetch_failed', 'Source fetch failed'),
  parseFailed('parse_failed', 'Source parsing failed'),
  validationFailed('validation_failed', 'Validation failed'),
  rateLimited('rate_limited', 'Provider rate limited'),
  notACard('not_a_card', 'Page is not a card'),
  ambiguousProduct('ambiguous_product', 'Ambiguous card product'),
  identityMismatch('identity_mismatch', 'Card identity mismatch'),
  unapprovedDomain('unapproved_domain', 'Domain is not approved'),
  unsupportedContent('unsupported_content', 'Unsupported source content'),
  unreachable('unreachable', 'Source is unreachable'),
  insufficientEvidence('insufficient_evidence', 'Insufficient evidence'),
  redirectRejected('redirect_rejected', 'Source redirect rejected'),
  privateAddress('private_address', 'Private source address rejected'),
  oversized('oversized', 'Source content is too large'),
  timeout('timeout', 'Enrichment timed out'),
  enrichmentFailed('enrichment_failed', 'Enrichment failed'),
  invalidUrl('invalid_url', 'Invalid source URL'),
  issuerMismatch('issuer_mismatch', 'Issuer does not match'),
  notProductPage('not_product_page', 'Source is not a product page'),
  unsafeRedirect('unsafe_redirect', 'Unsafe source redirect'),
  fetchTimeout('fetch_timeout', 'Source fetch timed out'),
  identityConflict('identity_conflict', 'Card identity conflict'),
  reviewRequired('review_required', 'Manual review required'),
  unknownFailure('unknown_failure', 'Unknown failure');

  const SystemFailureCategory(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static SystemFailureCategory? parse(Object? value) => switch (value) {
    null => null,
    'source_timeout' => sourceTimeout,
    'provider_timeout' => providerTimeout,
    'worker_resource_limit' => workerResourceLimit,
    'manual_quarantine' => manualQuarantine,
    'manual_review' => manualReview,
    'ambiguous_identity' => ambiguousIdentity,
    'fetch_failed' => fetchFailed,
    'parse_failed' => parseFailed,
    'validation_failed' => validationFailed,
    'rate_limited' => rateLimited,
    'not_a_card' => notACard,
    'ambiguous_product' => ambiguousProduct,
    'identity_mismatch' => identityMismatch,
    'unapproved_domain' => unapprovedDomain,
    'unsupported_content' => unsupportedContent,
    'unreachable' => unreachable,
    'insufficient_evidence' => insufficientEvidence,
    'redirect_rejected' => redirectRejected,
    'private_address' => privateAddress,
    'oversized' => oversized,
    'timeout' => timeout,
    'enrichment_failed' => enrichmentFailed,
    'invalid_url' => invalidUrl,
    'issuer_mismatch' => issuerMismatch,
    'not_product_page' => notProductPage,
    'unsafe_redirect' => unsafeRedirect,
    'fetch_timeout' => fetchTimeout,
    'identity_conflict' => identityConflict,
    'review_required' => reviewRequired,
    'unknown_failure' => unknownFailure,
    _ => throw const FormatException('Invalid failure category'),
  };
}

abstract final class SystemJobPolicy {
  static Set<SystemJobAction> actionsFor(
    SystemJobFamily family,
    String status,
  ) {
    if (family != SystemJobFamily.benefitEnrichment) return const {};
    return switch (status) {
      'queued' || 'staged' => const {SystemJobAction.quarantine},
      'failed' || 'review_required' => const {
        SystemJobAction.retry,
        SystemJobAction.quarantine,
      },
      'quarantined' => const {
        SystemJobAction.retry,
        SystemJobAction.unquarantine,
      },
      _ => const {},
    };
  }

  static bool allows(
    SystemJobFamily family,
    String status,
    SystemJobAction action,
  ) => actionsFor(family, status).contains(action);
}

enum PipelineHealth {
  healthy,
  degraded,
  paused,
  unknown;

  static PipelineHealth parse(Object? value) => switch (value) {
    'healthy' => healthy,
    'degraded' => degraded,
    'paused' => paused,
    'unknown' => unknown,
    _ => throw const FormatException('Invalid pipeline health'),
  };
}

enum SystemSourceError {
  sourceUnavailable;

  static SystemSourceError? parse(Object? value) => switch (value) {
    null => null,
    'source_unavailable' => sourceUnavailable,
    _ => throw const FormatException('Invalid source error'),
  };
}

final class PipelineSummary {
  const PipelineSummary({
    required this.key,
    required this.status,
    required this.queued,
    required this.running,
    required this.failed,
    required this.quarantined,
    required this.lastSuccessAt,
    required this.sourceError,
  });
  final SystemJobFamily key;
  final PipelineHealth status;
  final int queued;
  final int running;
  final int failed;
  final int quarantined;
  final DateTime? lastSuccessAt;
  final SystemSourceError? sourceError;

  factory PipelineSummary.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const {
      'key',
      'status',
      'queued',
      'running',
      'failed',
      'quarantined',
      'last_success_at',
      'source_error',
    });
    return PipelineSummary(
      key: SystemJobFamily.parse(json['key']),
      status: PipelineHealth.parse(json['status']),
      queued: _count(json['queued']),
      running: _count(json['running']),
      failed: _count(json['failed']),
      quarantined: _count(json['quarantined']),
      lastSuccessAt: _nullableDate(json['last_success_at']),
      sourceError: SystemSourceError.parse(json['source_error']),
    );
  }
}

final class RuntimeControl {
  const RuntimeControl({
    required this.isPaused,
    required this.reason,
    required this.updatedAt,
  });
  static const key = 'benefit_enrichment_scheduled';
  final bool isPaused;
  final String? reason;
  final DateTime updatedAt;
  factory RuntimeControl.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const {
      'control_key',
      'is_paused',
      'reason',
      'updated_at',
    });
    if (json['control_key'] != key || json['is_paused'] is! bool) {
      throw const FormatException('Invalid runtime control');
    }
    return RuntimeControl(
      isPaused: json['is_paused'] as bool,
      reason: _nullableString(json['reason']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class SystemStatusSnapshot {
  SystemStatusSnapshot({
    required List<PipelineSummary> pipelines,
    required List<RuntimeControl> controls,
    required this.controlSourceError,
    required this.refreshedAt,
  }) : pipelines = List.unmodifiable(pipelines),
       controls = List.unmodifiable(controls);
  final List<PipelineSummary> pipelines;
  final List<RuntimeControl> controls;
  final SystemSourceError? controlSourceError;
  final DateTime refreshedAt;
}

final class SystemJob {
  const SystemJob({
    required this.id,
    required this.family,
    required this.status,
    required this.failureCategory,
    required this.attemptCount,
    required this.nextRetryAt,
    required this.updatedAt,
  });
  final String id;
  final SystemJobFamily family;
  final String status;
  final SystemFailureCategory? failureCategory;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final DateTime updatedAt;
  factory SystemJob.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, const {
      'id',
      'family',
      'status',
      'failure_category',
      'attempt_count',
      'next_retry_at',
      'updated_at',
    });
    return SystemJob(
      id: _string(json['id']),
      family: SystemJobFamily.parse(json['family']),
      status: _string(json['status']),
      failureCategory: SystemFailureCategory.parse(json['failure_category']),
      attemptCount: _count(json['attempt_count']),
      nextRetryAt: _nullableDate(json['next_retry_at']),
      updatedAt: _date(json['updated_at']),
    );
  }
}

final class SystemJobsPage {
  SystemJobsPage({
    required List<SystemJob> items,
    required this.page,
    required this.limit,
    required this.hasMore,
  }) : items = List.unmodifiable(items);
  final List<SystemJob> items;
  final int page;
  final int limit;
  final bool hasMore;
}

sealed class SystemMutation {
  const SystemMutation();
}

sealed class SystemJobMutation extends SystemMutation {
  const SystemJobMutation({
    required this.family,
    required this.targetId,
    required this.status,
    required this.observedUpdatedAt,
  });
  final SystemJobFamily family;
  final String targetId;
  final String status;
  final String observedUpdatedAt;
}

final class RetrySystemJob extends SystemJobMutation {
  const RetrySystemJob({
    required super.family,
    required super.targetId,
    required super.status,
    required super.observedUpdatedAt,
  });
}

final class QuarantineSystemJob extends SystemJobMutation {
  const QuarantineSystemJob({
    required super.family,
    required super.targetId,
    required super.status,
    required super.observedUpdatedAt,
    required this.reason,
  });
  final String reason;
}

final class UnquarantineSystemJob extends SystemJobMutation {
  const UnquarantineSystemJob({
    required super.family,
    required super.targetId,
    required super.status,
    required super.observedUpdatedAt,
  });
}

sealed class SystemControlMutation extends SystemMutation {
  const SystemControlMutation({
    required this.observedUpdatedAt,
    required this.reason,
  });
  final String observedUpdatedAt;
  final String reason;
}

final class PauseSystemControl extends SystemControlMutation {
  const PauseSystemControl({
    required super.observedUpdatedAt,
    required super.reason,
  });
}

final class ResumeSystemControl extends SystemControlMutation {
  const ResumeSystemControl({
    required super.observedUpdatedAt,
    required super.reason,
  });
}

Map<String, dynamic> strictSystemMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid object');
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> strictSystemList(Object? value) {
  if (value is! List) throw const FormatException('Invalid list');
  return List<dynamic>.from(value);
}

void _exactKeys(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const FormatException('Invalid fields');
  }
}

String _string(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid string');
  }
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
int _count(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Invalid count');
  return value;
}

DateTime _date(Object? value) {
  final text = _string(value);
  final date = DateTime.tryParse(text);
  if (date == null || !text.contains('T')) {
    throw const FormatException('Invalid date');
  }
  return date.toUtc();
}

DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);
