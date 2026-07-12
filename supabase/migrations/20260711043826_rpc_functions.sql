--
-- Name: add_transaction(uuid, uuid, numeric, text, timestamp with time zone, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text DEFAULT 'INR'::text, _merchant_name text DEFAULT NULL::text, _location text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    transaction_id UUID;
BEGIN
    -- Validate required parameters
    IF _user_id IS NULL OR _user_card_id IS NULL OR _amount IS NULL THEN
        RAISE EXCEPTION 'Required parameters cannot be null: user_id, user_card_id, amount';
    END IF;
    
    -- Verify this card belongs to the user for security
    IF NOT EXISTS (SELECT 1 FROM user_cards WHERE id = _user_card_id AND user_id = _user_id) THEN
        RAISE EXCEPTION 'Card does not belong to user';
    END IF;
        
    INSERT INTO transactions (
        user_id, user_card_id, amount, description,
        transaction_date, category, transaction_type,
        currency, merchant_name, location
    ) VALUES (
        _user_id, _user_card_id, _amount, _description,
        _transaction_date, _category, _type,
        _currency, _merchant_name, _location
    ) RETURNING id INTO transaction_id;
    
    RETURN transaction_id;
END;
$$;


ALTER FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) OWNER TO postgres;

--
-- Name: associate_card_with_user(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text DEFAULT '0000'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  inserted_id UUID;
BEGIN
  -- Check if association already exists
  IF EXISTS (
    SELECT 1 FROM user_cards 
    WHERE user_id = _user_id AND card_id = _card_id
  ) THEN
    RETURN NULL; -- Already exists
  END IF;
  
  INSERT INTO user_cards (
    id, user_id, card_id, last_four_digits, 
    is_active, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), _user_id, _card_id, _last_four_digits, 
    true, NOW(), NOW()
  )
  RETURNING id INTO inserted_id;
  
  RETURN inserted_id;
END;
$$;


ALTER FUNCTION public.associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text) OWNER TO postgres;

--
-- Name: associate_user_with_card(uuid, uuid, text, text, text, text, numeric, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text DEFAULT NULL::text, _card_number text DEFAULT NULL::text, _expiry_date text DEFAULT NULL::text, _card_holder_name text DEFAULT NULL::text, _credit_limit numeric DEFAULT NULL::numeric, _statement_date integer DEFAULT NULL::integer, _due_date integer DEFAULT NULL::integer) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  user_card_id UUID;
BEGIN
  -- Check if association already exists
  SELECT id INTO user_card_id FROM user_cards 
  WHERE user_id = _user_id 
  AND catalog_card_id = _catalog_card_id
  AND (_last_four_digits IS NULL OR last_four_digits = _last_four_digits);
  
  -- If not found, create it
  IF user_card_id IS NULL THEN
    INSERT INTO user_cards (
      user_id, catalog_card_id, last_four_digits, card_number,
      expiry_date, card_holder_name, credit_limit, statement_date, due_date
    ) VALUES (
      _user_id, _catalog_card_id, _last_four_digits, _card_number,
      _expiry_date, _card_holder_name, _credit_limit, _statement_date, _due_date
    ) RETURNING id INTO user_card_id;
  END IF;
  
  RETURN user_card_id;
END;
$$;


ALTER FUNCTION public.associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _card_number text, _expiry_date text, _card_holder_name text, _credit_limit numeric, _statement_date integer, _due_date integer) OWNER TO postgres;

--
-- Name: create_credit_card(uuid, text, text, text, text, numeric, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric DEFAULT NULL::numeric, _is_active boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  inserted_id UUID;
BEGIN
  INSERT INTO credit_cards (
    id, card_name, bank_name, network, card_type, 
    annual_fee, is_active, created_at, updated_at
  ) VALUES (
    _card_id, _card_name, _bank_name, _network, _card_type, 
    _annual_fee, _is_active, NOW(), NOW()
  )
  RETURNING id INTO inserted_id;
  
  RETURN inserted_id;
END;
$$;


ALTER FUNCTION public.create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric, _is_active boolean) OWNER TO postgres;

--
-- Name: create_or_get_card_catalog(text, text, text, text, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text DEFAULT 'credit'::text, _joining_fee numeric DEFAULT NULL::numeric, _annual_fee numeric DEFAULT NULL::numeric, _apr numeric DEFAULT NULL::numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  card_id UUID;
BEGIN
  -- Try to find existing card
  SELECT id INTO card_id FROM card_catalog 
  WHERE bank = _bank AND card_name = _card_name AND network = _network;
  
  -- If not found, create it
  IF card_id IS NULL THEN
    INSERT INTO card_catalog (
      bank, card_name, network, card_type, joining_fee, annual_fee, apr
    ) VALUES (
      _bank, _card_name, _network, _card_type, _joining_fee, _annual_fee, _apr
    ) RETURNING id INTO card_id;
  END IF;
  
  RETURN card_id;
END;
$$;


ALTER FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric) OWNER TO postgres;

