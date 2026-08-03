# Transaction Categorization

## Problem

`Transaction.category` (a `TransactionCategory` enum with 16 values: food, fuel,
grocery, entertainment, travel, shopping, utilities, insurance, medical,
education, investment, transport, rental, subscription, gift, other) is
already read by every downstream feature that would make spend analysis and
card recommendations useful:

- `financial_insights_widget.dart` — dashboard category breakdown/insights panel
- `dashboard_viewmodel.dart._calculateCategoryBreakdown` — feeds the above
- `transactions_screen.dart` — category filter dropdown
- `recommendation_service_impl.dart.getBestCardForTransaction` — compares the
  user's cards against the full card catalog by category and computes
  `potentialSavings`; this is the "which card should you use/onboard" feature
- `advanced_recommendation_service.dart` — category-based spend pattern analysis

None of it works today, because the value going into `category` is almost
always `TransactionCategory.other`. The categorization pipeline that's
supposed to populate this field is broken in two independent ways:

1. **Statement path (primary transaction volume)**:
   `TransactionParsingService._categorizeTransaction()`
   (`lib/core/services/transaction_parsing_service.dart:665`) returns
   human-readable strings like `'Food & Dining'`, `'Transportation'`,
   `'Digital Payments'`, `'Cash Withdrawal'`. The consumer,
   `PdfParsingServiceImpl._parseCategory()`
   (`lib/core/services/pdf_parsing_service_impl.dart:259`), switches on
   enum-style strings: `'FOOD_DINING'`, `'TRANSPORTATION'`, `'GROCERY'`,
   `'HEALTHCARE'`. These never match (`'Food & Dining'.toUpperCase()` is
   `'FOOD & DINING'`, not `'FOOD_DINING'`), so every statement-sourced
   transaction falls through to `TransactionCategory.other`.

2. **Alert-email path**: `enhanced_gmail_service.dart._convertGeminiToTransaction()`
   (`lib/core/services/enhanced_gmail_service.dart:1133`) maps a
   Gemini-returned `category` string to `TransactionCategory`, but the switch
   only handles 6 of 16 values (shopping, food/dining, travel, fuel,
   entertainment, bills/utilities). Grocery, insurance, medical, education,
   investment, transport, rental, subscription, and gift all fall through to
   `other`.

A secondary, pre-existing bug found during investigation: `Transaction.currency`
and the `transactions.currency` column both default to `'INR'`
(`lib/shared/models/transaction.dart:112`, schema `currency TEXT DEFAULT 'INR'`).
Since CardCompass serves both Indian and UAE users, defaulting to a single
currency is wrong regardless of category — this gets fixed alongside the
categorization work since it feeds the same `isInternational` signal (below).

## Goal

Make `Transaction.category` reliably populated for both new and existing
transactions, across both the Indian and UAE card markets this app serves, so
the dashboard, transaction filters, and card-recommendation engine — all
already built — work as intended.

## Non-goals

- Changing the `TransactionCategory` enum. Verified against real reward data
  from both markets (below) — no new categories are needed.
- A user-facing "review AI-guessed categories" screen. Categorization is
  applied silently, same trust level as a rule-based match.
- Manual per-transaction recategorization UI. Out of scope; can be a
  follow-up if it turns out to be needed.

## Taxonomy: unchanged, verified against real reward data

The 16-value `TransactionCategory` enum was checked against reward-category
vocabulary actually used in both markets:

- **UAE**: scanned `docs/uae_credit_cards.csv` (158 cards) for category
  keywords in `rewards_rate`/`cashback_rate`/`other_benefits`. Every real
  spend-category bucket found (dining: 24 cards, fuel: 17, supermarket/grocery:
  16 — used as synonyms across banks, not distinct categories — travel: 62,
  entertainment/cinema: 15, education: 3, transport: 3, subscription/streaming:
  5, insurance: 49) already exists in the enum. `gift`, `rental`, and
  `investment` have zero UAE card reward support — they're already in the
  enum from a prior generic design and are harmless to leave, but nothing new
  needs adding for them.
- **International spend** appears in 55/158 UAE cards
  (`"3 pts/AED domestic; 6 pts/AED international"` style language) but this
  is a currency/geography attribute of a transaction, not a merchant-type
  category — a Carrefour purchase abroad is still "grocery," just also
  "international." Modeling it as a category value would force a transaction
  to pick one signal and lose the other, since `category` is single-valued.
  Instead: a derived `isInternational` signal
  (`transaction.currency != cardHomeCurrency`), independent of `category`,
  usable by the recommendation engine alongside it.
- **India**: checked already-seeded `card_benefits.spending_categories` data
  (dining, entertainment, fuel, shopping, travel/flights, all) — a strict
  subset of the enum. `flights` is a `travel` sub-type, same pattern as UAE's
  `international`.

No enum migration. No new `TransactionCategory` values.

## Architecture

### 1. Merchant → category lookup: new `merchant_category_map` table

Checked whether any existing table could serve this purpose before adding a
new one, per the project's preference for minimal, reuse-existing-schema
fixes. The only candidate was `benefit_categories`
(`category_code` PK, `name`, `description`, `is_active` — 19 seeded rows:
CASHBACK, CONCIERGE, DINING, ENTERTAINMENT, FUEL, GENERAL, GOLF, GROCERY,
HEALTHCARE, INSURANCE, LOUNGE, MILES, OTHER, POINTS, SHOPPING, TRAVEL,
UTILITIES, UTILITY, plus a lowercase `entertainment` duplicate — confirmed
against the live table). It doesn't fit:

- No `merchant_name` column — nowhere to look up "Carrefour" or "Swiggy."
- No FK from `transactions.category` — that column is bare `TEXT`, never
  constrained against `benefit_categories.category_code`. The only real FK
  usage is `card_benefits.category_code → benefit_categories`.
