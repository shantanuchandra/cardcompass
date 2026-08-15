# CardCompass founder-led GTM playbook

## Operating thesis

The first goal is not the biggest waitlist. It is a small, observable group of Indian multi-card users who repeatedly face the problem CardCompass is designed to solve: deciding among several cards while accounting for caps, milestones and offer conditions.

The founder owns the first eight weeks. Work in invite cohorts of **10–15 people**, learn from behaviour and direct conversations, and review the system at **every 25 qualified leads** before increasing volume. A qualified lead is an applicant with the required qualification fields completed and a credible multi-card/reward-optimisation need under the scorecard definition.

## Weekly operating rhythm

Every week uses the same loop:

- Monday: review the scorecard, open user issues and prior-week interviews; choose one learning question.
- Tuesday: publish the first of the **twice-weekly** useful content pieces and answer relevant community questions.
- Wednesday: interview or observe 2–3 current users; summarise evidence without exposing personal financial details.
- Thursday: publish the second content piece; send the next invite cohort only if the previous cohort's activation/support load is understood.
- Friday: reconcile waitlist sources, invitations, activation and retention; decide what to keep, change or stop.

The founder should reserve one daily 30-minute block for responses. Fast, specific support is part of research during early access, but it should not become unscheduled all-day messaging.

## Security launch gate

Do not begin broad acquisition until the card-data hardening migration `20260815090910_remove_legacy_card_secrets.sql` has been applied and verified in the target Supabase project. Repository state alone does not prove deployed database state.

Before clearing this gate:

- Apply the migration through the controlled database deployment process; do not auto-apply it from a marketing or landing-page deployment.
- Run the supplied reset/upgrade and permission checks in a non-production environment first.
- Verify in the target project that `user_cards.card_number` and `user_cards.expiry_date` are absent and that the unsafe historical `associate_user_with_card`, `update_user_card`, and `get_user_cards` signatures are absent.
- Record the environment, migration version, verification time, operator, commands and results in the launch record.
- Keep broad acquisition paused if any check is incomplete or fails. A small internal remediation cohort must not submit PAN, expiry, CVV, PIN, OTP or banking credentials.

## External launch gates: consent, abuse and analytics

- Do not send marketing mail from `marketing_consent_requested_at`. It records an unverified request only. Marketing remains blocked until an email-ownership verification mechanism and unsubscribe workflow are configured, tested and able to set `marketing_consent_at` only after verification.
- The database honeypot and hashed-email rate bucket reduce repeated same-address calls without retaining raw IP. They are not a complete bot boundary. Broad production acquisition remains blocked until a server or Edge boundary with Turnstile (or equivalent) is configured with external secrets and tested.
- In Plausible, create custom event goals with the exact names `Waitlist Started`, `Waitlist Joined`, `Enrichment Submitted`, and `Waitlist Error`. Verify each goal in production with query-free URLs and allow-listed properties before launch. `Enrichment Submitted` is diagnostic only; completed applications come from non-null `enriched_at` in the operator view.
- Apply migrations through the controlled database workflow, then open Supabase Studio with an authorized service workflow. Read `operator_waitlist_ranked`; mutate only through `update_waitlist_operator(...)`. Never expose a service-role or secret key to the browser or export the enrichment token hash.
- Production OAuth remains gated on adding the exact `https://cardcompass.in/app/` redirect URL in Supabase Auth and completing a deployed callback/session test.
- The repository's standalone `login/` directory is non-deployed legacy material. Production and the local public server expose authentication only through the Flutter app under `/app/`; no campaign or public navigation may link to `/login/`.
- Target-database apply, executable reset/upgrade/RLS tests, qualified legal review, email verification configuration, Turnstile configuration and Plausible account setup are explicit external launch gates, not completed repository work.

## 8-week cadence

