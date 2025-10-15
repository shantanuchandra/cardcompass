	-- CardCompass - Card Catalog Schema Standardization
-- Generated on: July 6, 2025

-- Standardize card_catalog schema and relationships

-- 1. Ensure tables exist with proper structure
CREATE TABLE IF NOT EXISTS card_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_name TEXT NOT NULL,
  bank TEXT NOT NULL,
  network TEXT NOT NULL,
  card_type TEXT NOT NULL,
  annual_fee DECIMAL(10,2),
  is_discontinued BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  catalog_card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE,
  card_number TEXT,
  expiry_date DATE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Ensure all card_catalog entries have proper is_discontinued flag
UPDATE card_catalog
SET is_discontinued = FALSE
WHERE is_discontinued IS NULL;

-- 3. Update references in transactions table
ALTER TABLE transactions
DROP CONSTRAINT IF EXISTS transactions_card_id_fkey;

ALTER TABLE transactions
ADD CONSTRAINT transactions_card_id_fkey
FOREIGN KEY (user_card_id) REFERENCES user_cards(id) ON DELETE SET NULL;

-- 4. Update references in statements table
ALTER TABLE statements
DROP CONSTRAINT IF EXISTS statements_card_id_fkey;

ALTER TABLE statements
ADD CONSTRAINT statements_card_id_fkey
FOREIGN KEY (user_card_id) REFERENCES user_cards(id) ON DELETE CASCADE;

-- 5. Update references in card_benefits table
ALTER TABLE card_benefits
DROP CONSTRAINT IF EXISTS card_benefits_card_id_fkey;

ALTER TABLE card_benefits
ADD CONSTRAINT card_benefits_card_id_fkey
FOREIGN KEY (card_id) REFERENCES card_catalog(id) ON DELETE CASCADE;

-- 6. Enable RLS on card_catalog
ALTER TABLE card_catalog ENABLE ROW LEVEL SECURITY;

-- 7. Create policies for card_catalog
CREATE POLICY "Allow authenticated users to read cards" ON card_catalog
FOR SELECT
TO authenticated
USING (TRUE);

CREATE POLICY "Allow service role to manage cards" ON card_catalog
FOR ALL
TO service_role
USING (TRUE);

-- Print completion message
DO $$
BEGIN
  RAISE NOTICE 'Schema standardization completed: card_catalog table now uses is_discontinued consistently';
END $$;
