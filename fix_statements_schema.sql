-- Fix statements table schema to match the application expectations
-- The app expects 'user_card_id' but the database has 'card_id'

-- Step 1: Add the user_card_id column if it doesn't exist
ALTER TABLE statements 
ADD COLUMN IF NOT EXISTS user_card_id UUID REFERENCES user_cards(id) ON DELETE CASCADE;

-- Step 2: Create an index for the new column
CREATE INDEX IF NOT EXISTS idx_statements_user_card_id ON statements(user_card_id);

-- Step 3: For existing data, try to map card_id to user_card_id if possible
-- This is a one-time migration to fix existing data
UPDATE statements 
SET user_card_id = (
    SELECT uc.id 
    FROM user_cards uc 
    WHERE uc.catalog_card_id = statements.card_id 
    AND uc.user_id = statements.user_id 
    LIMIT 1
)
WHERE user_card_id IS NULL AND card_id IS NOT NULL;

-- Step 4: Add a policy for the new column
CREATE POLICY IF NOT EXISTS "Users can view own statements by user_card" ON statements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_cards uc 
      WHERE uc.id = statements.user_card_id 
      AND uc.user_id = auth.uid()
    )
  );

-- Print completion message
DO $$
BEGIN
  RAISE NOTICE 'Statements table schema fixed:';
  RAISE NOTICE '- Added user_card_id column referencing user_cards table';
  RAISE NOTICE '- Created index for performance';
  RAISE NOTICE '- Migrated existing data where possible';
  RAISE NOTICE '- Added RLS policy for new column';
END $$;
