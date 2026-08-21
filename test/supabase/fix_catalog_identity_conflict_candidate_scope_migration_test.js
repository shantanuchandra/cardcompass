import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const migrationPath = path.join(
  process.cwd(),
  'supabase/migrations/20260821151500_fix_catalog_identity_conflict_candidate_scope.sql',
);

test('forward migration scopes raising network checks to the destination family', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(
    sql,
    /pg_get_functiondef\(\s*'public\.publish_card_catalog_identity\(uuid,uuid,uuid,text,jsonb,uuid,text,text\)'::regprocedure/i,
  );
  assert.match(sql, /WITH family_candidates AS MATERIALIZED/i);
  assert.match(
    sql,
    /FROM family_candidates AS conflict[\s\S]*card_catalog_effective_network/i,
  );
  assert.match(
    sql,
    /catalog_identity_conflict_candidate_scope_source_missing/i,
  );
  assert.match(
    sql,
    /has_function_privilege\([\s\S]*service_role[\s\S]*publish_card_catalog_identity/i,
  );
});
