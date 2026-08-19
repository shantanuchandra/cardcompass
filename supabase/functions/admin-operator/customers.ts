import { type AdminActionHandler } from "./access.ts";
import {
  type AdminActionContext,
  type AdminDatabaseError,
  AdminHttpError,
} from "./types.ts";

type JsonRecord = Record<string, unknown>;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_FAILURES = new Set([
  "reauthentication_required",
  "gmail_unavailable",
  "processing_failed",
]);
const DELETION_STATUSES = new Set([
  "requested",
  "verified",
  "scheduled",
  "completed",
  "cancelled",
]);
const AUTH_BAN_STATUSES = new Set([
  "pending",
  "processing",
  "completed",
  "failed",
]);

function invalid(): never {
  throw new AdminHttpError("invalid_request", 400);
}
function record(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}
function onlyKeys(body: JsonRecord, allowed: ReadonlySet<string>) {
  if (Object.keys(body).some((key) => !allowed.has(key))) invalid();
}
function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID.test(value)) invalid();
  return value;
}
function timestamp(value: unknown): string {
  if (
    typeof value !== "string" || value.length > 100 ||
    Number.isNaN(Date.parse(value))
  ) invalid();
  return value;
}
function safeTimestamp(value: unknown): string | null {
  return typeof value === "string" && value.length <= 100 &&
      !Number.isNaN(Date.parse(value))
    ? value
    : null;
}
function reason(value: unknown): string {
  if (typeof value !== "string") invalid();
  const result = value.trim();
  if (result.length < 2 || result.length > 1000) invalid();
  return result;
}
function mapDatabaseError(error: AdminDatabaseError): AdminHttpError {
  const message = typeof error.message === "string"
    ? error.message.toLowerCase()
    : "";
  if (
    message.includes("request_id_collision") ||
    message.includes("state_conflict") ||
    message.includes("self_disable_denied")
  ) return new AdminHttpError("state_conflict", 409);
  if (message.includes("not_found")) {
    return new AdminHttpError("not_found", 404);
  }
  if (message.includes("reason_required")) {
    return new AdminHttpError("reason_required", 400);
  }
  if (message.includes("invalid_request")) {
    return new AdminHttpError("invalid_request", 400);
  }
  return new AdminHttpError("request_failed", 500);
}
function safeProfile(value: unknown) {
  const row = record(value);
  const id = row?.id;
  const email = row?.email;
  const createdAt = safeTimestamp(row?.created_at);
  const updatedAt = safeTimestamp(row?.updated_at);
  if (
    typeof id !== "string" || !UUID.test(id) || typeof email !== "string" ||
    email.length > 320 || createdAt === null || updatedAt === null ||
    typeof row?.is_active !== "boolean"
  ) throw new AdminHttpError("request_failed", 500);
  return {
    id,
    email: email.trim().toLowerCase(),
    created_at: createdAt,
    last_activity_at: updatedAt,
    is_active: row.is_active,
  };
}
function escapedLike(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll("%", "\\%").replaceAll(
    "_",
    "\\_",
  );
}
async function rows(query: any): Promise<unknown[]> {
  const { data, error } = await query;
  if (error || !Array.isArray(data)) {
    throw new AdminHttpError("request_failed", 500);
  }
  return data;
}
async function exactCount(
  context: AdminActionContext,
  table: string,
  userId: string,
  processed?: boolean,
): Promise<number> {
  let query = (context.db as any).from(table).select("id", {
    count: "exact",
    head: true,
  }).eq("user_id", userId);
  if (processed !== undefined) query = query.eq("processed", processed);
  const { count, error } = await query.range(0, 0);
  if (
    error || typeof count !== "number" || !Number.isSafeInteger(count) ||
    count < 0
  ) throw new AdminHttpError("request_failed", 500);
  return count;
}
async function latest(
  context: AdminActionContext,
  table: string,
  column: string,
  userId: string,
): Promise<string | null> {
  const data = await rows(
    (context.db as any).from(table).select(`${column},id`).eq("user_id", userId)
      .order(column, { ascending: false, nullsFirst: false }).order("id", {
        ascending: false,
      }).range(0, 0),
  );
  if (data.length === 0) return null;
  const result = safeTimestamp(record(data[0])?.[column]);
  if (result === null) throw new AdminHttpError("request_failed", 500);
  return result;
}

