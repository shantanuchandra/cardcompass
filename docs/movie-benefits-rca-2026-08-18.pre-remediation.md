# Movies page and benefit-ingestion RCA — 18 Aug 2026

## Executive result

The Movies UI is clearer at the individual-offer level, but the desktop bento layout is not yet balanced. The larger issue is data completeness: the live database contains 49 active rows matched by the Movies repository query, but only 8 have a `card_benefit_mapping`. The other 41 are discarded before normalization and cannot appear in the app.

The recent all-card scrape is not reflected in the approved production tables. The ingestion design deliberately stages extracted benefits for admin approval; the public approved tables show only one new benefit since the recent scrape window and only 18 total mappings across the entire database.

## RCA summary

| Area | Evidence | Finding | Root cause | Severity / action |
|---|---:|---|---|---|
| Port 8080 rendering | `server.js` mounts `build/web` at `/app/`; the inspected build temporarily had `<base href="/">` | `/app/` rendered blank until rebuilt | A debug `flutter run` build overwrote `build/web` with the wrong base path for the static server | P1 local workflow: use `npm run build:app` before testing through port 8080 |
| Offer-card UI | Live authenticated Chrome test at `http://127.0.0.1:8080/app/#/app/movie-deals` | Bank and variant are now visibly separated in individual offer boxes; `Zomato/District` is present | Intended UI change is working | Pass |
| Desktop bento composition | Zomato/District search, 2 tickets × ₹300, desktop viewport | Empty guaranteed tiles consume most of the width; five usable offers are squeezed into a narrow right rail | Grid span is fixed by group, not by whether a group has results | P1 UX: collapse empty groups into compact strips and let the populated group span remaining columns |
| Approved catalog freshness | 185 cards; only 5 card records created/updated on or after 15 Aug; latest update is 17 Aug | An all-variant refresh is not visible in `card_catalog` | Crawl output and approved catalog state are separate; most crawl results did not mutate approved rows | P1 ingestion/review audit |
| Approved benefit freshness | 491 active benefits; 488 last updated 13 Jul; 1 created 15 Aug; 2 updated 16 Aug | Latest scrape did not broadly publish new benefit records | Enrichment writes to `card_benefits_staging`; approval RPC is required before approved benefits/mappings change | P0: review/approve staged jobs or automate safe approvals |
| Mapping coverage | 491 benefits, 185 cards, only 18 total mappings | Most approved benefits are orphaned from cards | `card_benefit_mapping` is the hard join gate and is severely under-populated | P0 data integrity |
| Movies fetch funnel | 49 active movie-query rows → 8 mapped → 7 distinct card variants / 4 banks | 41 fetched rows never become candidates | Repository loads mappings after the broad fetch and drops every unmapped benefit | P0 page completeness |
| Exact URL evidence | 48/49 movie rows have a source URL matching a catalog card URL; 41 exact matches are unmapped | Most missing joins are deterministically recoverable | Promotion/mapping did not use the already available canonical URL relationship | P0: backfill mappings after validation |
| Bank coverage | Displayable mappings: IDFC FIRST 4, HDFC 2 (same card), Axis 1, HSBC 1; SBI 0 | Movies page is not representative of the catalog | 35 exact-URL SBI movie rows are unmapped | P0; validate SBI rows before mapping because several titles are contaminated |
| Source-data quality | Examples label “SBI Card ELITE Free Movie Tickets” on unrelated SBI product URLs; HDFC has two near-duplicate Diners Club milestone benefits | Blindly mapping all 41 would publish false or duplicate offers | Legacy scrape attached page text/templates to the wrong product and dedupe is not semantic enough | P0: identity validation + duplicate review before promotion |
| Zomato result correctness | Live search showed Firstprivatecreditcard as “not tied to Zomato” but still calculated `Save ₹600` in Potential Overall | Honest caveat is shown, but the monetary presentation can look actionable for an unmatched platform | Potential candidates remain eligible even when explicit platform differs | P1 product decision: suppress savings or clearly label as “only on BookMyShow” for platform mismatch |

## Live database funnel

