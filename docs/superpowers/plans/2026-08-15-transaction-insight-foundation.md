# Transaction Insight Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Make v2 transactions safe to aggregate by separating retail spend from other ledger movements, adding hybrid MCC context, and producing the seven deterministic spend summaries required by recommendations.

**Architecture:** Extend the working statement-ingestion path. Pure Dart services own transaction-type normalization, eligible-spend decisions, MCC precedence, and insight aggregation; repositories own Supabase I/O, and Riverpod exposes a selected period whose initial value is 60 days.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase/Postgres, flutter_test.

**Spec:** docs/source-of-truth/00-cardcompass-source-of-truth-index.md, docs/source-of-truth/03-transaction-normalization-merchant-and-mcc.md, docs/source-of-truth/04-spend-insights.md

## Global Constraints

- Work in /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2 on feature/landing-v2.
- Preserve unrelated edits and re-read dirty files before changing them.
- Finish applicable remaining tasks in docs/superpowers/plans/2026-08-16-transaction-categorization.md before Task 2.
- Keep the approved 16-category vocabulary unchanged.
- Dashboard insights default to 60 days. The next plan owns the 90-day recommendation window.
- Do not add authentication, privacy, retention, audit, or password-storage systems.
- Unknown merchant/category/MCC values do not block ingestion.
- Inferred MCC never overwrites issuer-confirmed MCC.
- Run each new test and observe failure before implementation.

---

## File Structure

| File | Responsibility |
|---|---|
| lib/core/services/transaction_type_normalizer.dart | Normalize parser output into ledger types. |
| lib/core/services/eligible_spend.dart | Define which transactions contribute to spend. |
| lib/core/services/mcc_resolver.dart | Resolve MCC candidates by authority. |
| lib/features/insights/domain/spend_insight.dart | Typed insight results. |
| lib/core/services/spend_insight_aggregator.dart | Aggregate seven insight families. |
| lib/features/insights/providers/spend_insights_provider.dart | Load selected-period insights. |

### Task 1: Verify the categorization prerequisite

**Files:**
- Read: docs/superpowers/plans/2026-08-16-transaction-categorization.md
- Read: lib/core/services/transaction_categorizer.dart
- Read: lib/core/repositories/transactions_repository.dart
- Read: lib/core/services/statement_processing_service.dart
- Test: existing categorization tests

**Interfaces:**
- Consumes: August 16 categorization plan.
- Produces: ingestion persisting fixed category, resolved currency, and category provenance.

- [ ] **Step 1: Compare commits with the prerequisite plan**

Run:

~~~bash
git log --oneline --all -- lib/core/services/transaction_categorizer.dart \
  lib/core/repositories/transactions_repository.dart \
  lib/core/services/statement_processing_service.dart supabase/migrations
~~~

Expected: seed, bank-market, categorizer, and prompt commits are visible. List any remaining Tasks 5-12.

- [ ] **Step 2: Run current categorization tests**

~~~bash
flutter test test/core/services/merchant_category_seed_test.dart \
  test/core/services/bank_market_test.dart \
  test/core/services/transaction_categorizer_test.dart \
  test/core/services/gemini_statement_parser_prompt_test.dart
~~~

Expected: PASS.

- [ ] **Step 3: Confirm production wiring**

~~~bash
rg -n "TransactionCategorizer|category_source|currencyForBank" \
  lib/core/repositories/transactions_repository.dart \
  lib/core/services/statement_processing_service.dart
~~~

Expected: all concepts occur on the persistence path. If absent, execute the relevant prerequisite-plan task with its tests and commit.

### Task 2: Normalize transaction types and eligible spend

**Files:**
- Create: lib/core/services/transaction_type_normalizer.dart
- Create: lib/core/services/eligible_spend.dart
- Modify: lib/core/services/gemini_statement_parser.dart
- Modify: lib/core/services/statement_processing_service.dart
- Modify: lib/features/transactions/providers/transactions_provider.dart
- Modify: lib/features/dashboard/providers/dashboard_provider.dart
- Test: test/core/services/transaction_type_normalizer_test.dart
- Test: test/core/services/eligible_spend_test.dart
- Test: test/features/transactions/transactions_state_test.dart

**Interfaces:**
- Produces: TransactionTypeNormalizer.normalize({String? parserType, required String description}) returning a canonical string.
- Produces: bool isEligibleRetailSpend(Transaction transaction).

- [ ] **Step 1: Write failing normalizer tests**

