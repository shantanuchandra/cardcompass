sealed class FeedbackTarget {
  const FeedbackTarget(this.outputRefId);

  final String outputRefId;
  String get featureKey;
  String get outputRefType;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is FeedbackTarget &&
      other.outputRefId == outputRefId;

  @override
  int get hashCode => Object.hash(runtimeType, outputRefId);
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
  const UserCardFeedbackTarget(super.outputRefId);
  @override
  String get featureKey => 'card_data';
  @override
  String get outputRefType => 'user_card';
}

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
    required this.engineVersion,
  });

  final Map<String, Object?> safeInputContext;
  final Map<String, Object?> outputSnapshot;
  final List<String> cardIds;
  final List<String> benefitIds;
  final String engineVersion;
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
