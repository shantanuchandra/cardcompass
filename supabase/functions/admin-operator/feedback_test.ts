import { assertEquals, assertRejects } from "@std/assert";
import {
  handleEvalCaseAction,
  handleFeedbackReview,
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
        expected_output: {},
        scoring_rubric: {},
        severe_failure_conditions: {},
      }, rpcContext([])),
    AdminHttpError,
    "invalid_request",
  );
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
