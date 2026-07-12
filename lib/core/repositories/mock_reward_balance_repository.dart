import 'package:cardcompass/core/repositories/reward_balance_repository.dart';
import 'package:cardcompass/shared/models/reward_balance.dart';

/// Stub implementation for guest mode — all methods return empty/zero values.
class MockRewardBalanceRepository implements RewardBalanceRepository {
  @override
  Future<List<RewardBalance>> getUserRewardBalances(String userId) async => [];

  @override
  Future<List<RewardBalance>> getUserCardRewardBalances(
      String userCardId) async => [];

  @override
  Future<RewardBalance?> getRewardBalanceById(String balanceId) async => null;

  @override
  Future<String> updateRewardBalance({
    required String userId,
    required String userCardId,
    required String rewardType,
    required double rewardAmount,
    String? transactionId,
  }) async => '';

  @override
  Future<void> upsertRewardBalance(RewardBalance rewardBalance) async {}

  @override
  Future<Map<String, dynamic>> getUserRewardSummary(String userId) async => {};

  @override
  Future<String> redeemRewards({
    required String userId,
    required String userCardId,
    required String rewardBalanceId,
    required double pointsToRedeem,
    required String redemptionType,
    required double redemptionValue,
    String? voucherDetails,
  }) async => '';

  @override
  Future<List<RewardRedemption>> getUserRedemptionHistory(
    String userId, {
    int? limit,
    String? status,
  }) async => [];

  @override
  Future<List<RewardRedemption>> getCardRedemptionHistory(
    String userCardId, {
    int? limit,
    String? status,
  }) async => [];

  @override
  Future<void> updateRedemptionStatus({
    required String redemptionId,
    required String status,
    DateTime? completedDate,
  }) async {}

  @override
  Future<List<RewardBalance>> getExpiringRewards(
    String userId, {
    int daysAhead = 30,
  }) async => [];

  @override
  Future<double> getTotalRewardValue(
    String userId, {
    String? rewardType,
  }) async => 0.0;

  @override
  Future<List<Map<String, dynamic>>> getRewardEarningTrends(
    String userId, {
    int months = 12,
  }) async => [];
}
