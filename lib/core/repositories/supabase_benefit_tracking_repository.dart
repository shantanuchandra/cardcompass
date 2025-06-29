import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/shared/models/benefit_tracking.dart';

/// Repository for managing benefit tracking in Supabase
class SupabaseBenefitTrackingRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Record a new benefit usage
  Future<BenefitUsageRecord> recordBenefitUsage(BenefitUsageRecord record) async {
    try {
      final response = await _supabase
          .from('benefit_usage_records')
          .insert(record.toJson())
          .select()
          .single();

      return BenefitUsageRecord.fromJson(response);
    } catch (e) {
      throw Exception('Failed to record benefit usage: $e');
    }
  }  /// Get benefit usage records for a user
  Future<List<BenefitUsageRecord>> getUserBenefitUsage(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    String? category,
  }) async {
    try {
      var queryBuilder = _supabase
          .from('benefit_usage_records')
          .select()
          .eq('user_id', userId);

      if (startDate != null) {
        queryBuilder = queryBuilder.gte('usage_date', startDate.toIso8601String());
      }

      if (endDate != null) {
        queryBuilder = queryBuilder.lte('usage_date', endDate.toIso8601String());
      }

      if (category != null) {
        queryBuilder = queryBuilder.eq('category', category);
      }

      var transformBuilder = queryBuilder.order('usage_date', ascending: false);

      if (limit != null) {
        transformBuilder = transformBuilder.limit(limit);
      }

      final response = await transformBuilder;

      return (response as List)
          .map((json) => BenefitUsageRecord.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch benefit usage: $e');
    }
  }

  /// Get benefit usage analytics
  Future<BenefitAnalytics> getBenefitAnalytics(
    String userId, {
    required String period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Use a stored procedure or function for complex analytics
      final response = await _supabase.rpc('get_benefit_analytics', params: {
        'user_id_param': userId,
        'period_param': period,
        'start_date_param': startDate?.toIso8601String(),
        'end_date_param': endDate?.toIso8601String(),
      });

      return BenefitAnalytics.fromJson(response);
    } catch (e) {
      // Fallback to calculating analytics in the app
      return _calculateAnalyticsLocally(userId, period, startDate, endDate);
    }
  }

  /// Calculate analytics locally if database function is not available
  Future<BenefitAnalytics> _calculateAnalyticsLocally(
    String userId,
    String period,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final records = await getUserBenefitUsage(
        userId,
        startDate: startDate,
        endDate: endDate,
      );

      // Calculate category-wise savings
      final categoryWiseSavings = <String, double>{};
      final cardWiseSavings = <String, double>{};
      double totalSavings = 0;

      for (final record in records) {
        categoryWiseSavings[record.category] = 
            (categoryWiseSavings[record.category] ?? 0) + record.benefitValue;
        
        cardWiseSavings[record.userCardId] = 
            (cardWiseSavings[record.userCardId] ?? 0) + record.benefitValue;
        
        totalSavings += record.benefitValue;
      }

      // Generate trends (simplified)
      final trends = _generateTrends(records);

      // Generate recommendations (simplified)
      final recommendations = await _generateRecommendations(userId, records);

      return BenefitAnalytics(
        period: period,
        startDate: startDate ?? DateTime.now().subtract(const Duration(days: 30)),
        endDate: endDate ?? DateTime.now(),
        categoryWiseSavings: categoryWiseSavings,
        cardWiseSavings: cardWiseSavings,
        totalSavings: totalSavings,
        totalBenefitsUsed: records.length,
        trends: trends,
        recommendations: recommendations,
      );
    } catch (e) {
      throw Exception('Failed to calculate benefit analytics: $e');
    }
  }

  /// Generate benefit usage trends
  List<BenefitTrend> _generateTrends(List<BenefitUsageRecord> records) {
    final categoryData = <String, List<BenefitUsageRecord>>{};
    
    // Group records by category
    for (final record in records) {
      categoryData.putIfAbsent(record.category, () => []).add(record);
    }

    final trends = <BenefitTrend>[];
    
    for (final entry in categoryData.entries) {
      final category = entry.key;
      final categoryRecords = entry.value;
      
      // Sort by date
      categoryRecords.sort((a, b) => a.usageDate.compareTo(b.usageDate));
      
      // Create data points
      final dataPoints = categoryRecords.map((record) => 
        TrendDataPoint(
          date: record.usageDate,
          value: record.benefitValue,
          label: '₹${record.benefitValue.toStringAsFixed(0)}',
        )
      ).toList();

      // Calculate growth rate (simplified)
      double growthRate = 0;
      String trendDirection = 'stable';
      
      if (dataPoints.length >= 2) {
        final firstHalf = dataPoints.take(dataPoints.length ~/ 2)
            .fold<double>(0, (sum, point) => sum + point.value);
        final secondHalf = dataPoints.skip(dataPoints.length ~/ 2)
            .fold<double>(0, (sum, point) => sum + point.value);
        
        if (firstHalf > 0) {
          growthRate = ((secondHalf - firstHalf) / firstHalf) * 100;
          trendDirection = growthRate > 5 ? 'up' : 
                          growthRate < -5 ? 'down' : 'stable';
        }
      }

      trends.add(BenefitTrend(
        category: category,
        dataPoints: dataPoints,
        growthRate: growthRate,
        trendDirection: trendDirection,
      ));
    }

    return trends;
  }

  /// Generate benefit recommendations
  Future<List<BenefitRecommendation>> _generateRecommendations(
    String userId,
    List<BenefitUsageRecord> records,
  ) async {
    final recommendations = <BenefitRecommendation>[];
    
    // Analyze spending patterns and generate recommendations
    final categorySpending = <String, double>{};
    for (final record in records) {
      categorySpending[record.category] = 
          (categorySpending[record.category] ?? 0) + record.transactionAmount;
    }

    // Find top spending category
    if (categorySpending.isNotEmpty) {
      final topCategory = categorySpending.entries
          .reduce((a, b) => a.value > b.value ? a : b);
      
      recommendations.add(BenefitRecommendation(
        id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
        type: 'category_optimization',
        title: 'Optimize ${topCategory.key} Spending',
        description: 'You spent ₹${topCategory.value.toStringAsFixed(0)} on ${topCategory.key}. Consider using a card with better ${topCategory.key} benefits.',
        potentialSavings: topCategory.value * 0.02, // Assume 2% additional savings
        priority: 'high',
        actionItems: [
          'Review cards with better ${topCategory.key} rewards',
          'Check for promotional offers in ${topCategory.key} category',
        ],
        createdAt: DateTime.now(),
      ));
    }

    return recommendations;
  }

  /// Get benefit usage summary for a specific period
  Future<Map<String, dynamic>> getBenefitUsageSummary(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final records = await getUserBenefitUsage(
        userId,
        startDate: startDate,
        endDate: endDate,
      );

      final summary = {
        'total_benefits_used': records.length,
        'total_savings': records.fold<double>(0, (sum, record) => sum + record.benefitValue),
        'average_benefit_value': records.isNotEmpty 
            ? records.fold<double>(0, (sum, record) => sum + record.benefitValue) / records.length
            : 0,
        'most_used_category': _getMostUsedCategory(records),
        'highest_saving_transaction': _getHighestSavingTransaction(records),
        'benefits_by_type': _groupBenefitsByType(records),
      };

      return summary;
    } catch (e) {
      throw Exception('Failed to get benefit usage summary: $e');
    }
  }

  String _getMostUsedCategory(List<BenefitUsageRecord> records) {
    if (records.isEmpty) return 'None';
    
    final categoryCount = <String, int>{};
    for (final record in records) {
      categoryCount[record.category] = (categoryCount[record.category] ?? 0) + 1;
    }
    
    return categoryCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  BenefitUsageRecord? _getHighestSavingTransaction(List<BenefitUsageRecord> records) {
    if (records.isEmpty) return null;
    
    return records.reduce((a, b) => a.benefitValue > b.benefitValue ? a : b);
  }

  Map<String, double> _groupBenefitsByType(List<BenefitUsageRecord> records) {
    final typeGroups = <String, double>{};
    for (final record in records) {
      typeGroups[record.benefitType] = 
          (typeGroups[record.benefitType] ?? 0) + record.benefitValue;
    }
    return typeGroups;
  }
}
