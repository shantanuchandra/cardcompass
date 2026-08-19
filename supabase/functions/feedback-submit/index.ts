import { createClient } from "@supabase/supabase-js";
import {
  ActiveProfileError,
  requireActiveProfile,
} from "../_shared/active_profile.ts";
import {
  resolveFeedbackContext,
  resolveRecommendationCatalog,
  type SafeContext,
} from "./context.ts";
import { parseFeedbackBody } from "./validation.ts";
import {
  createGeminiTriageModel,
  triageFeedback,
} from "../_shared/feedback_triage.ts";

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: cors });
type Actor = { id: string };
type Dependencies = {
  authenticate: (request: Request) => Promise<Actor>;
  requireActive: (id: string) => Promise<void>;
  resolveContext: (
    userId: string,
    feature: string,
    refType: string,
    refId: string,
  ) => Promise<SafeContext>;
  resolveCatalog?: (
    cardIds: string[],
    benefitIds: string[],
  ) => Promise<Record<string, unknown>>;
  rpc: (name: string, args: Record<string, unknown>) => Promise<any>;
  triage?: (id: string) => Promise<void>;
  waitUntil: (promise: Promise<unknown>) => void;
};

async function defaultDependencies(request: Request): Promise<Dependencies> {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authDb = createClient(url, request.headers.get("apikey") ?? key, {
    global: {
      headers: { Authorization: request.headers.get("Authorization") ?? "" },
    },
  });
  const serviceDb: any = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await serviceDb.rpc(name, args);
    if (error) {
      throw new Error(
        error.message?.includes("request_id_collision")
          ? "request_id_collision"
          : error.message?.includes("state_conflict")
          ? "state_conflict"
          : "request_failed",
      );
    }
    return data;
  };
  const apiKeys: string[] = [];
  const firstKey = Deno.env.get("GEMINI_API_KEY");
  if (firstKey) apiKeys.push(firstKey);
  for (let index = 2;; index++) {
    const key = Deno.env.get(`GEMINI_API_KEY_${index}`);
    if (!key) break;
    apiKeys.push(key);
  }
  const model = createGeminiTriageModel({ apiKeys, fetch });
  return {
    authenticate: async () => {
      const header = request.headers.get("Authorization");
      if (!header?.startsWith("Bearer ")) {
        throw Object.assign(new Error("authentication_required"), {
          status: 401,
        });
      }
      const { data, error } = await authDb.auth.getUser(header.slice(7));
      if (error || !data.user) {
        throw Object.assign(new Error("authentication_required"), {
          status: 401,
        });
      }
      return { id: data.user.id };
    },
    requireActive: (id) => requireActiveProfile(serviceDb, id),
    resolveContext: (id, feature, type, ref) =>
      resolveFeedbackContext(serviceDb, id, feature, type, ref),
    resolveCatalog: (cards, benefits) =>
      resolveRecommendationCatalog(serviceDb, cards, benefits),
    rpc,
    triage: (id) => triageFeedback(id, { rpc, model }),
    waitUntil: (promise) => EdgeRuntime.waitUntil(promise),
  };
}

export async function handleFeedbackRequest(
  request: Request,
  provided?: Dependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (request.method !== "POST") return json({ error: "invalid_request" }, 405);
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > 65536) {
      return json({ error: "invalid_request" }, 413);
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("invalid_request");
    }
    const body = parseFeedbackBody(parsed);
    const deps = provided ?? await defaultDependencies(request);
    const actor = await deps.authenticate(request);
    await deps.requireActive(actor.id);
    if (body.action === "trace-create") {
      const authoritative = await deps.resolveCatalog!(
        body.card_ids,
        body.benefit_ids,
      );
      const result = await deps.rpc("create_ai_output_trace", {
        _user_id: actor.id,
        _request_id: body.request_id,
        _feature_key: body.feature_key,
        _safe_input: body.safe_input_context,
        _output: { ...body.output_snapshot, provenance: "client_reported" },
        _authoritative: authoritative,
        _metadata: {
          engine_version: body.engine_version,
          prompt_version: body.engine_version,
        },
      });
      return json({ trace_id: result.id, expires_at: result.expires_at }, 201);
    }
    const context = await deps.resolveContext(
      actor.id,
      body.feature_key,
      body.output_ref_type,
      body.output_ref_id,
    );
    const result = await deps.rpc("submit_ai_feedback", {
      _user_id: actor.id,
      _request_id: body.request_id,
      _feature_key: body.feature_key,
      _output_ref_type: body.output_ref_type,
      _output_ref_id: body.output_ref_id,
      _feedback_text: body.feedback_text.trim(),
      _safe_input: context.safeInputContext,
      _output: context.outputSnapshot,
      _metadata: {
        ...context.metadata,
        authoritative_context: context.authoritativeContext,
      },
    });
    deps.waitUntil(
      (deps.triage ?? (async () => {}))(result.id).catch(() => undefined),
    );
    return json(
      { feedback_id: result.id, triage_status: result.triage_status },
      202,
    );
  } catch (error) {
    const code = error instanceof ActiveProfileError
      ? error.code
      : error instanceof Error &&
          [
            "invalid_request",
            "authentication_required",
            "account_inactive",
            "profile_unavailable",
            "not_found",
            "request_id_collision",
          ].includes(error.message)
      ? error.message
      : "request_failed";
    const status = (error as { status?: number }).status ??
      (code === "invalid_request"
        ? 400
        : code === "authentication_required"
        ? 401
        : code === "account_inactive"
        ? 403
        : code === "not_found"
        ? 404
        : code === "request_id_collision"
        ? 409
        : 500);
    return json({ error: code }, status);
  }
}

if (import.meta.main) Deno.serve((request) => handleFeedbackRequest(request));
