import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

test('forward migration enables RLS only after exact owner policies exist', async () => {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_enable_user_owned_table_rls.sql')
  );
  assert.equal(names.length, 1, 'exactly one user-owned RLS migration is required');
  assert.match(names[0], /^\d{14}_enable_user_owned_table_rls\.sql$/);
  const sql = await readFile(new URL(names[0], migrationsRoot), 'utf8');
  assert.match(sql, /ALTER TABLE public\.user_cards ENABLE ROW LEVEL SECURITY/i);
  assert.match(sql, /ALTER TABLE public\.statement_milestone_cache ENABLE ROW LEVEL SECURITY/i);
  assert.match(
    sql,
    /user_cards_policy[\s\S]*statement_milestone_user_policy[\s\S]*auth\.uid\(\)[\s\S]*user_id/i,
  );
  assert.match(sql, /relrowsecurity/i);
  assert.doesNotMatch(sql, /DISABLE ROW LEVEL SECURITY|DROP POLICY|TRUNCATE|DELETE FROM/i);
});
