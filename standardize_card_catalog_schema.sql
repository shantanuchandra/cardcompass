-- CardCompass - Standardize Card Catalog Schema
-- Generated on: July 4, 2025
-- This script ensures the card_catalog table uses is_discontinued (not is_active)
-- and fixes any inconsistencies in the database schema

-- 1. Check if card_catalog table exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'card_catalog') THEN
        RAISE NOTICE 'card_catalog table does not exist, creating it with standardized schema';
        
        -- Create the table with the standardized schema
        CREATE TABLE card_catalog (
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
        
        RAISE NOTICE 'card_catalog table created with standardized schema';
    ELSE
        RAISE NOTICE 'card_catalog table already exists, checking for schema inconsistencies';
    END IF;
END $$;

-- 2. Check if is_active column exists and needs to be migrated to is_discontinued
DO $$
DECLARE
    has_is_active BOOLEAN;
    has_is_discontinued BOOLEAN;
BEGIN
    -- Check if is_active column exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'card_catalog' AND column_name = 'is_active'
    ) INTO has_is_active;
    
    -- Check if is_discontinued column exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'card_catalog' AND column_name = 'is_discontinued'
    ) INTO has_is_discontinued;
    
    IF has_is_active AND has_is_discontinued THEN
        -- Both columns exist, migrate data from is_active to is_discontinued
        RAISE NOTICE 'Both is_active and is_discontinued exist, migrating data...';
        
        UPDATE card_catalog SET is_discontinued = NOT is_active;
        ALTER TABLE card_catalog DROP COLUMN is_active;
        
        RAISE NOTICE 'Successfully migrated data from is_active to is_discontinued and dropped is_active column';
    ELSIF has_is_active AND NOT has_is_discontinued THEN
        -- Only is_active exists, rename it to is_discontinued
        RAISE NOTICE 'Only is_active exists, adding is_discontinued and migrating data...';
        
        ALTER TABLE card_catalog ADD COLUMN is_discontinued BOOLEAN DEFAULT false;
        UPDATE card_catalog SET is_discontinued = NOT is_active;
        ALTER TABLE card_catalog DROP COLUMN is_active;
        
        RAISE NOTICE 'Successfully migrated is_active to is_discontinued';
    ELSIF NOT has_is_active AND NOT has_is_discontinued THEN
        -- Neither column exists, add is_discontinued
        RAISE NOTICE 'Neither is_active nor is_discontinued exists, adding is_discontinued...';
        
        ALTER TABLE card_catalog ADD COLUMN is_discontinued BOOLEAN DEFAULT false;
        
        RAISE NOTICE 'Successfully added is_discontinued column';
    ELSE
        RAISE NOTICE 'Schema is already standardized with is_discontinued column';
    END IF;
END $$;

-- 3. Add appropriate indexes for performance
DO $$
BEGIN
    -- Add index for is_discontinued if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE tablename = 'card_catalog' AND indexname = 'idx_card_catalog_is_discontinued'
    ) THEN
        CREATE INDEX idx_card_catalog_is_discontinued ON card_catalog(is_discontinued);
        RAISE NOTICE 'Created index on is_discontinued column';
    ELSE
        RAISE NOTICE 'Index on is_discontinued column already exists';
    END IF;
END $$;

-- 4. Final verification
DO $$
DECLARE
    correct_schema BOOLEAN;
BEGIN
    -- Verify schema is correct
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'card_catalog' AND column_name = 'is_discontinued'
    ) INTO correct_schema;
    
    IF correct_schema THEN
        RAISE NOTICE 'VERIFICATION SUCCESSFUL: card_catalog table now has standardized schema with is_discontinued column';
    ELSE
        RAISE NOTICE 'VERIFICATION FAILED: card_catalog schema standardization unsuccessful';
    END IF;
END $$;
