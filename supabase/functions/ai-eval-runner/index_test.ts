import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  assertRegistryMatchesDatabasePolicy,
  getCandidateConfig,
  getEvalConfig,
  getJudgeConfig,
} from "./config_registry.ts";
import { executeEvalCase } from "./executors.ts";
import type { EvalCaseFixture } from "./types.ts";
import evalMigration from "../../migrations/20260819090500_contextual_ai_eval_runs.sql" with {
  type: "text",
};

const fixture = (
  featureKey: EvalCaseFixture["featureKey"],
): EvalCaseFixture => ({
  caseId: "10000000-0000-4000-8000-000000000001",
  revision: 1,
  featureKey,
  inputFixture: featureKey === "statement_processing"
    ? { statement: { currency: "INR", lines: ["Grocer 12.50"] } }
    : featureKey === "card_data"
    ? {
      card_name: "Regalia Gold",
      authoritative_context: { source_ids: ["source-1"] },
    }
    : { owned_card_ids: ["card-1"], eligible_card_ids: ["card-1"] },
  capturedOutput: { secretBaseline: true },
  expectedOutput: { secretExpected: true },
  operatorFeedback: "secret feedback",
  scoringRubric: { secretRubric: true },
  severeFailureConditions: { secretSevere: true },
});

Deno.test("registry exposes only reviewed configuration keys and SQL-parity costs", () => {
  assertEquals(
    getEvalConfig("captured-production-v1").estimatedMaximumCostUsd,
    0,
  );
  assertEquals(
    getCandidateConfig("gemini-3.6-flash-statement-v1").featureKey,
    "statement_processing",
  );
  assertEquals(
    getCandidateConfig("gemini-3.6-flash-card-data-v1").featureKey,
    "card_data",
  );
  assertEquals(
    getCandidateConfig("gemini-3.6-flash-recommendation-v1").featureKey,
    "recommendation",
  );
  assertEquals(
    getJudgeConfig("gemini-3.6-flash-blind-judge-v1").model,
    "gemini-3.6-flash",
  );
  const databasePolicy = Object.fromEntries(
    [...evalMigration.matchAll(/when\s+'([^']+)'\s+then\s+([0-9.]+)/gi)]
      .map((match) => [match[1], Number(match[2])]),
  );
  assertRegistryMatchesDatabasePolicy(databasePolicy);
});

Deno.test("unknown and feature-mismatched keys fail before model execution", async () => {
  let calls = 0;
  const generate = async () => {
    calls++;
    return fakeGeneration({});
  };
  await assertRejects(
    () =>
      executeEvalCase(fixture("statement_processing"), "unknown", { generate }),
    Error,
    "invalid_request",
  );
  await assertRejects(
    () =>
      executeEvalCase(fixture("card_data"), "gemini-3.6-flash-statement-v1", {
        generate,
      }),
    Error,
    "invalid_request",
  );
  assertEquals(calls, 0);
});

Deno.test("captured baseline supports every family without a model call", async () => {
  for (
    const feature of [
      "statement_processing",
      "card_data",
      "recommendation",
    ] as const
  ) {
    const item = fixture(feature);
    const result = await executeEvalCase(item, "captured-production-v1", {
      generate: () => {
        throw new Error("must_not_call");
      },
    });
    assertEquals(result.output, item.capturedOutput);
    assertEquals(result.estimatedCostUsd, 0);
    assertEquals(result.inputTokens, 0);
    assertEquals(result.outputTokens, 0);
  }
});

Deno.test("candidate receives only deeply sanitized fixture inside a fixed, delimited prompt", async () => {
  const item = fixture("card_data");
  const seen: unknown[] = [];
  await executeEvalCase(item, "gemini-3.6-flash-card-data-v1", {
    generate: async (input) => {
      seen.push(input);
      return fakeGeneration({
        card: { id: "card-1", name: "Regalia Gold", issuer: "HDFC" },
        benefits: [],
        sources: [{ id: "source-1", field_paths: ["card.name"] }],
      });
    },
  });
  const serialized = JSON.stringify(seen);
  for (
    const forbidden of [
      "secretBaseline",
      "secretExpected",
      "secret feedback",
      "secretRubric",
      "secretSevere",
    ]
  ) {
    assertEquals(serialized.includes(forbidden), false);
  }
  assertEquals(serialized.includes("BEGIN_UNTRUSTED_INPUT_FIXTURE"), true);
  assertEquals(serialized.includes("No tools are available"), true);
});

Deno.test("fixture rejects nested ground-truth fields before model execution", async () => {
  const item = fixture("statement_processing");
  let calls = 0;
  await assertRejects(
    () =>
      executeEvalCase(
        { ...item, inputFixture: { safe: { expected_output: { answer: 1 } } } },
        "gemini-3.6-flash-statement-v1",
        {
          generate: async () => {
            calls++;
            return fakeGeneration({});
          },
        },
      ),
    Error,
    "invalid_request",
  );
  assertEquals(calls, 0);
});

Deno.test("candidate output is exact, bounded, typed, and grounded", async () => {
  const bad = [
    {
      parsed_statement: {
        currency: "INR",
        transactions: [{
          id: "t1",
          date: "2026-01-01",
          merchant: "M",
          amount: 10,
          currency: "INR",
          type: "debit",
          category: "grocery",
          extra: true,
        }],
      },
    },
    {
      card: { id: "card-1", name: "X", issuer: "Y" },
      benefits: [{
        id: "b1",
        title: "Lounge",
        limit: 4,
        period: "quarter",
        eligibility: "all",
        source_ids: ["missing"],
      }],
      sources: [],
    },
    {
      recommendations: [{
        rank: 1,
        card_id: "card-1",
        benefit_ids: [],
        explanation: "x".repeat(1001),
        source_ids: [],
      }],
    },
  ];
  const cases = [
    [fixture("statement_processing"), "gemini-3.6-flash-statement-v1"],
    [fixture("card_data"), "gemini-3.6-flash-card-data-v1"],
    [fixture("recommendation"), "gemini-3.6-flash-recommendation-v1"],
  ] as const;
  for (let index = 0; index < cases.length; index++) {
    const result = await executeEvalCase(cases[index][0], cases[index][1], {
      generate: async () => fakeGeneration(bad[index]),
    });
    assertEquals(result.executionStatus, "failed");
    assertEquals(result.safeFailureCategory, "invalid_model_output");
  }
});

Deno.test("invalid output retains metering in a safe failure", async () => {
  const result = await executeEvalCase(
    fixture("recommendation"),
    "gemini-3.6-flash-recommendation-v1",
    {
      generate: async () => fakeGeneration({ nope: true }, 23, 11, 48),
    },
  );
  assertEquals(result.executionStatus, "failed");
  assertEquals(result.safeFailureCategory, "invalid_model_output");
  assertEquals([result.inputTokens, result.outputTokens, result.latencyMs], [
    23,
    11,
    48,
  ]);
});

function fakeGeneration(
  output: unknown,
  inputTokens = 3,
  outputTokens = 4,
  latencyMs = 5,
) {
  return {
    model: "gemini-3.6-flash",
    response: output as Record<string, unknown>,
    inputTokens,
    outputTokens,
    latencyMs,
  };
}
