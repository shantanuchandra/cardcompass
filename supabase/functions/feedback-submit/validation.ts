export const outputRefByFeature = {
  statement_processing: ["transaction", "statement"],
  card_data: ["user_card"],
  recommendation: ["recommendation_trace"],
} as const;

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function exact(value: Record<string, unknown>, keys: string[]) {
  if (
    Object.keys(value).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(value, key))
  ) throw new Error("invalid_request");
}
function object(value: unknown): Record<string, unknown> {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw new Error("invalid_request");
  }
  return value as Record<string, unknown>;
}
function jsonBytes(value: unknown, max: number) {
  if (
    !value || Array.isArray(value) || typeof value !== "object" ||
    new TextEncoder().encode(JSON.stringify(value)).byteLength > max
  ) throw new Error("invalid_request");
}

function finite(value: unknown, min = 0): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= min;
}

function recommendationFixture(input: unknown, output: unknown) {
  const safe = object(input);
  const snapshot = object(output);
  const safeKeys = ["number_of_tickets", "price_per_ticket"];
  if (Object.hasOwn(safe, "preferred_platform")) {
    safeKeys.push("preferred_platform");
  }
  if (Object.hasOwn(safe, "preferred_cinema")) {
    safeKeys.push("preferred_cinema");
  }
  exact(safe, safeKeys);
  exact(snapshot, [
    "selected_card_id",
    "selected_benefit_id",
    "savings",
    "final_amount",
    "explanation",
  ]);
  if (
    !Number.isInteger(safe.number_of_tickets) ||
    !finite(safe.number_of_tickets, 1) ||
    !finite(safe.price_per_ticket) ||
    (Object.hasOwn(safe, "preferred_platform") &&
      (typeof safe.preferred_platform !== "string" ||
        [...safe.preferred_platform].length > 80)) ||
    (Object.hasOwn(safe, "preferred_cinema") &&
      (typeof safe.preferred_cinema !== "string" ||
        [...safe.preferred_cinema].length > 80)) ||
    typeof snapshot.selected_card_id !== "string" ||
    !uuid.test(snapshot.selected_card_id) ||
    typeof snapshot.selected_benefit_id !== "string" ||
    !uuid.test(snapshot.selected_benefit_id) ||
    !finite(snapshot.savings) || !finite(snapshot.final_amount) ||
    typeof snapshot.explanation !== "string" ||
    snapshot.explanation.trim().length < 1 ||
    [...snapshot.explanation].length > 1000
  ) throw new Error("invalid_request");
}

export type FeedbackBody =
  | {
    action: "feedback-submit";
    feature_key: keyof typeof outputRefByFeature;
    output_ref_type: string;
    output_ref_id: string;
    feedback_text: string;
    request_id: string;
  }
  | {
    action: "trace-create";
    feature_key: "recommendation";
    safe_input_context: Record<string, unknown>;
    output_snapshot: Record<string, unknown>;
    card_ids: string[];
    benefit_ids: string[];
    request_id: string;
  };

export function parseFeedbackBody(raw: unknown): FeedbackBody {
  const value = object(raw);
  if (value.action === "feedback-submit") {
    exact(value, [
      "action",
      "feature_key",
      "output_ref_type",
      "output_ref_id",
      "feedback_text",
      "request_id",
    ]);
    if (
      typeof value.feature_key !== "string" ||
      !Object.hasOwn(outputRefByFeature, value.feature_key)
    ) throw new Error("invalid_request");
    const allowed = outputRefByFeature[
      value.feature_key as keyof typeof outputRefByFeature
    ] as readonly string[];
    if (
      typeof value.output_ref_type !== "string" ||
      !allowed.includes(value.output_ref_type) ||
      typeof value.output_ref_id !== "string" ||
      !uuid.test(value.output_ref_id) || typeof value.request_id !== "string" ||
      !uuid.test(value.request_id) || typeof value.feedback_text !== "string" ||
      value.feedback_text.trim().length < 10 ||
      value.feedback_text.trim().length > 2000
    ) throw new Error("invalid_request");
    return value as FeedbackBody;
  }
  if (value.action === "trace-create") {
    exact(value, [
      "action",
      "feature_key",
      "safe_input_context",
      "output_snapshot",
      "card_ids",
      "benefit_ids",
      "request_id",
    ]);
    jsonBytes(value.safe_input_context, 16384);
    jsonBytes(value.output_snapshot, 32768);
    recommendationFixture(value.safe_input_context, value.output_snapshot);
    if (
      value.feature_key !== "recommendation" ||
      typeof value.request_id !== "string" || !uuid.test(value.request_id)
    ) throw new Error("invalid_request");
    for (const ids of [value.card_ids, value.benefit_ids]) {
      if (
        !Array.isArray(ids) || ids.length > 50 ||
        ids.some((id) => typeof id !== "string" || !uuid.test(id))
      ) throw new Error("invalid_request");
    }
    const cardIds = value.card_ids as string[];
    const benefitIds = value.benefit_ids as string[];
    const snapshot = value.output_snapshot as Record<string, unknown>;
    if (
      cardIds.length !== 1 || benefitIds.length !== 1 ||
      cardIds[0] !== snapshot.selected_card_id ||
      benefitIds[0] !== snapshot.selected_benefit_id
    ) throw new Error("invalid_request");
    return value as FeedbackBody;
  }
  throw new Error("invalid_request");
}
