import { assertEquals } from "@std/assert";
import { handleGeminiProxyRequest } from "./index.ts";

Deno.test("proxy preserves validation, 100 KB cap, and upstream response contract", async () => {
  const base = {
    authenticate: () => Promise.resolve("user"),
    requireActive: () => Promise.resolve(),
    consumeQuota: () => Promise.resolve(true),
  };
  const invalid = await handleGeminiProxyRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer x" },
      body: JSON.stringify({ model: "unknown", payload: {} }),
    }),
    { ...base, generate: () => Promise.reject(new Error("should not call")) },
  );
  assertEquals(invalid.status, 400);
  const huge = await handleGeminiProxyRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer x" },
      body: JSON.stringify({
        model: "gemini-3.6-flash",
        payload: { text: "x".repeat(100_001) },
      }),
    }),
    { ...base, generate: () => Promise.reject(new Error("should not call")) },
  );
  assertEquals(huge.status, 413);
  const upstream = await handleGeminiProxyRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer x" },
      body: JSON.stringify({ model: "gemini-3.6-flash", payload: {} }),
    }),
    {
      ...base,
      generate: () =>
        Promise.resolve({
          status: 418,
          body: '{"upstream":true}',
          selectedModel: "gemini-3.6-flash",
          parsedJson: { upstream: true },
          latencyMs: 1,
        }),
    },
  );
  assertEquals(upstream.status, 418);
  assertEquals(await upstream.text(), '{"upstream":true}');
  assertEquals(upstream.headers.get("access-control-allow-origin"), "*");
});

Deno.test("proxy keeps auth, profile, quota, and safe server failures", async () => {
  const request = () =>
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer x" },
      body: JSON.stringify({ model: "gemini-3.6-flash", payload: {} }),
    });
  const auth = await handleGeminiProxyRequest(request(), {
    authenticate: () => Promise.reject(new Error("no")),
    requireActive: () => Promise.resolve(),
    consumeQuota: () => Promise.resolve(true),
    generate: () => Promise.reject(new Error("no")),
  });
  assertEquals(auth.status, 401);
  const quota = await handleGeminiProxyRequest(request(), {
    authenticate: () => Promise.resolve("user"),
    requireActive: () => Promise.resolve(),
    consumeQuota: () => Promise.resolve(false),
    generate: () => Promise.reject(new Error("no")),
  });
  assertEquals(quota.status, 429);
  const failed = await handleGeminiProxyRequest(request(), {
    authenticate: () => Promise.resolve("user"),
    requireActive: () => Promise.resolve(),
    consumeQuota: () => Promise.resolve(true),
    generate: () => Promise.reject(new Error("secret provider detail")),
  });
  assertEquals(failed.status, 500);
  assertEquals(await failed.json(), { error: "request_failed" });
});
