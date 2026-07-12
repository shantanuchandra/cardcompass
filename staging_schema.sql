-- Create card benefits staging table for admin approval workflow
CREATE TABLE IF NOT EXISTS card_benefits_staging (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id UUID REFERENCES card_catalog(id) ON DELETE CASCADE,
  source_url TEXT,
  extracted_data JSONB NOT NULL,
  status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Grant appropriate permissions
GRANT ALL ON card_benefits_staging TO postgres;
GRANT ALL ON card_benefits_staging TO anon;
GRANT ALL ON card_benefits_staging TO authenticated;
GRANT ALL ON card_benefits_staging TO service_role;
