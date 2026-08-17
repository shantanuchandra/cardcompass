# CardCompass Production QA Report

Date: 17 August 2026
Environment: `https://www.cardcompass.in/app/`
Production branch: `prod` at `b1432233de12054080b4366973185449a6a287eb`
Backend worker: `main` at `b79f7a2ab5bb7825b26c9acebaaf8b7806f245bd`

## Executive result

**Overall: Passed with the unattended enrichment worker's resource-heavy cards
contained for admin review rather than allowed to block the queue.**

The deployed application, dashboard, card browsing, transaction display,
movie optimizer, settings safety control, responsive layout, Edge authorization,
and review-only benefit staging are working. The production findings below
were remediated and rechecked: expired worker leases no longer block the queue,
admin reauthorization clears stale local auth, the PNB duplicate is resolved,
and the mobile navigation label no longer wraps.

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

The PNB follow-up was resolved after the user supplied the official PNB Select
page and confirmed that it applied to the unknown statement. A guarded
production transaction moved the lone July statement to the existing Select
card ending `7372`, left the generic source row inactive for rollback, and
deleted no data. Production now has one active PNB Select card with three
statements and eight transactions.

The dashboard credit-limit metric is now labelled `Reported card limits` with
the disclosure that issuer limits may overlap. CardCompass does not currently
model shared credit-line identity, so it no longer presents the per-card sum as
an authoritative total available credit limit.

## Scenario results

| # | Scenario | Result | Production evidence | Required change |
|---|---|---|---|---|
| 1 | Latest production deployment | Pass | GitHub Actions workflow `32007264499` completed successfully for `b143223`; `/app/` returns HTTP 200. | None. |
| 2 | Security and cache headers | Pass | HSTS, CSP, `X-Frame-Options: DENY`, `nosniff`, permissions policy, and `Cache-Control: no-cache` observed on `/app/`. | None. |
| 3 | Authenticated dashboard | Pass | Dashboard loaded 14 cards, bills, spend summary and recent transactions with no browser console warnings. | None. |
| 4 | Card carousel mouse drag | Pass | Click-drag moved the carousel from PNB cards to Axis Privilege and IndusInd EazyDiner Platinum; position indicator changed. | None. |
| 5 | Known variant normalization | Pass | Live card list shows Privilege, EazyDiner Platinum, White Reserve, Swiggy, Tata Neu Infinity, Adani One, Sapphiro, Amazon Pay and Diners Club Black. | None for these variants. |
| 6 | HSBC primary last four | Pass | HSBC TravelOne displays masked last four `1759`. | None. |
| 7 | PNB identity resolution | Pass | Official `pnbcard.in/types6.html` evidence plus explicit user confirmation identified the unknown as PNB Select. The active Select ending `7372` now owns all three statements; the empty generic row is inactive and retained for rollback. | None. |
| 8 | Cards list and details | Pass | Cards page and card details load; the empty generic PNB record is inactive and no longer appears as a separate owned card. | None. |
| 9 | Transactions page | Pass | 17 filtered transactions, spend chart, categories and reward values rendered without console warnings. | None for rendering; transaction completeness was not re-synced during this read-only QA run. |
| 10 | Movie optimizer | Pass | Two tickets at ₹200 produced ₹400 base amount and rendered owned/overall offer comparisons. | None. |
| 11 | Settings data deletion control | Pass (presence only) | `Delete all CardCompass data` is present in the danger zone while account profile remains separate. Destructive confirmation was intentionally not executed. | Add/retain an automated integration test for exact data scope. |
| 12 | Admin expired-session message | Pass | Admin route shows `Your session needs authorization` and a `Sign in again` action instead of hanging or exposing a raw fetch error. | None for error presentation. |
| 13 | Admin reauthorization action | Pass | `Sign in again` now awaits local Supabase sign-out before navigation, forcing fresh authorization rather than reusing the stale session. | None. |
| 14 | Admin queue contents | Blocked in UI; pass via backend inspection | Expired admin authorization prevented UI inspection. Read-only DB QA found five pending `official_benefit_enrichment` proposals. | Fix reauthorization, then repeat approve/edit/reject UI QA while preserving review-only writes. |
| 15 | Edge endpoint authorization | Pass | Admin OPTIONS = 200; unauthenticated admin POST = 401; unauthenticated batch POST = 401. | None. |
| 16 | Benefit promotion safety | Pass | Live counts: 491 benefits, 18 mappings, 10 staging records. Five enrichment proposals are pending; none were automatically approved. | None. |
| 17 | Scheduler secret and invocation | Pass with containment | Smoke workflows `32014113354` and `32014222983` succeeded. A resource-heavy card is now moved to review after the attempt ceiling instead of blocking later jobs. | Future enhancement: isolate expensive extraction in a durable per-job worker. |
| 18 | Queue progression | Pass | The known expired Axis lease became `review_required`, lease fields were cleared, and the queued count progressed from 158 to 157. | Continue monitoring queue throughput. |
| 19 | Mobile layout | Pass | Dashboard/cards and bottom navigation render at 390×844; the visual label is the one-line `Spend` while accessibility semantics remain `Transactions`. | None. |
| 20 | Credit-limit aggregate | Pass with explicit limitation | HDFC `₹10.1L` and ICICI `₹20L` appear repeatedly on multiple cards and may represent shared issuer limits. The dashboard now calls the sum `Reported card limits` and discloses that issuer limits may overlap. | Future enhancement: model issuer credit-line identity before presenting total available credit. |

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
