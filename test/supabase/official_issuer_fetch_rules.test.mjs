import assert from "node:assert/strict";
import test from "node:test";

import {
  fetchOfficialIssuerObservation,
  fetchOfficialIssuerResource,
  OfficialFetchError,
  officialResourceText,
  requireOfficialFetchBody,
} from "../../supabase/functions/_shared/official_issuer_fetch.ts";

const issuer = "Kotak Bank";
const officialUrl = "https://www.kotak.com/rd/white-reserve";
const publicDns = async () => ["93.184.216.34"];

async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function reusablePrevious(submittedUrl, finalUrl = submittedUrl) {
  return {
    parserVersion: "benefits-v6",
    etag: '"cache-v1"',
    reusableExtraction: true,
    contentHash: "a".repeat(64),
    canonicalBenefitHash: "b".repeat(64),
    sourceIdentityHash: await digest(submittedUrl),
    finalResourceUrl: finalUrl,
    finalResourceIdentityHash: await digest(finalUrl),
    cardIdentityValidated: true,
  };
}

function response(body, options = {}) {
  return new Response(body, {
    status: options.status ?? 200,
    headers: options.headers ?? { "content-type": "text/html; charset=utf-8" },
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
      headers: options.headers ?? { "content-type": "text/html" },
    }),
    wasCancelled: () => cancelled,
  };
}

async function deflateBytes(value) {
  const stream = new Blob([new TextEncoder().encode(value)]).stream()
    .pipeThrough(new CompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function joinBytes(parts) {
  const length = parts.reduce((total, part) => total + part.length, 0);
  const joined = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return joined;
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
      setTimeout(() => reject(new Error("fetch did not settle")), timeoutMs);
    }),
  ]);
}

test("extracts benefit text from safely fetched PDF bytes", async () => {
  const pdf = new TextEncoder().encode(
    "%PDF-1.4\n1 0 obj<</Length 78>>stream\nBT (Get 2 complimentary lounge visits per quarter.) Tj ET\nendstream\nendobj\n%%EOF",
  );
  const text = await officialResourceText({
    submittedUrl: officialUrl,
    finalUrl: officialUrl,
    canonicalUrl: officialUrl,
    contentType: "application/pdf",
    bytes: pdf,
    text: "",
    contentHash: "pdf-hash",
    retrievedAt: "2026-08-17T00:00:00.000Z",
  });

  assert.match(text, /2 complimentary lounge visits per quarter/i);
});

test("PDF extraction reports explicit overflow instead of slicing a late fact", async () => {
  const filler = "x".repeat(1_000_100);
  const lateFact = "Late benefit earns 17% cashback on travel.";
  const pdf = new TextEncoder().encode(
    `%PDF-1.4\nBT (${filler}) Tj (${lateFact}) Tj ET\n%%EOF`,
  );
  await assert.rejects(
    () =>
      officialResourceText({
        submittedUrl: officialUrl,
        finalUrl: officialUrl,
        canonicalUrl: officialUrl,
        contentType: "application/pdf",
        bytes: pdf,
        text: "",
        contentHash: "pdf-hash",
        retrievedAt: "2026-08-17T00:00:00.000Z",
      }),
    (error) => error instanceof Error && error.message === "oversized",
  );
});

test("PDF extraction bounds aggregate decompressed bytes across every stream", async () => {
  const first = await deflateBytes("x".repeat(600_000));
  const second = await deflateBytes("y".repeat(600_000));
  const encode = (value) => new TextEncoder().encode(value);
  const pdf = joinBytes([
    encode("%PDF-1.4\n<</Filter /FlateDecode>>\nstream\n"),
    first,
    encode("\nendstream\n<</Filter /FlateDecode>>\nstream\n"),
    second,
    encode("\nendstream\n%%EOF"),
  ]);

  await assert.rejects(
    () =>
      officialResourceText({
        submittedUrl: officialUrl,
        finalUrl: officialUrl,
        canonicalUrl: officialUrl,
        contentType: "application/pdf",
        bytes: pdf,
        text: "",
        contentHash: "pdf-hash",
        retrievedAt: "2026-08-17T00:00:00.000Z",
      }),
    (error) => error instanceof Error && error.message === "oversized",
  );
});

async function rejectsWithin(input, code) {
  await assert.rejects(
    () => settlesWithin(fetchOfficialIssuerResource(input)),
    (error) => error instanceof Error && error.message === code,
  );
}

test("rejects non-HTTPS and off-issuer URLs before requesting them", async () => {
  await rejectsWith(
    {
      issuer,
      url: "http://www.kotak.com/rd/white-reserve",
      fetchImpl: async () => assert.fail("must not fetch unapproved URL"),
      resolveHost: publicDns,
    },
    "unapproved_domain",
  );
  await rejectsWith(
    {
      issuer,
      url: "https://attacker.example/rd/white-reserve",
      fetchImpl: async () => assert.fail("must not fetch unapproved URL"),
      resolveHost: publicDns,
    },
    "unapproved_domain",
  );
});

test("rejects an official hostname that resolves to a loopback or private address", async () => {
  for (
    const address of ["127.0.0.1", "10.1.2.3", "::1", "fd00::1", "fe80::1"]
  ) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () => assert.fail("must not fetch private address"),
        resolveHost: async () => [address],
      },
      "private_address",
    );
  }
});

test("revalidates every redirect target before requesting it", async () => {
  let calls = 0;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () => {
        calls += 1;
        return response("", {
          status: 302,
          headers: { location: "https://attacker.example/steal" },
        });
      },
      resolveHost: publicDns,
    },
    "redirect_rejected",
  );
  assert.equal(calls, 1);
});

