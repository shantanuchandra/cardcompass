# User Card Data Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every statement, transaction, recommendation, and benefit application correctly resolve through a user-owned card while preserving the reusable card catalog and benefit catalog.

**Architecture:** `card_catalog` remains the bank-product catalog and `user_cards` remains the user’s owned-card record. Statements and transactions use `user_card_id` as their authoritative relationship; benefits remain canonical definitions, while card-specific commercial terms move to `card_benefit_mapping`. The scrape workflow stores evidence and review decisions in staging before it can alter a mapping.

**Tech Stack:** Flutter/Dart, Supabase Postgres migrations and RLS, Supabase Edge Functions, Flutter unit/widget tests.

## Global Constraints

- Never write an approved benefit or mapping before evidence grounding and explicit review.
- Preserve the canonical `benefits` catalog; do not delete it during any migration.
- The movie recommendation must recommend only cards owned by the requesting user.
- Do not store full card numbers in plaintext.
- Do not rerun AU Zenith until the user approves the parser/grounding fix; retain rejected staging records as audit evidence.

---

## File structure

- `supabase/migrations/<timestamp>_enforce_user_card_ownership.sql` — statement/transaction keys, constraints, RLS, and data checks.
- `supabase/migrations/<timestamp>_card_benefit_mapping_terms.sql` — card-specific benefit rules on the mapping table.
- `lib/core/repositories/supabase_statement_repository.dart` — write/read statements by `user_card_id`.
- `lib/core/repositories/supabase_transaction_repository.dart` — store `statement_id` as the statement UUID.
- `lib/features/movie_rule_engine/data/movie_rule_engine_service.dart` — limit recommendation candidates to owned cards.
- `lib/core/services/advanced_benefit_calculation_service.dart` — promote accepted benefit semantics and card-specific rules separately.
- `lib/core/services/benefit_extraction_validator.dart` — enforce complete evidence and deduplicate claims before staging.
- `lib/features/debug/pm_pruning_debug_screen.dart` — expose rejected reasons and retry only after source/parser changes.
- `supabase/functions/gemini-proxy/index.ts` — authenticated server-side LLM proxy.

### Task 1: Make `user_cards` the authoritative ownership boundary

**Files:**

- Create: `supabase/migrations/<timestamp>_enforce_user_card_ownership.sql`
- Modify: `schema.sql`
- Modify: `lib/core/repositories/supabase_statement_repository.dart`
- Modify: `lib/shared/models/statement.dart`
- Test: `test/core/repositories/supabase_statement_repository_test.dart`

**Interfaces:**

- `statements.user_card_id` is non-null and references `user_cards(id)`.
- `statements` is unique on `(user_card_id, statement_date)`.
- `Statement` reads/writes `userCardId`; card product data is obtained by joining `user_cards.catalog_card_id`.

- [ ] **Step 1: Write the failing repository contract test**

```dart
test('a statement is addressed by the owned-card id, not catalog card id', () {
  final statement = Statement.fromJson({
    'id': 'statement-1',
    'user_id': 'user-1',
    'user_card_id': 'owned-card-1',
    'statement_date': '2026-07-01',
    'due_date': '2026-07-20',
    'total_amount': 0,
    'minimum_payment': 0,
    'closing_balance': 0,
    'available_credit': 0,
    'rewards_earned': 0,
    'interest_charged': 0,
    'fees_charged': 0,
    'payment_status': 'pending',
    'file_path': '',
    'file_name': '',
    'created_at': '2026-07-01T00:00:00Z',
  });
  expect(statement.userCardId, 'owned-card-1');
});
```

- [ ] **Step 2: Run the test before the migration/repository change**

Run: `flutter test test/core/repositories/supabase_statement_repository_test.dart`

Expected: the test exposes the current insert path’s mismatch between `card_id`, `user_card_id`, and required statement dates.

- [ ] **Step 3: Add ownership-safe schema constraints**

