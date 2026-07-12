import 'package:cardcompass/core/services/alert_email_parser_service.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Result from a deduplication check.
enum DeduplicationDecision {
  /// No matching statement transaction found — safe to insert as a new alert txn.
  insert,

  /// A matching statement transaction already exists — skip this alert.
  skip,

  /// A matching statement transaction exists but the alert has richer data
  /// (e.g. merchant name) — update the statement txn, discard the alert.
  updateExisting,
}

class DeduplicationResult {
  final DeduplicationDecision decision;
  /// Only set when [decision] == [DeduplicationDecision.updateExisting].
  final Transaction? existingTransaction;

  const DeduplicationResult({
    required this.decision,
    this.existingTransaction,
  });
}

/// Reconciles near-real-time alert-email transactions with accurate
/// statement-parsed transactions, ensuring no double-counting.
///
/// **Matching heuristic:**
///   A statement transaction and an alert transaction are considered the
///   same if ALL of the following are true:
///     1. Amounts match within [_amountTolerancePercent]%.
///     2. Transaction dates are within [_dateTolerance] of each other.
///     3. Card last-4 digits match (when both are known).
///
/// When a statement transaction arrives later and supersedes an alert:
///   - The alert transaction is soft-deleted (marked [TransactionSource.statement]
///     and its [alertEmailId] is preserved for audit).
///   - The statement transaction's [merchant_name] is filled in from the alert
///     if the statement parser left it blank.
class TransactionDeduplicationService {
  /// Maximum amount difference (as %) to still consider two txns the same.
  /// Banks sometimes round alert amounts to the nearest rupee.
  static const double _amountTolerancePercent = 1.0;

  /// Maximum date difference to still consider two txns the same.
  static const Duration _dateTolerance = Duration(hours: 36);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Decide what to do with a freshly parsed alert transaction.
  ///
  /// [alertResult] — the parsed alert email fields.
  /// [existingTransactions] — all statement/alert transactions for the same
  ///   user+card that fall within a sensible lookback window.
  DeduplicationResult evaluate({
    required AlertEmailParseResult alertResult,
    required List<Transaction> existingTransactions,
  }) {
    if (alertResult.amount == null) {
      // Unparseable — skip silently
      return const DeduplicationResult(decision: DeduplicationDecision.skip);
    }

    for (final existing in existingTransactions) {
      if (_matches(alertResult, existing)) {
        // We already have this transaction from the statement pipeline.
        // If the statement txn is missing a merchant, we can enrich it.
        if (existing.source == TransactionSource.statement &&
            (existing.merchantName == null || existing.merchantName!.isEmpty) &&
            alertResult.merchant != null) {
          return DeduplicationResult(
            decision: DeduplicationDecision.updateExisting,
            existingTransaction: existing,
          );
        }
        return const DeduplicationResult(
            decision: DeduplicationDecision.skip);
      }
    }

    return const DeduplicationResult(decision: DeduplicationDecision.insert);
  }

  /// Build a [Transaction] from a successful [AlertEmailParseResult].
  ///
  /// Callers are responsible for supplying [userId] and [userCardId].
  Transaction buildAlertTransaction({
    required AlertEmailParseResult result,
    required String userId,
    String? userCardId,
  }) {
    assert(result.success, 'Cannot build transaction from failed parse result');
    return Transaction(
      id: 'alert_${result.alertEmailId}',
      userId: userId,
      userCardId: userCardId,
      amount: result.amount!,
      description: result.merchant ?? 'Bank transaction alert',
      merchantName: result.merchant,
      type: result.transactionType,
      category: TransactionCategory.other,
      transactionDate: result.transactionDate,
      createdAt: DateTime.now(),
      source: TransactionSource.alertEmail,
      alertEmailId: result.alertEmailId,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  bool _matches(AlertEmailParseResult alert, Transaction existing) {
    // 1. Amount check
    if (!_amountsMatch(alert.amount!, existing.amount)) return false;

    // 2. Date proximity check
    final dateDiff =
        alert.transactionDate.difference(existing.transactionDate).abs();
    if (dateDiff > _dateTolerance) return false;

    // 3. Card last-4 check (only when both known)
    if (alert.cardLastFour != null && existing.metadata['card_last_four'] != null) {
      if (alert.cardLastFour != existing.metadata['card_last_four']) {
        return false;
      }
    }

    return true;
  }

  bool _amountsMatch(double a, double b) {
    if (b == 0) return a == 0;
    final diff = ((a - b).abs() / b) * 100;
    return diff <= _amountTolerancePercent;
  }
}
