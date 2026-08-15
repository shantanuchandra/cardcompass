import test from 'node:test';
import assert from 'node:assert/strict';

import { captureFirstTouch } from '../../landing/waitlist.js';

function memoryStorage(initialValue = null) {
  let value = initialValue;
  return {
    getItem() { return value; },
    setItem(_key, next) { value = next; },
    value() { return value; },
  };
}

test('first touch captures sanitized source and query variant ahead of page defaults', () => {
  const storage = memoryStorage();

  const attribution = captureFirstTouch({
    locationHref: 'https://cardcompass.in/?source=best-card&landing_variant=best-card&utm_source=LinkedIn&utm_medium=Paid%20Social&utm_campaign=Founding%20100&utm_term=card%20rewards&utm_content=receipt',
    referrer: 'https://cardcompass.in/best-credit-card/?email=private@example.com',
    variant: 'receipt_v1',
    storage,
  });

  assert.deepEqual(attribution, {
    source: 'best-card',
    utm_source: 'LinkedIn',
    utm_medium: 'Paid Social',
    utm_campaign: 'Founding 100',
    utm_term: 'card rewards',
    utm_content: 'receipt',
    referrer_path: '/best-credit-card/',
    landing_variant: 'best-card',
  });
  assert.equal(JSON.parse(storage.value()).utm_source, 'LinkedIn');
});

test('first touch does not overwrite an earlier valid attribution', () => {
  const original = JSON.stringify({
    source: 'newsletter-guide',
    utm_source: 'newsletter',
    utm_medium: 'email',
    utm_campaign: null,
    utm_term: null,
    utm_content: null,
    referrer_path: '/guides/',
    landing_variant: 'receipt_v1',
  });
  const storage = memoryStorage(original);

  const attribution = captureFirstTouch({
    locationHref: 'https://cardcompass.in/?utm_source=paid',
    referrer: 'https://search.example/',
    variant: 'receipt_v2',
    storage,
  });

  assert.equal(attribution.utm_source, 'newsletter');
  assert.equal(attribution.source, 'newsletter-guide');
  assert.equal(attribution.landing_variant, 'receipt_v1');
  assert.equal(storage.value(), original);
});

test('first touch preserves valid pre-source storage while upgrading its shape', () => {
  const storage = memoryStorage(JSON.stringify({
    utm_source: 'original-newsletter',
    utm_medium: 'email',
    utm_campaign: null,
    utm_term: null,
    utm_content: null,
    referrer_path: '/original/',
    landing_variant: 'receipt_v1',
  }));

  const attribution = captureFirstTouch({
    locationHref: 'https://cardcompass.in/?source=paid-tool&utm_source=paid',
    variant: 'receipt_v2',
    storage,
  });

  assert.equal(attribution.source, null);
  assert.equal(attribution.utm_source, 'original-newsletter');
  assert.equal(attribution.landing_variant, 'receipt_v1');
});

test('attribution discards unsafe source and variants and strips referrer query data', () => {
  const attribution = captureFirstTouch({
    locationHref: `https://cardcompass.in/?source=${encodeURIComponent('<script>')}&landing_variant=${encodeURIComponent('Receipt Experiment!')}&utm_campaign=${'x'.repeat(151)}`,
    referrer: 'not a url',
    variant: 'Receipt Experiment!',
    storage: memoryStorage(),
  });

  assert.deepEqual(attribution, {
    source: null,
    utm_source: null,
    utm_medium: null,
    utm_campaign: null,
    utm_term: null,
    utm_content: null,
    referrer_path: null,
    landing_variant: null,
  });
});
