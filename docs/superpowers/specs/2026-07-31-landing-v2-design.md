# CardCompass Landing Page v2 — Design Spec

**Date:** 2026-07-31  
**Status:** Approved  
**Branch:** `feature/landing-v2`

---

## 1. Goal

Rebuild the CardCompass landing page from scratch — same tech stack (pure HTML/CSS/JS), latest patterns — starting with the hero + waitlist form. The existing `landing/` folder is replaced on a git worktree branch; main is untouched until merge.

---

## 2. Tech Stack

- **HTML/CSS/JS** — no build step, no framework, no `node_modules`
- **Supabase JS client** — loaded via CDN (`@supabase/supabase-js` ESM)
- **Fonts** — Space Grotesk (headings) + Plus Jakarta Sans (body) via Google Fonts
- **Deployment** — same as existing (static hosting, `landing/` folder)

---

## 3. File Structure

```
landing/
  index.html     — single page, all sections
  style.css      — custom properties, animations, layout
  script.js      — form logic, validation, Supabase calls, modal
  img/           — existing assets preserved (favicon, etc.)
  llm.txt        — unchanged
```

---

## 4. Page Section Flow

```
Nav             — logo left, "Sign In" right → /app/
Hero            — dark, blobs, centered; email CTA; 2-step form trigger
How It Works    — 3-step: Gmail connect → AI reads → Best card shown
Stats           — 183+ cards · 50+ categories · ₹50k+ saved
Features        — 4 tiles: Movie Tickets, Milestones, Nudges, Analytics
FAQ             — 4–5 accordion items (privacy, Gmail, data, banks)
Bottom Waitlist — full-width repeat CTA with same 2-step form
Footer          — links, legal, cardcompass.in
```

---

## 5. Waitlist Form — Two-Step Flow

### Step 1 — Email (hero)
- Single email input + "Get Early Access" button
- Button disabled until email passes format validation: `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`
- On submit: `INSERT` into `waitlist(email)` via Supabase anon key
- On success: hero form fades to "Joined ✓"; modal opens after 300ms delay
- On `23505` unique violation: show "You're already on the list!" inline, skip modal

### Step 2 — Enrichment (modal)
- Appears after successful Step 1 insert
- Fields: name (text input, optional) + card count (select, optional)
- Card count options: `1–2`, `3–5`, `6+`
- "Save & close" → `UPDATE waitlist SET name=?, card_count=? WHERE id=?` using the id returned from Step 1 insert
- "Skip" or close (✕) → modal dismisses, no update made, nulls stay in DB
- Bottom repeat form uses the exact same logic

---

## 6. Supabase Schema

```sql
create table waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  name        text,                          -- null until enrichment
  card_count  text,                          -- '1-2' | '3-5' | '6+' | null
  created_at  timestamptz default now()
);
```

**RLS policy:**
- Anon can `INSERT` (email only)
- Anon can `UPDATE` own row matched by `id` (for enrichment)
- No anon `SELECT`

---

## 7. Visual Design

| Property | Value |
|---|---|
| Background | `#0a0a0f` |
| Primary accent | `#00F5FF` (cyan) |
| Secondary accent | `#8B5CF6` (purple) |
| Body text | `rgba(255,255,255,0.6)` |
| Heading text | `#ffffff` |
| Heading font | Space Grotesk 700/800 |
| Body font | Plus Jakarta Sans 400/500 |

**Animations:**
- 2 animated SVG blobs (blurred, slow-moving) — reduced from 4 in v1 for less noise
- Particle canvas removed entirely
- Section fade-ins via `IntersectionObserver` (no library)
- Magnetic button effect on primary CTAs (CSS transform on mousemove)
- Modal entrance: scale from 0.95 + fade-in, 200ms ease-out

---

## 8. Implementation Approach

- Git worktree on branch `feature/landing-v2`
- `landing/` folder rebuilt from scratch on that branch
- Existing `main` branch `landing/` unchanged until explicit merge
- Supabase anon key and project URL stored as JS constants at top of `script.js` (to be replaced with env-injected values before public launch)

---

## 9. Out of Scope (this iteration)

- Confirmation email to the user after signup
- Waitlist count / social proof counter (live from DB)
- Admin dashboard for viewing signups
- Analytics / event tracking
- Blog or dynamic content sections
- App screens or feature deep-dives beyond the 4 feature tiles
