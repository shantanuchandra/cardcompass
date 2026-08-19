import assert from 'node:assert/strict';
import test from 'node:test';

import {
  OfficialFetchError,
  fetchOfficialIssuerResource,
  fetchOfficialIssuerObservation,
  officialResourceText,
} from '../../supabase/functions/_shared/official_issuer_fetch.ts';

const issuer = 'Kotak Bank';
const officialUrl = 'https://www.kotak.com/rd/white-reserve';
const publicDns = async () => ['93.184.216.34'];

function response(body, options = {}) {
  return new Response(body, {
    status: options.status ?? 200,
    headers: options.headers ?? {'content-type': 'text/html; charset=utf-8'},
  });
}

function streamingResponse(options = {}) {
  let cancelled = false;
  const stream = new ReadableStream({
    start(controller) {
      for (const chunk of options.chunks ?? []) controller.enqueue(chunk);
      if (options.close !== false) controller.close();
    },
    cancel() {
      cancelled = true;
    },
  });
  return {
    response: new Response(stream, {
      status: options.status ?? 200,
      headers: options.headers ?? {'content-type': 'text/html'},
    }),
    wasCancelled: () => cancelled,
  };
}

async function rejectsWith(input, code) {
  await assert.rejects(
    () => fetchOfficialIssuerResource(input),
    (error) => error instanceof Error && error.message === code,
  );
}

function settlesWithin(operation, timeoutMs = 30) {
  return Promise.race([
    operation,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error('fetch did not settle')), timeoutMs);
    }),
  ]);
}

test('extracts benefit text from safely fetched PDF bytes', async () => {
  const pdf = new TextEncoder().encode(
    '%PDF-1.4\n1 0 obj<</Length 78>>stream\nBT (Get 2 complimentary lounge visits per quarter.) Tj ET\nendstream\nendobj\n%%EOF',
  );
  const text = await officialResourceText({
    submittedUrl: officialUrl,
    finalUrl: officialUrl,
    canonicalUrl: officialUrl,
    contentType: 'application/pdf',
    bytes: pdf,
    text: '',
    contentHash: 'pdf-hash',
    retrievedAt: '2026-08-17T00:00:00.000Z',
  });

  assert.match(text, /2 complimentary lounge visits per quarter/i);
});

async function rejectsWithin(input, code) {
  await assert.rejects(
    () => settlesWithin(fetchOfficialIssuerResource(input)),
    (error) => error instanceof Error && error.message === code,
  );
}

test('rejects non-HTTPS and off-issuer URLs before requesting them', async () => {
  await rejectsWith({
    issuer,
    url: 'http://www.kotak.com/rd/white-reserve',
    fetchImpl: async () => assert.fail('must not fetch unapproved URL'),
    resolveHost: publicDns,
  }, 'unapproved_domain');
  await rejectsWith({
    issuer,
    url: 'https://attacker.example/rd/white-reserve',
    fetchImpl: async () => assert.fail('must not fetch unapproved URL'),
    resolveHost: publicDns,
  }, 'unapproved_domain');
});

test('rejects an official hostname that resolves to a loopback or private address', async () => {
  for (const address of ['127.0.0.1', '10.1.2.3', '::1', 'fd00::1', 'fe80::1']) {
    await rejectsWith({
      issuer,
      url: officialUrl,
      fetchImpl: async () => assert.fail('must not fetch private address'),
      resolveHost: async () => [address],
    }, 'private_address');
  }
});

test('revalidates every redirect target before requesting it', async () => {
  let calls = 0;
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => {
      calls += 1;
      return response('', {
        status: 302,
        headers: {location: 'https://attacker.example/steal'},
      });
    },
    resolveHost: publicDns,
  }, 'redirect_rejected');
  assert.equal(calls, 1);
});

test('sanitizes malformed redirect locations into the redirect rejection code', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('', {
      status: 302,
      headers: {location: 'https://['},
    }),
    resolveHost: publicDns,
  }, 'redirect_rejected');
});

