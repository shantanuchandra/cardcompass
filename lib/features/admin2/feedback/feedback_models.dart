import 'dart:convert';

enum AdminFeedbackActionKind {
  createDraft,
  approve,
  revise,
  retire,
  retryTriage,
  dataIssue,
  productDefect,
  dismiss,
}

final class AdminFeedbackDetail {
  AdminFeedbackDetail({
    required this.id,
    required this.feature,
    required this.feedbackText,
    required Map<String, dynamic> capturedOutput,
    required Map<String, dynamic> safeContext,
    required this.triageStatus,
    required this.reviewStatus,
    required this.advisoryDiagnosis,
    required this.advisorySeverity,
    required Map<String, dynamic> advisoryExpectedOutput,
    required this.model,
    required this.promptVersion,
    required this.createdAt,
    this.caseId,
    this.caseStatus,
    this.caseUpdatedAt,
    this.provider,
    this.engineVersion,
    this.parserVersion,
    this.traceId,
    this.caseRevision,
    this.approvedDatasetVersion,
    this.retiredDatasetVersion,
    this.approvedAt,
  }) : capturedOutput = Map.unmodifiable(capturedOutput),
       safeContext = Map.unmodifiable(safeContext),
       advisoryExpectedOutput = Map.unmodifiable(advisoryExpectedOutput);
  final String id,
      feature,
      feedbackText,
      triageStatus,
      reviewStatus,
      advisoryDiagnosis,
      advisorySeverity;
  final String? model, promptVersion, caseId, caseStatus;
  final String? provider, engineVersion, parserVersion, traceId;
  final int? caseRevision, approvedDatasetVersion, retiredDatasetVersion;
  final DateTime? approvedAt;
  final DateTime? caseUpdatedAt;
  final DateTime createdAt;
  final Map<String, dynamic> capturedOutput,
      safeContext,
      advisoryExpectedOutput;
}

final class AdminFeedbackAction {
  const AdminFeedbackAction({
    required this.kind,
    required this.feedbackId,
    this.caseId,
    this.observedUpdatedAt,
    this.operatorBehavior,
    this.expectedOutput,
    this.rubric,
    this.severeConditions,
    this.reason,
    this.confirmation,
    this.groundTruthConfirmed = false,
  });
  final AdminFeedbackActionKind kind;
  final String feedbackId;
  final String? caseId, operatorBehavior, reason, confirmation;
  final bool groundTruthConfirmed;
  final DateTime? observedUpdatedAt;
  final Map<String, dynamic>? expectedOutput, rubric, severeConditions;
}

final class AdminFeedbackReceipt {
  const AdminFeedbackReceipt({
    required this.status,
    required this.caseId,
    required this.updatedAt,
    required this.datasetVersion,
  });
  final String status;
  final String? caseId;
  final DateTime? updatedAt;
  final int? datasetVersion;
}

Map<String, dynamic> parseJsonObject(String value) {
  final parsed = jsonDecode(value);
  if (parsed is! Map<String, dynamic>) {
    throw const FormatException('Object required');
  }
  if (parsed.isEmpty ||
      parsed.entries.any(
        (entry) =>
            entry.key.trim().isEmpty ||
            entry.value == null ||
            entry.value is String && (entry.value as String).trim().isEmpty,
      )) {
    throw const FormatException('Meaningful object required');
  }
  return parsed;
}
