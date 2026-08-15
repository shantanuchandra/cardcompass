enum TransactionType { debit, credit, refund, fee, interest, reward }

class Transaction {
  final String id;
  final String userId;
  final String userCardId;
  final double amount;
  final String currency;
  final String description;
  final String? merchantName;
  final String? category;
  final TransactionType transactionType;
  final DateTime transactionDate;
  final String? location;
  final double? rewardEarned;
  final String? rewardType;
  final String? statementId;
  final String? mccCode;
  final String? mccDescription;
  final String? mccSource;
  final double? mccConfidence;
  final DateTime? mccVerifiedAt;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const Transaction({
    required this.id,
    required this.userId,
    required this.userCardId,
    required this.amount,
    this.currency = 'INR',
    required this.description,
    this.merchantName,
    this.category,
    required this.transactionType,
    required this.transactionDate,
    this.location,
    this.rewardEarned,
    this.rewardType,
    this.statementId,
    this.mccCode,
    this.mccDescription,
    this.mccSource,
    this.mccConfidence,
    this.mccVerifiedAt,
    this.metadata = const {},
    required this.createdAt,
  });

  bool get isDebit => transactionType == TransactionType.debit;

  /// Whether this transaction's currency differs from [bankMarketCurrency]
  /// — the currency the issuing bank's statements are normally denominated
  /// in (see `currencyForBank` in bank_market.dart). A foreign-currency
  /// charge (e.g. a USD hotel booking on an otherwise-INR statement) is
  /// international; a same-currency charge isn't. Independent of
  /// `category` — a transaction can be both "food" and international.
  bool isInternational(String bankMarketCurrency) => currency != bankMarketCurrency;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userCardId: json['user_card_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      description: json['description'] as String,
      merchantName: json['merchant_name'] as String?,
      category: json['category'] as String?,
      transactionType: _parseType(json['transaction_type'] as String?),
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      location: json['location'] as String?,
      rewardEarned: (json['reward_earned'] as num?)?.toDouble(),
      rewardType: json['reward_type'] as String?,
      statementId: json['statement_id'] as String?,
      mccCode: json['mcc_code'] as String?,
      mccDescription: json['mcc_description'] as String?,
      mccSource: json['mcc_source'] as String?,
      mccConfidence: (json['mcc_confidence'] as num?)?.toDouble(),
      mccVerifiedAt: json['mcc_verified_at'] != null
          ? DateTime.parse(json['mcc_verified_at'] as String)
          : null,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static TransactionType _parseType(String? type) {
    switch (type) {
      case 'credit':
        return TransactionType.credit;
      case 'refund':
        return TransactionType.refund;
      case 'fee':
        return TransactionType.fee;
      case 'interest':
        return TransactionType.interest;
      case 'reward':
        return TransactionType.reward;
      default:
        return TransactionType.debit;
    }
  }
}
