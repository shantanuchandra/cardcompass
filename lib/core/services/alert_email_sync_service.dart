import 'package:cardcompass/core/repositories/transaction_repository.dart';
import 'package:cardcompass/core/services/alert_email_gmail_service.dart';
import 'package:cardcompass/core/services/alert_email_parser_service.dart';
import 'package:cardcompass/core/services/transaction_deduplication_service.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Summary returned after an alert-email sync run.
class AlertSyncSummary {
  final int emailsFetched;
  final int emailsParsed;
  final int transactionsInserted;
  final int transactionsUpdated;
  final int transactionsSkipped;
  final List<String> errors;

  const AlertSyncSummary({
    required this.emailsFetched,
    required this.emailsParsed,
    required this.transactionsInserted,
    required this.transactionsUpdated,
    required this.transactionsSkipped,
    required this.errors,
  });

  @override
  String toString() =>
      '📧 Alert Sync: fetched=$emailsFetched parsed=$emailsParsed '
      'inserted=$transactionsInserted updated=$transactionsUpdated '
      'skipped=$transactionsSkipped errors=${errors.length}';
}

/// Orchestrates the Phase 2 "Fresher Data" pipeline:
///
///   Gmail alert emails → parse → deduplicate → upsert to DB
///
/// Call [sync] from the existing Gmail sync flow (e.g. after the PDF
/// statement pipeline finishes) to enrich the transaction feed with
/// near-real-time data.
class AlertEmailSyncService {
  final AlertEmailParserService _parser;
  final TransactionDeduplicationService _deduplication;
  final TransactionRepository _transactionRepository;

  /// Default lookback: fetch alert emails received in the last 7 days.
  static const Duration _defaultLookback = Duration(days: 7);

  AlertEmailSyncService({
    required AlertEmailParserService parser,
    required TransactionDeduplicationService deduplication,
    required TransactionRepository transactionRepository,
  })  : _parser = parser,
        _deduplication = deduplication,
        _transactionRepository = transactionRepository;

  /// Run the alert email sync for [userId].
  ///
  /// [account] — the authenticated [GoogleSignInAccount] (same one used by
  ///             [EnhancedGmailService]).
  /// [userCardId] — optional card to associate alert transactions with;
  ///               if null, card matching is done later by the rule engine.
  /// [lookback] — how far back to fetch alert emails (default 7 days).
  Future<AlertSyncSummary> sync({
    required GoogleSignInAccount account,
    required String userId,
    String? userCardId,
    Duration lookback = _defaultLookback,
  }) async {
    final errors = <String>[];
    int inserted = 0;
    int updated = 0;
    int skipped = 0;

    print('🔄 Starting alert email sync for user $userId');

    // 1. Fetch alert emails from Gmail
    final alertEmailService = AlertEmailGmailService(account);
    final since = DateTime.now().subtract(lookback);

    List<AlertEmail> alertEmails;
    try {
      alertEmails = await alertEmailService.fetchAlertEmails(since: since);
    } catch (e) {
      final msg = 'Failed to fetch alert emails: $e';
      print('❌ $msg');
      return AlertSyncSummary(
        emailsFetched: 0,
        emailsParsed: 0,
        transactionsInserted: 0,
        transactionsUpdated: 0,
        transactionsSkipped: 0,
        errors: [msg],
      );
    }

    print('📩 Fetched ${alertEmails.length} alert emails');

    // 2. Parse each email body
    final parseResults = _parser.parseAll(alertEmails);
    final successfulParses =
        parseResults.where((r) => r.success).toList();

    print('✅ Successfully parsed ${successfulParses.length}/${alertEmails.length} emails');

    // 3. Load existing transactions for deduplication (lookback window + buffer)
    List<Transaction> existingTransactions;
    try {
      existingTransactions = await _transactionRepository.getUserTransactions(
        userId,
        startDate: since.subtract(const Duration(days: 2)), // small buffer
        endDate: DateTime.now(),
        userCardId: userCardId,
      );
    } catch (e) {
      final msg = 'Failed to load existing transactions: $e';
      print('❌ $msg');
      errors.add(msg);
      existingTransactions = [];
    }

    // 4. Deduplicate and upsert
    for (final result in successfulParses) {
      try {
        final decision = _deduplication.evaluate(
          alertResult: result,
          existingTransactions: existingTransactions,
        );

        switch (decision.decision) {
          case DeduplicationDecision.insert:
            final txn = _deduplication.buildAlertTransaction(
              result: result,
              userId: userId,
              userCardId: userCardId,
            );
            await _transactionRepository.addTransaction(txn);
            existingTransactions.add(txn); // prevent self-dedupe in this batch
            inserted++;
            print('➕ Inserted alert txn: ${result.merchant} ₹${result.amount}');
            break;

          case DeduplicationDecision.updateExisting:
            final enriched = decision.existingTransaction!.copyWith(
              merchantName: result.merchant,
              alertEmailId: result.alertEmailId,
            );
            await _transactionRepository.updateTransaction(enriched);
            updated++;
            print(
                '✏️  Enriched statement txn with merchant: ${result.merchant}');
            break;

          case DeduplicationDecision.skip:
            skipped++;
            break;
        }
      } catch (e) {
        final msg =
            'Error processing alert ${result.alertEmailId}: $e';
        print('❌ $msg');
        errors.add(msg);
      }
    }

    final summary = AlertSyncSummary(
      emailsFetched: alertEmails.length,
      emailsParsed: successfulParses.length,
      transactionsInserted: inserted,
      transactionsUpdated: updated,
      transactionsSkipped: skipped,
      errors: errors,
    );
    print(summary);
    return summary;
  }
}
