import { assertEquals, assertObjectMatch } from "jsr:@std/assert@1";
import { handleAiEvalRunnerRequest, type RunnerDependencies } from "./index.ts";
import type { EvalCaseFixture } from "./types.ts";
import evalMigration from "../../migrations/20260819090500_contextual_ai_eval_runs.sql" with {
  type: "text",
};
import supabaseConfig from "../../config.toml" with { type: "text" };
import { validateAiEvalRunnerReceipt } from "../_shared/ai_eval_runner_receipt.ts";

const runId = "10000000-0000-4000-8000-000000000099";
const lease = "20000000-0000-4000-8000-000000000099";
const secret = "service-role-secret-that-is-long-enough";

Deno.test("the worker lease-yield RPC is service-only and lease-fenced", () => {
  assertEquals(
    evalMigration.includes(
      "function public.yield_ai_eval_run(_run_id uuid,_lease_token uuid)",
    ),
    true,
  );
  assertEquals(
    evalMigration.includes("run.lease_token is distinct from _lease_token"),
    true,
  );
  assertEquals(
    evalMigration.includes(
      "grant execute on function public.yield_ai_eval_run(uuid,uuid) to service_role",
    ),
    true,
  );
  assertEquals(
    evalMigration.includes(
      "revoke all on function public.yield_ai_eval_run(uuid,uuid) from public,anon,authenticated",
    ),
    true,
  );
  assertEquals(
    evalMigration.includes(
      "+case when _candidate_config_key='gemini-3.6-flash-recommendation-v1' then 0.01 else 0 end",
    ),
    true,
  );
});

Deno.test("the runner owns service authorization at its private entrypoint", () => {
  assertEquals(
    supabaseConfig.includes(
      '[functions.ai-eval-runner]\nenabled = true\nverify_jwt = false\nentrypoint = "./functions/ai-eval-runner/index.ts"',
    ),
    true,
  );
});

