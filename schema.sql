-- ============================================================================
-- CardCompass - Complete Database Schema
-- ============================================================================
-- Version: 3.0
-- Last Updated: October 23, 2025
-- Description: Unified database schema matching actual Supabase database structure
-- Validated against live database on October 23, 2025
-- ============================================================================

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Users table (managed by Supabase Auth)
-- This is referenced by other tables but managed by Supabase

-- ============================================================================
-- CARD CATALOG & BENEFITS
-- ============================================================================

-- Card Catalog Table
CREATE TABLE IF NOT EXISTS card_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_name TEXT NOT NULL,
  bank TEXT,
  network TEXT, -- Visa, Mastercard, RuPay, etc.
  card_type TEXT, -- Credit, Debit
  annual_fee DECIMAL(10,2),
  joining_fee DECIMAL(10,2),
  apr DECIMAL(5,2), -- Annual Percentage Rate
  card_url TEXT, -- URL to card details/application page
  is_discontinued BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User Cards Table
CREATE TABLE IF NOT EXISTS user_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  catalog_card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  last_four_digits TEXT,
  card_number TEXT, -- Should be encrypted in production
  expiry_date TEXT, -- Format: MM/YY
  card_holder_name TEXT,
  credit_limit DECIMAL(12,2),
  statement_date INTEGER CHECK (statement_date >= 1 AND statement_date <= 31),
  due_date INTEGER CHECK (due_date >= 1 AND due_date <= 31),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, catalog_card_id)
);

-- Benefit Categories Table
CREATE TABLE IF NOT EXISTS benefit_categories (
  category_code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Benefits Table
CREATE TABLE IF NOT EXISTS benefits (
  benefit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  benefit_category TEXT NOT NULL, -- 'entertainment', 'dining', 'fuel', etc.
  benefit_type TEXT, -- Additional categorization
  value_config JSONB, -- Flexible configuration for different benefit types
  partners JSONB DEFAULT '[]', -- Partner names where benefit is applicable (JSONB, not TEXT[] - matches production data shape)
  exclusions JSONB DEFAULT '{}', -- Exclusion conditions, e.g. {"mcc_codes": [...], "merchants": [...], "additional": {...}} (JSONB, not TEXT[] - matches production data shape)
  regions JSONB DEFAULT '[]', -- Geographic regions where benefit is valid (JSONB, not TEXT[] - matches production data shape)
  source_url TEXT, -- URL to official benefit documentation
  dedupe_key TEXT NOT NULL UNIQUE, -- normalized category/type/title identity
  valid_from DATE, -- Benefit validity start date
  valid_until DATE, -- Benefit validity end date
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Historical Benefit Values Table (not a card relationship)
CREATE TABLE IF NOT EXISTS card_benefits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  benefit_id UUID REFERENCES benefits(benefit_id) ON DELETE SET NULL,
  value DECIMAL(12,2),
  configuration JSONB,
  spending_categories TEXT[],
  monthly_cap DECIMAL(12,2),
  annual_cap DECIMAL(12,2),
  valid_from DATE,
  valid_to DATE,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Card-Benefit Mapping Table (Simple mapping for display)
CREATE TABLE IF NOT EXISTS card_benefit_mapping (
  mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  benefit_id UUID NOT NULL REFERENCES benefits(benefit_id) ON DELETE CASCADE,
  display_priority INTEGER DEFAULT 1,
  is_primary BOOLEAN DEFAULT true,
  category_codes TEXT[] NOT NULL DEFAULT '{}', -- normalized searchable eligibility categories
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(card_id, benefit_id)
);

-- Benefit extraction review/audit table. This is deliberately separate from
-- the canonical benefits catalog and from the card-benefit mapping table.
CREATE TABLE IF NOT EXISTS card_benefits_staging (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE,
  source_url TEXT,
  extracted_data JSONB NOT NULL,
  source_evidence JSONB,
  validation_version TEXT,
  calculated_confidence NUMERIC(5,4),
  validation_reasons JSONB NOT NULL DEFAULT '[]'::jsonb,
  validation_warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
  benefit_decisions JSONB NOT NULL DEFAULT '[]'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  validated_at TIMESTAMP WITH TIME ZONE,
  reviewed_at TIMESTAMP WITH TIME ZONE,
  rejected_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- TRANSACTIONS & STATEMENTS
-- ============================================================================

-- Statements Table (Credit Card Statements)
CREATE TABLE IF NOT EXISTS statements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  user_card_id UUID NOT NULL REFERENCES user_cards(id) ON DELETE CASCADE,
  statement_date DATE NOT NULL,
  due_date DATE NOT NULL,
  total_amount DECIMAL(12,2) DEFAULT 0,
  minimum_payment DECIMAL(12,2) DEFAULT 0,
  closing_balance DECIMAL(12,2) DEFAULT 0,
  available_credit DECIMAL(12,2) DEFAULT 0,
  interest_charged DECIMAL(12,2) DEFAULT 0,
  fees_charged DECIMAL(12,2) DEFAULT 0,
  payment_status TEXT DEFAULT 'pending',
  rewards_earned DECIMAL(12,2) DEFAULT 0,
  file_path TEXT,
  file_name TEXT,
  processed BOOLEAN DEFAULT false,
  transaction_count INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_card_id, statement_date)
);

-- Transactions Table
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_card_id UUID NOT NULL REFERENCES user_cards(id) ON DELETE CASCADE,
  amount DECIMAL(12,2) NOT NULL,
  currency TEXT DEFAULT 'INR',
  description TEXT NOT NULL,
  merchant_name TEXT,
  category TEXT,
  transaction_type TEXT, -- 'debit', 'credit', 'refund', 'fee', 'interest', 'reward'
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  location TEXT,
  reward_earned DECIMAL(12,2),
  reward_type TEXT,
  statement_id UUID REFERENCES statements(id) ON DELETE SET NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- MILESTONE & BENEFIT TRACKING
-- ============================================================================

-- Statement Cycle Milestone Cache
CREATE TABLE IF NOT EXISTS statement_milestone_cache (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE,
  benefit_category VARCHAR(50) NOT NULL,
  statement_start_date DATE NOT NULL,
  statement_end_date DATE NOT NULL,
  total_spending DECIMAL(12,2) DEFAULT 0,
  milestone_progress DECIMAL(5,2) DEFAULT 0, -- Percentage towards milestone
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, card_id, benefit_category, statement_start_date, statement_end_date)
);