~~~dart
test('description corrects an underspecified debit', () {
  expect(TransactionTypeNormalizer.normalize(
    parserType: 'debit', description: 'FINANCE CHARGES / INTEREST'), 'interest');
  expect(TransactionTypeNormalizer.normalize(
    parserType: 'debit', description: 'ATM CASH WITHDRAWAL'), 'cash_withdrawal');
});

test('canonical parser types pass through', () {
  for (final type in const [
    'debit', 'credit', 'refund', 'fee', 'interest', 'reward', 'cash_withdrawal'
  ]) {
    expect(TransactionTypeNormalizer.normalize(parserType: type, description: ''), type);
  }
});
~~~

- [ ] **Step 2: Write failing eligible-spend tests**

Build Transaction fixtures and assert a purchase debit is eligible while credit, refund, fee, interest, reward, and a debit with normalized_transaction_type=cash_withdrawal are not.

- [ ] **Step 3: Run and observe failure**

~~~bash
flutter test test/core/services/transaction_type_normalizer_test.dart \
  test/core/services/eligible_spend_test.dart
~~~

Expected: FAIL because both services are missing.

- [ ] **Step 4: Implement the normalizer**

~~~dart
abstract final class TransactionTypeNormalizer {
  static const canonical = {
    'debit', 'credit', 'refund', 'fee', 'interest', 'reward', 'cash_withdrawal'
  };

  static String normalize({String? parserType, required String description}) {
    final raw = parserType?.trim().toLowerCase().replaceAll(' ', '_');
    final text = description.toLowerCase();
    if (RegExp(r'\b(refund|reversal|reversed)\b').hasMatch(text)) return 'refund';
    if (RegExp(r'\b(interest|finance charge)\b').hasMatch(text)) return 'interest';
    if (RegExp(r'\b(annual fee|late fee|processing fee|fee charged)\b').hasMatch(text)) return 'fee';
    if (RegExp(r'\b(atm|cash withdrawal)\b').hasMatch(text)) return 'cash_withdrawal';
    if (RegExp(r'\b(reward|cashback credit|points credit)\b').hasMatch(text)) return 'reward';
    return raw != null && canonical.contains(raw) ? raw : 'debit';
  }
}
~~~

- [ ] **Step 5: Implement the spend predicate**

~~~dart
bool isEligibleRetailSpend(Transaction transaction) {
  if (!transaction.isDebit) return false;
  return transaction.metadata['normalized_transaction_type'] != 'cash_withdrawal';
}
~~~

- [ ] **Step 6: Expand and wire parser types**

Change the Gemini type contract to debit|credit|refund|fee|interest|reward|cash_withdrawal. Normalize immediately before addTransaction. Preserve cash_withdrawal in metadata until the database model gains that enum value.

- [ ] **Step 7: Replace aggregations and set 60 days**

Use isEligibleRetailSpend in TxnsState.totalSpend, topCategory, spendTrend, and dashboardProvider. Change the dashboard query start to:

~~~dart
final insightWindowStart = now.subtract(const Duration(days: 60));
~~~

Write transactions_state_test.dart with a purchase, fee, refund, and withdrawal; only the purchase contributes.

- [ ] **Step 8: Verify and commit**

~~~bash
flutter test test/core/services/transaction_type_normalizer_test.dart \
  test/core/services/eligible_spend_test.dart \
  test/features/transactions/transactions_state_test.dart \
  test/core/services/gemini_statement_parser_prompt_test.dart
git add lib/core/services/transaction_type_normalizer.dart \
  lib/core/services/eligible_spend.dart \
  lib/core/services/gemini_statement_parser.dart \
  lib/core/services/statement_processing_service.dart \
  lib/features/transactions/providers/transactions_provider.dart \
  lib/features/dashboard/providers/dashboard_provider.dart \
  test/core/services/transaction_type_normalizer_test.dart \
  test/core/services/eligible_spend_test.dart \
  test/features/transactions/transactions_state_test.dart \
  test/core/services/gemini_statement_parser_prompt_test.dart
git commit -m "feat: distinguish eligible retail spend"
~~~

Expected: tests PASS before commit.

### Task 3: Add hybrid MCC persistence and precedence

**Files:**
- Create: supabase/migrations/20260817000000_transaction_mcc_enrichment.sql
- Create: lib/core/services/mcc_resolver.dart
- Modify: lib/shared/models/transaction.dart
- Modify: lib/core/repositories/transactions_repository.dart
- Test: test/core/services/mcc_resolver_test.dart
- Test: test/supabase/transaction_mcc_contract_test.dart

**Interfaces:**
- Produces: MccCandidate? resolveMcc with bankStatement, verifiedProvider, merchantRegistry, and inferred candidates.

