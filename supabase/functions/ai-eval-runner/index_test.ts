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
    ? {
      safe_input_context: {
        kind: "transaction",
        transaction: {
          id: "txn-1",
          user_card_id: "uc-1",
          statement_id: "st-1",
          amount: 1249,
          currency: "INR",
          merchant_name: "Big Bazaar",
          transaction_date: "2026-08-01",
        },
      },
      authoritative_context: {},
    }
    : featureKey === "card_data"
    ? {
      safe_input_context: {
        kind: "card_data",
        evaluation_mode: "catalog_identity_validation",
        identifiers: {
          entered_name: "Regalia Gold",
          issuer_hint: "HDFC",
          last_four_digits: "1234",
        },
        official_sources: [{
          id: "source-1",
          url: "https://bank.example/card",
          snippet: "Regalia Gold by HDFC. Annual fee INR 2500.",
          facts: {
            evaluation_mode: "catalog_identity_validation",
            provenance_claims: {
              issuer: "HDFC",
              card_name: "Regalia Gold",
              network: "Visa",
              aliases: ["Regalia Gold"],
            },
            catalog_reference: {
              id: "card-1",
              name: "Regalia Gold",
              bank: "HDFC",
              network: "Visa",
              annual_fee: 2500,
              joining_fee: 2500,
            },
          },
        }, {
          id: "source-benefit-1",
          url: "https://bank.example/benefit",
          snippet: "Four lounge visits",
          facts: {
            evaluation_mode: "benefit_extraction",
            catalog_reference_id: "card-1",
            benefits: [{
              id: "benefit-1",
              dedupe_key: "lounge",
              title: "Lounge",
              type: "access",
              category: "travel",
              value_config: { limit: 4 },
              limit: 4,
              period: "quarter",
              eligibility: "primary cardholder",
            }],
          },
        }],
      },
      authoritative_context: {},
    }
    : {
      safe_input_context: {
        number_of_tickets: 2,
        price_per_ticket: 400,
        task: "explain_fixed_selection",
      },
      authoritative_context: {
        cards: [{ id: "card-1" }],
        benefits: [{
          benefit_id: "benefit-1",
          value_config: {
            discount_percent: 25,
            max_discount_per_transaction: 200,
          },
        }],
        owned_card_ids: ["card-1"],
      },
    },
  capturedOutput: featureKey === "statement_processing"
    ? {
      id: "txn-1",
      user_card_id: "uc-1",
      statement_id: "st-1",
      amount: 1249,
      currency: "INR",
      merchant_name: "Big Bazaar",
      category: "shopping",
      transaction_type: "debit",
      transaction_date: "2026-08-01",
    }
    : featureKey === "card_data"
    ? {
      user_card: {
        id: "uc-1",
        catalog_card_id: "card-1",
        last_four_digits: "1234",
        is_active: true,
        created_at: "x",
        updated_at: "y",
      },
      catalog_card: {
        id: "card-1",
        card_name: "Regalia Gold",
        bank: "HDFC",
        network: "Visa",
        card_type: "credit",
        annual_fee: 2500,
        joining_fee: 2500,
        is_discontinued: false,
        updated_at: "2026-08-01",
      },
    }
    : {
      selected_card_id: "card-1",
      selected_benefit_id: "benefit-1",
      savings: 200,
      final_amount: 600,
      explanation: "Save on two tickets.",
    },
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
  assertEquals(
    getCandidateConfig("gemini-3.6-flash-recommendation-v1").taskScope,
    "fixed_selection_explanation_and_arithmetic",
  );
  const databasePolicy = Object.fromEntries(
    [...evalMigration.matchAll(/when\s+'([^']+)'\s+then\s+([0-9.]+)/gi)]
      .map((match) => [match[1], Number(match[2])]),
  );
  assertRegistryMatchesDatabasePolicy(databasePolicy);
  assertEquals(
    evalMigration.includes("_baseline_config_key<>'captured-production-v1'"),
    true,
  );
  assertEquals(
    evalMigration.includes(
      "_judge_config_key<>'gemini-3.6-flash-blind-judge-v1'",
    ),
    true,
  );
  for (
    const [key, feature] of [
      ["gemini-3.6-flash-statement-v1", "statement_processing"],
      ["gemini-3.6-flash-card-data-v1", "card_data"],
      ["gemini-3.6-flash-recommendation-v1", "recommendation"],
    ]
  ) {
    assertEquals(
      evalMigration.includes(`when '${key}' then '${feature}'`),
      true,
    );
    assertEquals(getCandidateConfig(key).featureKey, feature);
  }
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