test("sanitizes malformed redirect locations into the redirect rejection code", async () => {
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response("", {
          status: 302,
          headers: { location: "https://[" },
        }),
      resolveHost: publicDns,
    },
    "redirect_rejected",
  );
});

test("allows HTML, XHTML, and PDF by default while reserving XML for sitemap fetches", async () => {
  for (
    const contentType of [
      "text/html",
      "application/xhtml+xml",
      "application/pdf",
    ]
  ) {
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response("issuer content", {
          headers: { "content-type": contentType },
        }),
      resolveHost: publicDns,
    });
    assert.equal(result.contentType, contentType);
  }
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response("<urlset/>", {
          headers: { "content-type": "application/xml" },
        }),
      resolveHost: publicDns,
    },
    "unsupported_content",
  );
  let sitemapAccept = "";
  const sitemap = await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    contentPurpose: "sitemap",
    fetchImpl: async (_url, init) => {
      sitemapAccept = new Headers(init.headers).get("accept") ?? "";
      return response("<urlset/>", {
        headers: { "content-type": "application/xml" },
      });
    },
    resolveHost: publicDns,
  });
  assert.equal(sitemap.contentType, "application/xml");
  assert.match(sitemapAccept, /application\/xml/);
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response('{"not":"issuer content"}', {
          headers: { "content-type": "application/json" },
        }),
      resolveHost: publicDns,
    },
    "unsupported_content",
  );
});

test("enforces the eight-megabyte declared and actual response limits", async () => {
  const declared = streamingResponse({
    close: false,
    headers: { "content-type": "text/html", "content-length": "8388609" },
  });
  let declaredSignal;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async (_url, init) => {
        declaredSignal = init.signal;
        return declared.response;
      },
      resolveHost: publicDns,
    },
    "oversized",
  );
  assert.equal(declared.wasCancelled(), true);
  assert.equal(declaredSignal.aborted, true);
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response(new Uint8Array(8 * 1024 * 1024 + 1), {
          headers: { "content-type": "application/pdf" },
        }),
      resolveHost: publicDns,
    },
    "oversized",
  );
});

test("stops reading, cancels the reader, and aborts once streamed bytes exceed the limit", async () => {
  const streamed = streamingResponse({
    chunks: [new Uint8Array([1, 2]), new Uint8Array([3, 4])],
    close: false,
  });
  let signal;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      maxBytes: 3,
      fetchImpl: async (_url, init) => {
        signal = init.signal;
        return streamed.response;
      },
      resolveHost: publicDns,
    },
    "oversized",
  );
  assert.equal(streamed.wasCancelled(), true);
  assert.equal(signal.aborted, true);
});

test("does not await a never-settling body cancellation before reporting oversized", async () => {
  let cancellationRequested = false;
  const body = new ReadableStream({
    cancel() {
      cancellationRequested = true;
      return new Promise(() => {});
    },
  });
  await rejectsWithin(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        new Response(body, {
          headers: { "content-type": "text/html", "content-length": "8388609" },
        }),
      resolveHost: publicDns,
    },
    "oversized",
  );
  assert.equal(cancellationRequested, true);
});

test("does not await a never-settling reader cancellation after a stalled read times out", async () => {
  let cancellationRequested = false;
  const body = new ReadableStream({
    pull() {},
    cancel() {
      cancellationRequested = true;
      return new Promise(() => {});
    },
  });
  await rejectsWithin(
    {
      issuer,
      url: officialUrl,
      timeoutMs: 5,
      fetchImpl: async () =>
        new Response(body, { headers: { "content-type": "text/html" } }),
      resolveHost: publicDns,
    },
    "timeout",
  );
  assert.equal(cancellationRequested, true);
});

test("does not let reader cleanup replace an oversized failure code", async () => {
  const reader = {
    read: async () => ({ done: false, value: new Uint8Array([1, 2, 3, 4]) }),
    cancel: async () => undefined,
    releaseLock: () => {
      throw new Error("lock cleanup failed");
    },
  };
  const mockResponse = {
    status: 200,
    ok: true,
    headers: new Headers({ "content-type": "text/html" }),
    body: { getReader: () => reader },
  };
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      maxBytes: 3,
      fetchImpl: async () => mockResponse,
      resolveHost: publicDns,
    },
    "oversized",
  );
});

test("cancels each redirect response body before following the approved location", async () => {
  const redirect = streamingResponse({
    close: false,
    status: 302,
    headers: { location: "/rd/white-reserve/terms" },
  });
  let calls = 0;
  await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) return redirect.response;
      assert.equal(redirect.wasCancelled(), true);
      return response("approved content");
    },
    resolveHost: publicDns,
  });
  assert.equal(calls, 2);
});

test("uses one timeout deadline for stalled DNS and all redirect hops", async () => {
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      timeoutMs: 5,
      fetchImpl: async () => assert.fail("must not fetch while DNS is stalled"),
      resolveHost: async () => new Promise(() => {}),
    },
    "timeout",
  );

  let resolutions = 0;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      timeoutMs: 5,
      fetchImpl: async () =>
        response("", {
          status: 302,
          headers: { location: "/rd/white-reserve/terms" },
        }),
      resolveHost: async () => {
        resolutions += 1;
        return resolutions === 1 ? ["8.8.4.4"] : new Promise(() => {});
      },
    },
    "timeout",
  );
});

test("aborts a fetch after its configured timeout and exposes only the timeout code", async () => {
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      timeoutMs: 5,
      fetchImpl: async (_url, init) =>
        new Promise((_resolve, reject) => {
          init.signal.addEventListener(
            "abort",
            () => reject(init.signal.reason),
          );
        }),
      resolveHost: publicDns,
    },
    "timeout",
  );
});

