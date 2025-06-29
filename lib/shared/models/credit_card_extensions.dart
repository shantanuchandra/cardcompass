import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/reward_calculator.dart';

extension CreditCardExtension on CreditCard {
  RewardInfo getRewardInfo() {
    // Implement logic to fetch reward information based on card details
    // This is a placeholder, replace with actual logic
    String? issuer = 'unknown';
    double? rewardPercentage = 0.0;

    if (this.cardName.toLowerCase().contains('hdfc')) {
      issuer = 'hdfc';
      rewardPercentage = 0.25; // Assuming HDFC points
    } else if (this.cardName.toLowerCase().contains('icici')) {
      issuer = 'icici';
      rewardPercentage = 5.0; // Assuming ICICI cashback
    } else if (this.cardName.toLowerCase().contains('axis')) {
      issuer = 'axis';
      rewardPercentage = 0.0; // Assuming Axis discounts
    }

    return RewardInfo(issuer: issuer, rewardPercentage: rewardPercentage);
  }
}