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

    const { action, staging_id } = await request.json();
    if (action === "list") {
      const { data, error } = await supabase.rpc(
        "list_pending_catalog_entry_requests",
      );
      if (error) throw error;
      return Response.json({ requests: data ?? [] }, { headers: corsHeaders });
    }

    if (typeof staging_id !== "string" || staging_id.length === 0) {
      return Response.json({ error: "staging_id is required" }, {
        status: 400,
        headers: corsHeaders,
      });
    }

    if (action === "approve") {
      const { data, error } = await supabase.rpc(
        "approve_catalog_entry_request",
        {
          _staging_id: staging_id,
          _reviewed_by: user.id,
        },
      );
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : null;
      if (!row?.card_id) {
        return Response.json({ success: false, error: "Approval failed" }, {
          status: 500,
          headers: corsHeaders,
        });
      }
      return Response.json({
        success: true,
        card_id: row.card_id,
        bank_name: row.bank_name,
        card_name: row.card_name,
        source_url: row.source_url,
      }, { headers: corsHeaders });
    }

    if (action === "reject") {
      const { data: rejected, error } = await supabase.rpc(
        "reject_catalog_entry_request",
        {
          _staging_id: staging_id,
          _reviewed_by: user.id,
        },
      );
      if (error) throw error;
      if (rejected !== true) {
        return Response.json({
          success: false,
          error: "Request is not pending or not a catalog entry",
        }, { status: 409, headers: corsHeaders });
      }
      return Response.json({ success: true }, { headers: corsHeaders });
    }

    return Response.json({ error: "Unsupported action" }, {
      status: 400,
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
