import test from 'node:test';
import assert from 'node:assert/strict';

import {
  PLAUSIBLE_ENDPOINT,
  installAnalyticsTransport,
} from '../../landing/analytics.js';

test('analytics transport suppresses implicit pageviews and forwards one sanitized manual pageview', async () => {
  const calls = [];
  const fakeFetch = async (input, init) => {
    calls.push({ input, init });
    return { ok: true, status: 202 };
  };
  const transport = installAnalyticsTransport({ fetchImpl: fakeFetch });

  const implicit = {
    n: 'pageview',
    u: 'https://cardcompass.in/?utm_source=newsletter&email=private%40example.com#token',
    r: 'https://search.example/?q=private',
    p: { email: 'private@example.com', placement: 'hero' },
  };
  await transport.fetch(PLAUSIBLE_ENDPOINT, {
    method: 'POST',
    body: JSON.stringify(implicit),
  });
  assert.equal(calls.length, 0, 'the tracker\'s implicit pageview must be suppressed');

  transport.enableManualPageview();
  await transport.fetch(PLAUSIBLE_ENDPOINT, {
    method: 'POST',
    body: JSON.stringify(implicit),
  });
  await transport.fetch(PLAUSIBLE_ENDPOINT, {
    method: 'POST',
    body: JSON.stringify({ ...implicit, u: 'https://cardcompass.in/duplicate/?ref=private' }),
  });

  assert.equal(calls.length, 1, 'exactly one manual pageview reaches Plausible');
  assert.equal(calls[0].input, PLAUSIBLE_ENDPOINT);
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    n: 'pageview',
    u: 'https://cardcompass.in/',
    p: { placement: 'hero' },
  });
});

test('analytics transport recognizes Request-like endpoints, sanitizes events, and passes other requests unchanged', async () => {
  const calls = [];
  const fakeFetch = async (input, init) => {
    calls.push({ input, init });
    return { ok: true };
  };
  const transport = installAnalyticsTransport({ fetchImpl: fakeFetch });
  const endpointRequest = { url: PLAUSIBLE_ENDPOINT };

  await transport.fetch(endpointRequest, {
    method: 'POST',
    body: JSON.stringify({
      n: 'Enrichment Submitted',
      u: 'https://cardcompass.in/apply/?utm_campaign=launch&ref=private',
      ref: 'private-referrer',
      utm_source: 'newsletter',
      p: { placement: 'hero', outcome: 'accepted', name: 'Private Person' },
    }),
  });

  const otherInput = '/landing/card-catalog.json?cache=1';
  const otherInit = { cache: 'force-cache', headers: { Accept: 'application/json' } };
  await transport.fetch(otherInput, otherInit);

  assert.equal(calls.length, 2);
  assert.equal(calls[0].input, endpointRequest);
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    n: 'Enrichment Submitted',
    u: 'https://cardcompass.in/apply/',
    p: { placement: 'hero', outcome: 'accepted' },
  });
  assert.equal(calls[1].input, otherInput);
  assert.equal(calls[1].init, otherInit, 'non-Plausible requests pass through unchanged');
});
