import test from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdtemp, rm } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import net from 'node:net';

const repoRoot = new URL('../../', import.meta.url);
const chromeCandidates = [
  process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);

async function firstExisting(paths) {
  for (const value of paths) {
    try { await access(value); return value; } catch { /* continue */ }
  }
  return null;
}
async function unusedPort() {
  const socket = net.createServer().listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const { port } = socket.address();
  await new Promise((resolve) => socket.close(resolve));
  return port;
}
async function devtoolsUrl(child) {
  let output = '';
  return await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Chrome timeout: ${output}`)), 10_000);
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
}
async function connect(url) {
  const socket = new WebSocket(url);
  await once(socket, 'open');
  let id = 0;
  const pending = new Map();
  const listeners = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (!message.id && message.method) {
      for (const resolve of listeners.get(message.method) ?? []) resolve(message.params);
      listeners.delete(message.method);
      return;
    }
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    message.error ? request.reject(new Error(message.error.message)) : request.resolve(message.result);
  });
  return {
    close: () => socket.close(),
    once(method) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`Missing CDP event: ${method}`)), 10_000);
        const wrapped = (value) => { clearTimeout(timer); resolve(value); };
        listeners.set(method, [...(listeners.get(method) ?? []), wrapped]);
      });
    },
    send(method, params = {}) {
      const requestId = ++id;
      return new Promise((resolve, reject) => {
        pending.set(requestId, { resolve, reject });
        socket.send(JSON.stringify({ id: requestId, method, params }));
      });
    },
  };
}
async function evaluate(cdp, expression) {
  const { result, exceptionDetails } = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (exceptionDetails) throw new Error(exceptionDetails.text);
  return result.value;
}
async function navigate(cdp, url, expectedPath, expectedSemantic) {
  const loaded = cdp.once('Page.loadEventFired');
  const navigation = await cdp.send('Page.navigate', { url });
  assert.ok(navigation.loaderId, `navigation must create a new document: ${url}`);
  await loaded;
  let state;
  let stable = 0;
  for (let i = 0; i < 200; i += 1) {
    state = await evaluate(cdp, `({
      path: location.pathname,
      search: location.search,
      title: document.title,
      flutter: Boolean(document.querySelector('flutter-view, flt-glass-pane')),
      semantics: [...document.querySelectorAll('[aria-label]')].map((node) => node.getAttribute('aria-label')).filter(Boolean).join(' | '),
      body: document.body?.innerText?.slice(0, 500) ?? ''
    })`);
    const evidence = `${state.semantics} | ${state.body}`;
    const settled = state.path === expectedPath && state.flutter &&
      state.title === 'CardCompass' && evidence.includes(expectedSemantic) &&
      evidence.includes('cardcompass-browser-fixture-only') &&
      !/page not found|no routes for location/i.test(evidence);
    stable = settled ? stable + 1 : 0;
    if (stable >= 3) return state;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Compiled Flutter app did not render ${expectedPath}: ${JSON.stringify(state)}`);
}

test('compiled test bootstrap proves auth redirects and protected PathUrlStrategy destinations', { timeout: 60_000 }, async (t) => {
  if (typeof WebSocket === 'undefined') return t.skip('Node WebSocket support is required');
  const chrome = await firstExisting(chromeCandidates);
  if (!chrome) return t.skip('Chrome/Chromium is required');
  try { await access(new URL('../../build/web/index.html', import.meta.url)); } catch {
    assert.fail('Run the release web build before this compiled-browser test');
  }

  const serverPort = await unusedPort();
  const server = spawn(process.execPath, ['server.js', String(serverPort)], { cwd: repoRoot, stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => server.kill());
  await once(server.stdout, 'data');

  const profile = await mkdtemp(join(tmpdir(), 'cardcompass-path-browser-'));
  const browser = spawn(chrome, ['--headless=new', '--disable-background-networking', '--disable-extensions', '--no-first-run', '--no-sandbox', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
  t.after(async () => { browser.kill(); await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); });
  const browserSocket = await devtoolsUrl(browser);
  const target = await fetch(`http://127.0.0.1:${new URL(browserSocket).port}/json/new?about%3Ablank`, { method: 'PUT' }).then((r) => r.json());
  const cdp = await connect(target.webSocketDebuggerUrl);
  t.after(() => cdp.close());
  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');

  const origin = `http://127.0.0.1:${serverPort}`;
  await navigate(cdp, `${origin}/app/login`, '/app/login', 'Continue with Google');
  for (const protectedPath of ['admin2', 'cards', 'settings']) {
    const redirected = await navigate(cdp, `${origin}/app/${protectedPath}`, '/app/login', 'Continue with Google');
    assert.equal(redirected.path.includes('/app/app'), false);
  }

  const directAdmin = await navigate(cdp, `${origin}/app/admin2?fixture_auth=true`, '/app/admin2', 'Action Inbox');
  assert.equal(directAdmin.path.includes('/app/app'), false);
  await navigate(cdp, `${origin}/app/cards?fixture_auth=true`, '/app/cards', 'My Cards');
  await navigate(cdp, `${origin}/app/settings?fixture_auth=true`, '/app/settings', 'Settings');
  const legacy = await navigate(cdp, `${origin}/app/admin/catalog-review?discarded=true`, '/app/admin2', 'Card Data');
  assert.equal(legacy.search, '?section=card-data');
  assert.equal((await fetch(`${origin}/app/admin2.js`)).status, 404);
  assert.equal((await fetch(`${origin}/app/missing.js`)).status, 404);
});
