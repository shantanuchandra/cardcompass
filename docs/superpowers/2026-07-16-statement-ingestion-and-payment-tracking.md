# Statement Ingestion & Payment Tracking — Design Spec & Implementation Plan

## Design Specification

# Statement Ingestion and Payment Tracking Design

## Goal

Make statement dates trustworthy for card-cycle calculations, show the current
bill for every owned card, and retain an auditable record when a statement is
paid in full or in part.

## Data model

Extend the existing `public.statements` table. Do not create a parallel payment
table for the initial full/partial payment workflow.

- `paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0`: total amount applied to this
  statement.
- `paid_at TIMESTAMPTZ NULL`: timestamp of the most recent applied payment.
- Existing `payment_status` remains the lifecycle field: `pending`, `partial`,
  `paid`, or `overdue`.

The migration will add a check constraint that prevents negative paid amounts
and prevents a paid amount greater than `total_amount`. It will add an index
for locating a card's latest statement and its oldest unpaid statement.

## Ingestion and cycle dates

`GeminiTransactionParser.parseStatementInfo` already extracts `statement_date`
and `due_date` from PDF text. The Gmail ingestion result will use the parsed
statement date when it is a valid date. It will retain the email received date
only as a fallback if PDF extraction cannot provide a date.

Statement metadata will record `statement_date_source` as either `pdf` or
`email_fallback`, so benefit-cycle logic can distinguish verified dates from a
fallback. The parsed due date remains preferred; the existing default due-date
fallback remains only when the document omits it.

The actual benefit cycle is determined from consecutive statement dates for the
same `user_card_id`. It is not inferred from a fixed 30-day period when a prior
statement exists.

## Payment reconciliation

The parser will extract a statement-level `payments_received` total when the
PDF provides one. During ingestion, that amount is applied to prior open
statements for the same `user_card_id`, oldest due first.

- A payment less than the outstanding amount updates `paid_amount`, `paid_at`,
  and sets the statement to `partial`.
- A payment that clears the outstanding amount sets `payment_status` to `paid`.
- If one payment clears more than one prior statement, the remainder is applied
  to the next oldest open statement.
- Any remaining unmatched credit is retained in the current statement metadata
  as `unmatched_payment_credit`; it does not silently mark a statement paid.
- Re-ingesting the same statement must not apply its payment credit twice.

The user-facing “Mark paid” action applies the remaining outstanding amount to
that exact latest unpaid statement, sets `paid_at` to the action time, and
never alters a different card’s statement.

## Portfolio UI

The Show All Credit Cards page will load each card's latest statement by
`user_card_id` and render a compact bill panel below the existing card summary:

- total amount due;
- due date;
- payment status;
- a `Mark paid` action only when an amount remains outstanding.

The action requires confirmation and refreshes only after the database update
succeeds. Paid statements show their paid amount and timestamp instead of an
action. Cards with no statement show an explicit empty state, not invented
amounts or dates.

## Error handling

- Invalid or absent PDF dates never overwrite a valid stored statement date.
- A failed payment update leaves the UI unchanged and displays an error.
- The reconciliation is idempotent per source statement, protecting resyncs.
- RLS and ownership checks ensure statements can only be read or updated by
  their owner.

## Tests

Tests will be added before implementation and will cover:

1. parsed PDF statement date takes precedence over email date;
2. email date is explicitly marked as fallback only when PDF date is absent;
3. payment credits fully and partially reconcile prior statements, in oldest
   first order, without cross-card effects or duplicate application;
4. manual mark-paid records the exact remaining amount and timestamp;
5. latest-statement card summaries expose due date, total due, status, and
   empty-state behavior;
6. existing statement, sync, and movie-rule test suites continue to pass.


---

## Implementation Plan

# Statement Ingestion and Payment Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist PDF statement dates, reconcile PDF payment credits, and let users view and pay each card's latest bill.

**Architecture:** Existing `statements` rows own payment state. The parser provides statement facts, a reconciliation service allocates payment credits to older open rows for the same owned card, and the portfolio page reads one latest-statement summary per card.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase/Postgres, flutter_test.

## Global Constraints

- Extend `statements`; do not create a parallel payment table.
- Scope every operation by `user_id` and `user_card_id`.
- PDF statement dates take precedence over email dates.
- Re-sync is idempotent: one source statement credit is never applied twice.
- Preserve the existing uncommitted debug-service changes.

---

### Task 1: Add statement payment audit fields

**Files:**

- Create: `supabase/migrations/20260716090000_statement_payment_tracking.sql`
- Modify: `lib/shared/models/statement.dart`
- Create: `test/statement_payment_model_test.dart`
- Modify: `test/statement_schema_fix_test.dart`

**Interfaces:** Produces `Statement.paidAmount`, `Statement.paidAt`, `Statement.remainingAmount`, plus `statements.paid_amount` and `statements.paid_at`.

- [ ] **Step 1: Write the failing test**

