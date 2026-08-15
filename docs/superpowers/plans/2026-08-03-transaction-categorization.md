# Transaction Categorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every transaction's `category` field reliably populated with one
of 16 correct spend categories (for both Indian and UAE statements), fix the
three drifting cosmetic category-icon switches to read from one shared
source, and backfill existing transactions — per
`docs/superpowers/specs/2026-08-03-transaction-categorization-design.md`.

**Architecture:** A new pure-logic categorizer
(`lib/core/services/transaction_categorizer.dart`) picks a category for a
transaction via merchant lookup → trust Gemini's own value if valid →
keyword fallback, with no direct Supabase dependency (so it's unit-testable
without a live database). A new `bank_market.dart` fills a real gap found
during investigation — the codebase has no existing "is this bank Indian or
UAE" classification — needed to fix the currency-default bug and derive an
`isInternational` signal. A new Supabase table
(`merchant_category_map`) backs the merchant-lookup tier and is written to
by both a seed migration and, at runtime, whenever a category gets resolved
through the keyword tier (so future lookups of that same merchant are
instant). Three existing UI files get one shared category→icon/color
mapping instead of their own copies. A one-time backfill service
re-categorizes existing `other`-bucketed transactions using the same
categorizer.

**Tech Stack:** Flutter/Dart, Supabase (Postgres + supabase_flutter),
flutter_test (no mocking library in this project — tests target pure Dart
logic, not mocked repositories).

---

## Important context for whoever implements this

This work happens in the `cardcompass-landing-v2` git worktree, on branch
`feature/landing-v2` — **not** the main `cardcompass` repo. Before starting,
confirm you're in the right directory:

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
git branch --show-current
```

Expected output: `feature/landing-v2`

This worktree currently has 6 files with **pre-existing uncommitted
changes**, unrelated to this feature (a statement-ingestion
bank-disambiguation rework and a dashboard carousel fix):
`lib/core/repositories/cards_repository.dart`,
`lib/core/repositories/email_repository.dart`,
`lib/core/services/gemini_statement_parser.dart`,
`lib/core/services/statement_processing_service.dart`,
`lib/features/dashboard/providers/gmail_sync_provider.dart`,
`lib/features/dashboard/screens/dashboard_screen.dart`. **Do not discard,
stash, or `git checkout` these files.** Two of them
(`gemini_statement_parser.dart`, `statement_processing_service.dart`) are
modified by this plan too — build on top of their current content (shown in
full in each task below, reflecting their state as of this plan's writing),
don't revert them. If `git status` shows different content in these files
than what's quoted in this plan when you start, re-read the file fresh
before editing — someone may have committed or further changed them since.

All 16 categories referenced throughout: `food, fuel, grocery,
entertainment, travel, shopping, utilities, insurance, medical, education,
investment, transport, rental, subscription, gift, other`.

---

## Task 1: `merchant_category_map` table + seed data

**Files:**
- Create: `supabase/migrations/20260803120000_merchant_category_map.sql`
- Create: `lib/core/services/merchant_category_seed.dart`
- Test: `test/core/services/merchant_category_seed_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/merchant_category_seed_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/merchant_category_seed.dart';

const _validCategories = {
  'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
  'utilities', 'insurance', 'medical', 'education', 'investment',
  'transport', 'rental', 'subscription', 'gift', 'other',
};

