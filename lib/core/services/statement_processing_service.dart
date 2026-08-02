import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/email_repository.dart';
import '../repositories/statements_repository.dart';
import '../repositories/transactions_repository.dart';
import '../repositories/cards_repository.dart';
import '../../shared/models/user_card.dart';
import 'gmail_sync_service.dart';
import 'pdf_password_resolver.dart';
import 'gemini_statement_parser.dart';
import 'card_normalizer_service.dart';
import 'parsing_logger.dart';

enum EmailOutcome { succeeded, needsPassword, needsCardAssignment, failed }

class StatementProcessingResult {
  final int totalAttempted;
  final int succeeded;
  final int needsPassword;
  final int needsCardAssignment;
  final int failed;

  const StatementProcessingResult({
    required this.totalAttempted,
    required this.succeeded,
    required this.needsPassword,
    required this.needsCardAssignment,
    required this.failed,
  });
}

/// Processes every unprocessed statement email for a user: downloads the PDF,
/// resolves its password, parses statement info + transactions via Gemini,
/// persists them, and marks the email processed.
class StatementProcessingService {
  final GmailSyncService _gmailService;
  final EmailRepository _emailRepo;
  final StatementsRepository _statementsRepo;
  final TransactionsRepository _transactionsRepo;
  final CardsRepository _cardsRepo;
  final String _userId;
  final String _userEmail;
  final String _userName;
  final Map<String, String> _forcedCardIdByBank;

  /// [forcedCardIdByBank] lets a caller pin a specific bank name (as stored
  /// in emails.bank_detected) to a card for this run — used right after the
  /// user manually resolves a previously-unmatched bank, so this pass uses
  /// their choice instead of (still nonexistent) prior-resolution history.
  StatementProcessingService({
    required GmailSyncService gmailService,
    required SupabaseClient supabaseClient,
    required String userId,
    required String userEmail,
    required String userName,
    Map<String, String> forcedCardIdByBank = const {},
  })  : _gmailService = gmailService,
        _emailRepo = EmailRepository(),
        _statementsRepo = StatementsRepository(supabaseClient),
        _transactionsRepo = TransactionsRepository(supabaseClient),
        _cardsRepo = CardsRepository(supabaseClient),
        _userId = userId,
        _userEmail = userEmail,
        _userName = userName,
        _forcedCardIdByBank = forcedCardIdByBank;

  Future<StatementProcessingResult> processUnprocessedEmails() async {
    final emails = await _emailRepo.getUnprocessedEmails(_userId);
    final userCards = await _cardsRepo.getUserCards(_userId);

    var succeeded = 0;
    var needsPassword = 0;
    var needsCardAssignment = 0;
    var failed = 0;

    for (final email in emails) {
      final outcome = await _processOne(email, userCards);
      switch (outcome) {
        case EmailOutcome.succeeded:
          succeeded++;
          break;
        case EmailOutcome.needsPassword:
          needsPassword++;
          break;
        case EmailOutcome.needsCardAssignment:
          needsCardAssignment++;
          break;
        case EmailOutcome.failed:
          failed++;
          break;
      }
    }

    return StatementProcessingResult(
      totalAttempted: emails.length,
      succeeded: succeeded,
      needsPassword: needsPassword,
      needsCardAssignment: needsCardAssignment,
      failed: failed,
    );
  }

