# CardCompass Production QA Report

Date: 17 August 2026
Environment: `https://www.cardcompass.in/app/`
Production branch: `prod` at `b1432233de12054080b4366973185449a6a287eb`
Backend worker: `main` at `b79f7a2ab5bb7825b26c9acebaaf8b7806f245bd`

## Executive result

**Overall: Partially passed; not ready to call the unattended enrichment flow reliable.**

The deployed application, dashboard, card browsing, transaction display,
movie optimizer, settings safety control, responsive layout, Edge authorization,
and review-only benefit staging are working. Three user-visible issues and one
release-blocking backend issue remain:

1. Scheduled enrichment still hits Supabase `WORKER_RESOURCE_LIMIT` (HTTP 546)
   for a single card and leaves the job leased until recovery.
2. The admin `Sign in again` action returns to the dashboard instead of forcing
   a new authorization flow.
3. One PNB card remains generic and lacks last-four/verified-benefit identity.
4. Mobile `Transactions` navigation text wraps awkwardly.

## Post-remediation verification

Verified on 17 August 2026 after production release `54bcf75`:

- Frontend deployment workflow `32011436755` completed successfully.
- The mobile visual label is now the one-line `Spend` label while accessibility
  continues to expose the destination as `Transactions`.
- Expired admin authorization now clears the stale local Supabase session
  before returning the user to login.
- Migration `20260817082925` is recorded in production and the live claim RPC
  contains the `worker_resource_limit` recovery guard.
- Scheduler smoke runs `32014113354` and `32014222983` completed successfully.
- After the known Axis worker lease expired, it moved to `review_required` with
  failure category `worker_resource_limit`; its lease token and expiry were
  cleared and `lease_expired` was recorded in the safe result summary.
- The scheduled queue continued from 158 to 157 queued jobs, demonstrating
  that the resource-heavy card no longer blocks subsequent work indefinitely.

The generic PNB identity and possible issuer-level credit-limit duplication
remain data-quality follow-ups. They were not auto-corrected without unique
supporting evidence.

## Scenario results

