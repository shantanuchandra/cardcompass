-- get_user_transactions declared column 14 (statement_id) as text, matching
-- transactions.statement_id at the time it was written. Migration
-- 20260714020000_enforce_user_card_ownership.sql later converted that column
-- to uuid (adding a real FK to statements) without updating this function's
-- signature, so every call now fails with "structure of query does not match
-- function result type... Returned type uuid does not match expected type
-- text in column 14." Cast the selected value back to text here rather than
-- changing the declared return type, since the Dart client (Transaction.
-- statementId) expects a String.

CREATE OR REPLACE FUNCTION public.get_user_transactions(_user_id uuid, _limit integer DEFAULT 50) RETURNS TABLE(id uuid, user_id uuid, user_card_id uuid, amount numeric, currency text, description text, merchant_name text, category text, transaction_type text, transaction_date timestamp with time zone, location text, reward_earned numeric, reward_type text, statement_id text, metadata jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, bank text, card_name text, last_four_digits text, network text, card_type text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.user_id,
        t.user_card_id,
        t.amount,
        t.currency,
        t.description,
        t.merchant_name,
        t.category,
        t.transaction_type,
        t.transaction_date,
        t.location,
        t.reward_earned,
        t.reward_type,
        t.statement_id::text,
        t.metadata,
        t.created_at,
        t.updated_at,
        -- Card details from catalog via user_cards
        cc.bank,
        cc.card_name,
        uc.last_four_digits,
        cc.network,
        cc.card_type
    FROM transactions t
    LEFT JOIN user_cards uc ON t.user_card_id = uc.id
    LEFT JOIN card_catalog cc ON uc.catalog_card_id = cc.id
    WHERE t.user_id = _user_id
    ORDER BY t.transaction_date DESC
    LIMIT _limit;
END;
$$;
