import 'dart:convert';

/// Bounds caller-rendered feedback previews to 120 Unicode code points and
/// 256 UTF-8 bytes. It truncates only at a code-point boundary, so both the
/// visible sheet content and its derived semantic label share one safe value.
String boundedFeedbackPreview(
  String value, {
  int maxCodePoints = 120,
  int maxUtf8Bytes = 256,
}) {
  final codePoints = <int>[];
  var bytes = 0;
  for (final codePoint in value.runes) {
    final encodedLength = utf8.encode(String.fromCharCode(codePoint)).length;
    if (codePoints.length == maxCodePoints ||
        bytes + encodedLength > maxUtf8Bytes) {
      break;
    }
    codePoints.add(codePoint);
    bytes += encodedLength;
  }
  return String.fromCharCodes(codePoints);
}

sealed class FeedbackTarget {
  const FeedbackTarget(this.outputRefId);

  final String outputRefId;
  String get featureKey;
  String get outputRefType;
  String? get evaluationMode => null;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is FeedbackTarget &&
      other.outputRefId == outputRefId &&
      other.evaluationMode == evaluationMode;

  @override
  int get hashCode => Object.hash(runtimeType, outputRefId, evaluationMode);
}

final class TransactionFeedbackTarget extends FeedbackTarget {
  const TransactionFeedbackTarget(super.outputRefId);
  @override
  String get featureKey => 'statement_processing';
  @override
  String get outputRefType => 'transaction';
}

final class StatementFeedbackTarget extends FeedbackTarget {
  const StatementFeedbackTarget(super.outputRefId);
  @override
  String get featureKey => 'statement_processing';
  @override
  String get outputRefType => 'statement';
}

final class UserCardFeedbackTarget extends FeedbackTarget {
  const UserCardFeedbackTarget(
    super.outputRefId, {
    this.mode = CardDataFeedbackMode.catalogIdentityValidation,
  });
  final CardDataFeedbackMode mode;
  @override
  String get featureKey => 'card_data';
  @override
  String get outputRefType => 'user_card';
  @override
  String get evaluationMode => switch (mode) {
    CardDataFeedbackMode.catalogIdentityValidation =>
      'catalog_identity_validation',
    CardDataFeedbackMode.benefitExtraction => 'benefit_extraction',
  };
}

enum CardDataFeedbackMode { catalogIdentityValidation, benefitExtraction }

final class RecommendationFeedbackTarget extends FeedbackTarget {
  const RecommendationFeedbackTarget(super.outputRefId);
  @override
  String get featureKey => 'recommendation';
  @override
  String get outputRefType => 'recommendation_trace';
}

class RecommendationTraceInput {
  const RecommendationTraceInput({
    required this.safeInputContext,
    required this.outputSnapshot,
    required this.cardIds,
    required this.benefitIds,
  });

  final Map<String, Object?> safeInputContext;
  final Map<String, Object?> outputSnapshot;
  final List<String> cardIds;
  final List<String> benefitIds;
}

class FeedbackSubmission {
  const FeedbackSubmission({
    required this.target,
    required this.text,
    required this.requestId,
  });

  final FeedbackTarget target;
  final String text;
  final String requestId;
}

class FeedbackSubmitResult {
  const FeedbackSubmitResult(this.feedbackId, this.triageStatus);
  final String feedbackId;
  final String triageStatus;
}
