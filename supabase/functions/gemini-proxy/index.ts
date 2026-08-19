import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  allowedModels,
  modelCandidates,
  preparePayloadForModel,
  shouldTryAnotherModel,
} from "./model_policy.ts";
import {
  ActiveProfileError,
  requireActiveProfile,
} from "../_shared/active_profile.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: corsHeaders },
    );
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return Response.json({ error: "Authentication required" }, {
        status: 401,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const token = authorization.slice("Bearer ".length);
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !user) {
      return Response.json({ error: "Authentication required" }, {
        status: 401,
        headers: corsHeaders,
      });
    }
    try {
      await requireActiveProfile(supabase, user.id);
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

    const { model, payload } = await request.json();
    if (!allowedModels.has(model) || !payload || typeof payload !== "object") {
      return Response.json(
        { error: "Invalid Gemini request" },
        { status: 400, headers: corsHeaders },
      );
    }

    const serializedPayload = JSON.stringify(payload);
    if (serializedPayload.length > 100_000) {
      return Response.json({ error: "Request payload is too large" }, {
        status: 413,
        headers: corsHeaders,
      });
    }

    const { data: quotaAvailable, error: quotaError } = await supabase.rpc(
      "consume_gemini_proxy_quota",
      { _user_id: user.id, _limit: 10 },
    );
    if (quotaError) throw quotaError;
    if (quotaAvailable !== true) {
      return Response.json({ error: "Rate limit exceeded" }, {
        status: 429,
        headers: corsHeaders,
      });
    }

    // Each Gemini free-tier key has its own small daily request quota
    // (observed: 20/day on gemini-2.5-flash). GEMINI_API_KEY, _2, _3, _4...
    // are separate keys/projects, so a 429 on one doesn't mean the others
    // are exhausted too — try each in turn before giving up.
    const apiKeys = [Deno.env.get("GEMINI_API_KEY")];
    for (let i = 2;; i++) {
      const key = Deno.env.get(`GEMINI_API_KEY_${i}`);
      if (!key) break;
      apiKeys.push(key);
    }
    const configuredKeys = apiKeys.filter((k): k is string => !!k);
    if (configuredKeys.length === 0) {
      throw new Error("No GEMINI_API_KEY is configured");
    }

    let upstream: Response | null = null;
    let upstreamBody = "";
    outer:
    for (const candidateModel of modelCandidates(model)) {
      const candidatePayload = preparePayloadForModel(candidateModel, payload);
      for (const apiKey of configuredKeys) {
        // Bound every upstream attempt so a dead connection cannot stall the
        // client's processing queue indefinitely.
        upstream = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${candidateModel}:generateContent?key=${apiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(candidatePayload),
            signal: AbortSignal.timeout(25_000),
          },
        );
        upstreamBody = await upstream.text();
        if (upstream.status === 429) continue;
        if (shouldTryAnotherModel(upstream.status, upstreamBody)) continue;
        break outer;
      }
    }

    return new Response(upstreamBody, {
      status: upstream!.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch {
    return Response.json(
      { error: "request_failed" },
      { status: 500, headers: corsHeaders },
    );
  }
});