test("sanitizes transport and HTTP failures into the approved error codes", async () => {
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () => {
        throw new Error("socket reset at 10.0.0.1");
      },
      resolveHost: publicDns,
    },
    "unreachable",
  );
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () => response("service failure", { status: 503 }),
      resolveHost: publicDns,
    },
    "http_5xx",
  );
});

test("returns canonical URLs, text, bytes, timestamp, and a SHA-256 body hash", async () => {
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: "https://WWW.KOTAK.COM:443/rd//white-reserve/#ignored",
    fetchImpl: async (url) => {
      assert.equal(url, "https://www.kotak.com/rd/white-reserve");
      return response("official body");
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
      submittedUrl: "https://www.kotak.com/rd/white-reserve",
      finalUrl: "https://www.kotak.com/rd/white-reserve",
      canonicalUrl: "https://www.kotak.com/rd/white-reserve",
      contentType: "text/html",
      bytes: 13,
      text: "official body",
      contentHash:
        "62a1c97ac2be209866e770e905bb11268f8e247ee0e66fbd318117988f234865",
    },
  );
  assert.match(result.retrievedAt, /^\d{4}-\d{2}-\d{2}T/);
});

test("preserves status, bounded validators, and exact transient identity without persistable secrets", async () => {
  const submitted = `${officialUrl}?locale=en#private`;
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: submitted,
    allowedQueryParameters: ["locale"],
    now: () => Date.parse("2026-08-19T10:00:00.000Z"),
    fetchImpl: async () =>
      response("official body", {
        headers: {
          "content-type": "text/html; charset=utf-8",
          etag: `"${"a".repeat(700)}"`,
          "last-modified": "Wed, 19 Aug 2026 09:00:00 GMT",
        },
      }),
    resolveHost: publicDns,
  });
  assert.equal(result.status, 200);
  assert.equal(result.submittedUrl, officialUrl);
  assert.equal(result.finalUrl, officialUrl);
  assert.equal(result.canonicalUrl, officialUrl);
  assert.equal(result.notModified, false);
  assert.equal(result.etag.length, 512);
  assert.equal(result.retrievedAt, "2026-08-19T10:00:00.000Z");
});

test("sends validators only for a compatible parser cache and represents 304 without a body", async () => {
  for (
    const [cachedParserVersion, expectedConditional] of [
      ["benefits-v6", true],
      ["benefits-v5", false],
    ]
  ) {
    let headers;
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      previous: {
        ...(await reusablePrevious(officialUrl)),
        parserVersion: cachedParserVersion,
        lastModified: "Tue, 18 Aug 2026 00:00:00 GMT",
      },
      fetchImpl: async (_url, init) => {
        headers = new Headers(init.headers);
        return response(null, { status: 304, headers: { etag: '"cache-v1"' } });
      },
      resolveHost: publicDns,
    });
    assert.equal(headers.has("if-none-match"), expectedConditional);
    assert.equal(headers.has("if-modified-since"), expectedConditional);
    assert.equal(result.status, 304);
    assert.equal(result.notModified, true);
    assert.equal(result.bytes, undefined);
    assert.equal(result.text, undefined);
  }
});

test("unusable 304 forces exactly one unconditional request while reusable 304 completes directly", async () => {
  const requestHeaders = [];
  const recovered = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: {
      parserVersion: "benefits-v6",
      etag: '"cache-v1"',
      reusableExtraction: false,
    },
    fetchImpl: async (_url, init) => {
      requestHeaders.push(new Headers(init.headers));
      return requestHeaders.length === 1
        ? response(null, { status: 304 })
        : response("fresh issuer body");
    },
    resolveHost: publicDns,
  });
  assert.equal(recovered.disposition, "success");
  assert.deepEqual(
    recovered.attempts.map((attempt) => attempt.status),
    [304, 200],
  );
  assert.equal(requestHeaders[0].has("if-none-match"), false);
  assert.equal(requestHeaders[1].has("if-none-match"), false);

  let failedCalls = 0;
  const failed = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: {
      parserVersion: "benefits-v6",
      etag: '"cache-v1"',
      reusableExtraction: false,
    },
    maxAttempts: 5,
    delay: async () => {},
    fetchImpl: async () => (++failedCalls === 1
      ? response(null, { status: 304 })
      : response("failure", { status: 503 })),
    resolveHost: publicDns,
  });
  assert.equal(failedCalls, 2);
  assert.equal(failed.disposition, "failed");

  let reusableCalls = 0;
  const reusable = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: await reusablePrevious(officialUrl),
    fetchImpl: async () => {
      reusableCalls += 1;
      return response(null, { status: 304 });
    },
    resolveHost: publicDns,
  });
  assert.equal(reusableCalls, 1);
  assert.equal(reusable.disposition, "not_modified");
});

test("preserves structured HTTP errors and bounded Retry-After metadata", async () => {
  for (
    const [status, code] of [
      [401, "http_401"],
      [403, "http_403"],
      [404, "http_404"],
      [410, "http_410"],
      [429, "http_429"],
      [503, "http_5xx"],
    ]
  ) {
    await assert.rejects(
      () =>
        fetchOfficialIssuerResource({
          issuer,
          url: officialUrl,
          fetchImpl: async () =>
            response("failure", {
              status,
              headers: { "retry-after": "999999999" },
            }),
          resolveHost: publicDns,
        }),
      (error) =>
        error instanceof OfficialFetchError &&
        error.code === code &&
        error.httpStatus === status &&
        (status !== 429 || error.retryAfter === "999999999"),
    );
  }
});

