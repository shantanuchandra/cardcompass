import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { isAdminEmail } from "../_shared/card_discovery.ts";
import { publishReviewedCardIdentity } from "../_shared/catalog_identity_publication.ts";
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

export function safeError(error: unknown): { error: string; status: number } {
  if (error instanceof BenefitAdminError) {
    return { error: error.code, status: error.status };
  }
  const candidate = error && typeof error === "object"
    ? error as { code?: unknown; message?: unknown }
    : {};
  const message = typeof candidate.message === "string"
    ? candidate.message
    : "";
  if (
    candidate.code === "40001" || message.includes(
      "reviewed_enrichment_source_busy",
    )
  ) return { error: "publication_busy", status: 409 };
  for (
    const code of [
      "conflicting_url_identity",
      "url_identity_incompatible",
      "ambiguous_catalog_identity",
      "edit_target_conflict",
      "stale_catalog_review",
      "stale_catalog_publication",
      "stale_catalog_baseline",
    ]
  ) {
    if (message.includes(code)) return { error: code, status: 409 };
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

export async function terminalizeCalculatorReviewRows(
  db: UntypedSupabaseClient,
  actorId: string,
): Promise<number> {
  const { data, error } = await db.rpc("terminalize_calculator_review_rows", {
    _actor_id: actorId,
    _limit: 1000,
  });
  if (error) throw error;
  if (!Number.isInteger(data) || Number(data) < 0) {
    throw new Error("invalid_terminal_review_count");
  }
  return Number(data);
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
  let user: Record<string, any> | null = null;
  let authError: unknown = null;
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
    const authResult = await authDb.auth.getUser(
      authorization.slice("Bearer ".length),
    );
    user = authResult.data.user;
    authError = authResult.error;
  } catch (error) {
    authError = error;
  }
  if (authError || !user) {
    return json({ error: "Authentication required" }, 401);
  }
  if (
    !user.email_confirmed_at ||
    !isAdminEmail(user.email, Deno.env.get("CARD_CATALOG_ADMIN_EMAILS"))
  ) {
    return json({ error: "Administrator access required" }, 403);
  }

  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid request" }, 400);
    }
    const action = body.action;
    if (action === "access") return json({ is_admin: true });

    if (action === "purge-calculator-reviews") {
      return json({
        transitioned: await terminalizeCalculatorReviewRows(db, user.id),
      });
    }

    if (isBenefitAdminAction(action)) {
      return json(await handleBenefitAdminAction(db, body, { id: user.id }));
    }

    if (action === "list") {
      if (body.status === "pending") {
        await terminalizeCalculatorReviewRows(db, user.id);
      }
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
      ![
        "approve",
        "edit_approve",
        "merge",
        "retry",
        "reject",
        "mark_discontinued",
        "reactivate",
      ].includes(action)
    ) {
      return json({ error: "Unsupported action" }, 400);
    }
    if (
      typeof body.review_item_id !== "string" ||
      body.review_item_id.length === 0
    ) {
      return json({ error: "review_item_id is required" }, 400);
    }
    const { data: review, error: reviewError } = await db
      .from("card_catalog_review_queue")
      .select("discovery_job_id,proposed_fields,source_evidence")
      .eq("id", body.review_item_id)
      .single();
    if (reviewError || !review) {
      throw reviewError ?? new Error("review_not_found");
    }
    const reviewedFields = {
      ...(review.proposed_fields && typeof review.proposed_fields === "object"
        ? review.proposed_fields
        : {}),
      ...(body.proposed_fields && typeof body.proposed_fields === "object" &&
          !Array.isArray(body.proposed_fields)
        ? body.proposed_fields
        : {}),
    } as Record<string, unknown>;
    if (
      !reviewedFields.source_observation && review.source_evidence &&
      typeof review.source_evidence === "object"
    ) reviewedFields.source_observation = review.source_evidence;
    const data = await publishReviewedCardIdentity(db, {
      discoveryJobId: review.discovery_job_id,
      reviewItemId: body.review_item_id,
      actorId: user.id,
      action,
      reviewedFields,
      mergeCardId: body.merge_card_id ?? null,
      reason: body.reason ?? null,
      parserVersion: "benefits-v6",
    });
    return json({
      success: true,
      result: data,
    });
  } catch (error) {
    const result = safeError(error);
    return json({ error: result.error }, result.status);
  }
}

serve((request) => handleAdminCatalogEntry(request));
