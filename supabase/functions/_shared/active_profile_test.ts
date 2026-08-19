import { assertEquals } from "@std/assert";
import { readActiveProfile } from "./active_profile.ts";

function db(result: unknown) {
  return {
    from: (_table: string) => ({
      select: (_columns: string) => ({
        eq: (_column: string, _value: string) => ({
          maybeSingle: async () => result,
        }),
      }),
    }),
  };
}

Deno.test("active profile gate distinguishes active, inactive, missing, and unavailable", async () => {
  assertEquals(
    await readActiveProfile(
      db({ data: { id: "u", is_active: true }, error: null }),
      "u",
    ),
    "active",
  );
  assertEquals(
    await readActiveProfile(
      db({ data: { id: "u", is_active: false }, error: null }),
      "u",
    ),
    "inactive",
  );
  assertEquals(
    await readActiveProfile(db({ data: null, error: null }), "u"),
    "missing",
  );
  assertEquals(
    await readActiveProfile(
      db({ data: null, error: { message: "secret" } }),
      "u",
    ),
    "unavailable",
  );
});
