import 'package:uuid/uuid.dart';

import '../data/admin_operator_repository.dart';
import 'feedback_models.dart';

final class FeedbackAdminRepository {
  FeedbackAdminRepository(this._operator);
  final AdminOperatorRepository _operator;
  Future<AdminFeedbackPage> list({
    int page = 1,
    int limit = 25,
    String? reviewStatus,
  }) async {
    final body = <String, dynamic>{'page': page, 'limit': limit};
    if (reviewStatus != null) {
      body['review_status'] = reviewStatus;
    }
    final json = await _operator.invoke('feedback-list', body);
    try {
      final items = (json['items'] as List)
          .map((value) {
            final row = Map<String, dynamic>.from(value as Map);
            return AdminFeedbackListItem(
              id: row['id'] as String,
              feature: row['feature'] as String,
              reviewStatus: row['review_status'] as String,
              triageStatus: row['triage_status'] as String,
              severity: row['severity'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
            );
          })
          .toList(growable: false);
      return AdminFeedbackPage(
        items: items,
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
      );
    } catch (_) {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<AdminFeedbackDetail> detail(String id) async {
    final json = await _operator.invoke('feedback-detail', {
      'feedback_id': id,
      'request_id': const Uuid().v4(),
    });
    try {
      final row = Map<String, dynamic>.from(json['feedback'] as Map);
      final triage = Map<String, dynamic>.from(row['triage_proposal'] as Map);
      final cases = (json['eval_cases'] as List).cast<Map>();
      final latest = cases.isEmpty
          ? null
          : Map<String, dynamic>.from(cases.first);
      final evalCases = cases
          .map((value) {
            final item = Map<String, dynamic>.from(value);
            return AdminEvalCase(
              id: item['id'] as String,
              status: item['status'] as String,
              revision: item['revision'] as int,
              updatedAt: DateTime.parse(item['updated_at'] as String),
              inputFixture: Map<String, dynamic>.from(
                item['input_fixture'] as Map,
              ),
              capturedOutput: Map<String, dynamic>.from(
                item['captured_output'] as Map,
              ),
              expectedOutput: Map<String, dynamic>.from(
                item['expected_output'] as Map,
              ),
              operatorFeedback: item['operator_feedback'] as String,
              scoringRubric: Map<String, dynamic>.from(
                item['scoring_rubric'] as Map,
              ),
              severeConditions: Map<String, dynamic>.from(
                item['severe_failure_conditions'] as Map,
              ),
              approvedDatasetVersion:
                  item['approved_in_dataset_version'] as int?,
              retiredDatasetVersion: item['retired_in_dataset_version'] as int?,
              approvedAt: item['approved_at'] == null
                  ? null
                  : DateTime.parse(item['approved_at'] as String),
              retiredAt: item['retired_at'] == null
                  ? null
                  : DateTime.parse(item['retired_at'] as String),
            );
          })
          .toList(growable: false);
      return AdminFeedbackDetail(
        id: row['id'] as String,
        feature: row['feature'] as String,
        feedbackText: row['feedback_text'] as String,
        capturedOutput: Map<String, dynamic>.from(
          row['captured_output'] as Map,
        ),
        safeContext: Map<String, dynamic>.from(row['safe_context'] as Map),
        authoritativeContext: Map<String, dynamic>.from(
          row['authoritative_context'] as Map? ?? const {},
        ),
        triageStatus: row['triage_status'] as String,
        reviewStatus: row['review_status'] as String,
        advisoryDiagnosis: triage['diagnosis'] as String? ?? '',
        advisorySeverity: row['severity'] as String,
        advisoryExpectedOutput: Map<String, dynamic>.from(
          triage['proposed_expected_output'] as Map? ?? const {},
        ),
        model: row['model'] as String?,
        promptVersion: row['prompt_version'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        caseId: latest?['id'] as String?,
        caseStatus: latest?['status'] as String?,
        caseUpdatedAt: latest == null
            ? null
            : DateTime.parse(latest['updated_at'] as String),
        provider: row['provider'] as String?,
        engineVersion: row['engine_version'] as String?,
        parserVersion: row['parser_version'] as String?,
        traceId: row['trace_id'] as String?,
        caseRevision: latest?['revision'] as int?,
        approvedDatasetVersion: latest?['approved_in_dataset_version'] as int?,
        retiredDatasetVersion: latest?['retired_in_dataset_version'] as int?,
        approvedAt: latest?['approved_at'] == null
            ? null
            : DateTime.parse(latest!['approved_at'] as String),
        inputFixture: Map<String, dynamic>.from(
          latest?['input_fixture'] as Map? ?? const {},
        ),
        expectedOutput: Map<String, dynamic>.from(
          latest?['expected_output'] as Map? ?? const {},
        ),
        operatorFeedback: latest?['operator_feedback'] as String?,
        scoringRubric: Map<String, dynamic>.from(
          latest?['scoring_rubric'] as Map? ?? const {},
        ),
        severeFailureConditions: Map<String, dynamic>.from(
          latest?['severe_failure_conditions'] as Map? ?? const {},
        ),
        routeDestination: Map<String, dynamic>.from(
          row['route_destination'] as Map? ?? const {},
        ),
        reviewReason: row['review_reason'] as String?,
        evalCases: evalCases,
      );
    } catch (_) {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<AdminFeedbackReceipt> act(AdminFeedbackAction action) async {
    final requestId = action.requestId;
    final isCase = {
      AdminFeedbackActionKind.approve,
      AdminFeedbackActionKind.revise,
      AdminFeedbackActionKind.retire,
    }.contains(action.kind);
    final name = switch (action.kind) {
      AdminFeedbackActionKind.createDraft => 'create_eval_draft',
      AdminFeedbackActionKind.dataIssue => 'data_issue',
      AdminFeedbackActionKind.productDefect => 'product_defect',
      AdminFeedbackActionKind.dismiss => 'dismiss',
      AdminFeedbackActionKind.approve => 'approve',
      AdminFeedbackActionKind.revise => 'revise',
      AdminFeedbackActionKind.retire => 'retire',
      AdminFeedbackActionKind.retryTriage => 'retry',
    };
    final payload = <String, dynamic>{
      'request_id': requestId,
      if (action.kind == AdminFeedbackActionKind.retryTriage)
        'feedback_id': action.feedbackId
      else if (isCase) ...{
        'case_id': action.caseId,
        'case_action': name,
        'observed_updated_at': action.observedUpdatedAt?.toIso8601String(),
        'confirmation': action.confirmation,
      } else ...{
        'feedback_id': action.feedbackId,
        'review_action': name,
      },
      if (action.operatorBehavior != null)
        'operator_feedback': action.operatorBehavior,
      if (action.kind == AdminFeedbackActionKind.createDraft ||
          action.kind == AdminFeedbackActionKind.revise)
        'ground_truth_confirmed': action.groundTruthConfirmed,
      if (action.expectedOutput != null)
        'expected_output': action.expectedOutput,
      if (action.rubric != null) 'scoring_rubric': action.rubric,
      if (action.severeConditions != null)
        'severe_failure_conditions': action.severeConditions,
      if (action.reason != null) 'reason': action.reason,
      if (action.kind == AdminFeedbackActionKind.dataIssue)
        'destination': {
          'lane': action.dataIssueLane,
          if (action.dataIssueTargetId != null)
            'target_id': action.dataIssueTargetId,
        },
    };
    final result = await _operator.invoke(
      action.kind == AdminFeedbackActionKind.retryTriage
          ? 'feedback-triage-retry'
          : isCase
          ? 'eval-case-action'
          : 'feedback-review',
      payload,
    );
    return AdminFeedbackReceipt(
      status:
          (result['status'] ??
                  result['review_status'] ??
                  result['triage_status'])
              as String,
      caseId: result['case_id'] as String?,
      updatedAt: result['updated_at'] == null
          ? null
          : DateTime.parse(result['updated_at'] as String),
      datasetVersion: result['dataset_version'] as int?,
    );
  }

  Future<AdminFeedbackReceipt> retryTriage(FeedbackTriageRetry mutation) => act(
    AdminFeedbackAction(
      kind: AdminFeedbackActionKind.retryTriage,
      feedbackId: mutation.feedbackId,
      requestId: mutation.requestId,
    ),
  );
}
