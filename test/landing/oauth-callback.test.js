import test from 'node:test';
import assert from 'node:assert/strict';

import { oauthAppCallbackUrl } from '../../landing/oauth-callback.js';

test('root OAuth callback hands the one-time code to the app on the same origin', () => {
  assert.equal(
    oauthAppCallbackUrl('https://www.cardcompass.in/?code=one-time-code'),
    'https://www.cardcompass.in/app/?code=one-time-code',
  );
});

test('ordinary and malformed landing URLs are not redirected', () => {
  assert.equal(oauthAppCallbackUrl('https://www.cardcompass.in/'), null);
  assert.equal(oauthAppCallbackUrl('not a url'), null);
});

test('OAuth handoff drops unrelated query parameters and fragments', () => {
  assert.equal(
    oauthAppCallbackUrl(
      'https://www.cardcompass.in/?code=one-time-code&utm_source=private#fragment',
    ),
    'https://www.cardcompass.in/app/?code=one-time-code',
  );
});
