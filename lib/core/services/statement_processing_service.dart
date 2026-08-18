// ignore_for_file: prefer_initializing_formals

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
import 'card_identity_service.dart';
import 'card_discovery_service.dart';
import 'parsing_logger.dart';
import 'transaction_categorizer.dart';
import 'bank_market.dart';
import 'transaction_currency_resolver.dart';
import 'transaction_type_normalizer.dart';

enum EmailOutcome {
  succeeded,
  needsPassword,
  needsCardAssignment,
  discoveryQueued,
  failed,
}

/// Gemini generally returns JSON numbers, but statement typography sometimes
/// causes it to preserve currency symbols and Indian digit grouping. Treat
/// those values as optional evidence instead of letting one formatted field
/// abort persistence for the whole statement.
double? parsedGeminiNumber(Object? value) {
  if (value is num) return value.toDouble();
  if (value is! String) return null;
  final normalized = value
      .trim()
      .replaceAll(',', '')
      .replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (normalized.isEmpty || normalized == '-' || normalized == '.') {
    return null;
  }
  return double.tryParse(normalized);
}

/// Accepts the ISO dates requested from Gemini and the common DD/MM/YYYY form
/// seen in Indian statement tables. Invalid optional dates fall back to the
/// statement date rather than failing the entire email.
DateTime parsedGeminiDate(Object? value, DateTime fallback) {
  if (value is DateTime) return value;
  if (value is! String || value.trim().isEmpty) return fallback;
  final raw = value.trim();
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;
  final dayFirst = RegExp(
    r'^(\d{1,2})[\-/](\d{1,2})[\-/](\d{4})$',
  ).firstMatch(raw);
  if (dayFirst == null) return fallback;
  final day = int.parse(dayFirst.group(1)!);
  final month = int.parse(dayFirst.group(2)!);
  final year = int.parse(dayFirst.group(3)!);
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : fallback;
}

/// Extracts the last four digits from an explicitly-labelled masked primary
/// card number, as used on HSBC statements.
String? extractPrimaryCardLastFour(String pdfText) {
  final label = RegExp(
    r'primary\s+card\s+number\s*[:\-]?',
    caseSensitive: false,
  ).firstMatch(pdfText);
  if (label == null) return null;

  // PDF text layers sometimes insert whitespace between every glyph. Limit
  // the search to the small labelled field, then remove layout separators so
  // both `51xx xxxx xxxx 1759` and `5 1 x x ... 1 7 5 9` normalize alike.
  final fieldEnd = label.end + 80 < pdfText.length
      ? label.end + 80
      : pdfText.length;
  final normalized = pdfText
      .substring(label.end, fieldEnd)
      .replaceAll(RegExp(r'[\s\-]'), '');
  final labelledNumber = RegExp(
    r'(?:\d{2}[xX*]{10}|[xX*]{12})(\d{4})(?!\d)',
  ).firstMatch(normalized);
  return labelledNumber?.group(1);
}

/// Keeps a valid parser result, otherwise supplements it with deterministic
/// evidence from the PDF text.
Map<String, dynamic> statementInfoWithCardLastFour(
  Map<String, dynamic> statementInfo,
  String pdfText,
) {
  final existing = (statementInfo['card_last4'] as String?)?.trim();
  if (existing != null && RegExp(r'^\d{4}$').hasMatch(existing)) {
    return statementInfo;
  }
  final extracted = extractPrimaryCardLastFour(pdfText);
  if (extracted == null) return statementInfo;
  return {...statementInfo, 'card_last4': extracted};
}

