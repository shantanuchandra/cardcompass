import 'transaction_categorizer.dart';
import '../repositories/transactions_repository.dart';

/// Re-categorization decision for one existing transaction, given its
/// already-stored merchant name/description — no re-parsing of the
/// original statement needed. Pure function, reuses the same categorizer
/// tiers a fresh transaction goes through, minus the Gemini-provided
/// category tier: a backfilled row's original `category` value is exactly
/// what's being replaced (it's invalid/NULL/'other'), so there's nothing
/// useful to validate there.
CategorizationResult recategorize({
  required String merchantName,
  required String description,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  return categorize(
    merchantName: merchantName,
    description: description,
    geminiCategory: null,
    merchantLookup: merchantLookup,
  );
}

/// Result of one backfill run.
class BackfillResult {
  final int examined;
  final int recategorized;
  const BackfillResult({required this.examined, required this.recategorized});

  @override
  String toString() => 'BackfillResult(examined: $examined, recategorized: $recategorized)';
}

/// One-time job: re-categorizes every transaction whose category needs
/// backfilling (NULL, 'other', or a legacy/invalid value — see
/// `TransactionsRepository.getUncategorizedTransactions`) for [userId],
/// using their already-stored merchant_name/description.
///
/// MUST be run via a privileged Supabase client (service role), not a
/// regular per-user client — normal RLS scopes every read/write to the
/// signed-in user. This class itself doesn't enforce that — it takes
/// whatever TransactionsRepository it's given — but the repository MUST
/// be constructed with a service-role SupabaseClient when this is
/// actually run against production data across all users.
///
/// Idempotent: re-running for the same user after a successful pass
/// examines zero rows the second time, since the selection query only
/// matches rows that still need fixing.
///
/// CRITICAL — metadata merge, not replace: `updateTransactionCategory`
/// replaces the entire `metadata` JSONB column rather than merging keys
/// (verified in a prior code review of the repository method). This
/// method MUST read-merge-write: spread the transaction's EXISTING
/// metadata before adding/overwriting `category_source`, or any other
/// metadata this transaction already carries (e.g. MCC-related fields
/// from a separate concurrent feature) will be silently destroyed.
class CategoryBackfillService {
  final TransactionsRepository _repo;

  CategoryBackfillService(this._repo);

  Future<BackfillResult> run(String userId) async {
    final transactions = await _repo.getUncategorizedTransactions(userId);
    var recategorized = 0;

    for (final txn in transactions) {
      final merchantName = txn.merchantName ?? txn.description;
      final normalized = merchantName.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      final mapped = await _repo.lookupMerchantCategory(normalized);

      final result = recategorize(
        merchantName: merchantName,
        description: txn.description,
        merchantLookup: (_) => mapped,
      );

      if (result.category != txn.category) {
        await _repo.updateTransactionCategory(
          transactionId: txn.id,
          category: result.category,
          // Read-merge-write: preserve every existing metadata key (e.g.
          // any MCC-related fields another feature may have written),
          // only adding/overwriting category_source.
          metadata: {...txn.metadata, 'category_source': result.source.name},
        );
        recategorized++;
      }
    }

    return BackfillResult(examined: transactions.length, recategorized: recategorized);
  }
}