| Stage | Count | Notes |
|---|---:|---|
| `card_catalog` | 185 | 12 issuer-name values due to naming variants such as `IDFC FIRST Bank` / `IDFC First Bank` |
| `benefits` | 491 | All active; 0 missing source URLs; 0 missing dedupe keys |
| `card_benefit_mapping` | 18 | Includes 10 AU Zenith mappings unrelated to Movies and 8 movie mappings |
| Rows matched by the Movies repository query | 49 | 18 dining, 18 entertainment, 6 lifestyle, 4 offers, 3 rewards |
| Movie rows with mappings | 8 | 7 distinct card variants across 4 banks |
| Movie rows without mappings | 41 | Dropped before rule normalization |
| Unmapped rows with exact source URL → catalog URL match | 41 | HDFC 5, IDFC FIRST 1, SBI 35 |

## Currently mapped movie offers

| Bank | Card variant | Benefit | Expected page behavior |
|---|---|---|---|
| HSBC | TravelOne | Movie BOGO | Potential; tied to Zomato/District |
| HDFC Bank | Diners Club Black | Monthly Vouchers on Spends | Milestone candidate |
| HDFC Bank | Diners Club Black | Monthly Milestone Benefits | Likely semantic duplicate of the row above |
| IDFC FIRST Bank | Firstprivatecreditcard | BookMyShow Discount | Potential for Zomato search; explicit BookMyShow route |
| Axis Bank | Indianoil | Instant Discount on BookMyShow | Platform-specific candidate |
| IDFC FIRST Bank | Mayura | Twin ticket treats | Potential; tied to Zomato/District |
| IDFC FIRST Bank | Wealth | Buy-1-Get-1 Movie Ticket Offer | Potential; tied to Zomato/District |
| IDFC FIRST Bank | Millennia | 25% off on movie tickets | Potential; tied to Zomato/District |

## Why the latest scrape is not appearing

The code path is intentionally review-gated:

1. `benefit-enrichment-batch` crawls an official issuer URL and extracts proposals.
2. It calls `stage_card_benefit_enrichment`; the job ends in `staged`, not published.
3. `admin-catalog-entry` validates a staged job and calls `approve_card_benefit_enrichment` with per-benefit decisions.
4. Only approval should create/update approved `benefits` and `card_benefit_mapping` rows.
5. The Movies repository reads only approved `benefits`, `card_benefit_mapping`, and `card_catalog`; it never reads staging.

The scrape job/staging tables are correctly hidden from the anonymous client, so their exact status counts could not be queried through the app credential. The approved-table timestamps and mapping counts are sufficient to show that a broad promotion did not occur.

## Recommended next steps

| Priority | Action | Acceptance check |
|---|---|---|
| P0 | Export admin-only counts for enrichment jobs by status and pending staging rows by issuer | Counts for `queued`, `processing`, `staged`, `failed`, `quarantined`, `approved` are available |
| P0 | Review staged movie proposals first; approve only exact-identity, grounded rows | Every approved movie benefit has one correct card mapping and source evidence |
| P0 | Backfill safe exact-URL mappings, excluding known contaminated SBI and duplicate HDFC rows until reviewed | Movie funnel no longer loses validated rows at the mapping join |
| P0 | Add a database invariant/report for active benefits with zero mappings | CI/admin report fails or alerts when orphan count rises |
| P1 | Deduplicate the two HDFC Diners Club Black monthly milestone rows | One commercial offer produces one candidate |
| P1 | Make populated result groups expand when sibling groups are empty | Desktop search has no large empty bento region and offer cards remain comfortably wide |
| P1 | For explicit platform mismatch, show the valid platform in the price block or suppress the computed saving | No card visually promises a saving on the selected, ineligible platform |
| P2 | Canonicalize issuer names and clean card display variants such as `Firstprivatecreditcard` | Bank filters and card labels are consistent |

## Verification performed

- Rebuilt the static app with `npm run build:app` and verified `/app/` on port 8080.
- Used the existing authenticated Chrome session to open Movies and run a Zomato/District search for 2 × ₹300 tickets.
- Confirmed there were no browser console warnings or errors during the search.
- Queried the live Supabase approved tables through the same project endpoint configured by the app.
- Reproduced the repository's exact widened Movies filter and compared its benefit IDs with live mappings and catalog URLs.
- Existing Movies automated suite: 121 passing tests; scoped Flutter analysis: no issues.

