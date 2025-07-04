-- Movie Ticket Rule Engine Database Setup
-- This file contains the schema enhancements and sample data for the movie rule engine

-- ============================================================================
-- SCHEMA ENHANCEMENTS (Generic columns for all benefit categories)
-- ============================================================================

-- Add generic columns to card_benefits table
ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS 
  usage_period VARCHAR(20) DEFAULT 'monthly' CHECK (usage_period IN ('daily', 'weekly', 'monthly', 'yearly'));

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS 
  priority_score INTEGER DEFAULT 1 CHECK (priority_score >= 1 AND priority_score <= 10);

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS 
  efficiency_threshold DECIMAL(10,2); -- Don't use high-value benefits for low amounts

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS 
  last_usage_update TIMESTAMP DEFAULT NOW();

ALTER TABLE card_benefits ADD COLUMN IF NOT EXISTS 
  json_configuration JSONB;

-- Create weekly milestone cache table (generic for all categories)
CREATE TABLE IF NOT EXISTS weekly_milestone_cache (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  benefit_category VARCHAR(50) NOT NULL,
  week_start_date DATE NOT NULL,
  total_spending DECIMAL(12,2) DEFAULT 0,
  milestone_progress DECIMAL(5,2) DEFAULT 0, -- Percentage towards milestone
  last_updated TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, card_id, benefit_category, week_start_date)
);

-- Create index for fast milestone lookups
CREATE INDEX IF NOT EXISTS idx_milestone_cache_lookup 
ON weekly_milestone_cache(user_id, card_id, benefit_category, week_start_date);

-- ============================================================================
-- SAMPLE MOVIE BENEFITS DATA
-- ============================================================================

-- Insert entertainment category if not exists
INSERT INTO benefit_categories (category_code, name, description, is_active)
VALUES ('entertainment', 'Entertainment', 'Movie tickets, streaming services, and entertainment venues', true)
ON CONFLICT (category_code) DO NOTHING;

-- Sample Movie Benefits
-- These would typically be inserted/updated by the admin panel

-- 1. ICICI Sapphiro BOGO Movie Benefit
INSERT INTO benefits (
  name,
  category_code,
  description,
  calculation_method,
  default_value,
  is_active,
  created_at
) 
SELECT 
  'Movie BOGO Sapphiro',
  'entertainment',
  'Buy 1 Get 1 free movie tickets on BookMyShow',
  'percentage',
  50.0,
  true,
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM benefits WHERE name = 'Movie BOGO Sapphiro'
);

-- 2. ICICI Emerald BOGO Movie Benefit (Higher value)
INSERT INTO benefits (
  name,
  category_code,
  description,
  calculation_method,
  default_value,
  is_active,
  created_at
) 
SELECT 
  'Movie BOGO Emerald',
  'entertainment',
  'Buy 1 Get 1 free movie tickets up to ₹750 on BookMyShow',
  'percentage',
  50.0,
  true,
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM benefits WHERE name = 'Movie BOGO Emerald'
);

-- 3. Axis Burgundy Movie Cashback
INSERT INTO benefits (
  name,
  category_code,
  description,
  calculation_method,
  default_value,
  is_active,
  created_at
) 
SELECT 
  'Movie Cashback Burgundy',
  'entertainment',
  '25% cashback on movie tickets',
  'percentage',
  25.0,
  true,
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM benefits WHERE name = 'Movie Cashback Burgundy'
);

-- 4. Diners Club Black Milestone Benefit
INSERT INTO benefits (
  name,
  category_code,
  description,
  calculation_method,
  default_value,
  is_active,
  created_at
) 
SELECT 
  'Movie Milestone Black',
  'entertainment',
  'Free movie tickets on milestone completion',
  'fixed',
  2.0,
  true,
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM benefits WHERE name = 'Movie Milestone Black'
);

-- ============================================================================
-- SAMPLE CARD BENEFITS CONFIGURATION
-- ============================================================================

