# Movies benefits ingestion RCA — 18 Aug 2026

## Outcome

The Movies page was not limited by its comparison UI. It was reading only approved `benefits` joined through `card_benefit_mapping`, while the latest issuer scrape either discarded movie wording, lost its normalized JSON fields during review, or stopped on exact-card identity checks.

The live remediation is complete for six newly source-verified variants. The database now has **15 mapped movie benefits across 14 variants and 8 banks**: AU Small Finance Bank, Axis, HDFC, HSBC, ICICI, IDFC FIRST, Kotak, and SBI. AU Zenith+, ICICI HPCL Coral, and PSB SBI Card ELITE were verified in the internal browser at `127.0.0.1:54321` after a fresh bundle reload, alongside the earlier HDFC, Kotak, and SBI approvals.

## Concise RCA

| Failure | Evidence | Root cause | Fix / live status |
|---|---|---|---|
| Latest scrape did not create movie proposals | Percentage, BOGO, annual allowance, fixed discount, and milestone examples returned no proposal | The old parser handled only cashback, rewards, and lounge benefits | `benefits-v5` parses all movie shapes and passed its isolated five-card pilot |
| `Rs. 100` lost thresholds/restrictions | Sentence parsing stopped after `Rs.` | Currency abbreviations were treated as sentence endings | Splitter fixed; regression coverage added |
| Approved rows had `{}` commercial terms | Staging exposed flat fields while approval reads `valueConfig` | Extractor and approval contracts disagreed | Proposals now emit the approved `value_config` schema |
| Admin review could recreate `{}` | Review DTO omitted `valueConfig` and `partners` | Output allowlist did not include the new normalized fields | Allowlisted scalar movie config and partners now survive review; unknown keys remain stripped |
| HDFC pages failed before parsing | Live product HTML is about 1.2 MB | Primary issuer fetch ceiling was 1 MB | Primary page ceiling raised narrowly to 2 MB; supporting docs stay at 1 MB |
| Exact variants were quarantined | Marketing suffixes appeared in HDFC, ICICI, Kotak, and SBI page titles | Page title marketing text became part of the card identity | Known issuer suffixes are stripped while exact variant matching remains mandatory |
| HDFC cap was missing | Discount, monthly usage, and ₹600 cap are separate clauses | Parser evaluated one clause at a time | Bounded adjacent-clause assembly retains the ₹600 cap |
| Kotak staged a 20% movie offer | The source actually described cinema food and beverages | “Movies” elsewhere in the sentence triggered ticket classification | F&B-only cinema offers are rejected; only milestone and 5% ticket rows were approved |
| SBI annual benefit lacked its platform | BookMyShow appears only in the redemption link `href` | HTML-to-text conversion discarded partner links | Exact SBI ELITE supporting source plus known-cinema-link preservation produces `partners: ["BookMyShow"]` |
| Old parser jobs could cross rollout lanes | Pilot initialization was versioned, but execution claims filtered only by run mode | A `benefits-v5` gate could release queued v1–v4 work | Pilot status, queue counts, claims, leases, and scheduled seeding are all scoped to `benefits-v5`; stale pilot requests are rejected |
| Quarterly/yearly BOGO looked exhausted | Repository counted all matching transaction history | Usage period was displayed but not applied to transaction dates | Current calendar month, quarter, or year is now applied before counting redemptions |
| Identical approved movie terms conflicted on recrawl | Approved JSON persisted, but duplicate transient flat fields were also compared | Stored and parser representations of the same terms differed | Structured `value_config` is canonicalized for diffing; percent and BOGO recrawls now resolve as unchanged |
| One benefit could borrow the next benefit's cap | Adjacent-clause assembly used a fixed number of following lines | Assembly did not stop at a new offer lead | Percent, BOGO, milestone, annual, cashback, rewards, lounge, and fixed-off leads now form hard boundaries |
| Statement variant could match a longer product | Discovery searched the full page with substring inclusion | “Regalia” matched a “Regalia Gold” page | Both discovery paths now require an exact normalized official title/alias before any catalog mutation |
| UI showed only a subset of banks | Repository joins only approved mappings | 41 movie-like benefits were orphaned or contaminated | Four complete proposals were approved; incomplete/ambiguous variants remain quarantined |
| ICICI HPCL Coral stayed `ambiguous_product` | `Hpcl Coral` and `Hpcl Coral American Express` both normalized to `hpclcoral` | Exact matching reused a discovery normalizer that deliberately removed payment-network words | Exact enrichment matching now preserves Amex, Mastercard, RuPay, and Visa; HPCL Coral staged cleanly and was approved |
| ICICI Coral RuPay pages cannot be promoted | Both stored Coral RuPay URLs redirect to a generic ICICI RuPay page | Duplicate catalog rows plus non-product-specific source evidence | Left quarantined; no generic RuPay benefit was attached to either Coral variant |
| AU offer was absent | Official BOGO terms say Zenith+, but the live catalog contained only Zenith | The scrape omitted a distinct, current catalog variant | Added a reviewed Zenith+ row and exact BookMyShow BOGO mapping; Zenith remains unchanged |
| PSB Elite had exact evidence but no proposal | Official 68-page terms PDF is readable by Poppler but returned empty text in the bounded Edge PDF reader | Embedded-font/object-stream encoding exceeds the current lightweight PDF extractor | Added a reviewed PSB Elite mapping pinned to the exact SBI PDF; no cross-variant aliasing |

