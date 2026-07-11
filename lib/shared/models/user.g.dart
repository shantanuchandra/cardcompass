// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      profileImage: json['profileImage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLoginAt: json['lastLoginAt'] == null
          ? null
          : DateTime.parse(json['lastLoginAt'] as String),
      cardIds: (json['cardIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      preferences: json['preferences'] as Map<String, dynamic>? ?? const {},
      isPremium: json['isPremium'] as bool? ?? false,
      fullName: json['fullName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      dateOfBirth: json['dateOfBirth'] == null
          ? null
          : DateTime.parse(json['dateOfBirth'] as String),
      annualIncome: (json['annualIncome'] as num?)?.toDouble(),
      creditScore: (json['creditScore'] as num?)?.toInt(),
      occupation: json['occupation'] as String?,
      city: json['city'] as String?,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'name': instance.name,
      'profileImage': instance.profileImage,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastLoginAt': instance.lastLoginAt?.toIso8601String(),
      'cardIds': instance.cardIds,
      'preferences': instance.preferences,
      'isPremium': instance.isPremium,
      'fullName': instance.fullName,
      'phoneNumber': instance.phoneNumber,
      'dateOfBirth': instance.dateOfBirth?.toIso8601String(),
      'annualIncome': instance.annualIncome,
      'creditScore': instance.creditScore,
      'occupation': instance.occupation,
      'city': instance.city,
    };
