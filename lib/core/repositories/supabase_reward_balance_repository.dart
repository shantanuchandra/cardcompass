import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/reward_balance_repository.dart';
import 'package:cardcompass/core/services/reward_intelligence_service.dart'
    show pointExpiryMonthsFor;
import 'package:cardcompass/shared/models/reward_balance.dart';
import 'package:cardcompass/core/repositories/supabase_helpers.dart';

/// Supabase implementation of RewardBalanceRepository.
///
/// Reward balances are derived entirely from `transactions.reward_earned` /
/// `reward_type` via the read-only `reward_balances` view (see
/// supabase/migrations/20260714030000_reward_balances_view.sql) — there is no
/// separate mutable balances table. Nothing in the product currently tracks
/// redemptions, so the redemption-related methods below intentionally throw
/// rather than pretend to succeed against data that doesn't exist.
class SupabaseRewardBalanceRepository implements RewardBalanceRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, String>> _cardNamesFor(List<String> userCardIds) async {
    if (userCardIds.isEmpty) return {};
    final response = await _supabase
        .from('user_cards')
        .select('id, card_catalog(bank, card_name)')
        .inFilter('id', userCardIds);

    final names = <String, String>{};
    for (final row in asList(response)) {
      final catalog = row['card_catalog'] as Map<String, dynamic>?;
      final bank = catalog?['bank'] as String? ?? '';
      final cardName = catalog?['card_name'] as String? ?? '';
      names[row['id'] as String] = '$bank $cardName'.trim();
    }
    return names;
  }

  Future<List<RewardBalance>> _toBalances(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final userCardIds = rows.map((r) => r['user_card_id'] as String).toSet().toList();
    final cardNames = await _cardNamesFor(userCardIds);

    return rows.map((json) {
      final userCardId = json['user_card_id'] as String;
      final lastEarnedAt = json['last_earned_at'] != null
          ? DateTime.parse(json['last_earned_at'])
          : DateTime.now();
      final expiryMonths = pointExpiryMonthsFor(cardNames[userCardId] ?? '');
      final expiryDate = expiryMonths >= 999
          ? null
          : DateTime(
              lastEarnedAt.year,
              lastEarnedAt.month + expiryMonths,
              lastEarnedAt.day,
            );

      return RewardBalance.fromJson({
        ...json,
        'expiry_date': expiryDate?.toIso8601String(),
      });
    }).toList();
  }

  @override
  Future<List<RewardBalance>> getUserRewardBalances(String userId) async {
    try {
      final response = await _supabase
          .from('reward_balances')
          .select()
          .eq('user_id', userId)
          .order('available_balance', ascending: false);

      return _toBalances(asList(response));
    } catch (error) {
      throw Exception('Failed to fetch user reward balances: $error');
    }
  }

  @override
  Future<List<RewardBalance>> getUserCardRewardBalances(String userCardId) async {
    try {
      final response = await _supabase
          .from('reward_balances')
          .select()
          .eq('user_card_id', userCardId)
          .order('available_balance', ascending: false);

      return _toBalances(asList(response));
    } catch (error) {
      throw Exception('Failed to fetch card reward balances: $error');
    }
  }

  @override
  Future<RewardBalance?> getRewardBalanceById(String balanceId) async {
    try {
      final response = await _supabase
          .from('reward_balances')
          .select()
          .eq('id', balanceId)
          .maybeSingle();

      if (response == null) return null;
      final balances = await _toBalances([response]);
      return balances.isEmpty ? null : balances.first;
    } catch (error) {
      return null;
    }
  }

  @override
  Future<String> updateRewardBalance({
    required String userId,
    required String userCardId,
    required String rewardType,
    required double rewardAmount,
    String? transactionId,
  }) {
    throw UnimplementedError(
      'reward_balances is derived from transactions.reward_earned; '
      'write reward_earned on the transaction instead of updating a balance directly.',
    );
  }

  @override
  Future<void> upsertRewardBalance(RewardBalance rewardBalance) {
    throw UnimplementedError(
      'reward_balances is a read-only view over transactions; '
      'there is no balance row to upsert.',
    );
  }

  @override
  Future<Map<String, dynamic>> getUserRewardSummary(String userId) async {
    try {
      final balances = await getUserRewardBalances(userId);

      final summary = <String, dynamic>{
        'totalPoints': 0.0,
        'totalCashback': 0.0,
        'totalMiles': 0.0,
        'expiringPoints': 0.0,
        'cardCount': balances.map((b) => b.userCardId).toSet().length,
        'categories': <Map<String, dynamic>>[],
      };

      final byType = <String, List<RewardBalance>>{};
      for (final balance in balances) {
        byType.putIfAbsent(balance.rewardType, () => []).add(balance);
      }

      for (final entry in byType.entries) {
        final rewardType = entry.key;
        final group = entry.value;
        final totalBalance = group.fold(0.0, (sum, b) => sum + b.availableBalance);
        final expiringSoon = group
            .where((b) => b.isExpiringSoon)
            .fold(0.0, (sum, b) => sum + b.availableBalance);

        summary['categories'].add({
          'rewardType': rewardType,
          'totalBalance': totalBalance,
          'totalEarned': group.fold(0.0, (sum, b) => sum + b.totalEarned),
          'totalRedeemed': group.fold(0.0, (sum, b) => sum + b.totalRedeemed),
          'cardsCount': group.map((b) => b.userCardId).toSet().length,
          'expiringSoon': expiringSoon,
        });

        switch (rewardType.toLowerCase()) {
          case 'points':
            summary['totalPoints'] = totalBalance;
            break;
          case 'cashback':
            summary['totalCashback'] = totalBalance;
            break;
          case 'miles':
            summary['totalMiles'] = totalBalance;
            break;
        }

        summary['expiringPoints'] = (summary['expiringPoints'] as double) + expiringSoon;
      }

      return summary;
    } catch (error) {
      throw Exception('Failed to get reward summary: $error');
    }
  }

  @override
  Future<String> redeemRewards({
    required String userId,
    required String userCardId,
    required String rewardBalanceId,
    required double pointsToRedeem,
    required String redemptionType,
    required double redemptionValue,
    String? voucherDetails,
  }) {
    throw UnimplementedError(
      'Reward redemption is not implemented — there is no data source '
      'tracking redemptions yet.',
    );
  }

  @override
  Future<List<RewardRedemption>> getUserRedemptionHistory(
    String userId, {
    int? limit,
    String? status,
  }) {
    throw UnimplementedError('Reward redemption history is not implemented.');
  }

  @override
  Future<List<RewardRedemption>> getCardRedemptionHistory(
    String userCardId, {
    int? limit,
    String? status,
  }) {
    throw UnimplementedError('Reward redemption history is not implemented.');
  }

  @override
  Future<void> updateRedemptionStatus({
    required String redemptionId,
    required String status,
    DateTime? completedDate,
  }) {
    throw UnimplementedError('Reward redemption is not implemented.');
  }

  @override
  Future<List<RewardBalance>> getExpiringRewards(
    String userId, {
    int daysAhead = 30,
  }) async {
    final balances = await getUserRewardBalances(userId);
    final cutoff = DateTime.now().add(Duration(days: daysAhead));
    return balances.where((b) {
      if (b.expiryDate == null || b.availableBalance <= 0) return false;
      return b.expiryDate!.isBefore(cutoff) && b.expiryDate!.isAfter(DateTime.now());
    }).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  }

  @override
  Future<double> getTotalRewardValue(
    String userId, {
    String? rewardType,
  }) async {
    final balances = await getUserRewardBalances(userId);
    final filtered = rewardType == null
        ? balances
        : balances.where((b) => b.rewardType == rewardType).toList();
    double total = 0.0;
    for (final b in filtered) {
      total += b.availableBalance;
    }
    return total;
  }

  @override
  Future<List<Map<String, dynamic>>> getRewardEarningTrends(
    String userId, {
    int months = 12,
  }) async {
    try {
      final startDate = DateTime.now().subtract(Duration(days: months * 30));

      final response = await _supabase
          .from('transactions')
          .select('reward_earned, reward_type, transaction_date')
          .eq('user_id', userId)
          .not('reward_earned', 'is', null)
          .gte('transaction_date', startDate.toIso8601String())
          .order('transaction_date', ascending: true);

      final Map<String, Map<String, double>> monthlyTrends = {};

      for (final transaction in asList(response)) {
        final transactionDate = DateTime.parse(transaction['transaction_date']);
        final monthKey =
            '${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}';
        final rewardType = transaction['reward_type'] ?? 'points';
        final rewardEarned = (transaction['reward_earned'] as num).toDouble();

        monthlyTrends[monthKey] ??= {};
        monthlyTrends[monthKey]![rewardType] =
            (monthlyTrends[monthKey]![rewardType] ?? 0.0) + rewardEarned;
      }

      final trends = <Map<String, dynamic>>[];
      for (final entry in monthlyTrends.entries) {
        trends.add({
          'month': entry.key,
          'rewards': entry.value,
          'total': entry.value.values.fold(0.0, (sum, value) => sum + value),
        });
      }

      return trends;
    } catch (error) {
      throw Exception('Failed to get reward earning trends: $error');
    }
  }
}
