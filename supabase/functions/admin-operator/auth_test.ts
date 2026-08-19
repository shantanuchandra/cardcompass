import { assertEquals, assertRejects } from "@std/assert";
import { requireAdmin } from "./auth.ts";
import { AdminHttpError } from "./types.ts";

function authorizedRequest(): Request {
  return new Request("http://local", {
    headers: { Authorization: "Bearer valid" },
  });
}

function authenticatedUser(id = "user-1") {
  return {
    auth: {
      getUser: () => Promise.resolve({ data: { user: { id } }, error: null }),
    },
  } as never;
}

function profileDatabase(
  profile: { id: string; is_active: boolean; is_admin: boolean } | null,
  error: unknown = null,
) {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve({ data: profile, error }),
        }),
      }),
    }),
  } as never;
}

async function assertRequestFailed(operation: () => Promise<unknown>) {
  const error = await assertRejects(
    operation,
    AdminHttpError,
    "request_failed",
  );
  assertEquals(error.code, "request_failed");
  assertEquals(error.status, 500);
}

Deno.test("admin auth rejects a missing bearer token before database reads", async () => {
  let reads = 0;

  await assertRejects(
    () => requireAdmin(new Request("http://local"), {} as never, {
      from: () => {
        reads += 1;
        return {} as never;
      },
    } as never),
    AdminHttpError,
    "authentication_required",
  );

  assertEquals(reads, 0);
});

Deno.test("admin auth rejects an invalid bearer token", async () => {
  await assertRejects(
    () => requireAdmin(authorizedRequest(), {
      auth: {
        getUser: () => Promise.resolve({ data: { user: null }, error: new Error("invalid") }),
      },
    } as never, profileDatabase(null)),
    AdminHttpError,
    "authentication_required",
  );
});

Deno.test("admin auth rejects an inactive authenticated user", async () => {
  await assertRejects(
    () => requireAdmin(
      authorizedRequest(),
      authenticatedUser(),
      profileDatabase({ id: "user-1", is_active: false, is_admin: true }),
    ),
    AdminHttpError,
    "administrator_access_required",
  );
});

Deno.test("admin auth rejects an authenticated non-admin user", async () => {
  await assertRejects(
    () => requireAdmin(
      authorizedRequest(),
      authenticatedUser(),
      profileDatabase({ id: "user-1", is_active: true, is_admin: false }),
    ),
    AdminHttpError,
    "administrator_access_required",
  );
});

Deno.test("admin auth rejects an authenticated user with no profile row", async () => {
  await assertRejects(
    () => requireAdmin(authorizedRequest(), authenticatedUser(), profileDatabase(null)),
    AdminHttpError,
    "administrator_access_required",
  );
});

Deno.test("admin auth returns request_failed when database lookup errors", async () => {
  await assertRejects(
    () => requireAdmin(
      authorizedRequest(),
      authenticatedUser(),
      profileDatabase(null, new Error("database unavailable")),
    ),
    AdminHttpError,
    "request_failed",
  );
});

Deno.test("admin auth sanitizes rejected authentication calls", async () => {
  await assertRequestFailed(() => requireAdmin(authorizedRequest(), {
    auth: {
      getUser: () => Promise.reject(new Error("authentication backend unavailable")),
    },
  } as never, profileDatabase(null)));
});

Deno.test("admin auth sanitizes rejected database client calls", async () => {
  await assertRequestFailed(() => requireAdmin(
    authorizedRequest(),
    authenticatedUser(),
    { from: () => { throw new Error("database connection refused"); } } as never,
  ));
});

Deno.test("admin auth sanitizes rejected profile lookup calls", async () => {
  await assertRequestFailed(() => requireAdmin(
    authorizedRequest(),
    authenticatedUser(),
    {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: () => Promise.reject(new Error("profile query timed out")),
          }),
        }),
      }),
    } as never,
  ));
});

Deno.test("admin auth reads active and admin flags by authenticated user id", async () => {
  const actor = await requireAdmin(
    authorizedRequest(),
    authenticatedUser(),
    profileDatabase({ id: "user-1", is_active: true, is_admin: true }),
  );

  assertEquals(actor, { id: "user-1" });
});