function request(body: unknown, authorization = `Bearer ${secret}`) {
  return new Request("http://localhost/ai-eval-runner", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function item(index = 1): EvalCaseFixture {
  return {
    caseId: `10000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    revision: 1,
    featureKey: "statement_processing",
    inputFixture: {
      safe_input_context: {
        kind: "transaction",
        transaction: {
          id: `txn-${index}`,
          user_card_id: "uc-1",
          statement_id: "st-1",
          amount: 100,
          currency: "INR",
          merchant_name: "Store",
          transaction_date: "2026-08-01",
        },
      },
      authoritative_context: {},
    },
    capturedOutput: {
      id: `txn-${index}`,
      user_card_id: "uc-1",
      statement_id: "st-1",
      amount: 100,
      currency: "INR",
      merchant_name: "Store",
      category: "shopping",
      transaction_type: "debit",
      transaction_date: "2026-08-01",
    },
    scoringRubric: {
      assertions: [{
        key: "amount",
        path: "$.amount",
        operator: "equals",
        expectedPath: "$.amount",
      }],
    },
    expectedOutput: { amount: 100 },
    severeFailureConditions: { assertionKeys: ["amount"] },
  };
}

function dependencies(count = 1) {
  const fixtures = Array.from({ length: count }, (_, index) => item(index + 1));
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const recorded: Record<string, unknown>[] = [];
  const deps: RunnerDependencies = {
    serviceRoleSecret: secret,
    rpc: (name, args) => {
      calls.push({ name, args });
      if (name === "claim_ai_eval_run_batch") {
        return Promise.resolve({
          run_id: runId,
          lease_token: lease,
          cases: fixtures.map((entry) => ({
            case_id: entry.caseId,
            revision: entry.revision,
            feature_key: entry.featureKey,
          })),
          baseline_config_key: "captured-production-v1",
          candidate_config_key: "gemini-3.6-flash-statement-v1",
          judge_config_key: "gemini-3.6-flash-blind-judge-v1",
        });
      }
      if (name === "record_ai_eval_result") {
        recorded.push(args._result as Record<string, unknown>);
      }
      if (name === "finish_ai_eval_run") {
        return Promise.resolve({ run_id: runId, status: "completed" });
      }
      if (name === "yield_ai_eval_run") {
        return Promise.resolve({
          run_id: runId,
          status: "running",
          continuation_required: false,
        });
      }
      return Promise.resolve({ status: "running" });
    },
    loadCase: (id, revision) =>
      Promise.resolve(
        fixtures.find((entry) =>
          entry.caseId === id && entry.revision === revision
        )!,
      ),
    readRunState: () =>
      Promise.resolve({ status: "running", leaseToken: lease }),
    generate: async () => ({
      model: "gemini-3.6-flash",
      response: fixtures[recorded.length].capturedOutput,
      inputTokens: 7,
      outputTokens: 3,
      latencyMs: 11,
    }),
    scheduleContinuation: () => Promise.resolve(),
    waitUntil: () => {},
  };
  return { deps, calls, recorded, fixtures };
}

Deno.test("service authorization happens before request parsing or database access", async () => {
  let bodyRead = false;
  let dbCalls = 0;
  const { deps } = dependencies();
  deps.rpc = () => {
    dbCalls++;
    return Promise.resolve(null);
  };
  const guarded = new Request("http://localhost/ai-eval-runner", {
    method: "POST",
    headers: { authorization: "Bearer user-or-admin-jwt" },
    body: "not-json",
  });
  Object.defineProperty(guarded, "text", {
    value: () => {
      bodyRead = true;
      return Promise.resolve("not-json");
    },
  });
  const response = await handleAiEvalRunnerRequest(guarded, deps);
  assertEquals(response.status, 401);
  assertEquals(bodyRead, false);
  assertEquals(dbCalls, 0);
});

Deno.test("request body is an exact run_id object", async () => {
  for (
    const body of [{}, { run_id: "bad" }, { run_id: runId, extra: true }, []]
  ) {
    const { deps, calls } = dependencies();
    const response = await handleAiEvalRunnerRequest(request(body), deps);
    assertEquals(response.status, 400);
    assertEquals(calls.length, 0);
  }
});

Deno.test("an unclaimed run emits the shared exact safe receipt", async () => {
  const { deps } = dependencies();
  deps.rpc = () => Promise.resolve(null);
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  validateAiEvalRunnerReceipt(response.status, await response.json(), runId);
});

Deno.test("exactly five completed cases finish without a false continuation", async () => {
  const { deps, calls, recorded } = dependencies(5);
  let schedules = 0;
  deps.scheduleContinuation = () => {
    schedules++;
    return Promise.resolve();
  };
  let active = 0;
  let peak = 0;
  const originalGenerate = deps.generate;
  deps.generate = async (input) => {
    active++;
    peak = Math.max(peak, active);
    const value = await originalGenerate(input);
    active--;
    return value;
  };
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 200);
  validateAiEvalRunnerReceipt(
    response.status,
    await response.clone().json(),
    runId,
  );
  assertEquals(peak, 1);
  assertEquals(calls[0], {
    name: "claim_ai_eval_run_batch",
    args: { _run_id: runId, _batch_limit: 5 },
  });
  assertEquals(recorded.length, 5);
  assertObjectMatch(recorded[0], {
    feature_key: "statement_processing",
    execution_status: "succeeded",
    baseline_input_tokens: 0,
    candidate_input_tokens: 7,
    candidate_output_tokens: 3,
    candidate_latency_ms: 11,
  });
  assertEquals(schedules, 0);
  assertEquals(calls.some((call) => call.name === "finish_ai_eval_run"), true);
});

Deno.test("five zero-cost failures become terminal and are not automatically reclaimed", async () => {
  const { deps, calls, recorded } = dependencies(5);
  let schedules = 0;
  deps.generate = () => Promise.reject(new Error("provider_down"));
  deps.scheduleContinuation = () => {
    schedules++;
    return Promise.resolve();
  };
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 200);
  assertEquals(
    recorded.every((value) => value.execution_status === "failed"),
    true,
  );
  assertEquals(schedules, 0);
  assertEquals(calls.some((call) => call.name === "finish_ai_eval_run"), true);
});

Deno.test("cancellation between cases stops without recording or finishing another case", async () => {
  const { deps, calls, recorded } = dependencies(3);
  let checks = 0;
  deps.readRunState = () =>
    Promise.resolve(
      checks++ === 0
        ? { status: "running", leaseToken: lease }
        : { status: "cancelled", leaseToken: null },
    );
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  validateAiEvalRunnerReceipt(
    response.status,
    await response.clone().json(),
    runId,
  );
  assertEquals((await response.json()).status, "cancelled");
  assertEquals(recorded.length, 1);
  assertEquals(calls.some((call) => call.name === "finish_ai_eval_run"), false);
});

Deno.test("database cost stop is returned safely without provider work", async () => {
  const { deps } = dependencies();
  let generated = false;
  deps.generate = () => {
    generated = true;
    throw new Error("must_not_call");
  };
  deps.rpc = () =>
    Promise.resolve({
      run_id: runId,
      cases: [],
      safe_failure_category: "cost_ceiling_reached",
    });
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  validateAiEvalRunnerReceipt(
    response.status,
    await response.clone().json(),
    runId,
  );
  assertEquals(await response.json(), {
    run_id: runId,
    status: "completed_with_failures",
    processed: 0,
    safe_failure_category: "cost_ceiling_reached",
  });
  assertEquals(generated, false);
});

Deno.test("a full batch yields its lease and schedules exactly one continuation", async () => {
  const { deps, calls } = dependencies(5);
  const originalRpc = deps.rpc;
  deps.rpc = (name, args) =>
    name === "yield_ai_eval_run"
      ? (calls.push({ name, args }),
        Promise.resolve({
          run_id: runId,
          status: "running",
          continuation_required: true,
        }))
      : originalRpc(name, args);
  let schedules = 0;
  let background: Promise<unknown> | undefined;
  deps.scheduleContinuation = (id) => {
    schedules++;
    assertEquals(id, runId);
    return Promise.resolve();
  };
  deps.waitUntil = (promise) => background = promise;
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 202);
  validateAiEvalRunnerReceipt(
    response.status,
    await response.clone().json(),
    runId,
  );
  assertObjectMatch(await response.clone().json(), {
    status: "running",
    continuation_required: true,
  });
  await background;
  assertEquals(schedules, 1);
  assertEquals(
    calls.filter((call) => call.name === "yield_ai_eval_run").length,
    1,
  );
  assertEquals(calls.some((call) => call.name === "finish_ai_eval_run"), false);
});

Deno.test("continuation scheduling failure leaves the yielded run resumable", async () => {
  const { deps, calls } = dependencies(5);
  const originalRpc = deps.rpc;
  deps.rpc = (name, args) =>
    name === "yield_ai_eval_run"
      ? (calls.push({ name, args }),
        Promise.resolve({
          run_id: runId,
          status: "running",
          continuation_required: true,
        }))
      : originalRpc(name, args);
  let background: Promise<unknown> | undefined;
  deps.scheduleContinuation = () => Promise.reject(new Error("scheduler_down"));
  deps.waitUntil = (promise) => background = promise;
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 202);
  assertEquals(
    (await response.clone().json()).continuation_scheduled,
    undefined,
  );
  await background;
  assertEquals(
    calls.filter((call) => call.name === "yield_ai_eval_run").length,
    1,
  );
});

Deno.test("background scheduler registration failure still returns a resumable receipt", async () => {
  const { deps, calls } = dependencies(5);
  const originalRpc = deps.rpc;
  deps.rpc = (name, args) =>
    name === "yield_ai_eval_run"
      ? (calls.push({ name, args }),
        Promise.resolve({
          run_id: runId,
          status: "running",
          continuation_required: true,
        }))
      : originalRpc(name, args);
  deps.waitUntil = () => {
    throw new Error("runtime_rejected_background_task");
  };
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 202);
  assertObjectMatch(await response.json(), {
    run_id: runId,
    status: "running",
    processed: 5,
    continuation_required: true,
  });
  assertEquals(
    calls.filter((call) => call.name === "yield_ai_eval_run").length,
    1,
  );
});

Deno.test("stale lease rejection is safe and does not expose fixtures", async () => {
  const { deps, fixtures } = dependencies();
  deps.rpc = (name) =>
    name === "claim_ai_eval_run_batch"
      ? Promise.resolve({
        run_id: runId,
        lease_token: lease,
        cases: [{
          case_id: fixtures[0].caseId,
          revision: 1,
          feature_key: "statement_processing",
        }],
        baseline_config_key: "captured-production-v1",
        candidate_config_key: "gemini-3.6-flash-statement-v1",
        judge_config_key: "gemini-3.6-flash-blind-judge-v1",
      })
      : Promise.reject(new Error("state_conflict"));
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  const text = await response.text();
  assertEquals(response.status, 409);
  assertEquals(text.includes("Store"), false);
  assertEquals(text.includes("shopping"), false);
  assertEquals(JSON.parse(text), { error: "state_conflict" });
});

Deno.test("provider failures are recorded with safe metering fields only", async () => {
  const { deps, recorded } = dependencies();
  deps.generate = () => Promise.reject(new Error("provider secret response"));
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body, { run_id: runId, status: "completed", processed: 1 });
  assertObjectMatch(recorded[0], {
    execution_status: "failed",
    safe_failure_category: "model_unavailable",
    candidate_input_tokens: 0,
    candidate_output_tokens: 0,
    requires_review: true,
  });
  assertEquals(JSON.stringify(body).includes("provider secret"), false);
});

Deno.test("executor or scoring failures become metered safe case results", async () => {
  const { deps, recorded } = dependencies();
  const originalRpc = deps.rpc;
  deps.rpc = async (name, args) => {
    const result = await originalRpc(name, args) as Record<string, unknown>;
    if (name === "claim_ai_eval_run_batch") {
      result.candidate_config_key = "invalid-reviewed-key";
    }
    return result;
  };
  const response = await handleAiEvalRunnerRequest(
    request({ run_id: runId }),
    deps,
  );
  assertEquals(response.status, 200);
  assertObjectMatch(recorded[0], {
    execution_status: "failed",
    safe_failure_category: "provider_failed",
    baseline_input_tokens: 0,
    candidate_input_tokens: 0,
    estimated_cost_usd: 0,
  });
});
