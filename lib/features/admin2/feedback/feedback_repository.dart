import 'package:uuid/uuid.dart';

import '../data/admin_operator_repository.dart';
import 'feedback_models.dart';

final class FeedbackAdminRepository {
  const FeedbackAdminRepository(this._operator);
  final AdminOperatorRepository _operator;

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
      return AdminFeedbackDetail(
        id: row['id'] as String,
        feature: row['feature'] as String,
        feedbackText: row['feedback_text'] as String,
        capturedOutput: Map<String, dynamic>.from(
          row['captured_output'] as Map,
        ),
        safeContext: Map<String, dynamic>.from(row['safe_context'] as Map),
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
      );
    } catch (_) {
      throw const AdminRequestFailed('request_failed');
    }
  }

  Future<AdminFeedbackReceipt> act(AdminFeedbackAction action) async {
    final requestId = const Uuid().v4();
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
}
