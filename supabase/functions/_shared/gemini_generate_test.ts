import { assertEquals, assertRejects } from "@std/assert";
import { configuredGeminiKeys, generateGemini } from "./gemini_generate.ts";

const input = {
  model: "gemini-3.6-flash",
  payload: { contents: [{ parts: [{ text: "hello" }] }] },
};

Deno.test("Gemini key discovery loads every contiguous configured key", () => {
  const values: Record<string, string> = {
    GEMINI_API_KEY: "one",
    GEMINI_API_KEY_2: "two",
    GEMINI_API_KEY_3: "three",
  };
  assertEquals(configuredGeminiKeys((name) => values[name]), [
    "one",
    "two",
    "three",
  ]);
});

Deno.test("Gemini transport rotates keys on 429 and reports parsed usage", async () => {
  const urls: string[] = [];
  const result = await generateGemini(input, {
    apiKeys: ["first", "second"],
    fetch: (url) => {
      urls.push(String(url));
      return Promise.resolve(
        urls.length === 1
          ? new Response('{"error":"quota"}', { status: 429 })
          : new Response(
            '{"candidates":[],"usageMetadata":{"promptTokenCount":11,"candidatesTokenCount":6,"totalTokenCount":17}}',
            { status: 200 },
          ),
      );
    },
    now: (() => {
      let value = 10;
      return () => value += 5;
    })(),
  });
  assertEquals(urls.length, 2);
  assertEquals(urls[0].includes("key=first"), true);
  assertEquals(urls[1].includes("key=second"), true);
  assertEquals(result.status, 200);
  assertEquals(result.model, "gemini-3.6-flash");
  assertEquals(result.inputTokens, 11);
  assertEquals(result.outputTokens, 6);
  assertEquals(result.latencyMs, 5);
});

Deno.test("Gemini transport falls forward only for unavailable models", async () => {
  const urls: string[] = [];
  const result = await generateGemini(input, {
    apiKeys: ["key"],
    fetch: (url) => {
      urls.push(String(url));
      return Promise.resolve(
        urls.length === 1
          ? new Response('{"error":"model not found"}', { status: 404 })
          : new Response('{"candidates":[]}', { status: 200 }),
      );
    },
  });
  assertEquals(urls.length, 2);
  assertEquals(result.model, "gemini-3.5-flash");
});

Deno.test("Gemini transport exhausts keys for one unavailable model before advancing", async () => {
  const calls: string[] = [];
  const result = await generateGemini(input, {
    apiKeys: ["first", "second"],
    fetch: (url) => {
      const parsed = new URL(String(url));
      calls.push(
        `${parsed.pathname.split("/").at(-1)}:${
          parsed.searchParams.get("key")
        }`,
      );
      return Promise.resolve(
        calls.length < 3
          ? new Response('{"error":"model not found"}', { status: 404 })
          : new Response('{"candidates":[]}', { status: 200 }),
      );
    },
  });
  assertEquals(calls, [
    "gemini-3.6-flash:generateContent:first",
    "gemini-3.6-flash:generateContent:second",
    "gemini-3.5-flash:generateContent:first",
  ]);
  assertEquals(result.model, "gemini-3.5-flash");
});

Deno.test("Gemini transport tries the next supported model after every key is rate limited", async () => {
  const urls: string[] = [];
  const result = await generateGemini(input, {
    apiKeys: ["first", "second"],
    fetch: (url) => {
      urls.push(String(url));
      return Promise.resolve(
        urls.length <= 2
          ? new Response('{"error":"quota"}', { status: 429 })
          : new Response('{"candidates":[]}', { status: 200 }),
      );
    },
  });
  assertEquals(urls.length, 3);
  assertEquals(urls[2].includes("gemini-3.5-flash"), true);
  assertEquals(result.status, 200);
});

Deno.test("Gemini transport bounds every attempt and exposes only safe errors", async () => {
  let receivedSignal: AbortSignal | null | undefined;
  await assertRejects(
    () =>
      generateGemini(input, {
        apiKeys: ["key"],
        fetch: (_url, init) => {
          receivedSignal = init?.signal;
          throw new DOMException("timed out", "TimeoutError");
        },
      }),
    Error,
    "model_unavailable",
  );
  assertEquals(receivedSignal instanceof AbortSignal, true);
  await assertRejects(
    () => generateGemini(input, { apiKeys: [], fetch }),
    Error,
    "model_unavailable",
  );
});

Deno.test("Gemini transport preserves an ordinary upstream status and body", async () => {
  const result = await generateGemini(input, {
    apiKeys: ["key"],
    fetch: () =>
      Promise.resolve(new Response("upstream detail", { status: 400 })),
  });
  assertEquals({ status: result.status, body: result.body }, {
    status: 400,
    body: "upstream detail",
  });
});

Deno.test("Gemini transport normalizes absent and malformed usage counts", async () => {
  const result = await generateGemini(input, {
    apiKeys: ["key"],
    fetch: () =>
      Promise.resolve(
        new Response(
          '{"candidates":[],"usageMetadata":{"promptTokenCount":"secret","candidatesTokenCount":null}}',
        ),
      ),
  });
  assertEquals({ input: result.inputTokens, output: result.outputTokens }, {
    input: 0,
    output: 0,
  });
});

Deno.test("Gemini transport includes reasoning tokens exactly once", async () => {
  const result = await generateGemini(input, {
    apiKeys: ["key"],
    fetch: () =>
      Promise.resolve(
        new Response(JSON.stringify({
          candidates: [],
          usageMetadata: {
            promptTokenCount: 4,
            candidatesTokenCount: 7,
            thoughtsTokenCount: 3,
            totalTokenCount: 14,
          },
        })),
      ),
  });
  assertEquals(result.inputTokens, 4);
  assertEquals(result.outputTokens, 10);
});

Deno.test("Gemini transport rejects unknown models and oversized private payloads before fetch", async () => {
  let calls = 0;
  const dependencies = {
    apiKeys: ["key"],
    fetch: () => {
      calls++;
      return Promise.resolve(new Response("{}"));
    },
  };
  await assertRejects(
    () =>
      generateGemini({ model: "attacker-model", payload: {} }, dependencies),
    Error,
    "invalid_request",
  );
  await assertRejects(
    () => generateGemini({ model: "  ", payload: {} }, dependencies),
    Error,
    "invalid_request",
  );
  await assertRejects(
    () => generateGemini({ model: "", payload: {} }, dependencies),
    Error,
    "invalid_request",
  );
  await assertRejects(
    () =>
      generateGemini({
        model: "gemini-3.6-flash",
        payload: { text: "€".repeat(40_000) },
      }, dependencies),
    Error,
    "invalid_request",
  );
  assertEquals(calls, 0);
});
