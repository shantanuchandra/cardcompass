import 'package:cardcompass/shared/models/credit_card.dart';

/// Repository interface for credit card operations
abstract class CardRepository {
  /// Get all available credit cards
  Future<List<CreditCard>> getAllCards();

  /// Get user's credit cards
  Future<List<CreditCard>> getUserCards(String userId);

  /// Add a credit card to user's portfolio
  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  });

  /// Remove a credit card from user's portfolio
  Future<void> removeUserCard({
    required String userId,
    required String cardId,
  });

  /// Update user card details
  Future<void> updateUserCard({
    required String userId,
    required String cardId,
    String? lastFourDigits,
    double? creditLimit,
  });

  /// Get card details by ID
  Future<CreditCard?> getCardById(String cardId);

  /// Search cards by filters
  Future<List<CreditCard>> searchCards({
    String? bankName,
    String? cardType,
    String? network,
    double? maxAnnualFee,
    double? minIncome,
  });

  /// Get available banks
  Future<List<String>> getAvailableBanks();

  /// Get available networks
  Future<List<String>> getAvailableNetworks();

  /// Calculate reward for a transaction
  Future<double> calculateReward({
    required String cardId,
    required String category,
    required double amount,
  });

  /// Get best card recommendation for a transaction
  Future<CreditCard?> getBestCardForTransaction({
    required String userId,
    required String category,
    required double amount,
    String? merchantName,
  });
}