test('allows HTML, XHTML, and PDF by default while reserving XML for sitemap fetches', async () => {
  for (const contentType of [
    'text/html',
    'application/xhtml+xml',
    'application/pdf',
  ]) {
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      fetchImpl: async () => response('issuer content', {
        headers: {'content-type': contentType},
      }),
      resolveHost: publicDns,
    });
    assert.equal(result.contentType, contentType);
  }
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('<urlset/>', {
      headers: {'content-type': 'application/xml'},
    }),
    resolveHost: publicDns,
  }, 'unsupported_content');
  let sitemapAccept = '';
  const sitemap = await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    contentPurpose: 'sitemap',
    fetchImpl: async (_url, init) => {
      sitemapAccept = new Headers(init.headers).get('accept') ?? '';
      return response('<urlset/>', {headers: {'content-type': 'application/xml'}});
    },
    resolveHost: publicDns,
  });
  assert.equal(sitemap.contentType, 'application/xml');
  assert.match(sitemapAccept, /application\/xml/);
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('{"not":"issuer content"}', {
      headers: {'content-type': 'application/json'},
    }),
    resolveHost: publicDns,
  }, 'unsupported_content');
});

test('enforces the eight-megabyte declared and actual response limits', async () => {
  const declared = streamingResponse({
    close: false,
    headers: {'content-type': 'text/html', 'content-length': '8388609'},
  });
  let declaredSignal;
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async (_url, init) => {
      declaredSignal = init.signal;
      return declared.response;
    },
    resolveHost: publicDns,
  }, 'oversized');
  assert.equal(declared.wasCancelled(), true);
  assert.equal(declaredSignal.aborted, true);
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response(new Uint8Array(8 * 1024 * 1024 + 1), {
      headers: {'content-type': 'application/pdf'},
    }),
    resolveHost: publicDns,
  }, 'oversized');
});

test('stops reading, cancels the reader, and aborts once streamed bytes exceed the limit', async () => {
  const streamed = streamingResponse({
    chunks: [new Uint8Array([1, 2]), new Uint8Array([3, 4])],
    close: false,
  });
  let signal;
  await rejectsWith({
    issuer,
    url: officialUrl,
    maxBytes: 3,
    fetchImpl: async (_url, init) => {
      signal = init.signal;
      return streamed.response;
    },
    resolveHost: publicDns,
  }, 'oversized');
  assert.equal(streamed.wasCancelled(), true);
  assert.equal(signal.aborted, true);
});

test('does not await a never-settling body cancellation before reporting oversized', async () => {
  let cancellationRequested = false;
  const body = new ReadableStream({
    cancel() {
      cancellationRequested = true;
      return new Promise(() => {});
    },
  });
  await rejectsWithin({
    issuer,
    url: officialUrl,
    fetchImpl: async () => new Response(body, {
      headers: {'content-type': 'text/html', 'content-length': '8388609'},
    }),
    resolveHost: publicDns,
  }, 'oversized');
  assert.equal(cancellationRequested, true);
});

test('does not await a never-settling reader cancellation after a stalled read times out', async () => {
  let cancellationRequested = false;
  const body = new ReadableStream({
    pull() {},
    cancel() {
      cancellationRequested = true;
      return new Promise(() => {});
    },
  });
  await rejectsWithin({
    issuer,
    url: officialUrl,
    timeoutMs: 5,
    fetchImpl: async () => new Response(body, {headers: {'content-type': 'text/html'}}),
    resolveHost: publicDns,
  }, 'timeout');
  assert.equal(cancellationRequested, true);
});

test('does not let reader cleanup replace an oversized failure code', async () => {
  const reader = {
    read: async () => ({done: false, value: new Uint8Array([1, 2, 3, 4])}),
    cancel: async () => undefined,
    releaseLock: () => { throw new Error('lock cleanup failed'); },
  };
  const mockResponse = {
    status: 200,
    ok: true,
    headers: new Headers({'content-type': 'text/html'}),
    body: {getReader: () => reader},
  };
  await rejectsWith({
    issuer,
    url: officialUrl,
    maxBytes: 3,
    fetchImpl: async () => mockResponse,
    resolveHost: publicDns,
  }, 'oversized');
});

test('cancels each redirect response body before following the approved location', async () => {
  const redirect = streamingResponse({
    close: false,
    status: 302,
    headers: {location: '/rd/white-reserve?step=2'},
  });
  let calls = 0;
  await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) return redirect.response;
      assert.equal(redirect.wasCancelled(), true);
      return response('approved content');
    },
    resolveHost: publicDns,
  });
  assert.equal(calls, 2);
});

