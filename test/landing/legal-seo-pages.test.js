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

test('homepage and each public route have canonical social metadata and valid JSON-LD', async () => {
  for (const [directory, route] of [['.', '/'], ...routes]) {
    const html = await landingFile(directory === '.' ? 'index.html' : `${directory}/index.html`);
    const canonical = `${siteOrigin}${route}`;

    assert.match(html, new RegExp(`<link[^>]*rel="canonical"[^>]*href="${canonical.replaceAll('/', '\\/')}"`));
    assert.match(html, new RegExp(`<meta[^>]*property="og:url"[^>]*content="${canonical.replaceAll('/', '\\/')}"`));
    assert.match(html, /<meta\s+property="og:image"\s+content="https:\/\/cardcompass\.in\/img\/social-preview\.png"\s*\/?>/);
    assert.match(html, /<meta\s+property="og:image:alt"\s+content="[^"]+"\s*\/?>/);
    assert.match(html, /<meta\s+property="og:image:width"\s+content="1200"\s*\/?>/);
    assert.match(html, /<meta\s+property="og:image:height"\s+content="630"\s*\/?>/);
    assert.match(html, /<meta\s+name="twitter:card"\s+content="summary_large_image"\s*\/?>/);
    assert.match(html, /<meta\s+name="twitter:image"\s+content="https:\/\/cardcompass\.in\/img\/social-preview\.png"\s*\/?>/);
    assert.match(html, /<meta\s+name="twitter:image:alt"\s+content="[^"]+"\s*\/?>/);
    assert.ok(schemas(html).length > 0, `${route} needs JSON-LD`);
  }
});

test('homepage schema describes the organization, website, and software without unsupported claims', async () => {
  const html = await landingFile('index.html');
  const graph = schemas(html).flatMap((schema) => schema['@graph'] || [schema]);

  assert.ok(graph.some((entry) => entry['@type'] === 'Organization' && entry.url === 'https://cardcompass.in/'));
  assert.ok(graph.some((entry) => entry['@type'] === 'WebSite' && entry.url === 'https://cardcompass.in/'));
  const software = graph.find((entry) => entry['@type'] === 'SoftwareApplication');
  assert.equal(software?.applicationCategory, 'FinanceApplication');
  for (const unsupported of ['aggregateRating', 'review', 'offers', 'downloadUrl']) {
    assert.equal(Object.hasOwn(software, unsupported), false);
  }
  assert.match(html, /<link rel="alternate" type="text\/markdown" href="\/llms\.txt"/);
});

test('legal pages disclose the implemented processing boundaries without unsupported compliance claims', async () => {
  const privacy = textContent(await landingFile('privacy/index.html'));
  const security = textContent(await landingFile('data-security/index.html'));
  const combined = `${privacy} ${security}`;

  for (const expected of [
    /gmail\.readonly/i,
    /user\.birthday\.read/i,
    /message ID/i,
    /full parsed message/i,
    /app memory/i,
    /does not intentionally persist (?:the )?message body/i,
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
    /hardening migration/i,
    /live backend may still retain/i,
    /applied and verified/i,
    /attempts to store (?:the )?date of birth/i,
    /remain in memory/i,
    /requested again/i,
  ]) {
    assert.match(combined, expected);
  }

  assert.doesNotMatch(combined, /SOC\s?2|ISO\s?27001|certified|full DPDPA|DPDPA[- ]compliant/i);
  assert.doesNotMatch(combined, /historical RPCs[^.]*have been removed/i);
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
    'https://cardcompass.in/llms.txt',
  ]);
  assert.equal(new Set(locations).size, locations.length);
});

test('machine-readable product page distinguishes repository hardening from deployed backend state', async () => {
  const llm = await landingFile('llm.txt');
  assert.match(llm, /Gmail read-only/i);
  assert.match(llm, /Supabase/i);
  assert.match(llm, /Google Gemini/i);
  assert.match(llm, /transaction and statement records/i);
  assert.match(llm, /full parsed message/i);
  assert.match(llm, /does not intentionally persist (?:the )?message body/i);
  assert.match(llm, /hardening migration/i);
  assert.match(llm, /live backend may still retain/i);
  assert.match(llm, /applied and verified/i);
  assert.doesNotMatch(llm, /historical RPCs[^.]*have been removed/i);
  assert.match(llm, /attempts to store (?:the )?date of birth/i);
  assert.match(llm, /may remain in memory/i);
  assert.match(llm, /matching statement PDF/i);
  assert.doesNotMatch(llm, /selected statement PDF/i);
  assert.doesNotMatch(llm, /processed locally on-device|No transaction data is stored|Full DPDPA|99\.2%|₹50,000\+|real-time benefit rules/i);
});

test('GTM operations block broad acquisition until the card-data migration is verified', async () => {
  const playbook = await readFile(new URL('../../docs/gtm/founder-led-playbook.md', import.meta.url), 'utf8');

  assert.match(playbook, /launch gate/i);
  assert.match(playbook, /20260815090910_remove_legacy_card_secrets/i);
  assert.match(playbook, /applied and verified/i);
  assert.match(playbook, /do not begin broad acquisition/i);
});

test('llms.txt is a byte-for-byte public alias of llm.txt and is declared for crawlers', async () => {
  const llm = await landingFile('llm.txt');
  const llms = await landingFile('llms.txt');
  const robots = await landingFile('robots.txt');

  assert.equal(llms, llm);
  assert.match(robots, /^# LLM information: https:\/\/cardcompass\.in\/llms\.txt$/m);
});

test('social preview is a 1200 by 630 PNG asset', async () => {
  const image = await readFile(new URL('landing/img/social-preview.png', root));
  assert.deepEqual([...image.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(image.readUInt32BE(16), 1200);
  assert.equal(image.readUInt32BE(20), 630);
});
