import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/credit_card.dart';
import '../../auth/providers/auth_provider.dart';

// Real data provider that uses the repository
final cardsProvider = StateNotifierProvider<CardsNotifier, List<CreditCard>>((ref) {
  final cardRepository = ref.watch(cardRepositoryProvider);
  return CardsNotifier(cardRepository);
});

class CardsNotifier extends StateNotifier<List<CreditCard>> {
  final CardRepository _cardRepository;
  String? _currentUserId;

  CardsNotifier(this._cardRepository) : super([]);

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

// Provider for selected card
final selectedCardProvider = StateProvider<CreditCard?>((ref) => null);

// Provider for active cards only
final activeCardsProvider = Provider<List<CreditCard>>((ref) {
  final cards = ref.watch(cardsProvider);
  return cards.where((card) => card.isActive).toList();
});

// Provider for total credit limit
final totalCreditLimitProvider = Provider<double>((ref) {
  final cards = ref.watch(activeCardsProvider);
  return cards.fold(0.0, (sum, card) => sum + (card.creditLimit ?? 0.0));
});

// Provider for cards count
final cardsCountProvider = Provider<int>((ref) {
  final cards = ref.watch(activeCardsProvider);
  return cards.length;
});

// Provider that loads user cards when explicitly requested
// DO NOT USE for auto-loading as it can cause infinite loops
final userCardsForAnalyticsProvider = Provider.family<List<CreditCard>, String?>((ref, userId) {
  if (userId == null) return [];
  
  // Only fetch once per userId
  return ref.watch(cardsProvider);
});

/// Async provider that fetches the sum of available_credit from the most recent
/// statement per user card. Falls back to 0 if no statements are found.
final availableCreditProvider = FutureProvider<double>((ref) async {
  final authState = ref.watch(authStateProvider);
  final userId = authState.user?.id;
  if (userId == null || userId == 'guest') return 0.0;

  try {
    // Get all user cards to build a list of user_card_ids
    final supabase = Supabase.instance.client;

    // Query: for each user_card, get the most recent statement's available_credit
    // Using a GROUP BY approach: select max(statement_date), available_credit for each card
    final response = await supabase
        .from('statements')
        .select('card_id, available_credit, statement_date')
        .eq('user_id', userId)
        .order('statement_date', ascending: false);

    if (response == null || (response as List).isEmpty) return 0.0;

    // Keep only the most recent statement per card_id
    final Map<String, double> latestAvailablePerCard = {};
    for (final row in response) {
      final cardId = row['card_id'] as String?;
      final available = (row['available_credit'] as num?)?.toDouble() ?? 0.0;
      if (cardId != null && !latestAvailablePerCard.containsKey(cardId)) {
        latestAvailablePerCard[cardId] = available;
      }
    }

    final total = latestAvailablePerCard.values.fold(0.0, (sum, v) => sum + v);
    return total;
  } catch (e) {
    print('availableCreditProvider error: $e');
    return 0.0;
  }
});

/// Async provider that fetches total rewards_earned from the most recent
/// statement per user card (statement-level rewards, as opposed to per-tx rewards).
final statementRewardsTotalProvider = FutureProvider<double>((ref) async {
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

    if (response == null || (response as List).isEmpty) return 0.0;

    return response.fold<double>(
      0.0,
      (sum, row) => sum + ((row['rewards_earned'] as num?)?.toDouble() ?? 0.0),
    );
  } catch (e) {
    print('statementRewardsTotalProvider error: $e');
    return 0.0;
  }
});
