import type {
  GeminiGenerationResult,
  GeminiInput,
} from "../_shared/gemini_generate.ts";

export type EvalFeatureKey =
  | "statement_processing"
  | "card_data"
  | "recommendation";
export type EvalConfigKey =
  | "captured-production-v1"
  | "gemini-3.6-flash-statement-v1"
  | "gemini-3.6-flash-card-data-v1"
  | "gemini-3.6-flash-recommendation-v1";
export type JudgeConfigKey = "gemini-3.6-flash-blind-judge-v1";

export type EvalCaseFixture = Readonly<{
  caseId: string;
  revision: number;
  featureKey: EvalFeatureKey;
  inputFixture: Record<string, unknown>;
  capturedOutput: Record<string, unknown>;
  expectedOutput?: Record<string, unknown>;
  operatorFeedback?: string;
  scoringRubric?: Record<string, unknown>;
  severeFailureConditions?: Record<string, unknown>;
}>;

export type EvalExecutionResult = Readonly<{
  executionStatus: "succeeded" | "failed";
  output: Record<string, unknown>;
  safeFailureCategory?: "invalid_model_output" | "model_unavailable";
  model: string | null;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  estimatedCostUsd: number;
}>;

export type EvalGenerate = (
  input: GeminiInput,
) => Promise<GeminiGenerationResult>;
