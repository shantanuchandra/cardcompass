import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';

import {
  allowedOfficialUrl,
  canonicalOfficialUrl,
  canonicalCardIdentity,
  evaluateAutomaticCatalogGate,
  isAdminEmail,
  officialCardIdentityFromHtml,
  publicDiscoveryResult,
  publicReasonCode,
  rankOfficialUrls,
  reviewRequiredJobPatch,
  sanitizeEvidence,
  selectSubmittedUrlIdentity,
} from '../../supabase/functions/_shared/card_discovery.ts';

const cardDiscoveryEntrypoint = new URL(
  '../../supabase/functions/card-discovery/index.ts',
  import.meta.url,
);
const enrichmentBatchEntrypoint = new URL(
  '../../supabase/functions/benefit-enrichment-batch/index.ts',
  import.meta.url,
);

test('extracts a product identity from legacy issuer page headings', () => {
  const html = `
    <title>Punjab National Bank - Credit Card Portal</title>
    <nav><a href="types5.html">PNB RuPay Platinum Card</a></nav>
    <div class="leftbluelink title"><strong>PNB Rupay Select Card</strong></div>
  `;

  assert.deepEqual(
    officialCardIdentityFromHtml(html, 'Punjab National Bank'),
    {
      issuer: 'Punjab National Bank',
      cardName: 'Select',
      network: 'RuPay',
      aliases: ['PNB Rupay Select Card'],
    },
  );
});

test('extracts product identities from ordinary issuer page titles', () => {
  assert.deepEqual(
    officialCardIdentityFromHtml(
      '<title>Privilege Credit Card with Unlimited Benefits | Axis Bank</title>',
      'Axis Bank',
    ),
    {
      issuer: 'Axis Bank',
      cardName: 'Privilege',
      network: null,
      aliases: ['Privilege Credit Card'],
    },
  );
  assert.deepEqual(
    officialCardIdentityFromHtml(
      '<title>White Reserve Credit Card | Kotak</title>',
      'Kotak Bank',
    ),
    {
      issuer: 'Kotak Bank',
      cardName: 'White Reserve',
      network: null,
      aliases: ['White Reserve Credit Card'],
    },
  );
});

test('strips title marketing wrappers without removing real product variant tokens', () => {
  assert.deepEqual(
    officialCardIdentityFromHtml(
      '<title>Apply for Flipkart Axis Bank Credit Card | Axis Bank</title>',
      'Axis Bank',
    ),
    {
      issuer: 'Axis Bank',
      cardName: 'Flipkart',
      network: null,
      aliases: ['Flipkart Axis Bank Credit Card'],
    },
  );
  assert.deepEqual(
    officialCardIdentityFromHtml(
      '<title>Privilege Select Credit Card | Axis Bank</title>',
      'Axis Bank',
    ),
    {
      issuer: 'Axis Bank',
      cardName: 'Privilege Select',
      network: null,
      aliases: ['Privilege Select Credit Card'],
    },
  );
});