| Week | Learning objective | Founder actions | Exit evidence |
|---|---|---|---|
| 1 | Establish a trustworthy baseline | Verify analytics and attribution; manually inspect the first qualified applications; interview five people about the last card-choice mistake they remember. Publish “headline rate vs cap” and a worked purchase example. | Source and application counts reconcile; five concrete decision stories are documented. |
| 2 | Test problem language | Invite one cohort of 10–15. Observe first-session comprehension. Publish a cap checklist and a milestone-period explainer. | At least 70% of invitees can explain the product's job without founder coaching; objections are tagged. |
| 3 | Test first value | Invite the next cohort only after Week 2 support is resolved. Observe whether users can add their actual cards and reach one inspectable decision. Publish an anonymised calculation and a “what this estimate excludes” post. | Activation threshold is met or a single dominant activation blocker is identified. |
| 4 | Test repeat need | Ask activated users to use CardCompass for a second real purchase. Publish movie-offer cap arithmetic and a reward-point valuation note. Conduct the first every-25-qualified-leads review if the threshold is reached. | Week-2 retention and second-decision rate have a defensible denominator. |
| 5 | Test trust | Interview users who ignored or overrode a recommendation. Inspect whether caveats and sources answered their concern. Publish “when not to trust a best-card list” and a source-verification walkthrough. | At least 80% of interviewed active users can locate the caveat/source; material mismatches are triaged. |
| 6 | Test narrow referral | Ask high-intent active users whether one specific person in their circle has the same problem. Do not add rewards yet. Publish a multi-card workflow and a milestone “do not overspend” example. | Referred applicants can be separated from founder outreach; referral quality is no worse than the baseline cohort. |
| 7 | Test proof responsibly | Identify 2–3 possible case studies and run the consent protocol below. Publish only approved, evidence-backed material plus a product-change note. | At least one consented case study or a documented decision not to publish; no implied savings claims. |
| 8 | Decide the next motion | Review eight weeks of source quality, activation, retention, support effort and interview evidence. Run the next every-25-qualified-leads review if due. Publish a transparent “what we learned” note and one evergreen utility piece. | Choose: continue founder cohorts, narrow the ICP, repair activation, or pause acquisition. Record owner and next threshold. |

## Twice-weekly content calendar

Use one practical teaching piece on Tuesday and one evidence/decision piece on Thursday. Each piece should solve a narrow question before mentioning CardCompass.

| Week | Tuesday: search/community utility | Thursday: founder evidence |
|---|---|---|
| 1 | Why a 5% credit-card rate can lose after the cap | A worked ₹4,000 comparison with every assumption visible |
| 2 | How to calculate remaining monthly cashback cap | Five phrases users use for the “which card?” problem |
| 3 | Convert reward points to a conservative rupee rate | What the first cohort misunderstood and what changed |
| 4 | Credit-card milestone tracker: period, eligible spend, posting | BOGO is not always 50%: a fee-and-cap example |
| 5 | Checklist for verifying an issuer benefit source | Why a user overrode a recommendation (with permission or as a composite) |
| 6 | A three-card pre-payment decision routine | What a second real-world decision revealed |
| 7 | How to compare movie offers by final payable amount | A consented case study or an anonymised learning note |
| 8 | Best-card calculator methodology and limitations | Eight-week learning report and the next product bet |

Every post needs a source date, caveat and one next action. Avoid unsupported market-size, accuracy and savings statistics. Update or withdraw a post when the cited issuer rule changes.

## Reddit and community conduct

Communities are places to participate, not lists to harvest.

1. Read the community rules and recent moderator guidance before posting. If product links or research requests are prohibited, do not post them.
2. Use a clearly identifiable founder account. Disclose the CardCompass relationship on every relevant post or reply; never pose as a satisfied user.
3. Lead with a complete answer. A reader should get value without clicking a CardCompass link.
4. Link only when it directly answers the question and the community rules permit it. Use the attributed URL assigned to that community; do not conceal redirects.
5. Do not mass-DM, scrape usernames, buy aged accounts, coordinate votes, repost the same copy across groups or ask users to promote CardCompass without disclosure.
6. Ask a commenter for permission before moving to direct messages. Keep the conversation in public when personal details are unnecessary.
7. Do not request statements, full card numbers, CVV, PIN, OTP, banking passwords or other credentials in a community thread or DM.
8. Treat negative feedback as evidence. Correct factual errors publicly, log the issue and avoid arguments about intent.
9. If a moderator removes content, do not repost around the decision. Ask once for clarification only when the rules genuinely appear ambiguous.
10. Record community, post URL, disclosure, moderator outcome and useful questions in the weekly log—not personal profile dossiers.

