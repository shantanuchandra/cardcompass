// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_catalog.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CardCatalog _$CardCatalogFromJson(Map<String, dynamic> json) => CardCatalog(
      id: json['id'] as String,
      bank: json['bank'] as String,
      cardName: json['cardName'] as String,
      network: json['network'] as String,
      cardType: json['cardType'] as String,
      joiningFee: (json['joiningFee'] as num?)?.toDouble(),
      annualFee: (json['annualFee'] as num?)?.toDouble(),
      apr: (json['apr'] as num?)?.toDouble(),
      isDiscontinued: json['isDiscontinued'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$CardCatalogToJson(CardCatalog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bank': instance.bank,
      'cardName': instance.cardName,
      'network': instance.network,
      'cardType': instance.cardType,
      'joiningFee': instance.joiningFee,
      'annualFee': instance.annualFee,
      'apr': instance.apr,
      'isDiscontinued': instance.isDiscontinued,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
