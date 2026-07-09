import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/services/reward_calculator.dart';
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/transaction_repository.dart';

/// Default implementation of RecommendationService using RewardCalculator
class RecommendationServiceImpl implements RecommendationService {
  final RewardCalculator _rewardCalculator;
  final CardRepository _cardRepository;
  final TransactionRepository _transactionRepository;

  RecommendationServiceImpl({
    required MerchantRateService merchantRateService,
    required MilestoneTracker milestoneTracker,
    required CardRepository cardRepository,
    required TransactionRepository transactionRepository,
  })  : _cardRepository = cardRepository,
        _transactionRepository = transactionRepository,
        _rewardCalculator = RewardCalculator(
          merchantRateService: merchantRateService,
          milestoneTracker: milestoneTracker,
          cardRepository: cardRepository,
        );

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
    final cards = await _cardRepository.getUserCards(userId);
    return cards.take(limit).toList();
  }

  @override
  Future<CardRecommendationResult> getBestCardForTransaction({
    required String userId,
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    final userCards = await _cardRepository.getUserCards(userId);

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

    CreditCard? bestCard;
    double maxReward = 0.0;

    for (final card in userCards) {
      final reward = await _rewardCalculator.calculateRewardValue(
        card,
        amount,
        category,
        merchantName: merchantName,
      );
      if (reward > maxReward) {
        maxReward = reward;
        bestCard = card;
      }
    }

    return CardRecommendationResult(
      bestUserCard: bestCard,
      bestUserReward: maxReward,
      bestOverallCard: bestCard,
      bestOverallReward: maxReward,
      potentialSavings: maxReward,
      explanation: bestCard == null
          ? 'No suitable card found for this transaction'
          : 'Best card for this transaction: ${bestCard.cardName} with ₹${maxReward.toStringAsFixed(0)} reward',
    );
  }

  /// Compares what the user actually earned on each category against what
  /// their best-in-wallet card would have earned, surfacing categories
  /// where switching cards would have earned meaningfully more.
  @override
  Future<List<SpendingOptimization>> getSpendingOptimizations({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    if (cards.length < 2) return [];

    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: startDate ?? DateTime.now().subtract(const Duration(days: 60)),
      endDate: endDate,
    );

    final spendByCategory = <String, double>{};
    for (final t in transactions.where((t) => t.type == TransactionType.debit)) {
      spendByCategory[t.categoryString] = (spendByCategory[t.categoryString] ?? 0) + t.amount;
    }

    final optimizations = <SpendingOptimization>[];
    for (final entry in spendByCategory.entries) {
      final category = entry.key;
      final spend = entry.value;
      if (spend <= 0) continue;

      CreditCard? bestCard;
      double bestReward = -1;
      for (final card in cards) {
        final reward = await calculateReward(
          card: card,
          merchantName: '',
          category: category,
          amount: spend,
        );
        if (reward > bestReward) {
          bestReward = reward;
          bestCard = card;
        }
      }

      final flatReward = spend * 0.01;
      final upside = bestReward - flatReward;
      if (bestCard != null && upside > 50) {
        optimizations.add(SpendingOptimization(
          category: category,
          currentSpending: spend,
          potentialSavings: upside,
          suggestion: 'Route your $category spending through ${bestCard.cardName} to earn more rewards.',
          recommendedCard: bestCard,
        ));
      }
    }

    optimizations.sort((a, b) => b.potentialSavings.compareTo(a.potentialSavings));
    return optimizations.take(5).toList();
  }

  @override
  Future<List<CreditCard>> getNextCardRecommendations({
    required String userId,
    int limit = 3,
  }) async {
    return [];
  }

  @override
  Future<double> calculatePotentialSavings({
    required String userId,
    required String newCardId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return 0.0;
  }

  @override
  Future<Map<String, CreditCard>> getCategoryWiseBestCards({
    required String userId,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    final result = <String, CreditCard>{};
    for (final card in cards) {
      for (final category in card.rewardRates.keys) {
        final currentBest = result[category];
        if (currentBest == null || (card.rewardRates[category] ?? 0) > (currentBest.rewardRates[category] ?? 0)) {
          result[category] = card;
        }
      }
    }
    return result;
  }

  /// Surfaces reward balances that are meaningful enough to act on —
  /// currently: cards with an accumulated reward balance worth calling out.
  @override
  Future<List<RewardOptimization>> getRewardOptimizations({
    required String userId,
  }) async {
    final cards = await _cardRepository.getUserCards(userId);
    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: DateTime.now().subtract(const Duration(days: 30)),
    );

    final rewardsByCard = <String, double>{};
    for (final t in transactions) {
      if (t.userCardId == null || t.rewardEarned == null) continue;
      rewardsByCard[t.userCardId!] = (rewardsByCard[t.userCardId!] ?? 0) + t.rewardEarned!;
    }

    final results = <RewardOptimization>[];
    for (final card in cards) {
      final earned = rewardsByCard[card.id] ?? 0;
      if (earned <= 0) continue;
      results.add(RewardOptimization(
        title: '${card.cardName} rewards ready to redeem',
        description: 'You earned ₹${earned.toStringAsFixed(0)} in rewards on ${card.cardName} this month.',
        potentialReward: earned,
        actionRequired: 'Redeem via your card\'s rewards portal',
        relatedCard: card,
      ));
    }

    results.sort((a, b) => b.potentialReward.compareTo(a.potentialReward));
    return results;
  }

  @override
  Future<SpendingAnalysis> analyzeSpendingPatterns({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final transactions = await _transactionRepository.getUserTransactions(
      userId,
      startDate: startDate,
      endDate: endDate,
    );
    final debits = transactions.where((t) => t.type == TransactionType.debit);
    final totalSpending = debits.fold(0.0, (sum, t) => sum + t.amount);
    final totalRewards = transactions.fold(0.0, (sum, t) => sum + (t.rewardEarned ?? 0));
    final categoryBreakdown = <String, double>{};
    for (final t in debits) {
      categoryBreakdown[t.categoryString] = (categoryBreakdown[t.categoryString] ?? 0) + t.amount;
    }
    return SpendingAnalysis(
      totalSpending: totalSpending,
      totalRewards: totalRewards,
      categoryBreakdown: categoryBreakdown,
      monthlyTrend: const {},
      insights: totalSpending > 0
          ? ['You earned ${(totalRewards / totalSpending * 100).toStringAsFixed(1)}% back in rewards on your spending.']
          : [],
      rewardRate: totalSpending > 0 ? totalRewards / totalSpending : 0.0,
    );
  }
}