--
-- Name: get_card_catalog(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_card_catalog() RETURNS TABLE(id uuid, bank text, card_name text, network text, card_type text, joining_fee numeric, annual_fee numeric, apr numeric, is_discontinued boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cc.id,
        cc.bank,
        cc.card_name,
        cc.network,
        cc.card_type,
        cc.joining_fee,
        cc.annual_fee,
        cc.apr,
        cc.is_discontinued,
        cc.created_at,
        cc.updated_at
    FROM card_catalog cc
    WHERE cc.is_discontinued = false
    ORDER BY cc.bank, cc.card_name;
END;
$$;


ALTER FUNCTION public.get_card_catalog() OWNER TO postgres;

--
-- Name: get_user_cards(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_user_cards(_user_id uuid) RETURNS TABLE(id uuid, user_id uuid, catalog_card_id uuid, last_four_digits text, card_number text, expiry_date text, card_holder_name text, credit_limit numeric, statement_date integer, due_date integer, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone, bank text, card_name text, network text, card_type text, joining_fee numeric, annual_fee numeric, apr numeric, is_discontinued boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        uc.id,
        uc.user_id,
        uc.catalog_card_id,
        uc.last_four_digits,
        uc.card_number,
        uc.expiry_date,
        uc.card_holder_name,
        uc.credit_limit,
        uc.statement_date,
        uc.due_date,
        uc.is_active,
        uc.created_at,
        uc.updated_at,
        cc.bank,
        cc.card_name,
        cc.network,
        cc.card_type,
        cc.joining_fee,
        cc.annual_fee,
        cc.apr,
        cc.is_discontinued
    FROM user_cards uc
    JOIN card_catalog cc ON uc.catalog_card_id = cc.id
    WHERE uc.user_id = _user_id AND uc.is_active = true
    ORDER BY uc.created_at DESC;
END;
$$;


ALTER FUNCTION public.get_user_cards(_user_id uuid) OWNER TO postgres;

--
-- Name: get_user_transactions(uuid, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

-- NOTE: statement_id is TEXT here (not UUID) to match the real transactions.statement_id
-- column type (see initial_schema.sql). The original dump declared this column uuid in the
-- function signature while the table itself is text - a real bug that only surfaces at query
-- time ("structure of query does not match function result type... column 14").
CREATE FUNCTION public.get_user_transactions(_user_id uuid, _limit integer DEFAULT 50) RETURNS TABLE(id uuid, user_id uuid, user_card_id uuid, amount numeric, currency text, description text, merchant_name text, category text, transaction_type text, transaction_date timestamp with time zone, location text, reward_earned numeric, reward_type text, statement_id text, metadata jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, bank text, card_name text, last_four_digits text, network text, card_type text)
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
        t.statement_id,
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


ALTER FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) OWNER TO postgres;

--
-- Name: insert_transaction_with_card_id(uuid, uuid, uuid, numeric, text, timestamp with time zone, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text DEFAULT 'INR'::text, _category text DEFAULT 'other'::text, _transaction_type text DEFAULT 'debit'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    _result UUID;
BEGIN
    INSERT INTO transactions (
        id,
        user_id,
        card_id,
        amount,
        description,
        transaction_date,
        currency,
        category,
        transaction_type,
        created_at
    ) VALUES (
        _transaction_id,
        _user_id,
        _card_id,
        _amount,
        _description,
        _transaction_date,
        _currency,
        _category,
        _transaction_type,
        NOW()
    )
    RETURNING id INTO _result;
    
    RETURN _result;
END;
$$;


ALTER FUNCTION public.insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text, _category text, _transaction_type text) OWNER TO postgres;

--
-- Name: remove_user_card(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    cards_updated INTEGER;
BEGIN
    UPDATE user_cards 
    SET is_active = false, updated_at = NOW()
    WHERE user_id = _user_id AND catalog_card_id = _catalog_card_id AND is_active = true;
    
    GET DIAGNOSTICS cards_updated = ROW_COUNT;
    
    RETURN cards_updated > 0;
END;
$$;


ALTER FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) OWNER TO postgres;

--
-- Name: update_user_card(uuid, uuid, text, numeric, text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text DEFAULT NULL::text, _credit_limit numeric DEFAULT NULL::numeric, _card_holder_name text DEFAULT NULL::text, _expiry_date text DEFAULT NULL::text, _statement_date integer DEFAULT NULL::integer, _due_date integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    cards_updated INTEGER;
BEGIN
    UPDATE user_cards 
    SET 
        last_four_digits = COALESCE(_last_four_digits, last_four_digits),
        credit_limit = COALESCE(_credit_limit, credit_limit),
        card_holder_name = COALESCE(_card_holder_name, card_holder_name),
        expiry_date = COALESCE(_expiry_date, expiry_date),
        statement_date = COALESCE(_statement_date, statement_date),
        due_date = COALESCE(_due_date, due_date),
        updated_at = NOW()
    WHERE user_id = _user_id AND catalog_card_id = _catalog_card_id AND is_active = true;
    
    GET DIAGNOSTICS cards_updated = ROW_COUNT;
    
    RETURN cards_updated > 0;
END;
$$;


ALTER FUNCTION public.update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _credit_limit numeric, _card_holder_name text, _expiry_date text, _statement_date integer, _due_date integer) OWNER TO postgres;
-- Name: FUNCTION add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) TO anon;
GRANT ALL ON FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) TO authenticated;
GRANT ALL ON FUNCTION public.add_transaction(_user_id uuid, _user_card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _category text, _type text, _currency text, _merchant_name text, _location text) TO service_role;


--
-- Name: FUNCTION associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text) TO anon;
GRANT ALL ON FUNCTION public.associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text) TO authenticated;
GRANT ALL ON FUNCTION public.associate_card_with_user(_user_id uuid, _card_id uuid, _last_four_digits text) TO service_role;