test('card discovery emits parser-aware enrichment queue identity', async () => {
  const source = await readFile(cardDiscoveryEntrypoint, 'utf8');
  assert.match(source, /enqueueBenefitEnrichmentJob\(db,/);
  assert.match(source, /parserVersion:\s*["']benefits-v1["']/);
  assert.doesNotMatch(source, /onConflict:\s*["']card_id,final_url_hash,content_hash["']/);
  assert.doesNotMatch(source, /functions\/v1\/catalog-enrichment/);
});

test('benefit enrichment keeps initialization and issuer discovery off unsafe paths', async () => {
  const source = await readFile(enrichmentBatchEntrypoint, 'utf8');

  assert.match(source, /body\.action\s*===\s*["']initialize_pilot["']/);
  assert.match(source, /initialize_card_benefit_enrichment_pilot/);
  assert.match(source, /stage_card_benefit_enrichment/);
  assert.match(source, /finalize_card_catalog_enrichment_job/);
  assert.match(source, /EdgeRuntime\.waitUntil\(\s*runIssuerDiscovery/s);
  assert.match(source, /issuer_discovery_background_failed/);
  assert.doesNotMatch(source, /await\s+runIssuerDiscovery/);
  assert.doesNotMatch(source, /\.from\(["']card_benefits_staging["']\)\s*\.select[\s\S]*?\.limit\(20\)/);
});

test('uses official page identity when statement signals are issuer-only', () => {
  const result = selectSubmittedUrlIdentity({
    html: '<div class="title"><strong>PNB Rupay Select Card</strong></div>',
    issuer: 'Punjab National Bank',
    statementProducts: ['PNB'],
  });

  assert.equal(result.identity.cardName, 'Select');
  assert.deepEqual(result.statementProducts, []);
});

test('clears stale URL failures when a discovery job enters review', () => {
  assert.deepEqual(reviewRequiredJobPatch('review-1', '2026-08-17T00:00:00.000Z'), {
    status: 'review_required',
    review_item_id: 'review-1',
    failure_category: null,
    next_retry_at: null,
    updated_at: '2026-08-17T00:00:00.000Z',
  });
});

test('returns only safe discovery status fields to the client', () => {
  assert.deepEqual(
    publicDiscoveryResult({
      id: 'job-1',
      status: 'resolved',
      resolved_card_id: 'card-1',
      failure_category: 'raw upstream detail',
      next_retry_at: null,
      evidence: {pdf_header_excerpt: 'private'},
    }),
    {
      job_id: 'job-1',
      status: 'resolved',
      resolved_card_id: 'card-1',
      reason_code: null,
      retry_after: null,
    },
  );
});

test('maps internal URL failures to stable public reason codes', () => {
  assert.equal(publicReasonCode(new Error('unapproved_domain')), 'unapproved_domain');
  assert.equal(publicReasonCode(new DOMException('timed out', 'TimeoutError')), 'fetch_timeout');
  assert.equal(publicReasonCode(new Error('official_fetch_503')), 'fetch_timeout');
  assert.equal(publicReasonCode(new Error('database connection detail')), 'review_required');
});

test('canonicalizes equivalent official product URLs for deduplication', () => {
  assert.equal(
    canonicalOfficialUrl(
      'Kotak Bank',
      'https://WWW.KOTAK.COM:443/rd//white-reserve/?utm_source=gmail&b=2&a=1#fees',
    ),
    'https://www.kotak.com/rd/white-reserve?a=1&b=2',
  );
  assert.equal(
    canonicalOfficialUrl(
      'Axis Bank',
      'https://www.axis.bank.in/cards/privilege/?gclid=abc&offer=current',
    ),
    'https://www.axis.bank.in/cards/privilege?offer=current',
  );
});

test('rejects unsafe and cross-issuer product URLs', () => {
  assert.throws(
    () => canonicalOfficialUrl(
      'Kotak Bank',
      'https://kotak.com.evil.test/rd/white-reserve',
    ),
    /unapproved_domain/,
  );
  assert.throws(
    () => canonicalOfficialUrl(
      'Kotak Bank',
      'https://user:pass@kotak.com/rd/white-reserve',
    ),
    /invalid_url/,
  );
  assert.throws(
    () => canonicalOfficialUrl(
      'Kotak Bank',
      'http://kotak.com/rd/white-reserve',
    ),
    /invalid_url/,
  );
  assert.throws(
    () => canonicalOfficialUrl(
      'Kotak Bank',
      'https://www.axis.bank.in/cards/privilege',
    ),
    /unapproved_domain/,
  );
});

test('admin allowlist compares verified emails case-insensitively', () => {
  assert.equal(
    isAdminEmail('Admin@Example.com', 'owner@example.com, admin@example.com'),
    true,
  );
  assert.equal(
    isAdminEmail('visitor@example.com', 'owner@example.com, admin@example.com'),
    false,
  );
  assert.equal(isAdminEmail(null, 'admin@example.com'), false);
});

test('allows only HTTPS URLs on the detected issuer domain', () => {
  assert.equal(
    allowedOfficialUrl(
      'Axis Bank',
      'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    ),
    true,
  );
  assert.equal(
    allowedOfficialUrl('Axis Bank', 'https://evil.example/axis/privilege'),
    false,
  );
  assert.equal(
    allowedOfficialUrl(
      'Axis Bank',
      'http://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    ),
    false,
  );
  assert.equal(
    allowedOfficialUrl(
      'Punjab National Bank',
      'https://www.pnbcard.in/types15.html',
    ),
    true,
  );
});

test('normalizes reported statement variants into canonical products', () => {
  assert.deepEqual(canonicalCardIdentity('Axis Bank', 'Amex Privilege'), {
    issuer: 'Axis Bank',
    cardName: 'Privilege',
    network: 'American Express',
    aliases: ['Amex Privilege'],
  });
  assert.deepEqual(
    canonicalCardIdentity(
      'IndusInd Bank',
      'EAZYDINER INDUSIND BANK PLATINUM CREDIT CARD',
    ),
    {
      issuer: 'IndusInd Bank',
      cardName: 'EazyDiner Platinum',
      network: null,
      aliases: ['EAZYDINER INDUSIND BANK PLATINUM CREDIT CARD'],
    },
  );
});

test('requires official issuer evidence plus an agreeing statement signal', () => {
  assert.deepEqual(
    evaluateAutomaticCatalogGate({
      issuer: 'Axis Bank',
      officialUrl:
        'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
      officialProduct: 'Axis Bank Privilege Credit Card',
      statementProducts: ['Privilege'],
      confidence: 0.95,
      catalogCandidateCount: 0,
      conflicts: [],
    }),
    {autoAdd: true, reasons: []},
  );

  const missingStatementSignal = evaluateAutomaticCatalogGate({
    issuer: 'Axis Bank',
    officialUrl:
      'https://www.axis.bank.in/cards/credit-card/privilege-credit-card',
    officialProduct: 'Axis Bank Privilege Credit Card',
    statementProducts: [],
    confidence: 0.95,
    catalogCandidateCount: 0,
    conflicts: [],
  });
  assert.equal(missingStatementSignal.autoAdd, false);
  assert.ok(missingStatementSignal.reasons.includes('missing_statement_signal'));
});

test('rejects low confidence and conflicting automatic additions', () => {
  const result = evaluateAutomaticCatalogGate({
    issuer: 'Kotak Bank',
    officialUrl: 'https://www.kotak.com/rd/white-reserve',
    officialProduct: 'White Reserve',
    statementProducts: ['White'],
    confidence: 0.7,
    catalogCandidateCount: 2,
    conflicts: ['product_mismatch'],
  });

  assert.equal(result.autoAdd, false);
  assert.deepEqual(result.reasons, [
    'low_confidence',
    'product_mismatch',
    'ambiguous_catalog',
  ]);
});

test('ranks issuer URLs containing all specific product tokens first', () => {
  const urls = rankOfficialUrls('White Reserve', [
    'https://www.kotak.com/cards/white',
    'https://www.kotak.com/rd/white-reserve',
    'https://www.kotak.com/cards',
  ]);
  assert.equal(urls[0], 'https://www.kotak.com/rd/white-reserve');
});

test('sanitizes full numbers and unrelated customer text from evidence', () => {
  const safe = sanitizeEvidence(
    'Customer Jane Doe\nPrimary card number 5123 4567 8912 1759\nPrivilege Credit Card',
  );
  assert.equal(safe.includes('Jane Doe'), false);
  assert.equal(safe.includes('5123 4567 8912'), false);
  assert.equal(safe.includes('Privilege Credit Card'), true);
});
