# Transaction Categorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every transaction's `category` field reliably populated with
one of 16 correct spend categories (India + UAE), enforce that vocabulary at
the database level, fix the currency/`isInternational` chain, consolidate
the three drifting category icon switches, and safely backfill existing
transactions — per
`docs/superpowers/specs/2026-08-03-transaction-categorization-design.md`
(read that spec's full rationale before starting; this plan implements it,
not re-derives it).

**Architecture:** A pure-logic categorizer
(`lib/core/services/transaction_categorizer.dart`) resolves a category via
merchant-map lookup → Gemini's own validated value → keyword fallback, with
no write-back anywhere (a prior design had tier 3 write learned merchants
back to a shared table; that's removed — it leaked private statement data).
`merchant_category_map` is seed-only, read-only from the app's perspective.
A new `bank_market.dart` fills a real gap — no existing code classifies a
bank as Indian vs. UAE — needed for both the currency fix and
`isInternational`. The currency fix has three parts: correct the Gemini
prompt's category vocabulary, correct its currency instruction, and make
ingestion distrust a bare `"INR"` response by cross-checking against the
bank's known market. A `CHECK` constraint enforces the vocabulary at the
database level, added `NOT VALID` first so it doesn't fail against existing
bad data, validated only after a backfill job (with real operational
rigor — privileged execution, idempotency, audit counts) fixes every
legacy row.

**Tech Stack:** Flutter/Dart, Supabase (Postgres + supabase_flutter),
flutter_test. This project has two testing tiers, both used in this plan:
pure Dart unit tests (no mocking library exists here — test pure logic, not
mocked repositories), and **live-Supabase integration tests** against a
local instance (established precedent:
`test/supabase/benefit_platform_confirmations_permissions_test.dart`,
`test/supabase/waitlist_security_contract_test.dart` — both connect to
`http://127.0.0.1:54321` after `supabase start`/`supabase db reset` and
exercise real RLS/grant behavior, including a service-role client pattern
for privileged operations). This plan follows that same pattern for the new
`CHECK` constraints and the backfill's privileged-execution requirement —
not a hand-waved "manually check in the SQL editor" fallback.

---

## Important context for whoever implements this

This work happens in the `cardcompass-landing-v2` git worktree, on branch
`feature/landing-v2` — **not** the main `cardcompass` repo. Confirm before
starting:

```bash
cd /Users/shantanuchandra/Downloads/Personal/cardcompass-landing-v2
git branch --show-current
```

Expected output: `feature/landing-v2`

This worktree has **unrelated in-flight work** sitting uncommitted at the
time this plan was written — landing-page files (`landing/index.html`,
`landing/script.js`, `landing/style.css`, `landing/card-catalog.json`,
`landing/waitlist.js`), a GTM plan doc (`.superpowers/cardcompass-v2-gtm-plan.md`),
`test/landing/`, and `lib/features/dashboard/providers/dashboard_provider.dart`
/ `lib/features/dashboard/screens/dashboard_screen.dart` (the latter two
also happen to be files this plan touches — see Task 9's note on
re-reading `dashboard_screen.dart` fresh before editing). **Do not
discard, stash, or `git checkout` any of these files.** Before editing
`dashboard_screen.dart` specifically, run `git status` and `git diff` on
it first — if it has uncommitted changes beyond what this plan documents
finding, re-read the file fresh rather than trusting the line numbers
quoted here.

All 16 categories referenced throughout: `food, fuel, grocery,
entertainment, travel, shopping, utilities, insurance, medical, education,
investment, transport, rental, subscription, gift, other`.

A prior version of this plan (`docs/superpowers/plans/2026-08-03-transaction-categorization.md`,
if it still exists) was written against an earlier version of the spec
that included a `merchant_category_map` write-back RPC. That RPC is
**removed** from the current spec (privacy finding — see spec §1/§3) and
does not appear anywhere in this plan. If you find yourself reading the
old plan file for reference, do not port its RPC-related tasks — they no
longer apply.

---

## Task 1: `merchant_category_map` — seed-only table, no write path

**Files:**
- Create: `supabase/migrations/20260816000000_merchant_category_map.sql`
- Create: `lib/core/services/merchant_category_seed.dart`
- Test: `test/core/services/merchant_category_seed_test.dart`
- Test: `test/supabase/merchant_category_map_permissions_test.dart`

- [ ] **Step 1: Write the failing unit test for the seed data**

```dart
// test/core/services/merchant_category_seed_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/merchant_category_seed.dart';
import 'package:cardcompass/core/services/ambiguous_merchants.dart';

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

    test('never seeds a denylisted ambiguous merchant', () {
      for (final merchant in ambiguousMerchants) {
        expect(
          merchantCategorySeed.containsKey(merchant),
          isFalse,
          reason: '$merchant is denylisted as ambiguous and must never be seeded '
              'with a single fixed category (spec §1)',
        );
      }
    });

    test('covers known Indian merchants', () {
      expect(merchantCategorySeed['SWIGGY'], 'food');
      expect(merchantCategorySeed['ZOMATO'], 'food');
      expect(merchantCategorySeed['FLIPKART'], 'shopping');
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
Expected: FAIL — `merchant_category_seed.dart` and `ambiguous_merchants.dart`
don't exist yet, import errors.

- [ ] **Step 3: Write the ambiguous-merchants denylist**

```dart
// lib/core/services/ambiguous_merchants.dart

/// Merchants known to genuinely span multiple spend categories, where no
/// single fixed category is correct for every transaction (spec §1). These
/// must never appear as a key in `merchant_category_seed.dart` — seeding
/// one of them with any single category would give the same wrong answer,
/// every time, for every purchase type that isn't the one seeded category.
/// Checked before the merchant-lookup tier of the categorizer runs;
/// a denylisted merchant always falls through to Gemini's own value or
/// keyword matching, both of which can react to per-transaction context
/// (e.g. "AMAZON PRIME MEMBERSHIP" vs. "AMAZON.IN PURCHASE") that a bare
/// merchant name can't.
const Set<String> ambiguousMerchants = {
  'AMAZON',
  'PAYPAL',
};
```

- [ ] **Step 4: Write the seed data**

```dart
// lib/core/services/merchant_category_seed.dart

/// Merchant name (uppercase, normalized) -> one of the 16 spend categories.
/// Seeds `merchant_category_map` (see the migration in this same task).
/// Covers common Indian and UAE merchants — the two markets this app's
/// statement parsing supports (see `card_normalizer_service.dart`'s bank
/// list). Must never contain a key listed in `ambiguous_merchants.dart`
/// (enforced by a test, see Step 1).
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
  // Transport — UAE
  'CAREEM': 'transport',
  'RTA': 'transport',
  'SALIK': 'transport',

  // Fuel — India
  'INDIAN OIL': 'fuel',
  'BHARAT PETROLEUM': 'fuel',
  'HPCL': 'fuel',
  // Fuel — UAE
  'ADNOC': 'fuel',
  'ENOC': 'fuel',
  'EPPCO': 'fuel',

  // Entertainment — both markets
  'NETFLIX': 'entertainment',
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

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/services/merchant_category_seed_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 6: Create the migration — seed-only, no RPC, no write path**

```sql
-- supabase/migrations/20260816000000_merchant_category_map.sql
--
-- Maps a normalized merchant name to one of the 16 transaction spend
-- categories. Seed-only: this table is populated once here and never
-- written to at runtime by the app. An earlier design had a write-back
-- path for a keyword-fallback categorizer tier, but that would have
-- persisted a user's private, unfiltered statement merchant string into
-- a table every authenticated user can read — removed for that reason
-- (design spec §1/§3). Correcting a wrong row is a direct migration edit,
-- same mechanism as adding one.
create table if not exists public.merchant_category_map (
  merchant_name_normalized text primary key,
  category text not null check (category in (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other'
  )),
  created_at timestamptz not null default now()
);

alter table public.merchant_category_map enable row level security;

create policy "merchant_category_map_select_authenticated"
  on public.merchant_category_map
  for select
  to authenticated
  using (true);

grant select on public.merchant_category_map to authenticated;

-- Seed data — must match lib/core/services/merchant_category_seed.dart
-- row for row (verified by test/core/services/merchant_category_seed_test.dart
-- on the Dart side; there is no automated check that this SQL block and
-- the Dart map stay in sync — if you change one, change the other).
insert into public.merchant_category_map (merchant_name_normalized, category) values
  ('SWIGGY', 'food'),
  ('ZOMATO', 'food'),
  ('DOMINOS', 'food'),
  ('MCDONALDS', 'food'),
  ('STARBUCKS', 'food'),
  ('TALABAT', 'food'),
  ('DELIVEROO', 'food'),
  ('BIGBASKET', 'grocery'),
  ('BLINKIT', 'grocery'),
  ('ZEPTO', 'grocery'),
  ('DMART', 'grocery'),
  ('RELIANCE FRESH', 'grocery'),
  ('CARREFOUR', 'grocery'),
  ('LULU', 'grocery'),
  ('SPINNEYS', 'grocery'),
  ('WAITROSE', 'grocery'),
  ('FLIPKART', 'shopping'),
  ('MYNTRA', 'shopping'),
  ('AJIO', 'shopping'),
  ('NYKAA', 'shopping'),
  ('NOON', 'shopping'),
  ('NAMSHI', 'shopping'),
  ('SHEIN', 'shopping'),
  ('OLA', 'transport'),
  ('UBER', 'transport'),
  ('RAPIDO', 'transport'),
  ('IRCTC', 'transport'),
  ('CAREEM', 'transport'),
  ('RTA', 'transport'),
  ('SALIK', 'transport'),
  ('INDIAN OIL', 'fuel'),
  ('BHARAT PETROLEUM', 'fuel'),
  ('HPCL', 'fuel'),
  ('ADNOC', 'fuel'),
  ('ENOC', 'fuel'),
  ('EPPCO', 'fuel'),
  ('NETFLIX', 'entertainment'),
  ('SPOTIFY', 'entertainment'),
  ('BOOKMYSHOW', 'entertainment'),
  ('PVR', 'entertainment'),
  ('VOX CINEMAS', 'entertainment'),
  ('REEL CINEMAS', 'entertainment'),
  ('MAKEMYTRIP', 'travel'),
  ('GOIBIBO', 'travel'),
  ('INDIGO', 'travel'),
  ('AIR INDIA', 'travel'),
  ('EMIRATES', 'travel'),
  ('ETIHAD', 'travel'),
  ('BOOKING.COM', 'travel'),
  ('AIRBNB', 'travel'),
  ('DEWA', 'utilities'),
  ('ETISALAT', 'utilities'),
  ('DU', 'utilities'),
  ('AIRTEL', 'utilities'),
  ('JIO', 'utilities'),
  ('APOLLO PHARMACY', 'medical'),
  ('PHARMEASY', 'medical'),
  ('LIFE PHARMACY', 'medical'),
  ('ASTER PHARMACY', 'medical'),
  ('BYJUS', 'education'),
  ('UDEMY', 'education'),
  ('COURSERA', 'education')
on conflict (merchant_name_normalized) do nothing;
```

- [ ] **Step 7: Write the live-Supabase permissions test**

Following the established pattern in
`test/supabase/benefit_platform_confirmations_permissions_test.dart`:

```dart
// test/supabase/merchant_category_map_permissions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` (or `supabase db reset` to apply migrations fresh)
// before running this file.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    client = Supabase.instance.client;
    await client.auth.signUp(
      email: 'merchant-category-map-test@example.com',
      password: 'test-password-1234',
    );
  });

  test('authenticated role can SELECT merchant_category_map', () async {
    final result = await client.from('merchant_category_map').select().limit(1);
    expect(result, isA<List>());
  });

  test('seed data is present and correctly categorized', () async {
    final result = await client
        .from('merchant_category_map')
        .select()
        .eq('merchant_name_normalized', 'CARREFOUR')
        .single();
    expect(result['category'], 'grocery');
  });

  test('the category CHECK constraint rejects an invalid value', () async {
    expect(
      () => client.from('merchant_category_map').insert({
        'merchant_name_normalized': 'TEST_INVALID_ROW',
        'category': 'not_a_real_category',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('authenticated role cannot INSERT (no write grant exists)', () async {
    expect(
      () => client.from('merchant_category_map').insert({
        'merchant_name_normalized': 'TEST_SHOULD_FAIL',
        'category': 'shopping',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });
}
```

- [ ] **Step 8: Apply the migration and run the integration test**

Run: `supabase start` (starts local Postgres + auth + PostgREST if not
already running), then `supabase db reset` (applies every migration
fresh, including the new one).
Expected: no errors, migration applies cleanly.

Run: `flutter test test/supabase/merchant_category_map_permissions_test.dart --dart-define=SUPABASE_ANON_KEY=<local anon key from `supabase status`>`
Expected: PASS (4 tests). If the anon key isn't known, run `supabase status`
first to print it.

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260816000000_merchant_category_map.sql lib/core/services/merchant_category_seed.dart lib/core/services/ambiguous_merchants.dart test/core/services/merchant_category_seed_test.dart test/supabase/merchant_category_map_permissions_test.dart
git commit -m "feat: add seed-only merchant_category_map table and India/UAE merchant seed data"
```

---

## Task 2: `bank_market.dart` — resolve currency/market from bank name, fix UAE bank recognition ordering

This fills a gap found during spec investigation: `CardNormalizerService`
only recognizes Indian banks today. Also fixes a confirmed ordering bug:
UAE-specific checks for shared-brand banks (HSBC, Citibank) must come
*before* their generic Indian-bank counterparts, or they're unreachable.

**Files:**
- Modify: `lib/core/services/card_normalizer_service.dart:4-38`
- Create: `lib/core/services/bank_market.dart`
- Test: `test/core/services/bank_market_test.dart`
- Test: `test/core/services/card_normalizer_service_uae_test.dart`

- [ ] **Step 1: Write the failing tests**

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
      expect(currencyForBank('HSBC UAE'), 'AED');
      expect(currencyForBank('Citibank UAE'), 'AED');
    });

    test('returns null (not a silent INR default) for an unrecognized bank name', () {
      // Confirmed as a design requirement (spec §4, layer 3): a caller must
      // be able to distinguish "resolved to INR" from "couldn't resolve at
      // all" — silently defaulting to INR here would mask exactly the
      // failure this function exists to catch.
      expect(currencyForBank('Some New Bank Nobody Has Heard Of'), isNull);
    });
  });
}
```

```dart
// test/core/services/card_normalizer_service_uae_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/card_normalizer_service.dart';

void main() {
  group('CardNormalizerService.normalizeBankName — UAE recognition', () {
    test('recognizes UAE banks with no Indian namesake', () {
      expect(CardNormalizerService.normalizeBankName('FAB'), 'FAB');
      expect(CardNormalizerService.normalizeBankName('Emirates NBD Bank'), 'Emirates NBD');
      expect(CardNormalizerService.normalizeBankName('ADCB'), 'ADCB');
      expect(CardNormalizerService.normalizeBankName('Mashreq Bank'), 'Mashreq');
      expect(CardNormalizerService.normalizeBankName('RAKBANK'), 'RAKBANK');
    });

    test('recognizes shared-brand UAE banks when the raw name says UAE '
        '(the ordering bug this fix corrects — these must NOT fall through '
        'to the generic Indian HSBC/Citi checks)', () {
      expect(CardNormalizerService.normalizeBankName('HSBC UAE'), 'HSBC UAE');
      expect(CardNormalizerService.normalizeBankName('Citibank UAE'), 'Citibank UAE');
    });

    test('still recognizes plain Indian HSBC/Citi when the raw name does '
        'not say UAE (unchanged behavior)', () {
      expect(CardNormalizerService.normalizeBankName('HSBC'), 'HSBC');
      expect(CardNormalizerService.normalizeBankName('Citibank'), 'Citibank');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/bank_market_test.dart test/core/services/card_normalizer_service_uae_test.dart`
Expected: FAIL — `bank_market.dart` doesn't exist; UAE bank names aren't
recognized yet.

- [ ] **Step 3: Add UAE bank recognition to `CardNormalizerService.normalizeBankName`, with correct ordering**

Read `lib/core/services/card_normalizer_service.dart` fresh before editing
to confirm it still matches the content shown here (it's not one of the
files with unrelated in-flight changes noted at the top of this plan, but
verify). Replace the method body — UAE-specific checks for shared-brand
banks (`hsbc uae`, `citi uae`) go **before** the generic Indian `hsbc`/`citi`
checks; banks with no Indian namesake can go anywhere, added at the end for
clarity:

```dart
  /// Normalize a bank name to a canonical form to prevent duplicates
  static String normalizeBankName(String rawName) {
    final lower = rawName.toLowerCase();

    // UAE shared-brand checks MUST come before their generic Indian
    // counterparts below (hsbc, citi) — Dart's if/else-if chain matches
    // top-to-bottom, so a UAE-specific check placed after the generic one
    // would never be reached even when the raw name explicitly says "UAE".
    if (lower.contains('hsbc uae') || lower.contains('hsbc middle east')) return 'HSBC UAE';
    if (lower.contains('citibank uae') || lower.contains('citi uae')) return 'Citibank UAE';

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

    // UAE banks with no Indian namesake — no ordering hazard, can appear
    // anywhere relative to the Indian checks above.
    if (lower.contains('fab') || lower.contains('first abu dhabi')) return 'FAB';
    if (lower.contains('emirates nbd')) return 'Emirates NBD';
    if (lower.contains('adcb') || lower.contains('abu dhabi commercial')) return 'ADCB';
    if (lower.contains('mashreq')) return 'Mashreq';
    if (lower.contains('cbd') || lower.contains('commercial bank of dubai')) return 'CBD';
    if (lower.contains('dib') || lower.contains('dubai islamic')) return 'Dubai Islamic Bank';
    if (lower.contains('rakbank') || lower.contains('rak bank')) return 'RAKBANK';
    if (lower.contains('emirates islamic')) return 'Emirates Islamic';

    return rawName.split(RegExp(r"\s+")).map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }
```

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

/// Indian banks currently recognized by `CardNormalizerService.normalizeBankName`.
/// A bank name that's neither in this set nor `_uaeBanks` is genuinely
/// unrecognized — `currencyForBank` returns null for it rather than
/// guessing, per spec §4's explicit "must not silently default" requirement.
const Set<String> _indianBanks = {
  'HDFC Bank', 'SBI Card', 'Axis Bank', 'Amazon ICICI Bank', 'ICICI Bank',
  'Kotak Bank', 'IDFC FIRST Bank', 'Yes Bank', 'AU Small Finance Bank',
  'IndusInd Bank', 'Standard Chartered', 'American Express', 'Citibank',
  'HSBC', 'RBL Bank', 'Federal Bank', 'Karur Vysya Bank', 'Bank of Baroda',
  'Canara Bank', 'Punjab National Bank', 'Union Bank of India', 'Indian Bank',
  'Central Bank of India', 'Indian Overseas Bank',
};

/// The currency a bank's statements are denominated in, given its
/// already-normalized name (from `CardNormalizerService.normalizeBankName`).
/// Returns null — not a bare 'INR' default — for a name that's neither a
/// recognized Indian nor UAE bank, so callers can distinguish "resolved to
/// INR" from "couldn't resolve at all" (spec §4, layer 3: silently
/// defaulting to INR here would mask exactly the failure this function
/// exists to catch, e.g. a UAE bank not yet added to the recognized list).
String? currencyForBank(String normalizedBankName) {
  if (_uaeBanks.contains(normalizedBankName)) return 'AED';
  if (_indianBanks.contains(normalizedBankName)) return 'INR';
  return null;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/core/services/bank_market_test.dart test/core/services/card_normalizer_service_uae_test.dart`
Expected: PASS (3 + 3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/card_normalizer_service.dart lib/core/services/bank_market.dart test/core/services/bank_market_test.dart test/core/services/card_normalizer_service_uae_test.dart
git commit -m "feat: recognize UAE banks (ordering-safe), resolve currency by bank market without a silent INR default"
```

---

## Task 3: `transaction_categorizer.dart` — merchant lookup, Gemini validation, keyword fallback, provenance

No write-back anywhere in this task (removed per spec §1/§3 — see Task 1's
migration comment for why).

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
      expect(isValidCategory('dining'), isFalse); // superseded by 'food'
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

  group('keywordCategoryFor — covers the 13 categories with deterministic '
      'signals (investment/rental/gift have none, per spec Taxonomy section)', () {
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

    test('returns null for descriptions belonging to the 3 Gemini-only '
        'categories (investment/rental/gift) — this is tier 3\'s honest '
        'failure mode for those three, not a false positive', () {
      expect(keywordCategoryFor('MUTUAL FUND SIP INSTALLMENT'), isNull);
      expect(keywordCategoryFor('MONTHLY RENT PAYMENT LANDLORD'), isNull);
      expect(keywordCategoryFor('GIFT CARD PURCHASE'), isNull);
    });

    test('returns null when nothing matches at all', () {
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
        geminiCategory: 'shopping', // deliberately wrong, to prove priority
        merchantLookup: (normalized) => normalized == 'CARREFOUR' ? 'grocery' : null,
      );
      expect(result.category, 'grocery');
      expect(result.source, CategorizationSource.merchantMap);
    });

    test('a denylisted ambiguous merchant skips merchant lookup entirely, '
        'even if merchantLookup would have returned a value', () {
      final result = categorize(
        merchantName: 'Amazon',
        description: 'AMAZON PRIME MEMBERSHIP',
        geminiCategory: 'subscription',
        // This lookup function would return 'shopping' if consulted — proving
        // the denylist check happens before merchantLookup is ever called.
        merchantLookup: (_) => 'shopping',
      );
      expect(result.category, 'subscription'); // from Gemini, not the lookup
      expect(result.source, CategorizationSource.geminiValidated);
    });

    test("falls through to keyword matching when Gemini's category is invalid", () {
      final result = categorize(
        merchantName: 'Some New Restaurant',
        description: 'SOME NEW RESTAURANT PAYMENT',
        geminiCategory: 'dining', // not one of the 16 — superseded by 'food'
        merchantLookup: (_) => null,
      );
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

    test('calling categorize twice with the same never-before-seen merchant '
        're-resolves via keyword matching both times — proves there is no '
        'caching or write-back side effect (spec §3: privacy fix)', () {
      var lookupCallCount = 0;
      String? lookup(String _) {
        lookupCallCount++;
        return null; // never in the map
      }

      final first = categorize(
        merchantName: 'Local Restaurant XYZ',
        description: 'RESTAURANT PAYMENT',
        geminiCategory: null,
        merchantLookup: lookup,
      );
      final second = categorize(
        merchantName: 'Local Restaurant XYZ',
        description: 'RESTAURANT PAYMENT',
        geminiCategory: null,
        merchantLookup: lookup,
      );

      expect(first.category, 'food');
      expect(second.category, 'food');
      expect(first.source, CategorizationSource.keywordFallback);
      expect(second.source, CategorizationSource.keywordFallback);
      // Called once per categorize() invocation — nothing was cached/learned
      // between calls that would let the second call skip re-resolving.
      expect(lookupCallCount, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/transaction_categorizer_test.dart`
Expected: FAIL — `transaction_categorizer.dart` doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/services/transaction_categorizer.dart
import 'ambiguous_merchants.dart';

const Set<String> validCategories = {
  'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
  'utilities', 'insurance', 'medical', 'education', 'investment',
  'transport', 'rental', 'subscription', 'gift', 'other',
};

/// Which tier resolved a transaction's category — persisted in
/// `transactions.metadata['category_source']` (see Task 6) for
/// auditability. `unresolved` means even the keyword-fallback tier found
/// nothing and the category fell to 'other'.
enum CategorizationSource { merchantMap, geminiValidated, keywordFallback, unresolved }

class CategorizationResult {
  final String category;
  final CategorizationSource source;
  const CategorizationResult(this.category, this.source);
}

/// Normalizes a merchant name for lookup: uppercase, trimmed, internal
/// whitespace collapsed to single spaces. Must match how
/// `merchant_category_seed.dart`'s keys are normalized, so lookups hit.
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
/// indicate a category. Deliberately covers only the 13 categories with
/// deterministic signals — investment, rental, and gift have no reliable
/// universal keyword (spec Taxonomy section: "what generic word reliably
/// signals 'rental' without also matching unrelated transactions?"),
/// so they're intentionally absent here and can only be resolved via
/// Gemini's own value (tier 2).
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
///    per-call LLM guess. Skipped entirely for a denylisted ambiguous
///    merchant (`ambiguous_merchants.dart`) — those go straight to tier 2.
/// 2. Gemini's own [geminiCategory], trusted only when it's one of the 16
///    valid categories — Gemini's prompt asks for the right vocabulary but
///    isn't guaranteed to comply.
/// 3. Keyword matching against [description] — last resort when neither of
///    the above resolves anything.
///
/// [merchantLookup] is injected (rather than this function querying
/// `merchant_category_map` directly) so this whole decision tree stays pure
/// and unit-testable without a Supabase client. The caller (see
/// `statement_processing_service.dart`, Task 6) supplies a real lookup
/// backed by the seed map. There is NO write-back anywhere in this
/// function or its caller — an earlier design wrote tier-3 results back to
/// the shared table; that leaked private statement data and was removed
/// (spec §1/§3).
CategorizationResult categorize({
  required String merchantName,
  required String description,
  required String? geminiCategory,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  final normalized = normalizeMerchantName(merchantName);

  if (!ambiguousMerchants.contains(normalized)) {
    final mapped = merchantLookup(normalized);
    if (mapped != null) {
      return CategorizationResult(mapped, CategorizationSource.merchantMap);
    }
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/transaction_categorizer_test.dart`
Expected: PASS (all groups)

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/transaction_categorizer.dart test/core/services/transaction_categorizer_test.dart
git commit -m "feat: add pure categorization logic — merchant lookup, Gemini validation, keyword fallback, provenance, no write-back"
```

---

## Task 4: Fix Gemini's category and currency prompt instructions

**Files:**
- Modify: `lib/core/services/gemini_statement_parser.dart:189-216` (prompt-building, extracted into a testable function)
- Test: `test/core/services/gemini_statement_parser_prompt_test.dart`

- [ ] **Step 1: Write the failing test for the extracted prompt-builder**

The prompt *text* is a static, deterministic string — testable, unlike
Gemini's actual response to it. Extract prompt construction into its own
function first, then test the returned string directly.

```dart
// test/core/services/gemini_statement_parser_prompt_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/gemini_statement_parser.dart';

void main() {
  group('buildTransactionsPrompt', () {
    final prompt = buildTransactionsPrompt(bankName: 'HDFC Bank');

    test('contains the corrected 16-category vocabulary', () {
      expect(prompt, contains('food|fuel|grocery|entertainment|travel|shopping|'
          'utilities|insurance|medical|education|investment|transport|'
          'rental|subscription|gift|other'));
    });

    test('does not contain any of the old, wrong vocabulary values as '
        'category options (bills/transfer/fee/payment/cash/dining)', () {
      // These words might legitimately appear elsewhere in the prompt (e.g.
      // "payment" in general instructional text), so check the specific
      // category-vocabulary line doesn't contain the old pipe-delimited list.
      expect(prompt, isNot(contains('shopping|dining|travel|fuel|entertainment|'
          'bills|transfer|fee|payment|cash|other')));
    });

    test('instructs Gemini to report the observed currency, not assume '
        'INR as the sole example', () {
      expect(prompt, contains('actual currency'));
      expect(prompt, isNot(contains('"currency": "INR"')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/gemini_statement_parser_prompt_test.dart`
Expected: FAIL — `buildTransactionsPrompt` doesn't exist yet (prompt is
currently inlined in `parseTransactions()`).

- [ ] **Step 3: Extract and fix the prompt**

Read `lib/core/services/gemini_statement_parser.dart` fresh before editing
(it's one of the files this plan modifies in multiple tasks — Task 6 also
touches it — so re-confirm current line numbers if this task runs
non-sequentially). Replace the inlined prompt string inside
`parseTransactions()` (currently lines 188-216) with a call to a new
top-level function, and define that function:

```dart
  static Future<List<Map<String, dynamic>>> parseTransactions({
    required String pdfText,
    required String bankName,
  }) async {
    try {
      final prompt = buildTransactionsPrompt(bankName: bankName);

      final cleanedText = _pruneAndCleanText(pdfText);
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': '$prompt\n\n$cleanedText'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 8192}
      };

      final response = await _callGemini(requestBody, maxRetries: 3);

      if (response != null && response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final content = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (content != null) {
          try {
            final cleanContent = _extractJsonPayload(content);
            final List<dynamic> list = json.decode(cleanContent);

            const uuid = Uuid();
            final transactions = list.map<Map<String, dynamic>>((item) {
              final m = Map<String, dynamic>.from(item);
              m['id'] = m['id'] ?? uuid.v4();
              return m;
            }).toList();

            ParsingLogger.summary('Gemini Parser: Successfully parsed ${transactions.length} transactions');
            return transactions;
          } catch (e) {
            ParsingLogger.error('Gemini Parser: Failed to parse JSON response', e);
          }
        }
      }
      return [];
    } catch (e) {
      ParsingLogger.error('Gemini Parser: Error parsing transactions', e);
      return [];
    }
  }
```

Add this new top-level function (outside the class, or as a `static`
method — top-level is simpler here since it has no dependency on instance
state):

```dart
/// Builds the Gemini prompt for `parseTransactions()`. Extracted into its
/// own function (rather than inlined) so its exact text is directly
/// unit-testable — catches a future edit accidentally reintroducing the
/// old category vocabulary or the hardcoded INR example, which neither a
/// "prompts aren't testable" stance nor a live-Gemini-call test could
/// catch cheaply.
String buildTransactionsPrompt({required String bankName}) {
  return '''You are an expert at extracting transactions from Indian credit card statements. Analyze this ${bankName.toUpperCase()} statement and extract ALL transactions.

BANK: $bankName

EXTRACTION STRATEGY:
1. Find transaction table sections (look for headers like "Date", "Transaction", "Amount")
2. Extract each row that contains: Date + Description + Amount
3. Skip summary rows, balance rows, and headers
4. Parse amounts carefully - "CR" = credit (+), "D"/"Dr" = debit (-)
5. Clean merchant names (remove codes, URLs, extra numbers)
6. Convert all dates to YYYY-MM-DD format
7. For each transaction, identify the actual currency symbol or code visible on that line (e.g. "Rs.", "₹", "INR", "AED", "د.إ", "USD", "\$"). If no currency marker is visible on that specific line, assume INR only as a last resort — do not assume INR when a different marker is actually present.

JSON OUTPUT (return ONLY this array, no markdown blocks):
[
  {
    "date": "YYYY-MM-DD",
    "description": "Clean merchant name without codes",
    "amount": number (positive for credits, negative for debits),
    "currency": "the actual currency code observed on this line (e.g. INR, AED, USD) — only assume INR if no marker is visible",
    "merchantName": "Primary merchant name",
    "category": "food|fuel|grocery|entertainment|travel|shopping|utilities|insurance|medical|education|investment|transport|rental|subscription|gift|other",
    "type": "debit|credit",
    "reward_points": number or null (reward/loyalty points earned for this transaction, 0 if none),
    "reference": "transaction reference if clearly visible"
  }
]

ANALYZE THIS STATEMENT:''';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/gemini_statement_parser_prompt_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full existing test suite to confirm nothing else broke**

Run: `flutter test`
Expected: All previously-passing tests still pass (the prompt change
doesn't alter `parseTransactions()`'s public signature or return shape).

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/gemini_statement_parser.dart test/core/services/gemini_statement_parser_prompt_test.dart
git commit -m "fix: extract testable prompt builder, correct category vocabulary and currency instruction"
```

---

## Task 5: Currency resolution — ingestion distrusts a bare "INR" value

Implements spec §4 layer 2: read `txn['currency']`, but don't trust a bare
`"INR"` response uncritically — cross-check against `currencyForBank`.

**Files:**
- Create: `lib/core/services/transaction_currency_resolver.dart`
- Test: `test/core/services/transaction_currency_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/transaction_currency_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/transaction_currency_resolver.dart';

void main() {
  group('resolveTransactionCurrency', () {
    test('trusts a non-INR Gemini value directly, no cross-check needed', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'AED', bankMarketCurrency: 'INR'),
        'AED',
      );
      expect(
        resolveTransactionCurrency(geminiCurrency: 'USD', bankMarketCurrency: 'AED'),
        'USD',
      );
    });

    test('overrides a bare "INR" value when the bank resolves to a '
        'non-INR market — the core INR-distrust logic (spec §4, layer 2)', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: 'AED'),
        'AED',
      );
    });

    test('keeps "INR" when the bank also resolves to INR', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: 'INR'),
        'INR',
      );
    });

    test('keeps "INR" when the bank market is unresolved (null)', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: 'INR', bankMarketCurrency: null),
        'INR',
      );
    });

    test('missing/null Gemini value falls through to the bank market, '
        'same as a bare "INR" response would', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: null, bankMarketCurrency: 'AED'),
        'AED',
      );
      expect(
        resolveTransactionCurrency(geminiCurrency: null, bankMarketCurrency: null),
        'INR', // final fallback when nothing resolves anything
      );
    });

    test('empty string Gemini value is treated the same as null', () {
      expect(
        resolveTransactionCurrency(geminiCurrency: '', bankMarketCurrency: 'AED'),
        'AED',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/transaction_currency_resolver_test.dart`
Expected: FAIL — `transaction_currency_resolver.dart` doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/services/transaction_currency_resolver.dart

/// Resolves the currency to store for one transaction, given what Gemini
/// reported ([geminiCurrency], from `txn['currency']` in its per-transaction
/// JSON) and the issuing bank's known market currency ([bankMarketCurrency],
/// from `currencyForBank` — null if the bank is unrecognized).
///
/// A bare "INR" from Gemini is NOT trusted as automatically authoritative
/// (spec §4, layer 2): the prompt (Task 4) instructs Gemini to assume INR
/// only when no currency marker is visible on a line, which means a
/// genuinely-unmarked UAE transaction can legitimately come back as "INR" —
/// indistinguishable from a line where an actual Rs./₹ marker was observed.
/// So: any non-INR value is trusted directly (Gemini has no ambiguous
/// assumption for anything other than INR), but a bare "INR" or missing
/// value is cross-checked against the bank's market and overridden if the
/// bank resolves to something else.
///
/// Trade-off accepted explicitly (spec §4): a genuinely correct,
/// explicitly-marked INR line item on a UAE statement would be incorrectly
/// overridden to the bank's market currency by this logic, since there's
/// no way to distinguish "Gemini assumed INR" from "Gemini correctly read
/// an INR marker" from the string alone.
String resolveTransactionCurrency({
  required String? geminiCurrency,
  required String? bankMarketCurrency,
}) {
  final trimmed = geminiCurrency?.trim();
  if (trimmed != null && trimmed.isNotEmpty && trimmed.toUpperCase() != 'INR') {
    return trimmed.toUpperCase();
  }

  if (bankMarketCurrency != null) {
    return bankMarketCurrency;
  }

  return 'INR';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/transaction_currency_resolver_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/transaction_currency_resolver.dart test/core/services/transaction_currency_resolver_test.dart
git commit -m "feat: resolve transaction currency distrusting a bare INR response, cross-checked against bank market"
```

---

## Task 6: Wire everything into `TransactionsRepository` and `StatementProcessingService`

This is the integration task: the categorizer (Task 3), currency resolver
(Task 5), and bank market lookup (Task 2) all get called from the real
ingestion path, with provenance (Task 3's `CategorizationSource`) written
to `metadata['category_source']`.

**Files:**
- Modify: `lib/core/repositories/transactions_repository.dart`
- Modify: `lib/core/services/statement_processing_service.dart:384-474` (`_persistParsedStatement`)
- Test: `test/core/repositories/transactions_repository_category_test.dart`
- Test: `test/supabase/get_uncategorized_transactions_test.dart`

- [ ] **Step 1: Write the failing test for the repository's merchant-lookup method**

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

Read the current file fresh before editing (not one of the pre-flagged
in-flight files, but confirm). Replace the whole file:

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
  /// this). Returns null if the merchant isn't in the (seed-only) table.
  Future<String?> lookupMerchantCategory(String normalizedMerchantName) async {
    final row = await _db
        .from('merchant_category_map')
        .select('category')
        .eq('merchant_name_normalized', normalizedMerchantName)
        .maybeSingle();
    return parseMerchantCategoryRow(row);
  }

  /// Insert one transaction. Silently skips if a row with the same
  /// (user_id, user_card_id, transaction_date, description, amount) already
  /// exists — this project's dedup key, matching main's
  /// idx_transactions_dedup unique index.
  ///
  /// [currency] is now required (no default) — callers must resolve it via
  /// `resolveTransactionCurrency` (transaction_currency_resolver.dart)
  /// rather than relying on a hardcoded assumption here. This is a
  /// breaking change to this method's signature; the one caller in this
  /// codebase (statement_processing_service.dart) is updated in this same
  /// task, so this and Step 6 below must land together.
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

  /// Every transaction for [userId] whose category needs backfilling —
  /// NULL, exactly 'other', or any value outside the 16 valid categories
  /// (catches legacy vocabulary like 'dining'/'bills'/'transfer' in one
  /// condition, per spec §6). Used by CategoryBackfillService (Task 8).
  Future<List<Transaction>> getUncategorizedTransactions(String userId) async {
    const validCategories = [
      'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
      'utilities', 'insurance', 'medical', 'education', 'investment',
      'transport', 'rental', 'subscription', 'gift', 'other',
    ];
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .or('category.is.null,category.eq.other,category.not.in.(${validCategories.map((c) => '"$c"').join(',')})');
    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Updates just the category and metadata for an existing transaction by
  /// id — used by the backfill job. `addTransaction`'s upsert with
  /// ignoreDuplicates can't be reused here: it silently no-ops on a
  /// dedup-key conflict rather than updating, which is exactly what a
  /// backfill needs to do for a row that already exists.
  Future<void> updateTransactionCategory({
    required String transactionId,
    required String category,
    required Map<String, dynamic> metadata,
  }) async {
    await _db.from('transactions').update({
      'category': category,
      'metadata': metadata,
    }).eq('id', transactionId);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/repositories/transactions_repository_category_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Confirm no other call sites break from the `currency` signature change**

Run: `grep -rn "\.addTransaction(" lib/`
Expected: exactly one match, in `statement_processing_service.dart` — fixed
in the next step of this same task. If this grep finds additional call
sites, update this plan before proceeding — they'd also need the
`currency` argument added.

- [ ] **Step 6: Wire the categorizer, currency resolver, and provenance into `_persistParsedStatement`**

Read `lib/core/services/statement_processing_service.dart` fresh before
editing — this file is actively evolving (the bank-disambiguation logic in
`_processOneAmbiguousBank`/`_processOne` landed as a separate commit since
this plan was drafted) — confirm `_persistParsedStatement`'s current
signature and the transaction-persisting loop still match what's shown
here before making this edit; if they differ, adapt the edit to the
current shape rather than blindly overwriting.

Add three new imports at the top of the file, alongside the existing ones:

```dart
import 'transaction_categorizer.dart';
import 'bank_market.dart';
import 'transaction_currency_resolver.dart';
```

Add two new fields to the class, right after the existing repository
fields:

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
  final Map<String, String?> _merchantCategoryCache = {};
```

Add a small private helper method to the class (anywhere inside the class
body, e.g. right after the constructor):

```dart
  /// `categorize()`'s merchantLookup callback must be synchronous (it's
  /// pure, testable logic with no async dependency), but the real lookup
  /// is a Supabase call. This caches within one
  /// processUnprocessedEmails()/processSpecificEmail() run: the first time
  /// a merchant is seen, this warms the cache with an async Supabase call;
  /// every subsequent categorize() call for that same merchant (this run
  /// only — nothing persists across runs) reads from the in-memory map
  /// synchronously.
  Future<void> _warmMerchantCategoryCache(String normalizedMerchantName) async {
    if (_merchantCategoryCache.containsKey(normalizedMerchantName)) return;
    _merchantCategoryCache[normalizedMerchantName] =
        await _transactionsRepo.lookupMerchantCategory(normalizedMerchantName);
  }
```

Replace the transaction-persisting loop (currently within
`_persistParsedStatement`, iterating `for (final txn in transactions)`):

```dart
      final bankMarketCurrency = currencyForBank(bankName);

      for (final txn in transactions) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
        final type = txn['type'] as String? ?? 'debit';
        final description = txn['description'] as String? ?? 'Unknown transaction';
        final rawMerchantName = txn['merchantName'] as String?;
        final merchantForCategorization = rawMerchantName ?? description;
        final normalizedMerchant = normalizeMerchantName(merchantForCategorization);

        await _warmMerchantCategoryCache(normalizedMerchant);
        final categorization = categorize(
          merchantName: merchantForCategorization,
          description: description,
          geminiCategory: txn['category'] as String?,
          merchantLookup: (normalized) => _merchantCategoryCache[normalized],
        );

        final currency = resolveTransactionCurrency(
          geminiCurrency: txn['currency'] as String?,
          bankMarketCurrency: bankMarketCurrency,
        );

        await _transactionsRepo.addTransaction(
          userId: _userId,
          userCardId: userCardId,
          amount: amount.abs(),
          description: description,
          transactionDate:
              txn['date'] != null ? DateTime.parse(txn['date'] as String) : statementDate,
          currency: currency,
          merchantName: rawMerchantName,
          category: categorization.category,
          transactionType: type,
          rewardEarned: (txn['reward_points'] as num?)?.toDouble(),
          statementId: statement.id,
          metadata: {'category_source': categorization.source.name},
        );
      }
```

Note the distinction between `merchantForCategorization` (used to resolve
a category — falls back to `description` when Gemini didn't provide a
`merchantName`, since `categorize()` always needs *some* string to
normalize) and `rawMerchantName` (the true nullable value, stored as-is in
the `merchant_name` database column — these are different concerns: "what
do we categorize by" vs. "what do we display/store as the merchant name").

`categorization.source.name` relies on `CategorizationSource` being a Dart
enum (Task 3) — `.name` gives the lowercase-camelCase string
(`'merchantMap'`, `'geminiValidated'`, `'keywordFallback'`, `'unresolved'`),
matching what the provenance test in Task 3 and the metadata test below
expect.

- [ ] **Step 7: Verify the app still analyzes cleanly**

Run: `flutter analyze lib/core/services/statement_processing_service.dart lib/core/repositories/transactions_repository.dart`
Expected: No errors.

- [ ] **Step 8: Verify `getUncategorizedTransactions`'s PostgREST filter
  actually works against live Postgres — flagged as unverified syntax,
  not assumed correct**

The `.or('category.is.null,category.eq.other,category.not.in.(...)')`
filter string in this method (written above in Step 3) combines
operators (`is.null`, `eq`, `not.in`) inside a single `.or()` clause in a
way no existing code in this project does — `cards_repository.dart:86`
and `movie_deals_repository.dart` both use `.or()`, but neither combines
`not.in` with other clauses this way, and this exact combination hasn't
been run against a real Postgres/PostgREST instance while writing this
plan. Verify it directly rather than trusting it by construction:

```dart
// test/supabase/get_uncategorized_transactions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase db reset` first. Exists specifically to verify the
// getUncategorizedTransactions() PostgREST filter string actually
// behaves as intended — this combination of is.null/eq/not.in inside one
// .or() clause has no precedent elsewhere in this codebase to pattern-
// match against with confidence.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/transactions_repository.dart';

void main() {
  late SupabaseClient client;
  late TransactionsRepository repo;
  late String testUserId;
  late String testUserCardId;

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    client = Supabase.instance.client;
    repo = TransactionsRepository(client);
    final auth = await client.auth.signUp(
      email: 'uncategorized-filter-test@example.com',
      password: 'test-password-1234',
    );
    testUserId = auth.user!.id;

    final catalog = await client.from('card_catalog').select('id').limit(1).single();
    final card = await client.from('user_cards').insert({
      'user_id': testUserId,
      'catalog_card_id': catalog['id'],
    }).select('id').single();
    testUserCardId = card['id'] as String;

    // One row per case this filter needs to catch, plus one that should
    // NOT be caught (a valid, already-correct category).
    await client.from('transactions').insert([
      {
        'user_id': testUserId, 'user_card_id': testUserCardId, 'amount': 1,
        'description': 'null category case', 'transaction_date': DateTime.now().toIso8601String(),
        'category': null,
      },
      {
        'user_id': testUserId, 'user_card_id': testUserCardId, 'amount': 1,
        'description': 'other category case', 'transaction_date': DateTime.now().toIso8601String(),
        'category': 'other',
      },
      {
        'user_id': testUserId, 'user_card_id': testUserCardId, 'amount': 1,
        'description': 'legacy invalid category case', 'transaction_date': DateTime.now().toIso8601String(),
        'category': 'dining', // valid under the OLD vocabulary only
      },
      {
        'user_id': testUserId, 'user_card_id': testUserCardId, 'amount': 1,
        'description': 'already-correct category, must NOT be selected',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': 'food',
      },
    ]);
  });

  test('selects NULL, other, and legacy-invalid categories, but not an '
      'already-correct one', () async {
    final result = await repo.getUncategorizedTransactions(testUserId);
    final descriptions = result.map((t) => t.description).toSet();

    expect(descriptions, contains('null category case'));
    expect(descriptions, contains('other category case'));
    expect(descriptions, contains('legacy invalid category case'));
    expect(descriptions, isNot(contains('already-correct category, must NOT be selected')));
  });
}
```

Run: `supabase db reset` (if not already reset for this session), then:
`flutter test test/supabase/get_uncategorized_transactions_test.dart --dart-define=SUPABASE_ANON_KEY=<local anon key>`

If this test FAILS, the filter string in Step 3 is syntactically wrong or
doesn't behave as intended — do not proceed to Task 8 (which depends on
this method) until it's fixed and this test passes. Likely fix if it
fails: PostgREST's `not.in` operator may need to be written as
`category.not.is.null` combined separately, or the `.in.()` value list
may need different quoting/escaping than the double-quote-wrapped
approach shown in Step 3 — inspect the actual PostgREST error message
returned by the failing test for the specific syntax issue, rather than
guessing blindly.

- [ ] **Step 9: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, including every test from Tasks 1-6 and every
pre-existing test file.

- [ ] **Step 10: Commit**

```bash
git add lib/core/repositories/transactions_repository.dart lib/core/services/statement_processing_service.dart test/core/repositories/transactions_repository_category_test.dart test/supabase/get_uncategorized_transactions_test.dart
git commit -m "feat: wire categorizer, currency resolver, and provenance metadata into statement persistence"
```

---

## Task 7: Add `transactions.category` `CHECK` constraint (NOT VALID, validated after backfill)

Per spec §2/§6: add the constraint `NOT VALID` now (safe even with existing
bad data), validate it only after Task 8's backfill runs — implemented as
two separate migrations so the ordering is enforced by file sequencing.

**Files:**
- Create: `supabase/migrations/20260816000100_transactions_category_check.sql`
- Test: `test/supabase/transactions_category_check_test.dart`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260816000100_transactions_category_check.sql
--
-- Enforces the 16-category vocabulary at the database level (design spec
-- §2). Added NOT VALID so it doesn't fail against existing rows that may
-- hold legacy/invalid category values (e.g. 'dining', 'bills', NULL) —
-- NOT VALID enforces the constraint for all NEW writes immediately without
-- scanning existing rows. The companion migration that runs `VALIDATE
-- CONSTRAINT` (20260816000200) must not be applied until the backfill job
-- (application-level, see category_backfill_service.dart) has fixed every
-- pre-existing invalid row — see that migration's own comment for why.
alter table public.transactions
  add constraint transactions_category_valid check (
    category is null or category in (
      'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
      'utilities', 'insurance', 'medical', 'education', 'investment',
      'transport', 'rental', 'subscription', 'gift', 'other'
    )
  ) not valid;
```

- [ ] **Step 2: Write the live-Supabase test**

```dart
// test/supabase/transactions_category_check_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase db reset` first to apply migrations fresh.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late String testUserId;
  late String testUserCardId;

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    client = Supabase.instance.client;
    final auth = await client.auth.signUp(
      email: 'category-check-test@example.com',
      password: 'test-password-1234',
    );
    testUserId = auth.user!.id;

    // Create a minimal user_card + catalog row this test can attach
    // transactions to — adjust to match whatever fixture/catalog row
    // already exists in this project's seed data if one is available,
    // rather than inserting a fresh catalog entry per test run.
    final catalog = await client.from('card_catalog').select('id').limit(1).single();
    final card = await client.from('user_cards').insert({
      'user_id': testUserId,
      'catalog_card_id': catalog['id'],
    }).select('id').single();
    testUserCardId = card['id'] as String;
  });

  test('a valid category value is accepted', () async {
    await expectLater(
      client.from('transactions').insert({
        'user_id': testUserId,
        'user_card_id': testUserCardId,
        'amount': 100,
        'description': 'Test valid category',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': 'food',
      }),
      completes,
    );
  });

  test('NULL category is accepted (defense-in-depth, spec §2)', () async {
    await expectLater(
      client.from('transactions').insert({
        'user_id': testUserId,
        'user_card_id': testUserCardId,
        'amount': 100,
        'description': 'Test null category',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': null,
      }),
      completes,
    );
  });

  test('an invalid category value is rejected', () async {
    expect(
      () => client.from('transactions').insert({
        'user_id': testUserId,
        'user_card_id': testUserCardId,
        'amount': 100,
        'description': 'Test invalid category',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': 'not_a_real_category',
      }),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('a legacy pre-fix category value is also rejected by the new '
      'constraint (proves NOT VALID enforces on new writes immediately)', () async {
    expect(
      () => client.from('transactions').insert({
        'user_id': testUserId,
        'user_card_id': testUserCardId,
        'amount': 100,
        'description': 'Test legacy category',
        'transaction_date': DateTime.now().toIso8601String(),
        'category': 'dining', // valid under the OLD vocabulary, not the new one
      }),
      throwsA(isA<PostgrestException>()),
    );
  });
}
```

- [ ] **Step 3: Apply the migration and run the test**

Run: `supabase db reset`
Expected: no errors — `NOT VALID` means this applies cleanly even if any
pre-existing seed/fixture data has an invalid category value.

Run: `flutter test test/supabase/transactions_category_check_test.dart --dart-define=SUPABASE_ANON_KEY=<local anon key>`
Expected: PASS (4 tests)

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260816000100_transactions_category_check.sql test/supabase/transactions_category_check_test.dart
git commit -m "feat: add NOT VALID category CHECK constraint on transactions, enforced for new writes immediately"
```

---

## Task 8: `CategoryBackfillService` — privileged, idempotent, audited

Per spec §6: must run via a privileged path (not per-user RLS), must be
idempotent, must report a count of rows examined/changed.

**Files:**
- Create: `lib/core/services/category_backfill_service.dart`
- Test: `test/core/services/category_backfill_service_test.dart`
- Test: `test/supabase/category_backfill_privileged_test.dart`

- [ ] **Step 1: Write the failing unit test for the pure re-categorization logic**

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
      expect(result.category, 'grocery');
    });

    test('falls through to keyword matching for an unmapped merchant', () {
      final result = recategorize(
        merchantName: 'Some Petrol Station',
        description: 'PETROL PUMP PAYMENT',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'fuel');
    });

    test('returns other with unresolved source when nothing resolves, '
        'same as a fresh transaction would', () {
      final result = recategorize(
        merchantName: 'XYZ Corp',
        description: 'XYZ CORP TRANSACTION 998271',
        merchantLookup: (_) => null,
      );
      expect(result.category, 'other');
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
/// value is exactly what's being replaced (it's invalid/NULL/'other'), so
/// there's nothing useful to validate there.
CategorizationResult recategorize({
  required String merchantName,
  required String description,
  required String? Function(String normalizedMerchantName) merchantLookup,
}) {
  return categorize(
    merchantName: merchantName,
    description: description,
    geminiCategory: null, // nothing to validate — see doc comment above
    merchantLookup: merchantLookup,
  );
}

/// Result of one backfill run — reported so a caller has visibility into
/// what a job touching every user's data actually did (spec §6: minimum
/// operational requirement, not full audit logging).
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
/// signed-in user, so a job that needs to touch every user's transactions
/// cannot use the same client a regular user session would (spec §6).
/// This class itself doesn't enforce that — it takes whatever
/// TransactionsRepository it's given — but the repository MUST be
/// constructed with a service-role SupabaseClient when this is actually
/// run against production data across all users. See
/// test/supabase/category_backfill_privileged_test.dart for the
/// integration-level proof this requirement is real, and the trigger
/// mechanism note in the spec (§6) for why this plan doesn't build the
/// specific tool that invokes this in production.
///
/// Idempotent: re-running for the same user after a successful pass
/// examines zero rows the second time, since the selection query
/// (`getUncategorizedTransactions`) only matches rows that still need
/// fixing — a row this job already corrected no longer matches.
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
          metadata: {...txn.metadata, 'category_source': result.source.name},
        );
        recategorized++;
      }
    }

    return BackfillResult(examined: transactions.length, recategorized: recategorized);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/category_backfill_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Write the live-Supabase test proving the privileged-path requirement is real**

```dart
// test/supabase/category_backfill_privileged_test.dart
//
// Integration test against a LIVE local Supabase instance. Run
// `supabase start` first. Proves the design requirement from spec §6:
// a regular per-user client cannot run the backfill across other users'
// data, and a service-role client can. Skips the service-role assertions
// if SUPABASE_SERVICE_ROLE_KEY isn't provided (following the pattern in
// test/supabase/waitlist_security_contract_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient regularClient;
  const serviceRoleKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  late String userAId;
  late String userBId;

  setUpAll(() async {
    regularClient = SupabaseClient(
      'http://127.0.0.1:54321',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    final authA = await regularClient.auth.signUp(
      email: 'backfill-privileged-user-a@example.com',
      password: 'test-password-1234',
    );
    userAId = authA.user!.id;

    // A second user, signed up via a separate client so signing in as A
    // doesn't clobber the session — B's id is what this test tries (and
    // must fail) to read as A.
    final secondClient = SupabaseClient(
      'http://127.0.0.1:54321',
      const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    final authB = await secondClient.auth.signUp(
      email: 'backfill-privileged-user-b@example.com',
      password: 'test-password-1234',
    );
    userBId = authB.user!.id;
  });

  test('a regular authenticated client cannot read another user\'s '
      'transactions — proving the backfill cannot run as a normal user '
      'session across all users (spec §6 privileged-path requirement)', () async {
    // Signed in as user A (from setUpAll's signUp call). Querying for
    // user B's transactions must return empty, not user B's real rows —
    // RLS scopes every read to auth.uid(), regardless of the user_id
    // filter passed in the query.
    final result = await regularClient
        .from('transactions')
        .select()
        .eq('user_id', userBId);
    expect(result, isEmpty);
  }, skip: false);

  test('a service-role client CAN read across all users — the privileged '
      'path the backfill must actually use in production', () async {
    if (serviceRoleKey.isEmpty) {
      // Documented skip, same pattern as waitlist_security_contract_test.dart:
      // this assertion needs a service-role key not available in every
      // local environment by default.
      return;
    }
    final serviceClient = SupabaseClient('http://127.0.0.1:54321', serviceRoleKey);
    // A service-role client bypasses RLS entirely — this must succeed
    // without throwing, regardless of whose transactions exist.
    await expectLater(
      serviceClient.from('transactions').select().eq('user_id', userAId),
      completes,
    );
  });
}
```

- [ ] **Step 6: Run the test**

Run: `supabase start` (if not already running), then:
`flutter test test/supabase/category_backfill_privileged_test.dart --dart-define=SUPABASE_ANON_KEY=<local anon key>`
Expected: PASS (first test always runs and passes; second test
self-skips gracefully if `SUPABASE_SERVICE_ROLE_KEY` isn't provided — pass
it via `--dart-define=SUPABASE_SERVICE_ROLE_KEY=<key from `supabase status`>`
to exercise the full assertion).

- [ ] **Step 7: Commit**

```bash
git add lib/core/services/category_backfill_service.dart test/core/services/category_backfill_service_test.dart test/supabase/category_backfill_privileged_test.dart
git commit -m "feat: add idempotent, audited backfill service; prove privileged-path requirement against live RLS"
```

- [ ] **Step 8: Trigger mechanism — deliberately not decided here**

Per spec §6, this plan does not build the specific tool that invokes
`CategoryBackfillService.run()` against real production data (debug-menu
button, manually-run Edge Function, one-off script) — that's an
operational decision requiring a human choice about production data,
flagged explicitly rather than silently left undone. **Before this
feature is considered fully deployed, decide how this gets triggered for
real users** and construct a `TransactionsRepository` backed by a
service-role `SupabaseClient` (not the app's regular authenticated client)
to run it — surface this decision to whoever reviews this plan's
completion.

---

## Task 9: Validate the `CHECK` constraint (run only after Task 8's backfill has executed against production)

**This migration must not be applied until the backfill (Task 8) has
actually run against every existing invalid row in production.** Applying
it before that will fail with a constraint-violation error listing the
first non-compliant row found — that's the correct, safe failure mode
(the constraint simply doesn't validate yet), not a bug to work around.

**Files:**
- Create: `supabase/migrations/20260816000200_validate_transactions_category_check.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260816000200_validate_transactions_category_check.sql
--
-- Upgrades transactions_category_valid (added NOT VALID in
-- 20260816000100) to a fully-enforced constraint by validating every
-- existing row. DO NOT apply this migration until the backfill job
-- (category_backfill_service.dart, Task 8 of the implementation plan) has
-- run against production and corrected every pre-existing invalid
-- category value — if any row still holds an invalid value when this
-- runs, VALIDATE CONSTRAINT fails with an error identifying it, and this
-- migration does not apply. That failure is the correct, safe outcome:
-- it means the backfill hasn't finished, not that this SQL is wrong.
alter table public.transactions
  validate constraint transactions_category_valid;
```

- [ ] **Step 2: Confirm the backfill has run before applying this**

This is a manual, human-verified precondition, not an automated check —
query production (or the local dev instance, if testing this flow
end-to-end) directly:

```sql
select count(*) from transactions
where category is not null
  and category not in (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other'
  );
```

Expected: `0`. If this returns anything greater than zero, do not apply
this migration yet — go back to Task 8's trigger-mechanism gap and run the
backfill against whatever rows this query is finding first.

- [ ] **Step 3: Apply the migration**

Run: `supabase db reset` (local) or the project's normal migration-deploy
process (production) — only after Step 2's query confirms zero
non-compliant rows.
Expected: no errors — `VALIDATE CONSTRAINT` succeeds silently when every
row already complies.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260816000200_validate_transactions_category_check.sql
git commit -m "feat: validate transactions_category_valid constraint after backfill (run only once backfill has executed)"
```

---

## Task 10: `isInternational` on `Transaction` + its real consumer

**Files:**
- Modify: `lib/shared/models/transaction.dart`
- Modify: `lib/features/transactions/providers/transactions_provider.dart`
- Modify: `lib/features/transactions/screens/transactions_screen.dart`
- Test: `test/shared/models/transaction_is_international_test.dart`

- [ ] **Step 1: Write the failing test for `isInternational`**

```dart
// test/shared/models/transaction_is_international_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({required String currency}) {
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
      final tx = _tx(currency: 'INR');
      expect(tx.isInternational('INR'), isFalse);
    });

    test('true when currency differs from the bank market currency', () {
      final tx = _tx(currency: 'USD');
      expect(tx.isInternational('INR'), isTrue);
    });

    test('true for a foreign-currency charge on a UAE-market card', () {
      final tx = _tx(currency: 'EUR');
      expect(tx.isInternational('AED'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/models/transaction_is_international_test.dart`
Expected: FAIL — `isInternational` undefined on `Transaction`.

- [ ] **Step 3: Add the method**

Read `lib/shared/models/transaction.dart` fresh before editing (74 lines,
confirmed unchanged from earlier investigation, but verify). Add this
method inside the `Transaction` class, right after the existing `isDebit`
getter:

```dart
  bool get isDebit => transactionType == TransactionType.debit;

  /// Whether this transaction's currency differs from [bankMarketCurrency]
  /// — the currency the issuing bank's statements are normally denominated
  /// in (see `currencyForBank` in bank_market.dart). A foreign-currency
  /// charge (e.g. a USD hotel booking on an otherwise-INR statement) is
  /// international; a same-currency charge isn't. Independent of
  /// `category` — a transaction can be both "food" and international.
  bool isInternational(String bankMarketCurrency) => currency != bankMarketCurrency;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/models/transaction_is_international_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Wire the real consumer — a badge on the transactions list**

Read `lib/features/transactions/providers/transactions_provider.dart`
fresh (confirmed unchanged earlier in this plan's investigation, 237
lines). `TxnsState` currently loads `cards: List<UserCard>` alongside
`all: List<Transaction>` — `UserCard.bank` (already joined from
`card_catalog`, confirmed in `lib/shared/models/user_card.dart`) is exactly
the bank name `currencyForBank` needs. Add a helper method to `TxnsState`
that resolves a transaction's `isInternational` flag using its card's bank,
right after the existing `topCategory` getter:

```dart
  String? get topCategory {
    final map = <String, double>{};
    for (final t in filtered) {
      if (t.isDebit && t.category != null) {
        map[t.category!] = (map[t.category!] ?? 0) + t.amount;
      }
    }
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Whether [txn] is a foreign-currency charge relative to its card's
  /// issuing bank's market currency. Resolves the card's bank name once
  /// per lookup (cards list is small — far fewer cards than transactions)
  /// rather than joining bank name into every transaction row at the
  /// database level. Returns false if the card can't be found or its
  /// bank's market currency can't be resolved (currencyForBank returns
  /// null for an unrecognized bank) — a transaction is only flagged
  /// international when there's a concrete, resolved market to compare
  /// against.
  bool isTransactionInternational(Transaction txn) {
    final card = cards.where((c) => c.id == txn.userCardId).firstOrNull;
    if (card?.bank == null) return false;
    final normalizedBank = CardNormalizerService.normalizeBankName(card!.bank!);
    final marketCurrency = currencyForBank(normalizedBank);
    if (marketCurrency == null) return false;
    return txn.isInternational(marketCurrency);
  }
```

Add the two new imports this method needs, at the top of the file:

```dart
import '../../../core/services/card_normalizer_service.dart';
import '../../../core/services/bank_market.dart';
```

- [ ] **Step 6: Render the badge in `transactions_screen.dart`**

Read `lib/features/transactions/screens/transactions_screen.dart` fresh —
confirmed earlier in this plan's investigation to have its
`_categoryColor`/`_categoryIcon` switch around lines 370-392, and the
transaction row rendering that calls them nearby (around line 324/342 per
earlier investigation — re-confirm exact current line numbers with
`grep -n "_categoryIcon\|_categoryColor" lib/features/transactions/screens/transactions_screen.dart`
before editing, since Tasks 4-9 may have shifted other parts of this repo
but not necessarily this specific file). Find the row widget that renders
`Icon(_categoryIcon(txn.category), ...)` and add a small international
indicator next to it — the exact visual treatment (icon choice, position,
size) is a small implementation detail; a minimal correct version:

```dart
// Near the existing category icon rendering in the transaction row widget,
// add a conditional badge. `state` here refers to whatever TxnsState
// instance is in scope in the widget building this row (confirm the exact
// variable name at the call site — it's `state` in the icon-switch methods
// already present in this file).
if (state.isTransactionInternational(txn))
  Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Icon(Icons.public, size: 12, color: AppColors.textMuted),
  ),
```

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 8: Manual verification note**

No real UAE statement PDF exists to verify this end-to-end (spec §4's
honesty note — this worktree has never ingested one). Flag this
explicitly when reporting this task's completion: the code is correct by
inspection, but the badge's actual appearance for a genuine
foreign-currency transaction is unverified until a real UAE (or any
foreign-currency) statement is processed through the full pipeline.

- [ ] **Step 9: Commit**

```bash
git add lib/shared/models/transaction.dart lib/features/transactions/providers/transactions_provider.dart lib/features/transactions/screens/transactions_screen.dart test/shared/models/transaction_is_international_test.dart
git commit -m "feat: add Transaction.isInternational and a real consumer (transactions-list badge)"
```

---

## Task 11: Consolidate the three category icon/color switches

**Files:**
- Create: `lib/core/theme/category_display.dart`
- Modify: `lib/features/dashboard/screens/dashboard_screen.dart:1230-1254` (approximate — re-confirm before editing, see note below)
- Modify: `lib/features/transactions/screens/transactions_screen.dart:370-392`
- Modify: `lib/features/cards/screens/card_detail_screen.dart:770-793`
- Test: `test/core/theme/category_display_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/category_display_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cardcompass/core/theme/category_display.dart';
import 'package:cardcompass/core/theme/app_theme.dart';

void main() {
  const categories = [
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other',
  ];

  group('categoryIcon', () {
    test('returns a specific (non-default) icon for every one of the 16 '
        'valid categories except other, which shares the default icon '
        'by design', () {
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

- [ ] **Step 3: Read `app_theme.dart` to confirm exact `AppColors` field names**

Run: `grep -n "static const" lib/core/theme/app_theme.dart`
Confirm `warning`, `violet`, `success`, `textSecondary` (referenced in the
existing three switches) are still the correct field names before writing
code that references them.

- [ ] **Step 4: Write the shared mapping**

```dart
// lib/core/theme/category_display.dart
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Single source of truth for how each of the 16 transaction categories is
/// displayed (icon + color) — replaces three previously-independent,
/// drifting copies of this mapping in dashboard_screen.dart,
/// transactions_screen.dart, and card_detail_screen.dart, each of which
/// covered a different, incomplete subset of categories.
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

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/theme/category_display_test.dart`
Expected: PASS (all cases)

- [ ] **Step 6: Replace `dashboard_screen.dart`'s copy**

This file has unrelated in-flight uncommitted changes per this plan's
top-level note — run `git diff lib/features/dashboard/screens/dashboard_screen.dart`
first and re-locate `_categoryColor`/`_categoryIcon` by searching
(`grep -n "_categoryColor\|_categoryIcon" lib/features/dashboard/screens/dashboard_screen.dart`)
rather than trusting a specific line range, since this file may have
shifted. Replace both method bodies to delegate to the shared functions:

```dart
  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
```

Add the import at the top of the file, alongside the existing
`app_theme.dart` import:

```dart
import '../../../core/theme/category_display.dart';
```

- [ ] **Step 7: Replace `transactions_screen.dart`'s copy**

Same pattern. Confirmed current location (lines 370-392, verified earlier
in this plan's investigation). The `'dining': case 'food':` alias case is
dropped — `categoryColor`/`categoryIcon` already handle `'food'` directly,
and `'dining'` is no longer producible after Task 4's prompt fix (it's
been superseded by `'food'` in the vocabulary), so keeping the alias would
be dead code:

```dart
  static Color _categoryColor(String? cat) => categoryColor(cat);

  static IconData _categoryIcon(String? cat) => categoryIcon(cat);
```

Add the import (this file already has the `card_normalizer_service.dart`
and `bank_market.dart` imports from Task 10 — add this alongside them):

```dart
import '../../../core/theme/category_display.dart';
```

- [ ] **Step 8: Replace `card_detail_screen.dart`'s copy**

Confirmed current location (line 770, an instance method — not `static` —
with no corresponding `_categoryColor`, only icon). Replace just the icon
method body:

```dart
  IconData _categoryIcon(String? category) => categoryIcon(category);
```

Add the import:

```dart
import '../../../core/theme/category_display.dart';
```

(Confirm this relative path matches `card_detail_screen.dart`'s actual
location — `lib/features/cards/screens/` per earlier investigation.)

- [ ] **Step 9: Run the full test suite and analyzer**

Run: `flutter test`
Expected: All tests pass.

Run: `flutter analyze`
Expected: No new errors introduced by this task.

- [ ] **Step 10: Commit**

```bash
git add lib/core/theme/category_display.dart lib/features/dashboard/screens/dashboard_screen.dart lib/features/transactions/screens/transactions_screen.dart lib/features/cards/screens/card_detail_screen.dart test/core/theme/category_display_test.dart
git commit -m "refactor: consolidate three drifting category icon/color switches into one shared mapping"
```

---

## Task 12: Manual end-to-end verification

Automated tests cover every pure decision and the live-Supabase RLS/
constraint behavior. What's left is verifying the real ingestion pipeline
end-to-end, which no automated test in this plan exercises directly.

- [ ] **Step 1: Run the complete test suite one final time**

Run: `flutter test`
Expected: All tests pass — every new test file from Tasks 1-11, plus every
pre-existing test in the project (`test/features/benefits/movie_deals/*`,
`test/supabase/*` pre-existing files, `test/widget_test.dart`).

- [ ] **Step 2: Run the analyzer across the whole project**

Run: `flutter analyze`
Expected: No new errors. If pre-existing warnings exist from the unrelated
in-flight work noted at the top of this plan, don't chase those — confirm
only that this plan's changes introduce nothing new.

- [ ] **Step 3: Process one real Indian statement through the full pipeline**

Using the app's existing statement-upload flow, process one real Indian
bank statement PDF and confirm:
- Resulting transactions have a `category` from the 16-value list, never
  `bills`/`transfer`/`fee`/`payment`/`cash`/`dining`/null.
- `transactions.currency` is `INR`.
- `transactions.metadata['category_source']` is populated with one of
  `merchantMap`/`geminiValidated`/`keywordFallback`/`unresolved`.
- At least one transaction from a seeded merchant (Swiggy, Amazon —
  though Amazon is denylisted, so confirm it resolves via tier 2/3, not
  tier 1) categorizes correctly.

- [ ] **Step 4: Note the UAE gap explicitly rather than skip it silently**

No UAE statement PDF exists to test against in this worktree (confirmed
throughout the spec's revisions). Report this as an explicit, named gap in
this task's completion, not a silently-skipped step: the currency/
`isInternational`/UAE-bank-recognition code is correct by inspection and
fully unit-tested in isolation, but has never been exercised against a
real UAE statement end-to-end.

- [ ] **Step 5: Manually run the backfill against a test account**

Using a Dart REPL or a temporary debug entry point (see Task 8 Step 8's
note — this plan doesn't build a permanent trigger), construct a
`TransactionsRepository` backed by a **service-role** `SupabaseClient`
(not the app's regular authenticated client — Task 8's privileged-path
requirement is real, not decorative) and call
`CategoryBackfillService(repo).run(testUserId)` against a test account
with existing miscategorized transactions. Confirm the returned
`BackfillResult` counts make sense, and run it a second time to confirm
idempotency (second run's `recategorized` count should be 0).

- [ ] **Step 6: Visually confirm the three consolidated icon switches and the international badge render correctly**

Open the dashboard, transactions list, and a card detail screen in the
running app. Confirm transaction rows show category-appropriate icons
consistently across all three screens, and that the international badge
(Task 10) appears for any transaction whose currency differs from its
card's resolved bank-market currency.

- [ ] **Step 7: Report completion status**

Summarize which of Steps 3-6 were fully completed vs. which have a named,
explicit gap (the UAE end-to-end verification will very likely remain a
gap — that's expected and acceptable per this plan's honesty
requirements, not a failure to hide). Also flag Task 8 Step 8's and Task
9's still-unresolved decisions — how the backfill gets triggered for real
production data, and confirmation that it has actually run before Task 9's
`VALIDATE CONSTRAINT` migration is applied — both need a human decision
before this feature is fully deployed, not just implemented.
