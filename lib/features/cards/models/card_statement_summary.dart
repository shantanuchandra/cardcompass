import 'package:cardcompass/shared/models/statement.dart';

/// The latest persisted statement for one owned credit card.
///
/// This is derived from imported [Statement] records and never represents a
/// synthetic bill for a card with no statements.
class CardStatementSummary {
  const CardStatementSummary({
    required this.statementId,
    required this.userCardId,
    required this.statementDate,
    required this.dueDate,
    required this.totalAmount,
    required this.paidAmount,
    this.paidAt,
    this.paymentStatus = PaymentStatus.pending,
  });

  final String statementId;
  final String userCardId;
  final DateTime statementDate;
  final DateTime dueDate;
  final double totalAmount;
  final double paidAmount;
  final DateTime? paidAt;
  final PaymentStatus paymentStatus;

  double get remainingAmount =>
      (totalAmount - paidAmount).clamp(0, totalAmount).toDouble();
  bool get isPaid =>
      remainingAmount == 0 || paymentStatus == PaymentStatus.paid;

  CardStatementSummary copyWith({
    double? paidAmount,
    DateTime? paidAt,
    PaymentStatus? paymentStatus,
  }) =>
      CardStatementSummary(
        statementId: statementId,
        userCardId: userCardId,
        statementDate: statementDate,
        dueDate: dueDate,
        totalAmount: totalAmount,
        paidAmount: paidAmount ?? this.paidAmount,
        paidAt: paidAt ?? this.paidAt,
        paymentStatus: paymentStatus ?? this.paymentStatus,
      );

  factory CardStatementSummary.fromStatement(Statement statement) =>
      CardStatementSummary(
        statementId: statement.id,
        userCardId: statement.userCardId,
        statementDate: statement.statementDate,
        dueDate: statement.dueDate,
        totalAmount: statement.totalAmount,
        paidAmount: statement.paidAmount,
        paidAt: statement.paidAt,
        paymentStatus: statement.paymentStatus,
      );
}

/// Chooses the maximum statement date for each owned card id.
Map<String, CardStatementSummary> buildCardStatementSummaries(
  Iterable<Statement> statements,
) {
  final latest = <String, Statement>{};
  for (final statement in statements) {
    final current = latest[statement.userCardId];
    if (current == null ||
        statement.statementDate.isAfter(current.statementDate)) {
      latest[statement.userCardId] = statement;
    }
  }
  return {
    for (final entry in latest.entries)
      entry.key: CardStatementSummary.fromStatement(entry.value),
  };
}
