enum PaymentStatus { pending, partial, paid, overdue }

class Statement {
  final String id;
  final String userId;
  final String cardId;
  final String userCardId;
  final DateTime statementDate;
  final DateTime dueDate;
  final double totalAmount;
  final double minimumPayment;
  final double closingBalance;
  final double availableCredit;
  final double rewardsEarned;
  final PaymentStatus paymentStatus;
  final double paidAmount;
  final DateTime? paidAt;
  final bool processed;
  final int? transactionCount;
  final DateTime createdAt;

  const Statement({
    required this.id,
    required this.userId,
    required this.cardId,
    required this.userCardId,
    required this.statementDate,
    required this.dueDate,
    required this.totalAmount,
    this.minimumPayment = 0,
    this.closingBalance = 0,
    this.availableCredit = 0,
    this.rewardsEarned = 0,
    required this.paymentStatus,
    this.paidAmount = 0,
    this.paidAt,
    this.processed = false,
    this.transactionCount,
    required this.createdAt,
  });

  double get outstanding =>
      (totalAmount - paidAmount).clamp(0, double.infinity);
  bool get isPaid => paymentStatus == PaymentStatus.paid;
  bool get isOverdue => paymentStatus == PaymentStatus.overdue;

  factory Statement.fromJson(Map<String, dynamic> json) {
    return Statement(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      cardId: json['card_id'] as String,
      userCardId: json['user_card_id'] as String,
      statementDate: DateTime.parse(json['statement_date'] as String),
      dueDate: DateTime.parse(json['due_date'] as String),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      minimumPayment: (json['minimum_payment'] as num?)?.toDouble() ?? 0,
      closingBalance: (json['closing_balance'] as num?)?.toDouble() ?? 0,
      availableCredit: (json['available_credit'] as num?)?.toDouble() ?? 0,
      rewardsEarned: (json['rewards_earned'] as num?)?.toDouble() ?? 0,
      paymentStatus: _parseStatus(json['payment_status'] as String?),
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      processed: json['processed'] as bool? ?? false,
      transactionCount: json['transaction_count'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static PaymentStatus _parseStatus(String? s) {
    switch (s) {
      case 'partial':
        return PaymentStatus.partial;
      case 'paid':
        return PaymentStatus.paid;
      case 'overdue':
        return PaymentStatus.overdue;
      default:
        return PaymentStatus.pending;
    }
  }
}
