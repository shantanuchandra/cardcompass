import {
  type AdminActor,
  type AdminAuthClient,
  AdminHttpError,
} from "./types.ts";

type UserProfile = Readonly<{
  id: string;
  is_active: boolean;
  is_admin: boolean;
}>;

type ServiceDatabaseClient = Readonly<{
  from: (table: "users") => Readonly<{
    select: (columns: "id,is_active,is_admin") => Readonly<{
      eq: (column: "id", value: string) => Readonly<{
        maybeSingle: () => Promise<
          Readonly<{
            data: UserProfile | null;
            error: unknown;
          }>
        >;
      }>;
    }>;
  }>;
}>;

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

  const value = error as { code?: unknown; status?: unknown };
  if ((error as { name?: unknown }).name === "AuthSessionMissingError") {
    return true;
  }
  if (
    typeof value.code === "string" && CREDENTIAL_ERROR_CODES.has(value.code)
  ) {
    return true;
  }
  return value.status === 401 || value.status === 403;
}

export async function requireAdmin(
  request: Request,
  authDb: AdminAuthClient,
  serviceDb: ServiceDatabaseClient,
): Promise<AdminActor> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new AdminHttpError("authentication_required", 401);
  }

  const token = authorization.slice("Bearer ".length);
  let authData: Readonly<{ user: AdminActor | null }>;
  let authError: unknown;
  try {
    ({ data: authData, error: authError } = await authDb.auth.getUser(token));
  } catch {
    throw new AdminHttpError("request_failed", 500);
  }
  if (authError) {
    throw isCredentialError(authError)
      ? new AdminHttpError("authentication_required", 401)
      : new AdminHttpError("request_failed", 500);
  }
  if (!authData.user) {
    throw new AdminHttpError("authentication_required", 401);
  }

  let profile: UserProfile | null;
  let profileError: unknown;
  try {
    ({ data: profile, error: profileError } = await serviceDb
      .from("users")
      .select("id,is_active,is_admin")
      .eq("id", authData.user.id)
      .maybeSingle());
  } catch {
    throw new AdminHttpError("request_failed", 500);
  }
  if (profileError) throw new AdminHttpError("request_failed", 500);
  if (!profile?.is_active || !profile.is_admin) {
    throw new AdminHttpError("administrator_access_required", 403);
  }

  return { id: authData.user.id };
}
