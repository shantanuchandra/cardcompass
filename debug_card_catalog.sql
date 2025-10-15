-- Add debugging for PostgreSQL card_catalog error
-- Created on: July 6, 2025

-- First, let's check if there are any references to is_active in card_catalog
DO $$
DECLARE
    is_active_exists BOOLEAN;
BEGIN
    -- Check if 'is_active' column exists in card_catalog
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'card_catalog'
        AND column_name = 'is_active'
    ) INTO is_active_exists;

    IF is_active_exists THEN
        RAISE NOTICE 'ERROR: is_active column exists in card_catalog table - this should be is_discontinued';
        
        -- Show current schema for card_catalog
        RAISE NOTICE 'Current card_catalog schema:';
        RAISE NOTICE '%', (SELECT string_agg(column_name || ' ' || data_type, ', ')
                         FROM information_schema.columns
                         WHERE table_name = 'card_catalog');
    ELSE
        RAISE NOTICE 'CORRECT: card_catalog table does not have is_active column';
    END IF;

    -- Check if 'is_discontinued' column exists in card_catalog
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'card_catalog'
        AND column_name = 'is_discontinued'
    ) INTO is_active_exists;

    IF is_active_exists THEN
        RAISE NOTICE 'CORRECT: is_discontinued column exists in card_catalog table';
    ELSE
        RAISE NOTICE 'ERROR: is_discontinued column does not exist in card_catalog table';
        
        -- Add is_discontinued column if missing
        ALTER TABLE card_catalog ADD COLUMN is_discontinued BOOLEAN DEFAULT FALSE;
        RAISE NOTICE 'Added missing is_discontinued column to card_catalog';
    END IF;
END $$;

-- Create a logging table to track card catalog queries that might be causing issues
CREATE TABLE IF NOT EXISTS debug_query_logs (
    id SERIAL PRIMARY KEY,
    query_text TEXT,
    error_message TEXT,
    source_location TEXT,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create a function to log queries and errors
CREATE OR REPLACE FUNCTION log_card_catalog_query(query_text TEXT, error_message TEXT, source_location TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO debug_query_logs (query_text, error_message, source_location)
    VALUES (query_text, error_message, source_location);
END;
$$ LANGUAGE plpgsql;

-- Add a trigger to log any queries with 'is_active' in them that reference card_catalog
-- Note: This would be a complex trigger in a real scenario - simplified for this example

-- Add an index to help with query performance
CREATE INDEX IF NOT EXISTS idx_card_catalog_id ON card_catalog(id);

COMMENT ON TABLE card_catalog IS 'Standardized catalog of credit cards with is_discontinued flag';
COMMENT ON COLUMN card_catalog.is_discontinued IS 'Flag indicating if card has been discontinued (not using is_active)';

-- Print completion message
DO $$
BEGIN
  RAISE NOTICE 'Debug setup complete. The system will track card_catalog queries for troubleshooting';
END $$;
