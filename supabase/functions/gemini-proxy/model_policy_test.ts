import {
  modelCandidates,
  preparePayloadForModel,
  shouldTryAnotherModel,
} from "./model_policy.ts";

Deno.test("legacy requests fall forward to current Flash models", () => {
  if (
    JSON.stringify(modelCandidates("gemini-2.5-flash")) !==
      JSON.stringify([
        "gemini-2.5-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite",
      ])
  ) {
    throw new Error("unexpected model fallback order");
  }
});

Deno.test("Gemini 3 requests omit deprecated sampling parameters", () => {
  const payload = preparePayloadForModel("gemini-3.6-flash", {
    contents: [{ parts: [{ text: "parse this statement" }] }],
    generationConfig: {
      temperature: 0.1,
      topP: 0.9,
      topK: 20,
      maxOutputTokens: 2048,
    },
  });
  const generationConfig = payload.generationConfig as Record<string, unknown>;
  if (
    "temperature" in generationConfig || "topP" in generationConfig ||
    "topK" in generationConfig
  ) {
    throw new Error("deprecated sampling parameters were retained");
  }
  if (generationConfig.maxOutputTokens !== 2048) {
    throw new Error("maxOutputTokens was not preserved");
  }
});

Deno.test("only model-availability 404s trigger model fallback", () => {
  if (!shouldTryAnotherModel(404, "This model is no longer available")) {
    throw new Error("availability error should trigger fallback");
  }
  if (shouldTryAnotherModel(400, "invalid request")) {
    throw new Error("invalid payload must not trigger fallback");
  }
});
