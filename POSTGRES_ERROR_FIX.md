# PostgreSQL Error Fix: Statement Cycle Milestone Update

## Issue Description

An error was occurring when trying to get personalized movie recommendations:

```
PostgrestException(message: column card_catalog.is_active does not exist, code: 42703, details: , hint: null)
```

## Root Cause Analysis

The error was occurring due to an issue with how we were joining tables in our Supabase queries. Specifically:

1. We were using the inner join syntax `card:card_catalog!inner(...)` which was causing Supabase to apply filters to the joined table
2. The `is_active` filter was being applied to the `card_catalog` table instead of the `user_cards` table
3. The `card_catalog` table does not have an `is_active` column, causing the error

## Solution

We updated our queries to correctly handle card selection:
1. Changed to regular joins with `card:card_catalog(...)` syntax instead of inner joins
2. Kept the `is_active` filter on the `user_cards` table only
3. Removed dependency on card_catalog status - movie rule engine only depends on whether the card is active for the user

### Changes Made:

1. In the `_getUserMovieBenefits` method:
   ```dart
   // Changed from
   card:card_catalog!inner(
     id,
     card_name,
     network,
     bank
   )
   .eq('user_id', userId)
   .eq('is_active', true);
   
   // To
   card:card_catalog(
     id,
     card_name,
     network,
     bank
   )
   .eq('user_id', userId)
   .eq('is_active', true);
   ```

2. In the `_updateStatementCycleMilestones` method:
   ```dart
   // Changed from
   card:card_catalog!inner(id, card_name)
   .eq('user_id', userId)
   .eq('is_active', true);
   
   // To
   card:card_catalog(id, card_name)
   .eq('user_id', userId)
   .eq('is_active', true);
   ```

## Testing

The movie rule engine tests have been run successfully after making these changes, confirming that the error has been resolved.

## Learning

When using Supabase's query builder with PostgreSQL:
- Be careful with the foreign key join syntax
- Using `!inner` applies filters to the joined table
- When using `card:card_catalog!inner(...)` syntax, use `card.column_name` in filter conditions for columns in the joined table
- Always verify column existence in the tables being queried or filtered
- In this case, we've avoided using inner joins and only filter on columns we know exist
- The movie rule engine only needs to know if the card is active for the user, not its status in the catalog

## Benefits of the Fix

1. **Simpler Data Model**: We now only depend on the user's active cards, not catalog status
2. **Consistent Data Access**: Our queries align with the actual database schema
3. **Better Performance**: Regular joins can be more efficient in many cases
4. **Fewer Runtime Errors**: By using the correct column names and join types, we avoid PostgreSQL errors
