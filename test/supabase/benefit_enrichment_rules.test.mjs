import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  diffBenefits,
  extractGroundedBenefits,
  extractGroundedBenefitsV6,
} from '../../supabase/functions/_shared/benefit_enrichment.ts';

const SOURCE = 'https://issuer.example/cards/aurora';

test('keeps benefits-v5 synchronous legacy proposals and array exclusions unchanged', () => {
  // Catches an accidental v6 projection leaking into the rollback lane.
  const proposals = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 5% cashback on online spends, excluding fuel and wallet reloads.',
  }], 'benefits-v5');

  assert.equal(Array.isArray(proposals), true);
  assert.deepEqual(proposals.map((proposal) => ({
    parserVersion: proposal.parserVersion,
    dedupeKey: proposal.dedupeKey,
    valueConfig: proposal.valueConfig,
    exclusions: proposal.exclusions,
    benefitId: proposal.benefitId ?? null,
    conditionHash: proposal.conditionHash ?? null,
  })), [{
    parserVersion: 'benefits-v5',
    dedupeKey: 'benefit-58e9c49040ba5a39',
    valueConfig: undefined,
    exclusions: ['fuel', 'wallet reloads'],
    benefitId: null,
    conditionHash: null,
  }]);
});

test('projects v6 proposals through the card-scoped canonical contract and golden corpus', async () => {
  // Catches the v6 path silently keeping flat terms, legacy array exclusions,
  // or globally-scoped keys while the rollback v5 output remains unchanged.
  const golden = JSON.parse(readFileSync(
    new URL('./fixtures/benefit-enrichment/v6-golden.json', import.meta.url),
    'utf8',
  ));
  const cardId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  for (const fixture of golden) {
    const proposals = await extractGroundedBenefitsV6([{
      sourceUrl: SOURCE,
      text: fixture.text,
    }], 'benefits-v6', cardId);
    assert.deepEqual(proposals.map((proposal) => ({
      benefitId: proposal.benefitId,
      dedupeKey: proposal.dedupeKey,
      conditionHash: proposal.conditionHash,
      parserVersion: proposal.parserVersion,
      title: proposal.title,
      description: proposal.description,
      category: proposal.category,
      valueType: proposal.valueType,
      value: proposal.value ?? null,
      rate: proposal.rate ?? null,
      cap: proposal.cap ?? null,
      threshold: proposal.threshold ?? null,
      valueConfig: proposal.valueConfig,
      partners: proposal.partners ?? [],
      frequency: proposal.frequency ?? null,
      period: proposal.period ?? null,
      restrictions: proposal.restrictions,
      exclusions: proposal.exclusions,
      effectiveFrom: proposal.effectiveFrom ?? null,
      effectiveTo: proposal.effectiveTo ?? null,
      warnings: proposal.warnings,
    })), fixture.expected, fixture.name);
  }

  const [first] = await extractGroundedBenefitsV6([{
    sourceUrl: SOURCE,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'benefits-v6', cardId);
  const [sameTermsOtherCard] = await extractGroundedBenefitsV6([{
    sourceUrl: SOURCE,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'benefits-v6', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  assert.notEqual(first.dedupeKey, sameTermsOtherCard.dedupeKey);
});

test('extracts movie discounts, BOGO tickets, and annual allowances into the approved value-config contract', () => {
  // Catches the production failure where issuer pages were crawled but every
  // movie-specific sentence was discarded before staging.
  const benefits = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Get 25% off movie tickets up to Rs. 100 per transaction on BookMyShow.',
      'Buy one movie ticket and get the second ticket free on District, capped at ₹500, twice per month.',
      'Get free movie tickets worth Rs. 6,000 every year on BookMyShow.',
    ].join('\n'),
  }], 'benefits-v2');

  assert.deepEqual(
    benefits.map(({valueType, valueConfig, partners}) => ({
      valueType,
      valueConfig,
      partners,
    })).sort((left, right) => left.valueType.localeCompare(right.valueType)),
    [
      {
        valueType: 'annual_allowance',
        valueConfig: {
          category: 'movie_tickets',
          unit: 'fixed',
          annual_cap: 6000,
        },
        partners: ['BookMyShow'],
      },
      {
        valueType: 'bogo',
        valueConfig: {
          category: 'movie_tickets',
          discount_type: 'bogo',
          max_discount_per_transaction: 500,
          max_usage_per_month: 2,
        },
        partners: ['District'],
      },
      {
        valueType: 'percent_discount',
        valueConfig: {
          category: 'movie_tickets',
          discount_type: 'percent',
          discount_percent: 25,
          max_discount_per_transaction: 100,
        },
        partners: ['BookMyShow'],
      },
    ],
  );
});

test('keeps Rs abbreviations inside reward sentences so movie eligibility survives', () => {
  // Catches the sentence splitter treating the period in "Rs." as the end of
  // the sentence and silently dropping the threshold and movie restriction.
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Earn 10 reward points for every Rs. 100 spent on dining and movies.',
  }], 'benefits-v2');

  assert.equal(benefit.threshold, 100);
  assert.deepEqual(benefit.restrictions, ['dining and movies']);
  assert.deepEqual(benefit.valueConfig, {
    category: 'movies',
    multiplier: 10,
    unit: 'reward points per Rs. 100',
  });
});