test("retry matrix retains every attempt and never turns missing sources into discontinuation", async () => {
  for (
    const fixture of [
      { statuses: [404, 200], disposition: "success", attempts: 2 },
      {
        statuses: [404, 404],
        disposition: "review_required",
        reason: "persistent_404",
        attempts: 2,
      },
      {
        statuses: [410],
        disposition: "review_required",
        reason: "http_410",
        attempts: 1,
      },
      {
        statuses: [403],
        disposition: "blocked",
        reason: "http_403",
        attempts: 1,
      },
    ]
  ) {
    let call = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      delay: async () => {},
      fetchImpl: async () => {
        const status =
          fixture.statuses[Math.min(call++, fixture.statuses.length - 1)];
        return response(status === 200 ? "issuer card body" : "failure", {
          status,
        });
      },
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition, fixture.disposition);
    assert.equal(observation.reviewReason, fixture.reason);
    assert.equal(observation.attempts.length, fixture.attempts);
    assert.equal("isDiscontinued" in observation, false);
  }
});

test("transient soft 404 retries while persistent soft 404 and render shells require review", async () => {
  const soft404 = "<html><title>Page not found</title><h1>404</h1></html>";
  for (
    const fixture of [
      {
        bodies: [soft404, "<html><h1>White Reserve Credit Card</h1></html>"],
        disposition: "success",
      },
      {
        bodies: [soft404, soft404],
        disposition: "review_required",
        reason: "persistent_soft_404",
      },
    ]
  ) {
    let calls = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
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
    parserVersion: "benefits-v6",
    fetchImpl: async () =>
      response(
        '<html><div id="root"></div><script src="app.js"></script></html>',
      ),
    resolveHost: publicDns,
  });
  assert.equal(shell.disposition, "blocked");
  assert.equal(shell.reviewReason, "empty_shell");
});

test("429 honors bounded seconds/date retry and 5xx/network use bounded exponential retry", async () => {
  const delays = [];
  let now = Date.parse("2026-08-19T10:00:00.000Z");
  const statuses = [429, 429, 503, "network", 200];
  let call = 0;
  const observation = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    now: () => now,
    delay: async (milliseconds) => {
      delays.push(milliseconds);
      now += milliseconds;
    },
    maxAttempts: 5,
    maxBackoffMs: 30_000,
    fetchImpl: async () => {
      const status = statuses[call++];
      if (status === "network") throw new Error("socket secret");
      const headers = status === 429
        ? {
          "retry-after": call === 1
            ? "5"
            : new Date(now + 120_000).toUTCString(),
        }
        : undefined;
      return response(status === 200 ? "issuer card body" : "failure", {
        status,
        headers,
      });
    },
    resolveHost: publicDns,
  });
  assert.equal(observation.disposition, "success");
  assert.deepEqual(delays, [5_000, 30_000, 4_000, 8_000]);
  assert.equal(observation.attempts.length, 5);
});

test("rejects soft 404, challenge/login, and empty JavaScript shells with distinct safe codes", async () => {
  const fixtures = [
    ["<html><title>Page not found</title><h1>404</h1></html>", "soft_404"],
    [
      '<html><title>Sign in</title><form action="/login"><input type="password"></form></html>',
      "challenge_page",
    ],
    [
      '<html><div id="root"></div><script src="app.js"></script></html>',
      "empty_shell",
    ],
  ];
  for (const [body, code] of fixtures) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () => response(body),
        resolveHost: publicDns,
      },
      code,
    );
  }
});

test("validates charset, decodes legacy issuer text, and rejects malformed content type", async () => {
  const decoded = await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    fetchImpl: async () =>
      response(new Uint8Array([0x43, 0x61, 0x66, 0xe9]), {
        headers: { "content-type": "text/html; charset=iso-8859-1" },
      }),
    resolveHost: publicDns,
  });
  assert.equal(decoded.text, "Café");
  for (const contentType of ["", "garbage", "text/html; charset=made-up"]) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () =>
          response("body", { headers: { "content-type": contentType } }),
        resolveHost: publicDns,
      },
      contentType.includes("charset")
        ? "unsupported_charset"
        : "unsupported_content",
    );
  }
});

test("enforces robots policy and rechecks DNS before every same-issuer redirect request", async () => {
  let fetched = 0;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      robotsAllowed: async (url) => !url.includes("/private"),
      fetchImpl: async () => {
        fetched += 1;
        return response("", { status: 302, headers: { location: "/private" } });
      },
      resolveHost: publicDns,
    },
    "robots_disallowed",
  );
  assert.equal(fetched, 1);

  let resolutions = 0;
  let requests = 0;
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () => {
        requests += 1;
        return response("", {
          status: 302,
          headers: { location: "/rd/white-reserve/terms" },
        });
      },
      resolveHost:
        async () => (++resolutions === 1 ? ["93.184.216.34"] : ["100.64.0.1"]),
    },
    "private_address",
  );
  assert.equal(requests, 1);
  assert.equal(resolutions, 2);
});

test("compressed advertised bytes and decompressed streamed bytes are independently bounded", async () => {
  for (
    const fixture of [
      { body: "small", length: "11" },
      { body: "decompressed issuer text", length: "5" },
    ]
  ) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        maxBytes: 10,
        fetchImpl: async () =>
          response(fixture.body, {
            headers: {
              "content-type": "text/html",
              "content-encoding": "gzip",
              "content-length": fixture.length,
            },
          }),
        resolveHost: publicDns,
      },
      "oversized",
    );
  }
});

test("rejects redirect loops and generic/login redirect targets", async () => {
  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response("", { status: 302, headers: { location: officialUrl } }),
      resolveHost: publicDns,
    },
    "redirect_rejected",
  );
  for (const location of ["/login", "/cards/credit-card"]) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () =>
          response("", { status: 302, headers: { location } }),
        resolveHost: publicDns,
      },
      "identity_review",
    );
  }
});

