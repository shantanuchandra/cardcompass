import { assertEquals } from "jsr:@std/assert";
import { handleFeedbackRequest } from "./index.ts";
import { parseFeedbackBody } from "./validation.ts";

Deno.test("strict validation enforces action, compatibility, UUID and bounded text", () => {
  assertEquals(
    parseFeedbackBody({
      action: "feedback-submit",
      feature_key: "statement_processing",
      output_ref_type: "transaction",
      output_ref_id: "10000000-0000-4000-8000-000000000001",
      feedback_text: "Wrong merchant category",
      request_id: "20000000-0000-4000-8000-000000000001",
    }).action,
    "feedback-submit",
  );
  const card = parseFeedbackBody({
    action: "feedback-submit",
    feature_key: "card_data",
    output_ref_type: "user_card",
    output_ref_id: "10000000-0000-4000-8000-000000000001",
    evaluation_mode: "benefit_extraction",
    feedback_text: "The captured benefit is incomplete",
    request_id: "20000000-0000-4000-8000-000000000001",
  });
  assertEquals(
    card.action === "feedback-submit" && card.evaluation_mode,
    "benefit_extraction",
  );
  for (
    const body of [
      { action: "constructor" },
      {
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "transaction",
        output_ref_id: "x",
        feedback_text: "long enough text",
        request_id: "bad",
      },
      {
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        evaluation_mode: "catalog_identity_validation",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "short",
        request_id: "20000000-0000-4000-8000-000000000001",
      },
      {
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        evaluation_mode: "catalog_identity_validation",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "long enough text",
        request_id: "20000000-0000-4000-8000-000000000001",
        extra: true,
      },
      {
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        evaluation_mode: "ranking",
        feedback_text: "long enough text",
        request_id: "20000000-0000-4000-8000-000000000001",
      },
    ]
  ) {
    try {
      parseFeedbackBody(body);
      throw new Error("accepted");
    } catch (e) {
      assertEquals((e as Error).message, "invalid_request");
    }
  }
});

Deno.test("recommendation traces accept only the closed Movie Deals fixture", () => {
  const valid = {
    action: "trace-create",
    feature_key: "recommendation",
    safe_input_context: { number_of_tickets: 2, price_per_ticket: 450 },
    output_snapshot: {
      selected_card_id: "10000000-0000-4000-8000-000000000001",
      selected_benefit_id: "20000000-0000-4000-8000-000000000001",
      savings: 300,
      final_amount: 600,
      explanation: "Save on two tickets.",
    },
    card_ids: ["10000000-0000-4000-8000-000000000001"],
    benefit_ids: ["20000000-0000-4000-8000-000000000001"],
    request_id: "30000000-0000-4000-8000-000000000001",
  };
  assertEquals(parseFeedbackBody(valid).action, "trace-create");
  for (
    const poison of [
      { ...valid, engine_version: "spoofed" },
      {
        ...valid,
        safe_input_context: {
          ...valid.safe_input_context,
          raw_email: "secret",
        },
      },
      { ...valid, output_snapshot: { ...valid.output_snapshot, history: [] } },
      {
        ...valid,
        safe_input_context: {
          ...valid.safe_input_context,
          nested: { access_token: "secret" },
        },
      },
    ]
  ) {
    try {
      parseFeedbackBody(poison);
      throw new Error("accepted");
    } catch (error) {
      assertEquals((error as Error).message, "invalid_request");
    }
  }
});

Deno.test("endpoint authenticates and checks active profile before service work", async () => {
  let serviceCalls = 0;
  const response = await handleFeedbackRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer valid" },
      body: JSON.stringify({
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        evaluation_mode: "catalog_identity_validation",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "This is the wrong card",
        request_id: "20000000-0000-4000-8000-000000000001",
      }),
    }),
    {
      authenticate: async () => ({
        id: "30000000-0000-4000-8000-000000000001",
      }),
      requireActive: async () => {
        throw Object.assign(new Error("account_inactive"), { status: 403 });
      },
      resolveContext: async () => {
        serviceCalls++;
        return {} as never;
      },
      rpc: async () => {
        serviceCalls++;
        return {} as never;
      },
      waitUntil: () => {
        serviceCalls++;
      },
    },
  );
  assertEquals(response.status, 403);
  assertEquals(serviceCalls, 0);
});

Deno.test("accepted feedback returns before injected background triage", async () => {
  let background: Promise<unknown> | undefined;
  let submitted: Record<string, unknown> | undefined;
  const response = await handleFeedbackRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer valid" },
      body: JSON.stringify({
        action: "feedback-submit",
        feature_key: "statement_processing",
        output_ref_type: "transaction",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "This category should be grocery",
        request_id: "20000000-0000-4000-8000-000000000001",
      }),
    }),
    {
      authenticate: async () => ({
        id: "30000000-0000-4000-8000-000000000001",
      }),
      requireActive: async () => {},
      resolveContext: async () => ({
        safeInputContext: {},
        outputSnapshot: {},
        authoritativeContext: {},
        metadata: {},
      }),
      rpc: async (name, args) => {
        if (name === "find_ai_feedback_receipt") return null;
        submitted = args;
        return {
          id: "40000000-0000-4000-8000-000000000001",
          triage_status: "awaiting_triage",
        };
      },
      triage: async () => await new Promise<void>(() => {}),
      waitUntil: (promise: Promise<unknown>) => {
        background = promise;
      },
    },
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), {
    feedback_id: "40000000-0000-4000-8000-000000000001",
    triage_status: "awaiting_triage",
  });
  assertEquals(background instanceof Promise, true);
  assertEquals(submitted?._metadata, { authoritative_context: {} });
});

Deno.test("accepted replay returns its stable receipt without resolving or rescheduling", async () => {
  let privilegedWork = 0;
  const response = await handleFeedbackRequest(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer valid" },
      body: JSON.stringify({
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        evaluation_mode: "catalog_identity_validation",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "This is the wrong card identity",
        request_id: "20000000-0000-4000-8000-000000000001",
      }),
    }),
    {
      authenticate: async () => ({
        id: "30000000-0000-4000-8000-000000000001",
      }),
      requireActive: async () => {},
      resolveContext: async () => {
        privilegedWork++;
        return {} as never;
      },
      rpc: async (name) =>
        name === "find_ai_feedback_receipt"
          ? {
            id: "40000000-0000-4000-8000-000000000001",
            triage_status: "triaged",
          }
          : null,
      waitUntil: () => {
        privilegedWork++;
      },
    },
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), {
    feedback_id: "40000000-0000-4000-8000-000000000001",
    triage_status: "awaiting_triage",
  });
  assertEquals(privilegedWork, 0);
});
