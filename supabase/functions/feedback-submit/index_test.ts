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
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "short",
        request_id: "20000000-0000-4000-8000-000000000001",
      },
      {
        action: "feedback-submit",
        feature_key: "card_data",
        output_ref_type: "user_card",
        output_ref_id: "10000000-0000-4000-8000-000000000001",
        feedback_text: "long enough text",
        request_id: "20000000-0000-4000-8000-000000000001",
        extra: true,
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
      rpc: async (_name, args) => {
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
