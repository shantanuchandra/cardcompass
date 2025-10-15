-- Schema Validation Script for Movie Rule Engine
-- This script can be used to validate that the movie rule engine schema is working correctly

-- Check if all required columns exist in card_benefits table
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'card_benefits' 
AND column_name IN ('usage_period', 'priority_score', 'efficiency_threshold', 'last_usage_update', 'json_configuration')
ORDER BY column_name;

-- Check if weekly_milestone_cache table exists with correct structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'weekly_milestone_cache'
ORDER BY ordinal_position;

-- Check if entertainment category was inserted
SELECT * FROM benefit_categories WHERE category_code = 'entertainment';

-- Check sample movie benefits (if data was inserted)
SELECT 
  cc.card_name,
  b.name as benefit_name,
  cb.monthly_cap,
  cb.annual_cap,
  cb.priority_score,
  cb.efficiency_threshold,
  cb.json_configuration
FROM card_benefits cb
JOIN card_catalog cc ON cb.card_id = cc.id
JOIN benefits b ON cb.benefit_id = b.id
WHERE b.category = 'entertainment'
ORDER BY cb.priority_score DESC;

-- Test the weekly milestone cache functionality
-- (This would be empty initially, but the table should exist)
SELECT COUNT(*) as milestone_cache_count FROM weekly_milestone_cache;

-- Verify indexes were created
SELECT indexname, tablename 
FROM pg_indexes 
WHERE tablename IN ('card_benefits', 'weekly_milestone_cache')
AND indexname LIKE '%milestone%';
