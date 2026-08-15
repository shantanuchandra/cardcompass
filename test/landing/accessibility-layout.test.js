import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');

test('core landing narrative has five top-level sections or fewer', async () => {
  const html = await read('landing/index.html');

  assert.ok((html.match(/<section\b/g) || []).length <= 5);
});

test('non-decorative landing type never drops below 12px', async () => {
  const css = await read('landing/style.css');

  assert.doesNotMatch(css, /font-size:\s*(?:8|9|10|11)px/);
});
