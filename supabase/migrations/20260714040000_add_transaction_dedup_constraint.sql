-- Prevent duplicate transaction rows from being inserted more than once for
-- the same user/card/date/description/amount combination. A code comment in
-- supabase_transaction_repository.dart previously claimed this constraint
-- already existed; it did not. Verified no pre-existing duplicate rows before
-- adding this index.
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_dedup
  ON transactions (user_id, user_card_id, transaction_date, description, amount);