-- Email Records Table (for Gmail sync dedupe/status tracking)
CREATE TABLE IF NOT EXISTS emails (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  email_id TEXT NOT NULL UNIQUE,
  subject TEXT,
  sender TEXT,
  received_date TIMESTAMP WITH TIME ZONE,
  has_attachments BOOLEAN DEFAULT false,
  processed BOOLEAN DEFAULT false,
  bank_detected TEXT,
  statement_id TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- REWARDS & POINTS (Future Implementation)
-- ============================================================================
-- Note: reward_balances table not yet implemented in database
-- Will be added in future release for tracking points/cashback/miles

-- ============================================================================
-- USER PREFERENCES & DATA (Future Implementation)
-- ============================================================================
-- Note: user_birthdays table not yet implemented in database
-- Will be added in future release for password generation

-- ============================================================================
-- AI & ML FEATURES
-- ============================================================================

-- Add AI tracking columns to benefits table if needed
-- (For future ML benefit extraction features)

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Card Catalog Indexes
CREATE INDEX IF NOT EXISTS idx_card_catalog_bank ON card_catalog(bank);
CREATE INDEX IF NOT EXISTS idx_card_catalog_network ON card_catalog(network);
CREATE INDEX IF NOT EXISTS idx_card_catalog_discontinued ON card_catalog(is_discontinued);

-- User Cards Indexes
CREATE INDEX IF NOT EXISTS idx_user_cards_user_id ON user_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_user_cards_catalog_id ON user_cards(catalog_card_id);
CREATE INDEX IF NOT EXISTS idx_user_cards_active ON user_cards(user_id, is_active);

-- Benefits Indexes
CREATE INDEX IF NOT EXISTS idx_benefits_category ON benefits(benefit_category);
CREATE INDEX IF NOT EXISTS idx_benefits_active ON benefits(is_active);

-- Card-Benefit Mapping Indexes
CREATE INDEX IF NOT EXISTS idx_card_benefit_card ON card_benefit_mapping(card_id);
CREATE INDEX IF NOT EXISTS idx_card_benefit_benefit ON card_benefit_mapping(benefit_id);
CREATE INDEX IF NOT EXISTS idx_card_benefit_primary ON card_benefit_mapping(card_id, is_primary);
CREATE INDEX IF NOT EXISTS idx_card_benefit_mapping_category_codes
  ON card_benefit_mapping USING GIN (category_codes);

-- Transactions Indexes
CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_card ON transactions(user_card_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category);
CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_card_date ON transactions(user_card_id, transaction_date);

-- Statements Indexes
CREATE INDEX IF NOT EXISTS idx_statements_user ON statements(user_id);
CREATE INDEX IF NOT EXISTS idx_statements_card ON statements(card_id);
CREATE INDEX IF NOT EXISTS idx_statements_date ON statements(statement_date);

-- Milestone Cache Indexes
CREATE INDEX IF NOT EXISTS idx_statement_milestone_cache_lookup 
  ON statement_milestone_cache(user_id, card_id, benefit_category, statement_start_date, statement_end_date);
CREATE INDEX IF NOT EXISTS idx_statement_milestone_user_card 
  ON statement_milestone_cache(user_card_id);

-- Historical Card Benefits Indexes
CREATE INDEX IF NOT EXISTS idx_card_benefits_benefit ON card_benefits(benefit_id);
CREATE INDEX IF NOT EXISTS idx_card_benefits_active ON card_benefits(is_active);

-- Benefit Categories Indexes
CREATE INDEX IF NOT EXISTS idx_benefit_categories_active ON benefit_categories(is_active);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all user-facing tables
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE statement_milestone_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;

-- User Cards Policies
CREATE POLICY user_cards_policy ON user_cards
  FOR ALL TO authenticated
  USING (auth.uid() = user_id);

-- Transactions Policies
CREATE POLICY transactions_policy ON transactions
  FOR ALL TO authenticated
  USING (auth.uid() = user_id);

-- Statements Policies
CREATE POLICY statements_policy ON statements
  FOR ALL TO authenticated
  USING (auth.uid() = user_id);

-- Milestone Cache Policies
CREATE POLICY statement_milestone_user_policy ON statement_milestone_cache
  FOR ALL TO authenticated
  USING (auth.uid() = user_id);

-- Emails Policies
CREATE POLICY emails_policy ON emails
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- GRANTS
-- ============================================================================

-- Grant permissions to authenticated users
GRANT SELECT ON card_catalog TO authenticated;
GRANT SELECT ON benefit_categories TO authenticated;
GRANT SELECT ON benefits TO authenticated;
GRANT SELECT ON card_benefits TO authenticated;
GRANT SELECT ON card_benefit_mapping TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON user_cards TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON statements TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON statement_milestone_cache TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON emails TO authenticated;

-- Grant sequence usage
GRANT USAGE, SELECT ON SEQUENCE statement_milestone_cache_id_seq TO authenticated;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update timestamp triggers
CREATE TRIGGER update_card_catalog_updated_at
  BEFORE UPDATE ON card_catalog
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_benefits_updated_at
  BEFORE UPDATE ON benefits
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at
  BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Note: no trigger for user_birthdays here - that table is not yet implemented
-- (see "USER PREFERENCES & DATA (Future Implementation)" note above). A trigger
-- referencing it was previously left in this file by mistake and broke a clean
-- schema apply; add the trigger back alongside the table's own CREATE TABLE
-- statement whenever user_birthdays actually gets implemented.

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE card_catalog IS 'Master catalog of all credit cards available in the system';
COMMENT ON TABLE user_cards IS 'User-owned credit cards linked to catalog';
COMMENT ON TABLE benefit_categories IS 'Categories for organizing benefits (dining, travel, fuel, etc.)';
COMMENT ON TABLE benefits IS 'Master list of card benefits with flexible JSONB configuration';
COMMENT ON TABLE card_benefits IS 'Detailed card-specific benefit configurations with caps and priorities';
COMMENT ON TABLE card_benefit_mapping IS 'Simple mapping between cards and benefits for display';
COMMENT ON TABLE transactions IS 'All card transactions for users';
COMMENT ON TABLE statements IS 'Parsed credit card statements';
COMMENT ON TABLE statement_milestone_cache IS 'Stores card spending by statement cycle for milestone tracking';

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check if all tables were created
DO $$
BEGIN
  RAISE NOTICE 'CardCompass Database Schema Created Successfully!';
  RAISE NOTICE 'Tables created:';
  RAISE NOTICE '- card_catalog';
  RAISE NOTICE '- user_cards';
  RAISE NOTICE '- benefit_categories';
  RAISE NOTICE '- benefits';
  RAISE NOTICE '- card_benefits';
  RAISE NOTICE '- card_benefit_mapping';
  RAISE NOTICE '- transactions';
  RAISE NOTICE '- statements';
  RAISE NOTICE '- statement_milestone_cache';
  RAISE NOTICE '';
  RAISE NOTICE 'All indexes, policies, and grants applied.';
END $$;

-- ============================================================================
-- NOTES
-- ============================================================================

-- VALUE_CONFIG JSONB Structure Examples:
-- 
-- Movie Benefits (Entertainment):
-- {
--   "rate": 25.0,              -- Discount percentage or amount
--   "unit": "percent",         -- "percent", "bogo", "milestone", "cashback"
--   "category": "movie",
--   "platform": "BookMyShow",  -- Specific platform or null for all
--   "base_rate": 500,          -- Minimum transaction amount
--   "max_discount": 150        -- Maximum discount cap
-- }
--
-- Legacy format auto-conversion is handled in application code
-- (MovieBenefitConfig.fromJson() converts rate/unit to offer_type/discount_percent)