void main() {
  group('merchantCategorySeed', () {
    test('every value is one of the 16 valid categories', () {
      for (final entry in merchantCategorySeed.entries) {
        expect(
          _validCategories.contains(entry.value),
          isTrue,
          reason: '${entry.key} -> ${entry.value} is not a valid category',
        );
      }
    });

    test('every key is already uppercase-normalized', () {
      for (final key in merchantCategorySeed.keys) {
        expect(key, key.toUpperCase(), reason: '$key should be uppercase');
      }
    });

    test('covers known Indian merchants', () {
      expect(merchantCategorySeed['SWIGGY'], 'food');
      expect(merchantCategorySeed['ZOMATO'], 'food');
      expect(merchantCategorySeed['FLIPKART'], 'shopping');
      expect(merchantCategorySeed['AMAZON'], 'shopping');
      expect(merchantCategorySeed['OLA'], 'transport');
      expect(merchantCategorySeed['UBER'], 'transport');
    });

    test('covers known UAE merchants', () {
      expect(merchantCategorySeed['CARREFOUR'], 'grocery');
      expect(merchantCategorySeed['TALABAT'], 'food');
      expect(merchantCategorySeed['CAREEM'], 'transport');
      expect(merchantCategorySeed['ADNOC'], 'fuel');
      expect(merchantCategorySeed['ENOC'], 'fuel');
      expect(merchantCategorySeed['NOON'], 'shopping');
    });

    test('has no duplicate keys (Map construction would already prevent this, '
        'but guards against a future accidental re-declaration in a merge)', () {
      expect(merchantCategorySeed.keys.toSet().length, merchantCategorySeed.length);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/merchant_category_seed_test.dart`
Expected: FAIL — `merchant_category_seed.dart` doesn't exist, import error.

- [ ] **Step 3: Write the seed data**

```dart
// lib/core/services/merchant_category_seed.dart

/// Merchant name (uppercase, normalized) -> one of the 16 spend categories.
/// Seeds `merchant_category_map` (see the migration in this same task) and
/// is also imported directly by the categorizer's tests. Covers common
/// Indian and UAE merchants — the two markets this app's statement parsing
/// already supports (see `card_normalizer_service.dart`'s bank list).
const Map<String, String> merchantCategorySeed = {
  // Food delivery / dining — India
  'SWIGGY': 'food',
  'ZOMATO': 'food',
  'DOMINOS': 'food',
  'MCDONALDS': 'food',
  'STARBUCKS': 'food',
  // Food delivery / dining — UAE
  'TALABAT': 'food',
  'DELIVEROO': 'food',
  'ZOMATO UAE': 'food',

  // Grocery / supermarket — India
  'BIGBASKET': 'grocery',
  'BLINKIT': 'grocery',
  'ZEPTO': 'grocery',
  'DMART': 'grocery',
  'RELIANCE FRESH': 'grocery',
  // Grocery / supermarket — UAE
  'CARREFOUR': 'grocery',
  'LULU': 'grocery',
  'SPINNEYS': 'grocery',
  'WAITROSE': 'grocery',

  // Shopping — India
  'AMAZON': 'shopping',
  'FLIPKART': 'shopping',
  'MYNTRA': 'shopping',
  'AJIO': 'shopping',
  'NYKAA': 'shopping',
  // Shopping — UAE
  'NOON': 'shopping',
  'NAMSHI': 'shopping',
  'SHEIN': 'shopping',

  // Transport — India
  'OLA': 'transport',
  'UBER': 'transport',
  'RAPIDO': 'transport',
  'IRCTC': 'transport',
  'METRO': 'transport',
  // Transport — UAE
  'CAREEM': 'transport',
  'RTA': 'transport',
  'SALIK': 'transport',

  // Fuel — India
  'INDIAN OIL': 'fuel',
  'BHARAT PETROLEUM': 'fuel',
  'HP PETROL': 'fuel',
  'HPCL': 'fuel',
  // Fuel — UAE
  'ADNOC': 'fuel',
  'ENOC': 'fuel',
  'EPPCO': 'fuel',

  // Entertainment — both markets
  'NETFLIX': 'entertainment',
  'PRIME VIDEO': 'entertainment',
  'SPOTIFY': 'entertainment',
  'BOOKMYSHOW': 'entertainment',
  'PVR': 'entertainment',
  'VOX CINEMAS': 'entertainment',
  'REEL CINEMAS': 'entertainment',

  // Travel — both markets
  'MAKEMYTRIP': 'travel',
  'GOIBIBO': 'travel',
  'INDIGO': 'travel',
  'AIR INDIA': 'travel',
  'EMIRATES': 'travel',
  'ETIHAD': 'travel',
  'BOOKING.COM': 'travel',
  'AIRBNB': 'travel',

  // Utilities — both markets
  'DEWA': 'utilities',
  'ETISALAT': 'utilities',
  'DU': 'utilities',
  'AIRTEL': 'utilities',
  'JIO': 'utilities',

  // Medical — both markets
  'APOLLO PHARMACY': 'medical',
  'PHARMEASY': 'medical',
  'LIFE PHARMACY': 'medical',
  'ASTER PHARMACY': 'medical',

  // Education — both markets
  'BYJUS': 'education',
  'UDEMY': 'education',
  'COURSERA': 'education',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/merchant_category_seed_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Create the migration**

```sql
-- supabase/migrations/20260803120000_merchant_category_map.sql
BEGIN;

CREATE TABLE IF NOT EXISTS public.merchant_category_map (
  merchant_name_normalized TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.merchant_category_map IS
  'Maps a normalized merchant name to one of the 16 transaction spend categories. Seeded with common Indian/UAE merchants; grown at runtime when the keyword-fallback categorizer resolves an unrecognized merchant (source=''keyword_fallback'').';

ALTER TABLE public.merchant_category_map ENABLE ROW LEVEL SECURITY;

-- Every authenticated user can read the shared merchant map (it's not
-- per-user data) but writes go through the service role only (from the
-- app's categorizer, using the anon/authenticated Supabase client with
-- RLS still enforced for reads; inserts happen via an RPC below so a
-- malicious client can't poison shared merchant data with the wrong
-- category for other users).
CREATE POLICY "merchant_category_map_select_authenticated"
  ON public.merchant_category_map
  FOR SELECT
  TO authenticated
  USING (true);

GRANT SELECT ON public.merchant_category_map TO authenticated;

-- Upsert used by the app's categorizer when the keyword-fallback tier
-- resolves a category for a merchant not yet in the table. SECURITY
-- DEFINER so an authenticated user can grow the shared map without a
-- broader UPDATE/INSERT grant on the table itself. Never overwrites an
-- existing row — first categorization wins, consistent with treating
-- this as a growing cache, not a per-user editable value.
CREATE OR REPLACE FUNCTION public.upsert_merchant_category(
  p_merchant_name_normalized TEXT,
  p_category TEXT,
  p_source TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.merchant_category_map (merchant_name_normalized, category, source)
  VALUES (p_merchant_name_normalized, p_category, p_source)
  ON CONFLICT (merchant_name_normalized) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_merchant_category(TEXT, TEXT, TEXT) TO authenticated;

-- Seed data — must match lib/core/services/merchant_category_seed.dart
-- (Step 3 above) row for row. Hand-duplicated rather than generated: this
-- table changes rarely, and a code-generation step here would add a
-- fragile moving part (shell quoting, a throwaway script to maintain) for
-- a one-time write. If a merchant is added to/changed in the Dart map
-- later, add the matching row here too — the Dart-side test
-- (merchant_category_seed_test.dart) only validates the Dart map's own
-- internal consistency, not that this SQL block stays in sync with it, so
-- keeping the two aligned is a manual discipline, not something enforced
-- by CI.
INSERT INTO public.merchant_category_map (merchant_name_normalized, category, source) VALUES
  ('SWIGGY', 'food', 'seed'),
  ('ZOMATO', 'food', 'seed'),
  ('DOMINOS', 'food', 'seed'),
  ('MCDONALDS', 'food', 'seed'),
  ('STARBUCKS', 'food', 'seed'),
  ('TALABAT', 'food', 'seed'),
  ('DELIVEROO', 'food', 'seed'),
  ('ZOMATO UAE', 'food', 'seed'),
  ('BIGBASKET', 'grocery', 'seed'),
  ('BLINKIT', 'grocery', 'seed'),
  ('ZEPTO', 'grocery', 'seed'),
  ('DMART', 'grocery', 'seed'),
  ('RELIANCE FRESH', 'grocery', 'seed'),
  ('CARREFOUR', 'grocery', 'seed'),
  ('LULU', 'grocery', 'seed'),
  ('SPINNEYS', 'grocery', 'seed'),
  ('WAITROSE', 'grocery', 'seed'),
  ('AMAZON', 'shopping', 'seed'),
  ('FLIPKART', 'shopping', 'seed'),
  ('MYNTRA', 'shopping', 'seed'),
  ('AJIO', 'shopping', 'seed'),
  ('NYKAA', 'shopping', 'seed'),
  ('NOON', 'shopping', 'seed'),
  ('NAMSHI', 'shopping', 'seed'),
  ('SHEIN', 'shopping', 'seed'),
  ('OLA', 'transport', 'seed'),
  ('UBER', 'transport', 'seed'),
  ('RAPIDO', 'transport', 'seed'),
  ('IRCTC', 'transport', 'seed'),
  ('METRO', 'transport', 'seed'),
  ('CAREEM', 'transport', 'seed'),
  ('RTA', 'transport', 'seed'),
  ('SALIK', 'transport', 'seed'),
  ('INDIAN OIL', 'fuel', 'seed'),
  ('BHARAT PETROLEUM', 'fuel', 'seed'),
  ('HP PETROL', 'fuel', 'seed'),
  ('HPCL', 'fuel', 'seed'),
  ('ADNOC', 'fuel', 'seed'),
  ('ENOC', 'fuel', 'seed'),
  ('EPPCO', 'fuel', 'seed'),
  ('NETFLIX', 'entertainment', 'seed'),
  ('PRIME VIDEO', 'entertainment', 'seed'),
  ('SPOTIFY', 'entertainment', 'seed'),
  ('BOOKMYSHOW', 'entertainment', 'seed'),
  ('PVR', 'entertainment', 'seed'),
  ('VOX CINEMAS', 'entertainment', 'seed'),
  ('REEL CINEMAS', 'entertainment', 'seed'),
  ('MAKEMYTRIP', 'travel', 'seed'),
  ('GOIBIBO', 'travel', 'seed'),
  ('INDIGO', 'travel', 'seed'),
  ('AIR INDIA', 'travel', 'seed'),
  ('EMIRATES', 'travel', 'seed'),
  ('ETIHAD', 'travel', 'seed'),
  ('BOOKING.COM', 'travel', 'seed'),
  ('AIRBNB', 'travel', 'seed'),
  ('DEWA', 'utilities', 'seed'),
  ('ETISALAT', 'utilities', 'seed'),
  ('DU', 'utilities', 'seed'),
  ('AIRTEL', 'utilities', 'seed'),
  ('JIO', 'utilities', 'seed'),
  ('APOLLO PHARMACY', 'medical', 'seed'),
  ('PHARMEASY', 'medical', 'seed'),
  ('LIFE PHARMACY', 'medical', 'seed'),
  ('ASTER PHARMACY', 'medical', 'seed'),
  ('BYJUS', 'education', 'seed'),
  ('UDEMY', 'education', 'seed'),
  ('COURSERA', 'education', 'seed')
ON CONFLICT (merchant_name_normalized) DO NOTHING;

COMMIT;
```

- [ ] **Step 6: Verify the migration applies cleanly**

Run: `supabase db reset` (if using local Supabase dev) or apply via the
Supabase dashboard SQL editor against a dev project — confirm no errors
and `SELECT count(*) FROM merchant_category_map;` returns the expected
row count (67 seed rows).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260803120000_merchant_category_map.sql lib/core/services/merchant_category_seed.dart test/core/services/merchant_category_seed_test.dart
git commit -m "feat: add merchant_category_map table and India/UAE merchant seed data"
```

---

## Task 2: `bank_market.dart` — resolve currency/market from bank name

This fills a gap found during investigation: `CardNormalizerService` only
recognizes Indian banks (`lib/core/services/card_normalizer_service.dart`),
so there's currently no way to tell whether a parsed statement is from an
Indian or UAE bank. Needed both to fix the currency-default bug and to
support UAE statement parsing at all going forward — right now a UAE bank
name falls through to `normalizeBankName`'s generic title-case fallback.

**Files:**
- Modify: `lib/core/services/card_normalizer_service.dart:4-38`
- Create: `lib/core/services/bank_market.dart`
- Test: `test/core/services/bank_market_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/bank_market_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/bank_market.dart';

void main() {
  group('currencyForBank', () {
    test('returns INR for Indian banks', () {
      expect(currencyForBank('HDFC Bank'), 'INR');
      expect(currencyForBank('SBI Card'), 'INR');
      expect(currencyForBank('ICICI Bank'), 'INR');
      expect(currencyForBank('Axis Bank'), 'INR');
    });

    test('returns AED for UAE banks', () {
      expect(currencyForBank('FAB'), 'AED');
      expect(currencyForBank('Emirates NBD'), 'AED');
      expect(currencyForBank('ADCB'), 'AED');
      expect(currencyForBank('Mashreq'), 'AED');
      expect(currencyForBank('Dubai Islamic Bank'), 'AED');
    });

    test('defaults to INR for an unrecognized bank name', () {
      expect(currencyForBank('Some New Bank'), 'INR');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/bank_market_test.dart`
Expected: FAIL — `bank_market.dart` doesn't exist, import error.

- [ ] **Step 3: Add UAE bank recognition to `CardNormalizerService.normalizeBankName`**

Current content of `lib/core/services/card_normalizer_service.dart:4-38`
(read it fresh before editing — it's not one of the 6 files with
pre-existing uncommitted changes, so it should match what's shown at the
top of this plan under Task 2's context, but verify). Add UAE banks
alongside the existing Indian ones, inserting after the last Indian-bank
`if` and before the generic fallback:

```dart
  /// Normalize a bank name to a canonical form to prevent duplicates
  static String normalizeBankName(String rawName) {
    final lower = rawName.toLowerCase();

    if (lower.contains('hdfc')) return 'HDFC Bank';
    if (lower.contains('sbi')) return 'SBI Card';
    if (lower.contains('axis')) return 'Axis Bank';

    if (lower.contains('amazon') && lower.contains('icici')) return 'Amazon ICICI Bank';
    if (lower.contains('icici')) return 'ICICI Bank';

    if (lower.contains('kotak')) return 'Kotak Bank';
    if (lower.contains('idfc')) return 'IDFC FIRST Bank';
    if (lower.contains('yes')) return 'Yes Bank';
    if (lower.contains('au ')) return 'AU Small Finance Bank';
    if (lower.contains('indusind')) return 'IndusInd Bank';
    if (lower.contains('standard chartered')) return 'Standard Chartered';
    if (lower.contains('american express') || lower.contains('amex')) return 'American Express';
    if (lower.contains('citi')) return 'Citibank';
    if (lower.contains('hsbc')) return 'HSBC';
    if (lower.contains('rbl')) return 'RBL Bank';
    if (lower.contains('federal')) return 'Federal Bank';
    if (lower.contains('karur vysya')) return 'Karur Vysya Bank';
    if (lower.contains('bob') || lower.contains('bank of baroda')) return 'Bank of Baroda';
    if (lower.contains('canara')) return 'Canara Bank';
    if (lower.contains('pnb') || lower.contains('punjab national')) return 'Punjab National Bank';
    if (lower.contains('union bank')) return 'Union Bank of India';
    if (lower.contains('indian bank')) return 'Indian Bank';
    if (lower.contains('central bank')) return 'Central Bank of India';
    if (lower.contains('indian overseas')) return 'Indian Overseas Bank';
    if (lower.contains('allahabad') || lower.contains('indian')) return 'Indian Bank';

    // UAE banks
    if (lower.contains('fab') || lower.contains('first abu dhabi')) return 'FAB';
    if (lower.contains('emirates nbd')) return 'Emirates NBD';
    if (lower.contains('adcb') || lower.contains('abu dhabi commercial')) return 'ADCB';
    if (lower.contains('mashreq')) return 'Mashreq';
    if (lower.contains('cbd') || lower.contains('commercial bank of dubai')) return 'CBD';
    if (lower.contains('dib') || lower.contains('dubai islamic')) return 'Dubai Islamic Bank';
    if (lower.contains('rakbank') || lower.contains('rak bank')) return 'RAKBANK';
    if (lower.contains('emirates islamic')) return 'Emirates Islamic';
    if (lower.contains('hsbc uae') || lower.contains('hsbc middle east')) return 'HSBC UAE';
    if (lower.contains('citibank uae') || lower.contains('citi uae')) return 'Citibank UAE';

    return rawName.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }
```

Note: `'hsbc uae'`/`'citi uae'` checks are placed before the plain
`'hsbc'`/`'citi'` Indian-bank checks would be reached — but since Dart
evaluates `if` statements top-to-bottom and the Indian `hsbc`/`citi` checks
come first in the existing code, a UAE HSBC/Citibank statement whose raw
name doesn't explicitly say "UAE" (e.g. just `"HSBC"` as the sender name)
will incorrectly normalize to the Indian entity. This is a real ambiguity
in bank-name-only detection that the plan can't fully resolve (see Step 4);
`currencyForBank` places the specific-first UAE checks ahead of the
generic ones for the banks that are unambiguous (FAB, Emirates NBD, ADCB,
Mashreq, CBD, RAKBANK have no Indian namesake), and accepts that
shared-brand banks (HSBC, Citibank) need the statement to say "UAE" in the
sender/subject to disambiguate — which is the actual real-world case,
since bank emails include their region.

- [ ] **Step 4: Write `bank_market.dart`**

```dart
// lib/core/services/bank_market.dart

/// UAE banks currently recognized by `CardNormalizerService.normalizeBankName`.
/// Kept as its own small list here (rather than exposing internals of
/// CardNormalizerService) so `currencyForBank` has one place to check —
/// takes an already-normalized bank name (the canonical form
/// `normalizeBankName` returns), not a raw sender/subject string.
const Set<String> _uaeBanks = {
  'FAB',
  'Emirates NBD',
  'ADCB',
  'Mashreq',
  'CBD',
  'Dubai Islamic Bank',
  'RAKBANK',
  'Emirates Islamic',
  'HSBC UAE',
  'Citibank UAE',
};

/// The currency a bank's statements are denominated in, given its
/// already-normalized name (from `CardNormalizerService.normalizeBankName`).
/// Defaults to INR for any name not recognized as a UAE bank — matches this
/// app's original single-market assumption, now made explicit and
/// overridable rather than hardcoded on the Transaction model itself.
String currencyForBank(String normalizedBankName) {
  return _uaeBanks.contains(normalizedBankName) ? 'AED' : 'INR';
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/services/bank_market_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/card_normalizer_service.dart lib/core/services/bank_market.dart test/core/services/bank_market_test.dart
git commit -m "feat: recognize UAE banks and resolve statement currency by bank market"
```

---

## Task 3: `transaction_categorizer.dart` — the rule-first, LLM-second, keyword-fallback logic

**Files:**
- Create: `lib/core/services/transaction_categorizer.dart`
- Test: `test/core/services/transaction_categorizer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/transaction_categorizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/transaction_categorizer.dart';

void main() {
  group('normalizeMerchantName', () {
    test('uppercases and trims', () {
      expect(normalizeMerchantName('  Swiggy  '), 'SWIGGY');
    });

    test('collapses internal whitespace', () {
      expect(normalizeMerchantName('Big   Basket'), 'BIG BASKET');
    });
  });

  group('isValidCategory', () {
    test('accepts all 16 valid categories', () {
      const valid = {
        'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
        'utilities', 'insurance', 'medical', 'education', 'investment',
        'transport', 'rental', 'subscription', 'gift', 'other',
      };
      for (final c in valid) {
        expect(isValidCategory(c), isTrue, reason: c);
      }
    });

    test('rejects legacy vocabulary values', () {
      expect(isValidCategory('bills'), isFalse);
      expect(isValidCategory('transfer'), isFalse);
      expect(isValidCategory('fee'), isFalse);
      expect(isValidCategory('payment'), isFalse);
      expect(isValidCategory('cash'), isFalse);
    });

    test('rejects null and empty', () {
      expect(isValidCategory(null), isFalse);
      expect(isValidCategory(''), isFalse);
    });

    test('is case-insensitive', () {
      expect(isValidCategory('FOOD'), isTrue);
      expect(isValidCategory('Food'), isTrue);
    });
  });

  group('keywordCategoryFor', () {
    test('matches Indian merchant keywords in description', () {
      expect(keywordCategoryFor('SWIGGY ORDER #1234'), 'food');
      expect(keywordCategoryFor('PAYMENT TO ZOMATO LTD'), 'food');
      expect(keywordCategoryFor('AMAZON.IN PURCHASE'), 'shopping');
      expect(keywordCategoryFor('OLA CABS TRIP'), 'transport');
      expect(keywordCategoryFor('INDIAN OIL PETROL PUMP'), 'fuel');
    });

    test('matches UAE merchant keywords in description', () {
      expect(keywordCategoryFor('CARREFOUR HYPERMARKET DUBAI'), 'grocery');
      expect(keywordCategoryFor('TALABAT DELIVERY'), 'food');
      expect(keywordCategoryFor('CAREEM RIDE'), 'transport');
      expect(keywordCategoryFor('ADNOC FUEL STATION'), 'fuel');
    });

    test('matches generic category keywords not tied to a specific merchant', () {
      expect(keywordCategoryFor('RESTAURANT BILL PAYMENT'), 'food');
      expect(keywordCategoryFor('PHARMACY PURCHASE'), 'medical');
      expect(keywordCategoryFor('HOSPITAL CONSULTATION FEE'), 'medical');
      expect(keywordCategoryFor('ELECTRICITY BILL PAYMENT'), 'utilities');
      expect(keywordCategoryFor('INSURANCE PREMIUM'), 'insurance');
    });

    test('returns null when nothing matches', () {
      expect(keywordCategoryFor('XYZ CORP TRANSACTION 998271'), isNull);
    });

    test('is case-insensitive', () {
      expect(keywordCategoryFor('swiggy order'), 'food');
    });
  });

  group('categorize', () {
    test('merchant lookup takes priority over a valid Gemini-provided category', () {
      final result = categorize(
        merchantName: 'Carrefour',
        description: 'CARREFOUR HYPERMARKET',
        geminiCategory: 'shopping', // Gemini's own guess, deliberately wrong
        merchantLookup: (normalized) => normalized == 'CARREFOUR' ? 'grocery' : null,
      );
      expect(result.category, 'grocery');
      expect(result.source, CategorizationSource.merchantMap);
    });

    test("falls through to Gemini's category when it's valid and no merchant match", () {
      final result = categorize(
        merchantName: 'Some New Restaurant',
        description: 'SOME NEW RESTAURANT PAYMENT',
        geminiCategory: 'dining', // not in our 16 — see next test for the actual valid case
        merchantLookup: (_) => null,
      );
      // 'dining' isn't one of the 16 valid categories (it's 'food'), so this
      // should NOT be trusted and falls through to keyword matching instead.
      expect(result.category, 'food'); // matched via 'restaurant' keyword
      expect(result.source, CategorizationSource.keywordFallback);
    });

    test("trusts Gemini's category when it IS one of the 16 valid values", () {
      final result = categorize(
        merchantName: 'Some New Merchant',
        description: 'SOME NEW MERCHANT XYZ',
        geminiCategory: 'travel',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'travel');
      expect(result.source, CategorizationSource.geminiValidated);
    });

    test('falls through to keyword matching when Gemini category is invalid', () {
      final result = categorize(
        merchantName: 'Some Fuel Stop',
        description: 'INDIAN OIL FUEL PURCHASE',
        geminiCategory: 'cash', // legacy/invalid value
        merchantLookup: (_) => null,
      );
      expect(result.category, 'fuel');
      expect(result.source, CategorizationSource.keywordFallback);
    });

    test('falls through to keyword matching when Gemini category is null', () {
      final result = categorize(
        merchantName: 'Netflix',
        description: 'NETFLIX SUBSCRIPTION',
        geminiCategory: null,
        merchantLookup: (_) => null,
      );
      expect(result.category, 'entertainment');
      expect(result.source, CategorizationSource.keywordFallback);
    });

    test('returns other with unresolved source when nothing matches anything', () {
      final result = categorize(
        merchantName: 'XYZ Corp',
        description: 'XYZ CORP TRANSACTION 998271',
        geminiCategory: null,
        merchantLookup: (_) => null,
      );
      expect(result.category, 'other');
      expect(result.source, CategorizationSource.unresolved);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/transaction_categorizer_test.dart`
Expected: FAIL — `transaction_categorizer.dart` doesn't exist, import error.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/services/transaction_categorizer.dart
import 'merchant_category_seed.dart';

const Set<String> validCategories = {
  'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
  'utilities', 'insurance', 'medical', 'education', 'investment',
  'transport', 'rental', 'subscription', 'gift', 'other',
};

/// Where a transaction's resolved category came from — persisted alongside
/// the category when writing a new merchant->category row, and useful for
/// debugging/auditing which tier is actually doing the work over time.
enum CategorizationSource { merchantMap, geminiValidated, keywordFallback, unresolved }

class CategorizationResult {
  final String category;
  final CategorizationSource source;
  const CategorizationResult(this.category, this.source);
}

/// Normalizes a merchant name for lookup: uppercase, trimmed, internal
/// whitespace collapsed to single spaces. Must match how
/// `merchant_category_seed.dart`'s keys and any runtime-written rows are
/// normalized, so lookups actually hit.
String normalizeMerchantName(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Whether [category] (case-insensitive) is one of the 16 categories this
/// app recognizes. Used to decide whether to trust Gemini's own per-transaction
/// category guess (see `categorize`) rather than assuming its prompt
/// instructions were followed exactly.
bool isValidCategory(String? category) {
  if (category == null || category.isEmpty) return false;
  return validCategories.contains(category.toLowerCase());
}

/// Keyword phrases that, if found anywhere in a transaction description,
/// indicate a category — used as the last-resort tier when neither a
/// merchant-map match nor Gemini's own category value is usable. Order
/// matters only in that the first match wins; kept specific-merchant-name
/// keywords and generic category words in one list since a description can
/// contain either (a statement line might say "SWIGGY" or just "RESTAURANT").
const List<(String keyword, String category)> _keywordCategoryRules = [
  // Food
  ('SWIGGY', 'food'), ('ZOMATO', 'food'), ('TALABAT', 'food'),
  ('DELIVEROO', 'food'), ('RESTAURANT', 'food'), ('CAFE', 'food'),
  // Grocery
  ('CARREFOUR', 'grocery'), ('LULU', 'grocery'), ('BIGBASKET', 'grocery'),
  ('SUPERMARKET', 'grocery'), ('HYPERMARKET', 'grocery'),
  // Shopping
  ('AMAZON', 'shopping'), ('FLIPKART', 'shopping'), ('NOON', 'shopping'),
  ('MYNTRA', 'shopping'),
  // Transport
  ('OLA', 'transport'), ('UBER', 'transport'), ('CAREEM', 'transport'),
  ('METRO', 'transport'), ('CAB', 'transport'),
  // Fuel
  ('PETROL', 'fuel'), ('FUEL', 'fuel'), ('ADNOC', 'fuel'), ('ENOC', 'fuel'),
  ('INDIAN OIL', 'fuel'), ('HPCL', 'fuel'),
  // Entertainment
  ('NETFLIX', 'entertainment'), ('SPOTIFY', 'entertainment'),
  ('CINEMA', 'entertainment'), ('MOVIE', 'entertainment'),
  // Travel
  ('AIRLINE', 'travel'), ('MAKEMYTRIP', 'travel'), ('EMIRATES', 'travel'),
  ('BOOKING.COM', 'travel'), ('AIRBNB', 'travel'), ('HOTEL', 'travel'),
  // Utilities
  ('ELECTRICITY', 'utilities'), ('DEWA', 'utilities'), ('ETISALAT', 'utilities'),
  ('WATER BILL', 'utilities'),
  // Medical
  ('PHARMACY', 'medical'), ('HOSPITAL', 'medical'), ('CLINIC', 'medical'),
  // Insurance
  ('INSURANCE', 'insurance'), ('PREMIUM', 'insurance'),
  // Education
  ('SCHOOL FEE', 'education'), ('TUITION', 'education'), ('UDEMY', 'education'),
  // Subscription
  ('SUBSCRIPTION', 'subscription'),
];

/// Scans [description] for known keyword phrases (see
/// `_keywordCategoryRules`), returning the first match's category, or null
/// if nothing matches. Case-insensitive.
String? keywordCategoryFor(String description) {
  final upper = description.toUpperCase();
  for (final (keyword, category) in _keywordCategoryRules) {
    if (upper.contains(keyword)) return category;
  }
  return null;
}

/// Resolves a transaction's category through three tiers, in priority
/// order:
/// 1. Merchant lookup ([merchantLookup]) — deterministic, wins even over a
///    Gemini-provided value, since a known merchant is more reliable than a
///    per-call LLM guess.
/// 2. Gemini's own [geminiCategory], trusted only when it's one of the 16
///    valid categories — Gemini's prompt asks for the right vocabulary but
///    isn't guaranteed to comply.
/// 3. Keyword matching against [description] — last resort when neither of
///    the above resolves anything.
///
/// [merchantLookup] is injected (rather than this function querying
/// `merchant_category_map` directly) so this whole decision tree stays pure
/// and unit-testable without a Supabase client. The caller (see
/// `statement_processing_service.dart`) supplies a real lookup backed by
/// the seed map plus any runtime-learned rows, and is responsible for
/// writing a new row back to `merchant_category_map` when the result came
/// from `keywordFallback` (source == CategorizationSource.keywordFallback)
/// so future lookups of that same merchant hit tier 1 instead.
CategorizationResult categorize({
  required String merchantName,
  required String description,
  required String? geminiCategory,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  final normalized = normalizeMerchantName(merchantName);
  final mapped = merchantLookup(normalized);
  if (mapped != null) {
    return CategorizationResult(mapped, CategorizationSource.merchantMap);
  }

  if (isValidCategory(geminiCategory)) {
    return CategorizationResult(geminiCategory!.toLowerCase(), CategorizationSource.geminiValidated);
  }

  final keywordMatch = keywordCategoryFor(description);
  if (keywordMatch != null) {
    return CategorizationResult(keywordMatch, CategorizationSource.keywordFallback);
  }

  return const CategorizationResult('other', CategorizationSource.unresolved);
}
```

Note: `merchant_category_seed.dart` is imported but not directly referenced
in this file's logic — remove the unused import, since the seed map is
consumed by the *caller's* `merchantLookup` function (see Task 4), not by
`categorize` itself. Fix before running tests:

```dart
// Remove this line from the top of lib/core/services/transaction_categorizer.dart:
import 'merchant_category_seed.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/transaction_categorizer_test.dart`
Expected: PASS (all groups)

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/transaction_categorizer.dart test/core/services/transaction_categorizer_test.dart
git commit -m "feat: add pure categorization logic (merchant lookup, Gemini validation, keyword fallback)"
```

---

## Task 4: Fix Gemini's prompt vocabulary

**Files:**
- Modify: `lib/core/services/gemini_statement_parser.dart:209`

- [ ] **Step 1: Update the prompt's category vocabulary**

Current file state at the top of this plan's context shows line 209 as:

```dart
    "category": "shopping|dining|travel|fuel|entertainment|bills|transfer|fee|payment|cash|other",
```

Replace with the full 16-category vocabulary, dropping the four
transaction-type values that don't belong in a category field
(`transfer`, `fee`, `payment`, `cash` — already captured by
`TransactionType` elsewhere):

```dart
    "category": "food|fuel|grocery|entertainment|travel|shopping|utilities|insurance|medical|education|investment|transport|rental|subscription|gift|other",
```

This is a single-line change inside the existing prompt string in
`parseTransactions()` — read the file fresh first (it's one of the 6 files
with pre-existing uncommitted changes) to confirm line 209 still matches
what's shown here before editing; if the surrounding prompt text changed,
locate the `"category":` line by searching for it rather than trusting the
line number.

- [ ] **Step 2: There's no automated test for this — Gemini's actual output isn't unit-testable**

This change only affects what Gemini is *asked* to return; whether it
complies is exactly why Task 3's `isValidCategory` check and keyword
fallback exist. No test needed here — the categorizer's own tests (Task 3)
already cover both the "Gemini complies" and "Gemini doesn't comply" cases.

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/gemini_statement_parser.dart
git commit -m "fix: correct Gemini category prompt vocabulary to match the 16 valid categories"
```

---

## Task 5: Wire the categorizer and currency fix into `TransactionsRepository`

**Files:**
- Modify: `lib/core/repositories/transactions_repository.dart`
- Test: `test/core/repositories/transactions_repository_category_test.dart`

This task changes `TransactionsRepository.addTransaction`'s signature
(`currency` default removed — callers must now pass it explicitly) and adds
two new methods: a merchant lookup backed by the real table (for Task 6 to
inject into `categorize()`), and an update-by-id method the backfill job
(Task 8) needs, since `addTransaction`'s upsert-with-`ignoreDuplicates`
can't update an existing row's category.

- [ ] **Step 1: Write the failing test**

Since this repository talks to Supabase directly and this project has no
mocking library, this test targets only the parts of the class that don't
require a live `SupabaseClient` — the merchant-lookup row-shape parsing
logic, extracted into a small pure function first.

```dart
// test/core/repositories/transactions_repository_category_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/transactions_repository.dart';

void main() {
  group('parseMerchantCategoryRow', () {
    test('extracts category from a valid row', () {
      expect(parseMerchantCategoryRow({'category': 'grocery'}), 'grocery');
    });

    test('returns null for an empty result', () {
      expect(parseMerchantCategoryRow(null), isNull);
    });

    test('returns null when category field is missing', () {
      expect(parseMerchantCategoryRow({'merchant_name_normalized': 'CARREFOUR'}), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/repositories/transactions_repository_category_test.dart`
Expected: FAIL — `parseMerchantCategoryRow` undefined.

- [ ] **Step 3: Update `transactions_repository.dart`**

Current full file content is shown at the top of this plan's context.
Replace the whole file:

```dart
// lib/core/repositories/transactions_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/transaction.dart';

/// Pulled out of TransactionsRepository so it's testable without a
/// SupabaseClient: given a `merchant_category_map` row (or null, if no row
/// matched), extract the category value.
String? parseMerchantCategoryRow(Map<String, dynamic>? row) {
  if (row == null) return null;
  return row['category'] as String?;
}

class TransactionsRepository {
  final SupabaseClient _db;
  TransactionsRepository(this._db);

  Future<List<Transaction>> getTransactions({
    required String userId,
    String? userCardId,
    DateTime? from,
    DateTime? to,
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _db
        .from('transactions')
        .select()
        .eq('user_id', userId);

    if (userCardId != null) query = query.eq('user_card_id', userCardId);
    if (from != null) query = query.gte('transaction_date', from.toIso8601String());
    if (to != null) query = query.lte('transaction_date', to.toIso8601String());
    if (category != null) query = query.eq('category', category);

    final data = await query
        .order('transaction_date', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Transaction>> getRecentTransactions(String userId, {int limit = 10}) async {
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('transaction_date', ascending: false)
        .limit(limit);
    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Total spend for current month, grouped by category
  Future<Map<String, double>> getMonthlySpendByCategory(String userId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final txns = await getTransactions(
      userId: userId,
      from: start,
      to: now,
      limit: 500,
    );
    final map = <String, double>{};
    for (final t in txns) {
      if (!t.isDebit) continue;
      final cat = t.category ?? 'Other';
      map[cat] = (map[cat] ?? 0) + t.amount;
    }
    return map;
  }

  /// Looks up a merchant's category from `merchant_category_map`, by its
  /// already-normalized name (see `normalizeMerchantName` in
  /// transaction_categorizer.dart — callers must normalize before calling
  /// this). Returns null if the merchant isn't in the table yet.
  Future<String?> lookupMerchantCategory(String normalizedMerchantName) async {
    final row = await _db
        .from('merchant_category_map')
        .select('category')
        .eq('merchant_name_normalized', normalizedMerchantName)
        .maybeSingle();
    return parseMerchantCategoryRow(row);
  }

  /// Records a newly-learned merchant->category mapping via the
  /// `upsert_merchant_category` RPC (see the migration in Task 1) — a plain
  /// insert would fail under RLS, since only SELECT is granted directly on
  /// the table. Never overwrites an existing row (first categorization
  /// wins) — the RPC itself is ON CONFLICT DO NOTHING.
  Future<void> recordLearnedMerchantCategory({
    required String normalizedMerchantName,
    required String category,
    required String source,
  }) async {
    await _db.rpc('upsert_merchant_category', params: {
      'p_merchant_name_normalized': normalizedMerchantName,
      'p_category': category,
      'p_source': source,
    });
  }

  /// Insert one transaction. Silently skips if a row with the same
  /// (user_id, user_card_id, transaction_date, description, amount) already
  /// exists — this project's dedup key, matching main's
  /// idx_transactions_dedup unique index.
  ///
  /// [currency] is now required (no default) — callers must resolve it via
  /// `currencyForBank` (bank_market.dart) rather than relying on a
  /// hardcoded assumption here. This is a breaking change to this method's
  /// signature; the one caller in this codebase
  /// (statement_processing_service.dart) is updated in the same plan (see
  /// Task 6).
  Future<void> addTransaction({
    required String userId,
    required String userCardId,
    required double amount,
    required String description,
    required DateTime transactionDate,
    required String currency,
    String? merchantName,
    String? category,
    String transactionType = 'debit',
    String? location,
    double? rewardEarned,
    String? rewardType,
    String? statementId,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.from('transactions').upsert(
      {
        'user_id': userId,
        'user_card_id': userCardId,
        'amount': amount,
        'description': description,
        'transaction_date': transactionDate.toIso8601String(),
        'currency': currency,
        'merchant_name': merchantName,
        'category': category,
        'transaction_type': transactionType,
        'location': location,
        'reward_earned': rewardEarned,
        'reward_type': rewardType,
        'statement_id': statementId,
        'metadata': metadata,
      },
      onConflict: 'user_id,user_card_id,transaction_date,description,amount',
      ignoreDuplicates: true,
    );
  }

  /// Every transaction currently categorized as 'other' for [userId] — the
  /// backfill job's input set (see category_backfill_service.dart, Task 8).
  /// Unlike `getTransactions`, this has no limit/offset — the backfill job
  /// needs the complete set to process, not a page of it.
  Future<List<Transaction>> getUncategorizedTransactions(String userId) async {
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .eq('category', 'other');
    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Updates just the category column for an existing transaction by id —
  /// used by the backfill job. `addTransaction`'s upsert with
  /// ignoreDuplicates can't be reused here: it silently no-ops on a
  /// dedup-key conflict rather than updating, which is exactly what a
  /// backfill needs to do for a row that already exists.
  Future<void> updateTransactionCategory({
    required String transactionId,
    required String category,
  }) async {
    await _db.from('transactions').update({'category': category}).eq('id', transactionId);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/repositories/transactions_repository_category_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Fix the one existing caller broken by the signature change**

`addTransaction`'s `currency` parameter is now required. Search for every
call site before moving on:

Run: `grep -rn "\.addTransaction(" lib/`
Expected: one match, in `lib/core/services/statement_processing_service.dart`
— fixed in Task 6, which also needs to change for the categorizer wiring,
so don't fix it here in isolation; Task 6 handles it as part of the same
edit. Confirm this grep result now so Task 6 isn't a surprise — if it finds
additional call sites beyond `statement_processing_service.dart`, note them
and update this plan's Task 6 to cover them too before proceeding.

- [ ] **Step 6: Commit**

```bash
git add lib/core/repositories/transactions_repository.dart test/core/repositories/transactions_repository_category_test.dart
git commit -m "feat: add merchant-category lookup/write methods, category-only update, require explicit currency"
```

Note: this commit leaves `statement_processing_service.dart` temporarily
broken (calls `addTransaction` without `currency`) — that's fixed in the
very next task. If your workflow requires every commit to compile, squash
Tasks 5 and 6 into one commit instead; this plan keeps them separate
because they're conceptually distinct (repository layer vs. call-site
wiring) and Task 6 is easier to review on its own.

---

## Task 6: Wire the categorizer + currency resolution into statement processing

**Files:**
- Modify: `lib/core/services/statement_processing_service.dart:384-474` (`_persistParsedStatement`)

- [ ] **Step 1: There's no new unit test in this task**

`_persistParsedStatement` orchestrates Supabase repositories end-to-end and
has no existing test coverage to extend (confirmed: no
`statement_processing_service_test.dart` exists in this project). The pure
logic it now calls into (`categorize()`, `currencyForBank()`,
`normalizeMerchantName()`) is already fully tested in Tasks 2 and 3. Adding
a test harness for this orchestration method (which would need a live or
mocked Supabase client, and this project has no mocking library) is out of
scope for this plan — flag it as a gap rather than silently skipping it:

This is a real test-coverage gap worth a follow-up if the team later adds a
mocking library (`mocktail` is the natural fit, given the rest of the
project's style) — not fixed here since introducing a new
testing-infrastructure dependency is a bigger decision than this plan's
scope.

- [ ] **Step 2: Update `_persistParsedStatement`**

Current content shown at the top of this plan's context
(`statement_processing_service.dart:384-474`). Add the two new imports at
the top of the file, alongside the existing ones:

```dart
import 'transaction_categorizer.dart';
import 'bank_market.dart';
```

Replace the transaction-persisting loop (currently lines 430-446):

```dart
      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: txn['description'] as String? ?? 'Unknown transaction',
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          merchantName: txn['merchantName'] as String?,
          category: txn['category'] as String?,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
        );
      }
```

with:

```dart
      final currency = currencyForBank(bankName);

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        final description = txn['description'] as String? ?? 'Unknown transaction';
        final merchantName = txn['merchantName'] as String? ?? description;

        final result = categorize(
          merchantName: merchantName,
          description: description,
          geminiCategory: txn['category'] as String?,
          merchantLookup: _merchantCategoryCache.lookup,
        );

        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: description,
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          currency: currency,
          merchantName: txn['merchantName'] as String?,
          category: result.category,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
        );

        if (result.source == CategorizationSource.keywordFallback) {
          await _transactionsRepo.recordLearnedMerchantCategory(
            normalizedMerchantName: normalizeMerchantName(merchantName),
            category: result.category,
            source: 'keyword_fallback',
          );
        }
      }
```

Note the distinction between `merchantName` (used for `categorize()`'s
merchant argument — falls back to `description` when Gemini didn't provide
one, since `categorize` always needs *some* string to normalize and look
up) and the `merchantName: txn['merchantName'] as String?` still passed to
`addTransaction` (unchanged — stores the true nullable value in the
database column, not the fallback-to-description value, since those are
different concerns: "what do we categorize by" vs. "what do we display as
the merchant name").

`_merchantCategoryCache` is a new field — add it to the class, right after
the existing repository fields (`lib/core/services/statement_processing_service.dart:36-44`):

```dart
  final GmailSyncService _gmailService;
  final EmailRepository _emailRepo;
  final StatementsRepository _statementsRepo;
  final TransactionsRepository _transactionsRepo;
  final CardsRepository _cardsRepo;
  final String _userId;
  final String _userEmail;
  final String _userName;
  final Map<String, String> _forcedCardIdByBank;
  final _MerchantCategoryCache _merchantCategoryCache;
```

And initialize it in the constructor, alongside the existing field
initializations (`lib/core/services/statement_processing_service.dart:57-65`):

```dart
  StatementProcessingService({
    required GmailSyncService gmailService,
    required SupabaseClient supabaseClient,
    required String userId,
    required String userEmail,
    required String userName,
    Map<String, String> forcedCardIdByBank = const {},
  })  : _gmailService = gmailService,
        _emailRepo = EmailRepository(),
        _statementsRepo = StatementsRepository(supabaseClient),
        _transactionsRepo = TransactionsRepository(supabaseClient),
        _cardsRepo = CardsRepository(supabaseClient),
        _userId = userId,
        _userEmail = userEmail,
        _userName = userName,
        _forcedCardIdByBank = forcedCardIdByBank,
        _merchantCategoryCache = _MerchantCategoryCache(TransactionsRepository(supabaseClient));
```

Add the small cache helper class at the bottom of the file, after the
closing brace of `StatementProcessingService`:

```dart
/// `categorize()`'s merchantLookup callback must be synchronous (it's pure,
/// testable logic with no async dependency), but the real lookup is a
/// Supabase call. This bridges the two: within one
/// `processUnprocessedEmails()`/`processSpecificEmail()` run, `warmUp` is
/// called once per unique merchant the first time it's seen, then `lookup`
/// (sync) serves every subsequent call from the in-memory cache — so a
/// statement with 50 transactions from the same 10 merchants only makes 10
/// Supabase round-trips, not 50, and `categorize()` itself never needs to
/// be async.
class _MerchantCategoryCache {
  final TransactionsRepository _repo;
  final Map<String, String?> _cache = {};

  _MerchantCategoryCache(this._repo);

  Future<void> warmUp(String normalizedMerchantName) async {
    if (_cache.containsKey(normalizedMerchantName)) return;
    _cache[normalizedMerchantName] = await _repo.lookupMerchantCategory(normalizedMerchantName);
  }

  String? lookup(String normalizedMerchantName) => _cache[normalizedMerchantName];
}
```

This means the loop needs one more line before calling `categorize()` — to
warm the cache first. Revise the loop body from Step 2 above: insert
`await _merchantCategoryCache.warmUp(normalizeMerchantName(merchantName));`
immediately before the `categorize(...)` call:

```dart
      final currency = currencyForBank(bankName);

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        final description = txn['description'] as String? ?? 'Unknown transaction';
        final merchantName = txn['merchantName'] as String? ?? description;
        final normalizedMerchant = normalizeMerchantName(merchantName);

        await _merchantCategoryCache.warmUp(normalizedMerchant);
        final result = categorize(
          merchantName: merchantName,
          description: description,
          geminiCategory: txn['category'] as String?,
          merchantLookup: _merchantCategoryCache.lookup,
        );

        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: description,
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          currency: currency,
          merchantName: txn['merchantName'] as String?,
          category: result.category,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
        );

        if (result.source == CategorizationSource.keywordFallback) {
          await _transactionsRepo.recordLearnedMerchantCategory(
            normalizedMerchantName: normalizedMerchant,
            category: result.category,
            source: 'keyword_fallback',
          );
        }
      }
```

- [ ] **Step 3: Verify the app still analyzes cleanly**

Run: `flutter analyze lib/core/services/statement_processing_service.dart`
Expected: No errors (warnings about the pre-existing uncommitted changes in
this file, if any, are not this task's concern).

- [ ] **Step 4: Run the full test suite to confirm nothing else broke**

Run: `flutter test`
Expected: All tests pass, including Tasks 1-5's new tests and the two
pre-existing test files (`movie_deal_rule_test.dart`, `widget_test.dart`).

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/statement_processing_service.dart
git commit -m "feat: wire merchant-lookup/Gemini-validation/keyword-fallback categorizer and currency resolution into statement persistence"
```

---

## Task 7: Add `isInternational` to `Transaction`

**Files:**
- Modify: `lib/shared/models/transaction.dart`
- Test: `test/shared/models/transaction_is_international_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/models/transaction_is_international_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({required String currency, required String bankMarketCurrency}) {
  return Transaction(
    id: 't1',
    userId: 'u1',
    userCardId: 'c1',
    amount: 100,
    currency: currency,
    description: 'test',
    transactionType: TransactionType.debit,
    transactionDate: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('Transaction.isInternational', () {
    test('false when currency matches the bank market currency', () {
      final tx = _tx(currency: 'INR', bankMarketCurrency: 'INR');
      expect(tx.isInternational('INR'), isFalse);
    });

    test('true when currency differs from the bank market currency', () {
      final tx = _tx(currency: 'USD', bankMarketCurrency: 'INR');
      expect(tx.isInternational('INR'), isTrue);
    });

    test('true for a foreign-currency charge on a UAE-market statement', () {
      final tx = _tx(currency: 'EUR', bankMarketCurrency: 'AED');
      expect(tx.isInternational('AED'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/models/transaction_is_international_test.dart`
Expected: FAIL — `isInternational` undefined on `Transaction`.

- [ ] **Step 3: Add the method**

Current full file content is shown near the top of this plan (under Task
1's investigation notes) — 74 lines. Add this method inside the
`Transaction` class, right after the existing `isDebit` getter
(`lib/shared/models/transaction.dart:40`):

```dart
  bool get isDebit => transactionType == TransactionType.debit;

  /// Whether this transaction's currency differs from [bankMarketCurrency]
  /// — the currency the issuing bank's statements are normally denominated
  /// in (see `currencyForBank` in bank_market.dart). A foreign-currency
  /// charge (e.g. a USD hotel booking on an otherwise-INR statement) is
  /// international; a same-currency charge isn't. This is independent of
  /// `category` — a transaction can be both "dining" and international.
  ///
  /// Takes [bankMarketCurrency] as a parameter rather than storing it on
  /// the transaction itself: the market currency is a property of the
  /// *bank/card* this transaction belongs to, not of the transaction row,
  /// and this app has no per-transaction denormalized copy of that today.
  /// Callers resolve it via `currencyForBank(bankName)` where the bank name
  /// is already known (e.g. from the card the transaction's `userCardId`
  /// belongs to).
  bool isInternational(String bankMarketCurrency) => currency != bankMarketCurrency;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/models/transaction_is_international_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/shared/models/transaction.dart test/shared/models/transaction_is_international_test.dart
git commit -m "feat: add Transaction.isInternational signal, independent of category"
```

---

## Task 8: Backfill service for existing transactions

**Files:**
- Create: `lib/core/services/category_backfill_service.dart`
- Test: `test/core/services/category_backfill_service_test.dart`

- [ ] **Step 1: Write the failing test**

The service's core re-categorization decision (given a transaction's stored
`merchantName`/`description`, what should its category become) is pure and
testable without touching Supabase — the orchestration around it (fetching
the `other`-bucketed rows, calling `updateTransactionCategory`) isn't, for
the same reason Task 6's orchestration code isn't: no mocking library in
this project. Test the pure decision function directly:

```dart
// test/core/services/category_backfill_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/category_backfill_service.dart';

void main() {
  group('recategorize', () {
    test('resolves a known merchant via the categorizer', () {
      final result = recategorize(
        merchantName: 'Carrefour',
        description: 'CARREFOUR HYPERMARKET DUBAI',
        merchantLookup: (normalized) => normalized == 'CARREFOUR' ? 'grocery' : null,
      );
      expect(result, 'grocery');
    });

    test('falls through to keyword matching for an unmapped merchant', () {
      final result = recategorize(
        merchantName: 'Some Petrol Station',
        description: 'PETROL PUMP PAYMENT',
        merchantLookup: (_) => null,
      );
      expect(result, 'fuel');
    });

    test('returns other when nothing resolves, same as a fresh transaction would', () {
      final result = recategorize(
        merchantName: 'XYZ Corp',
        description: 'XYZ CORP TRANSACTION 998271',
        merchantLookup: (_) => null,
      );
      expect(result, 'other');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/category_backfill_service_test.dart`
Expected: FAIL — `category_backfill_service.dart` doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/services/category_backfill_service.dart
import 'transaction_categorizer.dart';
import '../repositories/transactions_repository.dart';

/// Re-categorization decision for one existing transaction, given its
/// already-stored merchant name/description — no re-parsing of the
/// original statement needed. Pure function, reuses the same categorizer
/// tiers a fresh transaction goes through (Task 3), minus the
/// Gemini-provided category tier: a backfilled row's original `category`
/// value is exactly what we're trying to replace (it's 'other'), so
/// there's nothing useful to validate there — merchant lookup and keyword
/// fallback are the only two tiers that can produce a new answer.
String recategorize({
  required String merchantName,
  required String description,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  final result = categorize(
    merchantName: merchantName,
    description: description,
    geminiCategory: null, // nothing to validate — see doc comment above
    merchantLookup: merchantLookup,
  );
  return result.category;
}

/// One-time job: re-categorizes every transaction currently stuck at
/// 'other' for [userId], using their already-stored merchant_name/description.
/// Run once after the categorization pipeline fix lands (Tasks 1-6) —
/// existing transactions were persisted before the fix and need this pass
/// to pick up a real category; new transactions get categorized correctly
/// going forward without needing this job again.
class CategoryBackfillService {
  final TransactionsRepository _repo;

  CategoryBackfillService(this._repo);

  /// Returns the count of transactions that were re-categorized to
  /// something other than 'other' (i.e. actually improved) vs. the total
  /// examined, so a caller can log/report progress.
  Future<({int total, int recategorized})> run(String userId) async {
    final transactions = await _repo.getUncategorizedTransactions(userId);
    var recategorized = 0;

    for (final txn in transactions) {
      final merchantName = txn.merchantName ?? txn.description;
      final normalized = normalizeMerchantName(merchantName);
      final mapped = await _repo.lookupMerchantCategory(normalized);

      final newCategory = recategorize(
        merchantName: merchantName,
        description: txn.description,
        merchantLookup: (_) => mapped,
      );

      if (newCategory != 'other') {
        await _repo.updateTransactionCategory(
          transactionId: txn.id,
          category: newCategory,
        );
        recategorized++;
      }
    }

    return (total: transactions.length, recategorized: recategorized);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/category_backfill_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/category_backfill_service.dart test/core/services/category_backfill_service_test.dart
git commit -m "feat: add one-time backfill service to re-categorize existing 'other' transactions"
```

- [ ] **Step 7: Decide and document how this gets triggered**

This plan builds the backfill service but deliberately doesn't wire it to
a UI button or app-startup hook — running it is an operational decision
(once, for existing users, possibly from a debug/admin screen or a
one-off script), not a feature this plan is scoped to design. Flagging
this explicitly rather than silently leaving it uncallable: **before this
work is considered done, decide how `CategoryBackfillService.run()` gets
invoked for real users** — options include a temporary debug-menu button,
a Supabase Edge Function invoked manually once, or a `main()`-guarded
script run against production data directly. This decision needs a human,
not a task in this plan — surface it to whoever reviews this plan's
completion.

---

## Task 9: Consolidate the three category icon/color switches

**Files:**
- Create: `lib/core/theme/category_display.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart:1212-1234` (`_categoryColor`/`_categoryIcon`)
- Modify: `lib/features/transactions/screens/transactions_screen.dart` (`_categoryColor`/`_categoryIcon`)
- Modify: `lib/features/cards/screens/card_detail_screen.dart:769-793` (`_categoryIcon`)
- Test: `test/core/theme/category_display_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/category_display_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cardcompass/core/theme/category_display.dart';
import 'package:cardcompass/core/theme/app_theme.dart';

void main() {
  group('categoryIcon', () {
    test('returns a specific icon for every one of the 16 valid categories', () {
      const categories = [
        'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
        'utilities', 'insurance', 'medical', 'education', 'investment',
        'transport', 'rental', 'subscription', 'gift', 'other',
      ];
      for (final c in categories) {
        final icon = categoryIcon(c);
        expect(icon, isA<IconData>(), reason: c);
      }
    });

    test('falls back to the generic receipt icon for null/unrecognized', () {
      expect(categoryIcon(null), Icons.receipt_rounded);
      expect(categoryIcon('not_a_real_category'), Icons.receipt_rounded);
    });

    test('is case-insensitive', () {
      expect(categoryIcon('FOOD'), categoryIcon('food'));
    });
  });

  group('categoryColor', () {
    test('returns a specific color for every one of the 16 valid categories', () {
      const categories = [
        'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
        'utilities', 'insurance', 'medical', 'education', 'investment',
        'transport', 'rental', 'subscription', 'gift', 'other',
      ];
      for (final c in categories) {
        final color = categoryColor(c);
        expect(color, isA<Color>(), reason: c);
      }
    });

    test('falls back to textSecondary for null/unrecognized', () {
      expect(categoryColor(null), AppColors.textSecondary);
      expect(categoryColor('not_a_real_category'), AppColors.textSecondary);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/theme/category_display_test.dart`
Expected: FAIL — `category_display.dart` doesn't exist.

- [ ] **Step 3: Write the shared mapping**

First, read `lib/core/theme/app_theme.dart` in full to confirm the exact
`AppColors` field names available (the plan references
`AppColors.warning`, `AppColors.violet`, `AppColors.success`,
`AppColors.textSecondary` — all seen in the three existing switch
statements during investigation, so they should exist, but verify spelling
before writing code that references them).

```dart
// lib/core/theme/category_display.dart
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Single source of truth for how each of the 16 transaction categories is
/// displayed (icon + color) — replaces three previously-independent,
/// drifting copies of this mapping in dashboard_screen.dart,
/// transactions_screen.dart, and card_detail_screen.dart, each of which
/// covered a different, incomplete subset of categories and could silently
/// regress to the generic fallback if a category's spelling didn't match.
IconData categoryIcon(String? category) {
  switch (category?.toLowerCase()) {
    case 'food': return Icons.restaurant_rounded;
    case 'fuel': return Icons.local_gas_station_rounded;
    case 'grocery': return Icons.local_grocery_store_rounded;
    case 'entertainment': return Icons.theaters_rounded;
    case 'travel': return Icons.flight_rounded;
    case 'shopping': return Icons.shopping_bag_rounded;
    case 'utilities': return Icons.bolt_rounded;
    case 'insurance': return Icons.shield_rounded;
    case 'medical': return Icons.medical_services_rounded;
    case 'education': return Icons.school_rounded;
    case 'investment': return Icons.trending_up_rounded;
    case 'transport': return Icons.directions_car_rounded;
    case 'rental': return Icons.home_work_rounded;
    case 'subscription': return Icons.subscriptions_rounded;
    case 'gift': return Icons.card_giftcard_rounded;
    case 'other': return Icons.receipt_rounded;
    default: return Icons.receipt_rounded;
  }
}

Color categoryColor(String? category) {
  switch (category?.toLowerCase()) {
    case 'food': return AppColors.warning;
    case 'fuel': return const Color(0xFFF97316);
    case 'grocery': return AppColors.success;
    case 'entertainment': return const Color(0xFFEC4899);
    case 'travel': return const Color(0xFF38BDF8);
    case 'shopping': return AppColors.violet;
    case 'utilities': return const Color(0xFFFBBF24);
    case 'insurance': return const Color(0xFF64748B);
    case 'medical': return const Color(0xFFEF4444);
    case 'education': return const Color(0xFF6366F1);
    case 'investment': return const Color(0xFF10B981);
    case 'transport': return const Color(0xFF0EA5E9);
    case 'rental': return const Color(0xFF8B5CF6);
    case 'subscription': return const Color(0xFFA855F7);
    case 'gift': return const Color(0xFFF472B6);
    case 'other': return AppColors.textSecondary;
    default: return AppColors.textSecondary;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/category_display_test.dart`
Expected: PASS (all cases)

- [ ] **Step 5: Replace `dashboard_screen.dart`'s copy**

Read the file fresh first (one of the 6 pre-existing-uncommitted-changes
files). Find `_categoryColor`/`_categoryIcon` (shown at
`dashboard_screen.dart:1212-1234` as of this plan's investigation — confirm
the current line numbers, since this file has uncommitted edits elsewhere
that may have shifted things) and replace both method bodies:

```dart
  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
```

Add the import at the top of the file, alongside the existing
`app_theme.dart` import:

```dart
import '../../../core/theme/category_display.dart';
```

Keeping the `_categoryColor`/`_categoryIcon` method names and their
call sites in this file unchanged (rather than replacing every call site
with `categoryColor(...)`/`categoryIcon(...)` directly) minimizes the diff
inside this large, actively-edited file — this task only needs the *body*
delegating to the shared implementation, not a rename sweep.

- [ ] **Step 6: Replace `transactions_screen.dart`'s copy**

Same pattern. Find its `_categoryColor`/`_categoryIcon` (the `food`/`dining`
alias case is dropped — `categoryIcon`/`categoryColor` already handle
`'food'` directly, and `'dining'` isn't one of the 16 valid categories
Gemini/the categorizer will ever produce after Task 4's prompt fix, so
keeping a dead alias would be clutter):

```dart
  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
```

Add the import:

```dart
import '../../../core/theme/category_display.dart';
```

(Adjust the relative path if `transactions_screen.dart`'s actual location
differs from `lib/features/transactions/screens/` — confirm with `find
lib/features/transactions -iname transactions_screen.dart` before editing
if unsure.)

- [ ] **Step 7: Replace `card_detail_screen.dart`'s copy**

This one is an instance method (`IconData _categoryIcon(String? category)`,
not `static`) and has no corresponding `_categoryColor` — only icon,
confirmed during investigation. Replace just the icon method body:

```dart
  IconData _categoryIcon(String? category) => categoryIcon(category);
```

Add the import:

```dart
import '../../../core/theme/category_display.dart';
```

(Adjust the relative path to match `card_detail_screen.dart`'s actual
location if it differs from `lib/features/cards/screens/`.)

- [ ] **Step 8: Run the full test suite and analyzer**

Run: `flutter test`
Expected: All tests pass.

Run: `flutter analyze`
Expected: No new errors introduced by this task (pre-existing warnings from
the 6 uncommitted files are not this task's concern).

- [ ] **Step 9: Commit**

```bash
git add lib/core/theme/category_display.dart lib/features/dashboard/screens/dashboard_screen.dart lib/features/transactions/screens/transactions_screen.dart lib/features/cards/screens/card_detail_screen.dart test/core/theme/category_display_test.dart
git commit -m "refactor: consolidate three drifting category icon/color switches into one shared mapping"
```

---

## Task 10: Manual end-to-end verification

This plan's automated tests cover every pure decision (categorization
logic, currency resolution, display mapping) but, as noted in Tasks 6 and
8, the Supabase-touching orchestration has no automated coverage (no
mocking library in this project). Before considering this plan complete,
verify manually:

- [ ] **Step 1: Run the full test suite one more time**

Run: `flutter test`
Expected: All tests pass (this plan's ~9 new test files plus the 2
pre-existing ones).

- [ ] **Step 2: Run the analyzer across the whole project**

Run: `flutter analyze`
Expected: No new errors. Compare against a baseline run before this plan's
changes if the project already had pre-existing warnings, so you're not
chasing unrelated issues.

- [ ] **Step 3: Manually process one real Indian statement and one real UAE statement (if a UAE test statement is available)**

Using the app's existing statement-upload flow (via
`StatementProcessingService.processUnprocessedEmails()` or
`processSpecificEmail()`, whichever the app's UI already triggers), process
one real Indian bank statement PDF and confirm:
- Resulting transactions have a `category` from the 16-value list, not
  `bills`/`transfer`/`fee`/`payment`/`cash`/null.
- `transactions.currency` is `INR`.
- At least one transaction from a merchant in `merchant_category_seed.dart`
  (e.g. Swiggy, Amazon) got categorized correctly via the merchant-map tier.

If a UAE statement PDF is available for testing, repeat and additionally
confirm `transactions.currency` is `AED` for that statement's transactions.
If no UAE test statement is available, note this as an untested path in
your completion report rather than silently skipping verification.

- [ ] **Step 4: Manually run the backfill against a test user's existing data**

Using a Dart REPL, a temporary debug button, or a one-off script (see Task
8 Step 7's note — this plan doesn't build a permanent trigger), call
`CategoryBackfillService(TransactionsRepository(supabaseClient)).run(testUserId)`
against a test account with existing `other`-categorized transactions.
Confirm the returned `(total, recategorized)` counts make sense and spot-
check a handful of the updated rows in the Supabase table editor.

- [ ] **Step 5: Visually confirm the three consolidated icon switches render correctly**

Open the dashboard, transactions list, and a card detail screen in the
running app; confirm transaction rows show category-appropriate icons
(e.g. a grocery transaction shows the grocery-store icon, not the generic
receipt icon) across all three screens consistently.

- [ ] **Step 6: Report completion status**

Summarize: which of Steps 3-5 were completed vs. skipped (and why, if a UAE
test statement wasn't available), plus the unresolved Task 8 Step 7
decision (how the backfill gets triggered for real users) — this needs a
human decision before the feature is fully "done," not just implemented.