test('extracts fixed-value movie discounts without mistaking the discount for a cap', () => {
  // Covers issuer wording such as Kotak's monthly PVR ticket discount. The
  // approved contract must retain the discount amount and booking partner.
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get Rs. 500 off on booking 2 movie tickets on BookMyShow every month.',
  }], 'benefits-v2');

  assert.equal(benefit.valueType, 'fixed_discount');
  assert.deepEqual(benefit.valueConfig, {
    category: 'movie_tickets',
    discount_type: 'fixed',
    discount_amount: 500,
  });
  assert.deepEqual(benefit.partners, ['BookMyShow']);
});

test('assembles adjacent official clauses for quarterly BOGO limits without converting them to monthly limits', () => {
  // AU Zenith+ publishes the offer, quarterly usage limit, cap, and partner
  // as separate bullets. They are one benefit contract, not independent rows.
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Complimentary (Buy 1 Get 1) 16 Movie & Event tickets.',
      'This benefit can be availed for a maximum of 4 times in calendar quarter.',
      'Maximum discount per ticket booking is Rs. 500.',
      'Plan your bookings on BookMyShow app or website.',
    ].join('\n'),
  }], 'benefits-v2');

  assert.equal(benefit.valueType, 'bogo');
  assert.deepEqual(benefit.valueConfig, {
    category: 'movie_tickets',
    discount_type: 'bogo',
    max_discount_per_transaction: 500,
    max_usage_per_period: 4,
    usage_period: 'quarter',
  });
  assert.deepEqual(benefit.partners, ['BookMyShow']);
});

test('does not classify cinema food and beverage discounts as movie-ticket discounts', () => {
  const benefits = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get a flat 20% discount on Food & Beverages at any PVR INOX theater on your next visit to the Movies!',
  }], 'benefits-v2');

  assert.deepEqual(benefits, []);
});

test('attaches an adjacent per-transaction cap to a movie percentage discount', () => {
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      '50% off on movie tickets via BookMyShow.',
      'Up to 4 discounted tickets per card monthly.',
      'Maximum discount is ₹600 per transaction.',
    ].join('\n'),
  }], 'benefits-v3');

  assert.deepEqual(benefit.valueConfig, {
    category: 'movie_tickets',
    discount_type: 'percent',
    discount_percent: 50,
    max_discount_per_transaction: 600,
  });
});

