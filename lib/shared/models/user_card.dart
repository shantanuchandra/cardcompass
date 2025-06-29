import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:cardcompass/shared/models/card_catalog.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

part 'user_card.g.dart';

/// Represents a user's specific credit card
@HiveType(typeId: 6)
@JsonSerializable()
class UserCard {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String userId;
  
  @HiveField(2)
  final String catalogCardId;
  
  @HiveField(3)
  final String? lastFourDigits;
  
  @HiveField(4)
  final String? cardNumber;  // Should be encrypted in production
  
  @HiveField(5)
  final String? expiryDate;  // Format: MM/YY
  
  @HiveField(6)
  final String? cardHolderName;
  
  @HiveField(7)
  final double? creditLimit;
  
  @HiveField(8)
  final int? statementDate;  // Day of month when statement is generated
  
  @HiveField(9)
  final int? dueDate;  // Days after statement date
  
  @HiveField(10)
  final bool isActive;
  
  @HiveField(11)
  final DateTime createdAt;
  
  @HiveField(12)
  final DateTime updatedAt;
  
  @HiveField(13)
  final CardCatalog? cardCatalog;  // Associated card catalog entry

  const UserCard({
    required this.id,
    required this.userId,
    required this.catalogCardId,
    this.lastFourDigits,
    this.cardNumber,
    this.expiryDate,
    this.cardHolderName,
    this.creditLimit,
    this.statementDate,
    this.dueDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.cardCatalog,
  });

  factory UserCard.fromJson(Map<String, dynamic> json) {
    return UserCard(
      id: json['id'],
      userId: json['user_id'],
      catalogCardId: json['catalog_card_id'],
      lastFourDigits: json['last_four_digits'],
      cardNumber: json['card_number'],
      expiryDate: json['expiry_date'],
      cardHolderName: json['card_holder_name'],
      creditLimit: json['credit_limit']?.toDouble(),
      statementDate: json['statement_date'],
      dueDate: json['due_date'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
      cardCatalog: json['card_catalog'] != null 
          ? CardCatalog.fromJson(json['card_catalog']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = {
      'id': id,
      'user_id': userId,
      'catalog_card_id': catalogCardId,
      'last_four_digits': lastFourDigits,
      'card_number': cardNumber,
      'expiry_date': expiryDate,
      'card_holder_name': cardHolderName,
      'credit_limit': creditLimit,
      'statement_date': statementDate,
      'due_date': dueDate,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    
    // Don't include card_catalog in JSON for database operations
    return map;
  }
  
  String get maskedCardNumber {
    if (lastFourDigits == null || lastFourDigits!.isEmpty) return '****';
    return '**** **** **** ${lastFourDigits}';
  }
  
  // Convenience getters to access catalog properties directly
  String get bankName => cardCatalog?.bank ?? 'Unknown Bank';
  String get cardName => cardCatalog?.cardName ?? 'Unknown Card';
  CardType get cardType => cardCatalog?.typeEnum ?? CardType.credit;
  CardNetwork get network => cardCatalog?.networkEnum ?? CardNetwork.visa;
  double? get annualFee => cardCatalog?.annualFee;
  Color get networkColor => cardCatalog?.networkColor ?? Colors.blueGrey;
}
