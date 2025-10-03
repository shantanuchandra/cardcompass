# Root Cause Analysis: PostgreSQL Error in Movie Rule Engine

## Error Message
```
PostgrestException(message: column card_catalog.is_active does not exist, code: 42703, details: , hint: null)
```

## Summary
The PostgreSQL error occurred because our Supabase queries were trying to filter on an `is_active` column in the `card_catalog` table, but this column does not exist in the production database. Instead, the table has an `is_discontinued` column. There are inconsistencies in how the schema is defined across different SQL files in the codebase.

## Root Cause Identified
After investigating the codebase and database schema, I've identified several conflicts in how the `card_catalog` table is defined across different SQL scripts:

1. **Schema Inconsistency**: There's a mismatch between different SQL scripts that define the `card_catalog` table:

   - In `database_complete.sql` (line 684-694):
     ```sql
     CREATE TABLE IF NOT EXISTS card_catalog (
       ...
       is_active BOOLEAN DEFAULT TRUE,  -- Note: using is_active
       ...
     );
     ```

   - In `fix_card_catalog_schema.sql` (line 7-15):
     ```sql
     CREATE TABLE IF NOT EXISTS card_catalog (
       ...
       is_discontinued BOOLEAN DEFAULT TRUE,  -- Note: using is_discontinued
       ...
     );
     ```

2. **Migration Error**: There's an error in the data migration script that adds to the confusion:
   
   In previous version of migration scripts:
   ```sql
   -- This was incorrect and has been removed in the updated schema
   INSERT INTO card_catalog (id, card_name, bank_name, network, card_type, annual_fee, is_active, created_at)
   VALUES (...)
   ```
   
   This SQL tries to insert data into an `is_active` column in `card_catalog`, but according to the same file's schema definition, it should be using `is_discontinued`.

3. **Code Issue**: The Dart code in `movie_rule_engine_service.dart` had references to filtering on `card_catalog.is_active`, which was causing the error.

## Schema Resolution

Based on the evidence, it appears that:

1. The intention was for `card_catalog` to use `is_discontinued` (not `is_active`)
2. The `user_cards` table should have the `is_active` flag (which it does)
3. Multiple SQL files have inconsistent definitions
4. The migration script has an error

## Why Our Previous Fix Works

Our fix worked because we:

1. Removed any references to `is_active` in relation to `card_catalog`
2. Used regular joins instead of inner joins to prevent column reference issues
3. Only filtered on `is_active` in the `user_cards` table

## Recommended Next Steps

1. **Standardize Database Schema**:
   - Decide on one consistent schema for `card_catalog` (either with `is_active` or `is_discontinued`)
   - Update all SQL scripts to use the same column names
   - Run a migration to make the production schema match

2. **Fix Migration Scripts**:
   - Update `fix_credit_cards_table.sql` to use the correct column name in the INSERT statement

3. **Documentation**:
   - Create clear documentation about the card_catalog schema
   - Document the relationship between user_cards and card_catalog

4. **Code Review**:
   - Review any other code that might reference these tables
   - Ensure consistent column naming throughout the app
