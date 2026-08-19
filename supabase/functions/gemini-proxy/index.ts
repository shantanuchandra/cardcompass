import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { allowedModels } from "./model_policy.ts";
import {
  ActiveProfileError,
  requireActiveProfile,
} from "../_shared/active_profile.ts";
import {
  type GeminiInput,
  type GeminiResult,
  generateGemini,
} from "../_shared/gemini_generate.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ProxyDependencies = Readonly<{
  authenticate: (request: Request) => Promise<string>;
  requireActive: (userId: string) => Promise<void>;
  consumeQuota: (userId: string) => Promise<boolean>;
  generate: (input: GeminiInput) => Promise<GeminiResult>;
}>;

function configuredKeys(): string[] {
  const keys: string[] = [];
  const first = Deno.env.get("GEMINI_API_KEY");
  if (first) keys.push(first);
  for (let index = 2;; index++) {
    const key = Deno.env.get(`GEMINI_API_KEY_${index}`);
    if (!key) break;
    keys.push(key);
  }
  return keys;
}

function defaultDependencies(): ProxyDependencies {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const apiKeys = configuredKeys();
  return {
    authenticate: async (request) => {
      const authorization = request.headers.get("Authorization");
      if (!authorization?.startsWith("Bearer ")) {
        throw new Error("authentication_required");
      }
      const { data: { user }, error } = await supabase.auth.getUser(
        authorization.slice(7),
      );
      if (error || !user) throw new Error("authentication_required");
      return user.id;
    },
    requireActive: (id) => requireActiveProfile(supabase, id),
    consumeQuota: async (id) => {
      const { data, error } = await supabase.rpc("consume_gemini_proxy_quota", {
        _user_id: id,
        _limit: 10,
      });
      if (error) throw error;
      return data === true;
    },
    generate: (input) => generateGemini(input, { apiKeys, fetch }),
  };
}

export async function handleGeminiProxyRequest(
  request: Request,
  dependencies?: ProxyDependencies,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, {
      status: 405,
      headers: corsHeaders,
    });
  }
  const deps = dependencies ?? defaultDependencies();
  let userId: string;
  try {
    userId = await deps.authenticate(request);
  } catch {
    return Response.json({ error: "Authentication required" }, {
      status: 401,
      headers: corsHeaders,
    });
  }
  try {
    await deps.requireActive(userId);
  } catch (error) {
    if (error instanceof ActiveProfileError) {
      return Response.json({ error: error.code }, {
        status: error.status,
        headers: corsHeaders,
      });
    }
    return Response.json({ error: "profile_unavailable" }, {
      status: 503,
      headers: corsHeaders,
    });
  }
  try {
    const { model: suppliedModel, payload } = await request.json();
    const model = suppliedModel ?? "gemini-3.6-flash";
    if (
      !allowedModels.has(model) || !payload || typeof payload !== "object"
    ) {
      return Response.json({ error: "Invalid Gemini request" }, {
        status: 400,
        headers: corsHeaders,
      });
    }
    const serializedPayload = JSON.stringify(payload);
    if (serializedPayload.length > 100_000) {
      return Response.json({ error: "Request payload is too large" }, {
        status: 413,
        headers: corsHeaders,
      });
    }
    if (!await deps.consumeQuota(userId)) {
      return Response.json({ error: "Rate limit exceeded" }, {
        status: 429,
        headers: corsHeaders,
      });
    }
    const upstream = await deps.generate({ model, payload });
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch {
    return Response.json({ error: "request_failed" }, {
      status: 500,
      headers: corsHeaders,
    });
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleGeminiProxyRequest(request));
}
