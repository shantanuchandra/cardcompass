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
    final response = await _request({
      'action': 'benefit-list',
      'page': page,
      'limit': limit,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return BenefitEnrichmentReviewPage.fromJson(response);
  }

  @override
  Future<void> approve(BenefitEnrichmentReview item) =>
      _mutate('benefit-approve', item, decisions: item.staging.decisions);

  @override
  Future<void> editApprove(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  ) => _mutate('benefit-edit-approve', item, decisions: decisions);

  @override
  Future<void> reject(BenefitEnrichmentReview item, String reason) => _mutate(
    'benefit-reject',
    item,
    decisions: item.staging.decisions
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

  Future<JsonMap> _request(Map<String, dynamic> body) async {
    final response = await _api.invoke(body);
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
