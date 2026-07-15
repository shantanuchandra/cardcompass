import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/merchant_rate_service.dart';
import 'package:cardcompass/core/services/milestone_tracker.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';

/// Service for calculating and comparing credit card rewards
class RewardCalculator {
  // Services
  final MerchantRateService merchantRateService;
  final MilestoneTracker milestoneTracker;
  final CardRepository cardRepository;

  RewardCalculator({
    required this.merchantRateService,
    required this.milestoneTracker,
    required this.cardRepository,
  });

  /// Convert card-specific rewards to standardized ₹ value
  Future<double> calculateRewardValue(
      CreditCard card, double amount, String category,
      {String? merchantName}) async {
    // Get base reward from card benefits in database
    double baseReward = await cardRepository
        .calculateReward(
          cardId: card.catalogCardId ?? card.id,
          category: category,
          amount: amount,
        )
        .catchError((_) => 0.0);

    // Amazon Pay ICICI's headline Amazon cashback is merchant-specific, not a
    // generic shopping-category multiplier. Prime eligibility is not yet part
    // of the user profile, so the analyzer uses the card's 5% Prime rate.
    if (_isAmazonPayIcici(card) && _isAmazonMerchant(merchantName)) {
      return amount * 0.05 + milestoneTracker.applyMilestoneBonus(amount);
    }

    // Apply combined merchant and category rates
    if (merchantName != null) {
      baseReward *= merchantRateService.getCombinedRate(merchantName, category);
    } else {
      // Apply just category rate if no merchant specified
      baseReward *= merchantRateService.getCategoryRate(category);
    }

    // Apply milestone bonuses
    baseReward += milestoneTracker.applyMilestoneBonus(amount);

    return baseReward;
  }

  bool _isAmazonPayIcici(CreditCard card) {
    final bank = card.bankName.toLowerCase();
    final name = card.cardName.toLowerCase();
    return bank.contains('icici') &&
        name.contains('amazon') &&
        name.contains('pay');
  }

  bool _isAmazonMerchant(String? merchantName) =>
      merchantName?.toLowerCase().contains('amazon') ?? false;
}

class RewardInfo {
  final String? issuer;
  final double? rewardPercentage;

  RewardInfo({this.issuer, this.rewardPercentage});
}

extension RewardCalculatorExtensions on RewardCalculator {
  /// Compare two cards based on reward value for a transaction
  Future<int> compareCards(
      CreditCard card1, CreditCard card2, double amount, String category,
      {String? merchantName}) async {
    final reward1 = await calculateRewardValue(card1, amount, category,
        merchantName: merchantName);
    final reward2 = await calculateRewardValue(card2, amount, category,
        merchantName: merchantName);

    return reward1.compareTo(reward2);
  }

  /// Get the best card from a list for a specific category
  Future<CreditCard?> getBestCardForCategory(
      List<CreditCard> cards, String category, double amount,
      {String? merchantName}) async {
    if (cards.isEmpty) return null;

    CreditCard? bestCard;
    double maxReward = 0.0;

    for (final card in cards) {
      final reward = await calculateRewardValue(card, amount, category,
          merchantName: merchantName);
      if (reward > maxReward) {
        maxReward = reward;
        bestCard = card;
      }
    }

    return bestCard;
  }
}
