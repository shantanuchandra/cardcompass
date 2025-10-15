# Card Catalog Schema Standardization

## Issue Fixed

The project was experiencing a persistent error in the Movie Ticket Rule Engine:
```
PostgrestException(message: column card_catalog.is_active does not exist, code: 42703...)
```

This error was occurring because of inconsistencies in the database schema where different SQL files defined the `card_catalog` table differently - some using `is_active` and others using `is_discontinued`.

## Root Cause Analysis

1. **Schema Inconsistency**: The `card_catalog` table was defined inconsistently across multiple SQL files:
   - In some places it used `is_active` (boolean)
   - In others it used `is_discontinued` (boolean)

2. **Migration Issue**: The `fix_credit_cards_table.sql` file had an inconsistent INSERT statement that referenced `is_active` in a table that used `is_discontinued` as the column name.

3. **Documentation Discrepancy**: The example schema in the Dart documentation showed `is_active` while the actual database schema used `is_discontinued`.

## Solution Implemented

1. **Schema Standardization**: Created a new SQL script `standardize_card_catalog_schema.sql` that:
   - Ensures the `card_catalog` table uses `is_discontinued` (not `is_active`)
   - Migrates data from `is_active` to `is_discontinued` if both exist
   - Adds appropriate indexes for performance optimization
   - Performs verification to confirm the standardization was successful

2. **Fixed Migration Script**: Corrected the INSERT statement in `fix_credit_cards_table.sql` to use `is_discontinued` instead of `is_active`.

3. **Added Debug Logging**: Enhanced the Movie Rule Engine service with detailed debug logging to:
   - Trace the execution flow in the `optimizeMovieTicketPurchase` method
   - Log database queries and their results in the `_getUserMovieBenefits` method
   - Capture and display detailed error information with stack traces

## How to Apply the Fix

1. Run the standardization SQL script:
   ```bash
   psql -U <username> -d <database> -f standardize_card_catalog_schema.sql
   ```

2. Restart the application and observe the debug logs to verify the error is resolved.

3. If the error persists, the enhanced debug logging will provide detailed information to pinpoint the exact source of the issue.

## Prevention Measures

To prevent similar schema inconsistencies in the future:

1. **Single Source of Truth**: Maintain a single, authoritative schema definition file that all other parts of the application reference.

2. **Automated Schema Validation**: Implement a CI process that validates schema consistency across all SQL files.

3. **Schema Documentation**: Keep schema documentation up-to-date when changes are made to the database structure.

4. **Migration Testing**: Test all migration scripts in a sandbox environment before applying them to production.

## Status

✅ Fixed inconsistency in SQL scripts
✅ Added standardization script
✅ Enhanced debug logging
✅ Updated documentation

The Movie Ticket Rule Engine now correctly depends only on `user_cards.is_active` for determining active cards, not on `card_catalog` status.
