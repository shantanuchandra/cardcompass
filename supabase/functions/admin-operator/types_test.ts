import { assertEquals } from "@std/assert";
import {
  type AdminActionContext,
  AdminHttpError,
  type AdminHttpErrorCode,
} from "./types.ts";

Deno.test("admin action context exposes the narrow RPC contract used by handlers", async () => {
  const context: AdminActionContext = {
    actor: { id: "admin-1" },
    requestId: null,
    db: {
      rpc: () => Promise.resolve({ data: { accepted: true }, error: null }),
    },
  };

  const result = await context.db.rpc("admin_card_data_action", {
    _actor_id: context.actor.id,
  });

  assertEquals(result, { data: { accepted: true }, error: null });
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
