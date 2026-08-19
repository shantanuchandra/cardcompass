import { createClient } from "@supabase/supabase-js";
import {
  configuredGeminiKeys,
  generateGemini,
} from "../_shared/gemini_generate.ts";
import { executeEvalCase } from "./executors.ts";
import {
  scoreRecommendationCase,
  type ScoreResult,
  scoreStructuredCase,
} from "./scorers.ts";
import type {
  EvalCaseFixture,
  EvalExecutionResult,
  EvalGenerate,
} from "./types.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };

type RunState = Readonly<{ status: string; leaseToken: string | null }>;
export type RunnerDependencies = {
  serviceRoleSecret: string;
  rpc: (name: string, args: Record<string, unknown>) => Promise<unknown>;
  loadCase: (caseId: string, revision: number) => Promise<EvalCaseFixture>;
  readRunState: (runId: string) => Promise<RunState>;
  generate: EvalGenerate;
  scheduleContinuation: (runId: string) => Promise<void>;
  waitUntil: (promise: Promise<unknown>) => void;
};

type Claim = Readonly<{
  runId: string;
  leaseToken: string;
  cases: readonly Readonly<
    {
      caseId: string;
      revision: number;
      featureKey: EvalCaseFixture["featureKey"];
    }
  >[];
  baselineConfigKey: string;
  candidateConfigKey: string;
  judgeConfigKey: string;
}>;

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const safeHeaders = {
  "content-type": "application/json",
  "cache-control": "no-store",
};
const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: safeHeaders });

function authorized(request: Request, expected: string): Promise<boolean> {
  const header = request.headers.get("authorization") ?? "";
  const supplied = header.startsWith("Bearer ") ? header.slice(7) : "";
  return constantTimeEqual(supplied, expected);
}

async function constantTimeEqual(
  left: string,
  right: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const aa = new Uint8Array(a), bb = new Uint8Array(b);
  let difference = left.length ^ right.length;
  for (let index = 0; index < aa.length; index++) {
    difference |= aa[index] ^ bb[index];
  }
  return right.length >= 24 && difference === 0;
}

function parseBody(value: unknown): { runId: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_request");
  }
  const record = value as Record<string, unknown>;
  if (
    Object.keys(record).length !== 1 || typeof record.run_id !== "string" ||
    !uuid.test(record.run_id)
  ) throw new Error("invalid_request");
  return { runId: record.run_id };
}

function parseClaim(value: unknown): Claim | null | "cost_stop" {
  if (value === null) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("persistence_failed");
  }
  const claim = value as Record<string, unknown>;
  if (
    claim.safe_failure_category === "cost_ceiling_reached" &&
    Array.isArray(claim.cases) && claim.cases.length === 0
  ) return "cost_stop";
  if (
    typeof claim.run_id !== "string" || typeof claim.lease_token !== "string" ||
    !Array.isArray(claim.cases) || claim.cases.length > 5 ||
    typeof claim.baseline_config_key !== "string" ||
    typeof claim.candidate_config_key !== "string" ||
    typeof claim.judge_config_key !== "string"
  ) throw new Error("persistence_failed");
  return {
    runId: claim.run_id,
    leaseToken: claim.lease_token,
    cases: claim.cases.map((entry) => {
      if (!entry || typeof entry !== "object") {
        throw new Error("persistence_failed");
      }
      const item = entry as Record<string, unknown>;
      if (
        typeof item.case_id !== "string" || !Number.isInteger(item.revision) ||
        !["statement_processing", "card_data", "recommendation"].includes(
          String(item.feature_key),
        )
      ) throw new Error("persistence_failed");
      return {
        caseId: item.case_id,
        revision: item.revision as number,
        featureKey: item.feature_key as EvalCaseFixture["featureKey"],
      };
    }),
    baselineConfigKey: claim.baseline_config_key,
    candidateConfigKey: claim.candidate_config_key,
    judgeConfigKey: claim.judge_config_key,
  };
}

