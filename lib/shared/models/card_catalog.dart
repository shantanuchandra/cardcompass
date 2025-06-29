import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

part 'card_catalog.g.dart';

/// Represents a credit card in the card catalog
@HiveType(typeId: 5)
@JsonSerializable()
class CardCatalog {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String bank;
  
  @HiveField(2)
  final String cardName;
  
  @HiveField(3)
  final String network;
  
  @HiveField(4)
  final String cardType;
  
  @HiveField(5)
  final double? joiningFee;
  
  @HiveField(6)
  final double? annualFee;
  
  @HiveField(7)
  final double? apr;
  
  @HiveField(8)
  final bool isDiscontinued;
  
  @HiveField(9)
  final DateTime createdAt;
  
  @HiveField(10)
  final DateTime updatedAt;

  const CardCatalog({
    required this.id,
    required this.bank,
    required this.cardName,
    required this.network,
    required this.cardType,
    this.joiningFee,
    this.annualFee,
    this.apr,
    this.isDiscontinued = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CardCatalog.fromJson(Map<String, dynamic> json) {
    return CardCatalog(
      id: json['id'],
      bank: json['bank'],
      cardName: json['card_name'],
      network: json['network'],
      cardType: json['card_type'],
      joiningFee: json['joining_fee']?.toDouble(),
      annualFee: json['annual_fee']?.toDouble(),
      apr: json['apr']?.toDouble(),
      isDiscontinued: json['is_discontinued'] ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bank': bank,
      'card_name': cardName,
      'network': network,
      'card_type': cardType,
      'joining_fee': joiningFee,
      'annual_fee': annualFee,
      'apr': apr,
      'is_discontinued': isDiscontinued,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CardNetwork get networkEnum {
    switch (network.toLowerCase()) {
      case 'visa': return CardNetwork.visa;
      case 'mastercard': return CardNetwork.mastercard;
      case 'rupay': return CardNetwork.rupay;
      case 'amex': return CardNetwork.amex;
      case 'discover': return CardNetwork.discover;
      case 'diners': return CardNetwork.diners;
      default: return CardNetwork.visa;
    }
  }

  CardType get typeEnum {
    switch (cardType.toLowerCase()) {
      case 'credit': return CardType.credit;
      case 'debit': return CardType.debit;
      case 'prepaid': return CardType.prepaid;
      default: return CardType.credit;
    }
  }

  Color get networkColor {
    switch (networkEnum) {
      case CardNetwork.visa: return const Color(0xFF1A1F71);
      case CardNetwork.mastercard: return const Color(0xFFEB001B);
      case CardNetwork.rupay: return const Color(0xFF007B3E);
      case CardNetwork.amex: return const Color(0xFF2671B9);
      case CardNetwork.discover: return const Color(0xFFFF6600);
      case CardNetwork.diners: return const Color(0xFF0079BE);
    }
  }
}