export async function handleCustomerSearch(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(body, new Set(["action", "query", "limit", "request_id"]));
  if (typeof body.query !== "string" || body.query.length > 320) invalid();
  const normalized = body.query.trim().toLowerCase();
  const isUuid = UUID.test(normalized);
  if (!isUuid && normalized.length < 3) invalid();
  const { error: auditError } = await context.db.rpc("record_admin_read", {
    _actor_id: context.actor.id,
    _action: "customer.search",
    _target_type: "user",
    _target_id: isUuid ? normalized : null,
    _request_id: uuid(body.request_id),
    _details: { query_type: isUuid ? "user_id" : "email_fragment" },
  });
  if (auditError) throw new AdminHttpError("request_failed", 500);
  const parsedLimit = body.limit === undefined ? 25 : Number(body.limit);
  const limit = Number.isInteger(parsedLimit)
    ? Math.min(25, Math.max(1, parsedLimit))
    : 25;
  let query: any = (context.db as any).from("users").select(
    "id,email,created_at,updated_at,is_active",
  );
  query = isUuid
    ? query.eq("id", normalized)
    : query.ilike("email", `%${escapedLike(normalized)}%`);
  const data = await rows(
    query.order("email", { ascending: true }).order("id", { ascending: true })
      .range(0, limit - 1),
  );
  return { items: data.map(safeProfile) };
}

async function auditCustomerRead(
  body: JsonRecord,
  context: AdminActionContext,
  targetId: string,
) {
  const { error } = await context.db.rpc("record_admin_read", {
    _actor_id: context.actor.id,
    _action: "customer.detail",
    _target_type: "user",
    _target_id: targetId,
    _request_id: uuid(body.request_id),
    _details: {},
  });
  if (error) throw new AdminHttpError("request_failed", 500);
}

export async function handleCustomerDetail(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(body, new Set(["action", "target_id", "request_id"]));
  const targetId = uuid(body.target_id);
  await auditCustomerRead(body, context, targetId);
  if (!context.authAdmin) throw new AdminHttpError("request_failed", 500);
  const profileRows = rows(
    (context.db as any).from("users").select(
      "id,email,created_at,updated_at,is_active",
    ).eq("id", targetId).range(0, 0),
  );
  const operationRows = rows(
    (context.db as any).from("admin_customer_operation_requests").select(
      "status,safe_failure_category,updated_at,id",
    ).eq("user_id", targetId).eq("operation_type", "gmail_sync").order(
      "updated_at",
      { ascending: false },
    ).order("id", { ascending: false }).range(0, 0),
  );
  const deletionRows = rows(
    (context.db as any).from("account_deletion_requests").select(
      "status,updated_at,id",
    ).eq("user_id", targetId).range(0, 0),
  );
  const authBanRows = rows(
    (context.db as any).from("admin_auth_ban_requests").select(
      "id,status,safe_failure_category,updated_at",
    ).eq("user_id", targetId).range(0, 0),
  );
  const authResult = context.authAdmin.getUserById(targetId);
  const [
    profiles,
    operations,
    deletions,
    cards,
    statements,
    processedStatements,
    emails,
    processedEmails,
    latestStatement,
    latestEmail,
    auth,
    authBans,
  ] = await Promise.all([
    profileRows,
    operationRows,
    deletionRows,
    exactCount(context, "user_cards", targetId),
    exactCount(context, "statements", targetId),
    exactCount(context, "statements", targetId, true),
    exactCount(context, "emails", targetId),
    exactCount(context, "emails", targetId, true),
    latest(context, "statements", "created_at", targetId),
    latest(context, "emails", "received_date", targetId),
    authResult,
    authBanRows,
  ]);
  if (profiles.length !== 1) throw new AdminHttpError("not_found", 404);
  if (auth.error || !record(auth.data)?.user) {
    throw new AdminHttpError("request_failed", 500);
  }
  const authUser = record(record(auth.data)?.user);
  const identities = Array.isArray(authUser?.identities)
    ? authUser.identities
    : [];
  const gmailConnected = identities.some((identity) =>
    record(identity)?.provider === "google"
  );
  const operation = operations.length ? record(operations[0]) : null;
  const deletion = deletions.length ? record(deletions[0]) : null;
  const authBan = authBans.length ? record(authBans[0]) : null;
  const operationStatus = typeof operation?.status === "string" &&
      ["queued", "claimed", "completed", "failed"].includes(operation.status)
    ? operation.status
    : null;
  const failure = typeof operation?.safe_failure_category === "string" &&
      SAFE_FAILURES.has(operation.safe_failure_category)
    ? operation.safe_failure_category
    : null;
  const deletionStatus = typeof deletion?.status === "string" &&
      DELETION_STATUSES.has(deletion.status)
    ? deletion.status
    : null;
  const profile = safeProfile(profiles[0]);
  const authBanStatus = typeof authBan?.status === "string" &&
      AUTH_BAN_STATUSES.has(authBan.status)
    ? authBan.status
    : null;
  if (authBan && authBanStatus === null) {
    throw new AdminHttpError("request_failed", 500);
  }
  return {
    customer: {
      ...profile,
      gmail_connected: gmailConnected,
      gmail_last_status: operationStatus,
      gmail_last_failure_category: failure,
      gmail_last_updated_at: operation
        ? safeTimestamp(operation.updated_at)
        : null,
      owned_card_count: cards,
      statement_count: statements,
      processed_statement_count: processedStatements,
      email_count: emails,
      processed_email_count: processedEmails,
      latest_statement_at: latestStatement,
      latest_email_at: latestEmail,
      deletion_status: deletionStatus,
      deletion_updated_at: deletion ? safeTimestamp(deletion.updated_at) : null,
      auth_ban_status: authBanStatus,
      auth_ban_updated_at: authBan ? safeTimestamp(authBan.updated_at) : null,
    },
  };
}