export async function handleAiEvalRunnerRequest(
  request: Request,
  provided?: RunnerDependencies,
): Promise<Response> {
  const deps = provided ?? defaultDependencies(request);
  // This check intentionally precedes method handling, body reads, and every DB operation.
  if (!(await authorized(request, deps.serviceRoleSecret))) {
    return json({ error: "authentication_required" }, 401);
  }
  if (request.method !== "POST") return json({ error: "invalid_request" }, 405);
  let runId: string;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > 1024) {
      throw new Error("invalid_request");
    }
    runId = parseBody(JSON.parse(raw)).runId;
  } catch {
    return json({ error: "invalid_request" }, 400);
  }

  try {
    const parsed = parseClaim(
      await deps.rpc("claim_ai_eval_run_batch", {
        _run_id: runId,
        _batch_limit: 5,
      }),
    );
    if (parsed === "cost_stop") {
      return json({
        run_id: runId,
        status: "completed_with_failures",
        processed: 0,
        safe_failure_category: "cost_ceiling_reached",
      });
    }
    if (!parsed) {
      return json({ run_id: runId, status: "not_claimed", processed: 0 }, 202);
    }
    if (parsed.runId !== runId) throw new Error("persistence_failed");
    let processed = 0;
    for (const manifest of parsed.cases) {
      const state = await deps.readRunState(runId);
      if (
        state.status !== "running" || state.leaseToken !== parsed.leaseToken
      ) {
        return json({
          run_id: runId,
          status: state.status === "cancelled" ? "cancelled" : "state_conflict",
          processed,
        }, state.status === "cancelled" ? 202 : 409);
      }
      const fixture = await deps.loadCase(manifest.caseId, manifest.revision);
      if (
        fixture.caseId !== manifest.caseId ||
        fixture.revision !== manifest.revision ||
        fixture.featureKey !== manifest.featureKey
      ) throw new Error("persistence_failed");
      let baseline: EvalExecutionResult = safeFailedExecution();
      let candidate: EvalExecutionResult = safeFailedExecution();
      let score: ScoreResult = safeFailedScore();
      let processingFailure = false;
      let judgeInputTokens = 0,
        judgeOutputTokens = 0,
        judgeLatencyMs = 0,
        judgeCost = 0;
      try {
        baseline = await executeEvalCase(fixture, parsed.baselineConfigKey, {
          generate: deps.generate,
        });
        candidate = await executeEvalCase(fixture, parsed.candidateConfigKey, {
          generate: deps.generate,
        });
        const meteredJudge: EvalGenerate = async (input) => {
          const result = await deps.generate(input);
          judgeInputTokens += result.inputTokens;
          judgeOutputTokens += result.outputTokens;
          judgeLatencyMs += result.latencyMs;
          judgeCost += Math.min(
            0.01,
            0.01 * (result.inputTokens + result.outputTokens) / 9216,
          );
          return result;
        };
        score = fixture.featureKey === "recommendation"
          ? await scoreRecommendationCase(
            fixture,
            baseline,
            candidate,
            meteredJudge,
            { runId, judgeConfigKey: parsed.judgeConfigKey },
          )
          : scoreStructuredCase(fixture, baseline, candidate);
      } catch {
        processingFailure = true;
      }
      const executionStatus = baseline.executionStatus === "succeeded" &&
          candidate.executionStatus === "succeeded"
        ? "succeeded"
        : "failed";
      const safeFailureCategory = processingFailure
        ? "provider_failed"
        : candidate.safeFailureCategory ?? baseline.safeFailureCategory;
      await deps.rpc("record_ai_eval_result", {
        _run_id: runId,
        _lease_token: parsed.leaseToken,
        _case_id: fixture.caseId,
        _case_revision: fixture.revision,
        _result: {
          feature_key: fixture.featureKey,
          baseline_output: baseline.output,
          candidate_output: candidate.output,
          deterministic_assertions: score.assertions,
          judge_verdict: score.judge ?? {},
          regression: score.regression,
          severe_regression: score.severeRegression,
          baseline_latency_ms: baseline.latencyMs,
          candidate_latency_ms: candidate.latencyMs + judgeLatencyMs,
          baseline_input_tokens: baseline.inputTokens,
          baseline_output_tokens: baseline.outputTokens,
          candidate_input_tokens: candidate.inputTokens + judgeInputTokens,
          candidate_output_tokens: candidate.outputTokens + judgeOutputTokens,
          estimated_cost_usd: baseline.estimatedCostUsd +
            candidate.estimatedCostUsd + judgeCost,
          execution_status: processingFailure ? "failed" : executionStatus,
          ...(safeFailureCategory
            ? { safe_failure_category: safeFailureCategory }
            : {}),
        },
      });
      processed++;
    }
    if (parsed.cases.length === 5) {
      await deps.rpc("yield_ai_eval_run", {
        _run_id: runId,
        _lease_token: parsed.leaseToken,
      });
      let continuationAccepted = false;
      try {
        const continuation = Promise.resolve().then(() =>
          deps.scheduleContinuation(runId)
        ).catch(() => undefined);
        deps.waitUntil(continuation);
        continuationAccepted = true;
      } catch {
        // The lease has already been yielded, so a later invocation can resume safely.
      }
      return json({
        run_id: runId,
        status: "running",
        processed,
        continuation_scheduled: continuationAccepted,
      }, 202);
    }
    const finished = await deps.rpc("finish_ai_eval_run", {
      _run_id: runId,
      _lease_token: parsed.leaseToken,
    }) as Record<string, unknown>;
    return json({
      run_id: runId,
      status: typeof finished?.status === "string"
        ? finished.status
        : "completed",
      processed,
    });
  } catch (error) {
    const code = error instanceof Error &&
        ["state_conflict", "cost_ceiling_reached"].includes(error.message)
      ? error.message
      : "persistence_failed";
    return json(
      { error: code },
      code === "state_conflict"
        ? 409
        : code === "cost_ceiling_reached"
        ? 202
        : 503,
    );
  }
}

