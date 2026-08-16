export const allowedModels = new Set([
  "gemini-3.6-flash",
  "gemini-3.5-flash",
  "gemini-3.1-flash-lite",
  "gemini-2.5-flash",
  "gemini-2.5-pro",
]);

const currentFlashModels = [
  "gemini-3.6-flash",
  "gemini-3.5-flash",
  "gemini-3.1-flash-lite",
];

export function modelCandidates(requestedModel: string): string[] {
  return [...new Set([requestedModel, ...currentFlashModels])].filter((model) =>
    allowedModels.has(model)
  );
}

export function preparePayloadForModel(
  model: string,
  payload: Record<string, unknown>,
): Record<string, unknown> {
  const generationConfig = {
    ...((payload.generationConfig as Record<string, unknown> | undefined) ??
      {}),
  };
  if (model.startsWith("gemini-3")) {
    delete generationConfig.temperature;
    delete generationConfig.topP;
    delete generationConfig.topK;
  }
  generationConfig.maxOutputTokens = Math.min(
    Number(generationConfig.maxOutputTokens) || 4096,
    8192,
  );
  return { ...payload, generationConfig };
}

export function shouldTryAnotherModel(status: number, body: string): boolean {
  if (status !== 404) return false;
  const normalized = body.toLowerCase();
  return normalized.includes("model") &&
    (normalized.includes("no longer available") ||
      normalized.includes("not found") ||
      normalized.includes("not_found"));
}
