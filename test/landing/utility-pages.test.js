import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import {
  calculateCardComparison,
  calculateMilestone,
  calculateMovieOffer,
  renderBestCardResult,
  renderToolError,
} from '../../landing/tools/tools.js';

class FakeClassList {
  constructor() { this.values = new Set(); }
  add(...values) { values.forEach((value) => this.values.add(value)); }
  remove(...values) { values.forEach((value) => this.values.delete(value)); }
}

class FakeNode {
  constructor(tagName) {
    this.tagName = tagName.toUpperCase();
    this.children = [];
    this.textContent = '';
    this.className = '';
    this.classList = new FakeClassList();
    this.hidden = false;
  }
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this.children = [...nodes]; this.textContent = ''; }
  set innerHTML(_) { throw new Error('Unsafe innerHTML boundary reached'); }
}

const fakeDocument = { createElement: (tagName) => new FakeNode(tagName) };

function descendantTags(node) {
  return [node.tagName, ...node.children.flatMap(descendantTags)];
}

function descendantText(node) {
  return [node.textContent, ...node.children.map(descendantText)].join(' ');
}

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
      winners: ['Lower rate, open cap'],
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

test('best-card comparison supports two cards and reports every tied maximum', () => {
  const uncapped = calculateCardComparison({
    amount: 1000,
    cards: [
      { name: 'Card A', ratePercent: 5, capRemaining: '' },
      { name: 'Card B', ratePercent: 5, capRemaining: '' },
    ],
  });
  assert.deepEqual(uncapped.winners, ['Card A', 'Card B']);

  const capped = calculateCardComparison({
    amount: 1000,
    cards: [
      { name: 'Card A', ratePercent: 10, capRemaining: 50 },
      { name: 'Card B', ratePercent: 5, capRemaining: 50 },
      { name: 'Card C', ratePercent: 1, capRemaining: '' },
    ],
  });
  assert.deepEqual(capped.winners, ['Card A', 'Card B']);
});

test('milestone tracker distinguishes reached, on-track, and shortfall projections', () => {
  assert.deepEqual(
    calculateMilestone({ target: 100000, currentSpend: 72000, plannedSpend: 8000, daysRemaining: 14 }),
    {
      target: 100000,
      remainingNow: 28000,
      projectedSpend: 80000,
      projectedGap: 20000,
      dailyPace: 1428.57,
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

test('movie BOGO redemptions limit eligible pairs while percent and fixed offers apply once', () => {
  const bogo = (remainingUses) => calculateMovieOffer({
    ticketPrice: 400,
    ticketCount: 6,
    offerType: 'bogo',
    savingsCap: 2000,
    remainingUses,
  }).estimatedSavings;
  assert.equal(bogo(0), 0);
  assert.equal(bogo(1), 400);
  assert.equal(bogo(2), 800);

  for (const offerType of ['percent', 'fixed']) {
    const input = {
      ticketPrice: 400,
      ticketCount: 4,
      offerType,
      offerValue: offerType === 'percent' ? 25 : 300,
      savingsCap: 2000,
    };
    assert.equal(
      calculateMovieOffer({ ...input, remainingUses: 1 }).estimatedSavings,
      calculateMovieOffer({ ...input, remainingUses: 2 }).estimatedSavings,
    );
  }

  assert.throws(() => calculateMovieOffer({
    ticketPrice: 400,
    ticketCount: 2,
    offerType: 'bogo',
    savingsCap: 400,
    remainingUses: 1.5,
  }), /whole number/i);
});

test('result and error renderers keep malicious user values as text nodes', () => {
  const output = new FakeNode('section');
  const attack = '<img src=x onerror="globalThis.pwned=true">';

  renderBestCardResult(fakeDocument, output, {
    winner: attack,
    comparisons: [{ name: attack, grossValue: 10, estimatedValue: 10, capApplied: false }],
  });
  assert.match(descendantText(output), /<img src=x onerror=/);
  assert.ok(!descendantTags(output).includes('IMG'));

  renderToolError(fakeDocument, output, new Error(attack));
  assert.match(descendantText(output), /<img src=x onerror=/);
  assert.ok(!descendantTags(output).includes('IMG'));
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
    assert.match(html, /<form\b[\s\S]*?method="post"[\s\S]*?action="\/tool-unavailable\/"[\s\S]*?>/i);
    assert.match(html, /<noscript>/i);
    assert.match(html, /<section\b[\s\S]*?class="tool-output"[\s\S]*?aria-live="polite"[\s\S]*?hidden[\s\S]*?><\/section>/);
    assert.match(html, /How this estimate works/i);
    assert.match(html, /What this does not include/i);
    assert.match(html, /Author:\s*CardCompass product team/i);
    assert.match(html, /Reviewed by:\s*CardCompass\s+engineering/i);
    assert.match(html, /Last updated:\s*15 August 2026/i);
    assert.match(html, /href="https:\/\/www\.rbi\.org\.in\/[^"]+"/i);
    assert.match(html, /href="\/recommendation-disclaimer\/"/i);
    assert.match(
      html,
      new RegExp(`href="/\\?source=${source}&amp;landing_variant=${source}#apply"`),
    );
    assert.match(html, /"@type":\s*"WebApplication"/);
  }

  const css = await readFile(new URL('../../landing/resources.css', import.meta.url), 'utf8');
  assert.doesNotMatch(css, /\.tool-output\[hidden\]\s*\{[^}]*display\s*:\s*block/);
});

test('best-card form allows the third card to be omitted', async () => {
  const html = await readFile(new URL('../../landing/tools/best-card/index.html', import.meta.url), 'utf8');
  assert.doesNotMatch(html.match(/<input[^>]*name="card_3_name"[^>]*>/)?.[0] || '', /\brequired\b/);
});