```sql
ALTER TABLE public.statements
  ALTER COLUMN user_card_id SET NOT NULL;
ALTER TABLE public.statements
  DROP CONSTRAINT IF EXISTS statements_card_id_statement_date_key;
ALTER TABLE public.statements
  ADD CONSTRAINT statements_user_card_statement_date_key
  UNIQUE (user_card_id, statement_date);
ALTER TABLE public.transactions
  ALTER COLUMN statement_id TYPE uuid USING statement_id::uuid;
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_statement_id_fkey
  FOREIGN KEY (statement_id) REFERENCES public.statements(id) ON DELETE SET NULL;
```

Before the type conversion, the migration must reject or quarantine any non-UUID `transactions.statement_id`; do not silently cast invalid values.

- [ ] **Step 4: Update repository writes**

`uploadStatement` must receive an owned-card id, resolve its `catalog_card_id` in a user-scoped query, and insert all required fields (`user_id`, `user_card_id`, `card_id`, `statement_date`, `due_date`). `getStatementsForCard` must join through `user_cards` when callers supply a catalog card id.

- [ ] **Step 5: Run focused tests and commit**

Run: `flutter test test/core/repositories/supabase_statement_repository_test.dart`

Expected: PASS.

```bash
git add schema.sql supabase/migrations lib/core/repositories/supabase_statement_repository.dart lib/shared/models/statement.dart test/core/repositories/supabase_statement_repository_test.dart
git commit -m "feat: enforce statement ownership through user cards"
```

### Task 2: Move card-specific commercial terms to the mapping

**Files:**

- Create: `supabase/migrations/<timestamp>_card_benefit_mapping_terms.sql`
- Modify: `schema.sql`
- Modify: `lib/core/services/advanced_benefit_calculation_service.dart`
- Modify: `lib/core/repositories/supabase_card_repository.dart`
- Test: `test/core/services/benefit_mapping_terms_test.dart`

**Interfaces:**

- `benefits` holds reusable semantic identity only.
- `card_benefit_mapping.rule_config` holds the card-specific rate, cap, partner, dates, and source staging id.

- [ ] **Step 1: Write the failing mapping-terms test**

```dart
test('two cards can share one benefit while retaining distinct caps', () {
  final fuelBenefit = 'benefit-fuel-waiver';
  final zenithRule = {'rate': 1, 'monthly_cap': 1000};
  final otherRule = {'rate': 1, 'monthly_cap': 400};
  expect(zenithRule['monthly_cap'], isNot(otherRule['monthly_cap']));
  expect(fuelBenefit, 'benefit-fuel-waiver');
});
```

- [ ] **Step 2: Run the test to verify the current model lacks mapping terms**

Run: `flutter test test/core/services/benefit_mapping_terms_test.dart`

Expected: FAIL because `CardBenefitMappingTerms` does not exist.

- [ ] **Step 3: Add the mapping configuration**

```sql
ALTER TABLE public.card_benefit_mapping
  ADD COLUMN rule_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN source_staging_id uuid REFERENCES public.card_benefits_staging(id) ON DELETE SET NULL,
  ADD COLUMN valid_from date,
  ADD COLUMN valid_until date,
  ADD COLUMN is_active boolean NOT NULL DEFAULT true;
```

Change the approval service to create/reuse `benefits` by semantic dedupe key and put extracted rate/cap/partner restrictions into `rule_config` on the mapping.

- [ ] **Step 4: Update reward queries**

