import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/reward_balance_repository.dart';
import 'package:cardcompass/shared/models/reward_balance.dart';
import 'package:cardcompass/core/repositories/supabase_helpers.dart';

/// Supabase implementation of RewardBalanceRepository
class SupabaseRewardBalanceRepository implements RewardBalanceRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<List<RewardBalance>> getUserRewardBalances(String userId) async {
    try {
      final response = await _supabase
          .from('reward_balances')
          .select()
          .eq('user_id', userId)
          .order('available_balance', ascending: false);

      return asList(response)
          .map((json) => RewardBalance.fromJson(json))
          .toList();
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

      return asList(response)
          .map((json) => RewardBalance.fromJson(json))
          .toList();
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
          .single();

      return RewardBalance.fromJson(response);
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
  }) async {
    try {
      final response = await _supabase.rpc('update_reward_balance', params: {
        '_user_id': userId,
        '_user_card_id': userCardId,
        '_reward_type': rewardType,
        '_reward_amount': rewardAmount,
        '_transaction_id': transactionId,
      });

      return response as String;
    } catch (error) {
      throw Exception('Failed to update reward balance: $error');
    }
  }

  @override
  Future<void> upsertRewardBalance(RewardBalance rewardBalance) async {
    try {
      await _supabase
          .from('reward_balances')
          .upsert(rewardBalance.toJson(), onConflict: 'user_card_id,reward_type');
    } catch (error) {
      throw Exception('Failed to upsert reward balance: $error');
    }
  }

  @override
  Future<Map<String, dynamic>> getUserRewardSummary(String userId) async {
    try {
      final response = await _supabase.rpc('get_user_reward_summary', params: {
        '_user_id': userId,
      });

      final summary = <String, dynamic>{
        'totalPoints': 0.0,
        'totalCashback': 0.0,
        'totalMiles': 0.0,
        'expiringPoints': 0.0,
        'cardCount': 0,
        'categories': <Map<String, dynamic>>[],
      };

      for (final item in asList(response)) {
        final rewardType = item['reward_type'] as String;
        final totalBalance = (item['total_balance'] as num).toDouble();
        final expiringSoon = (item['expiring_soon'] as num).toDouble();
        final cardsCount = item['cards_count'] as int;

        summary['categories'].add({
          'rewardType': rewardType,
          'totalBalance': totalBalance,
          'totalEarned': (item['total_earned'] as num).toDouble(),
          'totalRedeemed': (item['total_redeemed'] as num).toDouble(),
          'cardsCount': cardsCount,
          'expiringSoon': expiringSoon,
        });

        // Aggregate totals
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

        summary['expiringPoints'] = 
            (summary['expiringPoints'] as double) + expiringSoon;
        summary['cardCount'] = 
            (summary['cardCount'] as int) + cardsCount;
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
  }) async {
    try {
      final response = await _supabase.rpc('redeem_rewards', params: {
        '_user_id': userId,
        '_user_card_id': userCardId,
        '_reward_balance_id': rewardBalanceId,
        '_points_to_redeem': pointsToRedeem,
        '_redemption_type': redemptionType,
        '_redemption_value': redemptionValue,
        '_voucher_details': voucherDetails,
      });

      return response as String;
    } catch (error) {
      throw Exception('Failed to redeem rewards: $error');
    }
  }  @override
  Future<List<RewardRedemption>> getUserRedemptionHistory(
    String userId, {
    int? limit,
    String? status,
  }) async {
    try {
      var query = _supabase
          .from('reward_redemptions')
          .select()
          .eq('user_id', userId);

      if (status != null) {
        query = query.eq('status', status);
      }

      var orderedQuery = query.order('redemption_date', ascending: false);

      if (limit != null) {
        orderedQuery = orderedQuery.limit(limit);
      }

      final response = await orderedQuery;

      return asList(response)
          .map((json) => RewardRedemption.fromJson(json))
          .toList();
    } catch (error) {
      throw Exception('Failed to fetch redemption history: $error');
    }
  }
  @override
  Future<List<RewardRedemption>> getCardRedemptionHistory(
    String userCardId, {
    int? limit,
    String? status,
  }) async {
    try {
      var query = _supabase
          .from('reward_redemptions')
          .select()
          .eq('user_card_id', userCardId);

      if (status != null) {
        query = query.eq('status', status);
      }

      var orderedQuery = query.order('redemption_date', ascending: false);

      if (limit != null) {
        orderedQuery = orderedQuery.limit(limit);
      }

      final response = await orderedQuery;

      return asList(response)
          .map((json) => RewardRedemption.fromJson(json))
          .toList();
    } catch (error) {
      throw Exception('Failed to fetch card redemption history: $error');
    }
  }

  @override
  Future<void> updateRedemptionStatus({
    required String redemptionId,
    required String status,
    DateTime? completedDate,
  }) async {
    try {
      final updateData = {
        'status': status,
        if (completedDate != null) 'completed_date': completedDate.toIso8601String(),
      };

      await _supabase
          .from('reward_redemptions')
          .update(updateData)
          .eq('id', redemptionId);
    } catch (error) {
      throw Exception('Failed to update redemption status: $error');
    }
  }

  @override
  Future<List<RewardBalance>> getExpiringRewards(
    String userId, {
    int daysAhead = 30,
  }) async {
    try {
      final cutoffDate = DateTime.now().add(Duration(days: daysAhead));

      final response = await _supabase
          .from('reward_balances')
          .select()
          .eq('user_id', userId)
          .not('expiry_date', 'is', null)
          .lte('expiry_date', cutoffDate.toIso8601String())
          .gt('expiry_date', DateTime.now().toIso8601String())
          .gt('available_balance', 0)
          .order('expiry_date', ascending: true);

      return asList(response)
          .map((json) => RewardBalance.fromJson(json))
          .toList();
    } catch (error) {
      throw Exception('Failed to fetch expiring rewards: $error');
    }
  }

  @override
  Future<double> getTotalRewardValue(
    String userId, {
    String? rewardType,
  }) async {
    try {
      var query = _supabase
          .from('reward_balances')
          .select('available_balance')
          .eq('user_id', userId);

      if (rewardType != null) {
        query = query.eq('reward_type', rewardType);
      }

      final response = await query;

      double total = 0.0;
      for (final item in asList(response)) {
        total += (item['available_balance'] as num).toDouble();
      }

      return total;
    } catch (error) {
      throw Exception('Failed to calculate total reward value: $error');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getRewardEarningTrends(
    String userId, {
    int months = 12,
  }) async {
    try {
      // Get reward earning trends from transactions
      final startDate = DateTime.now().subtract(Duration(days: months * 30));

      final response = await _supabase
          .from('transactions')
          .select('reward_earned, reward_type, transaction_date')
          .eq('user_id', userId)
          .not('reward_earned', 'is', null)
          .gte('transaction_date', startDate.toIso8601String())
          .order('transaction_date', ascending: true);

      // Group by month and reward type
      final Map<String, Map<String, double>> monthlyTrends = {};

      for (final transaction in asList(response)) {
        final transactionDate = DateTime.parse(transaction['transaction_date']);
        final monthKey = '${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}';
        final rewardType = transaction['reward_type'] ?? 'points';
        final rewardEarned = (transaction['reward_earned'] as num).toDouble();

        monthlyTrends[monthKey] ??= {};
        monthlyTrends[monthKey]![rewardType] = 
            (monthlyTrends[monthKey]![rewardType] ?? 0.0) + rewardEarned;
      }

      // Convert to list format
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