test("accepts only global-unicast DNS answers including normalized mapped IPv6", async () => {
  for (
    const address of [
      "::ffff:7f00:1",
      "::ffff:127.0.0.1",
      "100.64.0.1",
      "192.0.2.1",
      "198.51.100.8",
      "203.0.113.9",
      "198.18.0.1",
      "2001:db8::1",
      "ff02::1",
      "::",
    ]
  ) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () => assert.fail(`must not fetch ${address}`),
        resolveHost: async () => [address],
      },
      "private_address",
    );
  }

  for (const address of ["8.8.8.8", "2606:4700:4700::1111", "::ffff:808:808"]) {
    const fetched = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      fetchImpl: async () => response("global issuer body"),
      resolveHost: async () => [address],
    });
    assert.equal(fetched.status, 200);
  }
});

test("never exposes query credentials in result URLs and sends only explicitly allowed query keys", async () => {
  const requested = `${officialUrl}?locale=en#private`;
  let target = "";
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: requested,
    allowedQueryParameters: ["locale"],
    fetchImpl: async (url) => {
      target = String(url);
      return response("issuer body");
    },
    resolveHost: publicDns,
  });
  assert.equal(target, `${officialUrl}?locale=en`);
  assert.equal(result.submittedUrl, officialUrl);
  assert.equal(result.submittedResourceUrl, `${officialUrl}?locale=en`);
  assert.equal(result.finalResourceUrl, `${officialUrl}?locale=en`);

  let calls = 0;
  const redirected = await fetchOfficialIssuerResource({
    issuer,
    url: requested,
    allowedQueryParameters: ["locale"],
    fetchImpl: async (url) => {
      calls += 1;
      if (calls === 1) {
        assert.equal(String(url), `${officialUrl}?locale=en`);
        return response("", {
          status: 302,
          headers: {
            location: "/rd/white-reserve/terms?locale=hi",
          },
        });
      }
      assert.equal(String(url), `${officialUrl}/terms?locale=hi`);
      return response("issuer terms");
    },
    resolveHost: publicDns,
  });
  assert.equal(redirected.submittedUrl, officialUrl);
  assert.equal(redirected.finalUrl, `${officialUrl}/terms`);
  assert.equal(redirected.canonicalUrl, `${officialUrl}/terms`);
  assert.equal(redirected.submittedResourceUrl, `${officialUrl}?locale=en`);
  assert.equal(redirected.finalResourceUrl, `${officialUrl}/terms?locale=hi`);
  assert.match(redirected.sourceIdentityHash, /^[0-9a-f]{64}$/);
  assert.equal(JSON.stringify(redirected).includes("secret"), false);

  await rejectsWith(
    {
      issuer,
      url: `${officialUrl}?session=secret&locale=en&utm_source=mail#private`,
      allowedQueryParameters: ["locale", "session", "utm_source"],
      fetchImpl: async () => assert.fail("sensitive query must not fetch"),
      resolveHost: publicDns,
    },
    "unapproved_query",
  );
});

test("conditional validators require reusable same-parser canonical content evidence", async () => {
  for (
    const previous of [
      {
        parserVersion: "benefits-v6",
        etag: '"v1"',
        reusableExtraction: false,
        contentHash: "a".repeat(64),
      },
      { parserVersion: "benefits-v6", etag: '"v1"', reusableExtraction: true },
      {
        parserVersion: "benefits-v5",
        etag: '"v1"',
        reusableExtraction: true,
        contentHash: "a".repeat(64),
      },
    ]
  ) {
    let headers;
    await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      previous,
      fetchImpl: async (_url, init) => {
        headers = new Headers(init.headers);
        return response("fresh content");
      },
      resolveHost: publicDns,
    });
    assert.equal(headers.has("if-none-match"), false);
  }
});

test("reusable 304 carries prior content evidence into the terminal result", async () => {
  const contentHash = "b".repeat(64);
  const observation = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: {
      ...(await reusablePrevious(officialUrl)),
      parserVersion: "benefits-v6",
      etag: '"v1"',
      contentHash,
    },
    fetchImpl: async () => response(null, { status: 304 }),
    resolveHost: publicDns,
  });
  assert.equal(observation.disposition, "not_modified");
  assert.equal(observation.result.contentHash, contentHash);
});

test("body callers must explicitly reject not-modified or incomplete fresh results", () => {
  assert.throws(
    () =>
      requireOfficialFetchBody({
        status: 304,
        submittedUrl: officialUrl,
        finalUrl: officialUrl,
        canonicalUrl: officialUrl,
        retrievedAt: "2026-08-19T00:00:00.000Z",
        contentHash: "a".repeat(64),
        notModified: true,
      }),
    /unusable_not_modified/,
  );
  assert.throws(
    () =>
      requireOfficialFetchBody({
        status: 200,
        submittedUrl: officialUrl,
        finalUrl: officialUrl,
        canonicalUrl: officialUrl,
        retrievedAt: "2026-08-19T00:00:00.000Z",
        notModified: false,
      }),
    /unsupported_content/,
  );
});

test("absolute deadline prevents DNS, robots, retry requests, and delay beyond the remaining budget", async () => {
  let now = 1_000;
  let resolutions = 0;
  let requests = 0;
  let slept = 0;
  const observation = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    deadlineAt: 2_000,
    now: () => now,
    delay: async (milliseconds) => {
      slept += milliseconds;
      now += milliseconds;
    },
    fetchImpl: async () => {
      requests += 1;
      return response("retry", { status: 503 });
    },
    resolveHost: async () => {
      resolutions += 1;
      return ["8.8.8.8"];
    },
  });
  assert.equal(slept, 1_000);
  assert.equal(requests, 1);
  assert.equal(resolutions, 1);
  assert.equal(observation.reviewReason, "deadline_exceeded");
});