-- ICICI Sapphiro Movie BOGO (Efficiency threshold: ₹200)
INSERT INTO card_benefits (
  card_id,
  benefit_id,
  spending_categories,
  monthly_cap,
  annual_cap,
  usage_period,
  priority_score,
  efficiency_threshold,
  json_configuration,
  is_active
) 
SELECT 
  (SELECT id FROM card_catalog WHERE card_name ILIKE '%Sapphiro%' LIMIT 1),
  (SELECT id FROM benefits WHERE name = 'Movie BOGO Sapphiro'),
  ARRAY['entertainment'],
  8, -- 8 tickets per month
  96, -- 96 tickets per year
  'monthly',
  7, -- High priority
  200, -- Don't use for tickets below ₹200
  '{
    "offer_type": "BOGO",
    "partner_filter": ["BookMyShow"],
    "free_ticket_count": 1,
    "max_discount_amount": 300,
    "txn_ticket_limit": 4,
    "month_ticket_limit": 8,
    "valid_dow": ["SAT", "SUN"],
    "start_date": "2025-01-01",
    "end_date": "2025-12-31",
    "min_transaction_amount": 200,
    "max_transaction_amount": 1200,
    "efficiency_threshold": 200
  }',
  true
WHERE EXISTS (SELECT 1 FROM card_catalog WHERE card_name ILIKE '%Sapphiro%')
  AND EXISTS (SELECT 1 FROM benefits WHERE name = 'Movie BOGO Sapphiro')
  AND NOT EXISTS (
    SELECT 1 FROM card_benefits cb 
    JOIN benefits b ON cb.benefit_id = b.id 
    WHERE b.name = 'Movie BOGO Sapphiro' 
    AND cb.card_id = (SELECT id FROM card_catalog WHERE card_name ILIKE '%Sapphiro%' LIMIT 1)
  );

-- ICICI Emerald Movie BOGO (Efficiency threshold: ₹400)
INSERT INTO card_benefits (
  card_id,
  benefit_id,
  spending_categories,
  monthly_cap,
  annual_cap,
  usage_period,
  priority_score,
  efficiency_threshold,
  json_configuration,
  is_active
) 
SELECT 
  (SELECT id FROM card_catalog WHERE card_name ILIKE '%emerald%' LIMIT 1),
  (SELECT id FROM benefits WHERE name = 'Movie BOGO Emerald'),
  ARRAY['entertainment'],
  12, -- 12 tickets per month
  144, -- 144 tickets per year
  'monthly',
  9, -- Higher priority but higher threshold
  400, -- Don't use for tickets below ₹400
  '{
    "offer_type": "BOGO",
    "partner_filter": ["BookMyShow", "PVR"],
    "free_ticket_count": 1,
    "max_discount_amount": 750,
    "txn_ticket_limit": 6,
    "month_ticket_limit": 12,
    "start_date": "2025-01-01",
    "end_date": "2025-12-31",
    "min_transaction_amount": 400,
    "max_transaction_amount": 2000,
    "efficiency_threshold": 400
  }',
  true
WHERE EXISTS (SELECT 1 FROM card_catalog WHERE card_name ILIKE '%emerald%')
  AND EXISTS (SELECT 1 FROM benefits WHERE name = 'Movie BOGO Emerald')
  AND NOT EXISTS (
    SELECT 1 FROM card_benefits cb 
    JOIN benefits b ON cb.benefit_id = b.id 
    WHERE b.name = 'Movie BOGO Emerald' 
    AND cb.card_id = (SELECT id FROM card_catalog WHERE card_name ILIKE '%emerald%' LIMIT 1)
  );

-- Axis Burgundy Movie Cashback (Efficiency threshold: ₹150)
INSERT INTO card_benefits (
  card_id,
  benefit_id,
  spending_categories,
  monthly_cap,
  annual_cap,
  usage_period,
  priority_score,
  efficiency_threshold,
  json_configuration,
  is_active
) 
SELECT 
  (SELECT id FROM card_catalog WHERE card_name ILIKE '%burgundy%' LIMIT 1),
  (SELECT id FROM benefits WHERE name = 'Movie Cashback Burgundy'),
  ARRAY['entertainment'],
  2500, -- ₹2500 cashback per month
  30000, -- ₹30000 cashback per year
  'monthly',
  6, -- Medium priority
  150, -- Good for smaller amounts
  '{
    "offer_type": "CASHBACK",
    "partner_filter": null,
    "discount_percent": 25,
    "max_discount_amount": 500,
    "txn_ticket_limit": 10,
    "month_cashback_limit": 2500,
    "start_date": "2025-01-01",
    "end_date": "2025-12-31",
    "min_transaction_amount": 150,
    "efficiency_threshold": 150
  }',
  true
WHERE EXISTS (SELECT 1 FROM card_catalog WHERE card_name ILIKE '%burgundy%')
  AND EXISTS (SELECT 1 FROM benefits WHERE name = 'Movie Cashback Burgundy')
  AND NOT EXISTS (
    SELECT 1 FROM card_benefits cb 
    JOIN benefits b ON cb.benefit_id = b.id 
    WHERE b.name = 'Movie Cashback Burgundy' 
    AND cb.card_id = (SELECT id FROM card_catalog WHERE card_name ILIKE '%burgundy%' LIMIT 1)
  );

