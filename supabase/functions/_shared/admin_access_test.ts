import { assertEquals, assertRejects } from "@std/assert";

type Resolver = (
  request: Request,
  authDb: unknown,
  serviceDb: unknown,
) => Promise<{ id: string }>;

async function resolver(): Promise<Resolver> {
  try {
    const module = await import("./admin_access.ts");
    return module.resolveAdminActor as Resolver;
  } catch {
    throw new Error("shared admin access resolver is missing");
  }
}

function bearerRequest() {
  return new Request("https://example.test", {
    headers: { authorization: "Bearer caller-token" },
  });
}

function authClient(
  result: { data: { user: Record<string, unknown> | null }; error: unknown },
) {
  return { auth: { getUser: () => Promise.resolve(result) } };
}

function profileClient(
  profiles: Array<{ id: string; is_active: boolean; is_admin: boolean } | null>,
) {
  let reads = 0;
  return {
    get reads() {
      return reads;
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => {
            const data = profiles[Math.min(reads, profiles.length - 1)];
            reads += 1;
            return Promise.resolve({ data, error: null });
          },
        }),
      }),
    }),
  };
}

async function assertAccessError(
  operation: () => Promise<unknown>,
  code: string,
  status: number,
) {
  const error = await assertRejects(operation, Error, code) as Error & {
    code: string;
    status: number;
  };
  assertEquals(error.code, code);
  assertEquals(error.status, status);
}

Deno.test("shared admin access rejects missing bearer credentials before dependencies", async () => {
  const resolve = await resolver();
  await assertAccessError(
    () => resolve(new Request("https://example.test"), {}, {}),
    "authentication_required",
    401,
  );
});

Deno.test("shared admin access classifies invalid credentials as 401", async () => {
  const resolve = await resolver();
  await assertAccessError(
    () =>
      resolve(
        bearerRequest(),
        authClient({
          data: { user: null },
          error: { code: "bad_jwt", status: 401, message: "secret detail" },
        }),
        profileClient([null]),
      ),
    "authentication_required",
    401,
  );
});

Deno.test("shared admin access rejects missing inactive and non-admin profiles", async () => {
  const resolve = await resolver();
  const auth = authClient({ data: { user: { id: "user-1" } }, error: null });
  for (
    const profile of [
      null,
      { id: "user-1", is_active: false, is_admin: true },
      { id: "user-1", is_active: true, is_admin: false },
    ]
  ) {
    await assertAccessError(
      () => resolve(bearerRequest(), auth, profileClient([profile])),
      "administrator_access_required",
      403,
    );
  }
});

Deno.test("shared admin access trusts only the database flags and reads them on every request", async () => {
  const resolve = await resolver();
  const auth = authClient({
    data: {
      user: {
        id: "user-1",
        email: "anyone@example.test",
        email_confirmed_at: null,
        user_metadata: { is_admin: false },
      },
    },
    error: null,
  });
  const profiles = profileClient([
    { id: "user-1", is_active: true, is_admin: true },
    { id: "user-1", is_active: true, is_admin: false },
  ]);

  assertEquals(await resolve(bearerRequest(), auth, profiles), {
    id: "user-1",
  });
  await assertAccessError(
    () => resolve(bearerRequest(), auth, profiles),
    "administrator_access_required",
    403,
  );
  assertEquals(profiles.reads, 2);
});

Deno.test("shared admin access sanitizes transient auth and profile failures", async () => {
  const resolve = await resolver();
  await assertAccessError(
    () =>
      resolve(
        bearerRequest(),
        authClient({
          data: { user: null },
          error: { status: 503, message: "upstream auth secret" },
        }),
        profileClient([null]),
      ),
    "request_failed",
    500,
  );
  await assertAccessError(
    () =>
      resolve(
        bearerRequest(),
        authClient({ data: { user: { id: "user-1" } }, error: null }),
        {
          from: () => ({
            select: () => ({
              eq: () => ({
                maybeSingle: () => Promise.reject(new Error("database secret")),
              }),
            }),
          }),
        },
      ),
    "request_failed",
    500,
  );
});

Deno.test("shared admin access treats malformed dependency responses as retryable", async () => {
  const resolve = await resolver();
  await assertAccessError(
    () =>
      resolve(
        bearerRequest(),
        { auth: { getUser: () => Promise.resolve({ data: {}, error: null }) } },
        profileClient([null]),
      ),
    "request_failed",
    500,
  );
  await assertAccessError(
    () =>
      resolve(
        bearerRequest(),
        authClient({ data: { user: { id: "user-1" } }, error: null }),
        {
          from: () => ({
            select: () => ({
              eq: () => ({ maybeSingle: () => Promise.resolve(undefined) }),
            }),
          }),
        },
      ),
    "request_failed",
    500,
  );
});