  Future<EmailOutcome> _processOne(
    Map<String, dynamic> email,
    List<UserCard> userCards,
  ) async {
    final emailId = email['email_id'] as String;
    final subject = email['subject'] as String? ?? '';
    final sender = email['sender'] as String? ?? '';
    final metadata = email['metadata'] as Map<String, dynamic>? ?? {};
    final attachmentId = metadata['attachmentId'] as String?;
    final fileName = metadata['attachmentFilename'] as String?;

    if (attachmentId == null) {
      ParsingLogger.warning('Statement Processing: No attachment id for email $emailId, skipping');
      return EmailOutcome.failed;
    }

    final bankName = CardNormalizerService.normalizeBankName(sender.isNotEmpty ? sender : subject);

    if (userCards.isEmpty) {
      ParsingLogger.warning('Statement Processing: No cards on file for user, skipping email $emailId');
      return EmailOutcome.failed;
    }

    UserCard? matchedCard;
    for (final card in userCards) {
      final code = card.bankCode;
      if (bankName.toLowerCase().contains(code) ||
          code.contains(bankName.toLowerCase().split(' ').first)) {
        matchedCard = card;
        break;
      }
    }

    // Bank didn't match any card's gradient-lookup code. Rather than
    // silently guessing (userCards.first), check if the user has already
    // resolved this exact bank name before; if not, ask them to clarify
    // instead of risking a wrong — or colliding — statement attribution.
    if (matchedCard == null) {
      final forcedCardId = _forcedCardIdByBank[bankName];
      final previousCardId = forcedCardId ??
          await _emailRepo.findPreviouslyAssignedCard(
            userId: _userId,
            bankDetected: bankName,
          );
      if (previousCardId != null) {
        matchedCard = userCards.where((c) => c.id == previousCardId).firstOrNull;
      }
    }

    if (matchedCard == null) {
      await _emailRepo.markNeedsCardAssignment(
        userId: _userId,
        emailId: emailId,
        bankDetected: bankName,
      );
      return EmailOutcome.needsCardAssignment;
    }

    Uint8List pdfBytes;
    try {
      pdfBytes = await _gmailService.downloadAttachment(emailId, attachmentId);
    } catch (e) {
      ParsingLogger.error('Statement Processing: Failed to download attachment for $emailId', e);
      return EmailOutcome.failed;
    }

    final resolver = PdfPasswordResolver();
    final googleAccessToken =
        Supabase.instance.client.auth.currentSession?.providerToken ?? '';

    final text = await resolver.extractText(
      pdfBytes: pdfBytes,
      bankName: bankName,
      userId: _userId,
      userEmail: _userEmail,
      userName: _userName,
      googleAccessToken: googleAccessToken,
      fileName: fileName,
      emailSubject: subject,
    );

    if (text == null) {
      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: false,
        bankDetected: bankName,
      );
      return EmailOutcome.needsPassword;
    }

    try {
      final statementInfo = await GeminiStatementParser.parseStatementInfo(
        pdfText: text,
        bankName: bankName,
      );
      final transactions = await GeminiStatementParser.parseTransactions(
        pdfText: text,
        bankName: bankName,
      );

      final userCard = matchedCard;
      final userCardId = userCard.id;
      final catalogCardId = userCard.catalogCardId;

      final statementDate = statementInfo['statement_date'] != null
          ? DateTime.parse(statementInfo['statement_date'] as String)
          : DateTime.now();
      final dueDate = statementInfo['due_date'] != null
          ? DateTime.parse(statementInfo['due_date'] as String)
          : statementDate.add(const Duration(days: 20));

      final statement = await _statementsRepo.upsertStatement(
        userId: _userId,
        cardId: catalogCardId,
        userCardId: userCardId,
        statementDate: statementDate,
        dueDate: dueDate,
        totalAmount: (statementInfo['total_amount'] as num?)?.toDouble() ?? 0,
        minimumPayment: (statementInfo['minimum_payment'] as num?)?.toDouble() ?? 0,
        closingBalance: (statementInfo['closing_balance'] as num?)?.toDouble() ?? 0,
        availableCredit: (statementInfo['available_credit'] as num?)?.toDouble() ?? 0,
        rewardsEarned: (statementInfo['rewards_earned'] as num?)?.toDouble() ?? 0,
        transactionCount: transactions.length,
      );

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: txn['description'] as String? ?? 'Unknown transaction',
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          merchantName: txn['merchantName'] as String?,
          category: txn['category'] as String?,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
        );
      }

      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: true,
        statementId: statement.id,
        bankDetected: bankName,
      );

      return EmailOutcome.succeeded;
    } catch (e) {
      ParsingLogger.error('Statement Processing: Failed to parse/store statement for $emailId', e);
      return EmailOutcome.failed;
    }
  }
}
