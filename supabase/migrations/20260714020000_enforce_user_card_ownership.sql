-- Make user_cards the authoritative ownership boundary for statements and
-- transactions. user_cards already enforces (user_id, catalog_card_id); this
-- migration stops statements/transactions from bypassing that boundary via a
-- nullable user_card_id and a uniqueness constraint keyed on the shared
-- card_catalog product instead of the user's owned card.

-- Backfill any statements missing user_card_id by resolving through user_cards.
UPDATE statements s
SET user_card_id = uc.id
FROM user_cards uc
WHERE s.user_card_id IS NULL
  AND uc.user_id = s.user_id
  AND uc.catalog_card_id = s.card_id;

-- Backfill any transactions missing user_card_id via their statement's card.
UPDATE transactions t
SET user_card_id = uc.id
FROM user_cards uc
WHERE t.user_card_id IS NULL
  AND uc.user_id = t.user_id
  AND uc.catalog_card_id = (
    SELECT s.card_id FROM statements s WHERE s.id::text = t.statement_id LIMIT 1
  );

-- Fail loudly instead of silently dropping rows that still can't be resolved.
DO $$
DECLARE
  orphaned_statements INTEGER;
  orphaned_transactions INTEGER;
BEGIN
  SELECT count(*) INTO orphaned_statements FROM statements WHERE user_card_id IS NULL;
  SELECT count(*) INTO orphaned_transactions FROM transactions WHERE user_card_id IS NULL;

  IF orphaned_statements > 0 OR orphaned_transactions > 0 THEN
    RAISE EXCEPTION
      'Cannot enforce user_card_id ownership: % statements and % transactions have no resolvable user_cards match. Resolve manually before rerunning.',
      orphaned_statements, orphaned_transactions;
  END IF;
END $$;

ALTER TABLE statements
  ALTER COLUMN user_card_id SET NOT NULL;

ALTER TABLE statements
  DROP CONSTRAINT IF EXISTS statements_card_id_statement_date_key;

ALTER TABLE statements
  ADD CONSTRAINT statements_user_card_statement_date_key
  UNIQUE (user_card_id, statement_date);

ALTER TABLE transactions
  ALTER COLUMN user_card_id SET NOT NULL;

-- transactions.statement_id is TEXT with no FK; tighten it to a real
-- reference so a transaction can't point at a nonexistent statement.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM transactions
    WHERE statement_id IS NOT NULL
      AND statement_id !~ '^[0-9a-fA-F-]{36}$'
  ) THEN
    RAISE EXCEPTION 'Non-UUID transactions.statement_id values present; resolve before migrating';
  END IF;
END $$;

ALTER TABLE transactions
  ALTER COLUMN statement_id TYPE uuid USING statement_id::uuid;

ALTER TABLE transactions
  ADD CONSTRAINT transactions_statement_id_fkey
  FOREIGN KEY (statement_id) REFERENCES statements(id) ON DELETE SET NULL;
