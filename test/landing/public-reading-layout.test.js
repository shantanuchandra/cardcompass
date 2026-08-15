import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const utilityPages = [
  'landing/tools/best-card/index.html',
  'landing/tools/milestone-tracker/index.html',
  'landing/tools/movie-offers/index.html',
];
const legalPages = [
  'landing/privacy/index.html',
  'landing/data-security/index.html',
  'landing/terms/index.html',
  'landing/recommendation-disclaimer/index.html',
];

async function read(path) {
  return readFile(new URL(path, root), 'utf8');
}

test('utility form appears before long-form methodology', async () => {
  for (const page of utilityPages) {
    const html = await read(page);
    assert.ok(html.indexOf('<form') < html.indexOf('How this estimate works'), page);
  }
});

test('legal pages provide a mobile contents disclosure', async () => {
  for (const page of legalPages) {
    const html = await read(page);
    assert.match(html, /<details\b[^>]*class="side-nav-disclosure"/i, page);
    assert.match(html, /<summary>On this page<\/summary>/i, page);
  }
});

test('public reading styles use readable body type and line length', async () => {
  const css = await read('landing/resources.css');
  assert.match(css, /body\s*\{[^}]*font-size:\s*(?:15|16)px/s);
  assert.match(css, /\.updated\s*\{[^}]*font:\s*500\s+(?:0\.9[4-9]|1)rem\//s);
  assert.doesNotMatch(css, /\.updated\s*\{[^}]*font:\s*[^;]*\b0\.7[0-9]rem\//s);
  assert.match(css, /\.content\s*\{[^}]*max-width:\s*(?:65|66|67|68|69|70|71|72|73|74|75)ch/s);
  assert.match(css, /@media\s*\(max-width:\s*820px\)\s*\{[\s\S]*?\.side-nav-disclosure\s*\{[^}]*display:\s*block/s);
});

test('legal update metadata uses the readable override rather than inheriting a smaller utility style', async () => {
  for (const page of legalPages) {
    const html = await read(page);
    assert.match(html, /<p\b[^>]*class="updated"[^>]*>/i, page);
  }
  const css = await read('landing/resources.css');
  const updatedRule = css.match(/\.updated\s*\{[^}]*\}/s)?.[0] || '';
  assert.match(updatedRule, /font:\s*500\s+(?:0\.9[4-9]|1)rem\//);
  assert.doesNotMatch(updatedRule, /0\.7[0-9]rem/);
});

test('404 offers home and sign-in exits', async () => {
  const html = await read('landing/404.html');
  assert.match(html, /href="\/"/);
  assert.match(html, /href="\/login"/);
});
