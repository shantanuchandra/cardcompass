import assert from 'node:assert/strict';
import test from 'node:test';

import {
  diffCatalogFields,
  normalizeMoney,
  normalizeOfficialCatalogPage,
} from '../../supabase/functions/_shared/card_catalog_enrichment.ts';

test('normalizes explicit Indian fee and APR values', () => {
  assert.equal(normalizeMoney('₹ 1,500 + GST'), 1500);
  assert.equal(normalizeMoney('INR 0'), 0);
  assert.equal(normalizeMoney('Not applicable'), null);

  const result = normalizeOfficialCatalogPage(`
    <html><head><title>White Reserve Credit Card | Kotak</title></head>
    <body>
      <h1>White Reserve Credit Card</h1>
      <dl>
        <dt>Joining Fee</dt><dd>₹ 12,500 + GST</dd>
        <dt>Annual Fee</dt><dd>₹ 12,500 + GST</dd>
        <dt>Finance Charges</dt><dd>3.5% per month (42% annually)</dd>
        <dt>Network</dt><dd>Visa Infinite</dd>
      </dl>
    </body></html>
  `, 'https://www.kotak.com/rd/white-reserve');

  assert.equal(result.patch.joining_fee?.value, 12500);
  assert.equal(result.patch.annual_fee?.value, 12500);
  assert.equal(result.patch.apr?.value, 42);
  assert.equal(result.patch.network?.value, 'Visa');
});

test('backfills null fields but reports non-null conflicts', () => {
  assert.deepEqual(
    diffCatalogFields(
      {network: null, annual_fee: null},
      {
        network: {value: 'Visa', confidence: 0.96, evidence: 'Network: Visa'},
        annual_fee: {value: 1500, confidence: 0.95, evidence: 'Annual Fee ₹1,500'},
      },
    ),
    {
      backfill: {network: 'Visa', annual_fee: 1500},
      conflicts: [],
    },
  );

  const conflict = diffCatalogFields(
    {annual_fee: 1000},
    {annual_fee: {value: 1500, confidence: 0.95, evidence: 'Annual Fee ₹1,500'}},
  );
  assert.deepEqual(conflict.backfill, {});
  assert.equal(conflict.conflicts[0].field, 'annual_fee');
  assert.equal(conflict.conflicts[0].existing, 1000);
  assert.equal(conflict.conflicts[0].proposed, 1500);
});

test('extracts grounded benefits without inventing missing values', () => {
  const result = normalizeOfficialCatalogPage(`
    <html><body>
      <h2>Dining benefits</h2>
      <p>Get 10% cashback on dining, capped at ₹500 per statement month.</p>
      <p>Airport lounge access: 2 complimentary visits per quarter.</p>
    </body></html>
  `, 'https://www.example-bank.test/cards/example');

  assert.equal(result.patch.annual_fee, undefined);
  assert.equal(result.benefits.length, 2);
  assert.match(result.benefits[0].evidence, /10% cashback/i);
  assert.equal(result.benefits[0].confidence >= 0.9, true);
});
