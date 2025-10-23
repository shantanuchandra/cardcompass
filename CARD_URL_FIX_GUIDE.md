# Card URL Fix and Deduplication Guide

## Problem
The `card_catalog` table has a NOT NULL constraint on `card_url`, which prevents card creation when the URL cannot be automatically discovered. Additionally, duplicate cards may be created during testing.

## Solution

### Part 1: Make card_url Nullable

Run the SQL migration script to allow NULL values in card_url:

```bash
# Connect to your Supabase database and run:
psql -h <your-db-host> -U postgres -d postgres -f fix_card_url_nullable.sql
```

Or in Supabase SQL Editor, copy and paste the contents of `fix_card_url_nullable.sql`.

### Part 2: Application Behavior

After the schema change, when a card cannot be auto-discovered:

1. The application will print a clear message asking for manual URL input:
   ```
   ╔═══════════════════════════════════════════════════════════╗
   ║  📋 MANUAL URL INPUT REQUIRED                             ║
   ╚═══════════════════════════════════════════════════════════╝
   
   🏦 Bank: HDFC Bank
   💳 Card Variant: Regalia Gold
   📧 Email Subject: Your HDFC Bank - Regalia Gold Credit Card Statement
   
   Please provide the official product page URL for this card.
   Example: https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia-gold
   ```

2. A card will be created with a placeholder Google search URL
3. You can update the URL later via SQL:

```sql
UPDATE card_catalog 
SET card_url = 'https://actual-product-page-url.com'
WHERE bank = 'HDFC Bank' AND card_name = 'Regalia Gold';
```

### Part 3: Deduplicate Existing Cards

The migration script includes a dedupe function that:
- Finds cards with duplicate `card_url` values
- Keeps the oldest entry (first created)
- Updates all user_cards references to point to the kept card
- Deletes duplicate entries

To run deduplication:

```sql
-- First, see what duplicates exist:
SELECT card_url, COUNT(*) as count, 
       array_agg(id) as ids, 
       array_agg(bank || ' - ' || card_name) as cards
FROM card_catalog
WHERE card_url IS NOT NULL
GROUP BY card_url
HAVING COUNT(*) > 1;

-- Then run the dedupe function:
SELECT * FROM dedupe_card_catalog_by_url();
```

## Benefits

1. **No more sync failures** due to card_url constraint
2. **Manual URL input** for cards that can't be auto-discovered
3. **Automatic deduplication by URL** to clean up duplicate cards with same card_url
4. **Unique constraint on card_url** prevents future duplicates with same URL
5. **Performance indexes** on bank+card_name for faster lookups

## Migration Steps

1. **Backup your database** (always!)
2. Run `fix_card_url_nullable.sql` in Supabase SQL Editor
3. Check for duplicates:
   ```sql
   SELECT card_url, COUNT(*) 
   FROM card_catalog 
   WHERE card_url IS NOT NULL
   GROUP BY card_url 
   HAVING COUNT(*) > 1;
   ```
4. If duplicates exist, run dedupe:
   ```sql
   SELECT * FROM dedupe_card_catalog_by_url();
   ```
5. Restart your Flutter app and run a sync

## Example: Manually Adding Card URLs

After cards are created with placeholder URLs, update them:

```sql
-- HDFC Regalia Gold
UPDATE card_catalog 
SET card_url = 'https://www.hdfcbank.com/personal/pay/cards/credit-cards/regalia-gold'
WHERE bank = 'HDFC Bank' AND card_name = 'Regalia Gold';

-- IDFC Millennia
UPDATE card_catalog 
SET card_url = 'https://www.idfcfirstbank.com/credit-card/millennia-credit-card'
WHERE bank = 'IDFC First Bank' AND card_name = 'Millennia';

-- Axis Ace
UPDATE card_catalog 
SET card_url = 'https://www.axisbank.com/retail/cards/credit-card/ace-credit-card'
WHERE bank = 'Axis Bank' AND card_name = 'Ace';
```

## Verification

After running the migration and dedupe:

```sql
-- Check card_url is now nullable
\d+ card_catalog

-- Verify no URL duplicates remain
SELECT card_url, COUNT(*) as count
FROM card_catalog
WHERE card_url IS NOT NULL
GROUP BY card_url
HAVING COUNT(*) > 1;

-- Check all cards have URLs (or intentionally NULL)
SELECT bank, card_name, card_url, created_at
FROM card_catalog
ORDER BY created_at DESC;
```
