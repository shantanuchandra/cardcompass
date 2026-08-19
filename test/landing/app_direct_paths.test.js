import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import net from 'node:net';

async function unusedPort() {
  const socket = net.createServer().listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const { port } = socket.address();
  await new Promise((resolve) => socket.close(resolve));
  return port;
}

test('server supports real Flutter path URLs without masking files or unsafe paths', async (t) => {
  const fixture = await mkdtemp(join(tmpdir(), 'cardcompass-app-build-'));
  await mkdir(join(fixture, 'assets'));
  await writeFile(join(fixture, 'index.html'), '<!doctype html><title>fixture app</title>');
  await writeFile(join(fixture, 'main.dart.js'), '/* fixture asset */');
  const port = await unusedPort();
  const child = spawn(process.execPath, ['server.js', String(port)], {
    cwd: new URL('../../', import.meta.url),
    env: { ...process.env, CARDCOMPASS_APP_ROOT: fixture },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(async () => {
    child.kill();
    await rm(fixture, { recursive: true, force: true });
  });
  await once(child.stdout, 'data');
  const request = (path, options = {}) => fetch(`http://127.0.0.1:${port}${path}`, { redirect: 'manual', ...options });

  const canonical = await request('/app');
  assert.equal(canonical.status, 308);
  assert.equal(canonical.headers.get('location'), '/app/');
  for (const path of ['/app/', '/app/admin2', '/app/admin2?section=system', '/app/admin2/nested']) {
    const response = await request(path);
    assert.equal(response.status, 200, path);
    assert.match(await response.text(), /fixture app/);
  }
  const legacy = await request('/app/admin/catalog-review');
  assert.equal(legacy.status, 308);
  assert.equal(legacy.headers.get('location'), '/app/admin2?section=card-data');
  assert.equal((await request('/app/main.dart.js')).status, 200);
  assert.equal((await request('/app/missing.js')).status, 404);
  assert.equal((await request('/app/api/missing')).status, 404);
  assert.equal((await request('/app/%2e%2e/server.js')).status, 403);
  assert.equal((await request('/app/%2e%2e%2fserver.js')).status, 403);
  assert.equal((await request('/app/#/admin2')).status, 200);
});
