class BenefitCategory {
  final String categoryCode;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BenefitCategory({
    required this.categoryCode,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BenefitCategory.fromJson(Map<String, dynamic> json) {
    return BenefitCategory(
      categoryCode: json['category_code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_code': categoryCode,
      'name': name,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BenefitCategory && other.categoryCode == categoryCode;
  }

  @override
  int get hashCode => categoryCode.hashCode;
}

class Benefit {
  final String id;
  final String categoryCode;
  final String name;
  final String? description;
  final String calculationMethod; // 'percentage', 'fixed', 'points', 'boolean'
  final double? defaultValue;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Benefit({
    required this.id,
    required this.categoryCode,
    required this.name,
    this.description,
    required this.calculationMethod,
    this.defaultValue,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Benefit.fromJson(Map<String, dynamic> json) {
    return Benefit(
      id: json['id'] as String,
      categoryCode: json['category_code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      calculationMethod: json['calculation_method'] as String,
      defaultValue: json['default_value'] != null
          ? (json['default_value'] as num).toDouble()
          : null,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_code': categoryCode,
      'name': name,
      'description': description,
      'calculation_method': calculationMethod,
      'default_value': defaultValue,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Benefit && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class CardBenefit {
  final String id;
  final String cardId;
  final String benefitId;
  final double? value;
  final List<String>? spendingCategories;
  final double? monthlyCap;
  final double? annualCap;
  final DateTime? validFrom;
  final DateTime? validTo;
  final Map<String, dynamic>? configuration;
  final bool isActive;

  const CardBenefit({
    required this.id,
    required this.cardId,
    required this.benefitId,
    this.value,
    this.spendingCategories,
    this.monthlyCap,
    this.annualCap,
    this.validFrom,
    this.validTo,
    this.configuration,
    this.isActive = true,
  });

  factory CardBenefit.fromJson(Map<String, dynamic> json) {
    return CardBenefit(
      id: json['id'] as String,
      cardId: json['card_id'] as String,
      benefitId: json['benefit_id'] as String,
      value: json['value'] != null ? (json['value'] as num).toDouble() : null,
      spendingCategories: json['spending_categories'] != null
          ? List<String>.from(json['spending_categories'] as List)
          : null,
      monthlyCap: json['monthly_cap'] != null
          ? (json['monthly_cap'] as num).toDouble()
          : null,
      annualCap: json['annual_cap'] != null
          ? (json['annual_cap'] as num).toDouble()
          : null,
      validFrom: json['valid_from'] != null
          ? DateTime.parse(json['valid_from'] as String)
          : null,
      validTo: json['valid_to'] != null
          ? DateTime.parse(json['valid_to'] as String)
          : null,
      configuration: json['configuration'] as Map<String, dynamic>?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'card_id': cardId,
      'benefit_id': benefitId,
      'value': value,
      'spending_categories': spendingCategories,
      'monthly_cap': monthlyCap,
      'annual_cap': annualCap,
      'valid_from': validFrom?.toIso8601String(),
      'valid_to': validTo?.toIso8601String(),
      'configuration': configuration,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CardBenefit && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class BenefitTier {
  final String id;
  final String cardBenefitId;
  final double tierMinValue;
  final double? tierMaxValue;
  final double tierBenefitValue;
  final String? tierName;
  final bool isActive;

  const BenefitTier({
    required this.id,
    required this.cardBenefitId,
    required this.tierMinValue,
    this.tierMaxValue,
    required this.tierBenefitValue,
    this.tierName,
    this.isActive = true,
  });

  factory BenefitTier.fromJson(Map<String, dynamic> json) {
    return BenefitTier(
      id: json['id'] as String,
      cardBenefitId: json['card_benefit_id'] as String,
      tierMinValue: (json['tier_min_value'] as num).toDouble(),
      tierMaxValue: json['tier_max_value'] != null
          ? (json['tier_max_value'] as num).toDouble()
          : null,
      tierBenefitValue: (json['tier_benefit_value'] as num).toDouble(),
      tierName: json['tier_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'card_benefit_id': cardBenefitId,
      'tier_min_value': tierMinValue,
      'tier_max_value': tierMaxValue,
      'tier_benefit_value': tierBenefitValue,
      'tier_name': tierName,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BenefitTier && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
