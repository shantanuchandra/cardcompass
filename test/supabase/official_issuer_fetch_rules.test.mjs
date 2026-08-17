import assert from 'node:assert/strict';
import test from 'node:test';

import {
  fetchOfficialIssuerResource,
  officialResourceText,
} from '../../supabase/functions/_shared/official_issuer_fetch.ts';

const issuer = 'Kotak Bank';
const officialUrl = 'https://www.kotak.com/rd/white-reserve';
const publicDns = async () => ['203.0.113.20'];

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
  }, 'unreachable');
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
      submittedUrl: 'https://www.kotak.com/rd/white-reserve?a=1&b=2',
      finalUrl: 'https://www.kotak.com/rd/white-reserve?a=1&b=2',
      canonicalUrl: 'https://www.kotak.com/rd/white-reserve?a=1&b=2',
      contentType: 'text/html',
      bytes: 13,
      text: 'official body',
      contentHash: '62a1c97ac2be209866e770e905bb11268f8e247ee0e66fbd318117988f234865',
    },
  );
  assert.match(result.retrievedAt, /^\d{4}-\d{2}-\d{2}T/);
});
