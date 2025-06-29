-- CardCompass - Complete Database Setup and Maintenance
-- Generated on: Mon, Jun 23, 2025 12:23:39 AM
-- This file contains all database schemas, functions, and maintenance scripts

-- ========================================
-- FROM FILE: add_ai_benefit_columns.sql
-- ========================================

-- CardCompass ML Benefit Extraction - Database Enhancement
-- Add AI tracking columns to existing card_benefits table

-- Add AI tracking columns to card_benefits table
ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS
  ai_extracted BOOLEAN DEFAULT FALSE;

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS
  extraction_confidence DECIMAL(3,2) DEFAULT 0.0;

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS
  last_scraped_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS
  source_url TEXT;

-- Create index for AI-extracted benefits
CREATE INDEX IF NOT EXISTS idx_card_benefits_ai_extracted 
  ON card_benefits(ai_extracted, last_scraped_at);

-- Create index for confidence scoring
CREATE INDEX IF NOT EXISTS idx_card_benefits_confidence 
  ON card_benefits(extraction_confidence) WHERE ai_extracted = TRUE;

-- Print completion message
DO $$
BEGIN
  RAISE NOTICE 'AI tracking columns added to card_benefits table:';
  RAISE NOTICE '- ai_extracted (BOOLEAN): Tracks if benefit was extracted by AI';
  RAISE NOTICE '- extraction_confidence (DECIMAL): AI confidence score (0.0-1.0)';
  RAISE NOTICE '- last_scraped_at (TIMESTAMP): When benefit was last scraped';
  RAISE NOTICE '- source_url (TEXT): URL where benefit information was found';
  RAISE NOTICE 'Indexes created for performance optimization';
END $$;


-- ========================================
-- FROM FILE: add_user_birthday_storage.sql
-- ========================================

-- Add user birthday storage to handle cases where Google API doesn't provide birthday data
-- This ensures password detection can still work even when Google profile lacks birthday info

-- Add birthday column to user_profiles table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'birthday'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN birthday DATE;
        
        -- Add comment explaining the purpose
        COMMENT ON COLUMN user_profiles.birthday IS 'User birthday for PDF password detection - fallback when Google API unavailable';
        
        PRINT 'Added birthday column to user_profiles table';
    ELSE
        PRINT 'Birthday column already exists in user_profiles table';
    END IF;
END $$;

-- Create index for faster birthday lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_birthday ON user_profiles(birthday) WHERE birthday IS NOT NULL;

-- Add metadata column to track birthday source
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'birthday_source'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN birthday_source VARCHAR(20) DEFAULT 'manual';
        
        -- Add comment explaining possible values
        COMMENT ON COLUMN user_profiles.birthday_source IS 'Source of birthday data: google_api, manual, or imported';
        
        PRINT 'Added birthday_source column to user_profiles table';
    ELSE
        PRINT 'Birthday_source column already exists in user_profiles table';
    END IF;
END $$;

-- Create a function to safely update user birthday
CREATE OR REPLACE FUNCTION update_user_birthday(
    p_user_id TEXT,
    p_birthday DATE,
    p_source VARCHAR(20) DEFAULT 'manual'
) RETURNS BOOLEAN AS $$
BEGIN
    -- Update or insert user birthday
    INSERT INTO user_profiles (user_id, birthday, birthday_source, updated_at)
    VALUES (p_user_id, p_birthday, p_source, NOW())
    ON CONFLICT (user_id) 
    DO UPDATE SET 
        birthday = EXCLUDED.birthday,
        birthday_source = EXCLUDED.birthday_source,
        updated_at = NOW()
    WHERE user_profiles.birthday IS NULL OR user_profiles.birthday_source = 'manual';
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION update_user_birthday(TEXT, DATE, VARCHAR) TO authenticated;

COMMENT ON FUNCTION update_user_birthday IS 'Safely update user birthday with source tracking';


-- ========================================
-- FROM FILE: final_function_fix.sql
-- ========================================

-- Final fix for add_transaction function to match our Dart code exactly
-- This will completely refresh the function and cache

-- Step 1: Drop ALL existing add_transaction functions
DROP FUNCTION IF EXISTS add_transaction CASCADE;

-- Step 2: Clear any cached function definitions
NOTIFY pgrst, 'reload schema';

