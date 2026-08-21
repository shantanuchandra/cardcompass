import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const migrationsRoot = new URL('../../supabase/migrations/', import.meta.url);

async function migrationSql() {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_fix_ingestion_function_operator_precedence.sql')
  );
  assert.equal(names.length, 1, 'exactly one forward precedence migration is required');
  assert.match(names[0], /^\d{14}_fix_ingestion_function_operator_precedence\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

test('forward migration repairs installed Task6 and Task7 JSON extraction precedence', async () => {
  const sql = await migrationSql();
  assert.match(
    sql,
    /pg_get_functiondef\(\s*'public\.card_enrichment_pilot_evidence_is_qualified\(public\.card_catalog_enrichment_jobs,public\.card_benefits_staging\)'::regprocedure/i,
  );
  assert.match(
    sql,
    /pg_get_functiondef\(\s*'public\.publish_card_catalog_identity\(uuid,uuid,uuid,text,jsonb,uuid,text,text\)'::regprocedure/i,
  );
  assert.match(sql, /\(decision\.value->>''proposal_index''\)/i);
  assert.match(sql, /\(decision\.value->>''benefit_id''\)/i);
  assert.match(
    sql,
    /\(issuer_quarantine_anchor\.evidence->''quarantine_fence''->>''episode''\)/i,
  );
  assert.match(sql, /IF fixed_task6_definition IS NOT DISTINCT FROM task6_definition/i);
  assert.match(sql, /IF fixed_task7_definition IS NOT DISTINCT FROM task7_definition/i);
  assert.match(sql, /EXECUTE fixed_task6_definition[\s\S]*EXECUTE fixed_task7_definition/i);
  assert.match(
    sql,
    /has_function_privilege\(\s*'service_role'[\s\S]*has_function_privilege\(\s*'authenticated'/i,
  );
});