async function attemptAuthBan(
  context: AdminActionContext,
  targetId: string,
  attemptRequestId: string,
) {
  const { data: claimed, error: claimError } = await context.db.rpc(
    "claim_admin_auth_ban",
    {
      _target_user_id: targetId,
      _attempt_actor_id: context.actor.id,
      _attempt_request_id: attemptRequestId,
    },
  );
  if (claimError) throw mapDatabaseError(claimError);
  const claim = record(claimed);
  if (
    !claim || claim.user_id !== targetId || typeof claim.id !== "string" ||
    !UUID.test(claim.id) ||
    !["processing", "failed", "completed"].includes(String(claim.status)) ||
    typeof claim.claimed !== "boolean" ||
    (claim.claimed &&
      (typeof claim.claim_token !== "string" || !UUID.test(claim.claim_token)))
  ) {
    throw new AdminHttpError("request_failed", 500);
  }
  if (claim.status === "completed") {
    return { user_id: targetId, is_active: false, auth_banned: true };
  }
  if (claim.status === "failed") {
    throw new AdminHttpError("auth_ban_pending", 502);
  }
  if (!claim.claimed) throw new AdminHttpError("auth_ban_pending", 502);
  let succeeded = false;
  if (context.authAdmin) {
    try {
      const response = await withTimeout(
        context.authAdmin.updateUserById(targetId, {
          ban_duration: "876000h",
        }),
        30_000,
      );
      succeeded = !response.error;
    } catch {
      succeeded = false;
    }
  }
  const { data: completed, error: completeError } = await context.db.rpc(
    "complete_admin_auth_ban",
    {
      _ban_id: claim.id,
      _claim_token: claim.claim_token,
      _succeeded: succeeded,
      _safe_failure_category: succeeded ? null : "auth_provider_unavailable",
    },
  );
  if (completeError) throw mapDatabaseError(completeError);
  const receipt = record(completed);
  if (
    receipt?.user_id !== targetId ||
    receipt?.auth_ban_status !== (succeeded ? "completed" : "failed")
  ) {
    throw new AdminHttpError("request_failed", 500);
  }
  if (!succeeded) throw new AdminHttpError("auth_ban_pending", 502);
  return { user_id: targetId, is_active: false, auth_banned: true };
}

