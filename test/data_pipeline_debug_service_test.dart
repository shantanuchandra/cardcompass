import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/card_repository.dart';
import 'package:cardcompass/core/repositories/email_repository_interface.dart';
import 'package:cardcompass/core/services/data_pipeline_debug_service.dart';
import 'package:cardcompass/core/services/enhanced_gmail_service.dart'
    show StatementParsingResult;
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Test double for [CardRepository]. Returns whatever [userCards] a test
/// case configures for [getUserCards]; every other method is unused by
/// [DataPipelineDebugService] and throws if called.
class _FakeCardRepository implements CardRepository {
  _FakeCardRepository({this.userCards = const []});

  final List<CreditCard> userCards;

  @override
  Future<List<CreditCard>> getUserCards(String userId) async => userCards;

  @override
  Future<List<CreditCard>> getAllCards() => throw UnimplementedError();

  @override
  Future<void> addUserCard(
          {required String userId,
          required String cardId,
          required String lastFourDigits}) =>
      throw UnimplementedError();

  @override
  Future<void> removeUserCard(
          {required String userId, required String cardId}) =>
      throw UnimplementedError();

  @override
  Future<void> updateUserCard(
          {required String userId,
          required String cardId,
          String? lastFourDigits,
          double? creditLimit}) =>
      throw UnimplementedError();

  @override
  Future<CreditCard?> getCardById(String cardId) => throw UnimplementedError();

  @override
  Future<List<CreditCard>> searchCards(
          {String? bankName,
          String? cardType,
          String? network,
          double? maxAnnualFee,
          double? minIncome}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getAvailableBanks() => throw UnimplementedError();

  @override
  Future<List<String>> getAvailableNetworks() => throw UnimplementedError();

  @override
  Future<double> calculateReward(
          {required String cardId,
          required String category,
          required double amount}) =>
      throw UnimplementedError();

  @override
  Future<CreditCard?> getBestCardForTransaction(
          {required String userId,
          required String category,
          required double amount,
          String? merchantName}) =>
      throw UnimplementedError();
}

/// Test double for [EmailRepositoryInterface]. `emailExists` always reports
/// no existing record so the service proceeds to `storeEmail`; both writes
/// are no-ops that succeed trivially, keeping focus on the card-association
/// failure path under test.
class _FakeEmailRepository implements EmailRepositoryInterface {
  @override
  Future<bool> emailExists(String userId, String emailId) async => false;

  @override
  Future<String> storeEmail({
    required String userId,
    required String emailId,
    required String subject,
    required String sender,
    required DateTime receivedDate,
    required bool hasAttachments,
    String? bankDetected,
    Map<String, dynamic>? metadata,
  }) async =>
      'fake-email-record-id';

  @override
  Future<void> updateEmailStatus({
    required String userId,
    required String emailId,
    required bool processed,
    String? statementId,
  }) async {}
}

void main() {
  group('DataPipelineDebugService.createUserCardAssociation', () {
    test(
        'throws instead of fabricating a user card ID when the RPC fails and no existing match is found',
        () async {
      final service = DataPipelineDebugService(
        cardRepo: _FakeCardRepository(userCards: const []),
        associateUserWithCard: (
                {required String userId, required String catalogCardId}) =>
            throw Exception('simulated RPC failure'),
      );

      expect(
        () => service.createUserCardAssociation('user-1', 'catalog-card-1'),
        throwsException,
      );
    });
  });

  group('DataPipelineDebugService.processEmailSequentially', () {
    test(
        'reports a StatementSyncFailure with the statement bank/date when '
        'card association fails and no existing match is found, instead of '
        'silently dropping the transactions', () async {
      // A non-empty transaction list so transactionCount > 0 and storage is
      // attempted (an empty statement takes an early "nothing to store"
      // return, which isn't the path this test exercises).
      final statementWithTransaction = StatementParsingResult(
        bankName: 'ICICI',
        statementDate: DateTime(2026, 3, 15),
        transactions: [
          Transaction(
            id: 'tx-1',
            userId: 'user-1',
            amount: 100.0,
            description: 'Test purchase',
            transactionDate: DateTime(2026, 3, 10),
            createdAt: DateTime(2026, 3, 10),
          ),
        ],
        originalPdfData: Uint8List(0),
        emailMessageId: 'email-1',
        processingSuccess: true,
        emailSubject: 'Your ICICI statement',
      );

      final service = DataPipelineDebugService(
        cardRepo: _FakeCardRepository(userCards: const []),
        emailRepo: _FakeEmailRepository(),
        findOrCreateCatalogCard: (
                {required String userId,
                required String bankName,
                required String cardName,
                required String emailSubject,
                required String pdfName}) async =>
            'catalog-card-1',
        associateUserWithCard: (
                {required String userId, required String catalogCardId}) =>
            throw Exception('simulated RPC failure'),
      );

      final result = await service.processEmailSequentially(
        'user-1',
        statementWithTransaction,
        const {},
        1,
        1,
      );

      expect(result.transactionCount, 0);
      expect(result.failure, isNotNull);
      expect(result.failure!.bankName, 'ICICI');
      expect(result.failure!.statementDate, DateTime(2026, 3, 15));
    });
  });

  group('DataPipelineDebugService card-catalog request flow', () {
    test(
        'queues a review request and reports failure instead of inserting '
        'directly into card_catalog when no catalog match exists and the '
        'user provides a card URL', () async {
      final statementWithTransaction = StatementParsingResult(
        bankName: 'ICICI',
        statementDate: DateTime(2026, 3, 15),
        transactions: [
          Transaction(
            id: 'tx-1',
            userId: 'user-1',
            amount: 100.0,
            description: 'Test purchase',
            transactionDate: DateTime(2026, 3, 10),
            createdAt: DateTime(2026, 3, 10),
          ),
        ],
        originalPdfData: Uint8List(0),
        emailMessageId: 'email-1',
        processingSuccess: true,
        emailSubject: 'Your ICICI statement',
      );

      final submittedRequests = <Map<String, String>>[];

      final serviceWithSubmitSeam = DataPipelineDebugService(
        cardRepo: _FakeCardRepository(userCards: const []),
        emailRepo: _FakeEmailRepository(),
        lookupCatalogCard: (
                {required String bankName,
                required String cardName,
                required String emailSubject,
                required String? cardUrl}) async =>
            null,
        submitCardCatalogRequest: (
            {required String userId,
            required String bankName,
            required String cardName,
            required String cardUrl}) async {
          submittedRequests.add(
              {'bankName': bankName, 'cardName': cardName, 'cardUrl': cardUrl});
          return true;
        },
      );
      serviceWithSubmitSeam.onCardUrlRequired = ({
        required String bankName,
        required String cardVariant,
        required String emailSubject,
        required String pdfName,
        String? suggestedUrl,
      }) async =>
          'https://example.com/icici-amazon-pay-card';

      final result = await serviceWithSubmitSeam.processEmailSequentially(
        'user-1',
        statementWithTransaction,
        const {},
        1,
        1,
      );

      expect(submittedRequests, [
        {
          'bankName': 'ICICI',
          'cardName': 'ICICI',
          'cardUrl': 'https://example.com/icici-amazon-pay-card',
        }
      ]);
      expect(result.transactionCount, 0);
      expect(result.failure, isNotNull);
      expect(result.failure!.reason, contains('submitted for admin review'));
    });
  });
}
