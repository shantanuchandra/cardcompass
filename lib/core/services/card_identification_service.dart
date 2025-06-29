import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// Service to handle card identification and suggestions
class CardIdentificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get cards that have been identified from transactions but not yet associated with user
  Future<List<Map<String, dynamic>>> getIdentifiedButUnassociatedCards(String userId) async {
    try {
      final response = await _supabase.rpc('get_identified_unassociated_cards', params: {
        '_user_id': userId,
      });
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // If RPC doesn't exist, return empty list
      return [];
    }
  }

  /// Suggest cards to user based on their transaction history
  Future<List<CreditCard>> getSuggestedCards(String userId) async {
    try {
      // Get cards mentioned in user's transactions that they haven't added yet
      final response = await _supabase.rpc('get_suggested_cards_for_user', params: {
        '_user_id': userId,
      });
      
      return (response as List)
          .map((json) => CreditCard.fromJson(json))
          .toList();
    } catch (e) {
      // If RPC doesn't exist, return empty list
      return [];
    }
  }

  /// Get cards that appear in transaction data but aren't in user's cards
  Future<List<String>> getCardNamesFromTransactions(String userId) async {
    try {
      // Query transactions for card names that aren't in user's associated cards
      final userTransactions = await _supabase
          .from('transactions')
          .select('metadata')
          .eq('user_id', userId);

      final cardNames = <String>{};
      
      for (final transaction in userTransactions) {
        final metadata = transaction['metadata'] as Map<String, dynamic>?;
        if (metadata != null && metadata.containsKey('card_name')) {
          cardNames.add(metadata['card_name'].toString());
        }
      }

      return cardNames.toList();
    } catch (e) {
      return [];
    }
  }

  /// Automatically associate an identified card with the user
  Future<void> autoAssociateCard({
    required String userId,
    required String cardName,
    String lastFourDigits = '****',
  }) async {
    try {
      // Find the card in catalog by name
      final catalogResponse = await _supabase
          .from('card_catalog')
          .select('id, card_name, bank_name')
          .ilike('card_name', '%$cardName%')
          .limit(1);

      if (catalogResponse.isEmpty) {
        throw Exception('Card not found in catalog: $cardName');
      }

      final catalogCard = catalogResponse.first;
      final catalogCardId = catalogCard['id'];

      // Associate with user
      await _supabase.rpc('associate_user_with_card', params: {
        '_user_id': userId,
        '_catalog_card_id': catalogCardId,
        '_last_four_digits': lastFourDigits,
      });
    } catch (e) {
      throw Exception('Failed to auto-associate card: $e');
    }
  }
}
