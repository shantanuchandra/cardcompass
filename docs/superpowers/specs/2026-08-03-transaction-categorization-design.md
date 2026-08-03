# Transaction Categorization (v2 worktree)

## Relationship to the main-repo spec

A design spec for this same feature was written against the main
`cardcompass` repo
(`docs/superpowers/2026-08-03-transaction-categorization.md` there). This
worktree (`feature/landing-v2`) has a restructured codebase that doesn't
share those files — different parser, different (nonexistent) enum,
different consumers. This is a from-scratch spec for v2's actual code, not a
port. Where a decision from the main spec still applies unchanged (taxonomy,
merchant-table shape), that's noted with the reasoning carried over rather
than re-derived.

## Problem

`Transaction.category` (`lib/shared/models/transaction.dart:11` —
`final String? category;`, a bare unconstrained string, not an enum) is
populated by exactly one path: `GeminiStatementParser.parseTransactions()`
(`lib/core/services/gemini_statement_parser.dart:209`) asks Gemini to fill a
`category` field with one of:

```
shopping|dining|travel|fuel|entertainment|bills|transfer|fee|payment|cash|other
```

`StatementProcessingService._persistParsedStatement()`
(`lib/core/services/statement_processing_service.dart:441`) passes whatever
Gemini returns straight to `TransactionsRepository.addTransaction()`
(`lib/core/repositories/transactions_repository.dart:67-103`) with **zero
validation or mapping** — `category: txn['category'] as String?`. This is
the only construction site for a transaction's category; both PDF-sourced
and Gmail-sourced ingestion converge on this one pipeline (there's no
separate alert-email path here, unlike main's `enhanced_gmail_service.dart`).

Two problems with this, found by inspecting the actual prompt and its
consumers:

1. **The vocabulary itself is wrong.** `transfer`, `fee`, `payment`, `cash`
   are transaction *types*, not spend categories — the same category of
   mistake as main repo's `'Digital Payments'` bug, except here it's baked
   directly into the LLM prompt instead of a keyword categorizer. And the
   vocabulary is missing entire categories real UAE/Indian card rewards
   care about: grocery, utilities, insurance, medical, education, transport,
   subscription (see Taxonomy section — this was verified against real card
   reward data in the main-repo spec, carried over below).

2. **Nothing constrains what actually lands in the column**, since there's
   no enum and no post-processing. Whatever string Gemini emits — correctly
   spelled, differently cased, a synonym, or a hallucinated value outside
   its own instructed vocabulary — is written to Supabase verbatim.

**Correction (post-review):** an earlier version of this spec claimed
`category`'s only consumers were cosmetic (icon/color display). That was
wrong — I hadn't read `transactions_provider.dart` when I wrote it. There
are real, non-cosmetic consumers:

- `lib/features/transactions/providers/transactions_provider.dart:104-113`
  (`TxnsState.topCategory`): groups debit transactions by `category` and
  sums amounts to find the highest-spend category — a real spend-analysis
  output, not display.
- `transactions_provider.dart:93-100` (`TxnsState.filtered`): the
  category filter is a genuine data filter on the transaction list, not
  just a UI chip's active state.
- `transactions_provider.dart:124-127` (`TxnsState.grouped`,
  `TxnGrouping.byCategory`): groups the actual transaction list by
  category for display — the grouping itself is real logic operating on
  `category` values, even though the result is then rendered.

This means the vocabulary fix in this spec isn't just cosmetic cleanup —
`topCategory` and category filtering are currently producing wrong answers
today (since almost everything is miscategorized per the Problem section
above), not just showing a wrong icon. Separately, there **are** still
three drifting icon/color switches (unchanged from the original finding
below) — that part of the original claim was correct, just not the whole
picture.

- `lib/features/dashboard/screens/dashboard_screen.dart:1213-1235`
  (`_categoryColor`/`_categoryIcon`): handles `dining, travel, shopping,
  fuel, entertainment, groceries` — 6 cases.
- `lib/features/transactions/screens/transactions_screen.dart:370-392`:
  same 6 plus `food` as a `dining` alias — 7 cases.
- `lib/features/cards/screens/card_detail_screen.dart:770-794`: a *third,
  different* list — `food, dining, travel, transport, shopping,
  entertainment, fuel, groceries, utilities, health, medical` — 11 cases,
  several of which (`transport`, `utilities`, `health`, `medical`,
  `groceries`) can never actually fire, because the Gemini prompt these
  transactions are sourced from doesn't produce those strings. Dead code
  today; would only start working if the vocabulary changes to include
  them.

Every unrecognized value in all three falls to the same generic default
(`Icons.receipt_rounded`, `AppColors.textSecondary`) — silently, with no
signal that the category didn't match anything.

Unlike main, **v2 has no recommendation engine and no dashboard category
breakdown** — grepped the whole `lib/` tree, confirmed neither
`recommendation_service` nor any category-aggregating dashboard provider
exists. `dashboard_provider.dart` computes `totalCreditLimit`,
`monthlySpend`, `rewardsEarned` only. This spec is scoped to fixing the
data and its consumers (both the real spend-analysis logic in
`transactions_provider.dart` and the three cosmetic switches), not
building a recommendation engine or dashboard breakdown — see Non-goals.

A secondary bug, same as main: `Transaction.currency` and the schema column
both default to `'INR'` (`transaction.dart:26,48`, `schema.sql:171`), and
`card_detail_screen.dart` hardcodes a `₹` symbol when rendering amounts
(around line 767) — both wrong for UAE users. Re-verified during review and
found to be **worse than originally stated**: `gemini_statement_parser.dart`'s
prompt (`lib/core/services/gemini_statement_parser.dart:207`) hardcodes
`"currency": "INR"` as a literal example value in the JSON schema Gemini is
shown, and — separately — `statement_processing_service.dart` never reads
`txn['currency']` from Gemini's response at all, even though Gemini's output
includes that field. So this isn't just an unhelpful default: even a real
UAE transaction, correctly identified by Gemini, would have its actual
currency silently discarded by the ingestion code, and the *prompt itself*
biases Gemini toward reporting INR regardless of what it actually sees. All
three layers need fixing together, not just the one default value — see
Architecture §4. The hardcoded `₹` display symbol is a separate pre-existing
UI bug outside this feature's scope, noted only so it isn't mistaken for
something this work already addresses.

## Goal

Make `category` reliably populated with one of a fixed, correct vocabulary
for every new transaction (PDF or Gmail-sourced — same single pipeline), for
both Indian and UAE users, and backfill existing transactions. Consolidate
the three drifting icon/color switches into one shared mapping so the
vocabulary has exactly one place to update, not three.

## Non-goals

- Building a recommendation engine or a dashboard category-spend breakdown.
  Neither exists in v2 today; this spec makes the underlying data correct
  and consistent so either is easy to build later, but building them is
  separate work.
- Introducing a `TransactionCategory` enum. `category` stays a `String?`
  constrained by validation/lookup logic, not a Dart enum — smaller change,
  consistent with v2's existing pattern of keeping the wire-format string
  close to the model (see `TransactionType`'s own hand-rolled
  `_parseType` for the one precedent that does use an enum, kept as network
  transaction-type only, not spend category).
- Fixing the hardcoded `₹` symbol in `card_detail_screen.dart`. Noted above
  as a related but separate pre-existing bug.
- A user-facing category-review/correction UI. Applied silently, same as
  main's spec decision.
- Unifying `transactions.category` with the two other, unrelated category
  vocabularies already in this schema (see the note at the end of the
  Taxonomy section). No alias/translation table is built for this.

## Taxonomy: adopt main's 16-category vocabulary, verified sufficient

Carried over from the main-repo spec's verification (re-deriving it here
would just re-confirm the same evidence):

