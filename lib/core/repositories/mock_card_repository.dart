import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// In-memory CardRepository for guest mode. Mutations affect only the
/// current session; nothing persists across app restarts.
class MockCardRepository implements CardRepository {
  final List<CreditCard> _cards = MockData.creditCards();

  @override
  Future<List<CreditCard>> getAllCards() async => List.unmodifiable(_cards);

  @override
  Future<List<CreditCard>> getUserCards(String userId) async {
    return _cards.where((c) => c.isActive).toList();
  }

  @override
  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  }) async {
    final existing = _cards.indexWhere((c) => c.id == cardId);
    if (existing == -1) return;
    final now = DateTime.now();
    _cards[existing] = _cards[existing].copyWith(cardNumber: lastFourDigits, updatedAt: now);
  }

  @override
  Future<void> removeUserCard({required String userId, required String cardId}) async {
    final index = _cards.indexWhere((c) => c.id == cardId);
    if (index == -1) return;
    _cards[index] = _cards[index].copyWith(isActive: false, updatedAt: DateTime.now());
  }

  @override
  Future<void> updateUserCard({
    required String userId,
    required String cardId,
    String? lastFourDigits,
    double? creditLimit,
  }) async {
    final index = _cards.indexWhere((c) => c.id == cardId);
    if (index == -1) return;
    _cards[index] = _cards[index].copyWith(
      cardNumber: lastFourDigits ?? _cards[index].cardNumber,
      creditLimit: creditLimit ?? _cards[index].creditLimit,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<CreditCard?> getCardById(String cardId) async {
    final matches = _cards.where((c) => c.id == cardId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<CreditCard>> searchCards({
    String? bankName,
    String? cardType,
    String? network,
    double? maxAnnualFee,
    double? minIncome,
  }) async {
    return _cards.where((c) {
      if (bankName != null && c.bankName != bankName) return false;
      if (cardType != null && c.cardType != cardType) return false;
      if (network != null && c.network.name != network) return false;
      if (maxAnnualFee != null && (c.annualFee ?? 0) > maxAnnualFee) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<String>> getAvailableBanks() async {
    return _cards.map((c) => c.bankName).toSet().toList()..sort();
  }

  @override
  Future<List<String>> getAvailableNetworks() async {
    return _cards.map((c) => c.network.name).toSet().toList()..sort();
  }

  @override
  Future<double> calculateReward({
    required String cardId,
    required String category,
    required double amount,
  }) async {
    final card = await getCardById(cardId);
    if (card == null) return 0;
    final rate = card.rewardRates[category.toLowerCase()] ?? card.rewardRates['other'] ?? 1.0;
    return amount * (rate / 100);
  }

  @override
  Future<CreditCard?> getBestCardForTransaction({
    required String userId,
    required String category,
    required double amount,
    String? merchantName,
  }) async {
    CreditCard? best;
    double bestReward = -1;
    for (final card in _cards.where((c) => c.isActive)) {
      final reward = await calculateReward(cardId: card.id, category: category, amount: amount);
      if (reward > bestReward) {
        bestReward = reward;
        best = card;
      }
    }
    return best;
  }
}
