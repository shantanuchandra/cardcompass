import type { EvalConfigKey, EvalFeatureKey, JudgeConfigKey } from "./types.ts";

export type EvalConfig = Readonly<{
  key: EvalConfigKey;
  featureKey: EvalFeatureKey | "all";
  provider: "captured" | "gemini";
  model: string;
  promptVersion: string;
  taskScope: string;
  maxInputTokens: number;
  maxOutputTokens: number;
  estimatedMaximumCostUsd: number;
}>;

const configs: Readonly<Record<EvalConfigKey, EvalConfig>> = Object.freeze({
  "captured-production-v1": Object.freeze({
    key: "captured-production-v1",
    featureKey: "all",
    provider: "captured",
    model: "captured-production",
    promptVersion: "captured-production-v1",
    taskScope: "captured_production_output",
    maxInputTokens: 0,
    maxOutputTokens: 0,
    estimatedMaximumCostUsd: 0,
  }),
  "gemini-3.6-flash-statement-v1": Object.freeze({
    key: "gemini-3.6-flash-statement-v1",
    featureKey: "statement_processing",
    provider: "gemini",
    model: "gemini-3.6-flash",
    promptVersion: "statement-v1",
    taskScope: "statement_field_extraction_and_classification",
    maxInputTokens: 8192,
    maxOutputTokens: 4096,
    estimatedMaximumCostUsd: 0.01,
  }),
  "gemini-3.6-flash-card-data-v1": Object.freeze({
    key: "gemini-3.6-flash-card-data-v1",
    featureKey: "card_data",
    provider: "gemini",
    model: "gemini-3.6-flash",
    promptVersion: "card-data-v1",
    taskScope: "card_catalog_identity_validation_and_benefit_extraction",
    maxInputTokens: 8192,
    maxOutputTokens: 4096,
    estimatedMaximumCostUsd: 0.02,
  }),
  "gemini-3.6-flash-recommendation-v1": Object.freeze({
    key: "gemini-3.6-flash-recommendation-v1",
    featureKey: "recommendation",
    provider: "gemini",
    model: "gemini-3.6-flash",
    promptVersion: "recommendation-v1",
    taskScope: "fixed_selection_explanation_and_arithmetic",
    maxInputTokens: 8192,
    maxOutputTokens: 4096,
    estimatedMaximumCostUsd: 0.03,
  }),
});

const judge = Object.freeze({
  key: "gemini-3.6-flash-blind-judge-v1" as const,
  featureKey: "recommendation" as const,
  provider: "gemini" as const,
  model: "gemini-3.6-flash",
  promptVersion: "blind-judge-v1",
  taskScope: "blind_output_comparison",
  maxInputTokens: 8192,
  maxOutputTokens: 1024,
  estimatedMaximumCostUsd: 0.01,
});

export function getEvalConfig(key: string): EvalConfig {
  if (!Object.hasOwn(configs, key)) throw new Error("invalid_request");
  return configs[key as EvalConfigKey];
}
export function getCandidateConfig(key: string): EvalConfig {
  const config = getEvalConfig(key);
  if (config.provider !== "gemini") throw new Error("invalid_request");
  return config;
}
export function getJudgeConfig(key: string): typeof judge {
  if (key !== judge.key) throw new Error("invalid_request");
  return judge;
}

export const candidateCostPolicy = Object.freeze({
  "gemini-3.6-flash-statement-v1": 0.01,
  "gemini-3.6-flash-card-data-v1": 0.02,
  "gemini-3.6-flash-recommendation-v1": 0.03,
});

export function assertRegistryMatchesDatabasePolicy(
  policy: Record<string, number>,
): void {
  const expected = Object.entries(candidateCostPolicy).sort();
  const actual = Object.entries(policy).sort();
  if (JSON.stringify(expected) !== JSON.stringify(actual)) {
    throw new Error("config_policy_mismatch");
  }
}
