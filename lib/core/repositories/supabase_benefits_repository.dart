import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/benefit.dart';
import 'package:cardcompass/core/repositories/supabase_helpers.dart';

/// Repository for managing benefits data in Supabase
class SupabaseBenefitsRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // In-memory caching fields
  static List<Benefit>? _allBenefitsCache;
  static final Map<String, List<CardBenefit>> _userCardBenefitsCache = {};

  static void clearUserCache(String userId) {
    _userCardBenefitsCache.remove(userId);
  }

  Future<List<Benefit>> getAllBenefits() async {
    if (_allBenefitsCache != null) {
      print('💾 SupabaseBenefitsRepository: Returning cached benefits (${_allBenefitsCache!.length} benefits)');
      return _allBenefitsCache!;
    }

    try {
      final response = await _supabase
          .from('benefits')
          .select('*') // Select all columns
          .eq('is_active', true)
          .order('benefit_type');

      final benefits = asList(response)
          .map((json) => Benefit.fromJson(json))
          .toList();
      
      _allBenefitsCache = benefits;
      print('💾 SupabaseBenefitsRepository: Cached benefits (${benefits.length} benefits)');
      return benefits;
    } catch (e) {
      throw Exception('Failed to fetch benefits: $e');
    }
  }

  /// Get benefits for specific categories
  Future<List<Benefit>> getBenefitsByCategories(List<String> categories) async {
    try {
      final response = await _supabase
          .from('benefits')
          .select('*') // Select all columns
          .eq('is_active', true)
          .inFilter('applicable_categories', categories)
          .order('benefit_type');

      return asList(response)
          .map((json) => Benefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch benefits by categories: $e');
    }
  }

  /// Get benefits for a specific card
  Future<List<CardBenefit>> getCardBenefits(String cardId) async {
    try {
      final response = await _supabase
          .from('card_benefits')
          .select('''
            *,
            benefits!inner(*)
          ''')
          .eq('card_id', cardId)
          .eq('is_active', true);

      return asList(response)
          .map((json) => CardBenefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch card benefits: $e');
    }
  }

  Future<List<CardBenefit>> getUserCardBenefits(String userId) async {
    if (_userCardBenefitsCache.containsKey(userId)) {
      print('💾 SupabaseBenefitsRepository: Returning cached user card benefits for user: $userId (${_userCardBenefitsCache[userId]!.length} benefits)');
      return _userCardBenefitsCache[userId]!;
    }

    try {
      final response = await _supabase
          .from('user_cards')
          .select('''
            *,
            card_catalog!inner(
              id,
              bank,
              card_name,
              card_benefits!inner(
                *,
                benefits!inner(*)
              )
            )
          ''')
          .eq('user_id', userId)
          .eq('is_active', true);

      final List<CardBenefit> allBenefits = [];
      
      for (final userCardJson in asList(response)) {
        final cardBenefits = asListDynamic(userCardJson['card_catalog']['card_benefits']);
        for (final benefitJson in cardBenefits) {
          allBenefits.add(CardBenefit.fromJson(benefitJson));
        }
      }

      _userCardBenefitsCache[userId] = allBenefits;
      print('💾 SupabaseBenefitsRepository: Cached user card benefits for user: $userId (${allBenefits.length} benefits)');
      return allBenefits;
    } catch (e) {
      throw Exception('Failed to fetch user card benefits: $e');
    }
  }

  /// Create a new benefit
  Future<Benefit> createBenefit(Benefit benefit) async {
    try {
      final response = await _supabase
          .from('benefits')
          .insert(benefit.toJson())
          .select()
          .single();

      return Benefit.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create benefit: $e');
    }
  }

  /// Update an existing benefit
  Future<Benefit> updateBenefit(Benefit benefit) async {
    try {
      final response = await _supabase
          .from('benefits')
          .update(benefit.toJson())
          .eq('id', benefit.id)
          .select()
          .single();

      return Benefit.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update benefit: $e');
    }
  }

  /// Delete a benefit (soft delete by setting is_active to false)
  Future<void> deleteBenefit(String benefitId) async {
    try {
      await _supabase
          .from('benefits')
          .update({'is_active': false})
          .eq('id', benefitId);
    } catch (e) {
      throw Exception('Failed to delete benefit: $e');
    }
  }

  /// Search benefits by name or description
  Future<List<Benefit>> searchBenefits(String query) async {
    try {
      final response = await _supabase
          .from('benefits')
          .select()
          .eq('is_active', true)
          .or('name.ilike.%$query%,description.ilike.%$query%')
          .order('name');

      return asList(response)
          .map((json) => Benefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to search benefits: $e');
    }
  }

  /// Tracks benefit usage
  Future<void> trackBenefitUsage(String benefitId, String userId) async {
    try {
      await _supabase
          .from('benefit_usage')
          .insert({
            'benefit_id': benefitId,
            'user_id': userId,
            'usage_timestamp': DateTime.now().toUtc().toIso8601String(),
          });
    } catch (e) {
      print('Failed to track benefit usage: $e');
      // Consider more specific error handling (e.g., logging, retries)
      rethrow;
    }
  }

  /// Get benefits for AI recommendations based on card_id and other criteria
  Future<List<Benefit>> getBenefitsForRecommendation(
      String cardId, List<String> categories, double? minSpend) async {
    try {
      var query = _supabase
          .from('benefits')
          .select('*')
          .eq('card_id', cardId)
          .eq('is_active', true);

      if (categories.isNotEmpty) {
        query = query.inFilter('applicable_categories', categories);
      }

      if (minSpend != null) {
        query = query.lte('min_spend_requirement', minSpend);
      }

      final response = await query;

      return asList(response)
          .map((json) => Benefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch benefits for recommendation: $e');
    }
  }
}