test('uses one timeout deadline for stalled DNS and all redirect hops', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    timeoutMs: 5,
    fetchImpl: async () => assert.fail('must not fetch while DNS is stalled'),
    resolveHost: async () => new Promise(() => {}),
  }, 'timeout');

  let resolutions = 0;
  await rejectsWith({
    issuer,
    url: officialUrl,
    timeoutMs: 5,
    fetchImpl: async () => response('', {
      status: 302,
      headers: {location: '/rd/white-reserve?next=1'},
    }),
    resolveHost: async () => {
      resolutions += 1;
      return resolutions === 1 ? ['203.0.113.20'] : new Promise(() => {});
    },
  }, 'timeout');
});

test('aborts a fetch after its configured timeout and exposes only the timeout code', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    timeoutMs: 5,
    fetchImpl: async (_url, init) => new Promise((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason));
    }),
    resolveHost: publicDns,
  }, 'timeout');
});

test('sanitizes transport and HTTP failures into the approved error codes', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => { throw new Error('socket reset at 10.0.0.1'); },
    resolveHost: publicDns,
  }, 'unreachable');
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('service failure', {status: 503}),
    resolveHost: publicDns,
  }, 'http_5xx');
});

test('returns canonical URLs, text, bytes, timestamp, and a SHA-256 body hash', async () => {
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: 'https://WWW.KOTAK.COM:443/rd//white-reserve/?b=2&a=1#ignored',
    fetchImpl: async (url) => {
      assert.equal(url, 'https://www.kotak.com/rd/white-reserve?a=1&b=2');
      return response('official body');
    },
    resolveHost: publicDns,
  });

  assert.deepEqual(
    {
      submittedUrl: result.submittedUrl,
      finalUrl: result.finalUrl,
      canonicalUrl: result.canonicalUrl,
      contentType: result.contentType,
      bytes: result.bytes.length,
      text: result.text,
      contentHash: result.contentHash,
    },
    {
      submittedUrl: 'https://WWW.KOTAK.COM:443/rd//white-reserve/?b=2&a=1#ignored',
      finalUrl: 'https://www.kotak.com/rd/white-reserve?a=1&b=2',
      canonicalUrl: 'https://www.kotak.com/rd/white-reserve',
      contentType: 'text/html',
      bytes: 13,
      text: 'official body',
      contentHash: '62a1c97ac2be209866e770e905bb11268f8e247ee0e66fbd318117988f234865',
    },
  );
  assert.match(result.retrievedAt, /^\d{4}-\d{2}-\d{2}T/);
});

test('preserves status, bounded validators, and exact transient identity without persistable secrets', async () => {
  const submitted = `${officialUrl}?session=secret&utm_source=mail#private`;
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: submitted,
    now: () => Date.parse('2026-08-19T10:00:00.000Z'),
    fetchImpl: async () => response('official body', {headers: {
      'content-type': 'text/html; charset=utf-8',
      etag: `"${'a'.repeat(700)}"`,
      'last-modified': 'Wed, 19 Aug 2026 09:00:00 GMT',
    }}),
    resolveHost: publicDns,
  });
  assert.equal(result.status, 200);
  assert.equal(result.submittedUrl, submitted);
  assert.equal(result.finalUrl.includes('session=secret'), true);
  assert.equal(result.canonicalUrl, officialUrl);
  assert.equal(result.notModified, false);
  assert.equal(result.etag.length, 512);
  assert.equal(result.retrievedAt, '2026-08-19T10:00:00.000Z');
});

test('sends validators only for a compatible parser cache and represents 304 without a body', async () => {
  for (const [cachedParserVersion, expectedConditional] of [['benefits-v6', true], ['benefits-v5', false]]) {
    let headers;
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      parserVersion: 'benefits-v6',
      previous: {
        parserVersion: cachedParserVersion,
        etag: '"cache-v1"',
        lastModified: 'Tue, 18 Aug 2026 00:00:00 GMT',
        reusableExtraction: true,
      },
      fetchImpl: async (_url, init) => {
        headers = new Headers(init.headers);
        return response(null, {status: 304, headers: {etag: '"cache-v1"'}});
      },
      resolveHost: publicDns,
    });
    assert.equal(headers.has('if-none-match'), expectedConditional);
    assert.equal(headers.has('if-modified-since'), expectedConditional);
    assert.equal(result.status, 304);
    assert.equal(result.notModified, true);
    assert.equal(result.bytes, undefined);
    assert.equal(result.text, undefined);
  }
});

