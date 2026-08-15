import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildEnrichmentPayload,
  buildJoinPayload,
  extractEnrichmentToken,
  isValidEmail,
  validateQualification,
} from '../../landing/waitlist.js';

test('email validation rejects malformed and overlong addresses', () => {
  assert.equal(isValidEmail(' person@example.com '), true);
  assert.equal(isValidEmail('person@example'), false);
  assert.equal(isValidEmail(`a@${'b'.repeat(250)}.com`), false);
});

test('join payload matches the public RPC contract exactly', () => {
  assert.deepEqual(
    buildJoinPayload({
      email: ' Person@Example.com ',
      privacyConsent: true,
      source: 'landing_hero',
      attribution: {
        utm_source: 'newsletter',
        utm_medium: 'email',
        utm_campaign: 'founding-100',
        utm_term: null,
        utm_content: 'receipt-a',
        referrer_path: '/best-credit-card/',
        landing_variant: 'receipt_v1',
      },
    }),
    {
      p_email: 'person@example.com',
      p_source: 'landing_hero',
      p_utm_source: 'newsletter',
      p_utm_medium: 'email',
      p_utm_campaign: 'founding-100',
      p_utm_term: null,
      p_utm_content: 'receipt-a',
      p_referrer_path: '/best-credit-card/',
      p_landing_variant: 'receipt_v1',
      p_privacy_consent: true,
    },
  );
});

test('qualification requires every scoring field', () => {
  assert.deepEqual(
    validateQualification({
      cardCount: '3-6',
      monthlySpendBand: '',
      primaryGoal: 'maximize_rewards',
      problemDetail: '',
      topCards: [],
    }),
    { monthlySpendBand: 'Choose your monthly card spend.' },
  );
});

test('qualification enforces RPC field limits and enum values', () => {
  assert.deepEqual(
    validateQualification({
      name: 'N'.repeat(101),
      cardCount: '3-5',
      monthlySpendBand: '50k-1l',
      primaryGoal: 'maximize_rewards',
      problemDetail: 'P'.repeat(501),
      topCards: ['A'.repeat(101), 'Card B', 'Card C'],
    }),
    {
      name: 'Keep your name to 100 characters or fewer.',
      cardCount: 'Choose how many cards you hold.',
      problemDetail: 'Keep this to 500 characters or fewer.',
      topCards: 'Choose up to two cards, each under 100 characters.',
    },
  );
});

test('enrichment payload trims optional values and matches the RPC contract', () => {
  assert.deepEqual(
    buildEnrichmentPayload({
      token: 'A'.repeat(64),
      name: '  Asha  ',
      cardCount: '3-6',
      monthlySpendBand: '50k-1l',
      primaryGoal: 'maximize_rewards',
      problemDetail: '  Caps are hard to remember.  ',
      topCards: ['  HDFC Bank Infinia  ', '', ' Axis Bank Atlas '],
      marketingConsent: true,
    }),
    {
      p_enrichment_token: 'a'.repeat(64),
      p_name: 'Asha',
      p_card_count: '3-6',
      p_monthly_spend_band: '50k-1l',
      p_primary_goal: 'maximize_rewards',
      p_problem_detail: 'Caps are hard to remember.',
      p_top_cards: ['HDFC Bank Infinia', 'Axis Bank Atlas'],
      p_marketing_consent: true,
    },
  );
});

test('join response accepts only a success row with a valid opaque token', () => {
  const token = '0123456789abcdef'.repeat(4);
  assert.equal(extractEnrichmentToken([{ status: 'accepted', enrichment_token: token }]), token);
  assert.throws(() => extractEnrichmentToken([{ status: 'accepted', enrichment_token: 'short' }]));
  assert.throws(() => extractEnrichmentToken([{ status: 'rejected', enrichment_token: token }]));
});
