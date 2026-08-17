import assert from 'node:assert/strict';
import test from 'node:test';

import {
  classifyIssuerPage,
  discoverIssuerCardCandidates,
  issuerDiscoveryFallbackUrls,
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

function everyReturnedString(value) {
  if (typeof value === 'string') return [value];
  if (Array.isArray(value)) return value.flatMap(everyReturnedString);
  if (value && typeof value === 'object') return Object.values(value).flatMap(everyReturnedString);
  return [];
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

test('builds conventional same-host sitemap and credit-card index fallbacks', () => {
  assert.deepEqual(
    issuerDiscoveryFallbackUrls(
      'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    ),
    {
      sitemapUrls: [
        'https://www.axis.bank.in/sitemap.xml',
        'https://www.axis.bank.in/sitemap_index.xml',
        'https://www.axis.bank.in/sitemap-index.xml',
        'https://www.axis.bank.in/sitemaps/sitemap.xml',
      ],
      indexUrls: [
        'https://www.axis.bank.in/cards/credit-card',
        'https://www.axis.bank.in/cards/credit-cards',
        'https://www.axis.bank.in/personal/cards/credit-cards',
      ],
    },
  );
});

test('falls back from unavailable sitemaps to same-host credit-card indexes', async () => {
  const product = 'https://www.axis.bank.in/cards/credit-card/select-credit-card';
  const seeds = issuerDiscoveryFallbackUrls(product);
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrls: seeds.sitemapUrls,
    indexUrls: seeds.indexUrls,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (seeds.sitemapUrls.includes(input.url)) throw new Error('unreachable');
      if (input.url === seeds.indexUrls[0]) {
        return resource(input.url, `<a href="${product}">Select card</a>`);
      }
      if (input.url === product) {
        return resource(input.url, '<h1>Axis Select Credit Card</h1>');
      }
      throw new Error('unused fallback');
    },
    delay: async () => {},
  });

  assert.equal(result.candidates[0]?.proposedName, 'Select');
  assert.equal(result.fetchedCount, 1);
  assert.deepEqual(requested, [...seeds.sitemapUrls, seeds.indexUrls[0], product]);
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

test('redacts long digit sequences from every returned result string', async () => {
  const product = 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card?account=1234567890123456';
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      if (input.url === rootSitemap) return resource(input.url, sitemap([product]), 'application/xml');
      return resource(
        input.url,
        '<h1>Axis Privilege 9876543210987654 Credit Card</h1><title>Member 1234567890123456</title>',
      );
    },
    delay: async () => {},
  });

  for (const value of everyReturnedString(result)) {
    assert.doesNotMatch(value, /\d{4,}/, value);
  }
});

test('ranks positives before the 40 fetch cap and quarantines hard-negative links without fetching them', async () => {
  const negatives = Array.from({length: 40}, (_, index) =>
    `https://www.axis.bank.in/login?tracking=${index + 1000000000000000}`,
  );
  const product = 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card';
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) return resource(input.url, sitemap([...negatives, product]), 'application/xml');
      assert.equal(input.url, product);
      return resource(input.url, '<h1>Axis Privilege Credit Card</h1>');
    },
    delay: async () => {},
  });

  assert.equal(result.consideredCount, 41);
  assert.equal(result.fetchedCount, 1);
  assert.equal(result.candidates[0]?.canonicalUrl, product);
  assert.equal(result.quarantined.length, 40);
  assert.deepEqual(requested, [rootSitemap, product]);
});

test('anchors sitemap, candidate, and returned canonical URLs to the initial approved hostname', async () => {
  const crossHostSitemap = 'https://www.axisbank.com/sitemap.xml';
  const crossHostCandidate = 'https://www.axisbank.com/cards/credit-card/privilege-credit-card';
  const localProduct = 'https://www.axis.bank.in/cards/credit-card/select-credit-card';
  const requested = [];
  const result = await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => {
      requested.push(input.url);
      if (input.url === rootSitemap) {
        return resource(input.url, sitemap([crossHostSitemap, crossHostCandidate, localProduct], true), 'application/xml');
      }
      assert.equal(input.url, localProduct);
      return {
        ...resource(input.url, '<h1>Axis Select Credit Card</h1>'),
        finalUrl: crossHostCandidate,
        canonicalUrl: crossHostCandidate,
      };
    },
    delay: async () => {},
  });

  assert.deepEqual(requested, [rootSitemap, localProduct]);
  assert.equal(result.candidates.length, 0);
  assert.equal(result.quarantined.length, 1);
  assert.doesNotMatch(result.quarantined[0].canonicalUrl, /axisbank\.com/);
});

test('requires product-specific identity context before classifying generic listings or sitewide documents positively', () => {
  const genericListing = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-cards',
    html: '<h1>Credit Cards</h1>',
  });
  const sitewideTerms = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/terms-and-conditions',
    html: '<h1>Terms and Conditions</h1>',
  });

  assert.equal(genericListing.kind, 'ambiguous');
  assert.equal(sitewideTerms.kind, 'ambiguous');
});

