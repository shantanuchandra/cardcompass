# Transaction Normalization, Merchant Identity, Category, and MCC

**Status:** Canonical MVP subsystem specification

**Parent:** [CardCompass Product Source of Truth](00-cardcompass-source-of-truth-index.md)

## Goal

Turn parsed ledger rows into deduplicated, consistently typed transactions with
a canonical merchant, fixed spend category, and trustworthy-or-labelled MCC
data for analytics and card recommendation.

## Canonical transaction

A normalized transaction contains:

- `user_card_id` and `statement_id`;
- transaction and posting dates when available;
- issuer description;
- canonical merchant name and original merchant text;
- billed amount and currency;
- original amount/currency when both are present in the source and supported;
- transaction type;
- spend category;
- MCC code and description when available;
- reward earned when stated;
- international-spend signal;
- enrichment source/confidence metadata; and
- a deduplication identity.

## Transaction types and eligible spend

Transaction type and spend category are separate concepts. The transaction type
must distinguish at least retail debit, credit/payment, refund, fee, interest,
reward, and cash withdrawal where the statement provides enough information.

Eligible spend totals include billed retail purchases. They exclude payments,
refunds, fees, interest, rewards, and cash withdrawals by default. Refunds
reduce the applicable merchant/category spend when they can be reliably linked.

## Deduplication and alert reconciliation

Statement transactions use a stable identity derived from user card, date,
normalized description, amount, currency, and type. Reprocessing the same
statement must not create duplicates.

Instant alert-email transactions are provisional. When an official statement
arrives:

- match likely alert and statement rows;
- preserve both source references;
- use the statement as the authoritative billed record;
- update differing merchant/date/currency facts when justified; and
- never count both rows in spend analytics.

## Merchant normalization

Normalize casing, punctuation, repeated whitespace, terminal/reference IDs,
payment-rail prefixes, and predictable location suffixes while retaining the
original issuer description.

Resolution order:

1. verified merchant alias/registry match;
2. deterministic normalization and context rules;
3. constrained AI merchant resolution;
4. unknown.

UPI, Paytm, Razorpay, wallets, and similar values are payment rails or
aggregators unless the underlying merchant is identifiable. Do not assign the
aggregator's identity to the merchant-specific recommendation context.

Useful merchant attributes include:

- canonical name;
- aliases;
- country/market;
- online/offline channel when known;
- merchant subtype, such as airline, hotel, quick commerce, restaurant, or
  supermarket;
- verified and inferred MCC candidates; and
- resolution source/confidence.

## Category taxonomy

The fixed values are:

`food`, `fuel`, `grocery`, `entertainment`, `travel`, `shopping`,
`utilities`, `insurance`, `medical`, `education`, `investment`, `transport`,
`rental`, `subscription`, `gift`, `other`.

Classification order follows the corrected v2 categorization design:

1. seed/verified merchant mapping;
2. validated Gemini category;
3. keyword fallback;
4. `other`.

Only fixed values may reach the canonical category field. Common aliases are
normalized, for example dining -> food, groceries/supermarket -> grocery,
bills -> utilities, and healthcare -> medical.

The category source uses the existing v2 provenance vocabulary where possible:
`merchantMap`, `geminiValidated`, `keywordFallback`, or `unresolved`.

The shared merchant map remains seed/curation driven for the MVP. Do not write
user-derived merchant descriptions into a global shared mapping automatically.

## Hybrid MCC enrichment

MCC is independent of the CardCompass category. Resolve in this order:

1. issuer-confirmed MCC from the statement or trusted issuer data;
2. verified external MCC provider;
3. curated merchant registry;
4. inferred probable MCC from merchant identity/category;
5. unknown.

Store or expose:

- `mcc_code`;
- `mcc_description`;
- `mcc_source`: `bank_statement`, `verified_provider`, `merchant_registry`,
  `inferred`, or `unknown`;
- `mcc_confidence`; and
- `mcc_verified_at` when applicable.

Inferred MCCs are always labelled and never overwrite issuer-confirmed MCCs.
Recommendation rules that depend on MCC may use an inferred MCC only with
reduced confidence and an explicit caveat.

## Currency and international transactions

Resolve currency from explicit parsed transaction data first and the owned
card's issuer market second. Do not silently default an unknown issuer to INR.

The card's market/home currency should ultimately be catalog data. Until that
is fully owned by the catalog, the corrected v2 bank-market resolver is the MVP
source.

`isInternational` means the transaction currency differs from the owned card's
home currency. It is an attribute, not a spend category.

When a statement provides original and billed values, billed amount/currency is
authoritative for spend totals; original values remain contextual.

## Backfill

Existing rows may be recategorized and enriched through an idempotent privileged
backfill. It must:

- use the same production normalizer;
- avoid overwriting stronger issuer-confirmed facts;
- record counts by outcome;
- be safe to rerun; and
- complete before validating stricter database constraints.

## Acceptance criteria

- Every transaction category is one of the 16 fixed values.
- Merchant normalization does not treat a payment rail as the merchant without
  evidence.
- Unknown merchant, category, or MCC values remain valid processable records.
- Statement and alert versions are not double counted.
- Non-spend ledger types do not inflate spend insights.
- Inferred MCC never masquerades as issuer-confirmed.
- India and UAE currency resolution do not share a silent INR default.

## Supporting references

- `docs/superpowers/specs/2026-08-03-transaction-categorization-design.md`
- `docs/superpowers/plans/2026-08-16-transaction-categorization.md`
- `docs/superpowers/specs/2026-08-03-transaction-categorization-review.md`
- Main repo: `docs/superpowers/2026-08-03-transaction-categorization.md`
