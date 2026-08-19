export type AdminActor = Readonly<{ id: string }>;

export type AdminAccessAuthClient = Readonly<{
  auth: Readonly<{
    getUser: (token: string) => Promise<
      Readonly<{
        data: Readonly<{ user: Readonly<{ id: string }> | null }>;
        error: unknown;
      }>
    >;
  }>;
}>;

type AdminProfile = Readonly<
  { id: string; is_active: boolean; is_admin: boolean }
>;

export type AdminAccessServiceClient = Readonly<{
  from: (table: "users") => Readonly<{
    select: (columns: "id,is_active,is_admin") => Readonly<{
      eq: (column: "id", value: string) => Readonly<{
        maybeSingle: () => Promise<
          Readonly<{ data: AdminProfile | null; error: unknown }>
        >;
      }>;
    }>;
  }>;
}>;

export type AdminAccessErrorCode =
  | "authentication_required"
  | "administrator_access_required"
  | "request_failed";

export class AdminAccessError extends Error {
  constructor(
    readonly code: AdminAccessErrorCode,
    readonly status: 401 | 403 | 500,
  ) {
    super(code);
    this.name = "AdminAccessError";
  }
}

const CREDENTIAL_ERROR_CODES = new Set([
  "bad_jwt",
  "session_expired",
  "session_not_found",
  "refresh_token_not_found",
  "refresh_token_already_used",
  "user_not_found",
]);

function isCredentialError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as { code?: unknown; status?: unknown; name?: unknown };
  return value.name === "AuthSessionMissingError" ||
    (typeof value.code === "string" &&
      CREDENTIAL_ERROR_CODES.has(value.code)) ||
    value.status === 401 || value.status === 403;
}

function isProfile(value: unknown): value is AdminProfile {
  if (!value || typeof value !== "object") return false;
  const profile = value as Record<string, unknown>;
  return typeof profile.id === "string" &&
    typeof profile.is_active === "boolean" &&
    typeof profile.is_admin === "boolean";
}

export async function resolveAdminActor(
  request: Request,
  authDb: AdminAccessAuthClient,
  serviceDb: AdminAccessServiceClient,
): Promise<AdminActor> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new AdminAccessError("authentication_required", 401);
  }
  let authResult: unknown;
  try {
    authResult = await authDb.auth.getUser(
      authorization.slice("Bearer ".length),
    );
  } catch {
    throw new AdminAccessError("request_failed", 500);
  }
  if (
    !authResult || typeof authResult !== "object" ||
    !("data" in authResult) || !("error" in authResult)
  ) {
    throw new AdminAccessError("request_failed", 500);
  }
  const typedAuthResult = authResult as Awaited<
    ReturnType<AdminAccessAuthClient["auth"]["getUser"]>
  >;
  if (typedAuthResult.error) {
    throw isCredentialError(typedAuthResult.error)
      ? new AdminAccessError("authentication_required", 401)
      : new AdminAccessError("request_failed", 500);
  }
  if (
    !typedAuthResult.data || typeof typedAuthResult.data !== "object" ||
    !("user" in typedAuthResult.data)
  ) {
    throw new AdminAccessError("request_failed", 500);
  }
  const actor = typedAuthResult.data.user;
  if (actor === null) {
    throw new AdminAccessError("authentication_required", 401);
  }
  if (typeof actor.id !== "string" || actor.id.length === 0) {
    throw new AdminAccessError("request_failed", 500);
  }
  let profileResult: unknown;
  try {
    profileResult = await serviceDb.from("users")
      .select("id,is_active,is_admin")
      .eq("id", actor.id)
      .maybeSingle();
  } catch {
    throw new AdminAccessError("request_failed", 500);
  }
  if (
    !profileResult || typeof profileResult !== "object" ||
    !("data" in profileResult) || !("error" in profileResult)
  ) {
    throw new AdminAccessError("request_failed", 500);
  }
  const typedProfileResult = profileResult as {
    data: AdminProfile | null;
    error: unknown;
  };
  if (typedProfileResult.error) {
    throw new AdminAccessError("request_failed", 500);
  }
  if (typedProfileResult.data === null) {
    throw new AdminAccessError("administrator_access_required", 403);
  }
  if (!isProfile(typedProfileResult.data)) {
    throw new AdminAccessError("request_failed", 500);
  }
  if (
    !typedProfileResult.data.is_active || !typedProfileResult.data.is_admin
  ) {
    throw new AdminAccessError("administrator_access_required", 403);
  }
  return { id: actor.id };
}
