import { assertEquals } from "@std/assert";
import { createAdminOperatorAuthClient, handleAdminOperator } from "./index.ts";
import { AdminHttpError } from "./types.ts";

const utf8 = new TextEncoder();

Deno.test("gateway auth client is stateless inside Edge", () => {
  let invocation: unknown[] = [];
  const request = new Request("http://local", {
    headers: {
      authorization: "Bearer user-jwt",
      apikey: "request-anon-key",
    },
  });

  const client = createAdminOperatorAuthClient(
    request,
    "https://project.supabase.co",
    "fallback-anon-key",
    (...args: unknown[]) => {
      invocation = args;
      return { marker: "client" };
    },
  );

  assertEquals(client, { marker: "client" });
  assertEquals(invocation, [
    "https://project.supabase.co",
    "request-anon-key",
    {
      global: { headers: { Authorization: "Bearer user-jwt" } },
      auth: { autoRefreshToken: false, persistSession: false },
    },
  ]);
});

function dependencies(overrides: Record<string, unknown> = {}) {
  return {
    authorize: () => Promise.resolve({ id: "admin-1" }),
    db: {},
    ...overrides,
  } as never;
}

function jsonRequest(body: string, method = "POST"): Request {
  return new Request("http://local", { method, body });
}

Deno.test("gateway serves access after authorization", async () => {
  let authorizations = 0;
  const response = await handleAdminOperator(
    jsonRequest(JSON.stringify({ action: "access" })),
    dependencies({
      authorize: () => {
        authorizations += 1;
        return Promise.resolve({ id: "admin-1" });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { is_admin: true });
  assertEquals(authorizations, 1);
});

Deno.test("gateway rejects malformed JSON with a stable invalid_request code", async () => {
  const response = await handleAdminOperator(
    jsonRequest('{"action":"access"'),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway rejects empty and non-object request bodies", async () => {
  for (const body of ["", "null", "[]", '"access"']) {
    const response = await handleAdminOperator(
      jsonRequest(body),
      dependencies(),
    );

    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_request" });
  }
});

Deno.test("gateway accepts a 32 KiB UTF-8 body", async () => {
  const body = `{"action":"access","note":"a${"é".repeat(16_369)}"}`;
  assertEquals(utf8.encode(body).length, 32_768);

  const response = await handleAdminOperator(jsonRequest(body), dependencies());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { is_admin: true });
});

Deno.test("gateway rejects bodies over the 32 KiB UTF-8 limit", async () => {
  const body = `{"action":"access","note":"a${"é".repeat(16_369)}b"}`;
  assertEquals(utf8.encode(body).length, 32_769);

  const response = await handleAdminOperator(jsonRequest(body), dependencies());

  assertEquals(response.status, 413);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway rejects unsupported HTTP methods", async () => {
  const response = await handleAdminOperator(
    new Request("http://local", { method: "GET" }),
    dependencies(),
  );

  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway authorizes before rejecting an unsupported action", async () => {
  const response = await handleAdminOperator(
    jsonRequest(JSON.stringify({ action: "raw-sql" })),
    dependencies({
      authorize: () =>
        Promise.reject(
          new AdminHttpError("administrator_access_required", 403),
        ),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(await response.json(), {
    error: "administrator_access_required",
  });
});

Deno.test("gateway rejects unsupported actions with a stable invalid_request code", async () => {
  const response = await handleAdminOperator(
    jsonRequest(JSON.stringify({ action: "raw-sql" })),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway rejects retry with an explicitly present null operation", async () => {
  const response = await handleAdminOperator(
    jsonRequest(JSON.stringify({
      action: "system-retry",
      operation: null,
      family: "benefit_enrichment",
      status: "failed",
      target_id: "00000000-0000-4000-8000-000000000010",
      request_id: "00000000-0000-4000-8000-000000000020",
      observed_updated_at: "2026-08-19T12:00:00Z",
    })),
    dependencies({
      db: {
        rpc: () => {
          throw new Error("must not reach rpc");
        },
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway rejects inherited constructor actions without echoing the body", async () => {
  const response = await handleAdminOperator(
    jsonRequest(
      JSON.stringify({ action: "constructor", secret: "do-not-echo" }),
    ),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway rejects inherited toString actions without echoing the body", async () => {
  const response = await handleAdminOperator(
    jsonRequest(JSON.stringify({ action: "toString", secret: "do-not-echo" })),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "invalid_request" });
});

Deno.test("gateway hides unexpected internal errors behind a stable response", async () => {
  const request = jsonRequest(JSON.stringify({ action: "access" }));
  Object.defineProperty(request, "text", {
    value: () => Promise.reject(new Error("sensitive transport failure")),
  });

  const response = await handleAdminOperator(request, dependencies());

  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "request_failed" });
});
