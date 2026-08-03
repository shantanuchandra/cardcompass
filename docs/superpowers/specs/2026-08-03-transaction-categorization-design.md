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
- **Fixing `TransactionType` extraction (added after second review pass).**
  The Gemini prompt only ever requests `debit|credit`, never `refund`,
  `fee`, `interest`, or `reward`, despite `TransactionType` having all
  five values (see the Taxonomy section's correction, above). This is a
  real gap — fee/interest charges are indistinguishable from ordinary
  spend today — but it's a transaction-*type* extraction problem,
  independent of the transaction-*category* extraction this spec fixes.
  Fixing both in one spec would conflate two different vocabularies
  again, the exact mistake this spec corrects for `category`. Flagged
  explicitly as follow-up work, not silently left for the categorizer to
  paper over (it won't — a fee transaction will categorize as `other`,
  correctly reflecting that it isn't spend on anything, but will still be
  *counted* as spend by anything that sums debit amounts without checking
  `transactionType`, e.g. `transactions_provider.dart`'s `totalSpend`,
  `TxnsState.totalSpend`, currently unconditional on `t.isDebit` — this
  spec doesn't change that either).

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

**"Sufficient" means the 16 values cover every real category — it does
not mean every value has an equally reliable path to being selected,
correction added after a second review pass.** Checked the actual seed
data and keyword rules being built: `investment`, `rental`, and `gift`
appear in the valid-category list and the display mapping (§5), but have
**no seed merchants and no keyword rules** — confirmed by inspecting the
implementation plan's merchant seed map and keyword-fallback rule list
directly. These three categories can only ever be selected via tier 2
(Gemini's own per-transaction value happening to be exactly one of these
three strings) — there is no deterministic path to them at all. This
isn't a defect in the 16-value list itself (a rent payment genuinely is
`rental`, not some other category), it's an honest limitation in *how
reliably* three of the sixteen can be detected from a bank statement line
with the mechanisms this spec builds — rent payments, gift purchases, and
investment transactions don't have obvious universal keyword signatures
the way "SWIGGY" or "PETROL PUMP" do. Left as a named gap rather than
papered over with speculative keyword rules that would likely be wrong
more often than they're right (e.g. what generic word reliably signals
"rental" without also matching unrelated transactions?).

