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
  fetch: typeof globalThis.fetch;
  waitUntil: (promise: Promise<unknown>) => void;
  supabaseUrl: string;
  serviceRoleKey: string;
}>;

type EvalSchedulerDependencies = Readonly<{
  fetch: typeof globalThis.fetch;
  waitUntil: (promise: Promise<unknown>) => void;
  supabaseUrl: string;
  serviceRoleKey: string;
}>;

export function createEvalScheduler(deps: EvalSchedulerDependencies) {
  return async (runId: string): Promise<void> => {
    const task = (async () => {
      const response = await deps.fetch(
        new Request(`${deps.supabaseUrl}/functions/v1/ai-eval-runner`, {
          method: "POST",
          headers: {
            authorization: `Bearer ${deps.serviceRoleKey}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ run_id: runId }),
        }),
      );
      if (response.status !== 202) {
        throw new Error("eval_worker_schedule_failed");
      }
      const receipt: unknown = await response.json();
      if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) {
        throw new Error("eval_worker_schedule_failed");
      }
      const row = receipt as Record<string, unknown>;
      const keys = new Set([
        "run_id",
        "status",
        "processed",
        "continuation_scheduled",
      ]);
      if (
        Object.keys(row).length !== keys.size ||
        Object.keys(row).some((key) => !keys.has(key)) ||
        row.run_id !== runId ||
        row.status !== "accepted" || !Number.isSafeInteger(row.processed) ||
        (row.processed as number) < 0 || (row.processed as number) > 5 ||
        typeof row.continuation_scheduled !== "boolean"
      ) throw new Error("eval_worker_schedule_failed");
    })();
    deps.waitUntil(task);
  };
}

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
    let scheduleEvalRun: AdminActionContext["scheduleEvalRun"];
    if (body.action === "eval-run-action") {
      const supabaseUrl = provided?.supabaseUrl ??
        Deno.env.get("SUPABASE_URL") ?? "";
      const serviceRoleKey = provided?.serviceRoleKey ??
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      const waitUntil = provided?.waitUntil ?? ((promise: Promise<unknown>) => {
        const runtime = (globalThis as unknown as {
          EdgeRuntime?: { waitUntil: (value: Promise<unknown>) => void };
        }).EdgeRuntime;
        if (!runtime) throw new Error("background_runtime_unavailable");
        runtime.waitUntil(promise);
      });
      scheduleEvalRun = createEvalScheduler({
        fetch: provided?.fetch ?? globalThis.fetch,
        waitUntil,
        supabaseUrl,
        serviceRoleKey,
      });
    }
    return jsonResponse(
      await handler(body, {
        actor,
        requestId,
        db,
        authAdmin,
        scheduleEvalRun,
      }),
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
