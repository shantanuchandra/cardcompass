import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { isAdminEmail } from "../_shared/card_discovery.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data: { user }, error: authError } = await db.auth.getUser(
    authorization.slice("Bearer ".length),
  );
  if (authError || !user) return json({ error: "Authentication required" }, 401);
  if (
    !user.email_confirmed_at ||
    !isAdminEmail(user.email, Deno.env.get("CARD_CATALOG_ADMIN_EMAILS"))
  ) {
    return json({ error: "Administrator access required" }, 403);
  }

  try {
    const body = await request.json();
    const action = body.action;
    if (action === "access") return json({ is_admin: true });

    if (action === "list") {
      let query = db.from("card_catalog_review_queue").select(`
        id, proposed_fields, source_evidence, existing_candidates,
        validation_warnings, confidence, status, review_reason, created_at,
        updated_at, reviewed_at,
        card_discovery_jobs!card_catalog_review_queue_discovery_job_id_fkey!inner(
          id, issuer, proposed_product, evidence, status, attempt_count,
          failure_category, resolved_card_id, created_at, updated_at
        )
      `).order("created_at", { ascending: true });
      if (typeof body.status === "string" && body.status.length > 0) {
        query = query.eq("status", body.status);
      }
      const { data, error } = await query.limit(100);
      if (error) throw error;
      return json({ items: data ?? [] });
    }

    if (!["approve", "edit_approve", "merge", "retry", "reject"].includes(action)) {
      return json({ error: "Unsupported action" }, 400);
    }
    if (typeof body.review_item_id !== "string" || body.review_item_id.length === 0) {
      return json({ error: "review_item_id is required" }, 400);
    }
    const { data, error } = await db.rpc("review_card_catalog_discovery", {
      _review_item_id: body.review_item_id,
      _actor_id: user.id,
      _action: action,
      _proposed_fields: body.proposed_fields ?? null,
      _merge_card_id: body.merge_card_id ?? null,
      _reason: body.reason ?? null,
    });
    if (error) throw error;
    return json({ success: true, result: Array.isArray(data) ? data[0] : data });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : error && typeof error === "object" && "message" in error
      ? String(error.message)
      : "Request failed";
    return json({ error: message }, 400);
  }
});
