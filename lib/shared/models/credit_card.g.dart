// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditCard _$CreditCardFromJson(Map<String, dynamic> json) => CreditCard(
      id: json['id'] as String,
      userId: json['userId'] as String,
      cardName: json['cardName'] as String,
      bankName: json['bankName'] as String,
      cardNumber: json['cardNumber'] as String?,
      network: $enumDecode(_$CardNetworkEnumMap, json['network']),
      type: $enumDecode(_$CardTypeEnumMap, json['type']),
      cardImage: json['cardImage'] as String?,
      issuedDate: DateTime.parse(json['issuedDate'] as String),
      expiryDate: json['expiryDate'] == null
          ? null
          : DateTime.parse(json['expiryDate'] as String),
      annualFee: (json['annualFee'] as num?)?.toDouble(),
      creditLimit: (json['creditLimit'] as num?)?.toDouble(),
      benefits: (json['benefits'] as List<dynamic>?)
              ?.map((e) => Benefit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rewardRates: (json['rewardRates'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toDouble()),
          ) ??
          const {},
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      catalogCardId: json['catalogCardId'] as String?,
    );

Map<String, dynamic> _$CreditCardToJson(CreditCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'cardName': instance.cardName,
      'bankName': instance.bankName,
      'cardNumber': instance.cardNumber,
      'network': _$CardNetworkEnumMap[instance.network]!,
      'type': _$CardTypeEnumMap[instance.type]!,
      'cardImage': instance.cardImage,
      'issuedDate': instance.issuedDate.toIso8601String(),
      'expiryDate': instance.expiryDate?.toIso8601String(),
      'annualFee': instance.annualFee,
      'creditLimit': instance.creditLimit,
      'benefits': instance.benefits,
      'rewardRates': instance.rewardRates,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'catalogCardId': instance.catalogCardId,
    };

const _$CardNetworkEnumMap = {
  CardNetwork.visa: 'visa',
  CardNetwork.mastercard: 'mastercard',
  CardNetwork.rupay: 'rupay',
  CardNetwork.amex: 'amex',
  CardNetwork.discover: 'discover',
  CardNetwork.diners: 'diners',
};

const _$CardTypeEnumMap = {
  CardType.credit: 'credit',
  CardType.debit: 'debit',
  CardType.prepaid: 'prepaid',
};
