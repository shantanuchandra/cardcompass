import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
@JsonSerializable()
class User {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String email;
  @HiveField(2)
  final String? name;
  
  @HiveField(3)
  final String? profileImage;
  
  @HiveField(4)
  final DateTime createdAt;
  
  @HiveField(5)
  final DateTime? lastLoginAt;
  
  @HiveField(6)
  final List<String> cardIds;
  
  @HiveField(7)
  final Map<String, dynamic> preferences;
  
  @HiveField(8)
  final bool isPremium;

  // Additional fields for enhanced profile
  @HiveField(9)
  final String? fullName;
  
  @HiveField(10)
  final String? phoneNumber;
  
  @HiveField(11)
  final DateTime? dateOfBirth;
  
  @HiveField(12)
  final double? annualIncome;
  
  @HiveField(13)
  final int? creditScore;
  
  @HiveField(14)
  final String? occupation;
  
  @HiveField(15)
  final String? city;
  const User({
    required this.id,
    required this.email,
    this.name,
    this.profileImage,
    required this.createdAt,
    this.lastLoginAt,
    this.cardIds = const [],
    this.preferences = const {},
    this.isPremium = false,
    this.fullName,
    this.phoneNumber,
    this.dateOfBirth,
    this.annualIncome,
    this.creditScore,
    this.occupation,
    this.city,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
  User copyWith({
    String? id,
    String? email,
    String? name,
    String? profileImage,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    List<String>? cardIds,
    Map<String, dynamic>? preferences,
    bool? isPremium,
    String? fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    double? annualIncome,
    int? creditScore,
    String? occupation,
    String? city,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      profileImage: profileImage ?? this.profileImage,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      cardIds: cardIds ?? this.cardIds,
      preferences: preferences ?? this.preferences,
      isPremium: isPremium ?? this.isPremium,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      annualIncome: annualIncome ?? this.annualIncome,
      creditScore: creditScore ?? this.creditScore,
      occupation: occupation ?? this.occupation,
      city: city ?? this.city,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, email: $email, name: $name, isPremium: $isPremium)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
