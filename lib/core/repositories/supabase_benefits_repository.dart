import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/benefit.dart';

/// Repository for managing benefits data in Supabase
class SupabaseBenefitsRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get all available benefits
  Future<List<Benefit>> getAllBenefits() async {
    try {
      final response = await _supabase
          .from('benefits')
          .select('*') // Select all columns
          .eq('is_active', true)
          .order('benefit_type');

      return (response as List)
          .map((json) => Benefit.fromJson(json))
          .toList();
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

      return (response as List)
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
          .eq('catalog_card_id', cardId)
          .eq('is_active', true);

      return (response as List)
          .map((json) => CardBenefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch card benefits: $e');
    }
  }

  /// Get user card benefits (for user's specific cards)
  Future<List<CardBenefit>> getUserCardBenefits(String userId) async {
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
      
      for (final userCardJson in response as List) {
        final cardBenefits = userCardJson['card_catalog']['card_benefits'] as List;
        for (final benefitJson in cardBenefits) {
          allBenefits.add(CardBenefit.fromJson(benefitJson));
        }
      }

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

      return (response as List)
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

      return (response as List)
          .map((json) => Benefit.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch benefits for recommendation: $e');
    }
  }
}