Deno.test("captured baseline supports structured non-card families without a model call", async () => {
  for (
    const feature of [
      "statement_processing",
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

Deno.test("captured card identity baseline normalizes persisted DTOs into the exact grounded mode", async () => {
  const item = fixture("card_data");
  const result = await executeEvalCase(item, "captured-production-v1", {
    generate: () => {
      throw new Error("must_not_call");
    },
  });
  assertEquals(result.executionStatus, "succeeded");
  assertEquals(result.output, {
    mode: "identity",
    card: {
      id: "card-1",
      name: "Regalia Gold",
      bank: "HDFC",
      network: "Visa",
      annual_fee: 2500,
      joining_fee: 2500,
    },
    sources: [{ id: "source-1", field_paths: ["facts.catalog_reference"] }],
  });
});

Deno.test("captured benefit baseline uses persisted values and official grounding without answer leakage", async () => {
  const item = fixture("card_data");
  const safe = item.inputFixture.safe_input_context as Record<string, unknown>;
  const official = safe.official_sources as Record<string, unknown>[];
  const benefitItem: EvalCaseFixture = {
    ...item,
    inputFixture: {
      ...item.inputFixture,
      safe_input_context: {
        ...safe,
        evaluation_mode: "benefit_extraction",
        official_sources: official.map((source) =>
          source.id === "source-benefit-1"
            ? {
              ...source,
              facts: {
                evaluation_mode: "benefit_extraction",
                catalog_reference_id: "card-1",
                benefits: [{
                  id: "benefit-1",
                  dedupe_key: "benefit-1",
                  title: "Lounge",
                  type: "access",
                  category: "travel",
                  value_config: { limit: 4, usage_period: "quarter" },
                  limit: 4,
                  period: "quarter",
                  eligibility: "see official terms",
                }],
              },
            }
            : source
        ),
      },
    },
    capturedOutput: {
      ...item.capturedOutput,
      benefits: [{
        benefit_id: "benefit-1",
        title: "Lounge",
        benefit_type: "access",
        benefit_category: "travel",
        value_config: { limit: 4, usage_period: "quarter" },
      }],
    },
  };
  const result = await executeEvalCase(benefitItem, "captured-production-v1", {
    generate: () => {
      throw new Error("must_not_call");
    },
  });
  assertEquals(result.executionStatus, "succeeded");
  assertEquals(result.output, {
    mode: "benefits",
    card_id: "card-1",
    benefits: [{
      id: "benefit-1",
      dedupe_key: "benefit-1",
      title: "Lounge",
      type: "access",
      category: "travel",
      value_config: { limit: 4, usage_period: "quarter" },
      limit: 4,
      period: "quarter",
      eligibility: "see official terms",
    }],
    sources: [{
      id: "source-benefit-1",
      field_paths: ["facts.benefits"],
    }],
  });
});

Deno.test("ambiguous or incomplete captured card baselines fail as insufficient fixtures", async () => {
  const item = fixture("card_data");
  const safe = item.inputFixture.safe_input_context as Record<string, unknown>;
  for (
    const candidate of [
      {
        ...item,
        inputFixture: {
          ...item.inputFixture,
          safe_input_context: { ...safe, evaluation_mode: undefined },
        },
      },
      {
        ...item,
        capturedOutput: {
          ...item.capturedOutput,
          catalog_card: { id: "card-1" },
        },
      },
    ]
  ) {
    const result = await executeEvalCase(candidate, "captured-production-v1", {
      generate: () => {
        throw new Error("must_not_call");
      },
    });
    assertEquals(result.executionStatus, "failed");
    assertEquals(result.safeFailureCategory, "insufficient_fixture");
  }
});

Deno.test("captured identity baseline rejects a second conflicting applicable source", async () => {
  const item = fixture("card_data");
  const safe = item.inputFixture.safe_input_context as Record<string, unknown>;
  const official = safe.official_sources as Record<string, unknown>[];
  const conflicting: EvalCaseFixture = {
    ...item,
    inputFixture: {
      ...item.inputFixture,
      safe_input_context: {
        ...safe,
        official_sources: [...official, {
          id: "source-conflict",
          url: "https://bank.example/conflict",
          snippet: "Conflicting identity",
          facts: {
            evaluation_mode: "catalog_identity_validation",
            provenance_claims: {
              issuer: "HDFC",
              card_name: "Legacy Regalia",
              network: "Visa",
              aliases: [],
            },
            catalog_reference: {
              id: "card-legacy",
              name: "Legacy Regalia",
              bank: "HDFC",
              network: "Visa",
              annual_fee: 2500,
              joining_fee: 2500,
            },
          },
        }],
      },
    },
  };
  const result = await executeEvalCase(conflicting, "captured-production-v1", {
    generate: () => {
      throw new Error("must_not_call");
    },
  });
  assertEquals(result.executionStatus, "failed");
  assertEquals(result.safeFailureCategory, "insufficient_fixture");
});

Deno.test("captured benefit baseline rejects an applicable source linked to another card", async () => {
  const item = fixture("card_data");
  const safe = item.inputFixture.safe_input_context as Record<string, unknown>;
  const official = safe.official_sources as Record<string, unknown>[];
  const benefit = [{
    id: "benefit-1",
    dedupe_key: "benefit-1",
    title: "Lounge",
    type: "access",
    category: "travel",
    value_config: { limit: 4 },
    limit: 4,
    period: null,
    eligibility: "see official terms",
  }];
  const supporting = official.map((source) =>
    source.id === "source-benefit-1"
      ? {
        ...source,
        facts: {
          evaluation_mode: "benefit_extraction",
          catalog_reference_id: "card-1",
          benefits: benefit,
        },
      }
      : source
  );
  const conflicting: EvalCaseFixture = {
    ...item,
    inputFixture: {
      ...item.inputFixture,
      safe_input_context: {
        ...safe,
        evaluation_mode: "benefit_extraction",
        official_sources: [...supporting, {
          id: "source-wrong-card",
          url: "https://bank.example/other-card-benefit",
          snippet: "Terms for another card",
          facts: {
            evaluation_mode: "benefit_extraction",
            catalog_reference_id: "card-2",
            benefits: benefit,
          },
        }],
      },
    },
    capturedOutput: {
      ...item.capturedOutput,
      benefits: [{
        benefit_id: "benefit-1",
        title: "Lounge",
        benefit_type: "access",
        benefit_category: "travel",
        value_config: { limit: 4 },
      }],
    },
  };
  const result = await executeEvalCase(conflicting, "captured-production-v1", {
    generate: () => {
      throw new Error("must_not_call");
    },
  });
  assertEquals(result.executionStatus, "failed");
  assertEquals(result.safeFailureCategory, "insufficient_fixture");
});

Deno.test("candidate receives only deeply sanitized fixture inside a fixed, delimited prompt", async () => {
  const item = fixture("card_data");
  const seen: unknown[] = [];
  await executeEvalCase(item, "gemini-3.6-flash-card-data-v1", {
    generate: async (input) => {
      seen.push(input);
      return fakeGeneration({
        mode: "identity",
        card: {
          id: "card-1",
          name: "Regalia Gold",
          bank: "HDFC",
          network: "Visa",
          annual_fee: 2500,
          joining_fee: 2500,
        },
        sources: [{
          id: "source-1",
          field_paths: [
            "facts.provenance_claims.card_name",
            "facts.catalog_reference.annual_fee",
          ],
        }],
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

Deno.test("candidate model data excludes captured statement labels and output", async () => {
  const item = fixture("statement_processing");
  let serialized = "";
  const result = await executeEvalCase(item, "gemini-3.6-flash-statement-v1", {
    generate: async (input) => {
      serialized = JSON.stringify(input);
      return fakeGeneration(item.capturedOutput);
    },
  });
  assertEquals(result.executionStatus, "succeeded");
  assertEquals(serialized.includes("shopping"), false);
  assertEquals(serialized.includes('"transaction_type":"debit"'), false);
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

Deno.test("historical under-specified fixtures fail safely before baseline or candidate execution", async () => {
  for (
    const key of ["captured-production-v1", "gemini-3.6-flash-statement-v1"]
  ) {
    const result = await executeEvalCase(
      {
        ...fixture("statement_processing"),
        inputFixture: { safe_input_context: {}, authoritative_context: {} },
      },
      key,
      {
        generate: () => {
          throw new Error("must_not_call");
        },
      },
    );
    assertEquals(result.safeFailureCategory, "insufficient_fixture");
  }
});

Deno.test("candidate output is exact, bounded, typed, and grounded", async () => {
  const bad = [
    {
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
    {
      mode: "identity",
      card: {
        id: "foreign",
        name: "X",
        bank: "Y",
        network: "Visa",
        annual_fee: 1,
        joining_fee: 1,
      },
      sources: [],
    },
    {
      selected_card_id: "foreign",
      selected_benefit_id: "benefit-1",
      savings: Number.NaN,
      final_amount: 600,
      explanation: "x".repeat(1001),
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

Deno.test("real captured-shape candidates succeed for every feature family", async () => {
  for (
    const [feature, key, output] of [
      [
        "statement_processing",
        "gemini-3.6-flash-statement-v1",
        fixture("statement_processing").capturedOutput,
      ],
      ["card_data", "gemini-3.6-flash-card-data-v1", {
        mode: "identity",
        card: {
          id: "card-1",
          name: "Regalia Gold",
          bank: "HDFC",
          network: "Visa",
          annual_fee: 2500,
          joining_fee: 2500,
        },
        sources: [{
          id: "source-1",
          field_paths: [
            "facts.provenance_claims.card_name",
            "facts.catalog_reference.annual_fee",
          ],
        }],
      }],
      [
        "recommendation",
        "gemini-3.6-flash-recommendation-v1",
        fixture("recommendation").capturedOutput,
      ],
    ] as const
  ) {
    const result = await executeEvalCase(fixture(feature), key, {
      generate: async () => fakeGeneration(output),
    });
    assertEquals(result.executionStatus, "succeeded");
  }
});

Deno.test("empty and foreign-id outputs never count as successful evidence", async () => {
  for (
    const [feature, key, output] of [
      ["statement_processing", "gemini-3.6-flash-statement-v1", {}],
      ["card_data", "gemini-3.6-flash-card-data-v1", {
        mode: "identity",
        card: {},
        sources: [],
      }],
      ["recommendation", "gemini-3.6-flash-recommendation-v1", {
        selected_card_id: "foreign",
        selected_benefit_id: "foreign",
        savings: 1,
        final_amount: 1,
        explanation: "unsupported",
      }],
    ] as const
  ) {
    const result = await executeEvalCase(fixture(feature), key, {
      generate: async () => fakeGeneration(output),
    });
    assertEquals(result.safeFailureCategory, "invalid_model_output");
  }
});

Deno.test("immutable transaction evidence, card paths and financial math are enforced deeply", async () => {
  const wrongTransaction = {
    ...fixture("statement_processing").capturedOutput,
    amount: 999,
  };
  const badPath = {
    mode: "identity",
    card: {
      id: "card-1",
      name: "Regalia Gold",
      bank: "HDFC",
      network: "Visa",
      annual_fee: 2500,
      joining_fee: 2500,
    },
    sources: [{ id: "source-1", field_paths: ["facts.missing"] }],
  };
  const wrongMath = {
    ...fixture("recommendation").capturedOutput,
    savings: 199,
    final_amount: 601,
  };
  for (
    const [feature, key, output] of [
      [
        "statement_processing",
        "gemini-3.6-flash-statement-v1",
        wrongTransaction,
      ],
      ["card_data", "gemini-3.6-flash-card-data-v1", badPath],
      ["recommendation", "gemini-3.6-flash-recommendation-v1", wrongMath],
    ] as const
  ) {
    const result = await executeEvalCase(fixture(feature), key, {
      generate: async () => fakeGeneration(output),
    });
    assertEquals(result.safeFailureCategory, "invalid_model_output");
  }
});

Deno.test("grounded benefit extraction accepts the exact official benefit only", async () => {
  const base = fixture("card_data");
  const safe = base.inputFixture.safe_input_context as Record<string, unknown>;
  const benefitFixture: EvalCaseFixture = {
    ...base,
    inputFixture: {
      ...base.inputFixture,
      safe_input_context: { ...safe, evaluation_mode: "benefit_extraction" },
    },
  };
  const benefit = {
    id: "benefit-1",
    dedupe_key: "lounge",
    title: "Lounge",
    type: "access",
    category: "travel",
    value_config: { limit: 4 },
    limit: 4,
    period: "quarter",
    eligibility: "primary cardholder",
  };
  const valid = {
    mode: "benefits",
    card_id: "card-1",
    benefits: [benefit],
    sources: [{ id: "source-benefit-1", field_paths: ["facts.benefits"] }],
  };
  assertEquals(
    (await executeEvalCase(
      benefitFixture,
      "gemini-3.6-flash-card-data-v1",
      { generate: async () => fakeGeneration(valid) },
    )).executionStatus,
    "succeeded",
  );
  const hallucinated = { ...valid, benefits: [{ ...benefit, limit: 8 }] };
  assertEquals(
    (await executeEvalCase(
      benefitFixture,
      "gemini-3.6-flash-card-data-v1",
      { generate: async () => fakeGeneration(hallucinated) },
    )).safeFailureCategory,
    "invalid_model_output",
  );
});

Deno.test("Movie Deals arithmetic covers percent, fixed thresholds/caps and BOGO odd/even", async () => {
  const cases = [
    [{ discount_percent: 10, max_discount_per_transaction: 50 }, 50, 750],
    [{ discount_amount: 150, min_transaction: 900 }, null, null],
    [
      { discount_amount: 150, min_transaction: 700, monthly_cap: 100 },
      100,
      700,
    ],
    [
      {
        discount_type: "bogo",
        max_discount_per_transaction: 300,
        max_usage_per_month: 2,
      },
      300,
      500,
    ],
  ] as const;
  for (const [config, savings, finalAmount] of cases) {
    const item = fixture("recommendation");
    const authoritative = item.inputFixture.authoritative_context as Record<
      string,
      unknown
    >;
    const customized = {
      ...item,
      inputFixture: {
        ...item.inputFixture,
        authoritative_context: {
          ...authoritative,
          benefits: [{ benefit_id: "benefit-1", value_config: config }],
        },
      },
    };
    let calls = 0;
    const result = await executeEvalCase(
      customized,
      "gemini-3.6-flash-recommendation-v1",
      {
        generate: async () => {
          calls++;
          return fakeGeneration({
            selected_card_id: "card-1",
            selected_benefit_id: "benefit-1",
            savings,
            final_amount: finalAmount,
            explanation: "Grounded arithmetic.",
          });
        },
      },
    );
    assertEquals(
      result.executionStatus,
      savings === null ? "failed" : "succeeded",
    );
    if (savings === null) {
      assertEquals(result.safeFailureCategory, "insufficient_fixture");
    }
  }
  const even = fixture("recommendation");
  const evenAuth = even.inputFixture.authoritative_context as Record<
    string,
    unknown
  >;
  const evenItem = {
    ...even,
    inputFixture: {
      safe_input_context: {
        number_of_tickets: 4,
        price_per_ticket: 400,
        task: "explain_fixed_selection",
      },
      authoritative_context: {
        ...evenAuth,
        benefits: [{
          benefit_id: "benefit-1",
          value_config: {
            discount_type: "bogo",
            max_discount_per_transaction: 300,
            max_usage_per_month: 2,
          },
        }],
      },
    },
  };
  const evenResult = await executeEvalCase(
    evenItem,
    "gemini-3.6-flash-recommendation-v1",
    {
      generate: async () =>
        fakeGeneration({
          selected_card_id: "card-1",
          selected_benefit_id: "benefit-1",
          savings: 600,
          final_amount: 1000,
          explanation: "Two free tickets.",
        }),
    },
  );
  assertEquals(evenResult.executionStatus, "succeeded");
});

Deno.test("platform mismatch changes confidence and cinema remains informational like production", async () => {
  for (
    const [safePatch, benefitPatch] of [[{ preferred_platform: "pvr" }, {
      partners: ["bookmyshow"],
    }], [{ preferred_cinema: "imax" }, {
      value_config: { discount_percent: 25, eligible_cinemas: ["inox"] },
    }]] as const
  ) {
    const item = fixture("recommendation");
    const safe = item.inputFixture.safe_input_context as Record<
        string,
        unknown
      >,
      auth = item.inputFixture.authoritative_context as Record<string, unknown>;
    const benefit = (auth.benefits as Record<string, unknown>[])[0];
    const customized = {
      ...item,
      inputFixture: {
        safe_input_context: { ...safe, ...safePatch },
        authoritative_context: {
          ...auth,
          benefits: [{ ...benefit, ...benefitPatch }],
        },
      },
    };
    const result = await executeEvalCase(
      customized,
      "gemini-3.6-flash-recommendation-v1",
      { generate: async () => fakeGeneration(item.capturedOutput) },
    );
    assertEquals(result.executionStatus, "succeeded");
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
