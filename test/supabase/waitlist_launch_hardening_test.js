import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationUrl = new URL('../../supabase/migrations/20260815095331_harden_waitlist_launch_contract.sql', import.meta.url);

test('waitlist launch migration keeps consent pending and rate-limits without raw IP', async () => {
  const sql = await readFile(migrationUrl, 'utf8');
  assert.match(sql, /marketing_consent_requested_at/i);
  assert.match(sql, /marketing_consent_at\s*=\s*NULL/i);
  assert.match(sql, /waitlist_public_attempts/i);
  assert.match(sql, /digest\(v_email,\s*'sha256'\)/i);
  assert.doesNotMatch(sql, /inet_client_addr|raw_ip|ip_address/i);
  assert.match(sql, /p_website/i);
  assert.match(sql, /v_attempts\s*<=\s*5/i);
});

test('operator mutation is a narrow service-role-only function', async () => {
  const sql = await readFile(migrationUrl, 'utf8');
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.update_waitlist_operator/i);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.update_waitlist_operator[\s\S]*FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.update_waitlist_operator[\s\S]*TO service_role/i);
  assert.match(sql, /REVOKE UPDATE ON TABLE public\.waitlist FROM service_role/i);
});

test('operator ranking excludes consent and requires legacy six-plus requalification', async () => {
  const sql = await readFile(migrationUrl, 'utf8');
  const view = sql.slice(sql.indexOf('CREATE VIEW public.operator_waitlist_ranked'));
  assert.match(view, /legacy-6-plus/i);
  assert.match(view, /needs_requalification/i);
  assert.doesNotMatch(view, /marketing_consent_at[^\n]*THEN\s+5/i);
});