test('assembles a monthly movie-ticket milestone and its adjacent ticket value', () => {
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Get 1 PVR INOX Movie Ticket on every spend of Rs. 10,000 in a monthly billing cycle.',
      'Earn tickets worth Rs. 300 each for achieving every spends milestone of Rs. 10,000.',
    ].join('\n'),
  }], 'benefits-v3');

  assert.equal(benefit.valueType, 'milestone');
  assert.deepEqual(benefit.valueConfig, {
    category: 'movie_tickets',
    milestone_type: 'monthly',
    threshold_amount: 10000,
    reward_value: 300,
  });
  assert.deepEqual(benefit.partners, ['PVR', 'INOX']);
});

test('attaches an adjacent redemption platform to an annual movie allowance', () => {
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      '<li>Free Movie Tickets worth Rs. 6,000 every year</li>',
      '<li>Transaction valid for at least 2 tickets per booking per month.</li>',
      '<li>Maximum discount is Rs. 250 per ticket for 2 tickets only.</li>',
      '<li>Convenience Fee would be chargeable</li>',
      '<li>This offer is valid on Primary Cards only</li>',
      '<li>To know the Redemption process <a href="https://in.bookmyshow.com/offers/sbi-elite">click here</a></li>',
    ].join('\n'),
  }], 'benefits-v5');

  assert.equal(benefit.valueType, 'annual_allowance');
  assert.deepEqual(benefit.valueConfig, {
    category: 'movie_tickets',
    unit: 'fixed',
    annual_cap: 6000,
  });
  assert.deepEqual(benefit.partners, ['BookMyShow']);
});

test('keeps the cap from an adjacent BOGO offer out of a percentage offer', () => {
  const benefits = extractGroundedBenefits(
    [{
      sourceUrl: SOURCE,
      text: [
        'Get 5% off movie tickets.',
        'Buy 1 movie ticket and get 1 free on BookMyShow, capped at Rs. 500 per booking, twice per quarter.',
      ].join('\n'),
    }],
    'benefits-v5',
  );

  const percent = benefits.find((benefit) => benefit.valueType === 'percent_discount');
  const bogo = benefits.find((benefit) => benefit.valueType === 'bogo');
  assert.ok(percent, 'percentage offer was not extracted');
  assert.ok(bogo, 'BOGO offer was not extracted');
  assert.equal(percent.valueConfig.max_discount_per_transaction, undefined);
  assert.equal(bogo.valueConfig.max_discount_per_transaction, 500);
});

test('treats an annual offer as a boundary when the period comes first', () => {
  const benefits = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Get 5% off movie tickets.',
      'Every year get free movie tickets worth Rs. 6,000.',
      'Maximum discount is Rs. 250 per ticket.',
    ].join('\n'),
  }], 'benefits-v5');

  const percent = benefits.find((benefit) => benefit.valueType === 'percent_discount');
  const annual = benefits.find((benefit) => benefit.valueType === 'annual_allowance');
  assert.ok(percent, 'percentage offer was not extracted');
  assert.ok(annual, 'annual offer was not extracted');
  assert.equal(percent.valueConfig.max_discount_per_transaction, undefined);
  assert.equal(annual.valueConfig.annual_cap, 6000);
});

test('extracts only explicit cashback values, caps, periods, and exclusions', () => {
  // Catches an extractor that invents a cap, merchant, or eligibility from marketing copy.
  const benefits = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      '<p>Earn 10% cashback on dining spends, capped at ₹500 per statement month.</p>',
      'Get 5% cashback on online spends, excluding fuel and wallet reloads.',
      'Enjoy exclusive lifestyle rewards curated for you.',
    ].join('\n'),
  }], 'grounded-v1');

  assert.equal(benefits.length, 2);
  assert.deepEqual(
    benefits.map(({rate, cap, period, restrictions, exclusions}) => ({
      rate, cap, period, restrictions, exclusions,
    })).sort((left, right) => right.rate - left.rate),
    [
      {
        rate: 10,
        cap: 500,
        period: 'statement month',
        restrictions: ['dining spends'],
        exclusions: [],
      },
      {
        rate: 5,
        cap: undefined,
        period: undefined,
        restrictions: ['online spends'],
        exclusions: ['fuel', 'wallet reloads'],
      },
    ],
  );
  assert.equal(benefits.some((benefit) => /lifestyle/i.test(benefit.title)), false);
  assert.equal(benefits.every((benefit) => benefit.sourceUrl === SOURCE), true);
  assert.equal(benefits.every((benefit) => benefit.sourceExcerpt.length > 0), true);
  assert.equal(benefits.every((benefit) => !/[<>]/.test(benefit.sourceExcerpt)), true);
  assert.equal(benefits.every((benefit) => benefit.confidence.rate >= 0.9), true);
});

