import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { analyzeFunctionSecurity } from './helpers/security_inventory.js';

const root = process.cwd();
const migrations = readdirSync(join(root, 'supabase/migrations')).filter((name) => name.endsWith('.sql')).sort()
  .map((name) => ({ path: name, sql: readFileSync(join(root, 'supabase/migrations', name), 'utf8') }));

test('every final authenticated or PUBLIC definer is active-gated or narrowly exempt', () => {
  const exemptions = new Set([
    'public.current_user_is_active()',
    'public.current_user_access_profile_state()',
    'public.join_waitlist(text,text,text,text,text,text,text,text,text,boolean,text)',
    // One-time enrichment-token workflow; it does not act as an authenticated user.
    'public.enrich_waitlist(text,text,text,text,text,text,text[],boolean)',
  ]);
  const unsafe = analyzeFunctionSecurity(migrations).filter((fn) =>
    fn.definer && (fn.publicExecute || fn.authenticatedExecute) &&
    !/public\.current_user_is_active\s*\(\s*\)/i.test(fn.body) && !exemptions.has(fn.key));
  assert.deepEqual(unsafe.map((fn) => fn.key), []);
});

test('analyzer rejects a newly exposed ungated definer and accepts revoke or active gate', () => {
  const exposed = `create function public.synthetic() returns int language sql security definer as $$ select 1 $$;`;
  assert.equal(analyzeFunctionSecurity([{ sql: exposed }])[0].publicExecute, true);
  const revoked = analyzeFunctionSecurity([{ sql: `${exposed} revoke execute on function public.synthetic() from public, authenticated;` }]);
  assert.equal(revoked[0].publicExecute, false);
  const gated = analyzeFunctionSecurity([{ sql: `create function public.synthetic() returns boolean language sql security definer as $$ select public.current_user_is_active() $$;` }]);
  assert.match(gated[0].body, /current_user_is_active/);
});

test('durable auth-ban state uses token-fenced attempts and deletion create fencing', () => {
  const sql = migrations.map((item) => item.sql).join('\n').toLowerCase();
  assert.match(sql, /claim_token uuid/);
  assert.match(sql, /attempt_actor_id uuid/);
  assert.match(sql, /attempt_request_id uuid/);
  assert.match(sql, /complete_admin_auth_ban\([\s\S]*_claim_token uuid/);
  assert.match(sql, /if not found and[\s\S]*profile\.updated_at is distinct from _observed_updated_at/);
});
