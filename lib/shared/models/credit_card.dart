import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cardcompass/shared/models/benefit.dart';

part 'credit_card.g.dart';

enum CardNetwork { visa, mastercard, rupay, amex, discover, diners }
enum CardType { credit, debit, prepaid }

@HiveType(typeId: 1)
@JsonSerializable()
class CreditCard {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String userId;
  
  @HiveField(2)
  final String cardName;
  
  @HiveField(3)
  final String bankName;
  
  @HiveField(4)
  final String? cardNumber; // Encrypted last 4 digits

  /// Last 4 digits of the card number
  String? get cardNumberLast4 => cardNumber;
  
  @HiveField(5)
  final CardNetwork network;
  
  @HiveField(6)
  final CardType type;
  
  @HiveField(7)
  final String? cardImage;
  
  @HiveField(8)
  final DateTime issuedDate;
  
  @HiveField(9)
  final DateTime? expiryDate;
  
  @HiveField(10)
  final double? annualFee;
  
  @HiveField(11)
  final double? creditLimit;
  
  @HiveField(12)
  final List<Benefit> benefits;
  
  @HiveField(13)
  final Map<String, double> rewardRates;
  
  @HiveField(14)
  final bool isActive;
  
  @HiveField(15)
  final DateTime createdAt;
  
  @HiveField(16)
  final DateTime updatedAt;

  final String? catalogCardId;

  const CreditCard({
    required this.id, // This will now be the user_card_id for user cards
    required this.userId,
    required this.cardName,
    required this.bankName,
    this.cardNumber,
    required this.network,
    required this.type,
    this.cardImage,
    required this.issuedDate,
    this.expiryDate,
    this.annualFee,
    this.creditLimit,
    this.benefits = const [],
    this.rewardRates = const {},
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.catalogCardId,
  });

  factory CreditCard.fromJson(Map<String, dynamic> json) => _$CreditCardFromJson(json);
  Map<String, dynamic> toJson() => _$CreditCardToJson(this);

  String get maskedCardNumber {
    if (cardNumber == null || cardNumber!.length < 4) return '****';
    return '**** **** **** ${cardNumber!.substring(cardNumber!.length - 4)}';
  }

  Color get networkColor {
    switch (network) {
      case CardNetwork.visa:
        return const Color(0xFF1A1F71);
      case CardNetwork.mastercard:
        return const Color(0xFFEB001B);
      case CardNetwork.rupay:
        return const Color(0xFF0066CC);
      case CardNetwork.amex:
        return const Color(0xFF006FCF);
      case CardNetwork.discover:
        return const Color(0xFFFF6000);
      case CardNetwork.diners:
        return const Color(0xFF0077C0);
    }
  }

  CreditCard copyWith({
    String? id,
    String? userId,
    String? cardName,
    String? bankName,
    String? cardNumber,
    CardNetwork? network,
    CardType? type,
    String? cardImage,
    DateTime? issuedDate,
    DateTime? expiryDate,
    double? annualFee,
    double? creditLimit,
    List<Benefit>? benefits,
    Map<String, double>? rewardRates,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? catalogCardId,
  }) {
    return CreditCard(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      cardName: cardName ?? this.cardName,
      bankName: bankName ?? this.bankName,
      cardNumber: cardNumber ?? this.cardNumber,
      network: network ?? this.network,
      type: type ?? this.type,
      cardImage: cardImage ?? this.cardImage,
      issuedDate: issuedDate ?? this.issuedDate,
      expiryDate: expiryDate ?? this.expiryDate,
      annualFee: annualFee ?? this.annualFee,
      creditLimit: creditLimit ?? this.creditLimit,
      benefits: benefits ?? this.benefits,
      rewardRates: rewardRates ?? this.rewardRates,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      catalogCardId: catalogCardId ?? this.catalogCardId,
    );
  }

  @override
  String toString() {
    return 'CreditCard(id: $id, cardName: $cardName, bankName: $bankName, network: $network)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreditCard && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  /// String representation of card type for UI (e.g. 'credit', 'debit')
  String get cardType => type.toString().split('.').last;
}

@HiveType(typeId: 3)
enum BenefitType {
  @HiveField(0)
  cashback,
  @HiveField(1)
  rewardPoints,
  @HiveField(2)
  discount,
  @HiveField(3)
  freeService,
  @HiveField(4)
  insurance,
  @HiveField(5)
  loungeAccess,
  @HiveField(6)
  fuelSurcharge,
  @HiveField(7)
  emi,
  @HiveField(8)
  other,
}
