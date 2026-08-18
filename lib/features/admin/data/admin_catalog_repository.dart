import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/benefit_enrichment_review.dart';

class AdminCatalogEntryResponse {
  const AdminCatalogEntryResponse(this.status, this.data);

  final int status;
  final Object? data;
}

abstract class AdminCatalogEntryApi {
  Future<AdminCatalogEntryResponse> invoke(Map<String, dynamic> body);
}

class SupabaseAdminCatalogEntryApi implements AdminCatalogEntryApi {
  SupabaseAdminCatalogEntryApi(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminCatalogEntryResponse> invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      'admin-catalog-entry',
      body: body,
    );
    return AdminCatalogEntryResponse(response.status, response.data);
  }
}

class AdminAuthorizationRequired implements Exception {}

class AdminAccessDenied implements Exception {}

class AdminCatalogRequestFailed implements Exception {
  AdminCatalogRequestFailed(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class BenefitEnrichmentRepository {
  Future<BenefitEnrichmentReviewPage> loadReviewPage({
    int page = 1,
    int limit = 25,
    String? status,
  });

  Future<void> approve(BenefitEnrichmentReview item);
  Future<void> editApprove(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  );
  Future<void> reject(BenefitEnrichmentReview item, String reason);
  Future<void> retry(BenefitEnrichmentReview item);
  Future<void> quarantine(BenefitEnrichmentReview item, String reason);
  Future<void> unquarantine(BenefitEnrichmentReview item);
}

class AdminCatalogRepository implements BenefitEnrichmentRepository {
  AdminCatalogRepository(this._api);

  factory AdminCatalogRepository.live() => AdminCatalogRepository(
    SupabaseAdminCatalogEntryApi(Supabase.instance.client),
  );

  final AdminCatalogEntryApi _api;

  @override
  Future<BenefitEnrichmentReviewPage> loadReviewPage({
    int page = 1,
    int limit = 25,
    String? status,
  }) async {
    final responses = await Future.wait([
      _request({
        'action': 'benefit-list',
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      }),
      _request({
        'action': 'benefit-status',
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      }),
    ]);
    final list = BenefitEnrichmentReviewPage.fromJson(responses.first);
    final statusPage = BenefitEnrichmentReviewPage.fromJson(responses.last);
    return list.copyWith(
      counts: statusPage.counts.total > 0 ? statusPage.counts : list.counts,
      history: statusPage.history,
      movieMappingHealth: statusPage.movieMappingHealth,
    );
  }

  @override
  Future<void> approve(BenefitEnrichmentReview item) =>
      _mutate('benefit-approve', item, decisions: _decisionsFor(item));

  @override
  Future<void> editApprove(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  ) => _mutate('benefit-edit-approve', item, decisions: decisions);

  @override
  Future<void> reject(BenefitEnrichmentReview item, String reason) => _mutate(
    'benefit-reject',
    item,
    decisions: _decisionsFor(item)
        .map(
          (decision) => BenefitReviewDecision(
            action: 'reject',
            benefit: decision.benefit,
            proposed: decision.proposed,
          ),
        )
        .toList(growable: false),
    reason: reason,
  );

  @override
  Future<void> retry(BenefitEnrichmentReview item) =>
      _request({'action': 'benefit-retry', 'job_id': item.id});

  @override
  Future<void> quarantine(BenefitEnrichmentReview item, String reason) =>
      _request({
        'action': 'benefit-quarantine',
        'job_id': item.id,
        'reason': reason,
      });

  @override
  Future<void> unquarantine(BenefitEnrichmentReview item) =>
      _request({'action': 'benefit-unquarantine', 'job_id': item.id});

  Future<void> _mutate(
    String action,
    BenefitEnrichmentReview item, {
    required List<BenefitReviewDecision> decisions,
    String? reason,
  }) async {
    final stagingId = item.staging.id ?? item.stagingId;
    if (stagingId == null || decisions.isEmpty) {
      throw AdminCatalogRequestFailed(
        'This enrichment has no reviewable staging decision.',
      );
    }
    await _request({
      'action': action,
      'job_id': item.id,
      'staging_id': stagingId,
      'decisions': decisions
          .map((decision) => decision.toJson())
          .toList(growable: false),
      'reason': ?reason,
    });
  }

  List<BenefitReviewDecision> _decisionsFor(BenefitEnrichmentReview item) {
    if (item.staging.decisions.isNotEmpty) return item.staging.decisions;
    final diff = item.staging.extractedData.diff;
    return [
      ...diff.additions.map(
        (benefit) => BenefitReviewDecision(
          action: 'approve',
          changeType: 'addition',
          dedupeKey: benefit.dedupeKey,
          benefit: benefit,
        ),
      ),
      ...diff.modifications.map(
        (change) => BenefitReviewDecision(
          action: 'approve',
          changeType: 'modification',
          dedupeKey: change.proposed.dedupeKey ?? change.current.dedupeKey,
          benefit: change.proposed,
          proposed: change.proposed,
        ),
      ),
      ...diff.possibleRemovals.map(
        (benefit) => BenefitReviewDecision(
          action: 'keep_existing',
          changeType: 'possible_removal',
          dedupeKey: benefit.dedupeKey,
          benefit: benefit,
        ),
      ),
      ...diff.unchanged.map(
        (change) => BenefitReviewDecision(
          action: 'keep_existing',
          changeType: 'unchanged',
          dedupeKey: change.current.dedupeKey ?? change.proposed.dedupeKey,
          benefit: change.current,
          proposed: change.proposed,
        ),
      ),
      ...diff.conflicts.expand(
        (conflict) => [
          ...conflict.current.map(
            (benefit) => BenefitReviewDecision(
              action: 'keep_existing',
              changeType: 'conflict',
              dedupeKey: benefit.dedupeKey,
              benefit: benefit,
            ),
          ),
          ...conflict.proposed.map(
            (benefit) => BenefitReviewDecision(
              action: 'approve',
              changeType: 'conflict',
              dedupeKey: benefit.dedupeKey,
              benefit: benefit,
              proposed: benefit,
            ),
          ),
        ],
      ),
    ];
  }

  Future<JsonMap> _request(Map<String, dynamic> body) async {
    final AdminCatalogEntryResponse response;
    try {
      response = await _api.invoke(body);
    } on FunctionException catch (error) {
      if (error.status == 401) throw AdminAuthorizationRequired();
      if (error.status == 403) throw AdminAccessDenied();
      final details = error.details;
      throw AdminCatalogRequestFailed(
        details is Map
            ? (details['error'] as String? ?? 'Admin request failed.')
            : 'Admin request failed.',
      );
    }
    if (response.status == 401) throw AdminAuthorizationRequired();
    if (response.status == 403) throw AdminAccessDenied();
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    if (response.status < 200 || response.status >= 300) {
      throw AdminCatalogRequestFailed(
        (data['error'] as String?) ?? 'Admin request failed.',
      );
    }
    return data;
  }
}
