import assert from 'node:assert/strict';
import test from 'node:test';

import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
} from '../../supabase/functions/_shared/issuer_card_crawl.ts';

const issuer = 'Axis Bank';
const rootSitemap = 'https://www.axis.bank.in/sitemap.xml';

function resource(url, text, contentType = 'text/html') {
  return {
    submittedUrl: url,
    finalUrl: url,
    canonicalUrl: url,
    contentType,
    text,
    bytes: new TextEncoder().encode(text),
    contentHash: 'test',
    retrievedAt: '2026-08-17T00:00:00.000Z',
  };
}

function sitemap(urls, index = false) {
  const tag = index ? 'sitemap' : 'url';
  return `<?xml version="1.0"?><${index ? 'sitemapindex' : 'urlset'}>${urls
    .map((url) => `<${tag}><loc>${url}</loc></${tag}>`)
    .join('')}</${index ? 'sitemapindex' : 'urlset'}>`;
}

test('stops nested sitemap indexes at depth two and uses a same-domain page index as a candidate fallback', async () => {
  const depthOne = 'https://www.axis.bank.in/sitemaps/one.xml';
  const depthTwo = 'https://www.axis.bank.in/sitemaps/two.xml';
  const depthThree = 'https://www.axis.bank.in/sitemaps/three.xml';
  const fallbackProduct = 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card';
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) return resource(input.url, sitemap([depthOne], true), 'application/xml');
      if (input.url === depthOne) return resource(input.url, sitemap([depthTwo], true), 'application/xml');
      if (input.url === depthTwo) return resource(input.url, sitemap([depthThree, fallbackProduct], true), 'application/xml');
      if (input.url === fallbackProduct) return resource(input.url, '<h1>Axis Privilege Credit Card</h1>');
      assert.fail(`depth-three sitemap must not be fetched: ${input.url}`);
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [rootSitemap, depthOne, depthTwo, fallbackProduct]);
  assert.equal(result.consideredCount, 1);
  assert.equal(result.fetchedCount, 1);
  assert.equal(result.candidates[0].kind, 'card_product');
});

test('caps sitemap URLs at 200 and candidate page requests at 40', async () => {
  const urls = Array.from({length: 201}, (_, index) =>
    `https://www.axis.bank.in/cards/credit-card/card-${index + 1}`,
  );
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) return resource(input.url, sitemap(urls), 'application/xml');
      return resource(input.url, `<h1>Axis Card ${input.url.match(/card-\d+/)?.[0]}</h1>`);
    },
    delay: async () => {},
  });

  assert.equal(result.consideredCount, 200);
  assert.equal(result.fetchedCount, 40);
  assert.equal(requested.length, 41);
  assert.equal(requested.at(-1), urls[39]);
});

test('never fetches more than 200 sitemap documents from a sitemap index', async () => {
  const nested = Array.from({length: 201}, (_, index) =>
    `https://www.axis.bank.in/sitemaps/cards-${index + 1}.xml`,
  );
  const requested = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, input.url === rootSitemap ? sitemap(nested, true) : sitemap([]), 'application/xml');
    },
    delay: async () => {},
  });

  assert.equal(requested.length, 200);
  assert.equal(requested.at(-1), nested[198]);
});

test('caps caller-provided sitemap roots at 200 too', async () => {
  const roots = Array.from({length: 201}, (_, index) =>
    `https://www.axis.bank.in/sitemaps/root-${index + 1}.xml`,
  );
  const requested = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrls: roots,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      return resource(input.url, sitemap([]), 'application/xml');
    },
    delay: async () => {},
  });

  assert.equal(requested.length, 200);
  assert.equal(requested.at(-1), roots[199]);
});

test('canonical duplicates collapse and all injected requests and delays are sequential', async () => {
  const first = 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card?utm_source=mail';
  const duplicate = 'https://www.axis.bank.in/cards//credit-card/privilege-credit-card/#details';
  const second = 'https://www.axis.bank.in/cards/credit-card/select-credit-card';
  let active = 0;
  let maxActive = 0;
  const order = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      active += 1;
      maxActive = Math.max(maxActive, active);
      order.push(`fetch:${input.url}`);
      await Promise.resolve();
      active -= 1;
      if (input.url === rootSitemap) return resource(input.url, sitemap([first, duplicate, second]), 'application/xml');
      return resource(input.url, '<h1>Axis Credit Card</h1>');
    },
    delay: async () => {
      assert.equal(active, 0);
      order.push('delay');
    },
  });

  assert.equal(maxActive, 1);
  assert.equal(result.consideredCount, 2);
  assert.equal(result.fetchedCount, 2);
  assert.deepEqual(order, [
    `fetch:${rootSitemap}`,
    'delay',
    'fetch:https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    'delay',
    `fetch:${second}`,
  ]);
});

test('scores product, benefit, fee, rewards, terms, and MITC pages positively', () => {
  const positives = [
    ['https://www.axis.bank.in/cards/credit-card/privilege-credit-card', 'card_product'],
    ['https://www.axis.bank.in/cards/privilege/benefits', 'supporting_document'],
    ['https://www.axis.bank.in/cards/privilege/fees-and-charges', 'supporting_document'],
    ['https://www.axis.bank.in/cards/privilege/rewards', 'supporting_document'],
    ['https://www.axis.bank.in/cards/privilege/terms-and-conditions', 'supporting_document'],
    ['https://www.axis.bank.in/cards/privilege/mitc.pdf', 'supporting_document'],
  ];

  for (const [url, kind] of positives) {
    const page = classifyIssuerPage({issuer, url, html: '<h1>Axis Privilege Credit Card</h1>'});
    assert.equal(page.kind, kind, url);
    assert.ok(page.confidence >= 0.7, url);
  }
});

test('quarantines known invalid Axis, HDFC, Kotak, and generic PNB pages without retaining sensitive evidence', () => {
  const invalids = [
    ['Axis Bank', 'https://www.axis.bank.in/login'],
    ['HDFC Bank', 'https://www.hdfcbank.com/personal/resources/learning-centre'],
    ['Kotak Bank', 'https://www.kotak.com/en/digital-banking/net-banking/login.html'],
    ['Punjab National Bank', 'https://www.pnbcard.in/types5.html?tracking=1234567890123456'],
    ['Punjab National Bank', 'https://www.pnbindia.in/protection.html'],
  ];

  for (const [pageIssuer, url] of invalids) {
    const page = classifyIssuerPage({
      issuer: pageIssuer,
      url,
      html: '<title>Generic account help 1234567890123456</title>',
    });
    assert.ok(['not_a_card', 'ambiguous'].includes(page.kind), url);
    assert.ok(page.warnings.length > 0, url);
    assert.ok(page.sanitizedEvidence.every((value) => !/\d{4,}/.test(value)), url);
    assert.ok(page.sanitizedEvidence.every((value) => value.length <= 300), url);
  }
});