## Source-verified approvals

| Bank + variant | Approved movie rules | Stored contract | Official source |
|---|---|---|---|
| HDFC Bank — Platinum Times | 50% off movie tickets | ₹600 per-transaction cap; BookMyShow | [HDFC Platinum Times](https://www.hdfc.bank.in/credit-cards/platinum-times-credit-card) |
| Kotak Bank — PVR INOX Kotak | 1 ticket worth ₹300 per ₹10,000 monthly spend; 5% off tickets | Monthly threshold ₹10,000; reward ₹300; PVR + INOX | [Kotak PVR INOX](https://www.kotak.bank.in/en/personal-banking/cards/credit-cards/pvr-inox-kotak-credit-card.html) |
| SBI Card — Elite | ₹6,000 annual movie-ticket allowance | Annual cap ₹6,000; BookMyShow | [SBI ELITE campaign terms](https://www.sbicard.com/en/eapply/sbicampaign.page) |
| AU Small Finance Bank — Zenith+ | BookMyShow BOGO | ₹500 per booking; 4 redemptions per calendar quarter | [AU Zenith+ product page](https://www.au.bank.in/premium-banking/credit-cards/zenith-plus-credit-card), [AU BookMyShow terms](https://www.au.bank.in/zenith-plus_tnc-book-my-show-terms-and-conditions.pdf) |
| ICICI Bank — HPCL Coral | 25% off movie tickets | ₹100 per transaction; 2 uses/month; BookMyShow; ₹25,000 preceding-quarter gate from 1 Apr 2026 | [ICICI HPCL Coral](https://www.icici.bank.in/personal-banking/cards/credit-card/hpcl-coral-credit-card) |
| SBI Card — PSB Elite | ₹6,000 annual movie-ticket allowance | BookMyShow; ₹500 maximum monthly redemption across up to 2 tickets; primary cards only | [PSB SBI Card ELITE](https://www.sbicard.com/en/personal/credit-cards/psb-sbi-card-elite.html), [official PSB Elite terms](https://www.sbicard.com/sbi-card-en/assets/docs/pdf/banking-tnc/psb-elite-tnc.pdf) |

The HDFC generic 50% marketing row, Kotak partner-less duplicate, and every non-movie staged proposal were deliberately left unapproved.

## Live database result

| Bank | Card variants | Mapped movie benefits |
|---|---:|---:|
| AU Small Finance Bank | 1 | 1 |
| Axis Bank | 1 | 1 |
| HDFC Bank | 2 | 2 |
| HSBC | 1 | 1 |
| ICICI Bank | 1 | 1 |
| IDFC FIRST Bank | 5 | 5 |
| Kotak Bank | 1 | 2 |
| SBI Card | 2 | 2 |
| **Total** | **14** | **15** |

The seven source-verified rows retain their normalized values:

| Variant | `benefit_type` | Key `value_config` fields | Partners |
|---|---|---|---|
| Platinum Times | `percent_discount` | `discount_percent: 50`, `max_discount_per_transaction: 600` | BookMyShow |
| PVR INOX Kotak | `milestone` | `threshold_amount: 10000`, `reward_value: 300`, `milestone_type: monthly` | PVR, INOX |
| PVR INOX Kotak | `percent_discount` | `discount_percent: 5` | PVR, INOX |
| Elite | `annual_allowance` | `annual_cap: 6000`, `unit: fixed` | BookMyShow |
| Zenith+ | `bogo` | `max_discount_per_transaction: 500`, `max_usage_per_period: 4`, `usage_period: quarter` | BookMyShow |
| HPCL Coral | `percent_discount` | `discount_percent: 25`, `max_discount_per_transaction: 100`, `max_usage_per_month: 2` | BookMyShow |
| PSB Elite | `annual_benefit` | `annual_cap: 6000`, `max_discount_per_transaction: 500`, `max_usage_per_month: 1` | BookMyShow |

## Internal-browser verification

| Check | Result |
|---|---|
| Desktop | Individual bank + card boxes render for AU Zenith+, ICICI HPCL Coral, and the prior eligible variants; SBI Elite and PSB Elite render separately in the annual-allowance panel |
| Mobile, 390 × 844 | Inputs and selectors stack to one column; chip groups wrap; fixed navigation remains usable |
| Platform label | `Zomato/District` renders for applicable HSBC and IDFC variants |
| Commercial details | Fresh ₹552 example shows AU Zenith+ BOGO saving ₹276, ICICI HPCL Coral capped at ₹100, and both SBI Elite variants at ₹6,000/year with BookMyShow |
| Browser console | 0 errors |

## Validation and rollout

| Check | Result |
|---|---|
| Flutter Movies feature suite | 127 passed |
| Movie extraction + identity + migration Node tests | 116 passed |
| Batch orchestration + supporting-source Deno tests | 36 passed |
| Batch policy tests | 15 passed |
| Supporting-document isolation tests | 5 passed |
| Admin review/DTO tests | 12 passed |
| Versioned pilot migrations | `20260818100125` and parser-scoped claim `20260818113000` applied live; remote DB lint passed |
| Current parser pilot | `benefits-v5` passed; unsafe mutations 0 |
| Edge deployments | `benefit-enrichment-batch`, `card-discovery`, and `admin-catalog-entry` deployed |
| Live parser-isolation probe | One scheduled v5 job claimed; all 174 queued v4 jobs remained untouched |
| Follow-up migration | `20260818123000` applied atomically after a live rollback validation; AU and PSB exact mappings added |
| Follow-up Edge deployment | `benefit-enrichment-batch` redeployed with network-aware exact matching |
| Follow-up live approval | ICICI HPCL Coral v5 staged with 0 warnings; movie proposal reviewed with the current eligibility/frequency terms and approved |

## Remaining quarantines

| Scope | Current reason | Required next action |
|---|---|---|
| ICICI Coral RuPay duplicates | Both catalog URLs redirect to the generic RuPay page, not an exact Coral product page | Merge/retire duplicate rows only after catalog review; do not promote generic RuPay wording |
| ICICI HPCL Coral American Express | Official page says the Amex movie cashback was revoked from 1 Jan 2025 | Keep unmapped unless ICICI publishes a new exact active offer |
| AU Zenith | Exact Zenith page has no movie-ticket offer; the offer belongs to separately stored Zenith+ | Keep Zenith unmapped; never alias Zenith+ benefits to it |
| SBI Elite Advantage | Stored URL redirects to plain SBI Elite | Correct or retire the catalog URL only when an exact Elite Advantage product source is available |
| Older scraped SBI rows | Shared navigation contaminated unrelated product URLs | Keep unmapped; never bulk-promote by issuer/title text |

These quarantines are intentional safety outcomes, not missing bulk approvals.