-- Step 3: Create the function with exact parameter signature matching our Dart code
CREATE OR REPLACE FUNCTION add_transaction(
    _user_id UUID,
    _user_card_id UUID,
    _amount DECIMAL,
    _description TEXT,
    _transaction_date TIMESTAMPTZ,
    _category TEXT,
    _type TEXT,
    _currency TEXT DEFAULT 'INR',
    _merchant_name TEXT DEFAULT NULL,
    _location TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Step 4: Grant proper permissions
GRANT EXECUTE ON FUNCTION add_transaction TO authenticated;
GRANT EXECUTE ON FUNCTION add_transaction TO anon;

-- Step 5: Force schema cache refresh
NOTIFY pgrst, 'reload schema';

-- Step 6: Test the function with a sample call (this will fail but validates signature)
-- SELECT add_transaction(
--     'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID,  -- _user_id
--     'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID,  -- _user_card_id  
--     100.00,                                         -- _amount
--     'Test transaction',                             -- _description
--     NOW(),                                          -- _transaction_date
--     'test',                                         -- _category
--     'debit',                                        -- _type
--     'INR',                                          -- _currency
--     'Test Merchant',                                -- _merchant_name
--     'Test Location'                                 -- _location
-- );

-- Step 7: Verify function exists with correct signature
SELECT 
    r.routine_name, 
    r.data_type,
    string_agg(
        COALESCE(p.parameter_name, 'RETURN') || ':' || 
        COALESCE(p.data_type, r.data_type), 
        ', ' ORDER BY p.ordinal_position
    ) as function_signature
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE r.routine_name = 'add_transaction'
  AND r.routine_schema = 'public'
GROUP BY r.routine_name, r.data_type;


-- ========================================
-- FROM FILE: fix_add_transaction_function.sql
-- ========================================

-- Fix add_transaction function signature
-- Run this in Supabase Dashboard > SQL Editor to fix the function mismatch

-- First, let's see what functions exist
SELECT 
    routine_name, 
    routine_definition,
    data_type
FROM information_schema.routines 
WHERE routine_name = 'add_transaction';

-- Drop ALL existing versions of add_transaction function
DROP FUNCTION IF EXISTS add_transaction CASCADE;

-- Check if function still exists (should be empty result)
SELECT routine_name FROM information_schema.routines WHERE routine_name = 'add_transaction';

-- Recreate the function with the correct signature that matches our Dart code
CREATE OR REPLACE FUNCTION add_transaction(
    _user_id UUID,
    _user_card_id UUID,
    _amount DECIMAL,
    _description TEXT,
    _transaction_date TIMESTAMPTZ,
    _category TEXT,
    _type TEXT,
    _currency TEXT DEFAULT 'INR',
    _merchant_name TEXT DEFAULT NULL,
    _location TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_id UUID;
BEGIN
    -- Debug: Log the parameters being passed
    RAISE LOG 'add_transaction called with: user_id=%, user_card_id=%, amount=%, category=%, type=%', 
        _user_id, _user_card_id, _amount, _category, _type;
        
    INSERT INTO transactions (
        user_id, user_card_id, amount, description,
        transaction_date, category, transaction_type,
        currency, merchant_name, location
    ) VALUES (
        _user_id, _user_card_id, _amount, _description,
        _transaction_date, _category, _type,
        _currency, _merchant_name, _location
    ) RETURNING id INTO transaction_id;
    
    RAISE LOG 'Transaction created with id: %', transaction_id;
    
    RETURN transaction_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION add_transaction TO authenticated;
GRANT EXECUTE ON FUNCTION add_transaction TO anon;

-- Verify the function was created correctly
SELECT 
    routine_name, 
    data_type,
    routine_definition
FROM information_schema.routines 
WHERE routine_name = 'add_transaction';


-- ========================================
-- FROM FILE: fix_card_catalog_rls.sql
-- ========================================

-- Fix Row-Level Security for card_catalog table
-- Run this in Supabase SQL Editor

-- Option 1: Create policies to allow service role to insert/update/delete
-- This is the recommended approach for production

-- Allow service role to insert cards
CREATE POLICY "Allow service role to insert cards" ON card_catalog
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

-- Allow service role to update cards  
CREATE POLICY "Allow service role to update cards" ON card_catalog
  FOR UPDATE 
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Allow service role to delete cards
CREATE POLICY "Allow service role to delete cards" ON card_catalog
  FOR DELETE 
  TO service_role
  USING (true);

-- Allow authenticated users to read cards (if not already allowed)
CREATE POLICY "Allow authenticated users to read cards" ON card_catalog
  FOR SELECT 
  TO authenticated
  USING (true);

-- Option 2: If you want to temporarily disable RLS for testing
-- (Uncomment the line below ONLY for testing, then re-enable RLS)
-- ALTER TABLE card_catalog DISABLE ROW LEVEL SECURITY;

-- To re-enable RLS later (if you disabled it):
-- ALTER TABLE card_catalog ENABLE ROW LEVEL SECURITY;

-- Check current RLS status and policies
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename = 'card_catalog';

-- List current policies
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'card_catalog';


-- ========================================
-- FROM FILE: fix_function_parameter_order.sql
-- ========================================

-- Fix add_transaction function parameter order to match what our Dart code expects
-- Run this in Supabase Dashboard > SQL Editor

-- Drop the existing function
DROP FUNCTION IF EXISTS add_transaction CASCADE;

-- Recreate with the exact parameter order that our Dart code is sending
-- All parameters after the first default must have defaults
CREATE OR REPLACE FUNCTION add_transaction(
    _user_id UUID,
    _user_card_id UUID,
    _amount DECIMAL,
    _description TEXT,
    _transaction_date TIMESTAMPTZ,
    _category TEXT,
    _type TEXT,
    _currency TEXT DEFAULT 'INR',
    _merchant_name TEXT DEFAULT NULL,
    _location TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_id UUID;
BEGIN
    -- Debug: Log the parameters being passed
    RAISE LOG 'add_transaction called with: user_id=%, user_card_id=%, amount=%, category=%, type=%', 
        _user_id, _user_card_id, _amount, _category, _type;
        
    INSERT INTO transactions (
        user_id, user_card_id, amount, description,
        transaction_date, category, transaction_type,
        currency, merchant_name, location
    ) VALUES (
        _user_id, _user_card_id, _amount, _description,
        _transaction_date, _category, _type,
        _currency, _merchant_name, _location
    ) RETURNING id INTO transaction_id;
    
    RAISE LOG 'Transaction created with id: %', transaction_id;
    
    RETURN transaction_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION add_transaction TO authenticated;
GRANT EXECUTE ON FUNCTION add_transaction TO anon;

-- Verify the function was created correctly
SELECT 
    r.routine_name, 
    r.data_type,
    array_agg(p.parameter_name ORDER BY p.ordinal_position) as parameters
FROM information_schema.routines r
LEFT JOIN information_schema.parameters p ON r.specific_name = p.specific_name
WHERE r.routine_name = 'add_transaction'
GROUP BY r.routine_name, r.data_type;


-- ========================================
-- FROM FILE: fix_rls_comprehensive.sql
-- ========================================

-- Comprehensive RLS Fix for card_catalog table
-- Run this in Supabase SQL Editor

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow service role to insert cards" ON card_catalog;
DROP POLICY IF EXISTS "Allow service role to update cards" ON card_catalog;
DROP POLICY IF EXISTS "Allow service role to delete cards" ON card_catalog;
DROP POLICY IF EXISTS "Allow authenticated users to read cards" ON card_catalog;

-- Option 1: Create policies for multiple roles (recommended)
-- Allow anon role (which Flutter uses by default) to insert/update/delete
CREATE POLICY "Allow anon role to insert cards" ON card_catalog
  FOR INSERT 
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow anon role to update cards" ON card_catalog
  FOR UPDATE 
  TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow anon role to delete cards" ON card_catalog
  FOR DELETE 
  TO anon
  USING (true);

-- Allow service role to insert/update/delete
CREATE POLICY "Allow service role to insert cards" ON card_catalog
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

CREATE POLICY "Allow service role to update cards" ON card_catalog
  FOR UPDATE 
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow service role to delete cards" ON card_catalog
  FOR DELETE 
  TO service_role
  USING (true);

-- Allow authenticated users to insert/update/delete
CREATE POLICY "Allow authenticated users to insert cards" ON card_catalog
  FOR INSERT 
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Allow authenticated users to update cards" ON card_catalog
  FOR UPDATE 
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow authenticated users to delete cards" ON card_catalog
  FOR DELETE 
  TO authenticated
  USING (true);

-- Allow all roles to read cards
CREATE POLICY "Allow all to read cards" ON card_catalog
  FOR SELECT 
  TO anon, authenticated, service_role
  USING (true);

-- Show current policies to verify
SELECT 
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'card_catalog';

-- Also fix the same issue for benefit-related tables
-- Allow access to benefit_categories
DROP POLICY IF EXISTS "Allow all to read benefit_categories" ON benefit_categories;
DROP POLICY IF EXISTS "Allow anon to insert benefit_categories" ON benefit_categories;
DROP POLICY IF EXISTS "Allow service role to insert benefit_categories" ON benefit_categories;
DROP POLICY IF EXISTS "Allow authenticated to insert benefit_categories" ON benefit_categories;

CREATE POLICY "Allow all to read benefit_categories" ON benefit_categories
  FOR SELECT 
  TO anon, authenticated, service_role
  USING (true);

CREATE POLICY "Allow anon to insert benefit_categories" ON benefit_categories
  FOR INSERT 
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow service role to insert benefit_categories" ON benefit_categories
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

CREATE POLICY "Allow authenticated to insert benefit_categories" ON benefit_categories
  FOR INSERT 
  TO authenticated
  WITH CHECK (true);

-- Allow access to benefits table
DROP POLICY IF EXISTS "Allow all to read benefits" ON benefits;
DROP POLICY IF EXISTS "Allow anon to insert benefits" ON benefits;
DROP POLICY IF EXISTS "Allow service role to insert benefits" ON benefits;
DROP POLICY IF EXISTS "Allow authenticated to insert benefits" ON benefits;

CREATE POLICY "Allow all to read benefits" ON benefits
  FOR SELECT 
  TO anon, authenticated, service_role
  USING (true);

CREATE POLICY "Allow anon to insert benefits" ON benefits
  FOR INSERT 
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow service role to insert benefits" ON benefits
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

CREATE POLICY "Allow authenticated to insert benefits" ON benefits
  FOR INSERT 
  TO authenticated
  WITH CHECK (true);

-- Allow access to card_benefits table
DROP POLICY IF EXISTS "Allow all to read card_benefits" ON card_benefits;
DROP POLICY IF EXISTS "Allow anon to insert card_benefits" ON card_benefits;
DROP POLICY IF EXISTS "Allow service role to insert card_benefits" ON card_benefits;
DROP POLICY IF EXISTS "Allow authenticated to insert card_benefits" ON card_benefits;

CREATE POLICY "Allow all to read card_benefits" ON card_benefits
  FOR SELECT 
  TO anon, authenticated, service_role
  USING (true);

CREATE POLICY "Allow anon to insert card_benefits" ON card_benefits
  FOR INSERT 
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow service role to insert card_benefits" ON card_benefits
  FOR INSERT 
  TO service_role
  WITH CHECK (true);

CREATE POLICY "Allow authenticated to insert card_benefits" ON card_benefits
  FOR INSERT 
  TO authenticated
  WITH CHECK (true);

-- Check RLS status for all tables
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE tablename IN ('card_catalog', 'benefit_categories', 'benefits', 'card_benefits')
ORDER BY tablename;


-- ========================================
-- FROM FILE: setup_benefit_tables.sql
-- ========================================

-- CardCompass Database Setup Script - Benefit Tables
-- This script creates the required tables for the benefit import system

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist to ensure clean setup
DROP TABLE IF EXISTS benefit_configurations CASCADE;
DROP TABLE IF EXISTS benefit_tiers CASCADE;
DROP TABLE IF EXISTS card_benefits CASCADE;
DROP TABLE IF EXISTS benefits CASCADE;
DROP TABLE IF EXISTS benefit_categories CASCADE;

-- Create benefit_categories table
CREATE TABLE benefit_categories (
  category_code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default benefit categories
INSERT INTO benefit_categories (category_code, name, description) VALUES
  ('CASHBACK', 'Cashback Rewards', 'Percentage-based cashback on spending'),
  ('POINTS', 'Reward Points', 'Points-based reward system'),
  ('MILES', 'Air Miles', 'Airline miles and travel rewards'),
  ('FUEL', 'Fuel Benefits', 'Benefits on fuel purchases'),
  ('DINING', 'Dining Benefits', 'Rewards on dining and restaurants'),
  ('TRAVEL', 'Travel Benefits', 'Travel-related perks and benefits'),
  ('SHOPPING', 'Shopping Benefits', 'Benefits on online and offline shopping'),
  ('ENTERTAINMENT', 'Entertainment Benefits', 'Benefits on movies, streaming, etc.'),
  ('UTILITY', 'Utility Benefits', 'Benefits on utility bill payments'),
  ('INSURANCE', 'Insurance Benefits', 'Insurance coverage and benefits'),
  ('LOUNGE', 'Airport Lounge Access', 'Airport lounge access benefits'),
  ('CONCIERGE', 'Concierge Services', 'Personal concierge services'),
  ('GOLF', 'Golf Benefits', 'Golf course access and benefits'),
  ('OTHER', 'Other Benefits', 'Miscellaneous benefits');

-- Create benefits table with proper foreign key
CREATE TABLE benefits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category_code TEXT NOT NULL REFERENCES benefit_categories(category_code),
  name TEXT NOT NULL,
  description TEXT,
  calculation_method TEXT NOT NULL CHECK (calculation_method IN ('percentage', 'fixed', 'points', 'boolean')),
  default_value DECIMAL(10, 2),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default benefits
INSERT INTO benefits (category_code, name, description, calculation_method, default_value) VALUES
  ('CASHBACK', 'General Cashback', 'General cashback on all purchases', 'percentage', 1.0),
  ('CASHBACK', 'Fuel Cashback', 'Cashback on fuel purchases', 'percentage', 5.0),
  ('CASHBACK', 'Dining Cashback', 'Cashback on dining', 'percentage', 5.0),
  ('CASHBACK', 'Online Shopping Cashback', 'Cashback on online shopping', 'percentage', 2.0),
  ('POINTS', 'Reward Points', 'Standard reward points', 'points', 1.0),
  ('POINTS', 'Accelerated Points', 'Accelerated reward points', 'points', 2.0),
  ('MILES', 'Air Miles', 'Airline miles accumulation', 'points', 1.0),
  ('FUEL', 'Fuel Surcharge Waiver', 'Waiver on fuel surcharges', 'percentage', 1.0),
  ('DINING', 'Restaurant Discounts', 'Discounts at partner restaurants', 'percentage', 10.0),
  ('TRAVEL', 'Travel Insurance', 'Complimentary travel insurance', 'boolean', 1.0),
  ('SHOPPING', 'Shopping Rewards', 'Rewards on shopping', 'percentage', 2.0),
  ('ENTERTAINMENT', 'Movie Tickets', 'Discounts on movie tickets', 'percentage', 25.0),
  ('UTILITY', 'Utility Bill Rewards', 'Rewards on utility bill payments', 'percentage', 1.0),
  ('INSURANCE', 'Purchase Protection', 'Purchase protection insurance', 'boolean', 1.0),
  ('LOUNGE', 'Airport Lounge Access', 'Complimentary airport lounge access', 'boolean', 1.0),
  ('CONCIERGE', 'Concierge Service', '24/7 concierge service', 'boolean', 1.0),
  ('GOLF', 'Golf Course Access', 'Access to partner golf courses', 'boolean', 1.0);

-- Check if credit_cards table exists, if not create a minimal version
CREATE TABLE IF NOT EXISTS credit_cards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bank_name TEXT,
  card_name TEXT NOT NULL,
  card_type TEXT DEFAULT 'standard',
  network TEXT DEFAULT 'VISA',
  annual_fee DECIMAL(10, 2) DEFAULT 0,
  credit_limit DECIMAL(10, 2),
  min_income DECIMAL(10, 2),
  min_credit_score INTEGER,
  interest_rate DECIMAL(5, 2),
  features JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Check if card_catalog table exists, if not create it
CREATE TABLE IF NOT EXISTS card_catalog (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bank TEXT NOT NULL,
  card_name TEXT NOT NULL,
  card_type TEXT DEFAULT 'standard',
  network TEXT DEFAULT 'VISA',
  annual_fee DECIMAL(10, 2) DEFAULT 0,
  features JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert some sample cards into card_catalog for testing
INSERT INTO card_catalog (bank, card_name, card_type, network, annual_fee)
VALUES 
  ('HDFC Bank', 'Regalia Credit Card', 'premium', 'VISA', 2500),
  ('ICICI Bank', 'Amazon Pay Credit Card', 'standard', 'VISA', 0),
  ('SBI Card', 'SimplyCLICK Credit Card', 'standard', 'VISA', 499),
  ('Axis Bank', 'Flipkart Credit Card', 'standard', 'VISA', 500),
  ('HDFC Bank', 'Diners Club Black Credit Card', 'super-premium', 'Diners Club', 10000)
ON CONFLICT DO NOTHING;

-- Create card_benefits table (works with both credit_cards and card_catalog)
CREATE TABLE card_benefits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id UUID, -- Can reference either credit_cards or card_catalog
  benefit_id UUID NOT NULL REFERENCES benefits(id),
  value DECIMAL(10, 2),
  spending_categories TEXT[],
  monthly_cap DECIMAL(10, 2),
  annual_cap DECIMAL(10, 2),
  valid_from TIMESTAMP WITH TIME ZONE,
  valid_to TIMESTAMP WITH TIME ZONE,
  configuration JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create benefit_tiers table
CREATE TABLE benefit_tiers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_benefit_id UUID NOT NULL REFERENCES card_benefits(id),
  tier_min_value DECIMAL(10, 2) NOT NULL,
  tier_max_value DECIMAL(10, 2),
  tier_benefit_value DECIMAL(10, 2) NOT NULL,
  tier_name TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create benefit_configurations table
CREATE TABLE benefit_configurations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_benefit_id UUID NOT NULL REFERENCES card_benefits(id),
  config_key TEXT NOT NULL,
  config_value TEXT NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(card_benefit_id, config_key)
);

-- Create indexes for better performance
CREATE INDEX idx_benefits_category_code ON benefits(category_code);
CREATE INDEX idx_benefits_active ON benefits(is_active);
CREATE INDEX idx_card_benefits_card_id ON card_benefits(card_id);
CREATE INDEX idx_card_benefits_benefit_id ON card_benefits(benefit_id);
CREATE INDEX idx_card_benefits_active ON card_benefits(is_active);

-- Print completion message
DO $$
BEGIN
  RAISE NOTICE 'CardCompass benefit tables created successfully!';
  RAISE NOTICE 'Tables created: benefit_categories, benefits, card_benefits, benefit_tiers, benefit_configurations';
  RAISE NOTICE 'Sample cards inserted into card_catalog table';
  RAISE NOTICE 'Default benefit categories and benefits inserted';
END $$;


-- ========================================
-- FROM FILE: setup_database.sql
-- ========================================

-- CardCompass Database Schema Setup - Updated Version
-- Run this in Supabase Dashboard > SQL Editor
-- This includes the new card catalog and user cards separation

-- 1. Create Users Table
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  given_name TEXT,
  family_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  date_of_birth DATE,
  profile_data JSONB DEFAULT '{}', -- Store additional profile info like birthday formats
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  preferences JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true
);

-- 2. Create Card Catalog Table (for card definitions)
CREATE TABLE IF NOT EXISTS card_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bank TEXT NOT NULL,
  card_name TEXT NOT NULL,
  network TEXT NOT NULL CHECK (network IN ('visa', 'mastercard', 'rupay', 'amex', 'discover', 'diners')),
  card_type TEXT NOT NULL CHECK (card_type IN ('credit', 'debit', 'prepaid')),
  joining_fee DECIMAL(10,2),
  annual_fee DECIMAL(10,2),
  apr DECIMAL(5,2),
  is_discontinued BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(bank, card_name, network)
);

-- 3. Create User Cards Table (for user-specific card instances)
CREATE TABLE IF NOT EXISTS user_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  catalog_card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE,
  last_four_digits TEXT,
  card_number TEXT, -- Should be encrypted in production
  expiry_date TEXT, -- Format: MM/YY
  card_holder_name TEXT,
  credit_limit DECIMAL(12,2),
  statement_date INTEGER, -- Day of month (1-31)
  due_date INTEGER, -- Days after statement date
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Create Transactions Table (Updated for new schema)
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID, -- Legacy field for backward compatibility
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE, -- New field
  amount DECIMAL(12,2) NOT NULL,
  currency TEXT DEFAULT 'INR' NOT NULL,
  description TEXT NOT NULL,
  merchant_name TEXT,
  category TEXT NOT NULL CHECK (category IN (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 
    'shopping', 'utilities', 'insurance', 'medical', 'education',
    'investment', 'transport', 'rental', 'subscription', 'gift', 'other'
  )),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN (
    'debit', 'credit', 'refund', 'fee', 'interest', 'reward'
  )),
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  location TEXT,
  reward_earned DECIMAL(8,2),
  reward_type TEXT,
  metadata JSONB DEFAULT '{}',
  statement_id UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Create Statements Table
CREATE TABLE IF NOT EXISTS statements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID REFERENCES credit_cards(id) ON DELETE CASCADE,
  statement_date DATE NOT NULL,
  due_date DATE NOT NULL,
  total_amount DECIMAL(12,2) NOT NULL,
  minimum_payment DECIMAL(12,2) NOT NULL,
  closing_balance DECIMAL(12,2) NOT NULL,
  available_credit DECIMAL(12,2),
  rewards_earned DECIMAL(8,2) DEFAULT 0,
  interest_charged DECIMAL(8,2) DEFAULT 0,
  fees_charged DECIMAL(8,2) DEFAULT 0,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue', 'partial')),
  file_path TEXT,
  file_name TEXT,
  parsed_at TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}',
  processed BOOLEAN DEFAULT false,
  transaction_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Create Benefits Table