test('normalizes explicit reward, lounge, and expiry terms with evidence per field', () => {
  // Catches omitted threshold/frequency/date facts or a proposal without field attribution.
  const benefits = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Earn 5 reward points for every ₹150 spent on eligible purchases, valid until 31 December 2026.',
      'Get 2 complimentary airport lounge visits per quarter.',
    ].join('\n'),
  }], 'grounded-v1');

  const rewards = benefits.find((benefit) => benefit.valueType === 'reward_points');
  const lounge = benefits.find((benefit) => benefit.valueType === 'lounge_access');
  const expiring = benefits.find((benefit) => benefit.effectiveTo === '2026-12-31');

  assert.deepEqual(
    {value: rewards?.value, threshold: rewards?.threshold, restrictions: rewards?.restrictions},
    {value: 5, threshold: 150, restrictions: ['eligible purchases']},
  );
  assert.deepEqual(
    {value: lounge?.value, frequency: lounge?.frequency, period: lounge?.period},
    {value: 2, frequency: '2 visits', period: 'quarter'},
  );
  assert.equal(expiring?.effectiveTo, '2026-12-31');
  assert.match(rewards?.evidence.threshold ?? '', /₹150/i);
  assert.match(lounge?.evidence.frequency ?? '', /2 complimentary airport lounge visits/i);
  assert.match(expiring?.evidence.effectiveTo ?? '', /31 December 2026/i);
});

test('deduplicates identical official wording across documents but keeps different conditions separate', () => {
  // Catches a key that depends on whitespace/source or ignores terms that change an offer.
  const [first] = extractGroundedBenefits([{
    sourceUrl: `${SOURCE}/page`,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'grounded-v1');
  const duplicateAndConflict = extractGroundedBenefits([
    {
      sourceUrl: `${SOURCE}/terms`,
      text: 'Get   10%   cashback on dining spends, capped at ₹500 per statement month.',
    },
    {
      sourceUrl: `${SOURCE}/revised-terms`,
      text: 'Get 10% cashback on dining spends, capped at ₹1,000 per statement month.',
    },
  ], 'grounded-v1');

  assert.equal(duplicateAndConflict.length, 2);
  assert.equal(duplicateAndConflict.some((benefit) => benefit.dedupeKey === first.dedupeKey), true);
  assert.equal(new Set(duplicateAndConflict.map((benefit) => benefit.dedupeKey)).size, 2);
  assert.equal(duplicateAndConflict.every((benefit) => benefit.warnings.includes('conflicting_official_terms')), true);
});

test('produces deterministic additions, modifications, unchanged benefits, conflicts, and informational removals', () => {
  // Catches a diff that turns absent proposals into a mutation or matches conflicting terms arbitrarily.
  const current = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
      'Get 2 complimentary airport lounge visits per quarter.',
    ].join('\n'),
  }], 'grounded-v1');
  const proposed = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: [
      'Get 10% cashback on dining spends, capped at ₹750 per statement month.',
      'Earn 5 reward points for every ₹150 spent on eligible purchases.',
    ].join('\n'),
  }], 'grounded-v1');

  const diff = diffBenefits(current, proposed);

  assert.equal(diff.additions.length, 1);
  assert.equal(diff.modifications.length, 1);
  assert.equal(diff.unchanged.length, 0);
  assert.equal(diff.possibleRemovals.length, 1);
  assert.deepEqual(diff.possibleRemovals[0], {
    benefit: current.find((benefit) => benefit.valueType === 'lounge_access'),
    informational: true,
  });
  assert.equal(diff.possibleRemovals[0].approvalAction, undefined);
  assert.equal(diff.conflicts.length, 0);

  const ambiguous = diffBenefits(current, [
    ...proposed,
    ...extractGroundedBenefits([{
      sourceUrl: `${SOURCE}/different-terms`,
      text: 'Get 10% cashback on dining spends, capped at ₹1,000 per statement month.',
    }], 'grounded-v1'),
  ]);
  assert.equal(ambiguous.conflicts.length > 0, true);
  assert.equal(ambiguous.additions.length, 1);
  assert.equal(ambiguous.possibleRemovals.length, 1);
});