- [ ] **Step 1: Write and run the failing precedence test**

~~~dart
test('issuer MCC outranks inferred MCC', () {
  final result = resolveMcc(
    bankStatement: const MccCandidate(
      code: '5541', source: MccSource.bankStatement, confidence: 1),
    inferred: const MccCandidate(
      code: '5812', source: MccSource.inferred, confidence: .65),
  );
  expect(result!.code, '5541');
  expect(result.source, MccSource.bankStatement);
});
~~~

Run: flutter test test/core/services/mcc_resolver_test.dart

Expected: FAIL because MCC types do not exist.

- [ ] **Step 2: Create the migration**

~~~sql
alter table public.transactions
  add column if not exists mcc_code text,
  add column if not exists mcc_description text,
  add column if not exists mcc_source text,
  add column if not exists mcc_confidence numeric(4,3),
  add column if not exists mcc_verified_at timestamptz;

alter table public.transactions add constraint transactions_mcc_source_check
  check (mcc_source is null or mcc_source in
    ('bank_statement','verified_provider','merchant_registry','inferred','unknown'));
alter table public.transactions add constraint transactions_mcc_confidence_check
  check (mcc_confidence is null or mcc_confidence between 0 and 1);
~~~

The contract test requires every field, constraint, and source value.

- [ ] **Step 3: Implement MCC types and precedence**

~~~dart
enum MccSource { bankStatement, verifiedProvider, merchantRegistry, inferred, unknown }
class MccCandidate {
  const MccCandidate({required this.code, required this.source,
    required this.confidence, this.description, this.verifiedAt});
  final String code;
  final String? description;
  final MccSource source;
  final double confidence;
  final DateTime? verifiedAt;
}
MccCandidate? resolveMcc({MccCandidate? bankStatement,
  MccCandidate? verifiedProvider, MccCandidate? merchantRegistry,
  MccCandidate? inferred}) =>
    bankStatement ?? verifiedProvider ?? merchantRegistry ?? inferred;
~~~

- [ ] **Step 4: Map model/repository fields**

Add nullable MCC fields to Transaction.fromJson. Add optional MccCandidate mcc to addTransaction and write all values. Never replace stored source bank_statement with a weaker candidate.

- [ ] **Step 5: Verify and commit**

~~~bash
flutter test test/core/services/mcc_resolver_test.dart \
  test/supabase/transaction_mcc_contract_test.dart
git add supabase/migrations/20260817000000_transaction_mcc_enrichment.sql \
  lib/core/services/mcc_resolver.dart lib/shared/models/transaction.dart \
  lib/core/repositories/transactions_repository.dart \
  test/core/services/mcc_resolver_test.dart \
  test/supabase/transaction_mcc_contract_test.dart
git commit -m "feat: add hybrid transaction MCC data"
~~~

Expected: tests PASS before commit.

### Task 4: Define and aggregate seven insight families

**Files:**
- Create: lib/features/insights/domain/spend_insight.dart
- Create: lib/core/services/spend_insight_aggregator.dart
- Test: test/features/insights/spend_insight_test.dart
- Test: test/core/services/spend_insight_aggregator_test.dart

**Interfaces:**
- Produces: SpendInsightKind with category, merchant, movie, travel, ecommerce, foodGrocery, fuel.
- Produces: buildSpendInsights({transactions, periodStart, periodEnd}).

- [ ] **Step 1: Write failing model and fixture tests**

~~~dart
final insight = SpendInsight(
  kind: SpendInsightKind.category,
  key: const SpendInsightKey(value: 'grocery', label: 'Grocery'),
  periodStart: DateTime(2026, 6, 16), periodEnd: DateTime(2026, 8, 15),
  amount: 12000, totalEligibleSpend: 30000, transactionCount: 8,
  unresolvedAmount: 1500,
);
expect(insight.shareOfEligibleSpend, .4);
expect(insight.unresolvedShare, .05);
~~~

Create eligible fixtures for Swiggy, BigBasket, Amazon/online, IndiGo, IndianOil, and BookMyShow/movie, plus a fee. Assert all seven kinds occur and the fee affects no amount.

- [ ] **Step 2: Run and observe failure**

~~~bash
flutter test test/features/insights/spend_insight_test.dart \
  test/core/services/spend_insight_aggregator_test.dart
~~~

Expected: FAIL because models and aggregator are missing.

- [ ] **Step 3: Implement result models**

