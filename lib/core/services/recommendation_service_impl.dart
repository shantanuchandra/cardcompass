import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/services/reward_calculator.dart';
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';

/// Default implementation of RecommendationService using RewardCalculator
class RecommendationServiceImpl implements RecommendationService {
  final RewardCalculator _rewardCalculator;

  RecommendationServiceImpl({
    required MerchantRateService merchantRateService,
    required MilestoneTracker milestoneTracker,
  }) : _rewardCalculator = RewardCalculator(
          merchantRateService: merchantRateService,
          milestoneTracker: milestoneTracker,
          cardRepository: SupabaseCardRepository(),
        );

  @override
  @override
  Future<double> calculateReward({
    required CreditCard card,
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    return _rewardCalculator.calculateRewardValue(card, amount, category);
  }

  @override
  Future<List<CreditCard>> getCardRecommendations({
    required String userId,
    int limit = 5,
  }) async {
    // TODO: Implement card recommendation logic
    return [];
  }

  @override
  Future<CardRecommendationResult> getBestCardForTransaction({
    required String userId,
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    // Get user's cards
    final cardRepo = SupabaseCardRepository();
    final userCards = await cardRepo.getUserCards(userId);

    if (userCards.isEmpty) {
      return CardRecommendationResult(
        bestUserCard: null,
        bestUserReward: 0.0,
        bestOverallCard: null,
        bestOverallReward: 0.0,
        potentialSavings: 0.0,
        explanation: 'No cards found for user',
      );
    }

    // Calculate rewards for each card
    CreditCard? bestCard;
    double maxReward = 0.0;
    Map<CreditCard, double> cardRewards = {};

    for (final card in userCards) {
      final reward = await _rewardCalculator.calculateRewardValue(
        card,
        amount,
        category,
        merchantName: merchantName,
      );
      cardRewards[card] = reward;

      if (reward > maxReward) {
        maxReward = reward;
        bestCard = card;
      }
    }

    return CardRecommendationResult(
      bestUserCard: bestCard,
      bestUserReward: maxReward,
      bestOverallCard: bestCard, // Same as user card for now
      bestOverallReward: maxReward,
      potentialSavings: maxReward,
      explanation: 'Best card for this transaction: ${bestCard?.cardName} '
          'with ₹$maxReward reward',
    );
  }

  @override
  Future<List<SpendingOptimization>> getSpendingOptimizations({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // TODO: Implement spending optimization logic
    return [];
  }

  @override
  Future<List<CreditCard>> getNextCardRecommendations({
    required String userId,
    int limit = 3,
  }) async {
    // TODO: Implement next card recommendations logic
    return [];
  }

  @override
  Future<double> calculatePotentialSavings({
    required String userId,
    required String newCardId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // TODO: Implement potential savings calculation
    return 0.0;
  }

  @override
  Future<Map<String, CreditCard>> getCategoryWiseBestCards({
    required String userId,
  }) async {
    // TODO: Implement category-wise best cards logic
    return {};
  }

  @override
  Future<List<RewardOptimization>> getRewardOptimizations({
    required String userId,
  }) async {
    // TODO: Implement reward optimization logic
    return [];
  }

  @override
  Future<SpendingAnalysis> analyzeSpendingPatterns({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // TODO: Implement spending analysis logic
    return SpendingAnalysis(
      totalSpending: 0.0,
      totalRewards: 0.0,
      categoryBreakdown: {},
      monthlyTrend: {},
      insights: [],
      rewardRate: 0.0,
    );
  }
}
