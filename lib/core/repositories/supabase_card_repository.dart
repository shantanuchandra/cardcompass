import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/config/constants.dart';
import 'package:cardcompass/core/repositories/supabase_helpers.dart';
import 'package:cardcompass/core/repositories/supabase_benefits_repository.dart';

/// Supabase implementation of CardRepository
class SupabaseCardRepository implements CardRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // In-memory caching fields
  static List<CreditCard>? _cardCatalogCache;
  static final Map<String, List<CreditCard>> _userCardsCache = {};

  static void clearUserCache(String userId) {
    _userCardsCache.remove(userId);
    SupabaseBenefitsRepository.clearUserCache(userId);
  }
  @override
  Future<List<CreditCard>> getAllCards() async {
    if (_cardCatalogCache != null) {
      print('💾 SupabaseCardRepository: Returning cached card catalog (${_cardCatalogCache!.length} cards)');
      return _cardCatalogCache!;
    }

    try {
      // Use RPC function to get card catalog
      final response = await _supabase.rpc('get_card_catalog');

      final cards = asList(response)
          .map((json) => _mapCatalogToCreditCard(json))
          .toList();
      
      _cardCatalogCache = cards;
      print('💾 SupabaseCardRepository: Cached card catalog (${cards.length} cards)');
      return cards;
    } catch (e) {
      throw Exception('Failed to fetch all cards: $e');
    }
  }

  @override
  Future<List<CreditCard>> getUserCards(String userId) async {
    if (_userCardsCache.containsKey(userId)) {
      print('💾 SupabaseCardRepository: Returning cached user cards for user: $userId (${_userCardsCache[userId]!.length} cards)');
      return _userCardsCache[userId]!;
    }

    try {
      // Use RPC function to get user cards with catalog information
      final response = await _supabase.rpc('get_user_cards', params: {
        '_user_id': userId,
      });

      final cards = asList(response)
          .map((json) => _mapUserCardRpcToCreditCard(json))
          .toList();
      
      _userCardsCache[userId] = cards;
      print('💾 SupabaseCardRepository: Cached user cards for user: $userId (${cards.length} cards)');
      return cards;
    } catch (e) {
      throw Exception('Failed to fetch user cards: $e');
    }
  }

  @override
  Future<void> addUserCard({
    required String userId,
    required String cardId,
    required String lastFourDigits,
  }) async {
    try {
      // Use the RPC function for associating a card with a user
      await _supabase.rpc('associate_user_with_card', params: {
        '_user_id': userId,
        '_catalog_card_id': cardId,
        '_last_four_digits': lastFourDigits,
      });
      
      // Invalidate cache on change
      clearUserCache(userId);
      print('💾 SupabaseCardRepository: Invalidated user card cache for user: $userId due to addUserCard');
    } catch (e) {
      throw Exception('Failed to add user card: $e');
    }
  }
  @override
  Future<void> removeUserCard({
    required String userId,
    required String cardId,
  }) async {
    try {
      // Use RPC function to remove user card
      final result = await _supabase.rpc('remove_user_card', params: {
        '_user_id': userId,
        '_catalog_card_id': cardId,
      });
      
      if (result != true) {
        throw Exception('User card not found or could not be removed');
      }
      
      // Invalidate cache on change
      clearUserCache(userId);
      print('💾 SupabaseCardRepository: Invalidated user card cache for user: $userId due to removeUserCard');
    } catch (e) {
      throw Exception('Failed to remove user card: $e');
    }
  }

  @override
  Future<void> updateUserCard({
    required String userId,
    required String cardId,
    String? lastFourDigits,
    double? creditLimit,
  }) async {
    try {
      // Use RPC function to update user card
      final result = await _supabase.rpc('update_user_card', params: {
        '_user_id': userId,
        '_catalog_card_id': cardId,
        '_last_four_digits': lastFourDigits,
        '_credit_limit': creditLimit,
      });
      
      if (result != true) {
        throw Exception('User card not found or could not be updated');
      }
      
      // Invalidate cache on change
      clearUserCache(userId);
      print('💾 SupabaseCardRepository: Invalidated user card cache for user: $userId due to updateUserCard');
    } catch (e) {
      throw Exception('Failed to update user card: $e');
    }
  }

  @override
  Future<CreditCard?> getCardById(String cardId) async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('*')
          .eq('id', cardId)
          .single();

      return _mapCatalogToCreditCard(response);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<CreditCard>> searchCards({
    String? bankName,
    String? cardType,
    String? network,
    double? maxAnnualFee,
    double? minIncome,
  }) async {
    try {
      var query = _supabase
          .from('card_catalog')
          .select('*')
          .eq('is_discontinued', false);

      if (bankName != null) {
        query = query.eq('bank', bankName);
      }
      if (cardType != null) {
        query = query.eq('card_type', cardType);
      }
      if (network != null) {
        query = query.eq('network', network);
      }
      if (maxAnnualFee != null) {
        query = query.lte('annual_fee', maxAnnualFee);
      }

      final response = await query;

      return asList(response)
          .map((json) => _mapCatalogToCreditCard(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to search cards: $e');
    }
  }

  @override
  Future<List<String>> getAvailableBanks() async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('bank')
          .eq('is_discontinued', false);

      final banks = asList(response)
          .map((item) => item['bank'] as String)
          .toSet()
          .toList();

      banks.sort();
      return banks;
    } catch (e) {
      // Fallback to constants if database fails
      return AppConstants.indianBanks;
    }
  }

  @override
  Future<List<String>> getAvailableNetworks() async {
    try {
      final response = await _supabase
          .from('card_catalog')
          .select('network')
          .eq('is_discontinued', false);

      final networks = asList(response)
          .map((item) => item['network'] as String)
          .toSet()
          .toList();

      networks.sort();
      return networks;
    } catch (e) {
      // Fallback to constants if database fails
      return AppConstants.cardNetworks;
    }
  }

  @override
  Future<double> calculateReward({
    required String cardId,
    required String category,
    required double amount,
  }) async {
    try {
      // Get card benefits for the specific card and category
      final response = await _supabase
          .from('card_benefits')
          .select('''
            value,
            spending_categories,
            monthly_cap,
            annual_cap
          ''')
          .eq('catalog_card_id', cardId)  // Updated to use catalog_card_id
          .eq('is_active', true);

      if (response.isEmpty) {
        return amount * (AppConstants.defaultRewardRate / 100);
      }

      double bestReward = 0.0;
      
      for (final benefit in response) {
        final categories = List<String>.from(benefit['spending_categories'] ?? []);
        
        // Check if category matches or if it's a general benefit
        if (categories.contains('all') || categories.contains(category.toLowerCase())) {
          final rewardRate = (benefit['value'] as num).toDouble();
          final reward = amount * (rewardRate / 100);
          
          // Apply caps if they exist
          double finalReward = reward;
          if (benefit['monthly_cap'] != null) {
            finalReward = finalReward.clamp(0, (benefit['monthly_cap'] as num).toDouble());
          }
          
          bestReward = finalReward > bestReward ? finalReward : bestReward;
        }
      }

      return bestReward > 0 ? bestReward : amount * (AppConstants.defaultRewardRate / 100);
    } catch (e) {
      // Fallback to default rate if calculation fails
      return amount * (AppConstants.defaultRewardRate / 100);
    }
  }

  @override
  Future<CreditCard?> getBestCardForTransaction({
    required String userId,
    required String category,
    required double amount,
    String? merchantName,
  }) async {
    try {
      // Get user's cards
      final userCards = await getUserCards(userId);
      
      if (userCards.isEmpty) return null;

      CreditCard? bestCard;
      double bestReward = 0.0;

      for (final card in userCards) {
        final reward = await calculateReward(
          cardId: card.id,
          category: category,
          amount: amount,
        );

        if (reward > bestReward) {
          bestReward = reward;
          bestCard = card;
        }
      }

      return bestCard;
    } catch (e) {
      return null;
    }
  }  /// Map card_catalog JSON to CreditCard model
  CreditCard _mapCatalogToCreditCard(Map<String, dynamic> json) {
    // Use direct JSON mapping instead of CardCatalog to handle column name differences
    return CreditCard(
      id: json['id'],
      catalogCardId: json['id'], // catalogCardId is the same as id for catalog entries
      userId: '',  // Card catalog entries don't have a user ID
      cardName: _normalizeCardName(json['card_name'] ?? 'Unknown Card'),
      bankName: json['bank'] ?? 'Unknown Bank',
      cardNumber: null,
      network: _parseCardNetwork(json['network']),
      type: _parseCardType(json['card_type']),
      cardImage: null,
      issuedDate: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      expiryDate: null,
      annualFee: json['annual_fee']?.toDouble(),
      creditLimit: null,
      benefits: [],
      rewardRates: {},
      isActive: !(json['is_discontinued'] ?? false),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }/// Map user_card RPC response with card_catalog to CreditCard model
  CreditCard _mapUserCardRpcToCreditCard(Map<String, dynamic> json) {
    // The RPC response includes flattened card catalog fields
    return CreditCard(
      id: json['id'],  // This is the user_card_id
      catalogCardId: json['catalog_card_id'], // This is the catalog_card_id
      userId: json['user_id'],
      cardName: _normalizeCardName(json['card_name'] ?? 'Unknown Card'),
      bankName: json['bank'] ?? 'Unknown Bank',
      cardNumber: json['last_four_digits'],
      network: _parseCardNetwork(json['network']),
      type: _parseCardType(json['card_type']),
      cardImage: null,
      issuedDate: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      expiryDate: json['expiry_date'] != null 
          ? _parseExpiryDate(json['expiry_date']) 
          : null,
      annualFee: json['annual_fee']?.toDouble(),
      creditLimit: json['credit_limit']?.toDouble(),
      benefits: [],
      rewardRates: {},
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }
  // Helper function to parse MM/YY format to DateTime
  DateTime _parseExpiryDate(String expiry) {
    try {
      final parts = expiry.split('/');
      if (parts.length != 2) return DateTime.now().add(Duration(days: 365));
      
      final month = int.tryParse(parts[0]) ?? 1;
      int year = int.tryParse(parts[1]) ?? 25;
      
      // Adjust year if it's a 2-digit representation
      if (year < 100) {
        year += 2000;
      }
      
      return DateTime(year, month, 1);
    } catch (e) {
      return DateTime.now().add(Duration(days: 365));
    }
  }

  // Helper function to parse CardNetwork from string
  CardNetwork _parseCardNetwork(String? network) {
    if (network == null) return CardNetwork.visa;
    
    switch (network.toLowerCase()) {
      case 'visa': return CardNetwork.visa;
      case 'mastercard': return CardNetwork.mastercard;
      case 'rupay': return CardNetwork.rupay;
      case 'amex': return CardNetwork.amex;
      case 'discover': return CardNetwork.discover;
      case 'diners': return CardNetwork.diners;
      default: return CardNetwork.visa;
    }
  }

  // Helper function to parse CardType from string
  CardType _parseCardType(String? type) {
    if (type == null) return CardType.credit;
    
    switch (type.toLowerCase()) {
      case 'credit': return CardType.credit;
      case 'debit': return CardType.debit;
      case 'prepaid': return CardType.prepaid;
      default: return CardType.credit;
    }
  }

  // Helper functions for working with the new schema
  
  /// Create a new card in the catalog or get existing one
  Future<String> createOrGetCardCatalog({
    required String bank,
    required String cardName,
    required String network,
    required String cardType,
    double? joiningFee,
    double? annualFee,
    double? apr,
  }) async {
    try {
      final result = await _supabase.rpc('create_or_get_card_catalog', params: {
        '_bank': bank,
        '_card_name': cardName,
        '_network': network,
        '_card_type': cardType,
        '_joining_fee': joiningFee,
        '_annual_fee': annualFee,
        '_apr': apr,
      });
      
      return result as String;
    } catch (e) {
      throw Exception('Failed to create card catalog entry: $e');
    }
  }
  
  /// Associate a user with a card
  Future<String> associateUserWithCard({
    required String userId,
    required String catalogCardId,
    String? lastFourDigits,
    String? cardNumber,
    String? expiryDate,
    String? cardHolderName,
    double? creditLimit,
    int? statementDate,
    int? dueDate,
  }) async {
    try {
      final result = await _supabase.rpc('associate_user_with_card', params: {
        '_user_id': userId,
        '_catalog_card_id': catalogCardId,
        '_last_four_digits': lastFourDigits,
        '_card_number': cardNumber,
        '_expiry_date': expiryDate,
        '_card_holder_name': cardHolderName,
        '_credit_limit': creditLimit,
        '_statement_date': statementDate,
        '_due_date': dueDate,
      });
      
      return result as String;
    } catch (e) {
      throw Exception('Failed to associate user with card: $e');
    }
  }
  
  /// Ensure a card exists in the catalog and associate it with the user
  Future<String> ensureCreditCardExists({
    required String userId,
    required String bankName,
    required String cardName,
    String network = 'visa',
    String cardType = 'credit',
    String? lastFourDigits,
  }) async {
    // Step 1: Create or get the card catalog entry
    final catalogCardId = await createOrGetCardCatalog(
      bank: bankName,
      cardName: cardName,
      network: network, 
      cardType: cardType,
    );
    
    // Step 2: Associate the card with the user
    final userCardId = await associateUserWithCard(
      userId: userId,
      catalogCardId: catalogCardId,
      lastFourDigits: lastFourDigits ?? '0000',
    );
    
    return userCardId;
  }

  /// Normalize card name by removing redundant terms
  String _normalizeCardName(String cardName) {
    String normalized = cardName.trim();
    
    // Remove redundant "Credit Card" suffix if it already contains the bank name
    if (normalized.toLowerCase().endsWith('credit card')) {
      final withoutSuffix = normalized.substring(0, normalized.length - 11).trim();
      
      // Check if it's just "Bank Name Credit Card" pattern
      if (withoutSuffix.split(' ').length <= 2) {
        // Keep it as is for simple patterns like "Zenith Credit Card"
        return normalized;
      } else {
        // Remove the suffix for complex names like "IDFC Power Plus Credit Card"
        normalized = withoutSuffix;
      }
    }
    
    return normalized;
  }
}