test("production robots fetch is cached per host and explicit disallow prevents the target request", async () => {
  const requested = [];
  const blocked = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    enforceRobots: true,
    fetchImpl: async (url) => {
      requested.push(String(url));
      if (String(url).endsWith("/robots.txt")) {
        return response("User-agent: CardCompassCatalogBot\nDisallow: /rd/", {
          headers: { "content-type": "text/plain; charset=utf-8" },
        });
      }
      return response("must not be fetched");
    },
    resolveHost: publicDns,
  });
  assert.equal(blocked.disposition, "blocked");
  assert.equal(blocked.reviewReason, "robots_disallowed");
  assert.deepEqual(requested, ["https://www.kotak.com/robots.txt"]);

  let robotsRequests = 0;
  let targetRequests = 0;
  const retried = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    enforceRobots: true,
    delay: async () => {},
    fetchImpl: async (url) => {
      if (String(url).endsWith("/robots.txt")) {
        robotsRequests += 1;
        return response("", { status: 404 });
      }
      targetRequests += 1;
      return targetRequests === 1
        ? response("retry", { status: 503 })
        : response("issuer content");
    },
    resolveHost: publicDns,
  });
  assert.equal(retried.disposition, "success");
  assert.equal(robotsRequests, 1);
  assert.equal(targetRequests, 2);
});

test("production robots accepts bounded ASCII rules under common issuer media declarations", async () => {
  for (
    const contentType of [
      "text/x-robots",
      "text/plain;charset=iso-8859-1",
    ]
  ) {
    const requested = [];
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      enforceRobots: true,
      maxAttempts: 1,
      fetchImpl: async (url) => {
        requested.push(String(url));
        if (String(url).endsWith("/robots.txt")) {
          return response(
            "User-agent: CardCompassCatalogBot\nAllow: /rd/",
            { headers: { "content-type": contentType } },
          );
        }
        return response("<h1>White Reserve Credit Card</h1>");
      },
      resolveHost: publicDns,
    });

    assert.equal(observation.disposition, "success", contentType);
    assert.deepEqual(requested, [
      "https://www.kotak.com/robots.txt",
      officialUrl,
    ]);
  }
});

test("page-level checkpoint detectors do not reject legitimate benefit prose", async () => {
  const legitimate = await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    fetchImpl: async () =>
      response(
        "<html><h1>White Reserve Credit Card</h1><p>Lounge access is denied when the quarterly spend threshold is not met.</p></html>",
      ),
    resolveHost: publicDns,
  });
  assert.equal(legitimate.status, 200);

  for (
    const [body, code] of [
      [
        "<html><title>We cannot find that page</title><h1>Sorry, we can't find this page</h1></html>",
        "soft_404",
      ],
      [
        "<html><title>Security check</title><h1>Enable cookies to continue</h1><p>Automated requests are blocked.</p></html>",
        "challenge_page",
      ],
    ]
  ) {
    await rejectsWith(
      {
        issuer,
        url: officialUrl,
        fetchImpl: async () => response(body),
        resolveHost: publicDns,
      },
      code,
    );
  }
});

test("invalid or missing Retry-After falls back to exponential delay instead of an immediate loop", async () => {
  for (const retryAfter of [undefined, "not-a-date"]) {
    const delays = [];
    let calls = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      delay: async (milliseconds) => delays.push(milliseconds),
      fetchImpl: async () =>
        ++calls === 1
          ? response("busy", {
            status: 429,
            headers: retryAfter ? { "retry-after": retryAfter } : {},
          })
          : response("issuer content"),
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition, "success");
    assert.deepEqual(delays, [1_000]);
  }
});

test("honors UTF BOMs when charset is absent", async () => {
  const fixtures = [
    [new Uint8Array([0xef, 0xbb, 0xbf, 0x43, 0x61, 0x72, 0x64]), "Card"],
    [
      new Uint8Array([
        0xff,
        0xfe,
        0x43,
        0x00,
        0x61,
        0x00,
        0x72,
        0x00,
        0x64,
        0x00,
      ]),
      "Card",
    ],
    [
      new Uint8Array([
        0xfe,
        0xff,
        0x00,
        0x43,
        0x00,
        0x61,
        0x00,
        0x72,
        0x00,
        0x64,
      ]),
      "Card",
    ],
  ];
  for (const [bytes, expected] of fixtures) {
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      fetchImpl: async () =>
        response(bytes, { headers: { "content-type": "text/html" } }),
      resolveHost: publicDns,
    });
    assert.equal(result.text, expected);
  }
});

