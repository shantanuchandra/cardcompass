import {
  modelCandidates,
  preparePayloadForModel,
  shouldTryAnotherModel,
} from "../gemini-proxy/model_policy.ts";

export type GeminiInput = Readonly<{
  model: string;
  payload: Record<string, unknown>;
}>;

export type GeminiGenerationResult = Readonly<{
  model: string;
  response: Record<string, unknown>;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
}>;

// Raw fields remain for the public proxy's backwards-compatible passthrough.
export type GeminiResult =
  & GeminiGenerationResult
  & Readonly<{
    status: number;
    body: string;
    parsedJson?: unknown;
    selectedModel: string;
    usageTokens?: number;
  }>;

export type GeminiDependencies = Readonly<{
  apiKeys: readonly string[];
  fetch: typeof fetch;
  now?: () => number;
  timeoutSignal?: (milliseconds: number) => AbortSignal;
}>;

export function configuredGeminiKeys(
  get = (name: string) => Deno.env.get(name),
): string[] {
  const keys: string[] = [];
  const first = get("GEMINI_API_KEY");
  if (first) keys.push(first);
  for (let index = 2;; index++) {
    const key = get(`GEMINI_API_KEY_${index}`);
    if (!key) break;
    keys.push(key);
  }
  return keys;
}

const safeError = (
  code: "model_unavailable" | "invalid_model_output" | "provider_failed",
) => new Error(code);

export async function generateGemini(
  input: GeminiInput,
  dependencies: GeminiDependencies,
): Promise<GeminiResult> {
  if (dependencies.apiKeys.length === 0) throw safeError("model_unavailable");
  const now = dependencies.now ?? Date.now;
  const timeoutSignal = dependencies.timeoutSignal ?? AbortSignal.timeout;
  let last:
    | { status: number; body: string; model: string; started: number }
    | undefined;
  try {
    for (const candidateModel of modelCandidates(input.model)) {
      const payload = preparePayloadForModel(candidateModel, input.payload);
      for (const apiKey of dependencies.apiKeys) {
        const started = now();
        const response = await dependencies.fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${candidateModel}:generateContent?key=${
            encodeURIComponent(apiKey)
          }`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
            signal: timeoutSignal(25_000),
          },
        );
        const body = await response.text();
        last = {
          status: response.status,
          body,
          model: candidateModel,
          started,
        };
        if (response.status === 429) continue;
        if (shouldTryAnotherModel(response.status, body)) continue;
        return resultFrom(last, now());
      }
      // Exhausting keys because each was rate-limited or reported this model
      // unavailable falls forward to the next supported model, matching the
      // long-standing public proxy behavior.
    }
  } catch {
    throw safeError("model_unavailable");
  }
  if (!last) throw safeError("model_unavailable");
  return resultFrom(last, now());
}

function resultFrom(
  value: { status: number; body: string; model: string; started: number },
  ended: number,
): GeminiResult {
  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(value.body);
  } catch {
    // The public proxy must preserve non-JSON upstream bodies byte-for-byte.
  }
  const usage = parsedJson && typeof parsedJson === "object"
    ? (parsedJson as Record<string, unknown>).usageMetadata
    : undefined;
  const total = usage && typeof usage === "object"
    ? (usage as Record<string, unknown>).totalTokenCount
    : undefined;
  const input = usage && typeof usage === "object"
    ? (usage as Record<string, unknown>).promptTokenCount
    : undefined;
  const output = usage && typeof usage === "object"
    ? (usage as Record<string, unknown>).candidatesTokenCount
    : undefined;
  return {
    model: value.model,
    response:
      parsedJson && typeof parsedJson === "object" && !Array.isArray(parsedJson)
        ? parsedJson as Record<string, unknown>
        : {},
    inputTokens: typeof input === "number" && Number.isFinite(input)
      ? input
      : 0,
    outputTokens: typeof output === "number" && Number.isFinite(output)
      ? output
      : 0,
    status: value.status,
    body: value.body,
    parsedJson,
    selectedModel: value.model,
    latencyMs: Math.max(0, ended - value.started),
    ...(typeof total === "number" && Number.isFinite(total)
      ? { usageTokens: total }
      : {}),
  };
}
