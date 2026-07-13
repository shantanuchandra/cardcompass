-- Reward balances, derived entirely from data that already exists in
-- transactions (reward_earned, reward_type). No new base table: nothing in
-- the product yet tracks redemptions, so a mutable "balance" table would
-- have no real writer and no source of truth for the redeemed side. This
-- view is read-only and always consistent with the underlying transactions.
--
-- id is deterministic (user_card_id + reward_type) so callers can treat it
-- like a stable primary key even though the view has no physical row.
CREATE OR REPLACE VIEW reward_balances AS
SELECT
  encode(sha256((t.user_card_id::text || ':' || t.reward_type)::bytea), 'hex') AS id,
  t.user_id,
  t.user_card_id,
  t.reward_type,
  SUM(t.reward_earned) AS available_balance,
  SUM(t.reward_earned) AS total_earned,
  0::decimal(12,2) AS total_redeemed,
  0::decimal(12,2) AS pending_balance,
  MAX(t.transaction_date) AS last_earned_at,
  MAX(t.updated_at) AS last_updated,
  MIN(t.created_at) AS created_at
FROM transactions t
WHERE t.reward_earned IS NOT NULL
  AND t.reward_earned > 0
  AND t.reward_type IS NOT NULL
GROUP BY t.user_id, t.user_card_id, t.reward_type;

-- Views inherit the querying role's grants, not RLS from the base table
-- directly, but security_invoker makes Postgres re-check the underlying
-- transactions RLS policy (auth.uid() = user_id) for every row.
ALTER VIEW reward_balances SET (security_invoker = true);

GRANT SELECT ON reward_balances TO authenticated;
