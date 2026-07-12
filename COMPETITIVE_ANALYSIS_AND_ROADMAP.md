# CardCompass — Competitive Analysis & Product Roadmap

**Date:** July 11, 2026
**Purpose:** Understand what CardCompass does today, see how it stacks up against real competitors, and lay out a phased plan to make it significantly better — written so a novice PM can follow it end-to-end.

---

## 1. What CardCompass Does Today

CardCompass is an **AI-powered credit card rewards optimizer for the Indian market**. In plain English: it tries to answer *"which of my cards should I use for this purchase, and am I leaving money on the table?"*

How it works today:

1. **Connect Gmail** → the app searches your inbox for bank statement emails.
2. **Download & unlock statement PDFs** → auto-guesses passwords (birthday-based).
3. **Gemini AI reads the PDF** → extracts transactions, dates, amounts, merchants.
4. **Transactions get categorized** (dining, fuel, travel, etc.) and matched against a database of ~183 Indian credit cards and their benefit rules (category rates, merchant offers, milestones, caps).
5. **The app recommends the best card** for a transaction, and has a specialized engine just for **movie ticket offers** (BookMyShow/PVR BOGO deals, which are unusually complex in India).
6. It also has (partial) screens for analytics, benefit tracking, notifications, and statements.

**Reality check (important):** the underlying Supabase backend is currently expired/dead, several screens are stubs ("Coming soon"), there are duplicate/conflicting home screens, API keys are hardcoded in source, and there's no monetization or eligibility logic yet. It's a **strong prototype with a genuinely hard, valuable AI pipeline already built** — not yet a polished, trustworthy consumer product.

---

## 2. The Competitive Landscape

I researched two groups: **India-focused card optimizers** (direct competitors) and **global "best card to use" apps** (proof of what a mature version of this product looks like).

### Group A — India card optimizer / comparison tools

| Competitor | What it does well | What it lacks |
|---|---|---|
| **CardSaathi** | 98-card database, deep redemption/transfer strategy guides (e.g. "never redeem HDFC points as statement credit, use SmartBuy") | Requires manual spend entry, no real transaction data, no app/wallet |
| **Vyaya** | Free calculator, lets you **upload statements** to find "gaps" in rewards, 154 cards | Statement upload is a one-time analysis, not an ongoing tracked wallet |
| **CardGenie** | AI chat ("GenieAI") for card Q&A, personalized matching quiz | Card discovery/affiliate focused, not a spend-tracking tool |
| **CardTrail** | "Which Card Tonight" — compares up to 5 of *your* cards against a merchant instantly, forex-fee-aware | Still manual entry per lookup, no automatic transaction capture |
| **Creget** | Ranks cards by **net annual value** and layers in **income-based eligibility** (are you even likely to get approved?) | Discovery-only, not a usage/optimization tool for cards you already own |
| **CRED** | Massive scale (25M+ users), bill payments, autopay, credit score tracking, spend insights, reads email/SMS for bill tracking | Focused on *paying bills* and lifestyle rewards, not on *which card to swipe* — genuinely different problem, but eats CardCompass's air in "manage my cards" mental space |
| **SaveSage** ⚠️ | **The closest real competitor.** VC-funded (₹4cr / ~$1M raised, appeared on Shark Tank India). AI assistant "Savvy" answers exactly the questions CardCompass targets — *"which card should I use for this purchase?"*, *"which of my cards give 1+1 on movie tickets?"* (yes, they explicitly market the movie-ticket use case too), *"how do I redeem points for a hotel in Dubai?"*. Has a full "Travel on Points" redemption engine, claims users go from ~2% to ~14% effective rewards, and monetizes today via **Pro/Elite/Private subscription tiers** (Elite adds human-expert consultations) | No browser extension or checkout-time automation found; app-only. Some public backlash after Shark Tank about being a paid platform — a cautionary tale on being upfront about pricing early |

