import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import {
  calculateCardComparison,
  calculateMilestone,
  calculateMovieOffer,
} from '../../landing/tools/tools.js';

test('best-card comparison applies the remaining cap before selecting a winner', () => {
  assert.deepEqual(
    calculateCardComparison({
      amount: 4000,
      cards: [
        { name: 'High rate, low cap', ratePercent: 5, capRemaining: 100 },
        { name: 'Lower rate, open cap', ratePercent: 3, capRemaining: 500 },
      ],
    }),
    {
      amount: 4000,
      winner: 'Lower rate, open cap',
      comparisons: [
        { name: 'High rate, low cap', grossValue: 200, estimatedValue: 100, capApplied: true },
        { name: 'Lower rate, open cap', grossValue: 120, estimatedValue: 120, capApplied: false },
      ],
    },
  );
});

test('best-card comparison rejects missing and negative inputs', () => {
  assert.throws(() => calculateCardComparison({ amount: 0, cards: [] }), /positive purchase amount/i);
  assert.throws(
    () => calculateCardComparison({
      amount: 1000,
      cards: [
        { name: 'Invalid Card', ratePercent: -1 },
        { name: 'Valid Card', ratePercent: 1 },
      ],
    }),
    /rate/i,
  );
});

test('milestone tracker distinguishes reached, on-track, and shortfall projections', () => {
  assert.deepEqual(
    calculateMilestone({ target: 100000, currentSpend: 72000, plannedSpend: 8000, daysRemaining: 14 }),
    {
      target: 100000,
      remainingNow: 28000,
      projectedSpend: 80000,
      projectedGap: 20000,
      dailyPace: 2000,
      status: 'shortfall',
    },
  );
  assert.equal(
    calculateMilestone({ target: 100000, currentSpend: 72000, plannedSpend: 30000, daysRemaining: 14 }).status,
    'on_track',
  );
  assert.equal(
    calculateMilestone({ target: 100000, currentSpend: 101000, plannedSpend: 0, daysRemaining: 0 }).status,
    'reached',
  );
});

test('movie-offer estimate applies offer type, cap, remaining use, and fees', () => {
  assert.deepEqual(
    calculateMovieOffer({
      ticketPrice: 450,
      ticketCount: 2,
      offerType: 'bogo',
      offerValue: 0,
      savingsCap: 300,
      convenienceFeePerTicket: 35,
      remainingUses: 1,
    }),
    {
      ticketSubtotal: 900,
      fees: 70,
      estimatedSavings: 300,
      estimatedPayable: 670,
      effectiveSavingsPercent: 30.93,
      available: true,
    },
  );

  assert.equal(
    calculateMovieOffer({
      ticketPrice: 500,
      ticketCount: 2,
      offerType: 'percent',
      offerValue: 25,
      savingsCap: 1000,
      convenienceFeePerTicket: 0,
      remainingUses: 0,
    }).estimatedSavings,
    0,
  );
});

test('utility pages are substantive applications with assumptions and attributed waitlist links', async () => {
  const pages = [
    ['best-card', 'best-card'],
    ['milestone-tracker', 'milestone-tracker'],
    ['movie-offers', 'movie-offers'],
  ];

  for (const [directory, source] of pages) {
    const html = await readFile(
      new URL(`../../landing/tools/${directory}/index.html`, import.meta.url),
      'utf8',
    );
    const visibleText = html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');

    assert.ok(visibleText.length > 1800, `${source} should not be thin content`);
    assert.match(html, /<form\b[^>]*data-tool-form/);
    assert.match(html, /<section class="tool-output"[^>]*aria-live="polite" hidden><\/section>/);
    assert.match(html, /How this estimate works/i);
    assert.match(html, /What this does not include/i);
    assert.match(
      html,
      new RegExp(`href="/\\?source=${source}&amp;landing_variant=${source}#apply"`),
    );
    assert.match(html, /"@type":\s*"WebApplication"/);
  }

  const css = await readFile(new URL('../../landing/resources.css', import.meta.url), 'utf8');
  assert.doesNotMatch(css, /\.tool-output\[hidden\]\s*\{[^}]*display\s*:\s*block/);
});