## Invite-cohort procedure

Before each cohort of 10–15:

- Confirm the prior cohort's urgent support issues are resolved or explicitly accepted.
- Choose a narrow cohort hypothesis: for example, people with 3–6 cards and monthly card spend above ₹25,000 who mention caps or milestones.
- Personalise the invitation using the applicant's stated goal or problem; do not infer sensitive traits.
- Send from a monitored founder address, include why the recipient is receiving it and give an easy decline route.
- Freeze the cohort membership and timestamp so activation/retention denominators cannot drift.
- Do not replace non-responders inside the same cohort; account for them in the invite activation rate.
- Wait at least 72 hours before one short follow-up. Stop after that unless the person replies.

Move to another cohort only when the scorecard says “continue” and founder support capacity is below the pause threshold.

## Review at every 25 qualified leads

At 25, 50, 75 and 100 cumulative qualified leads, stop outbound invitations for one working session and answer:

1. Which sources produced qualified leads rather than raw emails?
2. Where did application completion, invite activation and first value fall below threshold?
3. What did retained users do twice that one-session users did once?
4. Which promise or content piece attracted the wrong expectation?
5. Are Gmail/PDF/data-flow questions blocking trust?
6. Which issuer-rule mismatches were reported, and how quickly were they corrected?
7. What is median founder support time per activated user?
8. Is there enough evidence to invite the next 10–15, or should acquisition pause for a product fix?

Record the decision, evidence, owner and date in the scorecard. Do not retroactively redefine “qualified” to improve a rate.

## Interview guide

Use 20–25 minutes. Ask about behaviour before opinions:

- Tell me about the last purchase where you considered more than one card.
- Which rules did you check, and where?
- What did you choose? What made you uncertain?
- Show me how you would verify the recommendation and caveat.
- Which part would make you stop trusting the product?
- When would you use this again without a reminder?

Do not ask “Would you pay?” until a user has experienced the workflow. Do not coach a user through a confusing step before noting where they became blocked.

## Case-study consent protocol

Case studies require a separate, explicit process; product use, marketing consent and interview participation do not grant publication rights.

1. Prepare the exact draft: name/alias, role if relevant, quotations, screenshots, numerical outcomes and channels where it will appear.
2. Remove statement lines, merchant details, card last-four digits, email addresses and other personal financial data unless genuinely necessary and explicitly approved.
3. Explain that participation is optional, product access is unaffected and there is no guarantee the draft will be published.
4. Obtain **written consent** to the exact draft and named channels. Silence is not consent.
5. For savings or reward claims, preserve the calculation, inputs, issuer source and verification date. Label estimates and do not extrapolate one user to all users.
6. Store the consent record and approved version together. Do not reuse material in a new channel or materially edit its meaning without fresh approval.
7. Give the participant a contact route to correct or **withdraw** future use. Remove the case study from CardCompass-controlled channels promptly after a verified withdrawal request; explain that cached or third-party copies may persist.
8. Reconfirm time-sensitive outcomes before republishing them after six months.

## Decision rule after eight weeks

- Continue cohorts when qualified-lead rate, activation, Week-2 retention and support load meet the scorecard thresholds, with no unresolved high-severity trust issue.
- Narrow the audience when one source/persona retains materially better and the pattern is supported by interviews.
- Pause acquisition when activation or retention misses the stop threshold for two cohorts, founder support exceeds capacity, or a privacy/security/source-integrity issue remains unresolved.
- Do not compensate for weak retention by sending more invitations.
