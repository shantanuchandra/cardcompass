-- No-op migration.
--
-- The Supabase CLI created and applied this timestamp while an earlier
-- `supabase migration new add_emails_table` call hung without printing output.
-- Keep this file so local migration history matches the remote project.
--
-- The actual emails table DDL lives in:
--   20260711080122_add_emails_table.sql

select 1;
