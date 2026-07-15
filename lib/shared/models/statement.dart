import 'dart:math' as math;

/// Payment status enum for statements
enum PaymentStatus {
  pending,
  paid,
  overdue,
  partial,
}

/// Statement model representing a credit card statement
class Statement {
  final String id;
  final String userId;
  final String userCardId;
  final DateTime statementDate;
  final DateTime dueDate;
  final double totalAmount;
  final double paidAmount;
  final DateTime? paidAt;
  final double minimumPayment;
  final double closingBalance;
  final double availableCredit;
  final double rewardsEarned;
  final double interestCharged;
  final double feesCharged;
  final PaymentStatus paymentStatus;
  final String filePath;
  final String fileName;
  final DateTime? parsedAt;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final bool processed;
  final int? transactionCount;
  Statement({
    required this.id,
    required this.userId,
    required this.userCardId,
    required this.statementDate,
    required this.dueDate,
    required double totalAmount,
    double paidAmount = 0,
    this.paidAt,
    required this.minimumPayment,
    required this.closingBalance,
    required this.availableCredit,
    required this.rewardsEarned,
    required this.interestCharged,
    required this.feesCharged,
    required this.paymentStatus,
    required this.filePath,
    required this.fileName,
    this.parsedAt,
    this.metadata = const {},
    required this.createdAt,
    this.processed = false,
    this.transactionCount,
  })  : totalAmount = totalAmount,
        paidAmount = _validatedPaidAmount(totalAmount, paidAmount);

  static double _validatedPaidAmount(double totalAmount, double paidAmount) {
    if (!totalAmount.isFinite || totalAmount < 0) {
      throw ArgumentError.value(
        totalAmount,
        'totalAmount',
        'must be finite and non-negative',
      );
    }
    if (!paidAmount.isFinite || paidAmount < 0 || paidAmount > totalAmount) {
      throw ArgumentError.value(
        paidAmount,
        'paidAmount',
        'must be finite, non-negative, and no greater than totalAmount',
      );
    }
    return paidAmount;
  }

  factory Statement.fromJson(Map<String, dynamic> json) {
    return Statement(
      id: json['id'],
      userId: json['user_id'],
      userCardId: json['user_card_id'],
      statementDate: DateTime.parse(json['statement_date']),
      dueDate: DateTime.parse(json['due_date']),
      totalAmount: (json['total_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at']) : null,
      minimumPayment: (json['minimum_payment'] as num).toDouble(),
      closingBalance: (json['closing_balance'] as num).toDouble(),
      availableCredit: (json['available_credit'] as num).toDouble(),
      rewardsEarned: (json['rewards_earned'] as num).toDouble(),
      interestCharged: (json['interest_charged'] as num).toDouble(),
      feesCharged: (json['fees_charged'] as num).toDouble(),
      paymentStatus: PaymentStatus.values.firstWhere(
        (e) => e.name == json['payment_status'],
        orElse: () => PaymentStatus.pending,
      ),
      filePath: json['file_path'],
      fileName: json['file_name'],
      parsedAt:
          json['parsed_at'] != null ? DateTime.parse(json['parsed_at']) : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_card_id': userCardId,
      'statement_date': statementDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'paid_at': paidAt?.toIso8601String(),
      'minimum_payment': minimumPayment,
      'closing_balance': closingBalance,
      'available_credit': availableCredit,
      'rewards_earned': rewardsEarned,
      'interest_charged': interestCharged,
      'fees_charged': feesCharged,
      'payment_status': paymentStatus.name,
      'file_path': filePath,
      'file_name': fileName,
      'parsed_at': parsedAt?.toIso8601String(),
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Check if statement is overdue
  bool get isOverdue =>
      paymentStatus != PaymentStatus.paid && dueDate.isBefore(DateTime.now());

  /// Get days until due date
  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;

  /// Check if statement is paid
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// Amount remaining to be paid, never below zero.
  double get remainingAmount =>
      math.max(0, totalAmount - paidAmount).toDouble();

  /// Get formatted statement period
  String get statementPeriod {
    final year = statementDate.year;
    final month = statementDate.month;
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${monthNames[month - 1]} $year';
  }

  /// Copy with updated payment status
  Statement copyWith({
    String? id,
    String? userId,
    String? userCardId,
    DateTime? statementDate,
    DateTime? dueDate,
    double? totalAmount,
    double? paidAmount,
    DateTime? paidAt,
    double? minimumPayment,
    double? closingBalance,
    double? availableCredit,
    double? rewardsEarned,
    double? interestCharged,
    double? feesCharged,
    PaymentStatus? paymentStatus,
    String? filePath,
    String? fileName,
    DateTime? parsedAt,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return Statement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userCardId: userCardId ?? this.userCardId,
      statementDate: statementDate ?? this.statementDate,
      dueDate: dueDate ?? this.dueDate,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      paidAt: paidAt ?? this.paidAt,
      minimumPayment: minimumPayment ?? this.minimumPayment,
      closingBalance: closingBalance ?? this.closingBalance,
      availableCredit: availableCredit ?? this.availableCredit,
      rewardsEarned: rewardsEarned ?? this.rewardsEarned,
      interestCharged: interestCharged ?? this.interestCharged,
      feesCharged: feesCharged ?? this.feesCharged,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      parsedAt: parsedAt ?? this.parsedAt,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
