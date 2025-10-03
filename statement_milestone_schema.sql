-- Create table for statement cycle milestone tracking
-- This replaces the weekly milestone tracking with statement cycle-based tracking

-- Note: The weekly_milestone_cache table has already been removed from Supabase

-- Create new statement milestone cache table
CREATE TABLE IF NOT EXISTS statement_milestone_cache (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE,
  benefit_category VARCHAR(50) NOT NULL,
  statement_start_date DATE NOT NULL,
  statement_end_date DATE NOT NULL,
  total_spending DECIMAL(12,2) DEFAULT 0,
  milestone_progress DECIMAL(5,2) DEFAULT 0, -- Percentage towards milestone
  last_updated TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, card_id, benefit_category, statement_start_date, statement_end_date)
);

-- Create index for fast milestone lookups
CREATE INDEX IF NOT EXISTS idx_statement_milestone_cache_lookup 
ON statement_milestone_cache(user_id, card_id, benefit_category, statement_start_date, statement_end_date);

-- Create index for user_card_id lookup (useful for linking to user_cards table)
CREATE INDEX IF NOT EXISTS idx_statement_milestone_user_card 
ON statement_milestone_cache(user_card_id);

-- Sample query to find the latest statement cycle for a card
COMMENT ON TABLE statement_milestone_cache IS 'Stores card spending data by statement cycle for benefit milestone tracking';

-- Note: Migration code has been removed as weekly_milestone_cache table no longer exists
-- The statement_milestone_cache table will be populated directly by the application

-- Add RLS policy
ALTER TABLE statement_milestone_cache ENABLE ROW LEVEL SECURITY;

-- Allow users to see only their own data
CREATE POLICY statement_milestone_user_policy ON statement_milestone_cache
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id);

-- Grant access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON statement_milestone_cache TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE statement_milestone_cache_id_seq TO authenticated;

-- Check if table was created successfully
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'statement_milestone_cache'
) AS table_exists;
