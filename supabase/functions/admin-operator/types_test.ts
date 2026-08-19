import { assertEquals } from "@std/assert";
import {
  type AdminActionContext,
  type AdminAuthClient,
  AdminHttpError,
  type AdminHttpErrorCode,
} from "./types.ts";

Deno.test("admin action context exposes the narrow RPC contract used by handlers", async () => {
  const context: AdminActionContext = {
    actor: { id: "admin-1" },
    requestId: null,
    db: {
      from: () => ({
        select: () => ({
          eq() {
            return this;
          },
          order() {
            return this;
          },
          range: () => Promise.resolve({ data: [], error: null }),
        }),
      }),
      rpc: () => Promise.resolve({ data: { accepted: true }, error: null }),
    },
  };

  const result = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
  });

  assertEquals(result, { data: { accepted: true }, error: null });

  const rows = await context.db.from("card_catalog_review_queue")
    .select("id,status")
    .eq("status", "pending")
    .order("updated_at", { ascending: false })
    .range(0, 25);
  assertEquals(rows, { data: [], error: null });
});

Deno.test("admin auth lookup client is independent from handler database methods", async () => {
  const authDb: AdminAuthClient = {
    auth: {
      getUser: () =>
        Promise.resolve({ data: { user: { id: "admin-1" } }, error: null }),
    },
  };

  assertEquals(await authDb.auth.getUser("token"), {
    data: { user: { id: "admin-1" } },
    error: null,
  });
});

Deno.test("admin HTTP errors accept the planned stable handler codes", () => {
  const cases: ReadonlyArray<readonly [AdminHttpErrorCode, number]> = [
    ["invalid_request", 400],
    ["not_found", 404],
    ["state_conflict", 409],
    ["reason_required", 400],
  ];

  assertEquals(
    cases.map(([code, status]) => new AdminHttpError(code, status).code),
    cases.map(([code]) => code),
  );
});
