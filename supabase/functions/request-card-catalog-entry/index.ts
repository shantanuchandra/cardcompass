import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    return Response.json({ error: "Method not allowed" }, {
      status: 405,
      headers: corsHeaders,
    });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ error: "Authentication required" }, {
      status: 401,
      headers: corsHeaders,
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authorization.slice("Bearer ".length),
    );
    if (authError || !user) {
      return Response.json({ error: "Authentication required" }, {
        status: 401,
        headers: corsHeaders,
      });
    }

    const { bank_name, card_name, card_url } = await request.json();
    if (
      typeof bank_name !== "string" || bank_name.length < 2 ||
      bank_name.length > 100 ||
      typeof card_name !== "string" || card_name.length < 2 ||
      card_name.length > 150 ||
      typeof card_url !== "string" || card_url.length > 2048
    ) {
      return Response.json({ error: "Invalid card request" }, {
        status: 400,
        headers: corsHeaders,
      });
    }
    const url = new URL(card_url);
    if (url.protocol !== "https:") {
      return Response.json({ error: "Card URL must use HTTPS" }, {
        status: 400,
        headers: corsHeaders,
      });
    }

    const { data: accepted, error } = await supabase.rpc(
      "submit_card_catalog_request",
      {
        _user_id: user.id,
        _bank_name: bank_name.trim(),
        _card_name: card_name.trim(),
        _card_url: url.toString(),
      },
    );
    if (error) throw error;
    if (accepted !== true) {
      return Response.json(
        { error: "Too many pending requests" },
        { status: 429, headers: corsHeaders },
      );
    }
    return Response.json({ success: true, status: "pending" }, {
      headers: corsHeaders,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed";
    return Response.json({ error: message }, {
      status: 500,
      headers: corsHeaders,
    });
  }
});