test('rejects generic navigation and legal pages whose headings merely mention credit cards', () => {
  const genericPages = [
    ['https://www.axis.bank.in/cards/credit-card/all', '<h1>Compare Credit Card Options</h1>'],
    ['https://www.axis.bank.in/cards/credit-card/overview', '<h1>Explore Our Credit Card Range</h1>'],
    ['https://www.axis.bank.in/legal/terms-and-conditions', '<h1>Axis Bank Credit Card Terms and Conditions</h1>'],
  ];

  for (const [url, html] of genericPages) {
    const page = classifyIssuerPage({issuer, url, html});
    assert.equal(page.kind, 'ambiguous', url);
  }
});

test('keeps a real product when it contains generic card words alongside a meaningful shared token', () => {
  const page = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/select-credit-card',
    html: '<h1>Axis Select Credit Card</h1>',
  });

  assert.equal(page.kind, 'card_product');
  assert.equal(page.proposedName, 'Select');
});

test('does not self-validate generic identities using their own heading tokens', () => {
  const genericPages = [
    ['https://www.axis.bank.in/cards/credit-card/all', '<h1>Find the Right Credit Card</h1>'],
    ['https://www.axis.bank.in/cards/credit-card/overview', '<h1>Best Credit Card Offers</h1>'],
    ['https://www.axis.bank.in/legal/fees-and-charges', '<h1>Credit Card Fees and Charges Guide</h1>'],
  ];

  for (const [url, html] of genericPages) {
    assert.equal(classifyIssuerPage({issuer, url, html}).kind, 'ambiguous', url);
  }
});

test('matches meaningful identity tokens only against real product URL paths', () => {
  const pages = [
    ['https://www.axis.bank.in/cards/credit-card/select-credit-card', '<h1>Axis Select Credit Card</h1>', 'card_product'],
    ['https://www.axis.bank.in/cards/credit-card/flipkart-axis-bank-credit-card', '<h1>Flipkart Axis Bank Credit Card</h1>', 'card_product'],
    ['https://www.axis.bank.in/cards/privilege/benefits', '<h1>Axis Privilege Credit Card</h1>', 'supporting_document'],
  ];

  for (const [url, html, kind] of pages) {
    assert.equal(classifyIssuerPage({issuer, url, html}).kind, kind, url);
  }
});

test('classifies pilot product pages that expose identity only in an ordinary title', () => {
  const pages = [
    [
      'Axis Bank',
      'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
      '<title>Privilege Credit Card with Unlimited Benefits | Axis Bank</title>',
    ],
    [
      'Kotak Bank',
      'https://www.kotak.com/en/personal-banking/cards/credit-cards/white-reserve-credit-card.html',
      '<title>White Reserve Credit Card | Kotak</title>',
    ],
  ];

  for (const [pageIssuer, url, html] of pages) {
    assert.equal(classifyIssuerPage({issuer: pageIssuer, url, html}).kind, 'card_product', url);
  }
});

test('does not match a title marketing suffix against an unrelated product URL token', () => {
  const html = '<title>Privilege Credit Card with Unlimited Benefits | Axis Bank</title>';
  const marketingPath = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/unlimited-benefits',
    html,
  });
  const productPath = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    html,
  });

  assert.equal(marketingPath.kind, 'ambiguous');
  assert.equal(productPath.kind, 'card_product');
  assert.equal(productPath.proposedName, 'Privilege');
});

test('uses authoritative title metadata over navigation tiles while URL context rejects generic titles', () => {
  const liveHtml = `
    <div class="title">E-Debit Card</div>
    <title>Apply for PRIVILEGE Credit Card with unlimited benefits | Axis Bank</title>
    <h1>PRIVILEGE Credit Card</h1>
  `;
  const product = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    html: liveHtml,
  });
  const generic = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/all',
    html: '<title>Compare Credit Card Options | Axis Bank</title>',
  });

  assert.equal(product.kind, 'card_product');
  assert.equal(product.proposedName, 'Privilege');
  assert.equal(generic.kind, 'ambiguous');
});

test('falls back from issuer service-portal metadata to a product h1', () => {
  const page = classifyIssuerPage({
    issuer,
    url: 'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    html: `
      <title>Axis Bank Credit Card Services Portal</title>
      <h1>Axis Privilege Credit Card</h1>
    `,
  });

  assert.equal(page.kind, 'card_product');
  assert.equal(page.proposedName, 'Privilege');
});

test('passes a nonzero production default delay to an injected delay function', async () => {
  const delays = [];
  await discoverIssuerCardCandidates({
    issuer,
    sitemapUrl: rootSitemap,
    fetchOfficialIssuerResource: async (input) => input.url === rootSitemap
      ? resource(input.url, sitemap(['https://www.axis.bank.in/cards/credit-card/privilege-credit-card']), 'application/xml')
      : resource(input.url, '<h1>Axis Privilege Credit Card</h1>'),
    delay: async (milliseconds) => delays.push(milliseconds),
  });

  assert.equal(delays.length, 1);
  assert.ok(delays[0] > 0);
});