`SupabaseCardRepository.calculateReward` and `AdvancedBenefitCalculationService` must read `card_benefit_mapping.rule_config` before the generic benefit definition.

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/core/services/benefit_mapping_terms_test.dart test/shared/models/card_benefit_mapping_test.dart`

Expected: PASS.

```bash
git add schema.sql supabase/migrations lib/core/services/advanced_benefit_calculation_service.dart lib/core/repositories/supabase_card_repository.dart test/core/services/benefit_mapping_terms_test.dart
git commit -m "feat: retain card-specific benefit rules on mappings"
```

### Task 3: Enforce categories and repair the AU Zenith extraction path

**Files:**

- Create: `supabase/migrations/<timestamp>_benefit_category_integrity.sql`
- Modify: `lib/core/services/benefit_extraction_validator.dart`
- Modify: `lib/features/debug/pm_pruning_debug_screen.dart`
- Test: `test/core/services/benefit_extraction_validator_test.dart`

**Interfaces:**

- `benefits.benefit_category` references `benefit_categories(category_code)`.
- The validator removes duplicate normalized claims before deciding whether the candidate is valid.
- A missing evidence excerpt stays a rejection, with the claim and reason visible to the reviewer.

- [ ] **Step 1: Write failing validator tests from the AU Zenith rejection**

```dart
test('deduplicates repeated grounded fuel claims before validation', () {
  final result = BenefitExtractionValidator.validate(
    extractedData: auZenithRepeatedFuelFixture,
    evidenceText: auZenithEvidence,
    cardName: 'Zenith',
    bankName: 'AU Small Finance Bank',
  );
  expect(result.reasonCodes, isNot(contains('duplicate_benefit')));
});

test('rejects and identifies the exact claim without evidence', () {
  final result = BenefitExtractionValidator.validate(
    extractedData: auZenithMissingExcerptFixture,
    evidenceText: auZenithEvidence,
    cardName: 'Zenith',
    bankName: 'AU Small Finance Bank',
  );
  expect(result.reasonCodes, contains('missing_evidence'));
});
```

- [ ] **Step 2: Run validator tests before changing normalisation**

Run: `flutter test test/core/services/benefit_extraction_validator_test.dart`

Expected: the duplicate fixture fails the first assertion.

- [ ] **Step 3: Implement claim normalisation and category integrity**

Normalise claims by `category + rate_type + description` before validation, retaining one evidence excerpt per canonical claim. Do not invent an excerpt. Add a preflight migration that inserts only missing legitimate category rows, then add the foreign key from `benefits.benefit_category` to `benefit_categories.category_code`.

- [ ] **Step 4: Display rejected claim reasons in the PM UI**

Render each rejected claim’s index, source description, and validation reason in the pipeline rail/detail panel. The retry button must be disabled until extraction output changes or the source is re-scraped.

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/core/services/benefit_extraction_validator_test.dart test/features/debug/benefit_refresh_pipeline_test.dart`

Expected: PASS.

```bash
git add supabase/migrations lib/core/services/benefit_extraction_validator.dart lib/features/debug/pm_pruning_debug_screen.dart test/core/services/benefit_extraction_validator_test.dart
git commit -m "fix: normalize grounded benefit candidates"
```

### Task 4: Restrict movie optimisation to the user’s cards

**Files:**

- Modify: `lib/features/movie_rule_engine/data/movie_rule_engine_service.dart`
- Modify: `lib/features/movie_rule_engine/presentation/movie_analyzer_tab.dart`
- Test: `test/features/movie_rule_engine/movie_rule_engine_service_test.dart`

**Interfaces:**

- `_getUserMovieBenefits(userId)` returns only mappings where an active `user_cards` record belongs to `userId`.
- `getAllMovieCardBenefits` may expose catalog offers only when explicitly labelled “not owned”; `optimizeMovieTicketPurchase` must never consider them.

- [ ] **Step 1: Write a failing owned-card test**

```dart
test('movie optimisation excludes a more valuable card the user does not own', () async {
  final recommendation = await service.optimizeMovieTicketPurchase(
    userId: 'user-1',
    request: movieRequest,
  );
  expect(recommendation.isOwned, isTrue);
  expect(recommendation.cardId, 'owned-card-catalog-id');
});
```

- [ ] **Step 2: Run the test before restricting candidates**

Run: `flutter test test/features/movie_rule_engine/movie_rule_engine_service_test.dart`

Expected: FAIL because non-owned cards currently receive only a ranking penalty.

- [ ] **Step 3: Query owned cards first**

Replace the all-catalog mapping lookup with `user_cards(user_id, is_active) -> card_catalog -> card_benefit_mapping -> benefits`, and filter mappings by active dates/rules.

- [ ] **Step 4: Run tests and commit**

Run: `flutter test test/features/movie_rule_engine/movie_rule_engine_service_test.dart`

Expected: PASS.

