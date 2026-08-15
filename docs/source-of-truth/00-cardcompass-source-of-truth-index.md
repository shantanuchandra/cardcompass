# CardCompass Product Source of Truth

**Status:** Canonical MVP product specification

**Last updated:** 2026-08-15

## Purpose

This directory defines the product contract for the CardCompass MVP: acquire a
user's credit-card statements from Gmail, turn them into normalized spend data,
and use that data to recommend the best eligible card the user owns and the best
eligible card available in the user's market.

The documents are deliberately split by subsystem. This index owns shared
terminology, precedence, boundaries, and the end-to-end lifecycle.

## Document map

1. [Gmail consent and statement discovery](01-gmail-consent-and-statement-discovery.md)
2. [PDF password resolution and parsing](02-pdf-password-resolution-and-parsing.md)
3. [Transaction normalization, merchant identity, category, and MCC](03-transaction-normalization-merchant-and-mcc.md)
4. [Spend insights](04-spend-insights.md)
5. [Card recommendation engine](05-card-recommendation-engine.md)
6. [Movie platform and specialized offers](06-movie-platform-and-specialized-offers.md)

## Decision precedence

When sources conflict, use this order:

1. The working v2 implementation for behavior explicitly preserved by these documents.
2. This source-of-truth directory.
3. The latest corrected v2 design specification.
4. The latest v2 implementation plan.
5. Main-repository specifications for rationale or behavior not yet represented in v2.
6. Historical execution logs for forensic context only.
7. Landing-page or marketing copy never overrides product behavior.

## End-to-end lifecycle

### 1. Discover

The user signs in with Google, grants the existing Gmail read-only access, and
starts a sync. CardCompass finds likely statement emails with PDF attachments,
stores their metadata idempotently, and identifies unprocessed items.

### 2. Unlock

Each attachment is downloaded into the active processing flow. CardCompass
tries the existing bounded password-resolution chain: no password, email hints,
learned password, date-of-birth sources, bank-specific candidates, and manual
entry. A locked document does not stop the rest of the batch.

### 3. Parse

The PDF is converted to text and pruned to statement facts and ledger rows.
Statement dates, due dates, balances, payments, masked card identity, and
transactions are parsed. PDF dates take precedence over email-date fallbacks.

### 4. Normalize and enrich

Transactions are linked to the owned card and source statement, deduplicated,
typed, normalized, assigned a canonical merchant, categorized, and enriched
with a verified or inferred MCC when possible.

### 5. Analyze

The dashboard analyzes the selected date range, defaulting to the past 60 days.
Portfolio card recommendations use a trailing 90-day spend profile.

### 6. Recommend

For each supported insight, CardCompass independently ranks:

- the best eligible active card the user owns; and
- the best eligible active catalog card available in the user's country/market.

Recommendations account for applicable rates, caps, thresholds, exclusions,
fees, eligibility, benefit-cycle usage, and confidence. They explain the value
and assumptions rather than returning only a card name.

## Shared product rules

- `user_cards` is the ownership boundary for statements, transactions, and
  owned-card recommendations.
- The reusable card catalog and benefit catalog remain separate from user data.
- Only cards in the user's country/market and compatible with known eligibility
  constraints enter the overall recommendation pool.
- Dashboard insights use the selected range; the initial default is 60 days.
- Overall portfolio recommendations use the latest 90 days.
- Unknown merchant, category, or MCC values do not block ingestion.
- Issuer-confirmed facts outrank inferred facts.
- Payments, refunds, fees, interest, rewards, and cash withdrawals are ledger
  entries but are excluded from eligible retail-spend totals by default.
- Owned and overall recommendations are ranked independently.
- The MVP retains the current authentication, persistence, password-cache,
  proxy, and access-control behavior. New security or retention systems are not
  part of this documentation revamp.

## Canonical transaction category vocabulary

`food`, `fuel`, `grocery`, `entertainment`, `travel`, `shopping`,
`utilities`, `insurance`, `medical`, `education`, `investment`, `transport`,
`rental`, `subscription`, `gift`, `other`.

Payment rails and transaction types such as UPI, wallet, transfer, fee, cash,
and payment are not spend categories.

## Supported insight families

1. Maximum-spend category
2. Maximum-spend merchant
3. Movie platform
4. Travel merchant
5. E-commerce merchant
6. Food and grocery merchant
7. Fuel merchant

## Existing documents and status

### Current supporting references

- `docs/superpowers/specs/2026-08-02-gmail-sync-fetch-list-design.md`
- `docs/superpowers/specs/2026-08-02-pdf-statement-parsing-design.md`
- `docs/superpowers/specs/2026-08-03-transaction-categorization-design.md`
- `docs/superpowers/specs/2026-08-02-movie-deals-design.md`
- Main repo: `docs/superpowers/2026-07-16-statement-ingestion-and-payment-tracking.md`
- Main repo: `docs/superpowers/2026-07-14-user-card-data-integrity.md`
- Main repo: `docs/superpowers/2026-07-14-ledger-transactions-and-analytics.md`
- Main repo: `docs/superpowers/2026-07-14-benefit-extraction-and-catalog-pipeline.md`

### Superseded for product behavior

- The first Movie Deals plan is superseded by the corrected Movie Deals v2
  design and plan.
- The 2026-08-03 v2 categorization plan is superseded by the corrected
  2026-08-16 plan.
- Main-repo pipeline designs do not override the restructured v2 implementation
  where the two codebases differ.
- Marketing claims that no normalized transaction data is stored are not a
  product-system contract.

## MVP completion outcome

A user can connect Gmail, sync a supported statement, resolve a password or
card-assignment issue, see deduplicated categorized transactions, receive the
seven supported spend insights, and compare a best-owned recommendation with a
best-overall eligible recommendation.
