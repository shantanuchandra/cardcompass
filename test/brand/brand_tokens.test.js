import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('landing tokens match the canonical brand manifest', () => {
  const manifest = JSON.parse(
    readFileSync('assets/brand/cardcompass.tokens.json', 'utf8'),
  );
  const css = readFileSync('landing/brand-tokens.css', 'utf8');

  for (const [name, value] of Object.entries(manifest.color)) {
    assert.match(
      css,
      new RegExp(`--brand-${name.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}:\\s*${value}`, 'i'),
    );
  }
  assert.doesNotMatch(css, /#00f5ff|#8b5cf6/i);
});

test('landing styles consume the shared brand token sheet', () => {
  for (const file of ['landing/style.css', 'landing/resources.css']) {
    const css = readFileSync(file, 'utf8');
    assert.match(css, /@import\s+url\("\.\/brand-tokens\.css"\)/);
  }
});