--
-- Name: FUNCTION associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _card_number text, _expiry_date text, _card_holder_name text, _credit_limit numeric, _statement_date integer, _due_date integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _card_number text, _expiry_date text, _card_holder_name text, _credit_limit numeric, _statement_date integer, _due_date integer) TO anon;
GRANT ALL ON FUNCTION public.associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _card_number text, _expiry_date text, _card_holder_name text, _credit_limit numeric, _statement_date integer, _due_date integer) TO authenticated;
GRANT ALL ON FUNCTION public.associate_user_with_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _card_number text, _expiry_date text, _card_holder_name text, _credit_limit numeric, _statement_date integer, _due_date integer) TO service_role;


--
-- Name: FUNCTION create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric, _is_active boolean); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric, _is_active boolean) TO anon;
GRANT ALL ON FUNCTION public.create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric, _is_active boolean) TO authenticated;
GRANT ALL ON FUNCTION public.create_credit_card(_card_id uuid, _card_name text, _bank_name text, _network text, _card_type text, _annual_fee numeric, _is_active boolean) TO service_role;


--
-- Name: FUNCTION create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric) TO anon;
GRANT ALL ON FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric) TO authenticated;
GRANT ALL ON FUNCTION public.create_or_get_card_catalog(_bank text, _card_name text, _network text, _card_type text, _joining_fee numeric, _annual_fee numeric, _apr numeric) TO service_role;


--
-- Name: FUNCTION get_card_catalog(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_card_catalog() TO anon;
GRANT ALL ON FUNCTION public.get_card_catalog() TO authenticated;
GRANT ALL ON FUNCTION public.get_card_catalog() TO service_role;


--
-- Name: FUNCTION get_user_cards(_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_user_cards(_user_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_user_cards(_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_cards(_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_transactions(_user_id uuid, _limit integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) TO anon;
GRANT ALL ON FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_transactions(_user_id uuid, _limit integer) TO service_role;


--
-- Name: FUNCTION insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text, _category text, _transaction_type text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text, _category text, _transaction_type text) TO anon;
GRANT ALL ON FUNCTION public.insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text, _category text, _transaction_type text) TO authenticated;
GRANT ALL ON FUNCTION public.insert_transaction_with_card_id(_transaction_id uuid, _user_id uuid, _card_id uuid, _amount numeric, _description text, _transaction_date timestamp with time zone, _currency text, _category text, _transaction_type text) TO service_role;


--
-- Name: FUNCTION remove_user_card(_user_id uuid, _catalog_card_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) TO anon;
GRANT ALL ON FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_user_card(_user_id uuid, _catalog_card_id uuid) TO service_role;


--
-- Name: FUNCTION update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _credit_limit numeric, _card_holder_name text, _expiry_date text, _statement_date integer, _due_date integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _credit_limit numeric, _card_holder_name text, _expiry_date text, _statement_date integer, _due_date integer) TO anon;
GRANT ALL ON FUNCTION public.update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _credit_limit numeric, _card_holder_name text, _expiry_date text, _statement_date integer, _due_date integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_user_card(_user_id uuid, _catalog_card_id uuid, _last_four_digits text, _credit_limit numeric, _card_holder_name text, _expiry_date text, _statement_date integer, _due_date integer) TO service_role;
