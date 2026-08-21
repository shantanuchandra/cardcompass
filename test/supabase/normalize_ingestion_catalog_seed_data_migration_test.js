import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const migrationPath = path.join(
  process.cwd(),
  'supabase/migrations/20260821160000_normalize_ingestion_catalog_seed_data.sql',
);

test('forward migration normalizes safe catalog ingestion identities and locks the unused legacy table', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(
    sql,
    /UPDATE public\.card_catalog[\s\S]*SET card_type = 'credit'[\s\S]*lower\(btrim\(card_type\)\) = 'credit'/i,
  );
  assert.doesNotMatch(
    sql,
    /SET bank = 'Kotak Bank'/i,
    'a conflicting issuer identity must go through catalog review, not a blind update',
  );
  assert.match(
    sql,
    /ALTER TABLE public\.card_benefits ENABLE ROW LEVEL SECURITY/i,
  );
  assert.match(
    sql,
    /REVOKE ALL ON TABLE public\.card_benefits FROM PUBLIC, anon, authenticated/i,
  );
  assert.match(
    sql,
    /INSERT INTO public\.admin_runtime_controls[\s\S]*'benefit_enrichment_scheduled'[\s\S]*true[\s\S]*ON CONFLICT \(control_key\) DO UPDATE[\s\S]*is_paused = true/i,
  );
  assert.match(
    sql,
    /DO \$catalog_ingestion_normalization_apply\$[\s\S]*noncanonical credit card_type remains[\s\S]*legacy card_benefits RLS is disabled/i,
  );
});
