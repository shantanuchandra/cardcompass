import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildApplicationReceipt,
  buildPlausibleEvent,
  sanitizeAnalyticsPayload,
  searchCards,
  stripAnalyticsUrl,
} from '../../landing/waitlist.js';

test('Plausible event keeps only non-sensitive context properties', () => {
  assert.deepEqual(
    buildPlausibleEvent('Waitlist Joined', {
      placement: 'hero',
      step: 'email',
      variant: 'receipt_v1',
      outcome: 'accepted',
      email: 'private@example.com',
      name: 'Private Person',
      cardCount: '7+',
      monthlySpendBand: '1l-plus',
      primaryGoal: 'maximize_rewards',
      topCards: ['A', 'B'],
      problemDetail: 'Private detail',
      utm_campaign: 'private-ish campaign',
    }, 'https://cardcompass.in/?utm_source=private&email=private@example.com#private'),
    {
      name: 'Waitlist Joined',
      options: {
        url: 'https://cardcompass.in/',
        props: {
          placement: 'hero',
          step: 'email',
          variant: 'receipt_v1',
          outcome: 'accepted',
        },
      },
    },
  );
});

test('Plausible event rejects unknown names and property values', () => {
  assert.equal(buildPlausibleEvent('Email private@example.com', { placement: 'hero' }), null);
  assert.deepEqual(
    buildPlausibleEvent(
      'Waitlist Error',
      { placement: 'hero<script>', outcome: 'rpc_failure' },
      'https://cardcompass.in/apply/?ref=private',
    ),
    {
      name: 'Waitlist Error',
      options: { url: 'https://cardcompass.in/apply/', props: { outcome: 'rpc_failure' } },
    },
  );
});

test('analytics URL stripping removes query parameters and fragments', () => {
  assert.equal(
    stripAnalyticsUrl('https://cardcompass.in/apply/?utm_source=campaign&ref=partner&email=private%40example.com#token'),
    'https://cardcompass.in/apply/',
  );
});

test('Plausible request transform removes URL attribution, referrer, and unsafe props at the payload boundary', () => {
  assert.deepEqual(
    sanitizeAnalyticsPayload({
      n: 'Enrichment Submitted',
      u: 'https://cardcompass.in/?utm_source=campaign&utm_medium=email&utm_campaign=founding&ref=partner',
      d: 'cardcompass.in',
      r: 'https://search.example/results?q=private+person',
      ref: 'private-ref',
      utm_source: 'campaign',
      email: 'private@example.com',
      name: 'Private Person',
      m: { email: 'private@example.com', campaign: 'founding' },
      unknown: { nested: { email: 'private@example.com' } },
      p: {
        placement: 'hero',
        outcome: 'accepted',
        email: 'private@example.com',
        cardCount: '7+',
        utm_campaign: 'founding',
        metadata: { email: 'private@example.com' },
      },
    }),
    {
      n: 'Enrichment Submitted',
      u: 'https://cardcompass.in/',
      d: 'cardcompass.in',
      r: '',
      p: { placement: 'hero', outcome: 'accepted' },
    },
  );
});

test('success-shaped enrichment produces a decoy-neutral receipt and event', () => {
  const receipt = buildApplicationReceipt(true);

  assert.deepEqual(receipt, {
    eyebrow: 'Details received',
    title: 'Application step processed.',
    body: 'If these details matched an active application, they were processed. Keep an eye on your inbox for early-access updates.',
    eventName: 'Enrichment Submitted',
  });
  assert.doesNotMatch(JSON.stringify(receipt), /qualified|saved|reviewed|selected/i);
});

test('card search matches bank and card name, excluding selected cards', () => {
  const cards = [
    { id: '1', bank: 'HDFC Bank', card_name: 'Infinia' },
    { id: '2', bank: 'Axis Bank', card_name: 'Atlas' },
    { id: '3', bank: 'HDFC Bank', card_name: 'Diners Club Black' },
  ];

  assert.deepEqual(searchCards(cards, 'hdfc', ['HDFC Bank — Infinia']), [
    { id: '3', bank: 'HDFC Bank', card_name: 'Diners Club Black', label: 'HDFC Bank — Diners Club Black' },
  ]);
});

test('card search returns no suggestions for a blank query and limits results', () => {
  const cards = Array.from({ length: 12 }, (_, index) => ({
    id: String(index),
    bank: 'Bank',
    card_name: `Card ${index}`,
  }));

  assert.deepEqual(searchCards(cards, '   ', []), []);
  assert.equal(searchCards(cards, 'card', []).length, 8);
});
