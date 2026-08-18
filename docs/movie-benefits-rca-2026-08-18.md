# Movies benefits ingestion RCA — 18 Aug 2026

## Outcome

The Movies page was not limited by its comparison UI. It was reading only approved `benefits` joined through `card_benefit_mapping`, while the latest issuer scrape either discarded movie wording, lost its normalized JSON fields during review, or stopped on exact-card identity checks.

The live remediation is complete for three source-verified variants. The Movies page now returns **11 mapped movie benefits across 10 variants and 6 banks**: Axis, HDFC, HSBC, IDFC FIRST, Kotak, and SBI. HDFC Platinum Times, Kotak PVR INOX, and SBI Elite were verified in the internal browser at `127.0.0.1:54321` on desktop and 390 px mobile layouts. A follow-up safety review also closed the rollout and correctness gaps before commit.

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

## Source-verified approvals

| Bank + variant | Approved movie rules | Stored contract | Official source |
|---|---|---|---|
| HDFC Bank — Platinum Times | 50% off movie tickets | ₹600 per-transaction cap; BookMyShow | [HDFC Platinum Times](https://www.hdfc.bank.in/credit-cards/platinum-times-credit-card) |
| Kotak Bank — PVR INOX Kotak | 1 ticket worth ₹300 per ₹10,000 monthly spend; 5% off tickets | Monthly threshold ₹10,000; reward ₹300; PVR + INOX | [Kotak PVR INOX](https://www.kotak.bank.in/en/personal-banking/cards/credit-cards/pvr-inox-kotak-credit-card.html) |
| SBI Card — Elite | ₹6,000 annual movie-ticket allowance | Annual cap ₹6,000; BookMyShow | [SBI ELITE campaign terms](https://www.sbicard.com/en/eapply/sbicampaign.page) |

The HDFC generic 50% marketing row, Kotak partner-less duplicate, and every non-movie staged proposal were deliberately left unapproved.

## Live database result

| Bank | Card variants | Mapped movie benefits |
|---|---:|---:|
| Axis Bank | 1 | 1 |
| HDFC Bank | 1 | 1 |
| HSBC | 1 | 1 |
| IDFC FIRST Bank | 5 | 5 |
| Kotak Bank | 1 | 2 |
| SBI Card | 1 | 1 |
| **Total** | **10** | **11** |

The four newly approved rows retain their normalized values:

| Variant | `benefit_type` | Key `value_config` fields | Partners |
|---|---|---|---|
| Platinum Times | `percent_discount` | `discount_percent: 50`, `max_discount_per_transaction: 600` | BookMyShow |
| PVR INOX Kotak | `milestone` | `threshold_amount: 10000`, `reward_value: 300`, `milestone_type: monthly` | PVR, INOX |
| PVR INOX Kotak | `percent_discount` | `discount_percent: 5` | PVR, INOX |
| Elite | `annual_allowance` | `annual_cap: 6000`, `unit: fixed` | BookMyShow |

## Internal-browser verification

| Check | Result |
|---|---|
| Desktop, 1462 × 963 | Individual bank + card boxes rendered for Axis, HDFC, HSBC, IDFC FIRST, and Kotak; SBI appears in the separate annual-allowance panel |
| Mobile, 390 × 844 | Comparison cards stack vertically and remain usable above the fixed navigation |
| Platform label | `Zomato/District` renders for applicable HSBC and IDFC variants |
| Commercial details | HDFC shows 50% / ₹300 saving on a ₹600 example; Kotak shows PVR/INOX; annual panel shows `SBI Card — Elite`, ₹6,000/year, and BookMyShow |
| Browser console | 0 errors |

## Validation and rollout

| Check | Result |
|---|---|
| Flutter Movies feature suite | 127 passed |
| Movie extraction + identity + migration Node tests | 42 passed |
| Batch orchestration tests | 15 passed |
| Batch policy tests | 15 passed |
| Supporting-document isolation tests | 5 passed |
| Admin review/DTO tests | 12 passed |
| Versioned pilot migrations | `20260818100125` and parser-scoped claim `20260818113000` applied live; remote DB lint passed |
| Current parser pilot | `benefits-v5` passed; unsafe mutations 0 |
| Edge deployments | `benefit-enrichment-batch`, `card-discovery`, and `admin-catalog-entry` deployed |
| Live parser-isolation probe | One scheduled v5 job claimed; all 174 queued v4 jobs remained untouched |
| Live approval | 3 staging rows approved, creating 4 movie benefits/mappings |

## Remaining quarantines

| Scope | Current reason | Required next action |
|---|---|---|
| ICICI Coral family | Duplicate catalog identities produce `ambiguous_product` | Merge/retire duplicate Coral catalog variants, then rerun exact product URLs |
| AU Zenith / Zenith+ | Catalog product and official PDF name do not match exactly | Correct the catalog variant identity or add a reviewed Zenith+ entry; do not alias across products |
| SBI Elite Advantage / PSB Elite | Redirected identity or incomplete product-specific evidence | Add exact product pages/supporting terms per variant before approval |
| Older scraped SBI rows | Shared navigation contaminated unrelated product URLs | Keep unmapped; never bulk-promote by issuer/title text |

These quarantines are intentional safety outcomes, not missing bulk approvals.
