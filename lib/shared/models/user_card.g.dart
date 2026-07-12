// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserCard _$UserCardFromJson(Map<String, dynamic> json) => UserCard(
      id: json['id'] as String,
      userId: json['userId'] as String,
      catalogCardId: json['catalogCardId'] as String,
      lastFourDigits: json['lastFourDigits'] as String?,
      cardNumber: json['cardNumber'] as String?,
      expiryDate: json['expiryDate'] as String?,
      cardHolderName: json['cardHolderName'] as String?,
      creditLimit: (json['creditLimit'] as num?)?.toDouble(),
      statementDate: (json['statementDate'] as num?)?.toInt(),
      dueDate: (json['dueDate'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      cardCatalog: json['cardCatalog'] == null
          ? null
          : CardCatalog.fromJson(json['cardCatalog'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$UserCardToJson(UserCard instance) => <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'catalogCardId': instance.catalogCardId,
      'lastFourDigits': instance.lastFourDigits,
      'cardNumber': instance.cardNumber,
      'expiryDate': instance.expiryDate,
      'cardHolderName': instance.cardHolderName,
      'creditLimit': instance.creditLimit,
      'statementDate': instance.statementDate,
      'dueDate': instance.dueDate,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'cardCatalog': instance.cardCatalog,
    };
