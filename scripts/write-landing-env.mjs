import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

function decodeJwtPayload(key) {
  const parts = key.split('.');
  if (parts.length !== 3) return null;
  try { return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')); } catch { return null; }
}

export function assertPublicSupabaseKey(key) {
  if (typeof key !== 'string' || !key) throw new Error('SUPABASE_ANON_KEY is required.');
  if (key.startsWith('sb_secret_')) throw new Error('Supabase secret keys are server-only.');
  if (key.startsWith('sb_publishable_')) return key;
  const payload = decodeJwtPayload(key);
  if (payload?.role !== 'anon') throw new Error('Legacy Supabase JWT must have role=anon; service_role is forbidden.');
  return key;
}

export function buildPublicEnvModule(environment = process.env) {
  const url = new URL(environment.SUPABASE_URL || '');
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.supabase.co')) throw new Error('SUPABASE_URL must be an HTTPS Supabase project URL.');
  const key = assertPublicSupabaseKey(environment.SUPABASE_ANON_KEY);
  return `export const SUPABASE_URL = ${JSON.stringify(url.origin)};\nexport const SUPABASE_ANON = ${JSON.stringify(key)};\n`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const output = buildPublicEnvModule();
  const target = process.argv[2];
  if (target) await writeFile(target, output, { encoding: 'utf8', mode: 0o600 });
  else process.stdout.write(output);
}
