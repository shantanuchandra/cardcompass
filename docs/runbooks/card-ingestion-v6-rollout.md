# Card ingestion v6 rollout and rollback

Last updated: 2026-08-21

## Scope and owners

This runbook controls the dark deployment, pilot, staged rollout, and rollback of
the `benefits-v6` ingestion and issuer-discovery architecture.

- Release owner: Shantanu Chandra.
- Database and Edge deployment owner: the CardCompass repository maintainer
  performing the release.
- Review owner: a verified database administrator using the admin review UI.
- Exact hosted target: Supabase project `cardcompass`, project reference
  `prbcoxqobhjnnfnxevxf`, URL `https://prbcoxqobhjnnfnxevxf.supabase.co`.
- Never run these commands against another project reference, a preview project,
  or a database URL that is not checked against the reference above.

The workflow uses only these pre-existing secret names. Do not print, download,
rotate, or replace their values during rollout:

- Supabase Edge: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  `BENEFIT_ENRICHMENT_CRON_SECRET`.
- GitHub Actions: `SUPABASE_URL`, `SUPABASE_FUNCTION_URL`,
  `BENEFIT_ENRICHMENT_CRON_SECRET`.

## Dark-state controls

All three controls must agree before scheduled work is permitted:

1. `public.admin_runtime_controls.benefit_enrichment_scheduled.is_paused` is
   `true` during dark deployment and pilot preparation.
2. Repository variable `CARD_INGESTION_V6_SCHEDULE_ENABLED` is absent or not
   `true` until recurring v6 is approved.
3. Repository variable `CARD_DISCOVERY_SCHEDULE_ENABLED` is absent or not
   `true` until daily issuer discovery is approved.

Manual workflow dispatch remains available. A discovery dispatch with
`run_mode=manual` performs at most one issuer crawl and may stage review work,
but it does not publish catalog identity or benefits without an admin decision.

## Baseline recorded before dark deployment

Read-only snapshot on 2026-08-21:

- Latest hosted migration: `20260821160000`.
- Runtime control: paused, reason
  `Dark rollout pending benefits-v6 pilot verification`.
- Hosted enrichment inventory contains only `benefits-v1` through
  `benefits-v5`; there are zero `benefits-v6` jobs.
- Active consumer view contains 26 mappings.
- Deployed functions before this rollout: `admin-catalog-entry` v29,
  `benefit-enrichment-batch` v22, `card-discovery` v17,
  `catalog-enrichment` v8, and `request-card-catalog-entry` v6.
- The historical enrichment workflow runs every 15 minutes and issuer discovery
  every day. In the dark workflow definition, scheduled jobs are skipped unless
  their explicit repository variable is `true`; the database pause is the
  second fail-closed boundary.
- Task 11 hosted integration and two-session concurrency/rollback rehearsal:
  17 passed, zero residue, no deadlock. This is the release prerequisite for
  Task 12 and must remain attached to the release evidence.

## Supported issuer allowlist

The deployed discovery code accepts exactly these 15 first-party issuer roots:

| Issuer | Canonical root |
|---|---|
| Axis Bank | `https://www.axisbank.com/` |
| HDFC Bank | `https://www.hdfcbank.com/` |
| ICICI Bank | `https://www.icicibank.com/` |
| Kotak Bank | `https://www.kotak.com/` |
| IndusInd Bank | `https://www.indusind.com/` |
| HSBC | `https://www.hsbc.co.in/` |
| SBI Card | `https://www.sbicard.com/` |
| IDFC FIRST Bank | `https://www.idfcfirstbank.com/` |
| Yes Bank | `https://www.yesbank.in/` |
| AU Small Finance Bank | `https://www.aubank.in/` |
| RBL Bank | `https://www.rblbank.com/` |
| Bank of Baroda | `https://www.bobfinancial.com/` |
| Punjab National Bank | `https://www.pnbcard.in/` |
| Standard Chartered | `https://www.sc.com/in/` |
| American Express | `https://www.americanexpress.com/in/` |

Adding an issuer requires a separate reviewed code change; it is not a runtime
rollout operation.

## Capacity and timeout limits