test("binds validators and 304 reuse to the prior submitted and final resource identities", async () => {
  const league = "https://www.kotak.com/rd/league-platinum";
  const changedHopHeaders = [];
  const changed = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: await reusablePrevious(officialUrl),
    fetchImpl: async (url, init) => {
      changedHopHeaders.push([String(url), new Headers(init.headers)]);
      if (String(url) === officialUrl) {
        return response("", { status: 301, headers: { location: league } });
      }
      return new Headers(init.headers).has("if-none-match")
        ? response(null, { status: 304 })
        : response("<h1>League Platinum Credit Card</h1>");
    },
    resolveHost: publicDns,
  });
  assert.equal(changed.disposition, "success");
  assert.equal(changed.result.finalUrl, league);
  assert.equal(changedHopHeaders[0][1].has("if-none-match"), true);
  assert.equal(changedHopHeaders[1][1].has("if-none-match"), false);

  const vanity = "https://www.kotak.com/white-reserve";
  const permanentHopHeaders = [];
  const permanent = await fetchOfficialIssuerObservation({
    issuer,
    url: vanity,
    parserVersion: "benefits-v6",
    previous: await reusablePrevious(vanity, officialUrl),
    fetchImpl: async (url, init) => {
      permanentHopHeaders.push([String(url), new Headers(init.headers)]);
      return String(url) === vanity
        ? response("", { status: 301, headers: { location: officialUrl } })
        : response(null, { status: 304 });
    },
    resolveHost: publicDns,
  });
  assert.equal(permanent.disposition, "not_modified");
  assert.equal(permanentHopHeaders[0][1].has("if-none-match"), false);
  assert.equal(permanentHopHeaders[1][1].has("if-none-match"), true);
  assert.equal(permanent.result.finalUrl, officialUrl);

  let missingFinalHeaders;
  await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    previous: {
      parserVersion: "benefits-v6",
      etag: '"cache-v1"',
      reusableExtraction: true,
      contentHash: "a".repeat(64),
      canonicalBenefitHash: "b".repeat(64),
      sourceIdentityHash: await digest(officialUrl),
      cardIdentityValidated: true,
    },
    fetchImpl: async (_url, init) => {
      missingFinalHeaders = new Headers(init.headers);
      return response("fresh body");
    },
    resolveHost: publicDns,
  });
  assert.equal(missingFinalHeaders.has("if-none-match"), false);

  const alpha = `${officialUrl}?variant=alpha`;
  const beta = `${officialUrl}?variant=beta`;
  let variedHeaders;
  const varied = await fetchOfficialIssuerObservation({
    issuer,
    url: beta,
    allowedQueryParameters: ["variant"],
    parserVersion: "benefits-v6",
    previous: await reusablePrevious(alpha),
    fetchImpl: async (_url, init) => {
      variedHeaders = new Headers(init.headers);
      return variedHeaders.has("if-none-match")
        ? response(null, { status: 304 })
        : response("fresh beta body");
    },
    resolveHost: publicDns,
  });
  assert.equal(variedHeaders.has("if-none-match"), false);
  assert.equal(varied.disposition, "success");
});

test("robots uses selected-agent standard wildcard, terminal, and allow precedence rules", async () => {
  const fixtures = [
    ["/rd/public/card", true],
    ["/rd/private/card", false],
    ["/rd/private/public", true],
    ["/private", false],
    ["/private/more", true],
    ["/star-only", true],
    ["/encoded/~public", false],
  ];
  for (const [path, allowed] of fixtures) {
    let targetRequests = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: `https://www.kotak.com${path}`,
      parserVersion: "benefits-v6",
      enforceRobots: true,
      fetchImpl: async (url) => {
        if (String(url).endsWith("/robots.txt")) {
          return response(
            [
              "User-agent: *",
              "Disallow: /rd/*",
              "Disallow: /star-only",
              "Allow: /rd/public/*",
              "User-agent: CardCompassCatalogBot",
              "Disallow: /rd/*",
              "Allow: /rd/public/*",
              "Allow: /rd/private/public",
              "Disallow: /rd/private/public",
              "Disallow: /rd/private/*",
              "Disallow: /private$",
              "Disallow: /encoded/%7Epublic$",
            ].join("\n"),
            { headers: { "content-type": "text/plain; charset=utf-8" } },
          );
        }
        targetRequests += 1;
        return response("issuer body");
      },
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition === "success", allowed, path);
    assert.equal(targetRequests, allowed ? 1 : 0, path);
  }
});

test("robots rejects HTML and malformed 200 responses as review-required invalid policy", async () => {
  for (
    const [body, contentType] of [
      ["<html><body>not robots</body></html>", "text/html"],
      ["User-agent CardCompassCatalogBot\nDisallow: /", "text/plain"],
    ]
  ) {
    let targetRequests = 0;
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      enforceRobots: true,
      fetchImpl: async (url) => {
        if (String(url).endsWith("/robots.txt")) {
          return response(body, { headers: { "content-type": contentType } });
        }
        targetRequests += 1;
        return response("must not fetch");
      },
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition, "review_required");
    assert.equal(observation.reviewReason, "robots_invalid");
    assert.equal(targetRequests, 0);
  }
});

test("classifies exact IPv4 and IPv6 CIDR boundaries without rejecting adjacent global space", async () => {
  const rejected = [
    "100.63.255.255",
    "100.64.0.0",
    "100.127.255.255",
    "100.128.0.0",
    "192.0.0.255",
    "192.0.2.0",
    "192.0.2.255",
    "198.17.255.255",
    "198.18.0.0",
    "198.19.255.255",
    "198.20.0.0",
    "3fff::",
    "3fff:0fff:ffff:ffff:ffff:ffff:ffff:ffff",
    "2001:db8::",
    "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
    "::ffff:c000:201",
  ];
  const expectedRejected = new Set([
    "100.64.0.0",
    "100.127.255.255",
    "192.0.0.255",
    "192.0.2.0",
    "192.0.2.255",
    "198.18.0.0",
    "198.19.255.255",
    "3fff::",
    "3fff:0fff:ffff:ffff:ffff:ffff:ffff:ffff",
    "2001:db8::",
    "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
    "::ffff:c000:201",
  ]);
  for (const address of rejected) {
    let fetched = false;
    try {
      await fetchOfficialIssuerResource({
        issuer,
        url: officialUrl,
        fetchImpl: async () => {
          fetched = true;
          return response("issuer body");
        },
        resolveHost: async () => [address],
      });
      assert.equal(expectedRejected.has(address), false, address);
      assert.equal(fetched, true, address);
    } catch (error) {
      assert.equal(expectedRejected.has(address), true, address);
      assert.equal(error.message, "private_address", address);
    }
  }
  for (
    const address of [
      "192.0.0.9",
      "192.0.0.10",
      "192.0.1.1",
      "64:ff9b::808:808",
      "2001:4860:4860::8888",
      "3fff:1000::1",
    ]
  ) {
    const result = await fetchOfficialIssuerResource({
      issuer,
      url: officialUrl,
      fetchImpl: async () => response("issuer body"),
      resolveHost: async () => [address],
    });
    assert.equal(result.status, 200, address);
  }
});

