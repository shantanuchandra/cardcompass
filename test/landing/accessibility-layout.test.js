import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const read = (path) => readFile(new URL(path, root), 'utf8');

function rule(css, selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return css.match(new RegExp(`${escaped}\\s*\\{([^}]*)\\}`))?.[1] || '';
}

function journeyMarkup(html) {
  return html.match(/<section class="journey"[\s\S]*?<\/section>/)?.[0] || '';
}

test('core landing narrative has five top-level sections or fewer', async () => {
  const html = await read('landing/index.html');

  assert.ok((html.match(/<section\b/g) || []).length <= 5);
});

test('non-decorative landing type never drops below 12px', async () => {
  const css = await read('landing/style.css');

  assert.doesNotMatch(css, /font-size:\s*(?:8|9|10|11)px/);
});

test('landing sections follow the concise public journey order', async () => {
  const html = await read('landing/index.html');
  const classes = [...html.matchAll(/<section class="([^"]+)"/g)].map(([, className]) => className);

  assert.deepEqual(classes, ['hero', 'journey', 'trust section-pad', 'faq section-pad', 'final-cta']);
});

test('journey combines the decision flow and discloses secondary concepts without full bands', async () => {
  const html = await read('landing/index.html');
  const journey = journeyMarkup(html);

  assert.match(journey, /class="[^"]*decision-flow/);
  assert.match(journey, /<details class="[^"]*concept-disclosure/);
  assert.match(journey, /<summary>Illustrative early concepts <span>Not live product screens<\/span><\/summary>/);
  assert.doesNotMatch(journey, /(?:ledger-band|process section-pad|product-proof|capture-offset)/);
  assert.ok(journey.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().length < 1250);
});

test('resources are a compact link row rather than a padded narrative band', async () => {
  const html = await read('landing/index.html');
  const resources = html.match(/<nav class="resources"[\s\S]*?<\/nav>/)?.[0] || '';

  assert.match(resources, /class="[^"]*resource-links/);
  assert.doesNotMatch(resources, /section-pad/);
  assert.doesNotMatch(resources, /<h2\b/);
});

test('public landing actions explicitly meet readable copy and target-size floors', async () => {
  const css = await read('landing/style.css');
  const actions = [
    '.button',
    '.scenario-tab',
    '.suggestions [role="option"]',
    '.wordmark',
    '.nav-link',
    '.resources a',
    '.site-footer nav a',
    '.card-chip button',
    '.faq-list summary',
    '.concept-disclosure summary',
    '.check-row',
    '.skip-link',
  ];

  for (const selector of actions) {
    const declarations = rule(css, selector);
    assert.match(declarations, /font-size:\s*(?:1[4-9]|[2-9]\d)px/, `${selector} needs 14px action copy`);
    assert.match(declarations, /min-(?:height|block-size):\s*(?:4[4-9]|[5-9]\d)px/, `${selector} needs a 44px target`);
  }
});
