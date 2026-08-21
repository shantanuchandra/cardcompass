import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const migrationsRoot = new URL('supabase/migrations/', repoRoot);

async function hardeningMigration() {
  const names = (await readdir(migrationsRoot)).filter((name) => name.endsWith('_remove_legacy_card_secrets.sql'));
  assert.equal(names.length, 1, 'one forward-only card-secret hardening migration is required');
  return {
    name: names[0],
    sql: await readFile(new URL(names[0], migrationsRoot), 'utf8'),
  };
}

test('forward migration revokes and removes every PAN or expiry RPC overload before dropping storage', async () => {
  const { name, sql } = await hardeningMigration();
  assert.match(name, /^\d{14}_remove_legacy_card_secrets\.sql$/);

  const unsafeSignatures = [
    /associate_user_with_card\s*\(\s*uuid\s*,\s*uuid\s*,\s*text\s*,\s*text\s*,\s*text\s*,\s*text\s*,\s*numeric\s*,\s*integer\s*,\s*integer\s*\)/i,
    /update_user_card\s*\(\s*uuid\s*,\s*uuid\s*,\s*text\s*,\s*numeric\s*,\s*text\s*,\s*text\s*,\s*integer\s*,\s*integer\s*\)/i,
    /get_user_cards\s*\(\s*uuid\s*\)/i,
  ];
  for (const signature of unsafeSignatures) {
    assert.match(sql, new RegExp(`REVOKE[\\s\\S]*${signature.source}`, 'i'));
    assert.match(sql, new RegExp(`DROP FUNCTION[\\s\\S]*${signature.source}`, 'i'));
  }

  assert.doesNotMatch(sql, /UPDATE\s+public\.user_cards[\s\S]*card_number\s*=\s*NULL/i);
  assert.match(sql, /logical active schema|logical active-schema/i);
  assert.match(sql, /backups?\s+or\s+WAL/i);
  assert.match(sql, /DROP COLUMN\s+IF EXISTS\s+card_number/i);
  assert.match(sql, /DROP COLUMN\s+IF EXISTS\s+expiry_date/i);
  assert.doesNotMatch(sql, /CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION[\s\S]*_(?:card_number|expiry_date)\b/i);
});

test('canonical schema no longer declares PAN or card expiry storage', async () => {
  const schema = await readFile(new URL('schema.sql', repoRoot), 'utf8');
  const userCards = schema.match(
    /CREATE TABLE (?:IF NOT EXISTS )?(?:public\.)?user_cards\s*\(([\s\S]*?)\n\);/i,
  )?.[1];

  assert.ok(userCards, 'canonical user_cards table is required');
  assert.doesNotMatch(userCards, /\bcard_number\b/i);
  assert.doesNotMatch(userCards, /\bexpiry_date\b/i);
});

test('upgrade-path ownership assertion follows PostgreSQL WITH CHECK fallback semantics', async () => {
  const sql = await readFile(new URL('test/supabase/card_data_hardening_upgrade_path_test.sql', repoRoot), 'utf8');

  assert.match(sql, /COALESCE\s*\(\s*with_check\s*,\s*qual\s*\)/i);
});