- One enrichment job or one issuer is claimed per invocation.
- Function network deadline: 180 seconds.
- Workflow `curl` maximum: 240 seconds, with two bounded retries.
- Workflow job timeout: 5 minutes.
- Shared workflow concurrency group: `cardcompass-issuer-crawl`, with active
  work never cancelled or overlapped.
- Pilot: exactly five qualified cards, at least three issuers, all required
  page profiles, and explicit admin decisions for every staged target.

## Pre-deployment checks

Run from the reviewed worktree. None of these commands should display a secret.

```bash
git status --short
supabase projects list
supabase migration list --linked
supabase functions list --project-ref prbcoxqobhjnnfnxevxf
node --test test/gtm/benefit-enrichment-schedule.test.js \
  test/gtm/card-discovery-schedule.test.js
```

Using the password-free hosted integration defines described in
`test/supabase/README.md`, rerun the guarded hosted harness only if its recorded
Task 11 evidence is stale or the database contract changed. Never weaken its
project-reference, run-id, exact-ID cleanup, or two-session gates.

Read-only database checks:

```sql
select version
from supabase_migrations.schema_migrations
order by version desc limit 5;

select control_key, is_paused, reason, updated_at
from public.admin_runtime_controls
where control_key = 'benefit_enrichment_scheduled';

select parser_version, run_mode, status, count(*)
from public.card_catalog_enrichment_jobs
group by 1, 2, 3 order by 1, 2, 3;
```

Stop if the project reference differs, the migration chain is incomplete, the
runtime control is not paused, authenticated app reads regress, or an audit
reports an unhandled identity/shape conflict.

## Dark Edge deployment

Deploy with the Supabase API path; do not prune unrelated functions. Preserve
the existing JWT contract:

```bash
supabase functions deploy admin-catalog-entry \
  --project-ref prbcoxqobhjnnfnxevxf --use-api --no-verify-jwt
supabase functions deploy benefit-enrichment-batch \
  --project-ref prbcoxqobhjnnfnxevxf --use-api --no-verify-jwt
supabase functions deploy card-discovery \
  --project-ref prbcoxqobhjnnfnxevxf --use-api
supabase functions deploy catalog-enrichment \
  --project-ref prbcoxqobhjnnfnxevxf --use-api
supabase functions deploy request-card-catalog-entry \
  --project-ref prbcoxqobhjnnfnxevxf --use-api
```

Immediately re-read the function list and paused database control. Do not
enable either repository variable.

### Executed dark-deployment evidence — 2026-08-21

The five deployments completed successfully against the exact project. Hosted
versions advanced to `admin-catalog-entry` v30, `benefit-enrichment-batch` v23,
`card-discovery` v18, `catalog-enrichment` v9, and
`request-card-catalog-entry` v7. JWT verification modes were unchanged.

GitHub run `32472600905` invoked the deployed scheduled lane through the
protected secret and completed successfully with `status=paused`. The response
was handled as a successful dark-state no-op before inventory access. The
database control remained paused and the v6 job count remained zero.

## One-issuer dark smoke

Use GitHub Actions `Schedule issuer card discovery` with `run_mode=manual`.
The workflow supplies the existing protected cron credential; do not copy it to
a terminal. The expected response has `action=issuer_discovery`, `runMode=manual`,
`claimed` of 0 or 1, and a UUID `runId`.

After it completes, verify:

1. At most one issuer anchor/run was claimed.
2. Any new catalog item is pending review; none is approved or merged.
3. No `benefits-v6` live mapping was created.
4. No existing `benefits` or `card_benefit_mapping` row changed.
5. The runtime control remains paused and both schedule variables remain false
   or absent.

If the smoke fails after safely staging review work, keep that review for admin
inspection. Do not delete discovery, review, evidence, or audit history.

### Executed one-issuer smoke — 2026-08-21

GitHub run `32472690109` invoked `issuer_discovery` with `runMode=manual` and
completed successfully in 2 minutes 3 seconds. Run ID:
`6c0d20d0-4f99-4e88-8ace-c2303d1552d4`.

Fair rotation selected AU Small Finance Bank. The source blocked or replaced
the expected product bodies, so all attempted product pages failed the exact
requested-product check and the anchor stopped at the 40-candidate cap with
`candidate_fetch_cap_exceeded`. It retained 40 bounded quarantined candidate
outcomes plus two rejected non-card outcomes for resumable diagnosis. It did
not create a catalog review item because there was no positive product identity
evidence to approve. AU is blocked from rollout until a separately reviewed
fetch/browser policy can retrieve exact first-party product bodies.