test('matches benefit subjects independently from mutable reward conditions', () => {
  // Catches semantic matching that treats a changed rate as a new benefit, or treats dining and grocery as the same subject.
  const diningTen = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'grounded-v1');
  const diningFive = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 5% cashback on dining spends, capped at ₹750 per statement month.',
  }], 'grounded-v1');
  const groceryTen = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 10% cashback on grocery spends, capped at ₹500 per statement month.',
  }], 'grounded-v1');

  const changedRate = diffBenefits(diningTen, diningFive);
  assert.equal(changedRate.modifications.length, 1);
  assert.equal(changedRate.additions.length, 0);
  assert.equal(changedRate.possibleRemovals.length, 0);

  const changedSubject = diffBenefits(diningTen, groceryTen);
  assert.equal(changedSubject.modifications.length, 0);
  assert.equal(changedSubject.additions.length, 1);
  assert.equal(changedSubject.possibleRemovals.length, 1);
});

test('keeps divergent official terms as conflicts rather than silently matching them', () => {
  // Catches a semantic key that includes mutable rate/condition fields and misses conflicting official documents.
  const current = extractGroundedBenefits([{
    sourceUrl: `${SOURCE}/current`,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'grounded-v1');
  const proposed = extractGroundedBenefits([
    {
      sourceUrl: `${SOURCE}/page`,
      text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
    },
    {
      sourceUrl: `${SOURCE}/terms`,
      text: 'Get 5% cashback on dining spends, capped at ₹750 per statement month.',
    },
  ], 'grounded-v1');

  assert.equal(proposed.length, 2);
  assert.equal(proposed.every((benefit) => benefit.warnings.includes('conflicting_official_terms')), true);
  assert.equal(diffBenefits(current, proposed).conflicts.length > 0, true);
});

test('does not treat a reused dedupe key with divergent normalized conditions as unchanged', () => {
  // Catches Map-based dedupe overwrites that hide differing terms under one claimed key.
  const [base] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 10% cashback on dining spends, capped at ₹500 per statement month.',
  }], 'grounded-v1');
  const divergent = { ...base, cap: 999 };

  const diff = diffBenefits([base, divergent], [base]);
  assert.equal(diff.unchanged.length, 0);
  assert.equal(diff.conflicts.some((conflict) => conflict.code === 'dedupe_key_condition_mismatch'), true);

  const currentOnly = diffBenefits([base, divergent], []);
  assert.equal(currentOnly.conflicts.some((conflict) => conflict.code === 'dedupe_key_condition_mismatch'), true);
  assert.equal(currentOnly.possibleRemovals.length, 0);
});

test('stops exclusions before a stated expiry or other benefit clause', () => {
  // Catches exclusions absorbing expiry, cap, or period wording into the merchant list.
  const [benefit] = extractGroundedBenefits([{
    sourceUrl: SOURCE,
    text: 'Get 5% cashback on online spends, excluding fuel and wallet reloads, valid until 31 December 2026.',
  }], 'grounded-v1');

  assert.deepEqual(benefit.exclusions, ['fuel', 'wallet reloads']);
  assert.equal(benefit.effectiveTo, '2026-12-31');
});
