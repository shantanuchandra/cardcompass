# Movie Rule Engine: Statement Cycle Milestone Tracking

## Overview

This document outlines the migration from weekly milestone tracking to statement cycle-based milestone tracking for movie ticket benefits. The new approach aligns with the product requirement to track monthly milestones based on the total credit card payments in the last statement cycle, rather than using a weekly tracking system.

## Key Changes

1. **New Database Schema**: 
   - Created a new `statement_milestone_cache` table to replace the now-deprecated `weekly_milestone_cache`
   - Added support for statement cycle dates (start and end) instead of just week start date
   - Added reference to `user_card_id` for better integration with statements table

2. **Updated Service Logic**:
   - Replaced `_updateWeeklyMilestoneCache()` with `_updateStatementCycleMilestones()`
   - Added `_getLatestStatementCycle()` to determine the current statement cycle for a card
   - Updated `_getMonthlyUsage()` to use statement cycle dates instead of calendar month

3. **Fallback Mechanism**:
   - Implemented fallback to calendar month when no statement data is available
   - Provided default 30-day cycle when no previous statements exist

## Schema Definition

The new `statement_milestone_cache` table schema:

```sql
CREATE TABLE IF NOT EXISTS statement_milestone_cache (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  card_id UUID NOT NULL REFERENCES card_catalog(id) ON DELETE CASCADE,
  user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE,
  benefit_category VARCHAR(50) NOT NULL,
  statement_start_date DATE NOT NULL,
  statement_end_date DATE NOT NULL,
  total_spending DECIMAL(12,2) DEFAULT 0,
  milestone_progress DECIMAL(5,2) DEFAULT 0,
  last_updated TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, card_id, benefit_category, statement_start_date, statement_end_date)
);
```

## Statement Cycle Logic

The system now determines the statement cycle using the following logic:

1. Find the latest statement date for the card
2. Use that as the statement cycle end date
3. Find the previous statement date (if any) to use as the cycle start date
4. If no previous statement exists, default to 30 days before the end date

## Migration Plan

1. **Phase 1** (Completed):
   - Create the new table and update the service to use it
   - ✓ The old `weekly_milestone_cache` table has been removed from Supabase
   - Data is now tracked in the statement_milestone_cache table

2. **Phase 2** (Completed):
   - ✓ All references now use the new statement cycle-based approach
   - ✓ Documentation has been updated to reflect the new approach

## Testing

Test cases have been updated to verify:
- Proper retrieval of statement cycle dates
- Accurate update of statement milestone cache
- Correct usage calculation based on statement cycles

## Benefits

- More accurate benefit tracking aligned with actual statement cycles
- Better integration with the statement and payment tracking system
- Support for variable-length billing cycles (not just fixed 7-day weeks)
- More accurate milestone achievement based on actual payment patterns