CREATE TABLE IF NOT EXISTS benefits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  value_type TEXT CHECK (value_type IN ('percentage', 'fixed', 'points', 'cashback')),
  value DECIMAL(10,4),
  conditions JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. Create Card-Benefits Relationship Table (Updated for new schema)
CREATE TABLE IF NOT EXISTS card_benefits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE, -- Updated reference
  benefit_id UUID REFERENCES benefits(id) ON DELETE CASCADE,
  multiplier DECIMAL(4,2) DEFAULT 1.0,
  spending_categories TEXT[] DEFAULT '{}', -- Categories this benefit applies to
  monthly_cap DECIMAL(10,2), -- Monthly reward cap
  annual_cap DECIMAL(10,2), -- Annual reward cap
  conditions JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 8. Create Emails Table (for Gmail processing)
CREATE TABLE IF NOT EXISTS emails (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  email_id TEXT NOT NULL,
  subject TEXT,
  sender TEXT,
  received_date TIMESTAMP WITH TIME ZONE,
  has_attachments BOOLEAN DEFAULT false,
  processed BOOLEAN DEFAULT false,
  bank_detected TEXT,
  statement_id UUID REFERENCES statements(id),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 9. Create Parsed Data Table
CREATE TABLE IF NOT EXISTS parsed_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (source_type IN ('email', 'pdf', 'manual', 'api')),
  source_id TEXT,
  raw_data JSONB,
  parsed_data JSONB,
  parsing_status TEXT DEFAULT 'pending' CHECK (parsing_status IN ('pending', 'success', 'failed', 'partial')),
  error_message TEXT,
  confidence_score DECIMAL(3,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 10. Create ML Models Table
CREATE TABLE IF NOT EXISTS ml_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  model_type TEXT NOT NULL,
  parameters JSONB DEFAULT '{}',
  training_data_summary JSONB DEFAULT '{}',
  performance_metrics JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 11. Create ML Predictions Table
CREATE TABLE IF NOT EXISTS ml_predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  model_id UUID REFERENCES ml_models(id),
  prediction_type TEXT NOT NULL,
  input_data JSONB,
  prediction JSONB,
  confidence_score DECIMAL(3,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 12. Create Recommendations Table
CREATE TABLE IF NOT EXISTS recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  recommendation_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  card_id UUID REFERENCES credit_cards(id),
  priority INTEGER DEFAULT 1,
  confidence_score DECIMAL(3,2),
  potential_savings DECIMAL(10,2),
  metadata JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ===================================
-- RPC FUNCTIONS FOR NEW SCHEMA
-- ===================================

-- Function to create or get card catalog entry
CREATE OR REPLACE FUNCTION create_or_get_card_catalog(
    _bank TEXT,
    _card_name TEXT,
    _network TEXT,
    _card_type TEXT,
    _joining_fee DECIMAL DEFAULT NULL,
    _annual_fee DECIMAL DEFAULT NULL,
    _apr DECIMAL DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    card_id UUID;
BEGIN
    -- Try to find existing card
    SELECT id INTO card_id
    FROM card_catalog 
    WHERE bank = _bank 
    AND card_name = _card_name 
    AND network = _network
    AND card_type = _card_type;
    
    -- If not found, create new card
    IF card_id IS NULL THEN
        INSERT INTO card_catalog (
            bank, card_name, network, card_type, 
            joining_fee, annual_fee, apr
        ) VALUES (
            _bank, _card_name, _network, _card_type,
            _joining_fee, _annual_fee, _apr
        ) RETURNING id INTO card_id;
    END IF;
    
    RETURN card_id;
END;
$$;

-- Function to associate user with card
CREATE OR REPLACE FUNCTION associate_user_with_card(
    _user_id UUID,
    _catalog_card_id UUID,
    _last_four_digits TEXT DEFAULT NULL,
    _card_number TEXT DEFAULT NULL,
    _expiry_date TEXT DEFAULT NULL,
    _card_holder_name TEXT DEFAULT NULL,
    _credit_limit DECIMAL DEFAULT NULL,
    _statement_date INTEGER DEFAULT NULL,
    _due_date INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_card_id UUID;
BEGIN
    INSERT INTO user_cards (
        user_id, catalog_card_id, last_four_digits,
        card_number, expiry_date, card_holder_name,
        credit_limit, statement_date, due_date
    ) VALUES (
        _user_id, _catalog_card_id, _last_four_digits,
        _card_number, _expiry_date, _card_holder_name,
        _credit_limit, _statement_date, _due_date
    ) RETURNING id INTO user_card_id;
    
    RETURN user_card_id;
END;
$$;

-- Function to add transaction
CREATE OR REPLACE FUNCTION add_transaction(
    _user_id UUID,
    _user_card_id UUID,
    _amount DECIMAL,
    _description TEXT,
    _transaction_date TIMESTAMPTZ,
    _category TEXT,
    _type TEXT,
    _currency TEXT DEFAULT 'INR',
    _merchant_name TEXT DEFAULT NULL,
    _location TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_id UUID;
BEGIN
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

-- Function to get user cards with catalog information
CREATE OR REPLACE FUNCTION get_user_cards(_user_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    catalog_card_id UUID,
    last_four_digits TEXT,
    card_number TEXT,
    expiry_date TEXT,
    card_holder_name TEXT,
    credit_limit DECIMAL,
    statement_date INTEGER,
    due_date INTEGER,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    -- Card catalog fields
    bank TEXT,
    card_name TEXT,
    network TEXT,
    card_type TEXT,
    joining_fee DECIMAL,
    annual_fee DECIMAL,
    apr DECIMAL,
    is_discontinued BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to get card catalog
CREATE OR REPLACE FUNCTION get_card_catalog()
RETURNS TABLE (
    id UUID,
    bank TEXT,
    card_name TEXT,
    network TEXT,
    card_type TEXT,
    joining_fee DECIMAL,
    annual_fee DECIMAL,
    apr DECIMAL,
    is_discontinued BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to get user transactions with card details
CREATE OR REPLACE FUNCTION get_user_transactions(_user_id UUID, _limit INTEGER DEFAULT 50)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    user_card_id UUID,
    card_id UUID,
    amount DECIMAL,
    currency TEXT,
    description TEXT,
    merchant_name TEXT,
    category TEXT,
    transaction_type TEXT,
    transaction_date TIMESTAMPTZ,
    location TEXT,
    reward_earned DECIMAL,
    reward_type TEXT,
    statement_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    -- Card details
    bank TEXT,
    card_name TEXT,
    last_four_digits TEXT,
    network TEXT,
    card_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.user_id,
        t.user_card_id,
        t.card_id,
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
        COALESCE(cc.bank, 'Unknown') as bank,
        COALESCE(cc.card_name, 'Unknown') as card_name,
        COALESCE(uc.last_four_digits, '****') as last_four_digits,
        COALESCE(cc.network, 'unknown') as network,
        COALESCE(cc.card_type, 'unknown') as card_type
    FROM transactions t
    LEFT JOIN user_cards uc ON t.user_card_id = uc.id
    LEFT JOIN card_catalog cc ON uc.catalog_card_id = cc.id
    WHERE t.user_id = _user_id
    ORDER BY t.transaction_date DESC, t.created_at DESC
    LIMIT _limit;
END;
$$;

-- Function to remove/deactivate a user card
CREATE OR REPLACE FUNCTION remove_user_card(_user_id UUID, _catalog_card_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to update user card details
CREATE OR REPLACE FUNCTION update_user_card(
    _user_id UUID,
    _catalog_card_id UUID,
    _last_four_digits TEXT DEFAULT NULL,
    _credit_limit DECIMAL DEFAULT NULL,
    _card_holder_name TEXT DEFAULT NULL,
    _expiry_date TEXT DEFAULT NULL,
    _statement_date INTEGER DEFAULT NULL,
    _due_date INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_card_id ON transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category);
CREATE INDEX IF NOT EXISTS idx_user_cards_user_id ON user_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_statements_user_id ON statements(user_id);
CREATE INDEX IF NOT EXISTS idx_statements_card_id ON statements(card_id);

-- Enable Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE parsed_data ENABLE ROW LEVEL SECURITY;

-- Create RLS Policies (Basic - users can only access their own data)
CREATE POLICY "Users can view own data" ON users
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users can view own cards" ON user_cards
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own transactions" ON transactions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own statements" ON statements
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own recommendations" ON recommendations
  FOR ALL USING (auth.uid() = user_id);

-- Credit cards are public (read-only for discovery)
CREATE POLICY "Anyone can view credit cards" ON credit_cards
  FOR SELECT USING (true);

-- Enable and configure Row Level Security (RLS) policies

-- credit_cards RLS
ALTER TABLE credit_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own credit cards" ON credit_cards
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- user_cards RLS
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own user_cards" ON user_cards
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- transactions RLS
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own transactions" ON transactions
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- statements RLS
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own statements" ON statements
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- emails RLS
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own emails" ON emails
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Success Message
SELECT 'CardCompass Database Schema Setup Complete! ✅' as result;


-- ========================================
-- FROM FILE: setup_database_production.sql
-- ========================================

-- CardCompass Database Schema Setup - Updated Version
-- Run this in Supabase Dashboard > SQL Editor
-- This includes the new card catalog and user cards separation

-- 1. Create Users Table
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  given_name TEXT,
  family_name TEXT,
  avatar_url TEXT,
  phone TEXT,
  date_of_birth DATE,
  profile_data JSONB DEFAULT '{}', -- Store additional profile info like birthday formats
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  preferences JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true
);

-- 2. Create Card Catalog Table (for card definitions)
CREATE TABLE IF NOT EXISTS card_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bank TEXT NOT NULL,
  card_name TEXT NOT NULL,
  network TEXT NOT NULL CHECK (network IN ('visa', 'mastercard', 'rupay', 'amex', 'discover', 'diners')),
  card_type TEXT NOT NULL CHECK (card_type IN ('credit', 'debit', 'prepaid')),
  joining_fee DECIMAL(10,2),
  annual_fee DECIMAL(10,2),
  apr DECIMAL(5,2),
  is_discontinued BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(bank, card_name, network)
);

-- 3. Create User Cards Table (for user-specific card instances)
CREATE TABLE IF NOT EXISTS user_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  catalog_card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE,
  last_four_digits TEXT,
  card_number TEXT, -- Should be encrypted in production
  expiry_date TEXT, -- Format: MM/YY
  card_holder_name TEXT,
  credit_limit DECIMAL(12,2),
  statement_date INTEGER, -- Day of month (1-31)
  due_date INTEGER, -- Days after statement date
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Create Transactions Table (Updated for new schema)
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID, -- Legacy field for backward compatibility
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE, -- New field
  amount DECIMAL(12,2) NOT NULL,
  currency TEXT DEFAULT 'INR' NOT NULL,
  description TEXT NOT NULL,
  merchant_name TEXT,
  category TEXT NOT NULL CHECK (category IN (
    'food', 'fuel', 'grocery', 'entertainment', 'travel', 
    'shopping', 'utilities', 'insurance', 'medical', 'education',
    'investment', 'transport', 'rental', 'subscription', 'gift', 'other'
  )),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN (
    'debit', 'credit', 'refund', 'fee', 'interest', 'reward'
  )),
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  location TEXT,
  reward_earned DECIMAL(8,2),
  reward_type TEXT,
  metadata JSONB DEFAULT '{}',
  statement_id UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Create Statements Table
CREATE TABLE IF NOT EXISTS statements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID REFERENCES credit_cards(id) ON DELETE CASCADE,
  statement_date DATE NOT NULL,
  due_date DATE NOT NULL,
  total_amount DECIMAL(12,2) NOT NULL,
  minimum_payment DECIMAL(12,2) NOT NULL,
  closing_balance DECIMAL(12,2) NOT NULL,
  available_credit DECIMAL(12,2),
  rewards_earned DECIMAL(8,2) DEFAULT 0,
  interest_charged DECIMAL(8,2) DEFAULT 0,
  fees_charged DECIMAL(8,2) DEFAULT 0,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue', 'partial')),
  file_path TEXT,
  file_name TEXT,
  parsed_at TIMESTAMP WITH TIME ZONE,
  metadata JSONB DEFAULT '{}',
  processed BOOLEAN DEFAULT false,
  transaction_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Create Benefits Table
CREATE TABLE IF NOT EXISTS benefits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  value_type TEXT CHECK (value_type IN ('percentage', 'fixed', 'points', 'cashback')),
  value DECIMAL(10,4),
  conditions JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. Create Card-Benefits Relationship Table (Updated for new schema)
CREATE TABLE IF NOT EXISTS card_benefits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE, -- Updated reference
  benefit_id UUID REFERENCES benefits(id) ON DELETE CASCADE,
  multiplier DECIMAL(4,2) DEFAULT 1.0,
  spending_categories TEXT[] DEFAULT '{}', -- Categories this benefit applies to
  monthly_cap DECIMAL(10,2), -- Monthly reward cap
  annual_cap DECIMAL(10,2), -- Annual reward cap
  conditions JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 8. Create Emails Table (for Gmail processing)
CREATE TABLE IF NOT EXISTS emails (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  email_id TEXT NOT NULL,
  subject TEXT,
  sender TEXT,
  received_date TIMESTAMP WITH TIME ZONE,
  has_attachments BOOLEAN DEFAULT false,
  processed BOOLEAN DEFAULT false,
  bank_detected TEXT,
  statement_id UUID REFERENCES statements(id),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 9. Create Parsed Data Table
CREATE TABLE IF NOT EXISTS parsed_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (source_type IN ('email', 'pdf', 'manual', 'api')),
  source_id TEXT,
  raw_data JSONB,
  parsed_data JSONB,
  parsing_status TEXT DEFAULT 'pending' CHECK (parsing_status IN ('pending', 'success', 'failed', 'partial')),
  error_message TEXT,
  confidence_score DECIMAL(3,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 10. Create ML Models Table
CREATE TABLE IF NOT EXISTS ml_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  model_type TEXT NOT NULL,
  parameters JSONB DEFAULT '{}',
  training_data_summary JSONB DEFAULT '{}',
  performance_metrics JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 11. Create ML Predictions Table
CREATE TABLE IF NOT EXISTS ml_predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  model_id UUID REFERENCES ml_models(id),
  prediction_type TEXT NOT NULL,
  input_data JSONB,
  prediction JSONB,
  confidence_score DECIMAL(3,2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 12. Create Recommendations Table
CREATE TABLE IF NOT EXISTS recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  recommendation_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  card_id UUID REFERENCES credit_cards(id),
  priority INTEGER DEFAULT 1,
  confidence_score DECIMAL(3,2),
  potential_savings DECIMAL(10,2),
  metadata JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ===================================
-- RPC FUNCTIONS FOR NEW SCHEMA
-- ===================================

-- Function to create or get card catalog entry
CREATE OR REPLACE FUNCTION create_or_get_card_catalog(
    _bank TEXT,
    _card_name TEXT,
    _network TEXT,
    _card_type TEXT,
    _joining_fee DECIMAL DEFAULT NULL,
    _annual_fee DECIMAL DEFAULT NULL,
    _apr DECIMAL DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    card_id UUID;
BEGIN
    -- Try to find existing card
    SELECT id INTO card_id
    FROM card_catalog 
    WHERE bank = _bank 
    AND card_name = _card_name 
    AND network = _network
    AND card_type = _card_type;
    
    -- If not found, create new card
    IF card_id IS NULL THEN
        INSERT INTO card_catalog (
            bank, card_name, network, card_type, 
            joining_fee, annual_fee, apr
        ) VALUES (
            _bank, _card_name, _network, _card_type,
            _joining_fee, _annual_fee, _apr
        ) RETURNING id INTO card_id;
    END IF;
    
    RETURN card_id;
END;
$$;

-- Function to associate user with card
CREATE OR REPLACE FUNCTION associate_user_with_card(
    _user_id UUID,
    _catalog_card_id UUID,
    _last_four_digits TEXT DEFAULT NULL,
    _card_number TEXT DEFAULT NULL,
    _expiry_date TEXT DEFAULT NULL,
    _card_holder_name TEXT DEFAULT NULL,
    _credit_limit DECIMAL DEFAULT NULL,
    _statement_date INTEGER DEFAULT NULL,
    _due_date INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_card_id UUID;
BEGIN
    INSERT INTO user_cards (
        user_id, catalog_card_id, last_four_digits,
        card_number, expiry_date, card_holder_name,
        credit_limit, statement_date, due_date
    ) VALUES (
        _user_id, _catalog_card_id, _last_four_digits,
        _card_number, _expiry_date, _card_holder_name,
        _credit_limit, _statement_date, _due_date
    ) RETURNING id INTO user_card_id;
    
    RETURN user_card_id;
END;
$$;

-- Function to add transaction
CREATE OR REPLACE FUNCTION add_transaction(
    _user_id UUID,
    _user_card_id UUID,
    _amount DECIMAL,
    _description TEXT,
    _transaction_date TIMESTAMPTZ,
    _category TEXT,
    _type TEXT,
    _currency TEXT DEFAULT 'INR',
    _merchant_name TEXT DEFAULT NULL,
    _location TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_id UUID;
BEGIN
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

-- Function to get user cards with catalog information
CREATE OR REPLACE FUNCTION get_user_cards(_user_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    catalog_card_id UUID,
    last_four_digits TEXT,
    card_number TEXT,
    expiry_date TEXT,
    card_holder_name TEXT,
    credit_limit DECIMAL,
    statement_date INTEGER,
    due_date INTEGER,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    -- Card catalog fields
    bank TEXT,
    card_name TEXT,
    network TEXT,
    card_type TEXT,
    joining_fee DECIMAL,
    annual_fee DECIMAL,
    apr DECIMAL,
    is_discontinued BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to get card catalog
CREATE OR REPLACE FUNCTION get_card_catalog()
RETURNS TABLE (
    id UUID,
    bank TEXT,
    card_name TEXT,
    network TEXT,
    card_type TEXT,
    joining_fee DECIMAL,
    annual_fee DECIMAL,
    apr DECIMAL,
    is_discontinued BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to get user transactions with card details
CREATE OR REPLACE FUNCTION get_user_transactions(_user_id UUID, _limit INTEGER DEFAULT 50)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    user_card_id UUID,
    card_id UUID,
    amount DECIMAL,
    currency TEXT,
    description TEXT,
    merchant_name TEXT,
    category TEXT,
    transaction_type TEXT,
    transaction_date TIMESTAMPTZ,
    location TEXT,
    reward_earned DECIMAL,
    reward_type TEXT,
    statement_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    -- Card details
    bank TEXT,
    card_name TEXT,
    last_four_digits TEXT,
    network TEXT,
    card_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.user_id,
        t.user_card_id,
        t.card_id,
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
        COALESCE(cc.bank, 'Unknown') as bank,
        COALESCE(cc.card_name, 'Unknown') as card_name,
        COALESCE(uc.last_four_digits, '****') as last_four_digits,
        COALESCE(cc.network, 'unknown') as network,
        COALESCE(cc.card_type, 'unknown') as card_type
    FROM transactions t
    LEFT JOIN user_cards uc ON t.user_card_id = uc.id
    LEFT JOIN card_catalog cc ON uc.catalog_card_id = cc.id
    WHERE t.user_id = _user_id
    ORDER BY t.transaction_date DESC, t.created_at DESC
    LIMIT _limit;
END;
$$;

-- Function to remove/deactivate a user card
CREATE OR REPLACE FUNCTION remove_user_card(_user_id UUID, _catalog_card_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function to update user card details
CREATE OR REPLACE FUNCTION update_user_card(
    _user_id UUID,
    _catalog_card_id UUID,
    _last_four_digits TEXT DEFAULT NULL,
    _credit_limit DECIMAL DEFAULT NULL,
    _card_holder_name TEXT DEFAULT NULL,
    _expiry_date TEXT DEFAULT NULL,
    _statement_date INTEGER DEFAULT NULL,
    _due_date INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_card_id ON transactions(card_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category);
CREATE INDEX IF NOT EXISTS idx_user_cards_user_id ON user_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_statements_user_id ON statements(user_id);
CREATE INDEX IF NOT EXISTS idx_statements_card_id ON statements(card_id);

-- Enable Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE parsed_data ENABLE ROW LEVEL SECURITY;

-- Create RLS Policies (Basic - users can only access their own data)
CREATE POLICY "Users can view own data" ON users
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users can view own cards" ON user_cards
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own transactions" ON transactions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own statements" ON statements
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own recommendations" ON recommendations
  FOR ALL USING (auth.uid() = user_id);

-- Credit cards are public (read-only for discovery)
CREATE POLICY "Anyone can view credit cards" ON credit_cards
  FOR SELECT USING (true);

-- Enable and configure Row Level Security (RLS) policies

-- credit_cards RLS
ALTER TABLE credit_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own credit cards" ON credit_cards
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- user_cards RLS
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own user_cards" ON user_cards
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- transactions RLS
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own transactions" ON transactions
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- statements RLS
ALTER TABLE statements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own statements" ON statements
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- emails RLS
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own emails" ON emails
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Success Message
SELECT 'CardCompass Database Schema Setup Complete! ✅' as result;


