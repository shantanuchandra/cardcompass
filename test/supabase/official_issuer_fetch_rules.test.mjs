import assert from 'node:assert/strict';
import test from 'node:test';

import {fetchOfficialIssuerResource} from '../../supabase/functions/_shared/official_issuer_fetch.ts';

const issuer = 'Kotak Bank';
const officialUrl = 'https://www.kotak.com/rd/white-reserve';
const publicDns = async () => ['203.0.113.20'];

function response(body, options = {}) {
  return new Response(body, {
    status: options.status ?? 200,
    headers: options.headers ?? {'content-type': 'text/html; charset=utf-8'},
  });
}

async function rejectsWith(input, code) {
  await assert.rejects(
    () => fetchOfficialIssuerResource(input),
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

test('allows only HTML, XHTML, PDF, and issuer sitemap XML content', async () => {
  for (const contentType of [
    'text/html',
    'application/xhtml+xml',
    'application/pdf',
    'application/xml',
    'text/xml',
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
    fetchImpl: async () => response('{"not":"issuer content"}', {
      headers: {'content-type': 'application/json'},
    }),
    resolveHost: publicDns,
  }, 'unsupported_content');
});

test('enforces the eight-megabyte declared and actual response limits', async () => {
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response('small', {
      headers: {'content-type': 'text/html', 'content-length': '8388609'},
    }),
    resolveHost: publicDns,
  }, 'oversized');
  await rejectsWith({
    issuer,
    url: officialUrl,
    fetchImpl: async () => response(new Uint8Array(8 * 1024 * 1024 + 1), {
      headers: {'content-type': 'application/pdf'},
    }),
    resolveHost: publicDns,
  }, 'oversized');
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
