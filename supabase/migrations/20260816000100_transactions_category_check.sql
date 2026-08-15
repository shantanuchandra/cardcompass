-- supabase/migrations/20260816000100_transactions_category_check.sql
--
-- Enforces the 16-category vocabulary at the database level. Added NOT
-- VALID so it doesn't fail against existing rows that may hold
-- legacy/invalid category values (e.g. 'dining', 'bills', NULL) — NOT
-- VALID enforces the constraint for all NEW writes immediately without
-- scanning existing rows. The companion migration that runs VALIDATE
-- CONSTRAINT (20260816000200) must not be applied until the backfill job
-- (application-level, category_backfill_service.dart, a later task) has
-- fixed every pre-existing invalid row.
--
-- This list must match lib/core/services/transaction_categorizer.dart's
-- validCategories and the merchant_category_map migration's inline CHECK
-- (20260816000000_merchant_category_map.sql) character-for-character —
-- verified identical against both as of this migration's authoring.
alter table public.transactions
  add constraint transactions_category_valid check (
    category is null or category in (
      'food', 'fuel', 'grocery', 'entertainment', 'travel', 'shopping',
      'utilities', 'insurance', 'medical', 'education', 'investment',
      'transport', 'rental', 'subscription', 'gift', 'other'
    )
  ) not valid;