v2's current prompt vocabulary (`shopping, dining, travel, fuel,
entertainment, bills, transfer, fee, payment, cash, other`) gets replaced by
this list. `bills` maps to `utilities`. `transfer`, `fee`, `payment`, `cash`
are dropped from the *category* vocabulary — they describe how money moved
or what kind of charge it was, not what it was spent on.

**Correction (post-review, second pass):** the previous version of this
spec claimed `TransactionType` "already exists to capture" these four
values, citing the enum's `debit, credit, refund, fee, interest, reward`
values as if they were already being extracted. Checked directly and
that's not true in practice: `gemini_statement_parser.dart`'s prompt
(line 210) only ever asks Gemini for `"type": "debit|credit"` — never
`refund`, `fee`, `interest`, or `reward`, despite the enum having all
five. So today, a genuine fee/interest-charge line item gets extracted as
a plain `debit` with (after this fix) a category of `other`, rather than
being identified as a non-spend movement at all. Removing `fee`/`payment`/
`cash`/`transfer` from the *category* vocabulary is still correct — they
were never a coherent spend category — but claiming `TransactionType`
already "captures" them was wrong; nothing currently extracts that
distinction. Fixing the prompt to actually request the full
`TransactionType` vocabulary (`debit|credit|refund|fee|interest|reward`)
is a real, separate piece of work this spec does not do — it's a
transaction-*type* extraction gap, independent of transaction-*category*
extraction, and conflating the two is exactly the mistake being corrected
here. Noted as an explicit non-goal below rather than silently assumed
solved.

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
  category TEXT NOT NULL CHECK (category IN (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
    'utilities', 'insurance', 'medical', 'education', 'investment',
    'transport', 'rental', 'subscription', 'gift', 'other'
  )),
  source TEXT NOT NULL DEFAULT 'seed' CHECK (source IN ('seed', 'keyword_fallback')),
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**Write trust model — revised again after a second review pass.** The
previous revision specified a `SECURITY DEFINER` RPC as the only write
path, correctly closing off direct client `INSERT`/`UPDATE`. What it
missed: the RPC itself still accepted `category` and `source` as
client-supplied string parameters with no validation *inside the
function* — meaning a buggy or malicious authenticated client could call
`upsert_merchant_category('AMAZON', 'gift', 'seed')` and the function
would happily insert it, mislabeled as trustworthy seed data, for every
user, permanently (per the first-write-wins rule below). The `CHECK`
constraints added to the table above catch this at the *storage* layer
(an invalid `category` value can no longer be inserted at all, by anyone,
including this RPC), but the RPC should still not trust client input
blindly:

```sql
CREATE OR REPLACE FUNCTION upsert_merchant_category(
  p_merchant_name_normalized TEXT,
  p_category TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Reject empty/oversized input before it reaches the table's own
  -- CHECK constraints — a clearer failure than a generic constraint
  -- violation, and cheaper than letting Postgres do the rejecting.
  IF p_merchant_name_normalized IS NULL
     OR length(trim(p_merchant_name_normalized)) = 0
     OR length(p_merchant_name_normalized) > 200 THEN
    RAISE EXCEPTION 'invalid merchant_name_normalized';
  END IF;

  INSERT INTO merchant_category_map (merchant_name_normalized, category, source)
  VALUES (trim(upper(p_merchant_name_normalized)), p_category, 'keyword_fallback')
  ON CONFLICT (merchant_name_normalized) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION upsert_merchant_category(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_merchant_category(TEXT, TEXT) TO authenticated;
```

Two changes from the previous revision, both closing the same class of
gap: **`p_source` is removed from the function's parameters entirely** —
the only legitimate caller of this RPC is the app's own keyword-fallback
tier (§3, tier 3; seed rows are inserted by the migration directly, never
through this RPC), so the function hardcodes `source = 'keyword_fallback'`
rather than trusting a client to self-report it. **`REVOKE ... FROM
PUBLIC`** is explicit rather than assumed — Postgres grants `EXECUTE` on
new functions to `PUBLIC` by default, so without this line, any
authenticated *or unauthenticated* Supabase role could call the function;
the previous revision's "`GRANT EXECUTE ... TO authenticated`" alone
looked sufficient but didn't override the implicit `PUBLIC` grant.

- Every authenticated user can **read** the table directly (it's not
  per-user data).
- **The first categorization for a merchant wins, permanently, from the
  app's perspective** (`ON CONFLICT ... DO NOTHING`). This is a
  deliberate simplification, not an oversight: it avoids a single bad
  keyword-fallback guess silently overwriting a previously-correct row,
  at the cost of also preventing a later *correct* re-classification from
  overwriting an earlier wrong one automatically. Correcting a wrong row
  already in the table is a manual operation (direct SQL against the
  table, bypassing the RPC) — out of scope for this spec, since no
  tooling exists yet for operator-driven corrections and none is built
  here.
- `source = 'keyword_fallback'` (now server-controlled, never
  client-supplied — see above) distinguishes runtime-learned rows from
  the hand-seeded `'seed'` rows, so it's possible to audit later which
  rows came from a one-off keyword match on a single transaction's
  description vs. a deliberately curated seed list.

**Known-ambiguous merchants are excluded from this table entirely (added
after a second review pass — see the note in §3 on ambiguity, this is
the concrete mechanism).** A merchant like Amazon spans multiple real
categories (plain shopping, Amazon Fresh groceries, Prime subscription)
that a bare merchant name can't disambiguate — and because of the
first-write-wins rule above, permanently locking Amazon to whichever
category its *first-ever* transaction happened to be would silently
miscategorize every other kind of Amazon purchase forever, with no
mechanism to fix it short of a manual database edit. Rather than accept
that, a small hardcoded denylist (`lib/core/services/ambiguous_merchants.dart`
— just `{'AMAZON', 'PAYPAL'}` to start, extend as more are found) is
checked *before* the merchant-lookup tier runs: a denylisted merchant
never queries or writes `merchant_category_map` at all, and always falls
through to tier 2 (Gemini's own per-transaction value) or tier 3 (keyword
matching on `description`), both of which can react to per-transaction
context (`"AMAZON PRIME MEMBERSHIP"` vs. `"AMAZON.IN PURCHASE"`) that a
bare merchant name can't. This trades determinism for correctness on a
small, explicitly-maintained set of merchants known to be genuinely
multi-category — most seeded merchants (Carrefour, Swiggy, ADNOC) aren't
ambiguous and keep the deterministic, fast merchant-map path.

**Merchant-name normalization scope, addressed explicitly after a second
review pass (previously left entirely to the implementation plan, never
specified here).** The review's concern: real statement descriptors carry
gateway prefixes, reference numbers, punctuation, and legal suffixes, so
exact-match lookup after only uppercase/trim/whitespace-collapse will miss
most seed rows. Checked before deciding whether to expand this spec's
scope: `gemini_statement_parser.dart`'s prompt already instructs Gemini to
**clean merchant names before they ever reach this pipeline** — "Clean
merchant names (remove codes, URLs, extra numbers)" (line 198), and the
JSON schema explicitly asks for `"merchantName": "Primary merchant name"`
(line 208) and `"description": "Clean merchant name without codes"`
(line 205). This is real, existing mitigation this spec hadn't credited.
Given that, the case/whitespace normalization already specified is kept
as a cheap second layer on top of Gemini's own cleanup, rather than this
spec adding a second, redundant canonicalization system (stripping legal
suffixes, location codes, gateway prefixes) to solve a problem already
substantially mitigated upstream. This is a deliberate scope decision, not
an oversight — if real-world testing (once actual UAE statements are
available, per §4's honesty note) shows Gemini's cleanup is insufficient
in practice for a meaningful share of transactions, expanding
normalization is a small, contained follow-up to this table's lookup
function, not a redesign.

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
The merchant-lookup table still gets priority (step 1) — **except for
denylisted ambiguous merchants (see §1), which skip step 1 entirely and
go straight to step 2.** For everything else, a known merchant is
deterministic even if Gemini's per-transaction guess would've differed
run to run. Step 3 (keyword fallback on `description`) exists for the case
where the merchant is unrecognized (or denylisted) *and* Gemini's returned
value isn't one of the 16 valid categories (e.g. it hallucinates something
outside its own instructed vocabulary) — built from scratch here, seeded
with the same kind of India + UAE merchant keywords the main-repo spec
described (Swiggy/Zomato/Flipkart/Ola/Careem/Talabat/Carrefour/ADNOC/etc.),
since no prior keyword list exists in this worktree to promote from.

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
   as the last-resort default, used only when Gemini's per-transaction
   value is missing. This requires teaching
   `CardNormalizerService.normalizeBankName` to recognize UAE banks at
   all, since it currently only recognizes Indian ones — **and this
   ordering matters, corrected after a second review pass:** the existing
   Indian-bank checks in `normalizeBankName` include generic
   `lower.contains('hsbc')` and `lower.contains('citi')` matches. If UAE
   bank checks (`hsbc uae`, `citi uae`) are appended *after* those generic
   checks, they become unreachable — Dart's if/else-if chain matches the
   generic Indian check first and never evaluates the more specific UAE
   one, even when the raw sender/subject name explicitly says "UAE." The
   UAE-specific checks for shared-brand banks (HSBC, Citibank) must be
   ordered *before* their generic Indian-bank counterparts in the
   if/else-if chain, not after. Banks with no Indian namesake (FAB,
   Emirates NBD, ADCB, Mashreq, CBD, RAKBANK) don't have this ordering
   hazard and can be added in any position.

   **`currencyForBank` must not silently default to INR for an
   unrecognized bank name** — the previous revision of this spec treated
   "default to INR" as safe for any name not recognized as UAE, but that
   masks exactly the failure this section is trying to prevent: if a real
   UAE bank isn't in the recognized list (or is unreachable due to the
   ordering hazard above), the currency-resolution code should surface
   that as an explicit unresolved/unknown-market result rather than
   quietly asserting INR. Return a nullable/sentinel value instead of a
   bare `String` default, and let the caller (layer 3 above) decide what
   to do with "market unknown" — likely falling through to whatever
   Gemini's own per-transaction currency value was (layer 1+2), if any,
   rather than overriding it with a guess.

Priority order per transaction: Gemini's own reported currency (layer 1+2,
now actually read) → `currencyForBank` fallback (layer 3) → hardcoded
`'INR'` never happens again as a bare, unconditional default.

Add a derived `isInternational` method on `Transaction`:
`currency != bankMarketCurrency`, where `bankMarketCurrency` is the same
`currencyForBank(bankName)` result from layer 3 — the bank's *default*
market currency, independent of what this specific transaction's currency
turned out to be. Independent signal from `category`, not a new category
value (a foreign-currency restaurant charge is still "food," and separately
"international").

**This spec requires at least one real caller of `isInternational`,
added after a second review pass — a signal with no consumer is
incomplete, not merely unused.** The concrete consumer: the transactions
list (`transactions_screen.dart`, via `transactions_provider.dart`)
already renders each transaction's category icon per row (§5); add an
international-currency badge/indicator next to it, visible when
`isInternational(bankMarketCurrency)` is true for that row.
`bankMarketCurrency` for a loaded `Transaction` is resolved the same way
as at ingestion time — via the bank name of the card the transaction
belongs to (`userCardId` → `user_cards.catalog_card_id` → `card_catalog.bank`
→ `currencyForBank`) — which means `transactions_provider.dart`'s existing
query needs to either join that bank name in, or the provider resolves it
per-card once (there are far fewer cards than transactions) and looks it
up per row rather than re-deriving it per transaction. Exact query
shape/join strategy is an implementation-plan detail; the requirement
this spec fixes is that *a* real, named consumer exists and is specified,
not left for the plan to invent or skip.

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

**Scope, made precise after a second review pass** — the previous
revision said "re-categorizing existing transactions" without defining
which ones need it, which a prior implementation (predating this
revision) narrowed to only `category = 'other'` exactly. That's
insufficient: a transaction stored under the *old*, now-invalid
vocabulary (`'dining'`, `'bills'`, `'transfer'`, `'fee'`, `'payment'`,
`'cash'`, or any casing/spelling variant Gemini emitted before this fix)
is not literally `'other'`, but is exactly as wrong as one that is — and
once the `CHECK` constraint from §2 is added, any row holding one of
these now-invalid values would violate it. **The backfill must run, and
the `CHECK` constraint must be added, in a specific order relative to
each other**, addressed below. The backfill's selection query needs to
target every row where `category` is:

- `NULL`, or
- exactly `'other'`, or
- **not** one of the 16 valid values (catches every legacy/invalid string
  in one condition, rather than enumerating each legacy value by name —
  more robust against a legacy value this spec's authors didn't think to
  list, including anything Gemini hallucinated outside even its own old,
  wrong vocabulary).

**Constraint-vs-backfill ordering, addressing the review's concern that a
normal `CHECK` constraint would fail immediately if legacy invalid rows
already exist:** add the constraint as `NOT VALID` first (Postgres
enforces it for all *new* writes immediately, without scanning/validating
existing rows, so it can be added safely even with known-bad data
present), run the backfill second (which naturally fixes every row the
constraint would otherwise reject), then run `VALIDATE CONSTRAINT`
third to confirm every existing row now complies and upgrade it to a
fully-enforced constraint. If the backfill can't run immediately after
the constraint is added `NOT VALID` (e.g. it's a separate deploy step),
the window between them is safe — `NOT VALID` doesn't block existing rows
from being read or updated, only rejects *new* writes of invalid values,
so legacy rows sit in a known-bad-but-not-blocking state until the
backfill reaches them.

**Trigger mechanism — deliberately deferred, not decided, called out
explicitly rather than left implicit.** This spec does not decide how the
backfill job gets invoked for real production data (a temporary
debug-menu button, a manually-run Supabase Edge Function, a one-off
script run directly against production) — that's an operational decision
requiring a human choice about production data, out of place in a design
spec whose scope is the categorization pipeline itself. What this spec
does commit to: the backfill's selection query (above) and its
constraint-ordering relationship (above) are both fully specified
regardless of *how* it's triggered, so the implementation plan has
something unambiguous to build a trigger mechanism around, rather than
needing to also invent the query logic.

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
  - Gemini prompt: **corrected after a second review pass** — the prompt
    *text itself* is a static, deterministic string, and asserting
    against it is exactly as testable as any other string. What's
    genuinely untestable is *Gemini's actual response* to that prompt
    (an LLM call, not deterministic). So: extract the prompt-building
    logic into a function returning the prompt string (rather than
    inlining it in `parseTransactions()`), and add a unit test asserting
    the returned string contains the expected currency instruction and
    does not contain the old hardcoded `"INR"` literal — this catches a
    future edit accidentally reintroducing the hardcoded value, which a
    "we can't test this" stance would silently miss. Live LLM behavior
    (whether Gemini actually complies) stays a separate,
    manual/integration concern, consistent with the note on the category
    prompt below.
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