Safety proof before and after the smoke:

| Object | Rows | State hash before | State hash after |
|---|---:|---|---|
| `card_catalog` | 186 | `4a2f0aaf2a6ab4e64c36f1446ea7f910` | same |
| `benefits` | 499 | `952cecfc23df89ea7a2060697195d119` | same |
| `card_benefit_mapping` | 26 | `5be84f6333e050c767cf8abd6e82d560` | same |

Pending catalog review count remained 19, `benefits-v6` job count remained
zero, and the scheduled runtime control remained paused. The temporary
branch-only workflow revision used to access the protected secret was restored
immediately; final branch head retains the normal paused scheduled dispatch.

## Five-card pilot acceptance

Do not start without explicit release-owner approval. Use the Task 10 acceptance
corpus: five cards, at least three issuers, required static/DOM/PDF/supporting
profiles, and one known-invalid negative observation corrected before final
qualification.

For every card, compare retained source evidence to each proposed addition,
edit, keep, reject, or retirement. The pilot passes only when the Edge replay
and locked SQL validator both qualify all five, review coverage is exact, there
are zero unsafe mutations, and pre/post live-state snapshots prove no unrelated
catalog, mapping, or benefit mutation.

## Ramp gates

1. Unpause the database control through the audited admin UI/RPC only after the
   pilot passes.
2. Set `CARD_INGESTION_V6_SCHEDULE_ENABLED=true` for one issuer, batch size one.
   Observe two scheduled invocations and one completed admin review.
3. Set `CARD_DISCOVERY_SCHEDULE_ENABLED=true` for one issuer slot only after the
   recurring lane is healthy.
4. Ramp issuer coverage 1 -> 3 -> all approved issuers. Hold each stage for one
   full schedule interval plus review completion.

Every expansion requires zero unsafe removals, zero cross-card mutation, no
rising review-required loop, bounded duration/rate-limit behavior, and consumer
reads still coming from `active_card_benefits`.

## Observability and customer-impact checks

Monitor by parser, mode, status, issuer, failure category, retry age, review age,
and `next_run_at`. Logs must contain run/job/issuer/card IDs and allowlisted
metric/reason names only; never raw response bodies, credentials, statement
metadata, or customer identifiers.

Before and after each gate, record aggregate counts for:

- queued, discovering/processing, failed, quarantined, review-required, staged,
  and completed v6 jobs;
- pending catalog and benefit reviews;
- active mappings and retired mappings;
- v6 benefit categories/types and cards/issuers represented;
- cards with a successful retrieval but no future due time;
- stale leases and duplicate active claims.

Customer-impact stop conditions include any authenticated-read regression,
missing live benefit, unexpected retirement, cross-card term change, duplicate
catalog identity, or publication without an explicit reviewed decision.

## Pause and rollback

Pause immediately by setting `benefit_enrichment_scheduled` to `true` through
the audited admin control and setting both repository schedule variables to
false/absent. Confirm scheduled responses are `paused` before inventory access.

Rollback is operational, not destructive:

1. Disable discovery and recurring v6 scheduling.
2. Leave additive migrations, URL/provenance keys, staging, jobs, reviews, and
   audits in place.
3. Retain or resume the compatible v5 lane.
4. Leave v6 `next_run_at` unclaimed under the disabled gates; do not bulk-delete
   or rewrite history.
5. Correct an incorrect retirement only through the audited admin action that
   restores `retired_at` to null.
6. Verify the app still reads active mappings and the pre-rollout mapping count
   is explainable.
7. Re-run the two-session rollback/deadlock rehearsal before any retry if SQL or
   lock ordering changed.

Do not roll migrations backward in production and do not delete evidence to
make counts appear healthy.

## Closure window

Keep v5 compatibility for at least 30 days. Close rollout only after seven days
or one full recurrence cycle in an accelerated staging-equivalent environment,
with recorded metrics, incidents, overrides, blocked issuers, and remaining
coverage work. Removing v5 requires its own reviewed migration and rollback
decision.
