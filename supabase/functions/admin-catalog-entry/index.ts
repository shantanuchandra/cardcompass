import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import {
  AdminAccessError,
  resolveAdminActor,
} from "../_shared/admin_access.ts";
import {
  BenefitAdminError,
  handleBenefitAdminAction,
  isBenefitAdminAction,
  type UntypedSupabaseClient,
} from "./benefit_admin.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: corsHeaders });
}

function safeError(error: unknown): { error: string; status: number } {
  if (error instanceof BenefitAdminError) {
    return { error: error.code, status: error.status };
  }
  return { error: "Request failed", status: 400 };
}

export function createAdminAuthClient(
  request: Request,
  supabaseUrl: string,
  fallbackKey: string,
  factory: (...args: any[]) => any = createClient,
) {
  const authorization = request.headers.get("Authorization") ?? "";
  const apiKey = request.headers.get("apikey") ?? fallbackKey;
  return factory(supabaseUrl, apiKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function purgeCalculatorReviewRows(
  db: UntypedSupabaseClient,
): Promise<number> {
  const { data, error } = await db.from("card_catalog_review_queue")
    .select("discovery_job_id,proposed_fields,source_evidence")
    .eq("status", "pending")
    .limit(1000);
  if (error) throw error;
  const jobIds = (data ?? [])
    .filter((row: Record<string, any>) => {
      const url = row.proposed_fields?.official_url ??
        row.source_evidence?.official_url ?? "";
      return typeof url === "string" &&
        url.toLowerCase().includes("calculator");
    })
    .map((row: Record<string, any>) => row.discovery_job_id)
    .filter((id: unknown): id is string =>
      typeof id === "string" && id.length > 0
    );
  if (jobIds.length === 0) return 0;
  const { error: deleteError } = await db.from("card_discovery_jobs")
    .delete()
    .eq("discovery_source", "issuer_crawl")
    .in("id", jobIds);
  if (deleteError) throw deleteError;
  return jobIds.length;
}

export async function handleAdminCatalogEntry(
  request: Request,
  providedDb?: UntypedSupabaseClient,
  providedAuthDb?: UntypedSupabaseClient,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }
  let db: UntypedSupabaseClient;
  let actor: { id: string };
  try {
    db = providedDb ?? createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const authDb = providedAuthDb ?? providedDb ?? createAdminAuthClient(
      request,
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    );
    actor = await resolveAdminActor(request, authDb as never, db as never);
  } catch (error) {
    if (error instanceof AdminAccessError) {
      const message = error.code === "authentication_required"
        ? "Authentication required"
        : error.code === "administrator_access_required"
        ? "Administrator access required"
        : "Request failed";
      return json({ error: message }, error.status);
    }
    return json({ error: "Request failed" }, 500);
  }

  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid request" }, 400);
    }
    const action = body.action;
    if (action === "access") return json({ is_admin: true });

    if (action === "purge-calculator-reviews") {
      return json({ removed: await purgeCalculatorReviewRows(db) });
    }

    if (isBenefitAdminAction(action)) {
      return json(await handleBenefitAdminAction(db, body, actor));
    }

    if (action === "list") {
      if (body.status === "pending") await purgeCalculatorReviewRows(db);
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

    if (
      !["approve", "edit_approve", "merge", "retry", "reject"].includes(action)
    ) {
      return json({ error: "Unsupported action" }, 400);
    }
    if (
      typeof body.review_item_id !== "string" ||
      body.review_item_id.length === 0
    ) {
      return json({ error: "review_item_id is required" }, 400);
    }
    const { data, error } = await db.rpc("review_card_catalog_discovery", {
      _review_item_id: body.review_item_id,
      _actor_id: actor.id,
      _action: action,
      _proposed_fields: body.proposed_fields ?? null,
      _merge_card_id: body.merge_card_id ?? null,
      _reason: body.reason ?? null,
    });
    if (error) throw error;
    return json({
      success: true,
      result: Array.isArray(data) ? data[0] : data,
    });
  } catch (error) {
    const result = safeError(error);
    return json({ error: result.error }, result.status);
  }
}

if (import.meta.main) serve((request) => handleAdminCatalogEntry(request));
