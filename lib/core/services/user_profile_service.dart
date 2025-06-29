/// Service interface for user profile operations
abstract class UserProfileService {
  /// Get user profile including financial information
  Future<UserProfile> getUserProfile(String userId);
  
  /// Update user profile information
  Future<void> updateUserProfile(String userId, UserProfile profile);
  
  /// Get user's income information
  Future<double?> getUserIncome(String userId);
  
  /// Update user's income information
  Future<void> updateUserIncome(String userId, double income);
  
  /// Get user's credit score
  Future<int?> getUserCreditScore(String userId);
  
  /// Update user's credit score
  Future<void> updateUserCreditScore(String userId, int creditScore);
  
  /// Get user's financial goals
  Future<List<String>> getUserFinancialGoals(String userId);
  
  /// Update user's financial goals
  Future<void> updateUserFinancialGoals(String userId, List<String> goals);
}

/// User profile model for AI analysis
class UserProfile {
  final String userId;
  final String? name;
  final String? email;
  final double? annualIncome;
  final int? creditScore;
  final List<String> financialGoals;
  final String? occupation;
  final String? city;
  final DateTime? dateOfBirth;
  final String? phoneNumber;
  final Map<String, dynamic> preferences;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.userId,
    this.name,
    this.email,
    this.annualIncome,
    this.creditScore,
    this.financialGoals = const [],
    this.occupation,
    this.city,
    this.dateOfBirth,
    this.phoneNumber,
    this.preferences = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  UserProfile copyWith({
    String? userId,
    String? name,
    String? email,
    double? annualIncome,
    int? creditScore,
    List<String>? financialGoals,
    String? occupation,
    String? city,
    DateTime? dateOfBirth,
    String? phoneNumber,
    Map<String, dynamic>? preferences,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      annualIncome: annualIncome ?? this.annualIncome,
      creditScore: creditScore ?? this.creditScore,
      financialGoals: financialGoals ?? this.financialGoals,
      occupation: occupation ?? this.occupation,
      city: city ?? this.city,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      preferences: preferences ?? this.preferences,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'annualIncome': annualIncome,
      'creditScore': creditScore,
      'financialGoals': financialGoals,
      'occupation': occupation,
      'city': city,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'phoneNumber': phoneNumber,
      'preferences': preferences,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      annualIncome: (json['annualIncome'] as num?)?.toDouble(),
      creditScore: json['creditScore'] as int?,
      financialGoals: List<String>.from(json['financialGoals'] ?? []),
      occupation: json['occupation'] as String?,
      city: json['city'] as String?,
      dateOfBirth: json['dateOfBirth'] != null 
          ? DateTime.parse(json['dateOfBirth'] as String)
          : null,
      phoneNumber: json['phoneNumber'] as String?,
      preferences: Map<String, dynamic>.from(json['preferences'] ?? {}),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Get age from date of birth
  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month || 
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }
    return age;
  }

  /// Check if profile is complete for AI analysis
  bool get isCompleteForAI {
    return annualIncome != null && 
           creditScore != null && 
           name != null && 
           age != null;
  }

  /// Get profile completeness percentage
  double get completenessPercentage {
    int completed = 0;
    int total = 10;

    if (name != null && name!.isNotEmpty) completed++;
    if (email != null && email!.isNotEmpty) completed++;
    if (annualIncome != null) completed++;
    if (creditScore != null) completed++;
    if (financialGoals.isNotEmpty) completed++;
    if (occupation != null && occupation!.isNotEmpty) completed++;
    if (city != null && city!.isNotEmpty) completed++;
    if (dateOfBirth != null) completed++;
    if (phoneNumber != null && phoneNumber!.isNotEmpty) completed++;
    if (preferences.isNotEmpty) completed++;

    return completed / total;
  }

  /// Convert to format suitable for AI analysis
  Map<String, dynamic> toAIFormat() {
    return {
      'userId': userId,
      'annualIncome': annualIncome ?? 600000, // Default middle-class income
      'creditScore': creditScore ?? 700, // Default good credit score
      'age': age ?? 30, // Default age
      'city': city ?? 'Mumbai', // Default city
      'occupation': occupation ?? 'Professional', // Default occupation
      'financialGoals': financialGoals.isNotEmpty ? financialGoals : ['savings', 'rewards'],
      'profileCompleteness': completenessPercentage,
      'hasValidIncome': annualIncome != null,
      'hasValidCreditScore': creditScore != null,
    };
  }
}
