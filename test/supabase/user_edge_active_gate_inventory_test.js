import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const userGateways = [
  'card-discovery',
  'request-card-catalog-entry',
  'gemini-proxy',
];

test('every user JWT gateway using service role applies the shared active-profile gate', () => {
  for (const name of userGateways) {
    const source = readFileSync(`supabase/functions/${name}/index.ts`, 'utf8');
    assert.match(source, /from "\.\.\/_shared\/active_profile\.ts"/);
    assert.match(source, /await requireActiveProfile\(db|await requireActiveProfile\(supabase/);
  }
});