```dart
test('maps paid amount and derives amount still due', () {
  final statement = Statement.fromJson({'id': 'statement-1', 'user_id': 'user-1',
    'user_card_id': 'card-1', 'statement_date': '2026-07-01T00:00:00.000Z',
    'due_date': '2026-07-21T00:00:00.000Z', 'minimum_payment': 0,
    'closing_balance': 0, 'available_credit': 0, 'rewards_earned': 0,
    'interest_charged': 0, 'fees_charged': 0, 'file_path': '', 'file_name': '',
    'created_at': '2026-07-01T00:00:00.000Z',
    'total_amount': 1000, 'paid_amount': 250,
    'paid_at': '2026-07-16T10:00:00.000Z', 'payment_status': 'partial'});
  expect(statement.remainingAmount, 750);
  expect(statement.paidAt, DateTime.parse('2026-07-16T10:00:00.000Z'));
});
```

Add a migration-content test requiring `paid_amount`, `paid_at`, a bounds check `0 <= paid_amount <= total_amount`, and a `(user_card_id, payment_status, due_date)` index.

- [ ] **Step 2: Verify the test fails**

Run: `flutter test test/statement_payment_model_test.dart test/statement_schema_fix_test.dart`

Expected: FAIL because the fields and migration do not exist.

- [ ] **Step 3: Implement the smallest schema/model change**

```sql
ALTER TABLE public.statements
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE public.statements ADD CONSTRAINT statements_paid_amount_bounds_check
  CHECK (paid_amount >= 0 AND paid_amount <= total_amount);
CREATE INDEX statements_user_card_open_due_idx
  ON public.statements (user_card_id, payment_status, due_date);
```

Map the fields in `Statement.fromJson`, `toJson`, and `copyWith`; return `max(0, totalAmount - paidAmount)` from `remainingAmount`.

- [ ] **Step 4: Verify green and commit**

Run: `flutter test test/statement_payment_model_test.dart test/statement_schema_fix_test.dart`

Expected: PASS.

```bash
git add supabase/migrations/20260716090000_statement_payment_tracking.sql lib/shared/models/statement.dart test/statement_payment_model_test.dart test/statement_schema_fix_test.dart
git commit -m "feat: track statement payment amounts"
```

### Task 2: Ingest verified PDF dates and payment credits

**Files:**

- Modify: `lib/core/services/gemini_transaction_parser.dart`
- Modify: `lib/core/services/enhanced_gmail_service.dart`
- Modify: `lib/core/services/data_pipeline_debug_service.dart`
- Create: `test/gemini_statement_info_test.dart`
- Modify: `test/data_pipeline_debug_service_test.dart`

**Interfaces:** Produces `StatementParsingResult.statementDateSource` (`pdf`/`email_fallback`) and `paymentsReceived` (`double?`).

- [ ] **Step 1: Write failing parser/result tests**

```dart
test('uses the PDF statement date over the email received date', () {
  final result = StatementParsingResult.fromParsedInfo(
    emailDate: DateTime(2026, 7, 15),
    statementInfo: {'statement_date': '2026-07-10T00:00:00.000Z'}, base: base);
  expect(result.statementDate, DateTime(2026, 7, 10));
  expect(result.statementDateSource, 'pdf');
});
```

Add a parser fixture containing `Payments Received: ₹1,250.00` and expect `payments_received == 1250.0`.

- [ ] **Step 2: Verify red**

Run: `flutter test test/gemini_statement_info_test.dart test/data_pipeline_debug_service_test.dart`

Expected: FAIL because the parsed facts are discarded.

- [ ] **Step 3: Implement explicit parsed facts**

Add `payments_received` to the Gemini JSON contract and fallback extraction. Introduce `StatementParsingResult.fromParsedInfo`, using `DateTime.tryParse(statement_date) ?? emailDate` and recording `pdf` or `email_fallback`. Store source, received amount, and initial reconciliation state in statement metadata.

- [ ] **Step 4: Verify green and commit**

Run: `flutter test test/gemini_statement_info_test.dart test/data_pipeline_debug_service_test.dart`

Expected: PASS.

```bash
git add lib/core/services/gemini_transaction_parser.dart lib/core/services/enhanced_gmail_service.dart lib/core/services/data_pipeline_debug_service.dart test/gemini_statement_info_test.dart test/data_pipeline_debug_service_test.dart
git commit -m "fix: preserve PDF statement dates during ingestion"
```

### Task 3: Reconcile imported payment credits

**Files:**

- Create: `lib/core/services/statement_payment_reconciliation_service.dart`
- Modify: `lib/core/repositories/statement_repository.dart`
- Modify: `lib/core/repositories/supabase_statement_repository.dart`
- Modify: `lib/core/services/data_pipeline_debug_service.dart`
- Create: `test/core/services/statement_payment_reconciliation_service_test.dart`
- Modify: `test/supabase_statement_repository_test.dart`

**Interfaces:** Produces `reconcileImportedPayment({sourceStatementId, userId, userCardId, paymentCredit})` and repository operations `getOpenStatementsForCard`, `applyPaymentToStatement`, and `markStatementPaid`.

