import 'package:cardcompass/shared/models/reward_balance.dart';

/// Repository interface for reward balance operations
abstract class RewardBalanceRepository {
  /// Get all reward balances for a user
  Future<List<RewardBalance>> getUserRewardBalances(String userId);

  /// Get reward balances for a specific user card
  Future<List<RewardBalance>> getUserCardRewardBalances(String userCardId);

  /// Get a specific reward balance by ID
  Future<RewardBalance?> getRewardBalanceById(String balanceId);

  /// Update reward balance when new rewards are earned
  Future<String> updateRewardBalance({
    required String userId,
    required String userCardId,
    required String rewardType,
    required double rewardAmount,
    String? transactionId,
  });

  /// Create or update reward balance
  Future<void> upsertRewardBalance(RewardBalance rewardBalance);

  /// Get user's reward summary across all cards
  Future<Map<String, dynamic>> getUserRewardSummary(String userId);

  /// Redeem rewards
  Future<String> redeemRewards({
    required String userId,
    required String userCardId,
    required String rewardBalanceId,
    required double pointsToRedeem,
    required String redemptionType,
    required double redemptionValue,
    String? voucherDetails,
  });

  /// Get redemption history for a user
  Future<List<RewardRedemption>> getUserRedemptionHistory(
    String userId, {
    int? limit,
    String? status,
  });

  /// Get redemption history for a specific card
  Future<List<RewardRedemption>> getCardRedemptionHistory(
    String userCardId, {
    int? limit,
    String? status,
  });

  /// Update redemption status
  Future<void> updateRedemptionStatus({
    required String redemptionId,
    required String status,
    DateTime? completedDate,
  });

  /// Get rewards expiring soon (within specified days)
  Future<List<RewardBalance>> getExpiringRewards(
    String userId, {
    int daysAhead = 30,
  });

  /// Calculate total reward value for a user
  Future<double> getTotalRewardValue(
    String userId, {
    String? rewardType,
  });

  /// Get reward earning trends
  Future<List<Map<String, dynamic>>> getRewardEarningTrends(
    String userId, {
    int months = 12,
  });
}
