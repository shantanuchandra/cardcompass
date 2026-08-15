import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');

test('production surfaces preserve the /app/ OAuth callback and redirect legacy login', async () => {
  const auth = await read('lib/features/auth/providers/auth_provider.dart');
  const supabaseConfig = await read('supabase/config.toml');
  const server = await read('server.js');
  const workflow = await read('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml');
  assert.match(auth, /oauthRedirectUri/);
  assert.match(auth, /\/app\//);
  assert.match(supabaseConfig, /https:\/\/cardcompass\.in\/app\//);
  assert.match(server, /\/login/);
  assert.match(server, /\/app\/#\/login/);
  assert.doesNotMatch(workflow, /cp\s+-r\s+login/);
});

test('homepage CTAs, resources, and deploy exclusions match the public surface', async () => {
  const html = await read('landing/index.html');
  const css = await read('landing/style.css');
  const workflow = await read('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml');
  const robots = await read('landing/robots.txt');
  for (const cta of html.matchAll(/<a\b[^>]*class="[^"]*button[^"]*"[^>]*data-waitlist-entry[^>]*>/g)) {
    assert.match(cta[0], /href="#apply"/);
  }
  assert.match(html, /Resources/i);
  assert.match(html, /\/tools\/best-card\//);
  assert.match(css, /#apply\s*\{[^}]*scroll-margin-top/i);
  assert.match(workflow, /rm\s+-f\s+deploy\/design-system\.html\s+deploy\/design-system\.css/);
  assert.match(robots, /Disallow:\s*\/design-system/i);
});

test('deployment validates public keys, runs tests before upload, and sets CSP', async () => {
  const workflow = await read('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml');
  const envWriter = await read('scripts/write-landing-env.mjs');
  const config = JSON.parse(await read('staticwebapp.config.json'));
  assert.match(workflow, /node --test test\/landing\/\*\.test\.js test\/gtm\/\*\.test\.js/);
  assert.match(workflow, /flutter analyze/);
  assert.match(workflow, /flutter test test\/core test\/features/);
  assert.match(workflow, /test\/supabase\/\*_test\.js/);
  assert.match(envWriter, /sb_secret_/);
  assert.match(envWriter, /service_role/);
  assert.match(envWriter, /role/);
  assert.ok(config.globalHeaders['Content-Security-Policy']);
});

test('public analytics has no mutable tracker script and documents diagnostic goals', async () => {
  const script = await read('landing/script.js');
  const scorecard = await read('docs/gtm/operating-scorecard.md');
  const playbook = await read('docs/gtm/founder-led-playbook.md');
  assert.doesNotMatch(script, /plausible\.io\/js\/script\.js/);
  assert.match(scorecard, /enriched_at/i);
  assert.match(scorecard, /Enrichment Submitted[^\n]*diagnostic/i);
  assert.match(playbook, /Plausible[\s\S]*custom event goals/i);
  assert.match(playbook, /external launch gate/i);
});

test('database contracts preserve legacy ambiguity and pending marketing consent', async () => {
  const migration = await read('supabase/migrations/20260815073740_secure_waitlist_operator_workflow.sql');
  const upgrade = await read('test/supabase/waitlist_upgrade_path_test.sql');
  assert.match(migration, /legacy-6-plus/);
  assert.doesNotMatch(migration, /WHEN '6\+' THEN '7\+'/);
  assert.match(migration, /marketing_consent_requested_at/);
  assert.match(migration, /p_website/);
  assert.match(migration, /waitlist_public_attempts/);
  assert.match(migration, /attempt_count[^\n]*> 5|v_attempt_count > 5/);
  assert.match(migration, /update_waitlist_operator/);
  assert.match(migration, /TO service_role/);
  assert.doesNotMatch(migration, /WHEN p_marketing_consent THEN COALESCE\(marketing_consent_at/);
  assert.doesNotMatch(migration, /marketing_consent_at IS NOT NULL THEN 5/);
  assert.match(upgrade, /legacy-6-plus/);
});

test('incomplete Edge abuse protection is an explicit launch-blocking contract', async () => {
  const contract = await read('supabase/functions/waitlist-public/README.md');
  const entrypoint = await read('supabase/functions/waitlist-public/index.ts');
  const config = await read('supabase/config.toml');
  assert.match(contract, /TURNSTILE_SECRET_KEY/);
  assert.match(contract, /never store or log raw IP/i);
  assert.match(contract, /revoke direct browser execution of `join_waitlist`/i);
  assert.match(contract, /production launch remains blocked/i);
  assert.match(config, /\[functions\.waitlist-public\]/);
  assert.match(config, /verify_jwt\s*=\s*false/);
  assert.match(entrypoint, /status:\s*503/);
  assert.doesNotMatch(entrypoint, /SUPABASE_SERVICE_ROLE_KEY|TURNSTILE_SECRET_KEY/);
});

test('PAN migration promises logical schema removal without full-table overwrite', async () => {
  const migration = await read('supabase/migrations/20260815090910_remove_legacy_card_secrets.sql');
  const copy = `${await read('landing/privacy/index.html')} ${await read('landing/data-security/index.html')} ${await read('landing/llm.txt')}`;
  assert.doesNotMatch(migration, /UPDATE public\.user_cards[\s\S]*SET card_number = NULL/);
  assert.match(migration, /backup|WAL/i);
  assert.match(copy, /logical active-schema removal/i);
  assert.match(copy, /backup|WAL/i);
  assert.doesNotMatch(copy, /intended to erase/i);
});
