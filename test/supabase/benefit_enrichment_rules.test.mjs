import assert from 'node:assert/strict';
import test from 'node:test';

import {
  diffBenefits,
  extractGroundedBenefits,
} from '../../supabase/functions/_shared/benefit_enrichment.ts';

const SOURCE = 'https://issuer.example/cards/aurora';

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
