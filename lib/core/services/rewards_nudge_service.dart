import 'package:cardcompass/core/repositories/reward_balance_repository.dart';
import 'package:cardcompass/core/repositories/supabase_notification_repository.dart';
import 'package:cardcompass/core/services/reward_intelligence_service.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/notification.dart';
import 'package:cardcompass/shared/models/reward_balance.dart';

/// Summary returned after a nudge generation run.
class NudgeSummary {
  final int insightsGenerated;
  final int notificationsCreated;
  final int notificationsSkipped; // already exists with same key
  final List<String> errors;

  const NudgeSummary({
    required this.insightsGenerated,
    required this.notificationsCreated,
    required this.notificationsSkipped,
    required this.errors,
  });

  @override
  String toString() =>
      '🔔 Nudge Summary: insights=$insightsGenerated '
      'created=$notificationsCreated skipped=$notificationsSkipped '
      'errors=${errors.length}';
}

/// Converts [RewardInsight]s produced by [RewardIntelligenceService] into
/// [AppNotification] objects persisted via [SupabaseNotificationRepository].
///
/// Deduplication: we embed a stable `insight_key` in the notification's
/// `data` map and check existing notifications before inserting — so users
/// don't get the same expiry nudge every time the app opens.
class RewardsNudgeService {
  final RewardIntelligenceService _intelligence;
  final RewardBalanceRepository _rewardRepo;
  final SupabaseNotificationRepository _notificationRepo;

  RewardsNudgeService({
    required RewardIntelligenceService intelligence,
    required RewardBalanceRepository rewardRepo,
    required SupabaseNotificationRepository notificationRepo,
  })  : _intelligence = intelligence,
        _rewardRepo = rewardRepo,
        _notificationRepo = notificationRepo;

  /// Run the full nudge pipeline for [userId].
  ///
  /// [cards] — the user's credit cards (from [CardRepository.getUserCards]).
  Future<NudgeSummary> run({
    required String userId,
    required List<CreditCard> cards,
  }) async {
    final errors = <String>[];
    int created = 0;
    int skipped = 0;

    // 1. Load reward balances
    List<RewardBalance> balances;
    try {
      balances = await _rewardRepo.getUserRewardBalances(userId);
    } catch (e) {
      return NudgeSummary(
        insightsGenerated: 0,
        notificationsCreated: 0,
        notificationsSkipped: 0,
        errors: ['Failed to load reward balances: $e'],
      );
    }

    if (balances.isEmpty) {
      return const NudgeSummary(
        insightsGenerated: 0,
        notificationsCreated: 0,
        notificationsSkipped: 0,
        errors: [],
      );
    }

    // 2. Build card name lookup
    final cardNames = {
      for (final c in cards)
        c.id: '${c.bankName} ${c.cardName}'.trim(),
    };

    // 3. Generate insights
    final insights = _intelligence.analyse(
      balances: balances,
      cardNames: cardNames,
    );

    // 4. Load existing reward-nudge notifications to deduplicate
    List<AppNotification> existing;
    try {
      existing = await _notificationRepo.getUserNotifications(
        userId,
        type: 'reward_nudge',
        limit: 50,
      );
    } catch (_) {
      existing = [];
    }

    final existingKeys = {
      for (final n in existing)
        if (n.data?['insight_key'] != null) n.data!['insight_key'] as String,
    };

    // 5. Create notifications for new insights
    for (final insight in insights) {
      try {
        final key = _insightKey(insight);
        if (existingKeys.contains(key)) {
          skipped++;
          continue;
        }

        final notification = AppNotification(
          id: 'nudge_${DateTime.now().millisecondsSinceEpoch}_${insight.userCardId}',
          userId: userId,
          type: 'reward_nudge',
          title: insight.title,
          message: insight.body,
          priority: insight.priority,
          isActionable: true,
          actionType: 'view_rewards',
          actionData: insight.userCardId,
          isRead: false,
          createdAt: DateTime.now(),
          data: {
            'insight_key': key,
            'insight_type': insight.type.name,
            'user_card_id': insight.userCardId,
            ...insight.metadata,
          },
        );

        await _notificationRepo.createNotification(notification);
        existingKeys.add(key); // prevent self-dupe within this batch
        created++;

        print('🔔 Created nudge: ${insight.title}');
      } catch (e) {
        final msg = 'Failed to create nudge for ${insight.userCardId}: $e';
        print('❌ $msg');
        errors.add(msg);
      }
    }

    final summary = NudgeSummary(
      insightsGenerated: insights.length,
      notificationsCreated: created,
      notificationsSkipped: skipped,
      errors: errors,
    );
    print(summary);
    return summary;
  }

  /// Stable deduplication key — same insight doesn't fire twice in the same
  /// 24-hour window.
  String _insightKey(RewardInsight insight) {
    final dateStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
    return '${insight.type.name}_${insight.userCardId}_$dateStr';
  }
}
