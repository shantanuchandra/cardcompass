import 'package:supabase_flutter/supabase_flutter.dart';

import 'card_identity_service.dart';

Map<String, dynamic> metadataWithCardDiscovery(
  Map<dynamic, dynamic>? value, {
  required String jobId,
  required String status,
}) {
  final metadata = Map<String, dynamic>.from(value ?? const {});
  metadata.remove('needsCardAssignment');
  metadata['cardDiscoveryJobId'] = jobId;
  metadata['cardDiscoveryStatus'] = status;
  return metadata;
}

Map<String, dynamic> metadataAfterCardDiscoveryResolved(
  Map<dynamic, dynamic>? value,
) {
  final metadata = Map<String, dynamic>.from(value ?? const {});
  metadata.remove('cardDiscoveryJobId');
  metadata.remove('cardDiscoveryStatus');
  return metadata;
}

class CardDiscoveryJob {
  const CardDiscoveryJob({
    required this.id,
    required this.status,
    this.resolvedCardId,
    this.failureCategory,
    this.retryAfter,
  });

  final String id;
  final String status;
  final String? resolvedCardId;
  final String? failureCategory;
  final DateTime? retryAfter;

  factory CardDiscoveryJob.fromJson(Map<String, dynamic> json) {
    final retry = json['retry_after'] ?? json['next_retry_at'];
    return CardDiscoveryJob(
      id: (json['job_id'] ?? json['id']) as String,
      status: json['status'] as String,
      resolvedCardId: json['resolved_card_id'] as String?,
      failureCategory: json['failure_category'] as String?,
      retryAfter: retry is String ? DateTime.tryParse(retry) : null,
    );
  }
}

class CardUrlResolution {
  const CardUrlResolution({
    required this.jobId,
    required this.status,
    this.resolvedCardId,
    this.reasonCode,
    this.retryAfter,
  });

  final String jobId;
  final String status;
  final String? resolvedCardId;
  final String? reasonCode;
  final DateTime? retryAfter;

  bool get isResolved => status == 'resolved' && resolvedCardId != null;
  bool get requiresReview => status == 'review_required';

  String get userMessage => switch (reasonCode) {
    'invalid_url' => 'Enter a valid HTTPS card page URL.',
    'unapproved_domain' => 'Use the official card page from this bank.',
    'issuer_mismatch' => 'That card page belongs to a different bank.',
    'not_product_page' => 'That URL does not appear to be a card product page.',
    'unsafe_redirect' => 'That card page redirects to an unsupported website.',
    'fetch_timeout' => 'The bank website took too long. Try again shortly.',
    'unsupported_content' => 'That card page format is not supported.',
    'identity_conflict' => 'The card details conflict with this statement.',
    'review_required' =>
      'CardCompass is reviewing this card while the remaining sync continues.',
    _ => 'Could not verify this card page. Try again.',
  };

  factory CardUrlResolution.fromJson(Map<String, dynamic> json) {
    final retry = json['retry_after'];
    const safeReasons = {
      'invalid_url',
      'unapproved_domain',
      'issuer_mismatch',
      'not_product_page',
      'unsafe_redirect',
      'fetch_timeout',
      'unsupported_content',
      'identity_conflict',
      'review_required',
    };
    final rawReason = json['reason_code'] as String?;
    return CardUrlResolution(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      resolvedCardId: json['resolved_card_id'] as String?,
      reasonCode: safeReasons.contains(rawReason) ? rawReason : null,
      retryAfter: retry is String ? DateTime.tryParse(retry) : null,
    );
  }
}

class CardDiscoveryService {
  CardDiscoveryService(this._db);

  final SupabaseClient _db;

  Future<CardDiscoveryJob> discover(CardIdentityEvidence evidence) async {
    final response = await _db.functions.invoke(
      'card-discovery',
      body: {'action': 'discover', 'evidence': evidence.toSafeJson()},
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Card discovery failed (${response.status})');
    }
    return CardDiscoveryJob.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CardUrlResolution> resolveUrl(
    CardIdentityEvidence evidence,
    String sourceUrl,
  ) async {
    final response = await _db.functions.invoke(
      'card-discovery',
      body: {
        'action': 'resolve_url',
        'evidence': evidence.toSafeJson(),
        'source_url': sourceUrl.trim(),
      },
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    if (response.status < 200 || response.status >= 300) {
      final reason = data['reason_code'] as String?;
      throw CardUrlResolutionException(reason);
    }
    return CardUrlResolution.fromJson(data);
  }

  Future<CardDiscoveryJob> status(String jobId) async {
    final response = await _db.functions.invoke(
      'card-discovery',
      body: {'action': 'status', 'job_id': jobId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Card discovery status failed (${response.status})');
    }
    return CardDiscoveryJob.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<CardDiscoveryJob>> resume() async {
    final response = await _db.functions.invoke(
      'card-discovery',
      body: const {'action': 'resume'},
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Card discovery resume failed (${response.status})');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['jobs'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => CardDiscoveryJob.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}

class CardUrlResolutionException implements Exception {
  CardUrlResolutionException(String? reasonCode)
    : reasonCode =
          const {
            'invalid_url',
            'unapproved_domain',
            'issuer_mismatch',
            'not_product_page',
            'unsafe_redirect',
            'fetch_timeout',
            'unsupported_content',
            'identity_conflict',
            'review_required',
          }.contains(reasonCode)
          ? reasonCode
          : null;

  final String? reasonCode;

  String get userMessage => CardUrlResolution(
    jobId: '',
    status: 'failed',
    reasonCode: reasonCode,
  ).userMessage;

  @override
  String toString() => userMessage;
}
