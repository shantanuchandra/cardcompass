import { initializePilotJobs } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("pilot API refuses catalog-v1 before selecting or writing jobs", async () => {
  let rpcCalls = 0;
  const db = {
    async rpc() {
      rpcCalls += 1;
      return { data: [], error: null };
    },
  };
  let error: unknown;
  try {
    await initializePilotJobs(db, [], "catalog-v1");
  } catch (caught) {
    error = caught;
  }
  assert(
    error instanceof Error && error.message === "reserved_parser_version",
    "reserved parser was not rejected at the pilot API boundary",
  );
  assert(rpcCalls === 0, "rejected parser reached the pilot RPC");
});
