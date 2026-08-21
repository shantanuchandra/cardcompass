# Task 12 ingestion coverage audit — 2026-08-21

## Verdict

Live ingestion is **not yet complete**, and the rollout intentionally remains
dark. The modern migrations and Edge functions are hosted, but the scheduled
runtime control is paused while the five-card v6 pilot is repaired. The first
five retained v6 attempts failed or quarantined without creating staging rows,
publishing benefits, or auto-approving catalog changes. A green invocation is
therefore still not treated as publication success.

Hosted investigation was read-only except for the already-recorded guarded
pilot attempts and explicit dark runtime control. No schedule was enabled and
no benefit or catalog proposal was approved.

## Hosted evidence

- Catalog: 186 credit-card rows across 10 represented issuer names.
- Active benefits: 26 mappings across only 15 of 186 catalog cards.
- Missing supported issuers: American Express, Bank of Baroda, RBL Bank,
  Standard Chartered, and Yes Bank.
- The current five-card v6 pilot retained failures for Axis IndianOil, HDFC
  Swiggy, ICICI HPCL Coral, IDFC Wealth, and SBI Elite. The causes were two
  issuer robots exclusions, two bounded worker-resource failures, and one
  enrichment failure. There are no v6 staging rows or live publications from
  these attempts.
- Dominant retained failures: `identity_mismatch`, `ambiguous_product`,
  `redirect_rejected`, and `worker_resource_limit`.
- Live category/type coverage is dominated by legacy movie rows; fuel,
  insurance, concierge, dining, lounge, points, cashback, and other families
  cover only a handful of cards.
- Safe catalog hygiene findings include mixed-case `card_type`, one conflicting
  Kotak issuer identity, missing official URLs, and probable non-product URLs.
  Conflicting identities remain review work and are not blindly rewritten.
- Hosted migrations are applied through `20260821160000`; the runtime control
  remains explicitly paused. This round adds one forward-only normalization
  migration for plus-sign product identities, which is locally verified and
  is the sole migration reported by linked dry-run.

The reusable read-only evidence query is
`scripts/audit-card-ingestion.sql`. It now reports supported-issuer coverage,
active category/type coverage, retained job failures, and catalog hygiene in
addition to identity, provenance, mapping, staging, RLS, policy, and grant
checks.

## Official-source comparison

The supported issuers publish materially broader benefit terms than the old
four-family parser handled. Representative primary sources:

- [Axis SELECT](https://www.axisbank.com/retail/cards/credit-card/axis-bank-select-credit-card/features-benefits): points, movie, grocery, dining, lounge, golf, fuel, and fee-waiver terms.
- [ICICI benefits](https://www.icicibank.com/personal-banking/card/credit-card/benefits-and-features): points, movies, and fuel surcharge waivers.
- [Kotak fuel cards](https://www.kotak.com/en/personal-banking/cards/credit-cards/fuel-credit-card.html): fuel, rewards, lounge, grocery, dining, cashback, and travel.
- [IDFC FIRST cards](https://www.idfcfirstbank.com/credit-card?cardType=Select): points, fuel, grocery/utility, lounge, golf, and insurance.
- [HSBC Live+](https://www.hsbc.co.in/credit-cards/products/live-plus/): dining, grocery, shopping, utility cashback, lounge, and concierge.
- [AU Zenith+](https://www.aubank.in/personal-banking/credit-cards/zenith-plus-credit-card): points, milestones, lounge, golf, concierge, and fuel.
- [RBL Platinum Plus](https://www.rblbank.com/personal-banking/cards/credit-cards/platinum-plus-credit-card?tabName=welcome-benefits): welcome/base points, movie BOGO, lounge, fuel waiver, and annual fee waiver.
- [American Express India cards](https://www.americanexpress.com/in/credit-cards/index.html): points, milestones, lounge, golf, dining, and travel.

## Local fixes in this round

1. Expanded deterministic v6 extraction beyond movie/cashback/points/lounge:
   fuel surcharge waiver, insurance cover, golf, concierge, annual fee waiver,
   air miles, welcome and milestone points, points multipliers, and explicit
   dining/grocery/utility/shopping/healthcare/travel/general discounts.
2. Added strict negative fixtures so vague marketing copy still produces no
   benefit proposal.
3. Added one official-language regression lane for each of the 15 allowlisted
   issuers and all reference category families/aliases.
4. Kept multiple insurance and miles subjects independent rather than turning
   them into false conflicts.
5. Bootstrapped issuer discovery from all 15 allowlisted official origins while
   retaining reviewed catalog product URLs when available. Missing issuers can
   now enter the review-first catalog flow.
6. Moved scheduled issuer discovery behind the same fail-closed runtime control
   as scheduled benefit enrichment.
7. Added a forward migration that normalizes safe credit-card type casing,
   enables RLS on the empty legacy `card_benefits` table, and forces a dark
   scheduled rollout until the v6 pilot is explicitly accepted.
8. Removed global `<header>`, `<nav>`, `<footer>`, and equivalent semantic
   chrome before card identity matching, supporting-link discovery, replay
   evidence, and benefit extraction. A substantive target-bearing `<main>` is
   preferred; legacy pages with only a title shell fall back to the full
   chrome-free document so valid product sections are not lost.
9. Preserved visible plus signs as strong product identity. `Zenith+` and
   `Zenith` no longer collapse to the same TypeScript or PostgreSQL key.
10. Added grounded parsing for PNB-style `300+ reward points on 1st usage` and
    `2X rewards points on retail merchandise`, including an `Rs. 400`
    sentence-boundary regression guard.
11. Repaired the first HDFC Swiggy pilot failure without mutating hosted data:
    bounded real-world PDF parsing now handles font-mapped/hex-encoded issuer
    documents while preserving line and table boundaries, with explicit 2 MiB
    transport, 8 MiB inflated-stream, 1 MiB retained-text, 64-page, and
    4,194,304-pixel limits.
12. Made supporting-source selection product-scoped and fail-closed. Exact
    product terms/fees outrank redundant external partner links and generic
    issuer MITC documents; sibling upgrade/conversion documents cannot consume
    the source budget or satisfy product identity.
13. Hardened replay privacy without discarding public commercial tables:
    customer identifiers and contextual phone/account/card numbers still fail
    closed, while public issuer contact fragments are omitted and ordinary
    amounts such as `15000 18000` remain parseable benefit evidence.
14. Canonicalized HDFC-style cashback evidence across HTML and PDFs. Missing
    optional cap/period observations merge into a stronger structured
    observation, but conflicting explicit caps, eligibility, exclusions, or
    validity remain separate review conflicts. `e-shopping`, issuer typos such
    as `₹,1500`, and `per billing cycle` are normalized deterministically.
15. A read-only local extraction against the current HDFC Swiggy issuer page
    retains the expected three cashback tiers: 10% Swiggy (₹1,500 cap), 5%
    online (₹1,500 cap), and 1% general (₹500 cap), all per statement month.
    It deliberately remains incomplete: two linked generic HDFC agreements do
    not name the Swiggy product in their bounded PDF text, so they cannot satisfy
    exact-card required-source identity merely because their URL is nested under
    the product page.
16. Current Axis IndianOil extraction is source-complete with five grounded
    proposals: 20 points per ₹100 fuel, 5 points per ₹100 online, 1% fuel
    surcharge waiver, a ₹3.5 lakh annual-spend fee waiver, and 10% movie-ticket
    discount. Sitefinity `sfvrsn` cache-busters no longer manufacture distinct
    required sources, and Related Products sections do not leak sibling cards.
17. Current SBI ELITE extraction discovers the issuer's same-host bounded
    `productDetail` JSON behind its HTML shell and is source-complete. The ten
    reviewable observations cover movie allowance, milestone points, fee
    waiver, base/multiplier points, dining, fuel, and domestic/international
    lounge access. JSON transport is bounded and flattened without retaining
    arbitrary objects or FAQ questions.
18. Current ICICI HPCL Coral primary evidence yields the correct movie, fuel,
    and cashback observations, but the product's explicit terms PDF is excluded
    by the issuer's robots policy. Current IDFC Wealth yields grounded points,
    fuel, movie, cashback, lounge, golf, concierge, and travel observations, but
    selected official sources remain identity-ambiguous/mismatched or oversized.
    Both crawls therefore remain fail-closed; robots and evidence bounds were not
    bypassed to manufacture pilot success.
19. Tightened current-source normalization removes bare benefit headings,
    historical reward sentences, domestic/international aggregate totals, and
    negated reward categories. Equivalent current reward and access observations
    consolidate by explicit semantic scope while UPI, domestic/international,
    different counts, and contradictory terms remain separate review targets.

## Verification

- Deno Edge/shared suite: 627 passed, 0 failed, 1 ignored.
- Node Supabase/schema/rules suite: 358 passed, 0 failed, 6 explicitly gated
  PostgreSQL integration skips.
- Flutter suite: 778 passed, 0 failed, 25 explicitly gated integration skips.
- Production Deno checks, formatting, JSON/JavaScript validation, and
  `git diff --check`: passed.
- Flutter release web build: passed. Analyzer exited 0 with 12 pre-existing
  informational lints outside this ingestion change.
- The plus-identity migration was applied successfully to an isolated
  disposable local PostgreSQL database; `Zenith+`, `Zenith⁺ Plus`, and
  `Zenith` normalization plus function grants were verified before the exact
  database was stopped and removed.
- Linked Supabase migration dry-run over the transaction pooler: passed. It
  lists only `20260821161500_preserve_catalog_plus_identity.sql`; nothing was
  applied by the dry-run.
- The expanded audit SQL ran successfully against hosted Supabase under
  `default_transaction_read_only=on`; no hosted state was changed.

## Rollout gate

Do not enable schedules merely because CI or GitHub Actions is green. Required
order:

1. Pass all local Deno, Node, Flutter, format, type, migration, and build gates.
2. Apply the plus-identity forward migration with the runtime control paused.
3. Deploy Edge functions dark; do not enable either schedule.
4. Run the five-card/three-issuer v6 pilot and review all material proposals.
5. Rerun `scripts/audit-card-ingestion.sql`; require no unsafe identity,
   provenance, mapping, RLS, or permission regression.
6. Resume schedules explicitly, then monitor per-issuer success, quarantine,
   review age, and category/type coverage. Coverage growth—not HTTP 200—is the
   success metric.