**Key insight:** every India-focused optimizer requires the user to *manually type in* their spending, upload a one-off statement, or (in SaveSage's case) link accounts via aggregator/read-only access. **None of them do what CardCompass already does** — automatically pull real transactions on an ongoing basis via Gmail + AI. That is CardCompass's single biggest, defensible advantage — if it can be made reliable. But note: **SaveSage is the one competitor already executing on almost the exact same vision** (AI assistant + redemption guidance + movie-ticket niche + subscription revenue), is funded, and is already in market. It should be treated as the primary benchmark, not a secondary one — and the fact that even SaveSage has no browser extension is CardCompass's clearest opening (see Category 1 below).

### Group B — Global "best card to use" apps (mature market proof points)

| Competitor | Signature feature | Pricing |
|---|---|---|
| **MaxRewards** | Connects to real card accounts, auto-activates rotating bonus categories, "best card by category/location" | $54–108/yr |
| **CardPointers** | Largest card database, deep Apple/Siri/Safari integration, visually *hides* the wrong card in your wallet view | $49–99/yr |
| **Kudos** | Free browser extension: at online checkout it **auto-picks the best card and autofills the card number + CVV**, shares cashback commission back with users ("Boost") | Free (+ optional paid Boost) |

**Key insight:** in mature markets, the winning product isn't a calculator — it's something that sits **at the moment of payment** (browser extension, widget, Siri shortcut, "Cheatsheet" for in-store) and removes the thinking entirely. CardCompass today only tells you the answer if you *open the app and check* — it doesn't show up at the moment you actually need it.

### Group C — Adjacent open-source projects (validates the niche, proves it's hard)

Several GitHub projects (Momento, Stmtforge, finn-lens, expense_tracker) independently rebuilt "Gmail → PDF → AI → transactions" for India. This confirms two things: (1) the problem is real and people want it solved, and (2) nobody has turned it into a **trustworthy, polished, ongoing product** yet — they're all scripts/CLIs/single-bank hobby projects. That's the gap CardCompass can own.

---

## 3. Where CardCompass Can Get Significantly Better

Grouping the opportunity into categories, roughly in order of how foundational they are:

### Category 0 — Trust & Reliability (must-fix before anything else matters)
The Supabase backend is expired, secrets are hardcoded in the app, and there are duplicate home screens. This is a fintech-adjacent app asking for **Gmail access and bank statement data** — if the basics feel broken, users will never trust it enough to connect their inbox. No feature below matters until this is solid.

### Category 1 — Moment-of-Decision UX (biggest gap vs. global leaders — and vs. SaveSage)
Right now the recommendation only appears if you open the app. Kudos/CardPointers/MaxRewards win by appearing **exactly when you're about to pay** — browser extension at checkout, home-screen widget, Siri/quick-tile for in-store. CardCompass has the smartest backend logic (movie rule engine, milestone tracking) but the *weakest* delivery moment. Importantly, **not even SaveSage** (the best-funded, most direct India competitor) has a browser extension — every India player, including the market leader, still makes the user open an app and ask. A checkout-time browser extension would be a genuine first, not just a catch-up feature.

### Category 2 — Faster, Fresher Data (double down on the existing moat, without reading SMS)
Gmail statement parsing is powerful but **slow** — statements arrive monthly, days after the purchase, so recommendations are always retrospective. The improvement here should **not** come from reading SMS (privacy-invasive, and explicitly ruled out for this product) — a better path is:
1. **Parse the instant transaction-alert emails banks already send** (separate from the monthly statement email) — same Gmail permission already granted, no new invasive access, and alerts typically land within seconds/minutes of a swipe.
2. **Explore India's RBI-regulated Account Aggregator (AA) framework** (Setu, Finvu, OneMoney, CAMS Finserv, etc.) as a medium-term upgrade — this is a consent-based, bank-approved way to pull real transaction data directly from the issuing bank, with the user explicitly approving and able to revoke access at any time. It's a stronger trust story than Gmail parsing ("your bank shares data with our RBI-licensed partner, with your consent" beats "we read your inbox"), though credit-card coverage among AA-linked banks is still growing, so Gmail parsing should remain the reliable fallback while this is evaluated.
Either path moves CardCompass from "here's what you should have done" to "here's what to do right now" — without touching SMS.

### Category 3 — Rewards & Redemption Intelligence
Accrued points are tracked nowhere (`reward_balances` table doesn't even exist yet), and there's no guidance on redemption value. CardSaathi's whole differentiator is "here's how to not waste your points" (e.g., redeeming HDFC points at ₹1 via SmartBuy instead of ₹0.30 as statement credit). This is high-value, low-effort content + a features layer CardCompass is well-positioned to add given it already tracks real spend.

### Category 4 — Proactive Nudges (an advantage no competitor can easily copy)
Because CardCompass has real transaction history, it's the only product in this list that *could* say "you're ₹4,000 away from your Amazon Pay milestone this cycle — spend before the 25th" or "you haven't used your airport lounge visit this quarter." Nobody else in the India set has the underlying data to do this. This should be a flagship feature, not an afterthought.

### Category 5 — Card Discovery & Monetization
Creget and CardGenie make money by matching people to *new* cards (with income-based eligibility) and sending them to apply. CardCompass has zero monetization today. Adding an honest "you might benefit from Card X because of how you spend" recommendation, with eligibility checks, is both useful to users and a real revenue path (affiliate commissions + eventual premium tier).

### Category 6 — Everyday India-Specific Scenarios (defend the home turf)
Note: the movie-ticket rule engine is **not** a unique differentiator anymore — SaveSage explicitly markets the same "1+1 movie ticket" use case. What *is* still open: **no-cost EMI vs. reward-point tradeoffs**, and automatically tracking **"bank offer" sale promotions** (e.g., 10% instant discount with a specific bank card during Flipkart/Amazon sales) — neither CardSaathi/Vyaya/CardGenie/CardTrail/Creget nor SaveSage appear to deeply cover these, and both are huge, everyday India-specific decisions. CardCompass's movie-ticket engine proves the team can build this kind of niche logic well; the move now is to apply that same muscle to genuinely uncontested scenarios rather than ones SaveSage already owns.

### Category 7 — Conversational Assistant
CardGenie's "Ask GenieAI" chat and SaveSage's "Savvy" are both popular for open-ended card questions — this is now a **category expectation, not a differentiator**. CardCompass needs an assistant to stay competitive, but should win on grounding: answers referencing the *user's actual cards and real transaction history* (which CardCompass already has from its ingestion pipeline) rather than generic card facts alone.

---

## 4. The Agentic Plan — In Simple English

Think of this as five stages. Each stage has a **goal**, **what "done" looks like**, and **why we do it in this order**. Nothing in a later stage is worth doing if the stage before it isn't solid — a leaky foundation makes every feature on top of it untrustworthy.

**Stage 0 — Make the house not fall down.**
Goal: the app reliably works for a real user, end to end, with no broken backend or fake data.
Done looks like: a new user can sign up, connect Gmail, sync one real statement, and see one real, correct recommendation — with no crashes, no "coming soon" screens in that path, and no secrets sitting in the source code.
Good news: you already have a `db_cluster` backup of the old Supabase project sitting in the repo root — this is a full dump (schema + data + roles), so Stage 0 isn't "rebuild from zero," it's "spin up a fresh Supabase (or self-hosted Postgres) project and restore this backup," then rotate all the secrets that were previously hardcoded (they must be treated as compromised since they've been sitting in source control) and reconnect the app to the new project.
Why first: you cannot ask someone to trust an app with their bank statements if the basic plumbing is broken. Every subsequent feature is built on this pipe.

**Stage 1 — Make the recommendation show up when it's actually needed.**
Goal: the "which card should I use" answer meets the user at checkout or in-store, not buried in an app they have to remember to open.
Done looks like: a browser extension or web widget that suggests the best card while shopping online, plus a home-screen widget / quick-access card for in-store use.
Why now: this is the single biggest feature gap versus the products people already pay for abroad (Kudos, CardPointers, MaxRewards) — and versus SaveSage, the best-funded India competitor, which also doesn't have this. Without this, CardCompass is "a calculator you have to remember to use," which every India competitor, including the market leader, already is. This is the clearest, most-loved-by-the-team idea, so it's the flagship of the whole plan.

**Stage 2 — Make the data arrive faster (no SMS).**
Goal: move from "we know what you spent last month" to "we know what you just spent" — without ever asking to read SMS.
Done looks like: transactions show up within minutes by parsing the **instant transaction-alert emails** banks already send (a different, faster email than the monthly statement, using the Gmail access already granted), with India's consent-based **Account Aggregator** framework (Setu/Finvu/OneMoney) explored as a longer-term, more trustworthy upgrade once credit-card coverage on that network matures.
Why now: this is what makes Stage 1's real-time recommendations actually powerful, and it's the thing India competitors structurally can't copy easily (they only do manual entry) — achieved without the privacy trade-off of SMS access.

**Stage 3 — Turn tracked data into money-saving nudges.**
Goal: proactively tell users about milestones they're about to miss, points that are about to expire, or a bank sale offer they should use.
Done looks like: push notifications like "spend ₹4,000 more by the 25th to unlock your milestone reward" or "use HDFC card today — 10% instant discount on this Amazon sale."
Why now: this only becomes trustworthy once Stage 0–2 are solid (accurate, timely data). It's also the feature no competitor can easily copy, because it requires the real transaction pipeline CardCompass already invested in building.

**Stage 4 — Help people find their *next* card, and make money doing it.**
Goal: recommend new cards based on real spending patterns (not guesses), check if the user is likely eligible, and earn a commission when they apply.
Done looks like: a "you could be earning ₹X more per year with Card Y" screen with an apply button, backed by actual data instead of a generic quiz.
Why now: monetization should come after the core product is genuinely useful and trusted — recommending a paid product before that point damages trust; recommending it once the app has real data about the user makes the pitch honest and personalized (better than any competitor's generic quiz).

**Stage 5 — Cover the everyday India-specific edge cases, and add a smart assistant.**
Goal: extend the "movie ticket engine" pattern to 2–3 more high-value, *not-yet-owned-by-SaveSage* scenarios (EMI vs. rewards tradeoff, e-commerce sale bank offers), and let users ask questions in plain language grounded in their real cards.
Why last: these are high-value polish and differentiation features, best built once the core loop (know your cards → know your spend → get a real-time recommendation → get proactive nudges) is working end-to-end. An AI chat assistant is now table stakes (both CardGenie and SaveSage have one) rather than a differentiator, so it belongs here, not earlier.

---

## 5. Roadmap: Features, Sequenced, With Reasons

| Phase | Feature | Why it's on the roadmap |
|---|---|---|
| **Phase 0 — Foundation** | Restore the `db_cluster` backup into a fresh Supabase project, then rotate every secret that was previously hardcoded in source (treat them as compromised) | You already have the old schema + data saved locally — this turns Phase 0 from "rebuild from scratch" into "restore, then re-secure." Any key that was ever committed to source must be rotated regardless of the restore. |
| **Phase 0** | Fix guest mode & duplicate home screens, finish stubbed screens ("coming soon" → real) | A fintech-adjacent app asking for Gmail access can't have a broken or confusing first-run experience — it undermines trust before the AI pipeline even gets a chance to prove itself. |
| **Phase 0** | End-to-end reliability testing of the Gmail → PDF → Gemini → DB pipeline for the top 5–6 banks | This pipeline is the core moat; if it silently fails or mis-parses, every downstream recommendation is wrong and trust is destroyed instantly. |
| **Phase 1 — Be there at checkout** | Browser extension: "best card for this site/cart" + one-click autofill | Directly matches the #1 feature of every paid global competitor (Kudos, CardPointers, MaxRewards) — and it's a feature **not even SaveSage** (India's best-funded, most direct competitor) has built yet. This is the biggest usage-frequency lever available, and the team's favorite idea. |
| **Phase 1** | Home-screen widget / quick-glance "best card right now" card | Same logic as the extension, for in-store and non-browser use — closes the gap for users who don't shop online as much. |
| **Phase 1** | Fix and ship the in-app "Smart Transaction Analyzer" as the primary dashboard action (not buried in a menu) | Quick win using logic that already exists in the codebase — just needs to be the star of the home screen instead of a secondary widget. |
| **Phase 2 — Fresher data, no SMS** | Parse banks' **instant transaction-alert emails** (separate from monthly statements) using the Gmail access already granted | Alert emails land within seconds/minutes of a swipe, versus weeks for statements — a real-time lift with zero new invasive permissions. |
| **Phase 2** | Reconcile alert-email transactions with statement transactions (dedupe, correct amounts once the official statement lands) | Needed so "fast but rough" alert data and "slow but accurate" statement data don't create duplicate or conflicting entries. |
| **Phase 2** | Evaluate India's Account Aggregator network (Setu/Finvu/OneMoney/CAMS) as a consent-based, bank-approved real-time data source | A more trustworthy long-term story than any inbox-reading approach ("your bank shares data with an RBI-licensed partner, with your explicit, revocable consent") — worth a scoping spike once credit-card FIP coverage looks sufficient. |
| **Phase 3 — Rewards intelligence** | Build the missing `reward_balances` tracking (points/cashback balance per card, live) | The data model literally doesn't have this table yet; it's a prerequisite for any redemption guidance. |
| **Phase 3** | "How much is my point worth" redemption guidance per bank (steal CardSaathi's best idea, but personalized to the user's actual balance) | This is content + logic CardCompass can build once, and it directly answers the #1 complaint people have about card rewards: not knowing how to redeem well. |
| **Phase 3** | Points-expiry and milestone-progress push notifications | Converts passive tracking into money saved — "you're close, spend X more" or "these points expire in 30 days." No India competitor has the transaction data to do this credibly. |
| **Phase 4 — Discovery & monetization** | "Your next card" recommendation engine, using the user's actual 90-day spend (not a generic quiz) | Personalized recommendations backed by real data will out-convert every competitor's generic "answer 5 questions" quiz — and this is the natural first revenue stream (affiliate). |
| **Phase 4** | Income/eligibility pre-check before recommending a card to apply for | Copies Creget's smartest idea — recommending a card the user can't get approved for is a bad, trust-destroying experience. |
| **Phase 4** | Premium tier (e.g. unlimited cards tracked, priority sync, advanced analytics) | Mirrors the proven MaxRewards/CardPointers subscription model as a second revenue stream, once usage frequency (Phase 1–3) justifies asking for payment. |
| **Phase 5 — Depth & delight** | 2–3 new "rule engines" beyond movies: no-cost EMI vs. rewards tradeoff calculator, live bank sale-offer tracker for e-commerce | Extends the one thing CardCompass has already proven it's good at (deep, correct, India-specific benefit logic) into scenarios neither SaveSage nor the calculator-style competitors have deeply covered — the movie-ticket niche alone is no longer uncontested since SaveSage markets it too. |
| **Phase 5** | Conversational assistant grounded in the user's real cards/transactions ("Ask CardCompass") | Matches CardGenie's "GenieAI" and SaveSage's "Savvy" — now a category expectation, not a differentiator — but with a real advantage: answers can reference the user's *actual* cards and spend instead of generic card facts. |

---

## 6. One-Line Summary Per Stakeholder

- **For engineering:** restore the `db_cluster` backup into a fresh backend, rotate every secret, and fix the broken screens before building anything new; the recommendation logic is already good, the delivery and data-freshness are not.
- **For design/product:** move the "best card" answer out of the app and into the moment of payment via a browser extension — that's the single highest-leverage change, and the one thing not even the best-funded India competitor (SaveSage) has shipped.
- **For business/monetization:** don't charge anything until Phase 1–3 make the app used weekly, then monetize via card discovery/affiliate first, subscription second — and be more upfront about pricing earlier than SaveSage was, given the backlash it got after Shark Tank India.
- **For the pitch:** "Every other India tool — including the funded ones — makes you open an app and ask. CardCompass already knows your real spending automatically, and it's the only one that shows up right at checkout, without you lifting a finger."

---

## 7. Notes From This Review Round

- **Competitor added:** SaveSage (Gurugram, founded 2024, ~$1M pre-seed raised, Shark Tank India appearance) is the closest direct competitor and should be tracked ongoing — check their app periodically for a browser extension or checkout integration, since that's currently CardCompass's clearest window of advantage.
- **SMS-based real-time capture removed from the plan** per product decision — Phase 2 now relies only on (a) parsing existing instant alert emails via the Gmail access already granted, and (b) a future scoping spike into India's Account Aggregator framework, neither of which requires reading SMS.
- **Backend recovery de-risked:** a `db_cluster-07-11-2025@19-08-30.backup.gz` full Postgres cluster dump (schema, data, and roles) is already saved in the repo root. Phase 0 should restore from this into a new Supabase project rather than rebuilding the schema from scratch — but every credential in the old project (API keys, DB passwords) must still be rotated, since they were exposed in source control regardless of whether the project itself is renewed.
