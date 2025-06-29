-- Add reward balance tracking to CardCompass database
-- This enhances the existing reward tracking by adding dedicated balance storage per card

-- Create reward_balances table
CREATE TABLE IF NOT EXISTS reward_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('points', 'cashback', 'miles', 'vouchers')),
  available_balance DECIMAL(15,2) NOT NULL DEFAULT 0.0,
  total_earned DECIMAL(15,2) NOT NULL DEFAULT 0.0,
  total_redeemed DECIMAL(15,2) NOT NULL DEFAULT 0.0,
  pending_balance DECIMAL(15,2) NOT NULL DEFAULT 0.0,
  expiry_date DATE,
  metadata JSONB DEFAULT '{}',
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT unique_user_card_reward_type UNIQUE(user_card_id, reward_type)
);

-- Create reward_redemptions table
CREATE TABLE IF NOT EXISTS reward_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE,
  reward_balance_id UUID REFERENCES reward_balances(id) ON DELETE CASCADE,
  points_redeemed DECIMAL(15,2) NOT NULL,
  redemption_type TEXT NOT NULL CHECK (redemption_type IN ('statement_credit', 'voucher', 'cashback', 'transfer', 'gift_card')),
  redemption_value DECIMAL(12,2) NOT NULL,
  voucher_details TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  redemption_date TIMESTAMP WITH TIME ZONE NOT NULL,
  completed_date TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_reward_balances_user_id ON reward_balances(user_id);
CREATE INDEX IF NOT EXISTS idx_reward_balances_user_card_id ON reward_balances(user_card_id);
CREATE INDEX IF NOT EXISTS idx_reward_balances_expiry ON reward_balances(expiry_date) WHERE expiry_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reward_redemptions_user_id ON reward_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_reward_redemptions_status ON reward_redemptions(status);
CREATE INDEX IF NOT EXISTS idx_reward_redemptions_date ON reward_redemptions(redemption_date);

-- Add RLS policies for security
ALTER TABLE reward_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE reward_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own reward balances" ON reward_balances
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can manage their own reward redemptions" ON reward_redemptions
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Function to update reward balance when transaction rewards are added
CREATE OR REPLACE FUNCTION update_reward_balance(
  _user_id UUID,
  _user_card_id UUID,
  _reward_type TEXT,
  _reward_amount DECIMAL,
  _transaction_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  balance_id UUID;
  current_balance DECIMAL;
BEGIN
  -- Get or create reward balance record
  INSERT INTO reward_balances (user_id, user_card_id, reward_type, available_balance, total_earned)
  VALUES (_user_id, _user_card_id, _reward_type, _reward_amount, _reward_amount)
  ON CONFLICT (user_card_id, reward_type)
  DO UPDATE SET
    available_balance = reward_balances.available_balance + _reward_amount,
    total_earned = reward_balances.total_earned + _reward_amount,
    last_updated = NOW()
  RETURNING id INTO balance_id;
  
  RETURN balance_id;
END;
$$;

-- Function to redeem rewards
CREATE OR REPLACE FUNCTION redeem_rewards(
  _user_id UUID,
  _user_card_id UUID,
  _reward_balance_id UUID,
  _points_to_redeem DECIMAL,
  _redemption_type TEXT,
  _redemption_value DECIMAL,
  _voucher_details TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  redemption_id UUID;
  current_balance DECIMAL;
BEGIN
  -- Check if user has sufficient balance
  SELECT available_balance INTO current_balance
  FROM reward_balances
  WHERE id = _reward_balance_id AND user_id = _user_id;
  
  IF current_balance IS NULL THEN
    RAISE EXCEPTION 'Reward balance not found';
  END IF;
  
  IF current_balance < _points_to_redeem THEN
    RAISE EXCEPTION 'Insufficient reward balance. Available: %, Requested: %', current_balance, _points_to_redeem;
  END IF;
  
  -- Create redemption record
  INSERT INTO reward_redemptions (
    user_id, user_card_id, reward_balance_id, points_redeemed,
    redemption_type, redemption_value, voucher_details, redemption_date
  )
  VALUES (
    _user_id, _user_card_id, _reward_balance_id, _points_to_redeem,
    _redemption_type, _redemption_value, _voucher_details, NOW()
  )
  RETURNING id INTO redemption_id;
  
  -- Update reward balance
  UPDATE reward_balances
  SET 
    available_balance = available_balance - _points_to_redeem,
    total_redeemed = total_redeemed + _points_to_redeem,
    last_updated = NOW()
  WHERE id = _reward_balance_id;
  
  RETURN redemption_id;
END;
$$;

-- Function to get user's total reward balances
CREATE OR REPLACE FUNCTION get_user_reward_summary(_user_id UUID)
RETURNS TABLE (
  reward_type TEXT,
  total_balance DECIMAL,
  total_earned DECIMAL,
  total_redeemed DECIMAL,
  cards_count INTEGER,
  expiring_soon DECIMAL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    rb.reward_type,
    SUM(rb.available_balance + rb.pending_balance) as total_balance,
    SUM(rb.total_earned) as total_earned,
    SUM(rb.total_redeemed) as total_redeemed,
    COUNT(DISTINCT rb.user_card_id)::INTEGER as cards_count,
    SUM(
      CASE 
        WHEN rb.expiry_date IS NOT NULL 
        AND rb.expiry_date <= CURRENT_DATE + INTERVAL '30 days'
        AND rb.expiry_date > CURRENT_DATE
        THEN rb.available_balance
        ELSE 0
      END
    ) as expiring_soon
  FROM reward_balances rb
  WHERE rb.user_id = _user_id
  GROUP BY rb.reward_type
  ORDER BY total_balance DESC;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION update_reward_balance TO authenticated;
GRANT EXECUTE ON FUNCTION redeem_rewards TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_reward_summary TO authenticated;

-- Add comments for documentation
COMMENT ON TABLE reward_balances IS 'Stores accumulated reward balances per user card and reward type';
COMMENT ON TABLE reward_redemptions IS 'Tracks reward redemption history and status';
COMMENT ON FUNCTION update_reward_balance IS 'Updates reward balance when new rewards are earned from transactions';
COMMENT ON FUNCTION redeem_rewards IS 'Processes reward redemption and updates balances';
COMMENT ON FUNCTION get_user_reward_summary IS 'Returns summary of all reward balances for a user';

-- Success message
SELECT 'Reward balance tracking tables and functions created successfully! ✅' as result;