/// Builds the small, sanitized evidence set shown while a user resolves an
/// ambiguous statement. Raw statement text and transaction rows never enter
/// email metadata.
Map<String, dynamic> buildCardIdentityHints({
  required String bankName,
  required Map<String, dynamic> statementInfo,
  String? attachmentFilename,
}) {
  final hints = <String, dynamic>{};

  void addText(String key, Object? value) {
    if (value is! String) return;
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) hints[key] = trimmed;
  }

  addText('bank', bankName);
  final last4 = statementInfo['card_last4'];
  if (last4 is String && RegExp(r'^\s*\d{4}\s*$').hasMatch(last4)) {
    hints['last4'] = last4.trim();
  }
  addText('productName', statementInfo['card_name']);
  addText('statementDate', statementInfo['statement_date']);
  addText('dueDate', statementInfo['due_date']);
  final totalAmount = statementInfo['total_amount'];
  if (totalAmount is num) hints['totalAmount'] = totalAmount;
  addText('attachmentFilename', attachmentFilename);
  return hints;
}

Map<String, dynamic> metadataAfterCardAssignment(Map<dynamic, dynamic>? value) {
  final metadata = Map<String, dynamic>.from(value ?? const {});
  metadata.remove('needsCardAssignment');
  return metadata;
}

/// Returns only statement emails that still need automated processing.
///
/// Emails awaiting an explicit card choice stay unprocessed so they remain in
/// the assignment queue, but rerunning PDF/Gemini parsing cannot resolve that
/// user decision and only repeats expensive work.
List<Map<String, dynamic>> statementEmailsReadyForProcessing(
  Iterable<Map<String, dynamic>> emails, {
  List<UserCard> userCards = const [],
  Set<String>? allowedEmailIds,
}) {
  return emails.where((email) {
    if (allowedEmailIds != null &&
        !allowedEmailIds.contains(email['email_id'] as String?)) {
      return false;
    }
    final metadata = email['metadata'];
    if (metadata is! Map || metadata['needsCardAssignment'] != true) {
      return true;
    }
    // Pending rows must reach _processOne: it now performs the cheap catalog
    // evidence check before any PDF parsing or single-bank-card fallback.
    return true;
  }).toList();
}

