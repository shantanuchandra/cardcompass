-- supabase/migrations/20260802100100_benefit_platform_confirmations.sql
--
-- Design spec §6. Additive only — does not alter benefits, card_benefit_mapping,
-- user_cards, or transactions.
--
-- Security model, reasoned through statically (no live DB available to test
-- against in this environment):
--   - RLS is enabled with only an INSERT policy scoped to auth.uid() = user_id.
--     There is no SELECT policy.
--   - REVOKE ALL + GRANT INSERT means `authenticated` has the INSERT grant
--     only — no SELECT/UPDATE/DELETE grant on the base table at all. Grant
--     checks happen before RLS policies are even consulted, so a direct
--     SELECT against the base table fails at the grant layer regardless of
--     RLS, meaning authenticated users cannot read the raw table, not even
--     their own rows.
--   - security_invoker = false (the Postgres default for views; stated here
--     explicitly rather than relied upon implicitly) makes the aggregate
--     view execute as its owner (the migration-running role), which is why
--     the view can read across all users' rows to compute a count despite
--     `authenticated` having no direct grant on the base table.
--   - The view's column list (benefit_id, platform_key, confirmation_count)
--     never projects user_id — it is consumed only inside
--     count(DISTINCT user_id) — so individual confirmation identity cannot
--     be reconstructed from the view even though it reads owner-privileged.
--   - Precedent check: this codebase already uses ENABLE ROW LEVEL SECURITY
--     + REVOKE ALL ... FROM anon, authenticated on a table as a defense in
--     depth idiom (see card_benefits_staging in
--     20260712030000_card_benefits_staging.sql), so that half of this
--     pattern is conventional here. However, no other migration in this
--     repo sets security_invoker = false on a view — the one existing
--     precedent (reward_balances in 20260714030000_reward_balances_view.sql)
--     sets it to true, for the opposite reason (re-checking per-row RLS so
--     each user sees only their own data). This view's intent is the
--     opposite: an aggregate, deliberately non-personalized count, so the
--     opposite setting is the deliberate and correct choice here, not an
--     accidental deviation from convention — but it is a genuinely new
--     pattern in this codebase and has not been exercised against a live
--     database in this session.
BEGIN;

CREATE TABLE IF NOT EXISTS benefit_platform_confirmations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  benefit_id    uuid NOT NULL REFERENCES benefits(benefit_id),
  platform      text NOT NULL CHECK (trim(platform) <> ''),
  platform_key  text GENERATED ALWAYS AS (lower(trim(platform))) STORED,
  user_id       uuid NOT NULL REFERENCES auth.users(id),
  confirmed_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, benefit_id, platform_key)
);

CREATE INDEX IF NOT EXISTS idx_benefit_platform_confirmations_lookup
  ON benefit_platform_confirmations(benefit_id, platform_key);

ALTER TABLE benefit_platform_confirmations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated insert own confirmation" ON benefit_platform_confirmations;
CREATE POLICY "authenticated insert own confirmation"
  ON benefit_platform_confirmations FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE VIEW benefit_platform_confirmation_counts
  WITH (security_invoker = false) AS
  SELECT benefit_id, platform_key, count(DISTINCT user_id) AS confirmation_count
  FROM benefit_platform_confirmations
  GROUP BY benefit_id, platform_key;

REVOKE ALL ON benefit_platform_confirmations FROM authenticated;
GRANT INSERT ON benefit_platform_confirmations TO authenticated;
GRANT SELECT ON benefit_platform_confirmation_counts TO authenticated;

COMMIT;