~~~dart
enum SpendInsightKind { category, merchant, movie, travel, ecommerce, foodGrocery, fuel }
class SpendInsightKey {
  const SpendInsightKey({required this.value, required this.label, this.subtype});
  final String value; final String label; final String? subtype;
}
class SpendInsight {
  const SpendInsight({required this.kind, required this.key,
    required this.periodStart, required this.periodEnd, required this.amount,
    required this.totalEligibleSpend, required this.transactionCount,
    this.unresolvedAmount = 0});
  final SpendInsightKind kind; final SpendInsightKey key;
  final DateTime periodStart; final DateTime periodEnd;
  final double amount; final double totalEligibleSpend;
  final int transactionCount; final double unresolvedAmount;
  double get shareOfEligibleSpend => totalEligibleSpend == 0 ? 0 : amount / totalEligibleSpend;
  double get unresolvedShare => totalEligibleSpend == 0 ? 0 : unresolvedAmount / totalEligibleSpend;
}
~~~

- [ ] **Step 4: Implement deterministic aggregation**

Filter by period and isEligibleRetailSpend. Group category and merchant. Specialized filters are: movie=entertainment plus platform/movie subtype; travel=travel; ecommerce=channel online; foodGrocery=food or grocery; fuel=fuel. Pick the leading group by amount, transaction count, then normalized key alphabetically. Omit empty families.

- [ ] **Step 5: Verify and commit**

~~~bash
flutter test test/features/insights/spend_insight_test.dart \
  test/core/services/spend_insight_aggregator_test.dart
git add lib/features/insights/domain/spend_insight.dart \
  lib/core/services/spend_insight_aggregator.dart \
  test/features/insights/spend_insight_test.dart \
  test/core/services/spend_insight_aggregator_test.dart
git commit -m "feat: aggregate seven spend insight families"
~~~

Expected: empty/tie fixtures and all seven families PASS.

### Task 5: Expose selected-period insights

**Files:**
- Create: lib/features/insights/providers/spend_insights_provider.dart
- Test: test/features/insights/spend_insights_provider_test.dart

**Interfaces:**
- Produces: InsightPeriod.initial(DateTime now).
- Produces: spendInsightsProvider with setPeriod and reload.

- [ ] **Step 1: Write failing period/provider tests**

~~~dart
final now = DateTime(2026, 8, 15, 12);
final period = InsightPeriod.initial(now);
expect(period.end, now);
expect(period.start, now.subtract(const Duration(days: 60)));
~~~

Use a fake transaction reader and assert the provider requests selected from/to dates and returns aggregator output.

- [ ] **Step 2: Run and observe failure**

Run: flutter test test/features/insights/spend_insights_provider_test.dart

Expected: FAIL because types are missing.

- [ ] **Step 3: Implement period/provider**

~~~dart
class InsightPeriod {
  const InsightPeriod(this.start, this.end);
  final DateTime start; final DateTime end;
  factory InsightPeriod.initial(DateTime now) =>
    InsightPeriod(now.subtract(const Duration(days: 60)), now);
}
~~~

The provider loads up to 2,000 transactions, calls buildSpendInsights, and exposes setPeriod.

- [ ] **Step 4: Verify and commit**

~~~bash
flutter test test/features/insights/spend_insights_provider_test.dart \
  test/core/services/spend_insight_aggregator_test.dart
git add lib/features/insights/providers/spend_insights_provider.dart \
  test/features/insights/spend_insights_provider_test.dart
git commit -m "feat: provide selected-period spend insights"
~~~

Expected: PASS.

### Task 6: Foundation verification gate

**Files:** No production files unless a defect is found.

**Interfaces:** Produces a verified foundation for the separate recommendation-engine plan.

- [ ] **Step 1: Run relevant tests**

~~~bash
flutter test test/core/services test/features/insights \
  test/features/transactions test/features/benefits/movie_deals
~~~

Expected: zero failures.

- [ ] **Step 2: Run analysis**

Run: flutter analyze

Expected: no new errors.

- [ ] **Step 3: Verify migrations**

~~~bash
supabase db reset
flutter test test/supabase/merchant_category_map_permissions_test.dart \
  test/supabase/transaction_mcc_contract_test.dart
~~~

Expected: reset and tests pass. If local Supabase is unavailable, report that exact gap.

- [ ] **Step 4: Manually process one statement**

Confirm canonical categories, excluded non-spend rows, 60-day default, MCC source/confidence when available, and specialized insights only when matching spend exists.

## Plan Self-Review

- The plan stops before benefit evaluation/ranking because that is an independent subsystem requiring its own plan.
- Gmail/PDF and Movie Deals are reused.
- The August 16 categorization plan remains authoritative for unfinished category/currency/backfill work.
- Every new behavior has a failing-test step, verification, and commit boundary.
- No placeholders remain.