test('unusable 304 forces exactly one unconditional request while reusable 304 completes directly', async () => {
  const requestHeaders = [];
  const recovered = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: 'benefits-v6',
    previous: {parserVersion: 'benefits-v6', etag: '"cache-v1"', reusableExtraction: false},
    fetchImpl: async (_url, init) => {
      requestHeaders.push(new Headers(init.headers));
      return requestHeaders.length === 1 ? response(null, {status: 304}) : response('fresh issuer body');
    },
    resolveHost: publicDns,
  });
  assert.equal(recovered.disposition, 'success');
  assert.deepEqual(recovered.attempts.map((attempt) => attempt.status), [304, 200]);
  assert.equal(requestHeaders[0].get('if-none-match'), '"cache-v1"');
  assert.equal(requestHeaders[1].has('if-none-match'), false);

  let failedCalls = 0;
  const failed = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: 'benefits-v6',
    previous: {parserVersion: 'benefits-v6', etag: '"cache-v1"', reusableExtraction: false},
    maxAttempts: 5,
    delay: async () => {},
    fetchImpl: async () => ++failedCalls === 1 ? response(null, {status: 304}) : response('failure', {status: 503}),
    resolveHost: publicDns,
  });
  assert.equal(failedCalls, 2);
  assert.equal(failed.disposition, 'failed');

  let reusableCalls = 0;
  const reusable = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: 'benefits-v6',
    previous: {parserVersion: 'benefits-v6', etag: '"cache-v1"', reusableExtraction: true},
    fetchImpl: async () => {
      reusableCalls += 1;
      return response(null, {status: 304});
    },
    resolveHost: publicDns,
  });
  assert.equal(reusableCalls, 1);
  assert.equal(reusable.disposition, 'not_modified');
});

test('preserves structured HTTP errors and bounded Retry-After metadata', async () => {
  for (const [status, code] of [[401, 'http_401'], [403, 'http_403'], [404, 'http_404'], [410, 'http_410'], [429, 'http_429'], [503, 'http_5xx']]) {
    await assert.rejects(
      () => fetchOfficialIssuerResource({
        issuer,
        url: officialUrl,
        fetchImpl: async () => response('failure', {status, headers: {'retry-after': '999999999'}}),
        resolveHost: publicDns,
      }),
      (error) => error instanceof OfficialFetchError && error.code === code &&
        error.httpStatus === status && (status !== 429 || error.retryAfter === '999999999'),
    );
  }
});

test('retry matrix retains every attempt and never turns missing sources into discontinuation', async () => {
  for (const fixture of [
    {statuses: [404, 200], disposition: 'success', attempts: 2},
    {statuses: [404, 404], disposition: 'review_required', reason: 'persistent_404', attempts: 2},
    {statuses: [410], disposition: 'review_required', reason: 'http_410', attempts: 1},
    {statuses: [403], disposition: 'blocked', reason: 'http_403', attempts: 1},
  ]) {
    let call = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: 'benefits-v6',
      delay: async () => {},
      fetchImpl: async () => {
        const status = fixture.statuses[Math.min(call++, fixture.statuses.length - 1)];
        return response(status === 200 ? 'issuer card body' : 'failure', {status});
      },
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition, fixture.disposition);
    assert.equal(observation.reviewReason, fixture.reason);
    assert.equal(observation.attempts.length, fixture.attempts);
    assert.equal('isDiscontinued' in observation, false);
  }
});

test('transient soft 404 retries while persistent soft 404 and render shells require review', async () => {
  const soft404 = '<html><title>Page not found</title><h1>404</h1></html>';
  for (const fixture of [
    {bodies: [soft404, '<html><h1>White Reserve Credit Card</h1></html>'], disposition: 'success'},
    {bodies: [soft404, soft404], disposition: 'review_required', reason: 'persistent_soft_404'},
  ]) {
    let calls = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: 'benefits-v6',
      delay: async () => {},
      fetchImpl: async () => response(fixture.bodies[calls++]),
      resolveHost: publicDns,
    });
    assert.equal(calls, 2);
    assert.equal(observation.disposition, fixture.disposition);
    assert.equal(observation.reviewReason, fixture.reason);
  }
  const shell = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: 'benefits-v6',
    fetchImpl: async () => response('<html><div id="root"></div><script src="app.js"></script></html>'),
    resolveHost: publicDns,
  });
  assert.equal(shell.disposition, 'blocked');
  assert.equal(shell.reviewReason, 'empty_shell');
});

