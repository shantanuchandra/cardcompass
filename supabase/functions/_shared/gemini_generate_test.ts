import { assertEquals, assertRejects } from "@std/assert";
import { generateGemini } from "./gemini_generate.ts";

const input = {
  model: "gemini-3.6-flash",
  payload: { contents: [{ parts: [{ text: "hello" }] }] },
};

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
            '{"candidates":[],"usageMetadata":{"totalTokenCount":17}}',
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
  assertEquals(result.selectedModel, "gemini-3.6-flash");
  assertEquals(result.usageTokens, 17);
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
  assertEquals(result.selectedModel, "gemini-3.5-flash");
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