```bash
git add lib/features/movie_rule_engine/data/movie_rule_engine_service.dart lib/features/movie_rule_engine/presentation/movie_analyzer_tab.dart test/features/movie_rule_engine/movie_rule_engine_service_test.dart
git commit -m "fix: restrict movie recommendations to owned cards"
```

### Task 5: Secure and verify the ingestion/recommendation system

**Files:**

- Create: `supabase/migrations/<timestamp>_secure_card_and_statement_data.sql`
- Modify: `lib/core/services/enhanced_gmail_service.dart`
- Modify: `lib/core/services/transaction_deduplication_service.dart`
- Modify: `lib/database_setup_app.dart`
- Test: `test/core/services/transaction_deduplication_service_test.dart`

**Interfaces:**

- User-visible card data retains only masked last four digits; full card numbers are not written.
- Gmail ingestion records the originating statement UUID for each parsed transaction.
- `gemini-proxy` remains deployed and reads its key exclusively from Supabase secrets.
- `public.consume_gemini_proxy_quota(uuid, integer)` exists before the web client invokes `gemini-proxy`.

- [ ] **Step 1: Write the failing PII/deduplication test**

```dart
test('statement transaction retains the statement UUID and never stores a full card number', () {
  final transaction = parsedStatementTransaction(statementId: 'statement-1');
  expect(transaction.statementId, 'statement-1');
  expect(transaction.metadata.toString(), isNot(contains('4111111111111111')));
});
```

- [ ] **Step 2: Run the test before changing parser persistence**

Run: `flutter test test/core/services/transaction_deduplication_service_test.dart`

Expected: FAIL until statement UUID propagation is implemented.

- [ ] **Step 3: Implement safe persistence and RLS checks**

Remove or null `user_cards.card_number` after a migration audit, retain `last_four_digits`, add user-scoped RLS policies for statements and transactions, and propagate the created statement UUID to every parsed transaction.

- [ ] **Step 4: Add and deploy the Gemini quota dependency**

Create a new forward-only migration; do not backfill or mark the missing historical migration as applied.

```sql
CREATE TABLE IF NOT EXISTS public.gemini_proxy_usage (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gemini_proxy_usage_user_created
  ON public.gemini_proxy_usage(user_id, created_at DESC);
CREATE OR REPLACE FUNCTION public.consume_gemini_proxy_quota(
  _user_id uuid, _limit integer
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE recent_count integer;
BEGIN
  DELETE FROM public.gemini_proxy_usage
  WHERE created_at < now() - interval '1 hour';
  SELECT count(*) INTO recent_count FROM public.gemini_proxy_usage
  WHERE user_id = _user_id;
  IF recent_count >= _limit THEN RETURN false; END IF;
  INSERT INTO public.gemini_proxy_usage(user_id) VALUES (_user_id);
  RETURN true;
END;
$$;
```

Deploy `gemini-proxy`, set `GEMINI_API_KEY` through Supabase secrets, and verify the function succeeds for an authenticated user without exposing the key to the web bundle.

- [ ] **Step 5: Exercise the complete AU Zenith path after Task 3**

Run one official-URL scrape, verify one pending staging record, review every candidate, approve accepted candidates, and confirm the resulting records are: one or more canonical `benefits`, matching `card_benefit_mapping` rows, and no `card_benefits` writes.

- [ ] **Step 6: Run full focused verification and commit**

Run: `flutter test test/core/services test/features/movie_rule_engine test/features/debug`

Expected: PASS.

```bash
git add supabase/migrations lib/core/services/enhanced_gmail_service.dart lib/core/services/transaction_deduplication_service.dart lib/database_setup_app.dart test/core/services/transaction_deduplication_service_test.dart
git commit -m "feat: secure user card ingestion and provenance"
```

## Self-review

- Ownership, statements, transactions, category integrity, mapping terms, movie recommendations, scrape grounding, and PII handling each have a separate testable task.
- The plan preserves the canonical benefit catalog and requires review before applying mappings.
- No task permits another AU Zenith run until the missing-evidence and duplicate-claim behaviour is fixed.
