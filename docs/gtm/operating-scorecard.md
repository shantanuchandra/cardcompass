# CardCompass founder operating scorecard

## Measurement rules

Update every Friday and at **every 25 qualified leads**. Keep a frozen weekly snapshot so later definition changes do not rewrite history. Report counts beside percentages; never show a rate without its denominator.

A **waitlist start** is the allow-listed `Waitlist Started` event. A **completed application** is a database row with non-null `enriched_at`, counted from the service-role operator view. The browser-side `Enrichment Submitted` event is diagnostic only: duplicate joins receive decoy success-shaped responses, so it must never be used as the completion numerator. A **qualified lead** is a completed application that meets the current, pre-declared cohort rule (initial default: 3–6 or 7+ cards, a selected spend band, selected primary goal and a credible card-choice problem). `legacy-6-plus` is excluded until requalification. An **activated invitee** completes the first-value action defined before the cohort is sent. Initial first value: wallet setup plus one inspectable card decision with its caveat/source viewed.

The overall application completion rate reconciles Plausible starts with database `enriched_at` completions and is not source-segmented. Query attribution remains in Supabase; analytics accepts only closed, known experiment variants. Never infer source-level starts or completion rates by joining individual visitors across those systems.

## Core formulas and thresholds

| Metric | Formula | Continue | Watch / change | Stop / pause |
|---|---|---:|---:|---:|
| Application completion rate | **Application completion rate = completed applications / waitlist starts** (a completed application is a submitted application) | ≥ 55% | ≥ 35% and &lt; 55% | &lt; 35% for 2 weeks |
| Qualified lead rate | **Qualified lead rate = qualified leads / completed applications** (submitted applications) | ≥ 45% | ≥ 25% and &lt; 45% | &lt; 25% across 25 submitted applications |
| Invite activation rate | **Invite activation rate = activated invitees / invites sent** | ≥ 60% | ≥ 40% and &lt; 60% | &lt; 40% for 2 cohorts |
| Week-2 retention | **Week-2 retention = invitees active in week 2 / activated invitees** who have individually matured | ≥ 40% | ≥ 25% and &lt; 40% | &lt; 25% for 2 mature samples |
| Second-decision rate | users completing a second real decision within 14 days / mature activated users | ≥ 35% | ≥ 20% and &lt; 35% | &lt; 20% for 2 mature samples |
| Source-qualified rate | **Source-qualified rate = qualified submitted applications from source / submitted applications from source** | ≥ overall rate | below overall but < 15 percentage points below overall | ≥ 15 percentage points below overall after 20 submissions |
| Founder support load | total founder support minutes / activated invitees | ≤ 30 min | &gt; 30 and ≤ 60 min | &gt; 60 min for a cohort |
| Trust issue rate | invitees reporting a material source/privacy/incorrect-rule issue / activated invitees | &lt; 10% and no high severity open | ≥ 10% and ≤ 20%, with no high severity open | &gt; 20% or any unresolved high-severity issue |
| Interview coverage | completed learning interviews / activated invitees | 20–40% | 10–<20% or >40% | <10% |

Each activated user becomes denominator-eligible on day 14, and is counted active only for a meaningful session on days 8–14 after their own activation date that reaches a saved/inspectable decision, statement review or milestone/movie-deal action; merely opening an email does not count. This rolling per-user maturity rule avoids delaying early invitees until every member of an arbitrary send cohort matures.

## Weekly scorecard template

| Field | This week | Cumulative | Threshold status | Evidence / decision |
|---|---:|---:|---|---|
| Waitlist starts |  |  |  |  |
| Submitted applications |  |  |  |  |
| Qualified leads |  |  |  |  |
| Invites sent (cohort ID) |  |  |  |  |
| Activated invitees |  |  |  |  |
| Mature activated-user denominator |  |  |  |  |
| Week-2 active invitees |  |  |  |  |
| Second decisions within 14 days |  |  |  |  |
| Founder support minutes |  |  |  |  |
| Material trust issues opened / closed |  |  |  |  |
| Interviews completed |  |  |  |  |
| Tuesday / Thursday content shipped |  |  |  |  |

## Source table

Use the acquisition source and landing variant persisted with the waitlist record. Do not use query-bearing URLs from analytics; landing analytics deliberately strips query parameters.

| Source | Submitted | Qualified | Source-qualified rate | Invited | Activated | Week-2 active | Decision |
|---|---:|---:|---:|---:|---:|---:|---|
| Founder network |  |  |  |  |  |  |  |
| Reddit/community (name) |  |  |  |  |  |  |  |
| Search utility: best card |  |  |  |  |  |  |  |
| Search utility: milestone tracker |  |  |  |  |  |  |  |
| Search utility: movie offers |  |  |  |  |  |  |  |
| Referral |  |  |  |  |  |  |  |

## Cohort log

| Cohort | Sent date | Hypothesis | Invites | Activated | Week-2 eligible date | Week-2 active | Support min/user | Dominant blocker | Continue? |
|---|---|---|---:|---:|---|---:|---:|---|---|
| F100-01 |  |  | 10–15 |  |  |  |  |  |  |

Maturity is individual, not cohort-wide. Add each activated user to the Week-2 denominator after that user passes day 14; never include someone who has not yet had the full observation window.

## Every-25 review record

Run this at 25, 50, 75 and 100 cumulative qualified leads.

| Review | Date | Qualified total | Best source | Largest funnel loss | Product/trust blocker | Support capacity | Decision | Owner / due date |
|---|---|---:|---|---|---|---|---|---|
| Q25 |  | 25 |  |  |  |  | Continue / narrow / pause |  |

Required decision logic:

1. **Pause immediately** for an unresolved high-severity privacy, security or materially incorrect recommendation-source issue.
2. **Pause acquisition for a product fix** when invite activation is below 40% for two cohorts, Week-2 retention is below 25% for two mature cohorts, or founder support load is above 60 minutes per activated user.
3. **Narrow the next cohort** when one source or need-state beats overall Week-2 retention by at least 15 percentage points with at least 10 activated users and supporting interview evidence.
4. **Continue with 10–15 invitations** only when no pause rule fires and the founder can support the cohort.
5. Do not change definitions mid-cohort. Log a version and apply the new definition prospectively.

## Content scorecard

The twice-weekly calendar is a learning channel, not a vanity target.

| Post | Date | Channel | Search/community question | Source/verification date present? | Qualified applications | Useful replies/saves | Follow-up action |
|---|---|---|---|---|---:|---:|---|
|  |  |  |  | Yes / No |  |  |  |

Treat clicks, impressions and upvotes as diagnostic context. A post succeeds when it produces qualified applications, a repeated user question or evidence that changes onboarding/product copy.

## Worked formula example

If a week has 80 waitlist starts, 48 submitted applications and 24 qualified leads:

- Application completion rate = 48 / 80 = 60% → continue.
- Qualified lead rate = 24 / 48 = 50% → continue.

If a cohort sends 12 invites, 7 activate, and 2 of those 7 are active in days 8–14:

- Invite activation rate = 7 / 12 = 58.3% → watch.
- Week-2 retention = 2 / 7 = 28.6% → watch.

Do not round denominators, and do not call the retention result final until the cohort is mature.
