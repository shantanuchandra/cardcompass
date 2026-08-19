import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';

const migrationsDirectory = new URL('../../supabase/migrations/', import.meta.url);

async function adminFlagMigrationSql() {
  const files = (await readdir(migrationsDirectory))
    .filter((name) => name.endsWith('_add_admin_flag_to_public_users.sql'));
  assert.equal(files.length, 1, 'expected one admin-flag migration');
  return readFile(new URL(files[0], migrationsDirectory), 'utf8');
}

test('adds a deny-by-default admin flag and seeds the founder account', async () => {
  const sql = await adminFlagMigrationSql();

  assert.match(
    sql,
    /ALTER TABLE public\.users\s+ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false/i,
  );
  assert.match(
    sql,
    /UPDATE public\.users\s+SET is_admin = true\s+WHERE lower\(email\) = 'shantanu\.msp@gmail\.com'/i,
  );
});

test('prevents authenticated users from assigning the admin flag', async () => {
  const sql = await adminFlagMigrationSql();

  assert.match(
    sql,
    /REVOKE INSERT, UPDATE ON TABLE public\.users FROM authenticated/i,
  );

  const grants = [...sql.matchAll(
    /GRANT\s+(?:INSERT|UPDATE)\s*\(([^)]+)\)\s+ON\s+TABLE\s+public\.users\s+TO\s+authenticated/gi,
  )];
  assert.equal(grants.length, 2, 'expected restricted INSERT and UPDATE grants');
  for (const grant of grants) {
    assert.doesNotMatch(grant[1], /\bis_admin\b/i);
  }
});
