import 'package:cardcompass/shared/models/credit_card.dart';

/// Service interface for recommendation operations
abstract class RecommendationService {
  /// Get credit card recommendations for user
  Future<List<CreditCard>> getCardRecommendations({
    required String userId,
    int limit = 5,
  });

  /// Get best card for a specific transaction
  Future<CardRecommendationResult> getBestCardForTransaction({
    required String userId,
    required String merchantName,
    required String category,
    required double amount,
  });

  /// Get spending optimization suggestions
  Future<List<SpendingOptimization>> getSpendingOptimizations({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get next card recommendation based on spending patterns
  Future<List<CreditCard>> getNextCardRecommendations({
    required String userId,
    int limit = 3,
  });

  /// Calculate potential savings with a new card
  Future<double> calculatePotentialSavings({
    required String userId,
    required String newCardId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get category-wise best cards
  Future<Map<String, CreditCard>> getCategoryWiseBestCards({
    required String userId,
  });

  /// Get reward optimization suggestions
  Future<List<RewardOptimization>> getRewardOptimizations({
    required String userId,
  });

  /// Analyze spending patterns
  Future<SpendingAnalysis> analyzeSpendingPatterns({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Calculate reward for a specific transaction using a credit card
  Future<double> calculateReward({
    required CreditCard card,
    required String merchantName,
    required String category,
    required double amount,
  });
}

/// Result of card recommendation for a transaction
class CardRecommendationResult {
  final CreditCard? bestUserCard;
  final double bestUserReward;
  final CreditCard? bestOverallCard;
  final double bestOverallReward;
  final double potentialSavings;
  final String explanation;

  CardRecommendationResult({
    this.bestUserCard,
    required this.bestUserReward,
    this.bestOverallCard,
    required this.bestOverallReward,
    required this.potentialSavings,
    required this.explanation,
  });
}

/// Spending optimization suggestion
class SpendingOptimization {
  final String category;
  final double currentSpending;
  final double potentialSavings;
  final String suggestion;
  final CreditCard? recommendedCard;

  SpendingOptimization({
    required this.category,
    required this.currentSpending,
    required this.potentialSavings,
    required this.suggestion,
    this.recommendedCard,
  });
}

/// Reward optimization suggestion
class RewardOptimization {
  final String title;
  final String description;
  final double potentialReward;
  final String actionRequired;
  final CreditCard? relatedCard;

  RewardOptimization({
    required this.title,
    required this.description,
    required this.potentialReward,
    required this.actionRequired,
    this.relatedCard,
  });
}

/// Spending analysis result
class SpendingAnalysis {
  final double totalSpending;
  final double totalRewards;
  final Map<String, double> categoryBreakdown;
  final Map<String, double> monthlyTrend;
  final List<String> insights;
  final double rewardRate;

  SpendingAnalysis({
    required this.totalSpending,
    required this.totalRewards,
    required this.categoryBreakdown,
    required this.monthlyTrend,
    required this.insights,
    required this.rewardRate,
  });
}
