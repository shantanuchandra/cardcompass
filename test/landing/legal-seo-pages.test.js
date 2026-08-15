import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const siteOrigin = 'https://cardcompass.in';
const routes = [
  ['privacy', '/privacy/'],
  ['terms', '/terms/'],
  ['data-security', '/data-security/'],
  ['recommendation-disclaimer', '/recommendation-disclaimer/'],
  ['tools/best-card', '/tools/best-card/'],
  ['tools/milestone-tracker', '/tools/milestone-tracker/'],
  ['tools/movie-offers', '/tools/movie-offers/'],
];

async function landingFile(path) {
  return readFile(new URL(`landing/${path}`, root), 'utf8');
}

function textContent(html) {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');
}

function schemas(html) {
  return [...html.matchAll(/<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/g)]
    .map(([, json]) => JSON.parse(json));
}

test('each public route has absolute canonical, social metadata, and valid JSON-LD', async () => {
  for (const [directory, route] of routes) {
    const html = await landingFile(`${directory}/index.html`);
    const canonical = `${siteOrigin}${route}`;

    assert.match(html, new RegExp(`<link rel="canonical" href="${canonical.replaceAll('/', '\\/')}"`));
    assert.match(html, new RegExp(`<meta property="og:url" content="${canonical.replaceAll('/', '\\/')}"`));
    assert.match(html, /<meta property="og:image" content="https:\/\/cardcompass\.in\/landing\/img\/social-preview\.png">/);
    assert.match(html, /<meta name="twitter:card" content="summary_large_image">/);
    assert.ok(schemas(html).length > 0, `${route} needs JSON-LD`);
  }
});

test('legal pages disclose the implemented processing boundaries without unsupported compliance claims', async () => {
  const privacy = textContent(await landingFile('privacy/index.html'));
  const security = textContent(await landingFile('data-security/index.html'));
  const combined = `${privacy} ${security}`;

  for (const expected of [
    /gmail\.readonly/i,
    /user\.birthday\.read/i,
    /message ID/i,
    /PDF attachment/i,
    /statement text/i,
    /Supabase/i,
    /Google Gemini/i,
    /transactions/i,
    /statements/i,
    /waitlist/i,
    /Plausible/i,
    /query parameters and fragments/i,
    /support@cardcompass\.in/i,
    /full card number/i,
    /CVV/i,
    /PIN/i,
    /OTP/i,
    /banking password/i,
    /statement PDF password/i,
    /locally/i,
  ]) {
    assert.match(combined, expected);
  }

  assert.doesNotMatch(combined, /SOC\s?2|ISO\s?27001|certified|full DPDPA|DPDPA[- ]compliant/i);
});

test('recommendation disclaimer keeps estimates informational and issuer terms authoritative', async () => {
  const disclaimer = textContent(await landingFile('recommendation-disclaimer/index.html'));
  assert.match(disclaimer, /informational/i);
  assert.match(disclaimer, /not (?:financial|investment|legal|tax) advice/i);
  assert.match(disclaimer, /issuer/i);
  assert.match(disclaimer, /caps/i);
  assert.match(disclaimer, /eligibility/i);
  assert.match(disclaimer, /verify/i);
});

test('robots and sitemap expose only canonical public routes', async () => {
  const robots = await landingFile('robots.txt');
  const sitemap = await landingFile('sitemap.xml');

  assert.match(robots, /^User-agent: \*$/m);
  assert.match(robots, /^Allow: \/$/m);
  assert.match(robots, /^Sitemap: https:\/\/cardcompass\.in\/sitemap\.xml$/m);

  const locations = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(([, value]) => value);
  assert.deepEqual(locations, [
    'https://cardcompass.in/',
    ...routes.map(([, route]) => `${siteOrigin}${route}`),
  ]);
  assert.equal(new Set(locations).size, locations.length);
});

test('machine-readable product page removes contradicted privacy and performance claims', async () => {
  const llm = await landingFile('llm.txt');
  assert.match(llm, /Gmail read-only/i);
  assert.match(llm, /Supabase/i);
  assert.match(llm, /Google Gemini/i);
  assert.match(llm, /transaction and statement records/i);
  assert.doesNotMatch(llm, /processed locally on-device|No transaction data is stored|Full DPDPA|99\.2%|₹50,000\+|real-time benefit rules/i);
});

test('social preview is a 1200 by 630 PNG asset', async () => {
  const image = await readFile(new URL('landing/img/social-preview.png', root));
  assert.deepEqual([...image.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(image.readUInt32BE(16), 1200);
  assert.equal(image.readUInt32BE(20), 630);
});