async function withTimeout<T>(value: PromiseLike<T>, milliseconds: number) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      Promise.resolve(value),
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error("timeout")), milliseconds);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

async function customerMutation(
  body: JsonRecord,
  context: AdminActionContext,
  action: string,
  payload: JsonRecord,
  mutationReason: string | null,
) {
  const targetId = uuid(body.target_id);
  const { data, error } = await context.db.rpc("admin_customer_action", {
    _actor_id: context.actor.id,
    _request_id: uuid(body.request_id),
    _action: action,
    _target_user_id: targetId,
    _payload: payload,
    _reason: mutationReason,
    _observed_updated_at: timestamp(body.observed_updated_at),
  });
  if (error) throw mapDatabaseError(error);
  return { targetId, receipt: record(data) };
}

export async function handleCustomerRetry(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set(["action", "target_id", "request_id", "observed_updated_at"]),
  );
  const { receipt } = await customerMutation(
    body,
    context,
    "request_gmail_sync",
    {},
    null,
  );
  if (
    !receipt || typeof receipt.request_id !== "string" ||
    !UUID.test(receipt.request_id) ||
    (receipt.status !== "queued" && receipt.status !== "claimed")
  ) throw new AdminHttpError("request_failed", 500);
  return { result: { request_id: receipt.request_id, status: receipt.status } };
}

export async function handleCustomerDisable(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set([
      "action",
      "target_id",
      "confirmation_user_id",
      "request_id",
      "observed_updated_at",
      "reason",
    ]),
  );
  const targetId = uuid(body.target_id);
  if (uuid(body.confirmation_user_id) !== targetId) invalid();
  const result = await customerMutation(
    body,
    context,
    "disable_account",
    {},
    reason(body.reason),
  );
  if (
    result.targetId !== targetId || result.receipt?.user_id !== targetId ||
    result.receipt?.is_active !== false ||
    result.receipt?.containment !== "database_contained" ||
    !["pending", "processing", "failed", "completed"].includes(
      String(result.receipt?.auth_ban_status),
    )
  ) throw new AdminHttpError("request_failed", 500);
  const banId = result.receipt?.auth_ban_id;
  if (typeof banId !== "string" || !UUID.test(banId)) {
    throw new AdminHttpError("request_failed", 500);
  }
  return { result: await attemptAuthBan(context, targetId, banId) };
}

export async function handleCustomerAuthBanRetry(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(body, new Set(["action", "target_id", "request_id"]));
  const requestId = uuid(body.request_id);
  const targetId = uuid(body.target_id);
  return { result: await attemptAuthBan(context, targetId, requestId) };
}

export async function handleCustomerDeletionStatus(
  body: JsonRecord,
  context: AdminActionContext,
) {
  onlyKeys(
    body,
    new Set([
      "action",
      "target_id",
      "confirmation_user_id",
      "request_id",
      "observed_updated_at",
      "status",
      "reason",
    ]),
  );
  if (typeof body.status !== "string" || !DELETION_STATUSES.has(body.status)) {
    invalid();
  }
  const confirmedTargetId = uuid(body.confirmation_user_id);
  if (confirmedTargetId !== uuid(body.target_id)) invalid();
  const { targetId, receipt } = await customerMutation(
    body,
    context,
    "set_deletion_status",
    { status: body.status },
    reason(body.reason),
  );
  if (
    receipt?.user_id !== targetId || receipt?.status !== body.status ||
    safeTimestamp(receipt.updated_at) === null
  ) throw new AdminHttpError("request_failed", 500);
  return {
    result: {
      user_id: targetId,
      status: body.status,
      updated_at: receipt.updated_at,
    },
  };
}

export const customerActionHandlers: Readonly<
  Record<string, AdminActionHandler>
> = Object.freeze(Object.assign(Object.create(null), {
  "customer-search": handleCustomerSearch,
  "customer-detail": handleCustomerDetail,
  "customer-retry": handleCustomerRetry,
  "customer-disable": handleCustomerDisable,
  "customer-auth-ban-retry": handleCustomerAuthBanRetry,
  "customer-deletion-status": handleCustomerDeletionStatus,
}));
