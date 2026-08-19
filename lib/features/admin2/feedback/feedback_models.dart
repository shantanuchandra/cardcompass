import 'dart:convert';
import 'package:uuid/uuid.dart';

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
    Map<String, dynamic> authoritativeContext = const {},
    Map<String, dynamic> inputFixture = const {},
    Map<String, dynamic> expectedOutput = const {},
    Map<String, dynamic> scoringRubric = const {},
    Map<String, dynamic> severeFailureConditions = const {},
    Map<String, dynamic> routeDestination = const {},
    this.operatorFeedback,
    this.reviewReason,
    List<AdminEvalCase> evalCases = const [],
  }) : capturedOutput = Map.unmodifiable(capturedOutput),
       safeContext = Map.unmodifiable(safeContext),
       advisoryExpectedOutput = Map.unmodifiable(advisoryExpectedOutput),
       authoritativeContext = Map.unmodifiable(authoritativeContext),
       inputFixture = Map.unmodifiable(inputFixture),
       expectedOutput = Map.unmodifiable(expectedOutput),
       scoringRubric = Map.unmodifiable(scoringRubric),
       severeFailureConditions = Map.unmodifiable(severeFailureConditions),
       routeDestination = Map.unmodifiable(routeDestination),
       evalCases = List.unmodifiable(evalCases);
  final String id,
      feature,
      feedbackText,
      triageStatus,
      reviewStatus,
      advisoryDiagnosis,
      advisorySeverity;
  final String? model, promptVersion, caseId, caseStatus;
  final String? provider, engineVersion, parserVersion, traceId;
  final String? operatorFeedback, reviewReason;
  final List<AdminEvalCase> evalCases;
  final int? caseRevision, approvedDatasetVersion, retiredDatasetVersion;
  final DateTime? approvedAt;
  final DateTime? caseUpdatedAt;
  final DateTime createdAt;
  final Map<String, dynamic> capturedOutput,
      safeContext,
      advisoryExpectedOutput,
      authoritativeContext,
      inputFixture,
      expectedOutput,
      scoringRubric,
      severeFailureConditions,
      routeDestination;
}

final class AdminEvalCase {
  AdminEvalCase({
    required this.id,
    required this.status,
    required this.revision,
    required this.updatedAt,
    required Map<String, dynamic> inputFixture,
    required Map<String, dynamic> capturedOutput,
    required Map<String, dynamic> expectedOutput,
    required this.operatorFeedback,
    required Map<String, dynamic> scoringRubric,
    required Map<String, dynamic> severeConditions,
    this.approvedDatasetVersion,
    this.retiredDatasetVersion,
    this.approvedAt,
    this.retiredAt,
  }) : inputFixture = Map.unmodifiable(inputFixture),
       capturedOutput = Map.unmodifiable(capturedOutput),
       expectedOutput = Map.unmodifiable(expectedOutput),
       scoringRubric = Map.unmodifiable(scoringRubric),
       severeConditions = Map.unmodifiable(severeConditions);
  final String id, status, operatorFeedback;
  final int revision;
  final DateTime updatedAt;
  final Map<String, dynamic> inputFixture,
      capturedOutput,
      expectedOutput,
      scoringRubric,
      severeConditions;
  final int? approvedDatasetVersion, retiredDatasetVersion;
  final DateTime? approvedAt, retiredAt;
}

final class AdminFeedbackListItem {
  const AdminFeedbackListItem({
    required this.id,
    required this.feature,
    required this.reviewStatus,
    required this.triageStatus,
    required this.severity,
    required this.createdAt,
  });
  final String id, feature, reviewStatus, triageStatus, severity;
  final DateTime createdAt;
}

final class AdminFeedbackPage {
  const AdminFeedbackPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });
  final List<AdminFeedbackListItem> items;
  final int page, limit, total;
  bool get hasMore => page * limit < total;
}

final class FeedbackTriageRetry {
  const FeedbackTriageRetry({
    required this.feedbackId,
    required this.requestId,
  });
  factory FeedbackTriageRetry.create(String feedbackId) =>
      FeedbackTriageRetry(feedbackId: feedbackId, requestId: const Uuid().v4());
  final String feedbackId, requestId;
}

final class AdminFeedbackAction {
  AdminFeedbackAction({
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
    this.dataIssueLane,
    this.dataIssueTargetId,
    this.groundTruthConfirmed = false,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final AdminFeedbackActionKind kind;
  final String feedbackId;
  final String? caseId, operatorBehavior, reason, confirmation;
  final bool groundTruthConfirmed;
  final String requestId;
  final String? dataIssueLane;
  final String? dataIssueTargetId;
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
