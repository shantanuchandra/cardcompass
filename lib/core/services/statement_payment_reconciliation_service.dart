import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/shared/models/statement.dart';

class ReconciliationRequest {
  const ReconciliationRequest({
    required this.sourceStatementId,
    required this.userId,
    required this.userCardId,
    required this.paymentCredit,
  });

  final String sourceStatementId;
  final String userId;
  final String userCardId;
  final double paymentCredit;
}

/// Allocates a parsed payment credit to the oldest open statements on its
/// source card. The repository persists the allocation atomically.
class StatementPaymentReconciliationService {
  StatementPaymentReconciliationService(this._repository);

  final StatementRepository _repository;

  Future<PaymentReconciliationResult> reconcileImportedPayment({
    ReconciliationRequest? request,
    String? sourceStatementId,
    String? userId,
    String? userCardId,
    double? paymentCredit,
  }) async {
    final resolvedRequest = request ??
        ReconciliationRequest(
          sourceStatementId: _required(sourceStatementId, 'sourceStatementId'),
          userId: _required(userId, 'userId'),
          userCardId: _required(userCardId, 'userCardId'),
          paymentCredit: paymentCredit ?? 0,
        );
    if (resolvedRequest.paymentCredit <= 0 ||
        !resolvedRequest.paymentCredit.isFinite) {
      return const PaymentReconciliationResult();
    }

    final openStatements = await _repository.getOpenStatementsForCard(
      userId: resolvedRequest.userId,
      userCardId: resolvedRequest.userCardId,
    );
    var remainingCredit = resolvedRequest.paymentCredit;
    final updates = <PaymentUpdate>[];
    final eligible = openStatements
        .where((statement) =>
            statement.userId == resolvedRequest.userId &&
            statement.userCardId == resolvedRequest.userCardId &&
            statement.paymentStatus != PaymentStatus.paid &&
            statement.remainingAmount > 0)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    for (final statement in eligible) {
      if (remainingCredit <= 0) break;
      final paymentAmount = remainingCredit < statement.remainingAmount
          ? remainingCredit
          : statement.remainingAmount;
      remainingCredit -= paymentAmount;
      updates.add(PaymentUpdate(
        statement.id,
        paymentAmount,
        paymentAmount == statement.remainingAmount
            ? PaymentStatus.paid
            : PaymentStatus.partial,
      ));
    }

    return _repository.reconcileImportedPayment(
      sourceStatementId: resolvedRequest.sourceStatementId,
      userId: resolvedRequest.userId,
      userCardId: resolvedRequest.userCardId,
      paymentCredit: resolvedRequest.paymentCredit,
      updates: updates,
      unmatchedPaymentCredit: remainingCredit,
    );
  }

  String _required(String? value, String name) {
    if (value == null || value.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return value;
  }
}
