import { createClient } from "@supabase/supabase-js";
import { requireAdmin } from "./auth.ts";
import { corsHeaders, jsonResponse } from "./http.ts";
import { actionHandlers } from "./router.ts";
import {
  type AdminActionContext,
  type AdminActor,
  type AdminAuthClient,
  type AdminDatabaseClient,
  AdminHttpError,
} from "./types.ts";

const MAX_BODY_BYTES = 32_768;

class InvalidRequestError extends Error {
  constructor(readonly status = 400) {
    super("invalid_request");
    this.name = "InvalidRequestError";
  }
}

type AdminOperatorDependencies = Readonly<{
  authorize: (request: Request) => Promise<AdminActor>;
  db: AdminActionContext["db"];
  authDb: AdminAuthClient;
  authAdmin: AdminActionContext["authAdmin"];
}>;

function invalidRequest(status = 400): never {
  throw new InvalidRequestError(status);
}

function parseRequestBody(
  raw: string,
): Record<string, unknown> & { action: string } {
  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
    invalidRequest(413);
  }

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    invalidRequest();
  }

  if (!body || Array.isArray(body) || typeof body !== "object") {
    invalidRequest();
  }

  const objectBody = body as Record<string, unknown>;
  if (typeof objectBody.action !== "string") invalidRequest();
  return objectBody as Record<string, unknown> & { action: string };
}

export async function handleAdminOperator(
  request: Request,
  provided?: Partial<AdminOperatorDependencies>,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "invalid_request" }, 405);
  }

  try {
    const body = parseRequestBody(await request.text());
    const db = provided?.db ?? (createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    ) as unknown as AdminDatabaseClient);
    const actor = provided?.authorize
      ? await provided.authorize(request)
      : await requireAdmin(
        request,
        (provided?.authDb ?? createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          request.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ??
            "",
          {
            global: {
              headers: {
                Authorization: request.headers.get("Authorization") ?? "",
              },
            },
          },
        )) as AdminAuthClient,
        db as never,
      );
    if (!Object.hasOwn(actionHandlers, body.action)) invalidRequest();
    const handler = actionHandlers[body.action];

    const requestId = typeof body.request_id === "string"
      ? body.request_id
      : null;
    const authAdmin = provided?.authAdmin ??
      (db as unknown as { auth?: { admin?: AdminActionContext["authAdmin"] } })
        .auth?.admin;
    return jsonResponse(
      await handler(body, { actor, requestId, db, authAdmin }),
    );
  } catch (error) {
    if (error instanceof InvalidRequestError) {
      return jsonResponse({ error: "invalid_request" }, error.status);
    }
    if (error instanceof AdminHttpError) {
      return jsonResponse({ error: error.code }, error.status);
    }
    return jsonResponse({ error: "request_failed" }, 500);
  }
}

if (import.meta.main) Deno.serve((request) => handleAdminOperator(request));
