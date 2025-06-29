/// Model for tracking benefit usage
class BenefitUsageRecord {
  final String id;
  final String userId;
  final String userCardId;
  final String benefitId;
  final String transactionId;
  final double transactionAmount;
  final double benefitValue;
  final String benefitType; // 'cashback', 'points', 'miles', etc.
  final DateTime usageDate;
  final String category;
  final String merchantName;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const BenefitUsageRecord({
    required this.id,
    required this.userId,
    required this.userCardId,
    required this.benefitId,
    required this.transactionId,
    required this.transactionAmount,
    required this.benefitValue,
    required this.benefitType,
    required this.usageDate,
    required this.category,
    required this.merchantName,
    this.metadata,
    required this.createdAt,
  });

  factory BenefitUsageRecord.fromJson(Map<String, dynamic> json) {
    return BenefitUsageRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userCardId: json['user_card_id'] as String,
      benefitId: json['benefit_id'] as String,
      transactionId: json['transaction_id'] as String,
      transactionAmount: (json['transaction_amount'] as num).toDouble(),
      benefitValue: (json['benefit_value'] as num).toDouble(),
      benefitType: json['benefit_type'] as String,
      usageDate: DateTime.parse(json['usage_date'] as String),
      category: json['category'] as String,
      merchantName: json['merchant_name'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_card_id': userCardId,
      'benefit_id': benefitId,
      'transaction_id': transactionId,
      'transaction_amount': transactionAmount,
      'benefit_value': benefitValue,
      'benefit_type': benefitType,
      'usage_date': usageDate.toIso8601String(),
      'category': category,
      'merchant_name': merchantName,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Model for benefit analytics
class BenefitAnalytics {
  final String period; // 'monthly', 'quarterly', 'yearly'
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, double> categoryWiseSavings;
  final Map<String, double> cardWiseSavings;
  final double totalSavings;
  final int totalBenefitsUsed;
  final List<BenefitTrend> trends;
  final List<BenefitRecommendation> recommendations;

  const BenefitAnalytics({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.categoryWiseSavings,
    required this.cardWiseSavings,
    required this.totalSavings,
    required this.totalBenefitsUsed,
    required this.trends,
    required this.recommendations,
  });

  factory BenefitAnalytics.fromJson(Map<String, dynamic> json) {
    return BenefitAnalytics(
      period: json['period'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      categoryWiseSavings: Map<String, double>.from(json['category_wise_savings']),
      cardWiseSavings: Map<String, double>.from(json['card_wise_savings']),
      totalSavings: (json['total_savings'] as num).toDouble(),
      totalBenefitsUsed: json['total_benefits_used'] as int,
      trends: (json['trends'] as List)
          .map((e) => BenefitTrend.fromJson(e))
          .toList(),
      recommendations: (json['recommendations'] as List)
          .map((e) => BenefitRecommendation.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'period': period,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'category_wise_savings': categoryWiseSavings,
      'card_wise_savings': cardWiseSavings,
      'total_savings': totalSavings,
      'total_benefits_used': totalBenefitsUsed,
      'trends': trends.map((e) => e.toJson()).toList(),
      'recommendations': recommendations.map((e) => e.toJson()).toList(),
    };
  }
}

/// Model for benefit usage trends
class BenefitTrend {
  final String category;
  final List<TrendDataPoint> dataPoints;
  final double growthRate; // Percentage growth
  final String trendDirection; // 'up', 'down', 'stable'

  const BenefitTrend({
    required this.category,
    required this.dataPoints,
    required this.growthRate,
    required this.trendDirection,
  });

  factory BenefitTrend.fromJson(Map<String, dynamic> json) {
    return BenefitTrend(
      category: json['category'] as String,
      dataPoints: (json['data_points'] as List)
          .map((e) => TrendDataPoint.fromJson(e))
          .toList(),
      growthRate: (json['growth_rate'] as num).toDouble(),
      trendDirection: json['trend_direction'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'data_points': dataPoints.map((e) => e.toJson()).toList(),
      'growth_rate': growthRate,
      'trend_direction': trendDirection,
    };
  }
}

/// Data point for trend analysis
class TrendDataPoint {
  final DateTime date;
  final double value;
  final String label;

  const TrendDataPoint({
    required this.date,
    required this.value,
    required this.label,
  });

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
    return TrendDataPoint(
      date: DateTime.parse(json['date'] as String),
      value: (json['value'] as num).toDouble(),
      label: json['label'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'value': value,
      'label': label,
    };
  }
}

/// Model for benefit recommendations
class BenefitRecommendation {
  final String id;
  final String type; // 'card_switch', 'category_optimization', 'new_benefit'
  final String title;
  final String description;
  final double potentialSavings;
  final String priority; // 'high', 'medium', 'low'
  final List<String> actionItems;
  final String? relatedCardId;
  final String? relatedBenefitId;
  final DateTime createdAt;

  const BenefitRecommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.potentialSavings,
    required this.priority,
    required this.actionItems,
    this.relatedCardId,
    this.relatedBenefitId,
    required this.createdAt,
  });

  factory BenefitRecommendation.fromJson(Map<String, dynamic> json) {
    return BenefitRecommendation(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      potentialSavings: (json['potential_savings'] as num).toDouble(),
      priority: json['priority'] as String,
      actionItems: List<String>.from(json['action_items']),
      relatedCardId: json['related_card_id'] as String?,
      relatedBenefitId: json['related_benefit_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'potential_savings': potentialSavings,
      'priority': priority,
      'action_items': actionItems,
      'related_card_id': relatedCardId,
      'related_benefit_id': relatedBenefitId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
