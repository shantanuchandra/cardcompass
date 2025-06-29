import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'transaction.g.dart';

/// Transaction category enumeration
enum TransactionCategory {
  food,
  fuel,
  grocery,
  entertainment,
  travel,
  shopping,
  utilities,
  insurance,
  medical,
  education,
  investment,
  transport,
  rental,
  subscription,
  gift,
  other
}

/// Transaction type enumeration
enum TransactionType {
  debit,
  credit,
  refund,
  fee,
  interest,
  reward
}

/// Transaction model class
@HiveType(typeId: 4)
@JsonSerializable()
class Transaction extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String userId;
  
  @HiveField(17)
  final String? userCardId;  // References user_cards table
  
  @HiveField(3)
  final double amount;

  @HiveField(4)
  final String currency;

  @HiveField(5)
  final String description;

  @HiveField(6)
  final String? merchantName;

  @HiveField(7)
  final TransactionCategory category;

  @HiveField(8)
  final TransactionType type;

  @HiveField(9)
  final DateTime transactionDate;

  @HiveField(10)
  final String? location;

  @HiveField(11)
  final double? rewardEarned;

  @HiveField(12)
  final String? rewardType;

  @HiveField(13)
  final Map<String, dynamic> metadata;

  @HiveField(14)
  final String? statementId;

  @HiveField(15)
  final bool isRecurring;

  @HiveField(16)
  final DateTime createdAt;  Transaction({
    required this.id,
    required this.userId,
    this.userCardId,  // References user_cards table
    required this.amount,
    this.currency = 'INR',
    required this.description,
    this.merchantName,
    this.category = TransactionCategory.other,
    this.type = TransactionType.debit,
    required this.transactionDate,
    this.location,
    this.rewardEarned,
    this.rewardType,
    this.metadata = const {},
    this.statementId,
    this.isRecurring = false,
    required this.createdAt,
  });

  /// Get category as display string
  String get categoryString => category.toString().split('.').last;
  
  /// Get transaction type as display string  
  String get typeString => type.toString().split('.').last;
  /// Create a copy of this transaction with updated fields
  Transaction copyWith({
    String? id,
    String? userId,
    String? userCardId,
    double? amount,
    String? currency,
    String? description,
    String? merchantName,
    TransactionCategory? category,
    TransactionType? type,
    DateTime? transactionDate,
    String? location,
    double? rewardEarned,
    String? rewardType,
    Map<String, dynamic>? metadata,
    String? statementId,
    bool? isRecurring,
    DateTime? createdAt,
  }) {    return Transaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userCardId: userCardId ?? this.userCardId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      description: description ?? this.description,
      merchantName: merchantName ?? this.merchantName,
      category: category ?? this.category,
      type: type ?? this.type,
      transactionDate: transactionDate ?? this.transactionDate,
      location: location ?? this.location,
      rewardEarned: rewardEarned ?? this.rewardEarned,
      rewardType: rewardType ?? this.rewardType,
      metadata: metadata ?? this.metadata,
      statementId: statementId ?? this.statementId,
      isRecurring: isRecurring ?? this.isRecurring,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final json = _$TransactionToJson(this);    // Handle Supabase column naming - ensure proper mapping between camelCase and snake_case
    // This addresses the schema cache issue by explicitly setting snake_case column names
    final adaptedJson = <String, dynamic>{
      'id': json['id'],
      'user_id': json['userId'],
      'user_card_id': json['userCardId'],  // Reference to user_cards table
      'amount': json['amount'],
      'currency': json['currency'] ?? 'INR',
      'description': json['description'],
      'merchant_name': json['merchantName'],
      'category': json['category']?.toString().split('.').last,
      'transaction_type': json['type']?.toString().split('.').last,
      'transaction_date': json['transactionDate'],
      'location': json['location'],
      'reward_earned': json['rewardEarned'],
      'reward_type': json['rewardType'],
      'statement_id': json['statementId'],
      'metadata': json['metadata'] ?? {},
      'created_at': json['createdAt'] ?? DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    // Remove null values to prevent issues with NOT NULL constraints
    adaptedJson.removeWhere((key, value) => value == null);
    
    return adaptedJson;
  }
  /// Create from JSON
  factory Transaction.fromJson(Map<String, dynamic> json) {
    // Handle conversion from snake_case to camelCase and different field names
    final transactionType = json['transaction_type'] ?? json['type'] ?? 'debit';
    final category = json['category'] ?? 'other';
    
    TransactionType type;
    try {
      type = TransactionType.values.firstWhere(
        (e) => e.toString().split('.').last == transactionType,
        orElse: () => TransactionType.debit,
      );
    } catch (_) {
      type = TransactionType.debit;
    }
    
    TransactionCategory transactionCategory;
    try {
      transactionCategory = TransactionCategory.values.firstWhere(
        (e) => e.toString().split('.').last == category,
        orElse: () => TransactionCategory.other,
      );
    } catch (_) {
      transactionCategory = TransactionCategory.other;
    }
      return Transaction(
      id: json['id'],
      userId: json['user_id'],
      userCardId: json['user_card_id'],
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      currency: json['currency'] ?? 'INR',
      description: json['description'] ?? '',
      merchantName: json['merchant_name'],
      category: transactionCategory,
      type: type,
      transactionDate: json['transaction_date'] != null
          ? DateTime.parse(json['transaction_date'])
          : DateTime.now(),
      location: json['location'],
      rewardEarned: json['reward_earned']?.toDouble(),
      rewardType: json['reward_type'],
      metadata: json['metadata'] ?? {},
      statementId: json['statement_id'],
      isRecurring: json['is_recurring'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, amount: $amount, description: $description, date: $transactionDate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Transaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
