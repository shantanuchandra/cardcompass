import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import net from 'node:net';

const repoRoot = new URL('../../', import.meta.url);

async function landingFile(relativePath) {
  return readFile(new URL(`landing/${relativePath}`, repoRoot), 'utf8');
}

async function unusedPort() {
  const socket = net.createServer();
  socket.listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const { port } = socket.address();
  await new Promise((resolve, reject) => socket.close((error) => error ? reject(error) : resolve()));
  return port;
}

test('homepage retains waitlist anchors and exposes the utility CTA apply target', async () => {
  const html = await landingFile('index.html');

  assert.match(html, /\bid="waitlist"/);
  assert.match(html, /\bid="apply"/);
  assert.doesNotMatch(html, /href="#waitlist"/);
  assert.match(html, /href="#apply"/);
});

test('public deploy-root documents and modules use root asset URLs', async () => {
  const documents = [
    'index.html',
    'privacy/index.html',
    'terms/index.html',
    'data-security/index.html',
    'recommendation-disclaimer/index.html',
    'tools/best-card/index.html',
    'tools/milestone-tracker/index.html',
    'tools/movie-offers/index.html',
    'script.js',
  ];

  for (const document of documents) {
    const contents = await landingFile(document);
    assert.doesNotMatch(contents, /(?:href|src|from|fetch\()\s*[=(]?['"]\/landing\//, `${document} still requests /landing/`);
  }
});

test('local server serves landing, app, and generated environment roots without legacy login', async (t) => {
  const appFixture = new URL('../../build/web/server-allowlist-test.txt', import.meta.url);
  await mkdir(new URL('../../build/web/', import.meta.url), { recursive: true });
  await writeFile(appFixture, 'app fixture', 'utf8');
  const port = await unusedPort();
  const child = spawn(process.execPath, ['server.js', String(port)], {
    cwd: new URL('../..', import.meta.url),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(async () => {
    child.kill();
    await rm(appFixture, { force: true });
  });
  await Promise.race([
    once(child.stdout, 'data'),
    new Promise((_, reject) => setTimeout(() => reject(new Error('server did not start')), 3000)),
  ]);

  for (const route of ['/', '/style.css', '/privacy/', '/tools/tools.js', '/llms.txt', '/img/social-preview.png', '/app/server-allowlist-test.txt', '/env.js']) {
    const response = await fetch(`http://127.0.0.1:${port}${route}`);
    assert.equal(response.status, 200, route);
  }

  assert.equal((await fetch(`http://127.0.0.1:${port}/login/`)).status, 404);

});

test('local server blocks dotfiles, repository internals, secrets, and traversal', async (t) => {
  const port = await unusedPort();
  const child = spawn(process.execPath, ['server.js', String(port)], {
    cwd: new URL('../..', import.meta.url),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  await Promise.race([
    once(child.stdout, 'data'),
    new Promise((_, reject) => setTimeout(() => reject(new Error('server did not start')), 3000)),
  ]);

  for (const route of [
    '/.env',
    '/.env.example',
    '/.git/config',
    '/dart_defines.json',
    '/schema.sql',
    '/supabase/migrations/20260815090910_remove_legacy_card_secrets.sql',
    '/package.json',
    '/pubspec.yaml',
    '/..%2F.env',
    '/%2e%2e%2fschema.sql',
  ]) {
    const response = await fetch(`http://127.0.0.1:${port}${route}`);
    assert.ok([403, 404].includes(response.status), `${route} returned ${response.status}`);
  }
});

test('Azure Static Web Apps config protects public pages without rewriting app assets', async () => {
  const config = JSON.parse(await readFile(new URL('staticwebapp.config.json', repoRoot), 'utf8'));

  assert.equal(config.globalHeaders['X-Content-Type-Options'], 'nosniff');
  assert.match(config.globalHeaders['Referrer-Policy'], /strict-origin/);
  assert.ok(config.routes.some((route) => route.route === '/app/*' && !route.rewrite && !route.redirect));
  assert.ok(!config.navigationFallback || config.navigationFallback.exclude.includes('/app/*'));
  assert.equal(config.responseOverrides['404'].rewrite, '/404.html');
});

test('deployment environment module serializes public Supabase values as inert JavaScript strings', async () => {
  const child = spawn(process.execPath, ['scripts/write-landing-env.mjs'], {
    cwd: new URL('../..', import.meta.url),
    env: {
      ...process.env,
      SUPABASE_URL: 'https://project.supabase.co',
      SUPABASE_ANON_KEY: 'sb_publishable_public_test_key',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  const [exitCode] = await once(child, 'exit');

  assert.equal(exitCode, 0);
  assert.equal(stdout, `export const SUPABASE_URL = "https://project.supabase.co";\nexport const SUPABASE_ANON = "sb_publishable_public_test_key";\n`);

  const workflow = await readFile(new URL('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml', repoRoot), 'utf8');
  assert.match(workflow, /write-landing-env\.mjs deploy\/env\.js/);
});

test('deployment environment rejects Supabase secret and service-role keys', async () => {
  const { assertPublicSupabaseKey } = await import('../../scripts/write-landing-env.mjs');
  assert.throws(() => assertPublicSupabaseKey('sb_secret_server_only'), /server-only/i);
  const header = Buffer.from('{}').toString('base64url');
  const payload = Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url');
  assert.throws(() => assertPublicSupabaseKey(`${header}.${payload}.signature`), /service_role/i);
  assert.equal(assertPublicSupabaseKey('sb_publishable_public_test_key'), 'sb_publishable_public_test_key');
});

test('browser dart defines contain public configuration only', async () => {
  const workflow = await readFile(new URL('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml', repoRoot), 'utf8');
  const definesStep = workflow.match(/- name: Write dart_defines\.json from secrets([\s\S]*?)(?=\n\s+- name:)/)?.[1];

  assert.ok(definesStep, 'dart defines workflow step is required');
  assert.match(definesStep, /SUPABASE_URL/);
  assert.match(definesStep, /SUPABASE_ANON_KEY/);
  assert.match(definesStep, /GOOGLE_CLIENT_ID/);
  assert.doesNotMatch(definesStep, /GEMINI_API_KEY|GROQ_API_KEY/);
});