- Its vocabulary mixes real spend categories (`FUEL`, `DINING`, `GROCERY`)
  with reward-mechanism types (`CASHBACK`, `POINTS`, `MILES`) and benefit
  perks (`LOUNGE`, `GOLF`, `CONCIERGE`) — because it exists to tag what a
  *card benefit* covers, not what a *transaction's merchant* is. It also has
  duplicate/inconsistent codes (`UTILITY` vs `UTILITIES`, `OTHER` vs
  `GENERAL`).

Repurposing it would mean adding a column to a table other benefit-catalog
code depends on, then filtering application-side to keep merchant rows away
from non-spend codes. A new, purpose-built table is the smaller diff:

```sql
CREATE TABLE merchant_category_map (
  merchant_name_normalized TEXT PRIMARY KEY,
  category TEXT NOT NULL,        -- one of the 16 TransactionCategory values
  source TEXT NOT NULL DEFAULT 'seed',  -- 'seed' | 'llm' | 'manual'
  created_at TIMESTAMPTZ DEFAULT now()
);
```

No changes to `benefit_categories`, `card_benefits`, or any existing
benefit-catalog logic.

Seeded with common merchants from both markets in one table, one category
vocabulary:

- **India**: promoted from the existing (currently-broken) keyword list
  already in `transaction_parsing_service.dart` — Swiggy, Zomato → food;
  Flipkart, Amazon → shopping; Paytm, PhonePe, GPay, UPI → (kept out of the
  categorizer entirely, see note below); Ola, Uber, Metro → transport; petrol
  pumps → fuel; pharmacy/hospital → medical.
- **UAE**: Carrefour, Lulu → grocery; Talabat, Deliveroo → food; Careem,
  Uber → transport; ADNOC, ENOC → fuel; Noon → shopping.

Note: `paytm`/`phonepe`/`gpay`/`upi` in the current codebase map to
`'Digital Payments'`, which isn't a real spend category — it's a payment
*rail*, and the actual transaction underneath it is a purchase in some other
category the description context doesn't reveal (this is exactly the kind of
ambiguous case the LLM fallback layer is for, since a rule can't
disambiguate "UPI payment to Swiggy" from "UPI payment to a random person").

### 2. Categorization flow: rule-first, LLM fallback

```
Transaction (merchantName, description)
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
                  │ 2. Keyword fallback │  extend existing
                  │    (description)    │  _categorizeTransaction
                  └──────────┬───────────┘
              match?  │  no match
                  │   └──────────────┐
                  ▼                  ▼
             category set   ┌─────────────────────┐
                             │ 3. LLM fallback       │  Gemini classifies
                             │    (Gemini)           │  into one of 16
                             └──────────┬─────────────┘  categories
                                        ▼
                                category set
                                        │
                                        ▼
                          write merchant→category back into
                          merchant_category_map (source='llm')
```

The LLM fallback reuses the existing Gemini call pattern already used for
alert-email parsing (`gemini_transaction_parser.dart`), corrected to request
and parse the actual 16-value `TransactionCategory` vocabulary instead of the
current mismatched `shopping|dining|travel|fuel|entertainment|bills|transfer|fee|payment|cash|other`
list.

Writing the LLM's result back into `merchant_category_map` means each unique
merchant is classified by the LLM at most once across the entire user base —
subsequent encounters of the same merchant (any user, any transaction) are
rule-based hits. This is what makes the hybrid approach cost-bounded rather
than a per-transaction LLM call.

Applied silently — no confirmation UI, no "AI-guessed" flag. Matches how the
alert-email path already behaves.

### 3. Currency default fix

`Transaction.currency` and `transactions.currency` currently default to
`'INR'` unconditionally. The bank name is already known at parse time
(`TransactionParsingService.extractTransactionsFromText(bankName: ...)`,
`GeminiTransactionParser.parseTransactions(bankName: ...)`), and every bank
this app parses belongs to one market — Indian banks (SBI, HDFC, ICICI,
Axis, IndusInd) issue in INR, UAE banks (FAB, Emirates NBD, ADCB, etc.) issue
in AED. The default should be derived from the parsed bank's market instead
of hardcoded to `'INR'`.

### 4. `isInternational` signal

Add a derived getter (not a stored column) on `Transaction`:

```dart
bool get isInternational => currency != bankMarketCurrency;
```

where `bankMarketCurrency` is the same per-bank market currency used for the
default fix above (INR for Indian banks, AED for UAE banks) — a transaction
is international when its actual currency (e.g. a foreign-currency charge
appearing as USD/EUR on an otherwise-INR statement) differs from what that
bank's statements normally denominate in. This is a signal independent of
`category`, not a new category value — the recommendation engine can use
both together (e.g. "international grocery spend").

### 5. Backfill

One-time job, run after the pipeline fix lands:

1. Query `transactions` where `category = 'other'`.
2. Re-run the categorization flow (steps 1–3 above) against each row's
   already-stored `merchant_name`/`description` — no PDF re-parsing needed.
3. Update `category` in place.

Runs across all users and both markets — not filtered by bank/currency,
since the bug affected every statement-sourced transaction regardless of
market.

## Testing

- Unit tests for the merchant-lookup layer: normalized-name matching, case
  insensitivity, fallback to keyword matching when no merchant match.
- Unit tests for the keyword fallback: extend existing test patterns in
  `transaction_parsing_service` tests (if any exist) to cover all 16
  categories, both Indian and UAE merchant examples.
- Unit test for `isInternational`: currency matches home currency → false;
  differs → true.
- Backfill job: test against a fixture set of `other`-categorized
  transactions with known merchant names, assert correct re-categorization.
- No new widget/UI tests needed — no UI changes in this feature.
