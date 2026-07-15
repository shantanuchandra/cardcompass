import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show FutureProvider;
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/services/reward_intelligence_service.dart';
import 'package:cardcompass/features/cards/models/card_statement_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/credit_card.dart';
import '../../auth/providers/auth_provider.dart';

part 'cards_provider.g.dart';

/// Latest persisted statement per owned card for the signed-in user.
final cardStatementSummariesProvider =
    FutureProvider<Map<String, CardStatementSummary>>((ref) async {
  final userId = ref.watch(authStateProvider).user?.id;
  if (userId == null || userId == 'guest') return const {};

  final StatementRepository repository = ref.watch(statementRepositoryProvider);
  final statements = await repository.getStatements(userId);
  return buildCardStatementSummaries(statements);
});

@riverpod
class CardsNotifier extends _$CardsNotifier {
  late final CardRepository _cardRepository;
  String? _currentUserId;

  @override
  List<CreditCard> build() {
    _cardRepository = ref.watch(cardRepositoryProvider);
    return [];
  }

  Future<void> loadUserCards(String userId) async {
    try {
      _currentUserId = userId;
      state = await _cardRepository.getUserCards(userId);
    } catch (e) {
      print('Error loading user cards: $e');
      state = [];
    }
  }

  // Automatically refresh cards when user changes
  void setUserId(String? userId) {
    if (userId != null && userId != _currentUserId) {
      loadUserCards(userId);
    } else if (userId == null) {
      // Clear cards when user logs out
      state = [];
      _currentUserId = null;
    }
  }

  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  }) async {
    try {
      await _cardRepository.addUserCard(
        userId: userId,
        cardId: cardId,
        lastFourDigits: lastFourDigits,
      );
      // Reload cards after adding
      await loadUserCards(userId);
    } catch (e) {
      print('Error adding user card: $e');
    }
  }

  Future<void> removeUserCard({
    required String userId,
    required String cardId,
  }) async {
    try {
      await _cardRepository.removeUserCard(
        userId: userId,
        cardId: cardId,
      );
      // Reload cards after removing
      await loadUserCards(userId);
    } catch (e) {
      print('Error removing user card: $e');
    }
  }

  Future<void> updateUserCard({
    required String userId,
    required String cardId,
    String? lastFourDigits,
    double? creditLimit,
  }) async {
    try {
      await _cardRepository.updateUserCard(
        userId: userId,
        cardId: cardId,
        lastFourDigits: lastFourDigits,
        creditLimit: creditLimit,
      );
      // Reload cards after updating
      await loadUserCards(userId);
    } catch (e) {
      print('Error updating user card: $e');
    }
  }
}

// Provider for active cards only
@riverpod
List<CreditCard> activeCards(Ref ref) {
  final cards = ref.watch(cardsProvider);
  return cards.where((card) => card.isActive).toList();
}

// Provider for total credit limit
@riverpod
double totalCreditLimit(Ref ref) {
  final cards = ref.watch(activeCardsProvider);
  return cards.fold(0.0, (sum, card) => sum + (card.creditLimit ?? 0.0));
}

// Provider for cards count
@riverpod
int cardsCount(Ref ref) {
  final cards = ref.watch(activeCardsProvider);
  return cards.length;
}

// Provider that loads user cards when explicitly requested
@riverpod
List<CreditCard> userCardsForAnalytics(Ref ref, String? userId) {
  if (userId == null) return [];
  return ref.watch(cardsProvider);
}

/// Async provider that fetches the sum of available_credit from the most recent
/// statement per user card, restricted to cards that are still active — so a
/// deactivated/removed card's stale statement doesn't keep inflating this total
/// after it stops counting toward [totalCreditLimit]. Falls back to 0 if no
/// statements are found.
@riverpod
Future<double> availableCredit(Ref ref) async {
  final authState = ref.watch(authStateProvider);
  final userId = authState.user?.id;
  if (userId == null || userId == 'guest') return 0.0;

  try {
    final activeCardIds =
        ref.watch(activeCardsProvider).map((card) => card.id).toSet();
    if (activeCardIds.isEmpty) return 0.0;

    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('statements')
        .select('user_card_id, available_credit, statement_date')
        .eq('user_id', userId)
        .order('statement_date', ascending: false);

    final rows = response as List;
    if (rows.isEmpty) return 0.0;

    final Map<String, double> latestAvailablePerCard = {};
    for (final row in rows) {
      final userCardId = row['user_card_id'] as String?;
      final available = (row['available_credit'] as num?)?.toDouble() ?? 0.0;
      if (userCardId != null &&
          activeCardIds.contains(userCardId) &&
          !latestAvailablePerCard.containsKey(userCardId)) {
        latestAvailablePerCard[userCardId] = available;
      }
    }

    final total = latestAvailablePerCard.values.fold(0.0, (sum, v) => sum + v);
    return total;
  } catch (e) {
    print('availableCreditProvider error: $e');
    return 0.0;
  }
}

/// Async provider that fetches total rewards_earned from the most recent
/// statement per user card (statement-level rewards, as opposed to per-tx rewards).
@riverpod
Future<double> statementRewardsTotal(Ref ref) async {
  final authState = ref.watch(authStateProvider);
  final userId = authState.user?.id;
  if (userId == null || userId == 'guest') return 0.0;

  try {
    final supabase = Supabase.instance.client;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    final response = await supabase
        .from('statements')
        .select('rewards_earned')
        .eq('user_id', userId)
        .gte('statement_date', firstDayOfMonth.toIso8601String());

    final rows = response as List;
    if (rows.isEmpty) return 0.0;

    return rows.fold<double>(
      0.0,
      (sum, row) => sum + ((row['rewards_earned'] as num?)?.toDouble() ?? 0.0),
    );
  } catch (e) {
    print('statementRewardsTotalProvider error: $e');
    return 0.0;
  }
}

/// Reward insights for the dashboard nudge banner (Phase 3).
///
/// Loads the user's reward balances and runs [RewardIntelligenceService]
/// to produce ranked [RewardInsight] objects.
@riverpod
Future<List<RewardInsight>> rewardInsights(Ref ref) async {
  final authState = ref.watch(authStateProvider);
  final userId = authState.user?.id;
  if (userId == null || userId == 'guest') return [];

  try {
    final rewardRepo = ref.watch(rewardBalanceRepositoryProvider);
    final intelligence = ref.watch(rewardIntelligenceServiceProvider);
    final cardRepo = ref.watch(cardRepositoryProvider);

    final balances = await rewardRepo.getUserRewardBalances(userId);
    if (balances.isEmpty) return [];

    final cards = await cardRepo.getUserCards(userId);
    final cardNames = {
      for (final c in cards) c.id: '${c.bankName} ${c.cardName}'.trim(),
    };

    return intelligence.analyse(balances: balances, cardNames: cardNames);
  } catch (e) {
    print('rewardInsightsProvider error: $e');
    return [];
  }
}
