import { sanitizeAnalyticsPayload } from './waitlist.js';

export const PLAUSIBLE_ENDPOINT = 'https://plausible.io/api/event';

function inputUrl(input) {
  if (typeof input === 'string') return input;
  if (input && typeof input.url === 'string') return input.url;
  if (input instanceof URL) return input.href;
  return null;
}

function droppedResponse(responseFactory) {
  const response = responseFactory
    ? responseFactory()
    : (typeof Response === 'function' ? new Response(null, { status: 202 }) : { status: 202 });
  return Promise.resolve(response);
}

export function installAnalyticsTransport({
  fetchImpl,
  endpoint = PLAUSIBLE_ENDPOINT,
  responseFactory,
} = {}) {
  if (typeof fetchImpl !== 'function') throw new TypeError('A fetch implementation is required.');

  let manualPageviewEnabled = false;
  let pageviewForwarded = false;

  function guardedFetch(input, init = {}) {
    if (inputUrl(input) !== endpoint) return fetchImpl(input, init);
    if (typeof init.body !== 'string') return droppedResponse(responseFactory);

    let payload;
    try {
      payload = JSON.parse(init.body);
    } catch {
      return droppedResponse(responseFactory);
    }

    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return droppedResponse(responseFactory);
    }
    if (payload.n === 'pageview') {
      if (!manualPageviewEnabled || pageviewForwarded) return droppedResponse(responseFactory);
      pageviewForwarded = true;
    }

    return fetchImpl(input, {
      ...init,
      body: JSON.stringify(sanitizeAnalyticsPayload(payload)),
    });
  }

  return {
    fetch: guardedFetch,
    enableManualPageview() {
      manualPageviewEnabled = true;
    },
  };
}