test('429 honors bounded seconds/date retry and 5xx/network use bounded exponential retry', async () => {
  const delays = [];
  let now = Date.parse('2026-08-19T10:00:00.000Z');
  const statuses = [429, 429, 503, 'network', 200];
  let call = 0;
  const observation = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: 'benefits-v6',
    now: () => now,
    delay: async (milliseconds) => {
      delays.push(milliseconds);
      now += milliseconds;
    },
    maxAttempts: 5,
    maxBackoffMs: 30_000,
    fetchImpl: async () => {
      const status = statuses[call++];
      if (status === 'network') throw new Error('socket secret');
      const headers = status === 429
        ? {'retry-after': call === 1 ? '5' : new Date(now + 120_000).toUTCString()}
        : undefined;
      return response(status === 200 ? 'issuer card body' : 'failure', {status, headers});
    },
    resolveHost: publicDns,
  });
  assert.equal(observation.disposition, 'success');
  assert.deepEqual(delays, [5_000, 30_000, 4_000, 8_000]);
  assert.equal(observation.attempts.length, 5);
});

test('rejects soft 404, challenge/login, and empty JavaScript shells with distinct safe codes', async () => {
  const fixtures = [
    ['<html><title>Page not found</title><h1>404</h1></html>', 'soft_404'],
    ['<html><title>Sign in</title><form action="/login"><input type="password"></form></html>', 'challenge_page'],
    ['<html><div id="root"></div><script src="app.js"></script></html>', 'empty_shell'],
  ];
  for (const [body, code] of fixtures) {
    await rejectsWith({issuer, url: officialUrl, fetchImpl: async () => response(body), resolveHost: publicDns}, code);
  }
});

test('validates charset, decodes legacy issuer text, and rejects malformed content type', async () => {
  const decoded = await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response(new Uint8Array([0x43, 0x61, 0x66, 0xe9]), {headers: {'content-type': 'text/html; charset=iso-8859-1'}}),
    resolveHost: publicDns,
  });
  assert.equal(decoded.text, 'Café');
  for (const contentType of ['', 'garbage', 'text/html; charset=made-up']) {
    await rejectsWith({
      issuer,
      url: officialUrl,
      fetchImpl: async () => response('body', {headers: {'content-type': contentType}}),
      resolveHost: publicDns,
    }, contentType.includes('charset') ? 'unsupported_charset' : 'unsupported_content');
  }
});

test('enforces robots policy and rechecks DNS before every same-issuer redirect request', async () => {
  let fetched = 0;
  await rejectsWith({
    issuer,
    url: officialUrl,
    robotsAllowed: async (url) => !url.includes('/private'),
    fetchImpl: async () => {
      fetched += 1;
      return response('', {status: 302, headers: {location: '/private'}});
    },
    resolveHost: publicDns,
  }, 'robots_disallowed');
  assert.equal(fetched, 1);

  let resolutions = 0;
  let requests = 0;
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => {
      requests += 1;
      return response('', {status: 302, headers: {location: '/rd/white-reserve/terms'}});
    },
    resolveHost: async () => ++resolutions === 1 ? ['93.184.216.34'] : ['100.64.0.1'],
  }, 'private_address');
  assert.equal(requests, 1);
  assert.equal(resolutions, 2);
});

test('compressed advertised bytes and decompressed streamed bytes are independently bounded', async () => {
  for (const fixture of [
    {body: 'small', length: '11'},
    {body: 'decompressed issuer text', length: '5'},
  ]) {
    await rejectsWith({
      issuer,
      url: officialUrl,
      maxBytes: 10,
      fetchImpl: async () => response(fixture.body, {headers: {
        'content-type': 'text/html',
        'content-encoding': 'gzip',
        'content-length': fixture.length,
      }}),
      resolveHost: publicDns,
    }, 'oversized');
  }
});

test('rejects redirect loops and generic/login redirect targets', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('', {status: 302, headers: {location: officialUrl}}),
    resolveHost: publicDns,
  }, 'redirect_rejected');
  for (const location of ['/login', '/cards/credit-card']) {
    await rejectsWith({
      issuer,
      url: officialUrl,
      fetchImpl: async () => response('', {status: 302, headers: {location}}),
      resolveHost: publicDns,
    }, 'identity_review');
  }
});