| # | Scenario | Result | Production evidence | Required change |
|---|---|---|---|---|
| 1 | Latest production deployment | Pass | GitHub Actions workflow `32007264499` completed successfully for `b143223`; `/app/` returns HTTP 200. | None. |
| 2 | Security and cache headers | Pass | HSTS, CSP, `X-Frame-Options: DENY`, `nosniff`, permissions policy, and `Cache-Control: no-cache` observed on `/app/`. | None. |
| 3 | Authenticated dashboard | Pass | Dashboard loaded 14 cards, bills, spend summary and recent transactions with no browser console warnings. | None. |
| 4 | Card carousel mouse drag | Pass | Click-drag moved the carousel from PNB cards to Axis Privilege and IndusInd EazyDiner Platinum; position indicator changed. | None. |
| 5 | Known variant normalization | Pass | Live card list shows Privilege, EazyDiner Platinum, White Reserve, Swiggy, Tata Neu Infinity, Adani One, Sapphiro, Amazon Pay and Diners Club Black. | None for these variants. |
| 6 | HSBC primary last four | Pass | HSBC TravelOne displays masked last four `1759`. | None. |
| 7 | PNB identity resolution | Fail | Two PNB cards remain: one `Select` ending `7372`, and one generic `Punjab National Bank` with no last four and no verified benefits. | Re-run identity extraction for the generic PNB card using statement subject/PDF header and the approved PNB URL; merge only if issuer, variant and last-four evidence agree. |
| 8 | Cards list and details | Pass with data gap | Cards page and generic PNB details page load. Generic card correctly avoids inventing benefits, but its identity remains incomplete. | Resolve the PNB identity gap above. |
| 9 | Transactions page | Pass | 17 filtered transactions, spend chart, categories and reward values rendered without console warnings. | None for rendering; transaction completeness was not re-synced during this read-only QA run. |
| 10 | Movie optimizer | Pass | Two tickets at ₹200 produced ₹400 base amount and rendered owned/overall offer comparisons. | None. |
| 11 | Settings data deletion control | Pass (presence only) | `Delete all CardCompass data` is present in the danger zone while account profile remains separate. Destructive confirmation was intentionally not executed. | Add/retain an automated integration test for exact data scope. |
| 12 | Admin expired-session message | Pass | Admin route shows `Your session needs authorization` and a `Sign in again` action instead of hanging or exposing a raw fetch error. | None for error presentation. |
| 13 | Admin reauthorization action | Fail | Clicking `Sign in again` returned to `/app` because the global route guard still accepted the cached session; no fresh authorization occurred. | Invalidate/refresh the stale session before routing, or launch an explicit OAuth re-consent flow with a safe return URL to the admin queue. |
| 14 | Admin queue contents | Blocked in UI; pass via backend inspection | Expired admin authorization prevented UI inspection. Read-only DB QA found five pending `official_benefit_enrichment` proposals. | Fix reauthorization, then repeat approve/edit/reject UI QA while preserving review-only writes. |
| 15 | Edge endpoint authorization | Pass | Admin OPTIONS = 200; unauthenticated admin POST = 401; unauthenticated batch POST = 401. | None. |
| 16 | Benefit promotion safety | Pass | Live counts: 491 benefits, 18 mappings, 10 staging records. Five enrichment proposals are pending; none were automatically approved. | None. |
| 17 | Scheduler secret and invocation | Pass once, then fail under real recovery load | Workflow `32007220929` succeeded after throttling. After leases expired, workflow `32008225149` failed with HTTP 546 on one card. | See scheduler RCA below. |
| 18 | Queue progression | Fail | Current scheduled queue: 159 queued, 1 processing, 5 failed/unreachable, 4 quarantined/identity mismatch, 3 quarantined/insufficient evidence, 3 staged. | Prevent a resource-killed card from repeatedly blocking unattended runs. |
| 19 | Mobile layout | Partial pass | Dashboard/cards and bottom navigation render at 390×844. `Transactions` wraps as `Transaction` + `s`. | Use shorter label, smaller adaptive type, or allocate equal navigation widths with a one-line constraint. |
| 20 | Credit-limit aggregate | Needs data validation | HDFC `₹10.1L` and ICICI `₹20L` appear repeatedly on multiple cards, while dashboard reports `₹1.03Cr across 14 cards`. This may double-count issuer-shared limits. | Model credit-line identity separately from cards and sum unique credit lines, or label the total as per-card limits if duplication is intentional. |

## Scheduled enrichment RCA

The schedule itself and secret authentication work. The failing production run
claimed only one scheduled card, then the Supabase Edge runtime terminated the
worker after roughly eight seconds with HTTP 546. Because termination happens
outside the application exception path, the job remains `processing` until its
15-minute lease expires. The next run can recover it, but the same expensive
card can kill the worker again.

Recommended correction:

1. Split orchestration from extraction. The scheduled endpoint should claim one
   job and dispatch it to a durable per-job worker/queue rather than performing
   scraping and PDF extraction inside the scheduler request.
2. Add an expired-lease watchdog. On recovery, record a stable
   `worker_resource_limit` failure and quarantine/review the card after the
   configured attempt ceiling instead of immediately reclaiming it forever.
3. Store a processing phase (`fetch_primary`, `fetch_supporting`, `parse_pdf`,
   `stage`) before each expensive step so the failing resource can be identified.
4. Keep HTML and PDF processing separately budgeted. Large or complex PDFs
   should be sent to a constrained document worker or admin review, not parsed
   in the orchestration function.
5. Make the GitHub workflow fail on non-zero `failed`/stuck lease outcomes, not
   merely on transport status, and publish the sanitized run summary as an
   artifact.

## QA limitations

- No destructive data deletion was executed.
- No admin approval, edit, merge, retry or rejection was submitted.
- Gmail was not re-synced; this report validates the already-populated 90-day
  dataset and deployed UI behavior.
- Admin queue UI contents could not be inspected after the deliberate expired
  authorization scenario because reauthorization is currently defective.

## Evidence links

- Successful production deployment: https://github.com/shantanuchandra/cardcompass/actions/runs/32007264499
- Successful throttled scheduler smoke run: https://github.com/shantanuchandra/cardcompass/actions/runs/32007220929
- Failed post-lease scheduler recovery run: https://github.com/shantanuchandra/cardcompass/actions/runs/32008225149
