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
import 'transaction_categorizer.dart';
import 'bank_market.dart';
import 'transaction_currency_resolver.dart';
import 'transaction_type_normalizer.dart';

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
  final Map<String, String?> _merchantCategoryCache = {};

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
  }) : _gmailService = gmailService,
       _emailRepo = EmailRepository(),
       _statementsRepo = StatementsRepository(supabaseClient),
       _transactionsRepo = TransactionsRepository(supabaseClient),
       _cardsRepo = CardsRepository(supabaseClient),
       _userId = userId,
       _userEmail = userEmail,
       _userName = userName,
       _forcedCardIdByBank = forcedCardIdByBank;

  Future<void> _warmMerchantCategoryCache(String normalizedMerchantName) async {
    if (_merchantCategoryCache.containsKey(normalizedMerchantName)) return;
    _merchantCategoryCache[normalizedMerchantName] = await _transactionsRepo
        .lookupMerchantCategory(normalizedMerchantName);
  }

  Future<StatementProcessingResult> processUnprocessedEmails() async {
    final emails = await _emailRepo.getUnprocessedEmails(_userId);
    final userCards = await _cardsRepo.getUserCards(_userId);

    var succeeded = 0;
    var needsPassword = 0;
    var needsCardAssignment = 0;
    var failed = 0;

    for (final email in emails) {
      EmailOutcome outcome;
      try {
        outcome = await _processOne(email, userCards);
      } catch (e) {
        ParsingLogger.error(
          'Statement Processing: Unhandled error processing email ${email['email_id']}',
          e,
        );
        outcome = EmailOutcome.failed;
      }
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

  /// Reprocesses exactly one email against an explicitly given card, skipping
  /// the bank-name matching scan entirely. Used by the manual bank-resolution
  /// flow, where the card to use is already known (the user just picked it or
  /// it was just created) rather than needing to be inferred from bank name.
  Future<EmailOutcome> processSpecificEmail({
    required String emailId,
    required String userCardId,
  }) async {
    final email = await _emailRepo.getEmailById(
      userId: _userId,
      emailId: emailId,
    );
    if (email == null) {
      ParsingLogger.error(
        'Statement Processing: Email $emailId not found for targeted reprocess',
        null,
      );
      return EmailOutcome.failed;
    }

    final userCards = await _cardsRepo.getUserCards(_userId);
    final userCard = userCards.where((c) => c.id == userCardId).firstOrNull;
    if (userCard == null) {
      ParsingLogger.error(
        'Statement Processing: Card $userCardId not found for targeted reprocess',
        null,
      );
      return EmailOutcome.failed;
    }

    try {
      return await _processOneWithCard(email, userCard);
    } catch (e) {
      ParsingLogger.error(
        'Statement Processing: Unhandled error in targeted reprocess of email $emailId',
        e,
      );
      return EmailOutcome.failed;
    }
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

    if (attachmentId == null) {
      ParsingLogger.warning(
        'Statement Processing: No attachment id for email $emailId, skipping',
      );
      return EmailOutcome.failed;
    }

    final bankName = CardNormalizerService.normalizeBankName(
      sender.isNotEmpty ? sender : subject,
    );

    if (userCards.isEmpty) {
      ParsingLogger.warning(
        'Statement Processing: No cards on file for user, skipping email $emailId',
      );
      return EmailOutcome.failed;
    }

    final candidates = userCards.where((card) {
      final code = card.bankCode;
      return bankName.toLowerCase().contains(code) ||
          code.contains(bankName.toLowerCase().split(' ').first);
    }).toList();

    if (candidates.length == 1) {
      return _processOneWithCard(email, candidates.first);
    }

    // Zero or multiple same-bank candidates: bank name alone can't decide.
    // Check if the user has already resolved this exact bank name before —
    // but only trust that shortcut when there's a single card on file for
    // the bank, since a prior resolution can't disambiguate between two
    // same-bank cards either.
    if (candidates.isEmpty) {
      final forcedCardId = _forcedCardIdByBank[bankName];
      final previousCardId =
          forcedCardId ??
          await _emailRepo.findPreviouslyAssignedCard(
            userId: _userId,
            bankDetected: bankName,
          );
      final previousCard = previousCardId == null
          ? null
          : userCards.where((c) => c.id == previousCardId).firstOrNull;
      if (previousCard != null) {
        return _processOneWithCard(email, previousCard);
      }

      await _emailRepo.markNeedsCardAssignment(
        userId: _userId,
        emailId: emailId,
        bankDetected: bankName,
      );
      return EmailOutcome.needsCardAssignment;
    }

    // Multiple cards share this bank (e.g. two HDFC cards). Download and
    // parse first, then disambiguate using the statement's own last-4
    // digits against each candidate's lastFourDigits — the only reliable
    // signal, since filenames and sender addresses don't vary per card.
    return _processOneAmbiguousBank(email, candidates, bankName);
  }

  Future<EmailOutcome> _processOneAmbiguousBank(
    Map<String, dynamic> email,
    List<UserCard> staleCandidates,
    String bankName,
  ) async {
    final emailId = email['email_id'] as String;
    final subject = email['subject'] as String? ?? '';
    final metadata = email['metadata'] as Map<String, dynamic>? ?? {};
    final attachmentId = metadata['attachmentId'] as String?;
    final fileName = metadata['attachmentFilename'] as String?;

    // Re-fetch cards fresh rather than trusting staleCandidates: within one
    // processUnprocessedEmails() run, earlier same-bank statements in this
    // same batch may have just backfilled a candidate's real last-4 via
    // _persistParsedStatement, and the in-memory list from the top of the
    // batch wouldn't reflect that yet.
    final freshCards = await _cardsRepo.getUserCards(_userId);
    final candidateIds = staleCandidates.map((c) => c.id).toSet();
    final candidates = freshCards
        .where((c) => candidateIds.contains(c.id))
        .toList();

    if (attachmentId == null) {
      ParsingLogger.warning(
        'Statement Processing: No attachment id for email $emailId, skipping',
      );
      return EmailOutcome.failed;
    }

    Uint8List pdfBytes;
    try {
      pdfBytes = await _gmailService.downloadAttachment(emailId, attachmentId);
    } catch (e) {
      ParsingLogger.error(
        'Statement Processing: Failed to download attachment for $emailId',
        e,
      );
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

    final statementInfo = await GeminiStatementParser.parseStatementInfo(
      pdfText: text,
      bankName: bankName,
    );

    final last4 = (statementInfo['card_last4'] as String?)?.trim();
    var matched = last4 != null && last4.isNotEmpty
        ? candidates.where((c) => c.lastFourDigits == last4).firstOrNull
        : null;

    // No exact last-4 match — but if exactly one same-bank candidate has no
    // verified last-4 on file yet (null, or the known "1234" placeholder
    // some cards were added with before any statement had been parsed),
    // it's the only card this statement could belong to. Match it, and
    // _persistParsedStatement's backfillCardDetails call will immediately
    // record the real last-4 this statement just revealed.
    if (matched == null && last4 != null && last4.isNotEmpty) {
      final unverified = candidates
          .where(
            (c) =>
                c.lastFourDigits == null ||
                c.lastFourDigits == CardsRepository.placeholderLastFour,
          )
          .toList();
      if (unverified.length == 1) {
        matched = unverified.first;
      }
    }

    if (matched == null) {
      ParsingLogger.warning(
        'Statement Processing: Ambiguous bank "$bankName" with ${candidates.length} cards on file; '
        'statement card_last4 "$last4" didn\'t match any of them, asking user to clarify ($emailId)',
      );
      await _emailRepo.markNeedsCardAssignment(
        userId: _userId,
        emailId: emailId,
        bankDetected: bankName,
      );
      return EmailOutcome.needsCardAssignment;
    }

    return _persistParsedStatement(
      email: email,
      userCard: matched,
      bankName: bankName,
      statementInfo: statementInfo,
      pdfText: text,
    );
  }

  /// Downloads, unlocks, parses, and persists the statement for [email]
  /// against an already-decided [userCard] — no bank-matching involved.
  Future<EmailOutcome> _processOneWithCard(
    Map<String, dynamic> email,
    UserCard userCard,
  ) async {
    final emailId = email['email_id'] as String;
    final subject = email['subject'] as String? ?? '';
    final sender = email['sender'] as String? ?? '';
    final metadata = email['metadata'] as Map<String, dynamic>? ?? {};
    final attachmentId = metadata['attachmentId'] as String?;
    final fileName = metadata['attachmentFilename'] as String?;

    if (attachmentId == null) {
      ParsingLogger.warning(
        'Statement Processing: No attachment id for email $emailId, skipping',
      );
      return EmailOutcome.failed;
    }

    final bankName = CardNormalizerService.normalizeBankName(
      sender.isNotEmpty ? sender : subject,
    );

    Uint8List pdfBytes;
    try {
      pdfBytes = await _gmailService.downloadAttachment(emailId, attachmentId);
    } catch (e) {
      ParsingLogger.error(
        'Statement Processing: Failed to download attachment for $emailId',
        e,
      );
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

    final statementInfo = await GeminiStatementParser.parseStatementInfo(
      pdfText: text,
      bankName: bankName,
    );

    return _persistParsedStatement(
      email: email,
      userCard: userCard,
      bankName: bankName,
      statementInfo: statementInfo,
      pdfText: text,
    );
  }

  /// Parses transactions from [pdfText] and writes the statement + its
  /// transactions to [userCard], then marks the email processed. Shared by
  /// both the single-candidate and disambiguated-multi-candidate paths,
  /// which differ only in how they arrived at [userCard] and already have
  /// [statementInfo] parsed (so it isn't re-requested from Gemini here).
  Future<EmailOutcome> _persistParsedStatement({
    required Map<String, dynamic> email,
    required UserCard userCard,
    required String bankName,
    required Map<String, dynamic> statementInfo,
    required String pdfText,
  }) async {
    final emailId = email['email_id'] as String;
    try {
      final transactions = await GeminiStatementParser.parseTransactions(
        pdfText: pdfText,
        bankName: bankName,
      );

      final userCardId = userCard.id;
      final catalogCardId = userCard.catalogCardId;

      // Three-tier fallback for statement_date: Gemini's extraction, then a
      // direct regex pass over the PDF text (catches statements where
      // Gemini's call succeeded but didn't find the date), then the email's
      // own received_date. The received_date tier matters because it varies
      // per email — falling back to DateTime.now() instead would make every
      // undated statement for a card collide onto today's date, since
      // statements upsert on (user_card_id, statement_date).
      final statementDate = statementInfo['statement_date'] != null
          ? DateTime.parse(statementInfo['statement_date'] as String)
          : GeminiStatementParser.extractStatementDateFromText(pdfText) ??
                DateTime.parse(email['received_date'] as String);
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
        minimumPayment:
            (statementInfo['minimum_payment'] as num?)?.toDouble() ?? 0,
        closingBalance:
            (statementInfo['closing_balance'] as num?)?.toDouble() ?? 0,
        availableCredit:
            (statementInfo['available_credit'] as num?)?.toDouble() ?? 0,
        rewardsEarned:
            (statementInfo['rewards_earned'] as num?)?.toDouble() ?? 0,
        transactionCount: transactions.length,
      );

      final bankMarketCurrency = currencyForBank(bankName);

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final description =
            txn['description'] as String? ?? 'Unknown transaction';
        final type = TransactionTypeNormalizer.normalize(
          parserType: txn['type'] as String?,
          description: description,
        );
        final rawMerchantName = txn['merchantName'] as String?;
        final merchantForCategorization = rawMerchantName ?? description;
        final normalizedMerchant = normalizeMerchantName(
          merchantForCategorization,
        );

        await _warmMerchantCategoryCache(normalizedMerchant);
        final categorization = categorize(
          merchantName: merchantForCategorization,
          description: description,
          geminiCategory: txn['category'] as String?,
          merchantLookup: (normalized) => _merchantCategoryCache[normalized],
        );
        final currency = resolveTransactionCurrency(
          geminiCurrency: txn['currency'] as String?,
          bankMarketCurrency: bankMarketCurrency,
        );

        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: description,
          transactionDate: txn['date'] != null
              ? DateTime.parse(txn['date'] as String)
              : statementDate,
          currency: currency,
          merchantName: rawMerchantName,
          category: categorization.category,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
          metadata: {
            'category_source': categorization.source.name,
            'normalized_transaction_type': type,
          },
        );
      }

      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: true,
        statementId: statement.id,
        bankDetected: bankName,
      );

      // Backfill last-4 digits / credit limit onto the card the first time
      // a statement reveals them — only fills currently-null fields, never
      // overwrites a value the user entered manually.
      final last4 = (statementInfo['card_last4'] as String?)?.trim();
      final creditLimit = (statementInfo['credit_limit'] as num?)?.toDouble();
      if ((last4 != null && last4.isNotEmpty) || creditLimit != null) {
        await _cardsRepo.backfillCardDetails(
          userCardId: userCardId,
          lastFourDigits: last4 != null && last4.isNotEmpty ? last4 : null,
          creditLimit: creditLimit,
        );
      }

      return EmailOutcome.succeeded;
    } catch (e) {
      ParsingLogger.error(
        'Statement Processing: Failed to parse/store statement for $emailId',
        e,
      );
      return EmailOutcome.failed;
    }
  }
}