test("preserves explicitly safe functional query resources and rejects unknown or sensitive keys", async () => {
  const terms = "https://www.kotak.com/rd/white-reserve/terms?document=mitc";
  let requested;
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: terms,
    allowedQueryParameters: ["document"],
    fetchImpl: async (url) => {
      requested = String(url);
      return response("White Reserve terms");
    },
    resolveHost: publicDns,
  });
  assert.equal(requested, terms);
  assert.equal(result.finalUrl, "https://www.kotak.com/rd/white-reserve/terms");
  assert.equal(result.submittedResourceUrl, terms);
  assert.equal(result.finalResourceUrl, terms);
  for (const query of ["unknown=value", "session=secret", "token=secret"]) {
    await rejectsWith(
      {
        issuer,
        url: `${officialUrl}?${query}`,
        allowedQueryParameters: ["unknown", "session", "token"],
        fetchImpl: async () => assert.fail("unapproved query must not fetch"),
        resolveHost: publicDns,
      },
      "unapproved_query",
    );
  }
});

test("preserves approved duplicate query order exactly and rejects bounded-query overflow", async () => {
  const ordered = `${officialUrl}?variant=z&variant=a&document=mitc%2F2026`;
  let requested = "";
  const result = await fetchOfficialIssuerResource({
    issuer,
    url: ordered,
    allowedQueryParameters: ["variant", "document"],
    fetchImpl: async (url) => {
      requested = String(url);
      return response("issuer body");
    },
    resolveHost: publicDns,
  });
  assert.equal(requested, ordered);
  assert.equal(result.submittedResourceUrl, ordered);
  assert.equal(result.finalResourceUrl, ordered);

  for (
    const url of [
      `${officialUrl}?document=${"a".repeat(20_000)}`,
      `${officialUrl}?${
        Array.from({ length: 100 }, (_, index) => `variant=${index}`).join("&")
      }`,
    ]
  ) {
    await rejectsWith(
      {
        issuer,
        url,
        allowedQueryParameters: ["document", "variant"],
        fetchImpl: async () => assert.fail("oversized query must not fetch"),
        resolveHost: publicDns,
      },
      "unapproved_query",
    );
  }

  await rejectsWith(
    {
      issuer,
      url: officialUrl,
      allowedQueryParameters: ["variant"],
      fetchImpl: async () =>
        response("", {
          status: 302,
          headers: { location: `${officialUrl}/terms?document=mitc` },
        }),
      resolveHost: publicDns,
    },
    "redirect_rejected",
  );
});

test("shares one bounded robots policy across separate fetches in one crawl only", async () => {
  const robotsCache = {};
  let robotsRequests = 0;
  const fetchImpl = async (url) => {
    if (String(url).endsWith("/robots.txt")) {
      robotsRequests += 1;
      return response("User-agent: CardCompassCatalogBot\nAllow: /", {
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }
    return response("issuer body");
  };
  for (const path of ["/rd/white-reserve", "/rd/white-reserve/terms"]) {
    await fetchOfficialIssuerResource({
      issuer,
      url: `https://www.kotak.com${path}`,
      enforceRobots: true,
      robotsCache,
      fetchImpl,
      resolveHost: publicDns,
    });
  }
  assert.equal(robotsRequests, 1);

  await fetchOfficialIssuerResource({
    issuer,
    url: "https://cards.kotak.com/rd/white-reserve",
    enforceRobots: true,
    robotsCache,
    fetchImpl,
    resolveHost: publicDns,
  });
  assert.equal(
    robotsRequests,
    2,
    "a different host reused another host policy",
  );

  await fetchOfficialIssuerResource({
    issuer,
    url: officialUrl,
    enforceRobots: true,
    robotsCache: {},
    fetchImpl,
    resolveHost: publicDns,
  });
  assert.equal(robotsRequests, 3, "robots cache leaked across crawl scopes");
});

test("does not sleep or start a retry when the intended delay exceeds the absolute deadline", async () => {
  let now = 500;
  let sleeps = 0;
  let requests = 0;
  const observation = await fetchOfficialIssuerObservation({
    issuer,
    url: officialUrl,
    parserVersion: "benefits-v6",
    deadlineAt: 1_000,
    now: () => now,
    delay: async (milliseconds) => {
      sleeps += 1;
      now += milliseconds;
    },
    fetchImpl: async () => {
      requests += 1;
      return response("busy", { status: 503 });
    },
    resolveHost: publicDns,
  });
  assert.equal(sleeps, 0);
  assert.equal(requests, 1);
  assert.equal(observation.reviewReason, "deadline_exceeded");
});

test("valid Retry-After zero and zero max backoff retry immediately while time remains", async () => {
  for (const deadlineAt of [undefined, 2_000]) {
    let calls = 0;
    const delays = [];
    const observation = await fetchOfficialIssuerObservation({
      issuer,
      url: officialUrl,
      parserVersion: "benefits-v6",
      ...(deadlineAt === undefined ? {} : { deadlineAt }),
      now: () => 1_000,
      maxBackoffMs: 0,
      delay: async (milliseconds) => delays.push(milliseconds),
      fetchImpl: async () =>
        ++calls === 1
          ? response("busy", { status: 429, headers: { "retry-after": "0" } })
          : response("issuer body"),
      resolveHost: publicDns,
    });
    assert.equal(observation.disposition, "success");
    assert.equal(calls, 2);
    assert.deepEqual(delays, [0]);
  }
});