- [ ] **Step 1: Write failing service tests**

```dart
test('applies imported credit to the oldest open statement for the same card', () async {
  await service.reconcileImportedPayment(
    sourceStatementId: 'july', userId: 'user', userCardId: 'card-a', paymentCredit: 750);
  expect(repo.updates.single, PaymentUpdate('may', 750, PaymentStatus.partial));
});
test('does not apply the same source statement twice', () async {
  const request = ReconciliationRequest(
    sourceStatementId: 'july', userId: 'user', userCardId: 'card-a', paymentCredit: 750);
  await service.reconcileImportedPayment(request);
  await service.reconcileImportedPayment(request);
  expect(repo.updates, hasLength(1));
});
```

Cover a payment clearing two statements, a partial payment, cross-card isolation, and unmatched remainder.

- [ ] **Step 2: Verify red**

Run: `flutter test test/core/services/statement_payment_reconciliation_service_test.dart`

Expected: FAIL because the service/repository API does not exist.

- [ ] **Step 3: Implement reconciliation and manual payment update**

Fetch only `pending`, `partial`, and `overdue` statements for one `user_card_id`, ordered by due date. Allocate `min(remainingAmount, remainingCredit)` oldest first; set `partial` or `paid`, amount, and timestamp. In one RPC transaction, first mark source metadata `payment_reconciliation_state=applied`, then apply target changes; store any residual in `unmatched_payment_credit`. A repeat sees the applied marker and performs no writes. `markStatementPaid` applies exactly `remainingAmount` to the chosen user-owned statement.

- [ ] **Step 4: Verify green and commit**

Run: `flutter test test/core/services/statement_payment_reconciliation_service_test.dart test/supabase_statement_repository_test.dart`

Expected: PASS.

```bash
git add lib/core/services/statement_payment_reconciliation_service.dart lib/core/repositories/statement_repository.dart lib/core/repositories/supabase_statement_repository.dart lib/core/services/data_pipeline_debug_service.dart test/core/services/statement_payment_reconciliation_service_test.dart test/supabase_statement_repository_test.dart
git commit -m "feat: reconcile statement payment credits"
```

### Task 4: Show and pay the latest statement on each card

**Files:**

- Create: `lib/features/cards/models/card_statement_summary.dart`
- Modify: `lib/features/cards/providers/cards_provider.dart`
- Modify: `lib/features/cards/presentation/screens/cards_list_screen.dart`
- Create: `test/features/cards/card_statement_summary_test.dart`
- Create: `test/features/cards/cards_provider_test.dart`
- Create: `test/features/cards/cards_list_payment_action_test.dart`

**Interfaces:** Produces `CardStatementSummary` and `cardStatementSummariesProvider`, keyed by owned `CreditCard.id`.

- [ ] **Step 1: Write failing summary/provider/widget tests**

```dart
test('selects the latest statement per owned card', () {
  final summaries = buildCardStatementSummaries([oldStatement, latestStatement]);
  expect(summaries['card-a']!.dueDate, DateTime(2026, 7, 25));
  expect(summaries['card-a']!.remainingAmount, 900);
});
testWidgets('marks only the selected card statement paid after confirmation', (tester) async {
  await tester.pumpWidget(buildPortfolioWith(summary: unpaidSummary));
  await tester.tap(find.text('MARK PAID'));
  await tester.tap(find.text('CONFIRM PAYMENT'));
  expect(fakeRepository.markPaidCalls.single.statementId, unpaidSummary.statementId);
});
```

Include card-with-no-statement, cancel, paid-summary, and repository failure cases.

- [ ] **Step 2: Verify red**

Run: `flutter test test/features/cards/card_statement_summary_test.dart test/features/cards/cards_provider_test.dart test/features/cards/cards_list_payment_action_test.dart`

Expected: FAIL because no summary provider or action exists.

- [ ] **Step 3: Implement portfolio bill panel and action**

Use a pure helper to choose max `statementDate` per `userCardId`. The provider loads statements for the signed-in user. Render amount due, due date, and payment status under each existing card summary, or `No statement available`. Render `MARK PAID` only where `remainingAmount > 0`; require a dialog naming the card and amount. On confirmation, call `markStatementPaid`, refresh the provider, and show an error SnackBar without changing UI on failure. Paid rows show paid amount/date.

- [ ] **Step 4: Verify green, full suite, analysis, and commit**

Run: `flutter test test/features/cards/card_statement_summary_test.dart test/features/cards/cards_provider_test.dart test/features/cards/cards_list_payment_action_test.dart && flutter test && flutter analyze`

Expected: all runnable tests PASS and `No issues found!`; report any intentional environment-bound skips separately.

```bash
git add lib/features/cards/models/card_statement_summary.dart lib/features/cards/providers/cards_provider.dart lib/features/cards/presentation/screens/cards_list_screen.dart test/features/cards/card_statement_summary_test.dart test/features/cards/cards_provider_test.dart test/features/cards/cards_list_payment_action_test.dart
git commit -m "feat: show and pay portfolio card bills"
```
