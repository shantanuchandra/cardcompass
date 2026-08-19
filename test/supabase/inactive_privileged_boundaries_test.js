import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readdirSync } from 'node:fs';

const root = process.cwd();
const hardening = [
  'supabase/migrations/20260819090300_admin_customer_ops.sql',
  'supabase/migrations/20260819132439_harden_inactive_customer_boundaries.sql',
].map((path) => readFileSync(join(root, path), 'utf8')).join('\n');

const authenticatedDefiners = [
  'get_user_transactions',
  'reconcile_imported_statement_payment',
  'apply_statement_payment',
  'private.reset_my_cardcompass_data',
  'claim_my_admin_operation_request',
  'renew_my_admin_operation_request',
  'complete_my_admin_operation_request',
];

test('authenticated function grants stay in the reviewed inventory', () => {
  const names = new Set();
  for (const file of readdirSync(join(root, 'supabase/migrations')).filter((name) => name.endsWith('.sql'))) {
    const sql = readFileSync(join(root, 'supabase/migrations', file), 'utf8');
    for (const match of sql.matchAll(/grant\s+(?:all|execute)\s+on\s+function\s+((?:public|private)\.[a-z0-9_]+)[^;]*?\s+to\s+[^;]*?\bauthenticated\b/gi)) {
      names.add(match[1].toLowerCase());
    }
  }
  assert.deepEqual([...names].sort(), [
    'private.reset_my_cardcompass_data', 'public.add_transaction',
    'public.apply_statement_payment', 'public.associate_card_with_user',
    'public.associate_user_with_card', 'public.claim_my_admin_operation_request',
    'public.complete_my_admin_operation_request', 'public.create_credit_card',
    'public.create_or_get_card_catalog', 'public.current_user_access_profile_state',
    'public.current_user_is_active', 'public.enrich_waitlist',
    'public.get_card_catalog', 'public.get_user_cards',
    'public.get_user_transactions', 'public.insert_transaction_with_card_id',
    'public.join_waitlist', 'public.reconcile_imported_statement_payment',
    'public.remove_user_card', 'public.renew_my_admin_operation_request',
    'public.reset_my_cardcompass_data', 'public.submit_card_catalog_request',
    'public.update_user_card',
  ]);
});

test('every authenticated definer path has an explicit active-profile boundary', () => {
  for (const name of authenticatedDefiners) {
    assert.match(hardening, new RegExp(`-- active-boundary: ${name.replace('.', '\\.')}(?:\\n|\\r)`));
  }
  assert.match(hardening, /alter function public\.get_user_transactions[\s\S]*security invoker/i);
  assert.match(hardening, /create or replace function private\.reset_my_cardcompass_data\(\)[\s\S]*public\.current_user_is_active\(\)/i);
  assert.match(hardening, /alter function public\.apply_statement_payment[\s\S]*security invoker/i);
  assert.match(hardening, /alter function public\.reconcile_imported_statement_payment[\s\S]*security invoker/i);
});

test('durable auth-ban state and deletion create fencing are authoritative', () => {
  assert.match(hardening, /create table public\.admin_auth_ban_requests/i);
  assert.match(hardening, /status text not null[\s\S]*pending[\s\S]*processing[\s\S]*completed[\s\S]*failed/i);
  assert.match(hardening, /create or replace function public\.claim_admin_auth_ban/i);
  assert.match(hardening, /create or replace function public\.complete_admin_auth_ban/i);
  assert.match(hardening, /grant execute on function public\.claim_admin_auth_ban[\s\S]*service_role/i);
  assert.match(hardening, /if not found and[\s\S]*profile\.updated_at is distinct from _observed_updated_at/i);
});