/// Returns a card only when filename/subject evidence identifies exactly one
/// same-bank card. Verified last-four digits take precedence; product names in
/// subjects are the fallback for banks whose filenames omit useful digits.
UserCard? cardMatchedFromEmailFilename(
  Map<String, dynamic> email,
  List<UserCard> userCards,
) {
  final metadata = email['metadata'];
  final filename = metadata is Map
      ? metadata['attachmentFilename'] as String?
      : null;

  final detectedBank = CardNormalizerService.normalizeBankName(
    email['bank_detected'] as String? ?? '',
  );
  final sameBankCards = userCards.where((card) {
    final cardBank = CardNormalizerService.normalizeBankName(card.bank ?? '');
    return cardBank == detectedBank;
  }).toList();

  final lastFourMatches = sameBankCards.where((card) {
    final last4 = card.lastFourDigits?.trim();
    if (last4 == null || !RegExp(r'^\d{4}$').hasMatch(last4)) return false;
    return filename != null &&
        RegExp('(?<!\\d)${RegExp.escape(last4)}(?!\\d)').hasMatch(filename);
  }).toList();
  if (lastFourMatches.length == 1) return lastFourMatches.single;

  String searchable(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\bclub\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  final subject = searchable(email['subject'] as String? ?? '');
  if (subject.isEmpty) return null;
  final productMatches = sameBankCards.where((card) {
    final product = searchable(card.cardName ?? '');
    return product.length >= 5 && subject.contains(product);
  }).toList();
  return productMatches.length == 1 ? productMatches.single : null;
}

/// Returns a catalog entry only when the statement names exactly one product.
/// Callers must supply entries already constrained to the detected bank.
Map<String, dynamic>? catalogCardMatchedFromEmailEvidence(
  Map<String, dynamic> email,
  List<Map<String, dynamic>> catalogEntries,
) {
  final metadata = email['metadata'];
  final filename = metadata is Map
      ? metadata['attachmentFilename'] as String? ?? ''
      : '';
  final issuer =
      email['bank_detected'] as String? ??
      (catalogEntries.firstOrNull?['bank'] as String?) ??
      'Unknown Bank';
  final evidence = CardIdentityEvidence.extract(
    issuer: issuer,
    subject: email['subject'] as String? ?? '',
    attachmentFilename: filename,
  );
  final identities = catalogEntries
      .map((entry) {
        final aliasRows = entry['card_catalog_aliases'];
        final aliases = aliasRows is List
            ? aliasRows
                  .whereType<Map>()
                  .map((row) => row['alias'])
                  .whereType<String>()
                  .toList(growable: false)
            : const <String>[];
        return CardCatalogIdentity(
          id: entry['id'] as String,
          issuer: entry['bank'] as String? ?? issuer,
          name: entry['card_name'] as String? ?? '',
          network: entry['network'] as String?,
          aliases: aliases,
        );
      })
      .toList(growable: false);
  final match = const CardIdentityMatcher().match(evidence, identities);
  if (match == null) return null;
  return catalogEntries.where((entry) => entry['id'] == match.id).firstOrNull;
}

Future<UserCard?> resolveCatalogCardForEmail({
  required Map<String, dynamic> email,
  required String bankName,
  required List<UserCard> existingCards,
  required Future<List<Map<String, dynamic>>> Function(String bankName)
  loadCatalog,
  required Future<UserCard> Function(String catalogCardId) createCard,
}) async {
  final catalog = await loadCatalog(bankName);
  final match = catalogCardMatchedFromEmailEvidence(email, catalog);
  final catalogCardId = match?['id'] as String?;
  if (catalogCardId == null) return null;
  final existing = existingCards
      .where((card) => card.catalogCardId == catalogCardId)
      .firstOrNull;
  if (existing != null) return existing;
  return createCard(catalogCardId);
}

enum StatementIssueReason {
  attachmentUnavailable,
  downloadFailed,
  passwordRequired,
  passwordAttemptsExhausted,
  cardAssignmentRequired,
  cardDiscoveryPending,
  processingFailed,
}

class StatementProcessingIssue {
  const StatementProcessingIssue({
    required this.bankName,
    required this.cardContext,
    required this.reason,
  });

  final String bankName;
  final String cardContext;
  final StatementIssueReason reason;
}

/// Keeps failure reporting to one final explanation per processing attempt.
class StatementIssueAccumulator {
  final List<StatementProcessingIssue> _items = [];

  int beginAttempt() => _items.length;

  void record(StatementProcessingIssue issue) => _items.add(issue);

  void replaceAttemptWith(int startIndex, StatementProcessingIssue issue) {
    if (startIndex < _items.length) {
      _items.removeRange(startIndex, _items.length);
    }
    _items.add(issue);
  }

  void clear() => _items.clear();

  List<StatementProcessingIssue> get snapshot => List.unmodifiable(_items);
}

List<String> buildStatementIssueLines(List<StatementProcessingIssue> issues) {
  final grouped =
      <
        ({String bankName, String cardContext, StatementIssueReason reason}),
        int
      >{};
  for (final issue in issues) {
    final key = (
      bankName: issue.bankName,
      cardContext: issue.cardContext,
      reason: issue.reason,
    );
    grouped[key] = (grouped[key] ?? 0) + 1;
  }

  final entries = grouped.entries.toList()
    ..sort((a, b) {
      final bank = a.key.bankName.compareTo(b.key.bankName);
      if (bank != 0) return bank;
      return a.key.reason.index.compareTo(b.key.reason.index);
    });

  String reasonLabel(StatementIssueReason reason) => switch (reason) {
    StatementIssueReason.attachmentUnavailable =>
      'Attachment unavailable before card matching',
    StatementIssueReason.downloadFailed => 'Could not download the statement',
    StatementIssueReason.passwordRequired => 'Statement password required',
    StatementIssueReason.passwordAttemptsExhausted =>
      'Password still incorrect after 2 attempts',
    StatementIssueReason.cardAssignmentRequired => 'Choose the correct card',
    StatementIssueReason.cardDiscoveryPending =>
      'Card identification is continuing in the background',
    StatementIssueReason.processingFailed =>
      'Could not parse or save statement',
  };

  return entries.map((entry) {
    final count = entry.value;
    return '${entry.key.bankName} · ${entry.key.cardContext} · $count ${count == 1 ? 'email' : 'emails'} · ${reasonLabel(entry.key.reason)}';
  }).toList();
}

class StatementProcessingResult {
  final int totalAttempted;
  final int succeeded;
  final int needsPassword;
  final int needsCardAssignment;
  final int discoveryQueued;
  final int failed;
  final List<StatementProcessingIssue> issues;

  const StatementProcessingResult({
    required this.totalAttempted,
    required this.succeeded,
    required this.needsPassword,
    required this.needsCardAssignment,
    this.discoveryQueued = 0,
    required this.failed,
    this.issues = const [],
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
  final CardDiscoveryService _discoveryService;
  final String _userId;
  final String _userEmail;
  final String _userName;
  final Map<String, String?> _merchantCategoryCache = {};
  final StatementIssueAccumulator _issues = StatementIssueAccumulator();

  void _recordIssue({
    required String bankName,
    required String cardContext,
    required StatementIssueReason reason,
  }) {
    _issues.record(
      StatementProcessingIssue(
        bankName: bankName,
        cardContext: cardContext,
        reason: reason,
      ),
    );
  }

  String _cardContext(List<UserCard> cards) {
    if (cards.isEmpty) return 'No matching card';
    final names = cards.map(_cardName).toSet().toList()..sort();
    if (names.length <= 3) return names.join(' / ');
    return '${names.take(3).join(' / ')} / +${names.length - 3} more';
  }

  String _cardName(UserCard card) {
    final name = card.cardName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final lastFour = card.lastFourDigits?.trim();
    return lastFour == null || lastFour.isEmpty
        ? 'Unnamed card'
        : 'Card ••••$lastFour';
  }

  List<UserCard> _cardsForBank(String bankName, List<UserCard> cards) {
    return cards.where((card) {
      final code = card.bankCode;
      return bankName.toLowerCase().contains(code) ||
          code.contains(bankName.toLowerCase().split(' ').first);
    }).toList();
  }

  StatementProcessingService({
    required GmailSyncService gmailService,
    required SupabaseClient supabaseClient,
    required String userId,
    required String userEmail,
    required String userName,
  }) : _gmailService = gmailService,
       _emailRepo = EmailRepository(),
       _statementsRepo = StatementsRepository(supabaseClient),
       _transactionsRepo = TransactionsRepository(supabaseClient),
       _cardsRepo = CardsRepository(supabaseClient),
       _discoveryService = CardDiscoveryService(supabaseClient),
       _userId = userId,
       _userEmail = userEmail,
       _userName = userName;

  Future<void> _warmMerchantCategoryCache(String normalizedMerchantName) async {
    if (_merchantCategoryCache.containsKey(normalizedMerchantName)) return;
    _merchantCategoryCache[normalizedMerchantName] = await _transactionsRepo
        .lookupMerchantCategory(normalizedMerchantName);
  }

  Future<StatementProcessingResult> processUnprocessedEmails({
    required Set<String> allowedEmailIds,
  }) async {
    _issues.clear();
    final userCards = await _cardsRepo.getUserCards(_userId);
    final emails = statementEmailsReadyForProcessing(
      await _emailRepo.getUnprocessedEmails(_userId),
      userCards: userCards,
      allowedEmailIds: allowedEmailIds,
    );

    var succeeded = 0;
    var needsPassword = 0;
    var needsCardAssignment = 0;
    var discoveryQueued = 0;
    var failed = 0;
    final deferredEmails = <Map<String, dynamic>>[];

    for (final email in emails) {
      final attemptStart = _issues.beginAttempt();
      EmailOutcome outcome;
      try {
        outcome = await _processOne(email, userCards);
      } on GmailAuthException {
        rethrow;
      } catch (e) {
        final sender = email['sender'] as String? ?? '';
        final subject = email['subject'] as String? ?? '';
        final bankName = CardNormalizerService.normalizeBankName(
          sender.isNotEmpty ? sender : subject,
        );
        _issues.replaceAttemptWith(
          attemptStart,
          StatementProcessingIssue(
            bankName: bankName,
            cardContext: _cardContext(_cardsForBank(bankName, userCards)),
            reason: StatementIssueReason.processingFailed,
          ),
        );
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
        case EmailOutcome.discoveryQueued:
          discoveryQueued++;
          deferredEmails.add(email);
          break;
        case EmailOutcome.failed:
          failed++;
          break;
      }
    }

    // Revisit only the statements deferred during this pass. The Edge
    // Function may have completed while later Gmail messages were processed;
    // unresolved jobs remain persisted for the next authenticated session.
    for (final email in deferredEmails) {
      final metadata = email['metadata'];
      final jobId = metadata is Map
          ? metadata['cardDiscoveryJobId'] as String?
          : null;
      if (jobId == null) continue;
      try {
        final job = await _discoveryService.status(jobId);
        if (job.status != 'resolved' || job.resolvedCardId == null) continue;
        final outcome = await _processOne(email, userCards);
        if (outcome == EmailOutcome.succeeded) {
          discoveryQueued--;
          succeeded++;
        } else if (outcome == EmailOutcome.needsPassword) {
          discoveryQueued--;
          needsPassword++;
        }
      } on GmailAuthException {
        rethrow;
      } catch (error) {
        ParsingLogger.warning(
          'Statement Processing: Deferred discovery retry unavailable: $error',
        );
      }
    }

    return StatementProcessingResult(
      totalAttempted: emails.length,
      succeeded: succeeded,
      needsPassword: needsPassword,
      needsCardAssignment: needsCardAssignment,
      discoveryQueued: discoveryQueued,
      failed: failed,
      issues: _issues.snapshot,
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
    } on GmailAuthException {
      rethrow;
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

    final discoveryJobId = metadata['cardDiscoveryJobId'] as String?;
    if (discoveryJobId != null && discoveryJobId.isNotEmpty) {
      try {
        final discovery = await _discoveryService.status(discoveryJobId);
        if (discovery.status == 'resolved' &&
            discovery.resolvedCardId != null) {
          final existing = userCards
              .where((card) => card.catalogCardId == discovery.resolvedCardId)
              .firstOrNull;
          final resolvedCard =
              existing ??
              await _cardsRepo.addUserCard(
                userId: _userId,
                catalogCardId: discovery.resolvedCardId!,
              );
          if (existing == null) userCards.add(resolvedCard);
          await _emailRepo.updateEmailMetadata(
            userId: _userId,
            emailId: emailId,
            metadata: metadataAfterCardDiscoveryResolved(metadata),
          );
          return _processOneWithCard(email, resolvedCard);
        }
        final retryDue =
            discovery.status == 'failed' &&
            (discovery.retryAfter == null ||
                !discovery.retryAfter!.isAfter(DateTime.now()));
        if (retryDue) {
          email['metadata'] = metadataAfterCardDiscoveryResolved(metadata);
        } else if (discovery.status == 'queued' ||
            discovery.status == 'discovering' ||
            discovery.status == 'review_required' ||
            discovery.status == 'failed') {
          _recordIssue(
            bankName: email['bank_detected'] as String? ?? 'Unknown bank',
            cardContext: 'Catalog discovery',
            reason: StatementIssueReason.cardDiscoveryPending,
          );
          return EmailOutcome.discoveryQueued;
        }
      } catch (error) {
        ParsingLogger.warning(
          'Statement Processing: Discovery status unavailable for $emailId: $error',
        );
      }
    }

    final bankName = CardNormalizerService.normalizeBankName(
      sender.isNotEmpty ? sender : subject,
    );

    final candidates = _cardsForBank(bankName, userCards);
    final filenameMatchedCard = cardMatchedFromEmailFilename(email, userCards);

    if (filenameMatchedCard != null) {
      await _emailRepo.updateEmailMetadata(
        userId: _userId,
        emailId: emailId,
        metadata: metadataAfterCardAssignment(metadata),
      );
      return _processOneWithCard(email, filenameMatchedCard);
    }

    if (attachmentId == null) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardContext(candidates),
        reason: StatementIssueReason.attachmentUnavailable,
      );
      ParsingLogger.warning(
        'Statement Processing: No attachment id for email $emailId, skipping',
      );
      return EmailOutcome.failed;
    }

    // Product evidence must run before the legacy single-bank-card shortcut.
    // Otherwise, after the first auto-created ICICI/HDFC card, every other
    // product from that bank would be incorrectly assigned to it.
    final catalogCard = await resolveCatalogCardForEmail(
      email: email,
      bankName: bankName,
      existingCards: userCards,
      loadCatalog: (bank) => _cardsRepo.searchCatalogForBank(bank),
      createCard: (catalogCardId) =>
          _cardsRepo.addUserCard(userId: _userId, catalogCardId: catalogCardId),
    );
    if (catalogCard != null) {
      if (!userCards.any((card) => card.id == catalogCard.id)) {
        userCards.add(catalogCard);
      }
      await _emailRepo.updateEmailMetadata(
        userId: _userId,
        emailId: emailId,
        metadata: metadataAfterCardAssignment(metadata),
      );
      return _processOneWithCard(email, catalogCard);
    }

    final initialEvidence = CardIdentityEvidence.extract(
      issuer: bankName,
      subject: subject,
      attachmentFilename: metadata['attachmentFilename'] as String?,
    );

    // A named product that did not match the catalog must not fall through to
    // the legacy one-card-per-bank shortcut. Parse the PDF header so discovery
    // receives all three independent identity sources.
    if (initialEvidence.productSignals.isNotEmpty) {
      return _processOneAmbiguousBank(email, candidates, bankName);
    }

    if (candidates.length == 1) {
      return _processOneWithCard(email, candidates.first);
    }

    // Zero or multiple same-bank candidates: bank name alone can't decide.
    // Check if the user has already resolved this exact bank name before —
    // but only trust that shortcut when there's a single card on file for
    // the bank, since a prior resolution can't disambiguate between two
    // same-bank cards either.
    if (candidates.isEmpty) {
      return _processOneAmbiguousBank(email, const [], bankName);
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
      _recordIssue(
        bankName: bankName,
        cardContext: _cardContext(candidates),
        reason: StatementIssueReason.attachmentUnavailable,
      );
      ParsingLogger.warning(
        'Statement Processing: No attachment id for email $emailId, skipping',
      );
      return EmailOutcome.failed;
    }

    Uint8List pdfBytes;
    try {
      pdfBytes = await _gmailService.downloadAttachment(emailId, attachmentId);
    } on GmailAuthException {
      rethrow;
    } catch (e) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardContext(candidates),
        reason: StatementIssueReason.downloadFailed,
      );
      ParsingLogger.error(
        'Statement Processing: Failed to download attachment for $emailId',
        e,
      );
      return EmailOutcome.failed;
    }

    final resolver = PdfPasswordResolver();
    final googleAccessToken =
        Supabase.instance.client.auth.currentSession?.providerToken ?? '';
    final emailBody = await _loadEmailBodyForPasswordHint(emailId);

    final text = await resolver.extractText(
      pdfBytes: pdfBytes,
      bankName: bankName,
      userId: _userId,
      userEmail: _userEmail,
      userName: _userName,
      googleAccessToken: googleAccessToken,
      fileName: fileName,
      emailSubject: subject,
      emailBody: emailBody,
    );

    if (text == null) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardContext(candidates),
        reason: resolver.manualAttemptsExhausted
            ? StatementIssueReason.passwordAttemptsExhausted
            : StatementIssueReason.passwordRequired,
      );
      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: false,
        bankDetected: bankName,
      );
      return EmailOutcome.needsPassword;
    }

    final statementInfo = statementInfoWithCardLastFour(
      await GeminiStatementParser.parseStatementInfo(
        pdfText: text,
        bankName: bankName,
      ),
      text,
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
      return _resolveParsedIdentityOrDiscover(
        email: email,
        candidates: candidates,
        bankName: bankName,
        statementInfo: statementInfo,
        pdfText: text,
      );
    }

    return _persistParsedStatement(
      email: email,
      userCard: matched,
      bankName: bankName,
      statementInfo: statementInfo,
      pdfText: text,
    );
  }

  Future<EmailOutcome> _resolveParsedIdentityOrDiscover({
    required Map<String, dynamic> email,
    required List<UserCard> candidates,
    required String bankName,
    required Map<String, dynamic> statementInfo,
    required String pdfText,
  }) async {
    final metadata = email['metadata'] as Map<String, dynamic>? ?? {};
    final evidence = CardIdentityEvidence.extract(
      issuer: bankName,
      subject: email['subject'] as String? ?? '',
      attachmentFilename: metadata['attachmentFilename'] as String?,
      pdfHeader: pdfText,
    );
    final catalog = await _cardsRepo.searchCatalogForBank(bankName);
    final identities = catalog
        .map((entry) {
          final aliasRows = entry['card_catalog_aliases'];
          final aliases = aliasRows is List
              ? aliasRows
                    .whereType<Map>()
                    .map((row) => row['alias'])
                    .whereType<String>()
                    .toList(growable: false)
              : const <String>[];
          return CardCatalogIdentity(
            id: entry['id'] as String,
            issuer: entry['bank'] as String? ?? bankName,
            name: entry['card_name'] as String? ?? '',
            network: entry['network'] as String?,
            aliases: aliases,
          );
        })
        .toList(growable: false);
    final catalogMatch = const CardIdentityMatcher().match(
      evidence,
      identities,
    );
    if (catalogMatch != null) {
      final freshCards = await _cardsRepo.getUserCards(_userId);
      final existing = freshCards
          .where((card) => card.catalogCardId == catalogMatch.id)
          .firstOrNull;
      final userCard =
          existing ??
          await _cardsRepo.addUserCard(
            userId: _userId,
            catalogCardId: catalogMatch.id,
            lastFourDigits: evidence.lastFour,
          );
      await _emailRepo.updateEmailMetadata(
        userId: _userId,
        emailId: email['email_id'] as String,
        metadata: metadataAfterCardAssignment(metadata),
      );
      return _persistParsedStatement(
        email: email,
        userCard: userCard,
        bankName: bankName,
        statementInfo: statementInfo,
        pdfText: pdfText,
      );
    }

    try {
      final job = await _discoveryService.discover(evidence);
      final discoveryMetadata = metadataWithCardDiscovery(
        metadata,
        jobId: job.id,
        status: job.status,
      );
      discoveryMetadata['identityHints'] = buildCardIdentityHints(
        bankName: bankName,
        statementInfo: statementInfo,
        attachmentFilename: metadata['attachmentFilename'] as String?,
      );
      email['metadata'] = discoveryMetadata;
      await _emailRepo.updateEmailMetadata(
        userId: _userId,
        emailId: email['email_id'] as String,
        metadata: discoveryMetadata,
      );
      _recordIssue(
        bankName: bankName,
        cardContext: evidence.productSignals.join(' / ').isEmpty
            ? _cardContext(candidates)
            : evidence.productSignals.join(' / '),
        reason: StatementIssueReason.cardDiscoveryPending,
      );
      return EmailOutcome.discoveryQueued;
    } catch (error) {
      ParsingLogger.error(
        'Statement Processing: Could not queue catalog discovery for ${email['email_id']}',
        error,
      );
      _recordIssue(
        bankName: bankName,
        cardContext: _cardContext(candidates),
        reason: StatementIssueReason.processingFailed,
      );
      return EmailOutcome.failed;
    }
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
      _recordIssue(
        bankName: CardNormalizerService.normalizeBankName(
          sender.isNotEmpty ? sender : subject,
        ),
        cardContext: _cardName(userCard),
        reason: StatementIssueReason.attachmentUnavailable,
      );
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
    } on GmailAuthException {
      rethrow;
    } catch (e) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardName(userCard),
        reason: StatementIssueReason.downloadFailed,
      );
      ParsingLogger.error(
        'Statement Processing: Failed to download attachment for $emailId',
        e,
      );
      return EmailOutcome.failed;
    }

    final resolver = PdfPasswordResolver();
    final googleAccessToken =
        Supabase.instance.client.auth.currentSession?.providerToken ?? '';
    final emailBody = await _loadEmailBodyForPasswordHint(emailId);

    final text = await resolver.extractText(
      pdfBytes: pdfBytes,
      bankName: bankName,
      userId: _userId,
      userEmail: _userEmail,
      userName: _userName,
      googleAccessToken: googleAccessToken,
      fileName: fileName,
      emailSubject: subject,
      emailBody: emailBody,
    );

    if (text == null) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardName(userCard),
        reason: resolver.manualAttemptsExhausted
            ? StatementIssueReason.passwordAttemptsExhausted
            : StatementIssueReason.passwordRequired,
      );
      await _emailRepo.updateEmailStatus(
        userId: _userId,
        emailId: emailId,
        processed: false,
        bankDetected: bankName,
      );
      return EmailOutcome.needsPassword;
    }

    final statementInfo = statementInfoWithCardLastFour(
      await GeminiStatementParser.parseStatementInfo(
        pdfText: text,
        bankName: bankName,
      ),
      text,
    );

    return _persistParsedStatement(
      email: email,
      userCard: userCard,
      bankName: bankName,
      statementInfo: statementInfo,
      pdfText: text,
    );
  }

  Future<String> _loadEmailBodyForPasswordHint(String emailId) async {
    try {
      return await _gmailService.loadMessageBodyText(emailId);
    } on GmailAuthException {
      rethrow;
    } catch (error) {
      ParsingLogger.warning(
        'Statement Processing: Password hint unavailable for email $emailId',
      );
      return '';
    }
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
      final receivedDate = DateTime.parse(email['received_date'] as String);
      final statementDate = parsedGeminiDate(
        statementInfo['statement_date'],
        GeminiStatementParser.extractStatementDateFromText(pdfText) ??
            receivedDate,
      );
      final dueDate = parsedGeminiDate(
        statementInfo['due_date'],
        statementDate.add(const Duration(days: 20)),
      );

      final statement = await _statementsRepo.upsertStatement(
        userId: _userId,
        cardId: catalogCardId,
        userCardId: userCardId,
        statementDate: statementDate,
        dueDate: dueDate,
        totalAmount: parsedGeminiNumber(statementInfo['total_amount']) ?? 0,
        minimumPayment:
            parsedGeminiNumber(statementInfo['minimum_payment']) ?? 0,
        closingBalance:
            parsedGeminiNumber(statementInfo['closing_balance']) ?? 0,
        availableCredit:
            parsedGeminiNumber(statementInfo['available_credit']) ?? 0,
        rewardsEarned: parsedGeminiNumber(statementInfo['rewards_earned']) ?? 0,
        transactionCount: transactions.length,
      );

      final bankMarketCurrency = currencyForBank(bankName);

      for (final txn in transactions) {
        final amount = parsedGeminiNumber(txn['amount']) ?? 0;
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
          transactionDate: parsedGeminiDate(txn['date'], statementDate),
          currency: currency,
          merchantName: rawMerchantName,
          category: categorization.category,
          transactionType: type,
          rewardEarned: parsedGeminiNumber(txn['reward_points']),
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
      final creditLimit = parsedGeminiNumber(statementInfo['credit_limit']);
      if ((last4 != null && last4.isNotEmpty) || creditLimit != null) {
        await _cardsRepo.backfillCardDetails(
          userCardId: userCardId,
          lastFourDigits: last4 != null && last4.isNotEmpty ? last4 : null,
          creditLimit: creditLimit,
        );
      }

      return EmailOutcome.succeeded;
    } catch (e) {
      _recordIssue(
        bankName: bankName,
        cardContext: _cardName(userCard),
        reason: StatementIssueReason.processingFailed,
      );
      ParsingLogger.error(
        'Statement Processing: Failed to parse/store statement for $emailId',
        e,
      );
      return EmailOutcome.failed;
    }
  }
}
