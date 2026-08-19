import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const configUrl = new URL('../../deno.json', import.meta.url);

test('root Deno config resolves Admin Operator test dependencies', async () => {
  const config = JSON.parse(await readFile(configUrl, 'utf8'));

  assert.equal(config.nodeModulesDir, 'auto');
  assert.notEqual(config.lock, false);
  assert.equal(config.imports?.['@std/assert'], 'jsr:@std/assert@1');
  assert.equal(
    config.imports?.['@supabase/supabase-js'],
    'npm:@supabase/supabase-js@2.95.0',
  );
});

test('root Deno lock pins Admin Operator dependencies', async () => {
  const lockUrl = new URL('../../deno.lock', import.meta.url);
  const lock = JSON.parse(await readFile(lockUrl, 'utf8'));

  assert.equal(lock.version, '5');
  assert.ok(lock.specifiers?.['jsr:@std/assert@1']);
  assert.ok(lock.specifiers?.['npm:@supabase/supabase-js@2.95.0']);
});
