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

The only consumers of `category` today are **cosmetic**, and there are
**three separate, drifting copies** of the same icon/color mapping, each
built independently and each out of sync with the others and with the
Gemini prompt's own vocabulary:

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
`monthlySpend`, `rewardsEarned` only. This spec is scoped to fixing the data
and its cosmetic consumers, not building those features — see Non-goals.

A secondary bug, same as main: `Transaction.currency` and the schema column
both default to `'INR'` (`transaction.dart:26,48`, `schema.sql:171`), and
`card_detail_screen.dart` hardcodes a `₹` symbol when rendering amounts
(around line 767) — both wrong for UAE users. The currency-default part is
fixed here since it's needed for the `isInternational` signal (below); the
hardcoded `₹` display symbol is a pre-existing, separate UI bug outside this
feature's scope and is only noted here so it isn't mistaken for something
this work already addresses.

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
  source TEXT NOT NULL DEFAULT 'seed',  -- 'seed' | 'llm' | 'manual'
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### 2. Categorization flow: build the rule layer from scratch, LLM fallback

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
                          merchant_category_map (source='llm' or 'seed')
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

### 3. Currency default fix + `isInternational` signal

Same shape as main's spec, re-derived against this worktree's actual
currency handling (`transaction.dart:26,48`, `schema.sql:171` — confirmed
identical `'INR'`-default bug):

- Bank name is known at parse time (statement ingestion already resolves
  which bank a statement is from, to select card-matching logic). Derive
  the default currency from the parsed bank's market (INR for Indian banks,
  AED for UAE banks) instead of hardcoding `'INR'`.
- Add a derived `isInternational` getter on `Transaction`:
  `currency != bankMarketCurrency` (same `bankMarketCurrency` concept as
  main — the market currency for the bank that issued the statement this
  transaction came from). Independent signal from `category`, not a new
  category value, consistent with main's reasoning (a foreign-currency
  restaurant charge is still "dining," and separately "international").

### 4. Consolidate the three icon/color switches

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

### 5. Backfill

Same mechanism as main's spec: one-time job, run after the pipeline fix
lands, re-categorizing existing transactions using their already-stored
`merchant_name`/`description` — no re-parsing of statements needed. Runs
across all users, not filtered by market.

## Testing

- Unit tests for the merchant-lookup layer (new, built from scratch here):
  normalized-name matching, case insensitivity, fallback when unrecognized.
- Unit tests for Gemini-category validation (step 2): valid value passes
  through, invalid/missing value falls through to step 3.
- Unit tests for the keyword fallback (new, built from scratch): covers all
  16 categories, India + UAE merchant examples.
- Unit test for `isInternational`: currency matches bank market currency →
  false; differs → true.
- Unit test for the consolidated category-display mapping: all 16
  categories return a non-default icon/color; unrecognized value returns
  the shared fallback.
- Backfill job: test against a fixture set of transactions with known
  merchant names/descriptions and legacy (wrong-vocabulary) category
  values, assert correct re-categorization.
- No changes needed to `transactions_screen.dart`'s filter-chip logic — no
  test needed there beyond what already exists, since its behavior is
  unchanged by this work.
