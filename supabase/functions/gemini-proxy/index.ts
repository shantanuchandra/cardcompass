import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedModels = new Set([
  "gemini-3.5-flash",
  "gemini-3.1-flash-lite",
  "gemini-2.5-flash",
  "gemini-2.5-pro",
]);

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

    const generationConfig = payload.generationConfig ?? {};
    payload.generationConfig = {
      ...generationConfig,
      maxOutputTokens: Math.min(
        Number(generationConfig.maxOutputTokens) || 4096,
        8192,
      ),
    };

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

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) throw new Error("GEMINI_API_KEY is not configured");

    // Some models (observed: gemini-3.5-flash) can hang with no response for
    // well over a minute. Bound the upstream call so the client's fallback
    // chain gets a timely error instead of stalling on a dead connection.
    const upstream = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(25_000),
      },
    );

    return new Response(await upstream.text(), {
      status: upstream.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Proxy request failed";
    return Response.json(
      { error: message },
      { status: 500, headers: corsHeaders },
    );
  }
});