-- Diners Club Black Milestone (Efficiency threshold: ₹300)
INSERT INTO card_benefits (
  card_id,
  benefit_id,
  spending_categories,
  usage_period,
  priority_score,
  efficiency_threshold,
  json_configuration,
  is_active
) 
SELECT 
  (SELECT id FROM card_catalog WHERE card_name ILIKE '%diners%black%' LIMIT 1),
  (SELECT id FROM benefits WHERE name = 'Movie Milestone Black'),
  ARRAY['entertainment'],
  'monthly',
  8, -- High priority for milestone
  300, -- Good threshold
  '{
    "offer_type": "MILESTONE",
    "partner_filter": null,
    "milestone_currency": 10000,
    "milestone_reward": 2,
    "start_date": "2025-01-01",
    "end_date": "2025-12-31",
    "efficiency_threshold": 300
  }',
  true
WHERE EXISTS (SELECT 1 FROM card_catalog WHERE card_name ILIKE '%diners%black%')
  AND EXISTS (SELECT 1 FROM benefits WHERE name = 'Movie Milestone Black')
  AND NOT EXISTS (
    SELECT 1 FROM card_benefits cb 
    JOIN benefits b ON cb.benefit_id = b.id 
    WHERE b.name = 'Movie Milestone Black' 
    AND cb.card_id = (SELECT id FROM card_catalog WHERE card_name ILIKE '%diners%black%' LIMIT 1)
  );

-- ============================================================================
-- SAMPLE WEEKLY MILESTONE CACHE DATA
-- ============================================================================

-- Sample weekly milestone cache entries (for testing)
INSERT INTO weekly_milestone_cache (
  user_id,
  card_id,
  benefit_category,
  week_start_date,
  total_spending,
  milestone_progress,
  last_updated
) VALUES 
  -- User has spent ₹5000 this week on entertainment with Diners Black
  ('5dc9b591-40b6-4486-944e-3b4ef58c3d47'::UUID, (SELECT id FROM card_catalog WHERE card_name ILIKE '%Diners%Black%' LIMIT 1), 'entertainment', 
   DATE_TRUNC('week', NOW()), 5000.00, 50.0, NOW()),
  
  -- User has spent ₹2500 this week on entertainment with ICICI Sapphiro
  ('5dc9b591-40b6-4486-944e-3b4ef58c3d47'::UUID, (SELECT id FROM card_catalog WHERE card_name ILIKE '%Sapphiro%' LIMIT 1), 'entertainment', 
   DATE_TRUNC('week', NOW()), 2500.00, 0.0, NOW())
ON CONFLICT (user_id, card_id, benefit_category, week_start_date) DO NOTHING;

-- ============================================================================
-- USEFUL QUERIES FOR TESTING
-- ============================================================================

-- Query to check movie benefits for a user
/*
SELECT 
  cc.card_name,
  b.name,
  cb.spending_categories,
  cb.efficiency_threshold,
  cb.priority_score,
  cb.json_configuration
FROM user_cards uc
JOIN card_catalog cc ON uc.card_id = cc.id
JOIN card_benefits cb ON cc.id = cb.card_id
JOIN benefits b ON cb.benefit_id = b.id
WHERE uc.user_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND uc.is_active = true
  AND 'entertainment' = ANY(cb.spending_categories)
  AND cb.is_active = true
ORDER BY cb.priority_score DESC;
*/

-- Query to check weekly milestone progress
/*
SELECT 
  wmc.*,
  cc.card_name
FROM weekly_milestone_cache wmc
JOIN card_catalog cc ON wmc.card_id = cc.id
WHERE wmc.user_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND wmc.benefit_category = 'entertainment'
  AND wmc.week_start_date = DATE_TRUNC('week', NOW());
*/

-- ============================================================================
-- SCHEMA VALIDATION
-- ============================================================================

-- Verify the new columns were added
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns 
WHERE table_name = 'card_benefits' 
  AND column_name IN ('usage_period', 'priority_score', 'efficiency_threshold', 'last_usage_update');

-- Verify the weekly_milestone_cache table was created
SELECT table_name, column_name, data_type
FROM information_schema.columns 
WHERE table_name = 'weekly_milestone_cache'
ORDER BY ordinal_position;

COMMIT;
