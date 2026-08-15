import test from 'node:test';
import assert from 'node:assert/strict';

import { buildPlausibleEvent, searchCards } from '../../landing/waitlist.js';

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
    }),
    {
      name: 'Waitlist Joined',
      options: {
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
    buildPlausibleEvent('Waitlist Error', { placement: 'hero<script>', outcome: 'rpc_failure' }),
    { name: 'Waitlist Error', options: { props: { outcome: 'rpc_failure' } } },
  );
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
