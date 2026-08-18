# Movies page and benefit-ingestion RCA — 18 Aug 2026

## Executive result

The offer-card UI correctly separates bank and card variant and uses the requested `Zomato/District` label. The follow-up remediation now makes the only populated recommendation group expand, keeps empty groups compact, and suppresses price/saving claims when a card is explicitly tied to another platform.

The main remaining production risk is data completeness. The live approved tables contained 49 active rows matched by the Movies query but only 8 mappings (7 card variants across 4 banks); 41 rows were discarded at the mapping join. The recent scrape is review-gated and was not broadly promoted into approved benefits/mappings.

## Concise RCA

| Area | Evidence | Root cause | Remediation / status |
|---|---:|---|---|
| Port 8080 | Static server mounts `build/web` at `/app/` | Debug builds can overwrite the release output with base `/` | Release build with `/app/` completed and is served on port 8080 |
| Offer options | Authenticated Movies search | Previous presentation did not clearly separate issuer/variant | Individual bank + card boxes and `Zomato/District` are present |
| Bento layout | Empty guaranteed tiles dominated a Zomato/District result; useful offers occupied one narrow column | Group spans were fixed regardless of content | Implemented adaptive spans: a sole populated group takes 3 columns; empty groups take 1 |
| Platform mismatch | BookMyShow-only card still showed `Save ₹600` for a Zomato/District search | Potential ranking retained computed amounts after explicit platform mismatch | Implemented “Available on …” plus non-actionable status; gross/final/save are suppressed |
| Approved freshness | 491 active benefits; 488 last updated 13 Jul; only 18 total mappings | Enrichment writes to staging and requires reviewed approval | Inspect/approve the admin queue only with source evidence; no blind bulk approval |
| Movies funnel | 49 matched rows → 8 mapped → 7 variants / 4 banks | `card_benefit_mapping` is a hard gate and under-populated | Added source-verified IDFC Classic mapping and service-only mapping-health RPC |
| Exact URL candidates | 41 unmapped rows have exact source URL → catalog URL matches | Promotion did not create mappings | Automatic backfill limited to IDFC Classic; SBI intentionally excluded due contamination |
| HDFC duplication | Two Diners Club Black rows describe the same ₹80k monthly voucher milestone | Dedupe key is not semantic | Migration removes only `Monthly Milestone Benefits` mapping; source benefit is retained |
| Catalog labels | `Firstprivatecreditcard`, `Indianoil`, and two IDFC issuer casings | Scrape-derived display labels were not canonicalized | Exact URL/name-guarded cleanup added |
| Remote migration | Direct Postgres ports time out from this environment | Network path blocks pooler connections | Restored access through the HTTPS Management API; both migrations applied and recorded |
| Admin review queue | 134 queued, 28 quarantined, 12 review-required, 5 staged jobs; 8 pending staging rows | Latest issuer crawl is still largely queued/review-gated | No pending proposal contains movie terms, so no movie approval was safe or necessary |
| SBI validation | 35 movie-query rows span contradictory titles across unrelated product URLs | Legacy scraper mixed shared/navigation text with product-specific benefits | Kept all SBI rows unmapped; 59 current SBI enrichment jobs are queued for clean extraction |

## Live database funnel (pre-remediation baseline)

| Stage | Count | Notes |
|---|---:|---|
| `card_catalog` | 185 | 12 issuer strings, including IDFC casing variants |
| `benefits` | 491 | Active; no missing source URLs or dedupe keys |
| `card_benefit_mapping` | 18 | 10 AU Zenith mappings and 8 Movies mappings |
| Rows matched by Movies query | 49 | 18 dining, 18 entertainment, 6 lifestyle, 4 offers, 3 rewards |
| Movie rows with mappings | 8 | 7 card variants across 4 banks |
| Movie rows without mappings | 41 | Dropped before normalization |
| Exact URL matched but unmapped | 41 | HDFC 5, IDFC FIRST 1, SBI 35 |

## Why the latest scrape is not appearing

`benefit-enrichment-batch` extracts proposals into `card_benefits_staging`. The admin workflow then calls `approve_card_benefit_enrichment` with per-benefit decisions. Only approval writes approved `benefits` and `card_benefit_mapping` rows. The Movies repository reads those approved tables and never reads staging. Therefore a successful crawl is not evidence that benefits are live.

## Safe remediation delivered

The migration `20260818090000_movie_benefit_mapping_remediation.sql`:

1. Adds the IDFC FIRST Classic “25% Off on Movie Tickets” mapping only where exact card URL, bank, card name, benefit title, and active status agree.
2. Removes the duplicate HDFC Diners Club Black `Monthly Milestone Benefits` mapping while retaining the benefit evidence row.
3. Repairs three exact catalog labels with issuer/URL guards.
4. Adds service-only `get_movie_benefit_mapping_health()` metrics for active, mapped, and orphaned movie benefits. A follow-up migration aligns the predicate exactly with the production repository schema.
5. Performs no SBI auto-mapping; conflicting titles across SBI product URLs require issuer-source review.

## Acceptance and verification

| Check | Result |
|---|---|
| UI widget tests, including adaptive spans and platform mismatch | Pass (16/16 scoped results tests) |
| Movies feature suite baseline | Pass (121 tests before remediation) |
| Migration contract tests | Pass, including live-schema regression for the health predicate |
| Release web build with `/app/` base | Pass |
| Port 8080 responds with new release build | Pass; `/app/` base verified and unauthenticated Playwright correctly redirects to login |
| Remote DB migration | Deployed and recorded through Supabase Management API SQL |
| Live migration assertions | Classic mapping 1; HDFC duplicate mapping 0; repaired labels 1 each; old IDFC issuer spelling 0 |
| Live health RPC | `49 active / 8 mapped / 41 orphaned`; anon denied, service role allowed |
| Admin enrichment status | Health metric added to admin UI; `admin-catalog-entry` deployed ACTIVE version 14 |
| Admin staged proposal approvals | None performed: all 8 pending rows are non-movie proposals |

## Remaining operational actions

| Priority | Action | Acceptance check |
|---|---|---|
| P0 | Let queued issuer enrichment complete, then review movie proposals by exact product identity | Each approval includes the correct card and official source evidence |
| P0 | Re-extract SBI from current product pages and reject shared-navigation contamination | No ELITE/free-ticket text is attached to unrelated SBI variants |
| P1 | Establish an alert threshold on the admin-visible orphan count | New orphan growth is visible before release |
| P1 | Re-run authenticated Zomato/District and BookMyShow searches after the queued jobs are reviewed | Correct variants and benefits appear once, with truthful platform pricing |