function safeFailedExecution(): EvalExecutionResult {
  return {
    executionStatus: "failed",
    output: {},
    model: null,
    inputTokens: 0,
    outputTokens: 0,
    latencyMs: 0,
    estimatedCostUsd: 0,
  };
}

function safeFailedScore(): ScoreResult {
  return {
    passed: false,
    regression: false,
    severeRegression: false,
    requiresReview: true,
    assertions: [],
    judge: null,
  };
}

function defaultDependencies(request: Request): RunnerDependencies {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const db: any = createClient(url, serviceRoleSecret);
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await db.rpc(name, args);
    if (error) {
      throw new Error(
        error.message?.includes("state_conflict")
          ? "state_conflict"
          : error.message?.includes("cost_ceiling_reached")
          ? "cost_ceiling_reached"
          : "persistence_failed",
      );
    }
    return data;
  };
  return {
    serviceRoleSecret,
    rpc,
    loadCase: async (caseId, revision) => {
      const { data, error } = await db.from("ai_eval_cases").select(
        "id,revision,feature_key,input_fixture,captured_output,expected_output,operator_feedback,scoring_rubric,severe_failure_conditions",
      ).eq("id", caseId).eq("revision", revision).single();
      if (error || !data) throw new Error("persistence_failed");
      return {
        caseId: data.id,
        revision: data.revision,
        featureKey: data.feature_key,
        inputFixture: data.input_fixture,
        capturedOutput: data.captured_output,
        expectedOutput: data.expected_output,
        operatorFeedback: data.operator_feedback,
        scoringRubric: data.scoring_rubric,
        severeFailureConditions: data.severe_failure_conditions,
      };
    },
    readRunState: async (id) => {
      const { data, error } = await db.from("ai_eval_runs").select(
        "status,lease_token",
      ).eq("id", id).single();
      if (error || !data) throw new Error("persistence_failed");
      return { status: data.status, leaseToken: data.lease_token };
    },
    generate: (input) =>
      generateGemini(input, { apiKeys: configuredGeminiKeys(), fetch }),
    scheduleContinuation: async (id) => {
      const response = await fetch(`${url}/functions/v1/ai-eval-runner`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${serviceRoleSecret}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ run_id: id }),
      });
      if (!response.ok) throw new Error("schedule_failed");
    },
    waitUntil: (promise) => EdgeRuntime.waitUntil(promise),
  };
}

if (import.meta.main) {
  Deno.serve((request) => handleAiEvalRunnerRequest(request));
}
