import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import '../../../shared/models/credit_card.dart';

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
