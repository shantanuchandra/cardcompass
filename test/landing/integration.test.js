import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
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
  assert.match(html, /href="#waitlist"/);
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

test('local server serves deploy-root landing routes and blocks traversal', async (t) => {
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

  for (const route of ['/', '/style.css', '/privacy/', '/tools/tools.js', '/llms.txt', '/img/social-preview.png']) {
    const response = await fetch(`http://127.0.0.1:${port}${route}`);
    assert.equal(response.status, 200, route);
  }

  const traversal = await fetch(`http://127.0.0.1:${port}/..%2F.env`);
  assert.ok([400, 403, 404].includes(traversal.status));
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
      SUPABASE_ANON_KEY: `key'; globalThis.compromised = true; //`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  const [exitCode] = await once(child, 'exit');

  assert.equal(exitCode, 0);
  assert.equal(stdout, `export const SUPABASE_URL = "https://project.supabase.co";\nexport const SUPABASE_ANON = "key'; globalThis.compromised = true; //";\n`);

  const workflow = await readFile(new URL('.github/workflows/azure-static-web-apps-thankful-moss-0b0214000.yml', repoRoot), 'utf8');
  assert.match(workflow, /write-landing-env\.mjs deploy\/env\.js/);
});
