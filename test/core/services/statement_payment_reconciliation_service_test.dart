import 'dart:io';

import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/core/services/statement_payment_reconciliation_service.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStatementRepository implements StatementRepository {
  _FakeStatementRepository(this.openStatements);

  final List<Statement> openStatements;
  final List<PaymentUpdate> updates = [];
  final List<double> unmatchedCredits = [];
  final Set<String> reconciledSources = <String>{};

  @override
  Future<PaymentReconciliationResult> reconcileImportedPayment({
    required String sourceStatementId,
    required String userId,
    required String userCardId,
    required double paymentCredit,
    required List<PaymentUpdate> updates,
    required double unmatchedPaymentCredit,
  }) async {
    if (!reconciledSources.add(sourceStatementId)) {
      return const PaymentReconciliationResult(alreadyApplied: true);
    }
    this.updates.addAll(updates);
    unmatchedCredits.add(unmatchedPaymentCredit);
    return PaymentReconciliationResult(
      appliedUpdates: updates,
      unmatchedPaymentCredit: unmatchedPaymentCredit,
    );
  }

  @override
  Future<List<Statement>> getOpenStatementsForCard({
    required String userId,
    required String userCardId,
  }) async =>
      openStatements
          .where((statement) =>
              statement.userId == userId && statement.userCardId == userCardId)
          .toList();

  @override
  Future<void> applyPaymentToStatement({
    required String statementId,
    required String userId,
    required String userCardId,
    required double paymentAmount,
    required PaymentStatus paymentStatus,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> markStatementPaid({
    required String statementId,
    required String userId,
    required String userCardId,
  }) =>
      throw UnimplementedError();

  @override
  Future<Statement> createStatement(
          {required String userId,
          required String userCardId,
          required Map<String, dynamic> statementData,
          String? filePath,
          String? emailId}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteStatement(String statementId) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>?> getStatementById(String statementId) =>
      throw UnimplementedError();
  @override
  Future<List<Statement>> getStatements(String userId) =>
      throw UnimplementedError();
  @override
  Future<List<Map<String, dynamic>>> getStatementsForCard(
          {required String userId, required String cardId}) =>
      throw UnimplementedError();
  @override
  List<String> getSupportedFormats() => throw UnimplementedError();
  @override
  Future<List<Map<String, dynamic>>> getUserStatements(String userId) =>
      throw UnimplementedError();
  @override
  Future<List<Map<String, dynamic>>> importFromGmail(String userId) =>
      throw UnimplementedError();
  @override
  Future<List<Map<String, dynamic>>> parseStatement(
          {required String userId,
          required String cardId,
          required String filePath}) =>
      throw UnimplementedError();
  @override
  Future<void> updateStatementStatus(
          {required String statementId, required bool processed}) =>
      throw UnimplementedError();
  @override
  Future<String> uploadStatement(
          {required String userId,
          required String cardId,
          required File file}) =>
      throw UnimplementedError();
  @override
  Future<bool> validateStatementFile(File file) => throw UnimplementedError();
}

Statement _statement({
  required String id,
  required String userCardId,
  required DateTime dueDate,
  double totalAmount = 1000,
  double paidAmount = 0,
  PaymentStatus status = PaymentStatus.pending,
}) =>
    Statement(
      id: id,
      userId: 'user',
      userCardId: userCardId,
      statementDate: dueDate.subtract(const Duration(days: 30)),
      dueDate: dueDate,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      minimumPayment: 100,
      closingBalance: totalAmount,
      availableCredit: 0,
      rewardsEarned: 0,
      interestCharged: 0,
      feesCharged: 0,
      paymentStatus: status,
      filePath: '',
      fileName: 'statement.pdf',
      createdAt: dueDate,
    );

void main() {
  group('StatementPaymentReconciliationService', () {
    test(
        'applies imported credit to the oldest open statement for the same card',
        () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'june', userCardId: 'card-a', dueDate: DateTime(2026, 6, 1)),
        _statement(
            id: 'may', userCardId: 'card-a', dueDate: DateTime(2026, 5, 1)),
      ]);
      final service = StatementPaymentReconciliationService(repo);

      await service.reconcileImportedPayment(
        sourceStatementId: 'july',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 750,
      );

      expect(repo.updates,
          [const PaymentUpdate('may', 750, PaymentStatus.partial)]);
    });

    test('does not apply the same source statement twice', () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'may', userCardId: 'card-a', dueDate: DateTime(2026, 5, 1)),
      ]);
      final service = StatementPaymentReconciliationService(repo);
      const request = ReconciliationRequest(
        sourceStatementId: 'july',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 750,
      );

      await service.reconcileImportedPayment(request: request);
      await service.reconcileImportedPayment(request: request);

      expect(repo.updates, hasLength(1));
    });

    test('clears multiple oldest statements before partially paying the next',
        () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'may',
            userCardId: 'card-a',
            dueDate: DateTime(2026, 5, 1),
            totalAmount: 300),
        _statement(
            id: 'june',
            userCardId: 'card-a',
            dueDate: DateTime(2026, 6, 1),
            totalAmount: 500),
        _statement(
            id: 'july',
            userCardId: 'card-a',
            dueDate: DateTime(2026, 7, 1),
            totalAmount: 600),
      ]);
      final service = StatementPaymentReconciliationService(repo);

      await service.reconcileImportedPayment(
        sourceStatementId: 'august',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 1000,
      );

      expect(repo.updates, const [
        PaymentUpdate('may', 300, PaymentStatus.paid),
        PaymentUpdate('june', 500, PaymentStatus.paid),
        PaymentUpdate('july', 200, PaymentStatus.partial),
      ]);
    });

    test('does not allocate a credit across card boundaries', () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'other-card',
            userCardId: 'card-b',
            dueDate: DateTime(2026, 4, 1)),
        _statement(
            id: 'same-card',
            userCardId: 'card-a',
            dueDate: DateTime(2026, 5, 1)),
      ]);
      final service = StatementPaymentReconciliationService(repo);

      await service.reconcileImportedPayment(
        sourceStatementId: 'july',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 750,
      );

      expect(repo.updates,
          [const PaymentUpdate('same-card', 750, PaymentStatus.partial)]);
    });

    test('records unmatched remainder after all open statements are paid',
        () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'may',
            userCardId: 'card-a',
            dueDate: DateTime(2026, 5, 1),
            totalAmount: 250),
      ]);
      final service = StatementPaymentReconciliationService(repo);

      await service.reconcileImportedPayment(
        sourceStatementId: 'july',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 750,
      );

      expect(
          repo.updates, [const PaymentUpdate('may', 250, PaymentStatus.paid)]);
      expect(repo.unmatchedCredits, [500]);
    });

    test('does not allocate an imported credit back to its source statement',
        () async {
      final repo = _FakeStatementRepository([
        _statement(
            id: 'july', userCardId: 'card-a', dueDate: DateTime(2026, 7, 1)),
      ]);
      final service = StatementPaymentReconciliationService(repo);

      await service.reconcileImportedPayment(
        sourceStatementId: 'july',
        userId: 'user',
        userCardId: 'card-a',
        paymentCredit: 750,
      );

      expect(repo.updates, isEmpty);
      expect(repo.unmatchedCredits, [750]);
    });
  });
}
