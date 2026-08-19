import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { discoverUserServiceGateways, hasEarlyActiveGate } from './helpers/security_inventory.js';

function walk(directory) {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? walk(path) : path.endsWith('.ts') ? [path] : [];
  });
}

test('every discovered user-JWT service-role gateway gates before privileged work', () => {
  const root = join(process.cwd(), 'supabase/functions');
  const files = walk(root).map((path) => ({ path: relative(root, path), source: readFileSync(path, 'utf8') }));
  const gateways = discoverUserServiceGateways(files);
  assert.deepEqual(gateways.map((item) => item.path).sort(), [
    'card-discovery/index.ts', 'feedback-submit/index.ts', 'gemini-proxy/index.ts', 'request-card-catalog-entry/index.ts',
  ]);
  assert.deepEqual(gateways.filter((item) => !hasEarlyActiveGate(item.source)).map((item) => item.path), []);
});

test('gateway analyzer rejects a new ungated user function and excludes admin internals', () => {
  const source = `const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"); await db.auth.getUser(token); await db.from("users").select();`;
  const discovered = discoverUserServiceGateways([{ path: 'new-user/index.ts', source }]);
  assert.equal(discovered.length, 1);
  assert.equal(hasEarlyActiveGate(source), false);
  assert.equal(discoverUserServiceGateways([{ path: 'admin-internal/index.ts', source }]).length, 0);
});
