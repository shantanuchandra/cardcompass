import 'package:http/http.dart' as http;
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

Never throwAdminInvocationError(Object error) {
  if (error is FunctionException) {
    if (error.status == 401) throw AdminAuthorizationRequired();
    if (error.status == 403) throw AdminAccessDenied();
    final details = error.details;
    throw AdminCatalogRequestFailed(
      details is Map
          ? (details['error'] as String? ?? 'Admin request failed.')
          : 'Admin request failed.',
    );
  }
  if (error is http.ClientException &&
      error.message.toLowerCase().contains('failed to fetch')) {
    throw AdminCatalogRequestFailed(
      'Could not reach the admin service. Try again.',
    );
  }
  throw error;
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
  Future<void> retire(
    BenefitEnrichmentReview item,
    BenefitPossibleRemoval removal,
    String reason,
  );
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
  Future<void> approve(BenefitEnrichmentReview item) async {
    if (item.hasConflicts) {
      throw AdminCatalogRequestFailed(
        'Conflicting proposals require one explicit edit or rejection.',
      );
    }
    await _mutate('benefit-approve', item, decisions: _decisionsFor(item));
  }

  @override
  Future<void> editApprove(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  ) async {
    var submitted = decisions;
    if (item.hasConflicts) {
      _validateConflictResolutions(item, decisions);
      submitted = [..._derivedDecisionsForDiff(item), ...decisions];
    }
    await _mutate('benefit-edit-approve', item, decisions: submitted);
  }

  @override
  Future<void> reject(BenefitEnrichmentReview item, String reason) => _mutate(
    'benefit-reject',
    item,
    decisions: [BenefitReviewDecision(action: 'reject', reason: reason)],
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

  @override
  Future<void> retire(
    BenefitEnrichmentReview item,
    BenefitPossibleRemoval removal,
    String reason,
  ) {
    final normalizedReason = reason.trim();
    final liveBenefitId = removal.benefit.liveBenefitId;
    if (!removal.retirementEligible ||
        liveBenefitId == null ||
        normalizedReason.length < 3) {
      throw AdminCatalogRequestFailed(
        'An eligible benefit and a retirement reason are required.',
      );
    }
    return _mutate(
      'benefit-approve',
      item,
      decisions: [
        BenefitReviewDecision(
          action: 'retire',
          reason: normalizedReason,
          liveBenefitId: liveBenefitId,
          dedupeKey: removal.benefit.dedupeKey,
          benefit: removal.benefit,
        ),
      ],
    );
  }

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
          .map((decision) {
            final request = decision.toJson();
            if (item.parserVersion == 'benefits-v6') {
              // v6 keeps the server's classification visible in the DTO, but
              // the Edge validator recomputes it from locked staging rather
              // than accepting client publication authority.
              request.remove('change_type');
            }
            return request;
          })
          .toList(growable: false),
      'reason': ?reason,
    });
  }

  List<BenefitReviewDecision> _decisionsFor(BenefitEnrichmentReview item) {
    if (item.staging.decisions.isNotEmpty) return item.staging.decisions;
    return _derivedDecisionsForDiff(item);
  }

  List<BenefitReviewDecision> _derivedDecisionsForDiff(
    BenefitEnrichmentReview item,
  ) {
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
          changeType: change.changeType ?? 'modification',
          liveBenefitId: change.current.liveBenefitId,
          dedupeKey: change.proposed.dedupeKey ?? change.current.dedupeKey,
          benefit: change.proposed,
          proposed: change.proposed,
        ),
      ),
      ...diff.possibleRemovals.map(
        (removal) => BenefitReviewDecision(
          action: 'keep_existing',
          changeType: 'possible_removal',
          liveBenefitId: removal.benefit.liveBenefitId,
          dedupeKey: removal.benefit.dedupeKey,
          benefit: removal.benefit,
        ),
      ),
      ...diff.unchanged.map(
        (change) => BenefitReviewDecision(
          action: 'keep_existing',
          changeType: 'unchanged',
          liveBenefitId: change.current.liveBenefitId,
          dedupeKey: change.current.dedupeKey ?? change.proposed.dedupeKey,
          benefit: change.current,
          proposed: change.proposed,
        ),
      ),
    ];
  }

  void _validateConflictResolutions(
    BenefitEnrichmentReview item,
    List<BenefitReviewDecision> decisions,
  ) {
    final conflicts = item.staging.extractedData.diff.conflicts;
    String? proposalKey(BenefitProposal? proposal) =>
        proposal?.benefitId ?? proposal?.dedupeKey;
    String? targetKey(BenefitReviewDecision decision) {
      switch (decision.action.toLowerCase()) {
        case 'approve':
          if (decision.editedBenefit != null || decision.current != null) {
            return null;
          }
          return proposalKey(decision.benefit ?? decision.proposed);
        case 'edit':
          if (decision.editedBenefit == null || decision.current != null) {
            return null;
          }
          final editedKey = proposalKey(decision.editedBenefit);
          final stagedKey = proposalKey(decision.benefit ?? decision.proposed);
          return editedKey != null && editedKey == stagedKey ? editedKey : null;
        case 'reject':
          if (decision.current != null ||
              decision.liveBenefitId != null ||
              decision.editedBenefit != null ||
              decision.proposed != null) {
            return null;
          }
          return proposalKey(decision.benefit);
        default:
          return null;
      }
    }

    String? currentRejectKey(BenefitReviewDecision decision) {
      if (decision.action.toLowerCase() != 'reject' ||
          decision.benefit != null ||
          decision.proposed != null ||
          decision.editedBenefit != null ||
          decision.current == null ||
          decision.liveBenefitId == null ||
          decision.liveBenefitId != decision.current!.liveBenefitId) {
        return null;
      }
      return decision.liveBenefitId;
    }

    final keysByGroup = conflicts
        .map(
          (conflict) =>
              conflict.proposed.map(proposalKey).whereType<String>().toSet(),
        )
        .toList(growable: false);
    final decisionKeys = decisions.map(targetKey).toList(growable: false);
    final currentKeysByGroup = conflicts
        .map(
          (conflict) => conflict.current
              .map((current) => current.liveBenefitId)
              .whereType<String>()
              .toSet(),
        )
        .toList(growable: false);
    final currentDecisionKeys = decisions
        .map(currentRejectKey)
        .toList(growable: false);
    final complete = List.generate(conflicts.length, (group) {
      final proposalKeys = keysByGroup[group];
      if (proposalKeys.isNotEmpty) {
        return decisionKeys.where(proposalKeys.contains).length == 1;
      }
      final currentKeys = currentKeysByGroup[group];
      return currentKeys.isNotEmpty &&
          currentDecisionKeys.where(currentKeys.contains).length == 1;
    }).every((resolved) => resolved);
    final everyDecisionIsScoped = List.generate(decisions.length, (index) {
      final proposalKey = decisionKeys[index];
      final currentKey = currentDecisionKeys[index];
      final proposalGroups = proposalKey == null
          ? 0
          : keysByGroup.where((keys) => keys.contains(proposalKey)).length;
      final currentGroups = currentKey == null
          ? 0
          : currentKeysByGroup
                .where((keys) => keys.contains(currentKey))
                .length;
      return proposalGroups + currentGroups == 1;
    }).every((scoped) => scoped);
    final submittedCurrentKeys = currentDecisionKeys.whereType<String>().toList(
      growable: false,
    );
    final proposedConflictCount = keysByGroup
        .where((keys) => keys.isNotEmpty)
        .length;
    if (!complete ||
        !everyDecisionIsScoped ||
        submittedCurrentKeys.toSet().length != submittedCurrentKeys.length ||
        decisions.length !=
            proposedConflictCount + submittedCurrentKeys.length) {
      throw AdminCatalogRequestFailed(
        'Resolve every conflict with exactly one unchanged selection, edit, or targeted rejection.',
      );
    }
  }

  Future<JsonMap> _request(Map<String, dynamic> body) async {
    final AdminCatalogEntryResponse response;
    try {
      response = await _api.invoke(body);
    } catch (error) {
      throwAdminInvocationError(error);
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
