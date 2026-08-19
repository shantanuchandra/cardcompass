import { assertEquals, assertRejects } from "@std/assert";
import {
  handleEvalCaseAction,
  handleFeedbackDetail,
  handleFeedbackReview,
  handleFeedbackTriageRetry,
  parseFeedbackListRequest,
} from "./feedback.ts";
import { type AdminActionContext, AdminHttpError } from "./types.ts";

const actor = { id: "10000000-0000-4000-8000-000000000001" };
const id = "20000000-0000-4000-8000-000000000001";

function rpcContext(
  calls: Array<[string, Record<string, unknown> | undefined]>,
  result: unknown = {},
) {
  return {
    actor,
    requestId: "30000000-0000-4000-8000-000000000001",
    db: {
      from: () => {
        const query: any = {
          select: () => query,
          eq: () => query,
          range: () =>
            Promise.resolve({
              data: [{ id, updated_at: "2026-08-19T12:00:00Z" }],
              error: null,
            }),
        };
        return query;
      },
      rpc: (name: string, args?: Record<string, unknown>) => {
        calls.push([name, args]);
        return Promise.resolve({ data: result, error: null });
      },
    },
  } as unknown as AdminActionContext;
}

Deno.test("feedback list parser accepts only bounded exact filters", async () => {
  assertEquals(
    parseFeedbackListRequest({
      action: "feedback-list",
      page: 2,
      limit: 25,
      feature: "card_data",
      review_status: "pending",
      severity: "high",
      model_version: "gemini-3.6-flash",
    }),
    {
      page: 2,
      limit: 25,
      feature: "card_data",
      reviewStatus: "pending",
      severity: "high",
      modelVersion: "gemini-3.6-flash",
    },
  );
  for (
    const body of [
      { action: "feedback-list", limit: 101 },
      { action: "feedback-list", page: 0 },
      { action: "feedback-list", surprise: true },
      { action: "feedback-list", severity: "urgent" },
    ]
  ) {
    await assertRejects(
      async () => parseFeedbackListRequest(body),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("draft review sends only complete operator-authored ground truth", async () => {
  const calls: Array<[string, Record<string, unknown> | undefined]> = [];
  const output = await handleFeedbackReview(
    {
      action: "feedback-review",
      request_id: "30000000-0000-4000-8000-000000000001",
      feedback_id: id,
      review_action: "create_eval_draft",
      operator_feedback: "Expected the grocery category",
      ground_truth_confirmed: true,
      expected_output: { category: "Groceries" },
      scoring_rubric: { exact: true },
      severe_failure_conditions: { wrong_amount: true },
    },
    rpcContext(calls, {
      feedback_id: id,
      review_status: "eval_created",
      case_id: id,
      revision: 1,
    }),
  );
  assertEquals(output, {
    feedback_id: id,
    review_status: "eval_created",
    case_id: id,
    revision: 1,
    updated_at: "2026-08-19T12:00:00Z",
  });
  assertEquals(calls[0][0], "admin_review_ai_feedback");
  await assertRejects(
    () =>
      handleFeedbackReview({
        action: "feedback-review",
        request_id: "30000000-0000-4000-8000-000000000001",
        feedback_id: id,
        review_action: "create_eval_draft",
        operator_feedback: "",
        ground_truth_confirmed: true,
        expected_output: {},
        scoring_rubric: {},
        severe_failure_conditions: {},
      }, rpcContext([])),
    AdminHttpError,
    "invalid_request",
  );
  for (
    const invalid of [
      {
        expected_output: {},
        scoring_rubric: { exact: true },
        severe_failure_conditions: { wrong: true },
        ground_truth_confirmed: true,
      },
      {
        expected_output: { category: "Groceries" },
        scoring_rubric: {},
        severe_failure_conditions: { wrong: true },
        ground_truth_confirmed: true,
      },
      {
        expected_output: { category: "Groceries" },
        scoring_rubric: { exact: true },
        severe_failure_conditions: {},
        ground_truth_confirmed: true,
      },
      {
        expected_output: { category: "Groceries" },
        scoring_rubric: { exact: true },
        severe_failure_conditions: { wrong: true },
        ground_truth_confirmed: false,
      },
    ]
  ) {
    await assertRejects(
      () =>
        handleFeedbackReview({
          action: "feedback-review",
          request_id: "30000000-0000-4000-8000-000000000001",
          feedback_id: id,
          review_action: "create_eval_draft",
          operator_feedback: "Human authored behavior",
          ...invalid,
        }, rpcContext([])),
      AdminHttpError,
      "invalid_request",
    );
  }
});

Deno.test("routing decisions require operator reasons", async () => {
  for (const action of ["data_issue", "product_defect", "dismiss"]) {
    await assertRejects(
      () =>
        handleFeedbackReview({
          action: "feedback-review",
          request_id: "30000000-0000-4000-8000-000000000001",
          feedback_id: id,
          review_action: action,
          reason: " ",
        }, rpcContext([])),
      AdminHttpError,
      "reason_required",
    );
  }
});

Deno.test("eval approval requires typed confirmation and observed version", async () => {
  await assertRejects(
    () =>
      handleEvalCaseAction({
        action: "eval-case-action",
        request_id: "30000000-0000-4000-8000-000000000001",
        case_id: id,
        case_action: "approve",
        observed_updated_at: "2026-08-19T12:00:00Z",
        confirmation: "APPROV",
      }, rpcContext([])),
    AdminHttpError,
    "invalid_request",
  );
  const calls: Array<[string, Record<string, unknown> | undefined]> = [];
  await handleEvalCaseAction(
    {
      action: "eval-case-action",
      request_id: "30000000-0000-4000-8000-000000000001",
      case_id: id,
      case_action: "approve",
      observed_updated_at: "2026-08-19T12:00:00Z",
      confirmation: "APPROVE",
    },
    rpcContext(calls, {
      case_id: id,
      status: "approved",
      dataset_version: 7,
      updated_at: "2026-08-19T12:01:00Z",
    }),
  );
  assertEquals(calls[0][0], "admin_ai_eval_case_action");
});

Deno.test("feedback detail audits before reading feedback or eval cases", async () => {
  const events: string[] = [];
  const context = {
    actor,
    requestId: "30000000-0000-4000-8000-000000000001",
    db: {
      rpc: (name: string) => {
        events.push(`rpc:${name}`);
        return Promise.resolve({ data: {}, error: null });
      },
      from: (table: string) => {
        events.push(`from:${table}`);
        const query: any = {
          select: () => query,
          eq: () => query,
          order: () => query,
          range: () =>
            Promise.resolve({
              data: table === "ai_feedback"
                ? [{
                  id,
                  feature_key: "card_data",
                  feedback_text: "The annual fee shown is wrong",
                  safe_input_context: {},
                  output_snapshot: {},
                  authoritative_context: {},
                  triage_result: {},
                }]
                : [],
              error: null,
            }),
        };
        return query;
      },
    },
  } as unknown as AdminActionContext;

  await handleFeedbackDetail({
    action: "feedback-detail",
    feedback_id: id,
    request_id: "30000000-0000-4000-8000-000000000001",
  }, context);

  assertEquals(events, [
    "rpc:record_admin_read",
    "from:ai_feedback",
    "from:ai_eval_cases",
  ]);
});

Deno.test({
  name:
    "admin retry audits, resets, claims, and records safe unavailable-model failure",
  ignore: (await Deno.permissions.query({ name: "env" })).state !== "granted",
  fn: async () => {
    const events: string[] = [];
    let background: Promise<unknown> | undefined;
    const originalRuntime = (globalThis as any).EdgeRuntime;
    (globalThis as any).EdgeRuntime = {
      waitUntil: (task: Promise<unknown>) => background = task,
    };
    const context = {
      actor,
      requestId: "30000000-0000-4000-8000-000000000001",
      db: {
        rpc: (name: string, args?: Record<string, unknown>) => {
          events.push(`rpc:${name}`);
          if (name === "claim_ai_feedback_triage") {
            return Promise.resolve({
              data: {
                id,
                claim_token: "40000000-0000-4000-8000-000000000001",
                feature_key: "card_data",
                feedback_text: "The annual fee shown is wrong",
                safe_input_context: {},
                output_snapshot: {},
                authoritative_context: {},
              },
              error: null,
            });
          }
          if (name === "complete_ai_feedback_triage") {
            assertEquals(args?._succeeded, false);
            assertEquals(args?._failure_category, "model_unavailable");
          }
          return Promise.resolve({ data: {}, error: null });
        },
        from: (table: string) => {
          events.push(`from:${table}`);
          const query: any = {
            select: () => query,
            update: () => {
              events.push("update:awaiting_triage");
              return query;
            },
            eq: () => query,
            range: () =>
              Promise.resolve({
                data: [{ id, triage_status: "triage_failed" }],
                error: null,
              }),
          };
          return query;
        },
      },
    } as unknown as AdminActionContext;
    try {
      assertEquals(
        await handleFeedbackTriageRetry({
          action: "feedback-triage-retry",
          feedback_id: id,
          request_id: "30000000-0000-4000-8000-000000000001",
        }, context),
        { feedback_id: id, triage_status: "awaiting_triage" },
      );
      await background;
    } finally {
      (globalThis as any).EdgeRuntime = originalRuntime;
    }

    assertEquals(events, [
      "from:ai_feedback",
      "rpc:record_admin_read",
      "from:ai_feedback",
      "update:awaiting_triage",
      "rpc:claim_ai_feedback_triage",
      "rpc:complete_ai_feedback_triage",
    ]);
  },
});
