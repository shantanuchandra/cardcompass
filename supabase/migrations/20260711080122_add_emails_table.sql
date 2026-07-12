-- Email records are used by the Gmail sync pipeline for dedupe and processing
-- status tracking. The table existed in the original Supabase backup, but was
-- missing from schema.sql and from the first recovery migration.
--
-- Note: the old backup had emails.statement_id as UUID. The current recovered
-- statements.id column is TEXT, and EmailRepository.updateEmailStatus() passes
-- statement IDs as strings, so this migration uses TEXT to match the current
-- app/schema contract.

CREATE TABLE IF NOT EXISTS emails (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  email_id TEXT NOT NULL,
  subject TEXT,
  sender TEXT,
  received_date TIMESTAMP WITH TIME ZONE,
  has_attachments BOOLEAN DEFAULT false,
  processed BOOLEAN DEFAULT false,
  bank_detected TEXT,
  statement_id TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_emails_user_id ON emails(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_emails_user_email_id ON emails(user_id, email_id);
CREATE INDEX IF NOT EXISTS idx_emails_user_received_date ON emails(user_id, received_date DESC);
CREATE INDEX IF NOT EXISTS idx_emails_unprocessed ON emails(user_id, processed) WHERE processed = false;

ALTER TABLE emails ENABLE ROW LEVEL SECURITY;

CREATE POLICY emails_policy ON emails
  FOR ALL TO authenticated
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON emails TO authenticated;
