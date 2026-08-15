# CardCompass founder operating scorecard

## Measurement rules

Update every Friday and at **every 25 qualified leads**. Keep a frozen weekly snapshot so later definition changes do not rewrite history. Report counts beside percentages; never show a rate without its denominator.

A **waitlist start** is the allow-listed `Waitlist Started` event. A **completed application** is accepted enrichment. A **qualified lead** is a completed application that meets the current, pre-declared cohort rule (initial default: 3–6 or 7+ cards, a selected spend band, selected primary goal and a credible card-choice problem). An **activated invitee** completes the first-value action defined before the cohort is sent. Initial first value: wallet setup plus one inspectable card decision with its caveat/source viewed.

## Core formulas and thresholds

| Metric | Formula | Continue | Watch / change | Stop / pause |
|---|---|---:|---:|---:|
| Application completion rate | **Application completion rate = completed applications / waitlist starts** | ≥ 55% | 35–54% | &lt; 35% for 2 weeks |
| Qualified lead rate | **Qualified lead rate = qualified leads / completed applications** | ≥ 45% | 25–44% | &lt; 25% across 25 completed applications |
| Invite activation rate | **Invite activation rate = activated invitees / invites sent** | ≥ 60% | 40–59% | &lt; 40% for 2 cohorts |
| Week-2 retention | **Week-2 retention = invitees active in week 2 / activated invitees** | ≥ 40% | 25–39% | &lt; 25% for 2 mature cohorts |
| Second-decision rate | users completing a second real decision within 14 days / activated invitees | ≥ 35% | 20–34% | &lt; 20% for 2 mature cohorts |
| Source-qualified rate | qualified leads from source / completed applications from source | ≥ overall rate | within 10 points below | &gt;15 points below after 20 completions |
| Founder support load | total founder support minutes / activated invitees | ≤ 30 min | 31–60 min | &gt;60 min for a cohort |
| Trust issue rate | invitees reporting a material source/privacy/incorrect-rule issue / activated invitees | &lt; 10% and no high severity open | 10–20% | any unresolved high-severity issue or &gt;20% |
| Interview coverage | completed learning interviews / activated invitees | 20–35% | 10–19% | &lt;10% |

“Active in week 2” means at least one meaningful session on days 8–14 after activation that reaches a saved/inspectable decision, statement review or milestone/movie-deal action; merely opening an email does not count.

## Weekly scorecard template

| Field | This week | Cumulative | Threshold status | Evidence / decision |
|---|---:|---:|---|---|
| Waitlist starts |  |  |  |  |
| Completed applications |  |  |  |  |
| Qualified leads |  |  |  |  |
| Invites sent (cohort ID) |  |  |  |  |
| Activated invitees |  |  |  |  |
| Mature Week-2 cohort denominator |  |  |  |  |
| Week-2 active invitees |  |  |  |  |
| Second decisions within 14 days |  |  |  |  |
| Founder support minutes |  |  |  |  |
| Material trust issues opened / closed |  |  |  |  |
| Interviews completed |  |  |  |  |
| Tuesday / Thursday content shipped |  |  |  |  |

## Source table

Use the acquisition source and landing variant persisted with the waitlist record. Do not use query-bearing URLs from analytics; landing analytics deliberately strips query parameters.

| Source | Starts | Completed | Qualified | Completion rate | Qualified rate | Invited | Activated | Week-2 active | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Founder network |  |  |  |  |  |  |  |  |  |
| Reddit/community (name) |  |  |  |  |  |  |  |  |  |
| Search utility: best card |  |  |  |  |  |  |  |  |  |
| Search utility: milestone tracker |  |  |  |  |  |  |  |  |  |
| Search utility: movie offers |  |  |  |  |  |  |  |  |  |
| Referral |  |  |  |  |  |  |  |  |  |

## Cohort log

| Cohort | Sent date | Hypothesis | Invites | Activated | Week-2 eligible date | Week-2 active | Support min/user | Dominant blocker | Continue? |
|---|---|---|---:|---:|---|---:|---:|---|---|
| F100-01 |  |  | 10–15 |  |  |  |  |  |  |

A cohort becomes mature for Week-2 retention only after every member has passed day 14. Never mix people who have not had the observation window into the denominator.

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

If a week has 80 waitlist starts, 48 completed applications and 24 qualified leads:

- Application completion rate = 48 / 80 = 60% → continue.
- Qualified lead rate = 24 / 48 = 50% → continue.

If a cohort sends 12 invites, 7 activate, and 2 of those 7 are active in days 8–14:

- Invite activation rate = 7 / 12 = 58.3% → watch.
- Week-2 retention = 2 / 7 = 28.6% → watch.

Do not round denominators, and do not call the retention result final until the cohort is mature.
