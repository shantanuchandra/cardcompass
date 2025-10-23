-- Migration: Make card_url nullable and add dedupe logic
-- This allows the RPC function to create cards with NULL card_url,
-- which we then immediately update with the actual URL

-- Step 1: Make card_url nullable
ALTER TABLE card_catalog 
ALTER COLUMN card_url DROP NOT NULL;

-- Step 2: Add a comment explaining why it's nullable
COMMENT ON COLUMN card_catalog.card_url IS 
'Product page URL for the credit card. Nullable to support 2-step creation process where card is first created via RPC, then URL is updated separately.';

-- Step 3: Add unique constraint on card_url to prevent duplicate URLs
-- This will help dedupe cards later
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_card_catalog_card_url_unique 
ON card_catalog(card_url) 
WHERE card_url IS NOT NULL;

-- Step 4: Add index on bank+card_name for faster lookups
CREATE INDEX IF NOT EXISTS idx_card_catalog_bank_card_name 
ON card_catalog(bank, card_name);

-- Step 5: Dedupe existing cards by finding duplicates based on card_url
-- This query identifies duplicates (run this first to see what would be affected):
-- SELECT card_url, COUNT(*) as count, array_agg(id) as ids, array_agg(bank || ' - ' || card_name) as cards
-- FROM card_catalog
-- WHERE card_url IS NOT NULL
-- GROUP BY card_url
-- HAVING COUNT(*) > 1;

-- Step 6: Function to merge duplicate cards based on card_url (keeps oldest entry)
CREATE OR REPLACE FUNCTION dedupe_card_catalog_by_url()
RETURNS TABLE(merged_count INT, details TEXT) AS $$
DECLARE
    duplicate_record RECORD;
    keep_id UUID;
    delete_ids UUID[];
    total_merged INT := 0;
BEGIN
    -- Find all duplicate card_url entries (only for non-NULL URLs)
    FOR duplicate_record IN 
        SELECT card_url, array_agg(id ORDER BY created_at ASC) as ids
        FROM card_catalog
        WHERE card_url IS NOT NULL
        GROUP BY card_url
        HAVING COUNT(*) > 1
    LOOP
        -- Keep the first ID (oldest entry)
        keep_id := duplicate_record.ids[1];
        delete_ids := duplicate_record.ids[2:];
        
        -- Update user_cards to point to the kept card
        UPDATE user_cards 
        SET catalog_card_id = keep_id
        WHERE catalog_card_id = ANY(delete_ids);
        
        -- Delete the duplicate cards
        DELETE FROM card_catalog WHERE id = ANY(delete_ids);
        
        total_merged := total_merged + array_length(delete_ids, 1);
        
        RAISE NOTICE 'Merged % duplicates for URL: %', array_length(delete_ids, 1), duplicate_record.card_url;
    END LOOP;
    
    RETURN QUERY SELECT total_merged, 'Deduplication complete' :: TEXT;
END;
$$ LANGUAGE plpgsql;

-- To run the dedupe, execute: SELECT * FROM dedupe_card_catalog_by_url();