`food, fuel, grocery, entertainment, travel, shopping, utilities, insurance,
medical, education, investment, transport, rental, subscription, gift,
other`

Checked against real reward-category language from 158 UAE cards
(`docs/uae_credit_cards.csv`) and seeded Indian card benefit data
(`card_benefits.spending_categories`: dining, entertainment, fuel,
shopping, travel/flights, all — a strict subset). That verification was
done against the main repo's checkout, where the UAE dataset file lives —
checked directly, **this worktree does not have that file on disk**
(`feature/landing-v2` branched before the commit that added it, and it
hasn't been merged forward; the commit itself, `10faf70`, is reachable in
this worktree's full history via `git log --all`, just not checked out
here). The underlying data and the verification against it are real; only
noting this so the file path isn't assumed present if someone tries to
re-run the check from this worktree. Every real spend-category reward
bucket found in either market's data already exists in this list. No gaps
found, so no expansion needed — "grocery" and
"supermarket" are bank-language synonyms for one category, not two;
"international"/"flights" are currency/geography and travel-subtype
attributes respectively, not distinct merchant categories (see
`isInternational` below).

v2's current prompt vocabulary (`shopping, dining, travel, fuel,
entertainment, bills, transfer, fee, payment, cash, other`) gets replaced by
this list. `bills` maps to `utilities`. `transfer`, `fee`, `payment`, `cash`
are dropped from the *category* vocabulary — they describe how money moved
or what kind of charge it was, which `TransactionType` already exists to
capture (`debit, credit, refund, fee, interest, reward` —
`transaction.dart:1`); conflating a transaction's type with its spend
category is what let `fee`/`payment`/`cash` end up in a category field in
the first place.

**Known limitation, documented rather than fixed (post-review finding):**
this 16-value list is a *third* category vocabulary in this schema,
unrelated to and not reconciled with two others already live:

- `benefits.benefit_category` — free text, e.g. literal `'dining'`
  (confirmed via `supabase/migrations/20260711043900_restore_reference_data.sql`,
  many rows, e.g. lines 253, 268, 401) — describes what a *card's benefit*
  covers, not what a transaction is.
- `benefit_exclusions.categories` (a JSONB array nested in
  `benefits.exclusions`) — yet another vocabulary: `rent_payments`,
  `wallet_loads`, `government_payments`, `EMI`, `cash_withdrawal`,
  `rental_property_management`, `wallet_load` (singular, inconsistent with
  the plural form elsewhere) — confirmed present across dozens of rows in
  the same migration file. This vocabulary is read by real, working
  application code: `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart`'s
  `qualifyingCategories`/`excludedCategories` do plain string-set matching
  against these values, with no fixed enum on that side either.

This spec's 16-category list doesn't touch either of those columns and
doesn't break the movie-deals rule engine (different table, different
column, no shared code path). But there is currently **no mapping between
any of the three vocabularies** — nothing in this codebase compares "what a
user spent on" (`transactions.category`) against "what a card's benefits
cover" (`benefits.benefit_category`/`benefit_exclusions.categories`), and
this work doesn't build that comparison or a translation layer for it.
Building one now would mean guessing at mappings (e.g. is `EMI` a spend
category or a transaction type? does `rental_property_management` map to
this spec's `rental`, or is it narrower?) for a comparison no current
feature needs — v2 has no recommendation engine (confirmed above) to
consume it. When that engine gets built, reconciling these vocabularies
becomes part of *that* spec, informed by whatever comparison it actually
needs to do.

## Architecture

### 1. Merchant → category lookup: new `merchant_category_map` table

Same conclusion as main's spec, re-checked directly against this worktree's
schema: `benefit_categories` (`schema.sql:56-63`,
`supabase/migrations/20260711043900_restore_reference_data.sql:669-688`) has
the identical 19 seeded rows (CASHBACK, CONCIERGE, DINING, ENTERTAINMENT,
FUEL, GENERAL, GOLF, GROCERY, HEALTHCARE, INSURANCE, LOUNGE, MILES, OTHER,
POINTS, SHOPPING, TRAVEL, UTILITIES, UTILITY, plus a lowercase
`entertainment` duplicate) — same lack of a `merchant_name` column, same
mixed vocabulary (real spend categories alongside reward-mechanism types
and benefit perks), same absence of any FK from `transactions.category`.
Confirmed no merchant→category table or Dart map exists anywhere in this
worktree either (`grep -rin "merchant" lib/ supabase/migrations/*.sql
schema.sql` — only field-level `merchantName`/`merchant_name` hits). New
table, unchanged from main's design:

```sql
CREATE TABLE merchant_category_map (
  merchant_name_normalized TEXT PRIMARY KEY,
  category TEXT NOT NULL,        -- one of the 16 categories above
  source TEXT NOT NULL DEFAULT 'seed',  -- 'seed' | 'keyword_fallback' | 'manual'
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**Write trust model (missing from the original version of this spec,
flagged in review):** this table is shared across all users — a wrong row
would misclassify that merchant for everyone, not just the user whose
transaction triggered it. So:

- Every authenticated user can **read** the table directly (it's not
  per-user data).
- **Writes never happen directly from an authenticated client.** The
  app never calls `INSERT`/`UPDATE` on this table with the regular
  Supabase client. Instead, a `SECURITY DEFINER` Postgres function
  (`upsert_merchant_category`) is the only write path, callable via RPC,
  and it always inserts with `ON CONFLICT (merchant_name_normalized) DO
  NOTHING` — **the first categorization for a merchant wins, permanently,
  from the app's perspective.** This is a deliberate simplification, not
  an oversight: it avoids a single bad keyword-fallback guess silently
  overwriting a previously-correct row (whether seeded or
  keyword-fallback-derived), at the cost of also preventing a later
  *correct* re-classification from overwriting an earlier wrong one
  automatically. Correcting a wrong row that's already in the table is a
  manual operation (direct SQL against the table, bypassing the RPC) —
  out of scope for this spec, since no tooling exists yet for
  operator-driven corrections and none is built here.
- `source = 'keyword_fallback'` distinguishes runtime-learned rows from
  the hand-seeded `'seed'` rows, so it's possible to audit later which
  rows came from a one-off keyword match on a single transaction's
  description vs. a deliberately curated seed list — this matters because
  a keyword match (Task 3's tier 3) is a weaker signal than an exact
  merchant name in the seed list, even though both currently get treated
  identically by the read side (there's no confidence scoring; the table
  doesn't distinguish "seen once, from one transaction's description"
  from "known common merchant" once a row exists).

### 2. Enforce the vocabulary at the database level

**Added after review** — the original version of this spec relied
entirely on application code (the categorizer, Gemini validation) to keep
`transactions.category` limited to the 16 valid values, with nothing
stopping a bypass — a direct SQL edit, a future code path that doesn't go
through the categorizer, a migration script — from writing an arbitrary
string. Confirmed `transactions.category` currently has no `CHECK`
constraint, only an index (`schema.sql:294`,
`idx_transactions_category`). This codebase already uses `CHECK`
constraints elsewhere for exactly this kind of enforcement
(`statement_date`/`due_date` on `user_cards`, `benefit_extractions.status`
— confirmed via `schema.sql:47-48,127`), so adding one here is consistent
with an existing pattern, not a new one:

```sql
ALTER TABLE transactions
  ADD CONSTRAINT transactions_category_valid CHECK (
    category IS NULL OR category IN (
      'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
      'utilities', 'insurance', 'medical', 'education', 'investment',
      'transport', 'rental', 'subscription', 'gift', 'other'
    )
  );
```

`category IS NULL` stays allowed at the constraint level even though the
categorizer (§3 below) is designed to always resolve to a concrete value,
including `'other'`, never `NULL` — this is a defense-in-depth choice, not
a contradiction: existing rows created before this constraint exists
(handled by the backfill, §6) and any future code path that doesn't call
the categorizer should fail *safely* (row insert succeeds with `NULL`)
rather than fail the whole insert outright if something upstream doesn't
set a category at all. The categorizer itself is still specified to never
produce `NULL` — this constraint is a safety net for cases the categorizer
doesn't cover, not routine behavior.

### 3. Categorization flow: build the rule layer from scratch, LLM fallback

Unlike main (which had an existing, if broken, keyword categorizer to
correct and extend), **v2 has no rule-based layer at all** — categorization
today is a single LLM call with no pre- or post-processing. This spec builds
the rule-first tier new rather than fixing an existing one:

```
Gemini statement parse (existing)
        │
        ▼
merchantName, description, raw category string (now corrected vocabulary)
        │
        ▼
┌───────────────────────┐
│ 1. Merchant lookup     │  normalize merchantName, query
│    (merchant_category_ │  merchant_category_map
│    map)                │
└───────────┬────────────┘
    match?  │  no match
        │   └──────────────┐
        ▼                  ▼
   category set   ┌────────────────────┐
                  │ 2. Trust Gemini's    │  if Gemini's own category
                  │    category, if      │  value is one of the 16
                  │    valid             │  valid values, use it
                  └──────────┬───────────┘
              valid?  │  invalid/missing
                  │   └──────────────┐
                  ▼                  ▼
             category set   ┌─────────────────────┐
                             │ 3. Keyword fallback   │  description-based,
                             │    (description)      │  built new (no
                             └──────────┬─────────────┘  existing list to
                                        ▼                  reuse in v2)
                                category set
                                        │
                                        ▼
                          write merchant→category back into
                          merchant_category_map (source='keyword_fallback')
```

Step 2 differs from main's design: since v2's Gemini call already runs as
part of statement parsing (there's no separate "alert email" pipeline to
add an LLM fallback *to*), the corrected-vocabulary Gemini output is used
directly when it's valid, rather than treated as a last-resort fallback.
The merchant-lookup table still gets priority (step 1) so a known merchant
is deterministic even if Gemini's per-transaction guess would've differed
run to run. Step 3 (keyword fallback on `description`) exists for the case
where the merchant is unrecognized *and* Gemini's returned value isn't one
of the 16 valid categories (e.g. it hallucinates something outside its own
instructed vocabulary) — built from scratch here, seeded with the same
kind of India + UAE merchant keywords the main-repo spec described
(Swiggy/Zomato/Flipkart/Ola/Careem/Talabat/Carrefour/ADNOC/etc.), since no
prior keyword list exists in this worktree to promote from.

Applied silently — no confirmation UI, no "AI-guessed" flag, consistent
with the main spec's decision and with v2 having no review-UI precedent to
follow instead.

### 4. Currency fix (three layers) + `isInternational` signal

**Revised after review** — the original version of this spec described a
single-layer fix (change the hardcoded default). That's insufficient:
verified during review that the problem exists at three independent layers,
and all three need fixing for `isInternational` to mean anything real:

1. **The Gemini prompt hardcodes a wrong example value.**
   `gemini_statement_parser.dart:207` (inside `parseTransactions()`'s JSON
   schema shown to Gemini) has `"currency": "INR"` as a literal in the
   example — not a fallback value used only when detection fails, but the
   *only* value ever shown as an example, for every statement regardless of
   bank. Fix: change the prompt to ask Gemini to report the actual currency
   symbol/code it observes on each transaction line (most Indian statements
   say "Rs." or "₹"; a UAE statement would say "AED" or "د.إ"), with `INR`
   only as what to assume *if no currency marker is visible at all* — not
   as the example's fixed value.
2. **The ingestion code discards whatever currency Gemini returns.**
   `statement_processing_service.dart`'s transaction-persisting loop
   (`_persistParsedStatement`, currently around lines 430-446) never reads
   `txn['currency']` — it's present in Gemini's per-transaction JSON object
   (per the prompt's own schema) but silently dropped. Fix: read it, and
   pass it through to `TransactionsRepository.addTransaction`'s `currency`
   parameter instead of relying on that parameter's default.
3. **No default value exists for when neither of the above resolves
   anything** (e.g. Gemini returns null for a line with no visible
   currency marker). Bank name is known at parse time (statement ingestion
   already resolves which bank a statement is from, to select
   card-matching logic) — add a small `currencyForBank(bankName)` lookup
   (INR for Indian banks, AED for UAE banks; this also requires teaching
   `CardNormalizerService.normalizeBankName` to recognize UAE banks at
   all, since it currently only recognizes Indian ones) as the last-resort
   default, used only when Gemini's per-transaction value is missing.

Priority order per transaction: Gemini's own reported currency (layer 1+2,
now actually read) → `currencyForBank` fallback (layer 3) → hardcoded
`'INR'` never happens again as a bare default.

Add a derived `isInternational` method on `Transaction`:
`currency != bankMarketCurrency`, where `bankMarketCurrency` is the same
`currencyForBank(bankName)` result from layer 3 — the bank's *default*
market currency, independent of what this specific transaction's currency
turned out to be. Independent signal from `category`, not a new category
value (a foreign-currency restaurant charge is still "food," and separately
"international").

**What this fix does not cover, honestly:** none of this can be verified
end-to-end without a real UAE statement PDF to run through the pipeline —
this worktree has never ingested one (confirmed: `card_normalizer_service.dart`
recognized zero UAE banks before this work). The fix is correct by
inspection of the prompt/code, but unverified by an actual parse until a
real UAE statement is available for testing. Flag this explicitly during
manual verification (see the implementation plan's Task 10) rather than
treating "the code looks right" as equivalent to "this was tested against
UAE data."

### 5. Consolidate the three icon/color switches

New to v2's spec — main never had this problem because its category logic
was centralized. Replace the three independent
`_categoryColor`/`_categoryIcon` pairs in `dashboard_screen.dart`,
`transactions_screen.dart`, and `card_detail_screen.dart` with one shared
mapping (a single function or small lookup class, e.g.
`lib/shared/utils/category_display.dart`) covering all 16 categories with a
consistent icon/color per category, used by all three call sites. This
removes the current risk where changing the vocabulary requires updating
three lists in lockstep or silently regressing to the generic fallback
icon — now there's exactly one place to update.

`transactions_screen.dart`'s filter-chip list
(`state.all.map((t) => t.category).whereType<String>().toSet()`) needs no
change — it already builds its options dynamically from whatever category
strings exist in the data, so it self-adapts to the corrected vocabulary.

### 6. Backfill

Same mechanism as main's spec: one-time job, run after the pipeline fix
lands, re-categorizing existing transactions using their already-stored
`merchant_name`/`description` — no re-parsing of statements needed. Runs
across all users, not filtered by market.

## Testing

- Unit tests for the merchant-lookup layer (new, built from scratch here):
  normalized-name matching, case insensitivity, fallback when unrecognized.
- Unit tests for Gemini-category validation (§3, tier 2): valid value
  passes through, invalid/missing value falls through to tier 3.
- Unit tests for the keyword fallback (§3, tier 3, new, built from
  scratch): covers all 16 categories, India + UAE merchant examples.
- **Database `CHECK` constraint (§2, added after review):** verify the
  constraint actually rejects an invalid value and accepts every one of
  the 16 valid values plus `NULL` — this needs a test against a real (or
  local) Supabase instance, since a `CHECK` constraint can't be tested
  against pure Dart logic; if this project has no existing pattern for
  schema-level tests, a manual verification step (attempt an invalid
  insert via the Supabase SQL editor, confirm it's rejected) is the
  fallback — call this out explicitly rather than silently skipping
  constraint verification.
- **Currency fix, three layers (§4, revised after review):**
  - Gemini prompt: no automated test possible (same reasoning as the
    original spec's note on the category prompt — this only affects what
    Gemini is *asked* to return, not verifiable by unit test).
  - Ingestion reading `txn['currency']`: unit-testable once extracted into
    a pure function (given a parsed transaction map, extract and validate
    its currency field) — test that a present, valid currency is used,
    and that a missing/invalid one falls through to the bank-market
    default.
  - `currencyForBank`: unit test covering at least one Indian and one UAE
    bank name, plus an unrecognized name (should default to INR,
    preserving today's single-market assumption for anything not
    explicitly recognized as UAE).
  - `isInternational`: currency matches bank market currency → false;
    differs → true.
  - **Explicitly untested end-to-end:** no real UAE statement PDF exists
    to verify the full pipeline against (see §4's honesty note). Flag
    this as a known gap in test coverage, not a silently accepted risk.
- Unit test for the consolidated category-display mapping: all 16
  categories return a non-default icon/color; unrecognized value returns
  the shared fallback.
- Backfill job: test against a fixture set of transactions with known
  merchant names/descriptions and legacy (wrong-vocabulary) category
  values, assert correct re-categorization.
- **`transactions_provider.dart` consumers (added after review — these
  are no longer assumed unaffected):** `topCategory` and `filtered`
  (category filter) should get at least one test each confirming they
  produce correct results once `category` values are the corrected
  vocabulary — these were previously assumed cosmetic and untested;
  after the correction earlier in this spec, they're known to be real
  logic that depends on correct category data, so they need coverage
  even though this spec doesn't change their implementation.
- No changes needed to `transactions_screen.dart`'s filter-chip logic — no
  test needed there beyond what already exists, since its behavior is
  unchanged by this work.
