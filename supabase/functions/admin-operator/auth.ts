import { AdminHttpError, type AdminActor } from "./types.ts";

type AuthenticatedUser = Readonly<{ id: string }>;

type AuthClient = Readonly<{
  auth: Readonly<{
    getUser: (token: string) => Promise<Readonly<{
      data: Readonly<{ user: AuthenticatedUser | null }>;
      error: unknown;
    }>>;
  }>;
}>;

type UserProfile = Readonly<{
  id: string;
  is_active: boolean;
  is_admin: boolean;
}>;

type ServiceDatabaseClient = Readonly<{
  from: (table: "users") => Readonly<{
    select: (columns: "id,is_active,is_admin") => Readonly<{
      eq: (column: "id", value: string) => Readonly<{
        maybeSingle: () => Promise<Readonly<{
          data: UserProfile | null;
          error: unknown;
        }>>;
      }>;
    }>;
  }>;
}>;

export async function requireAdmin(
  request: Request,
  authDb: AuthClient,
  serviceDb: ServiceDatabaseClient,
): Promise<AdminActor> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    throw new AdminHttpError("authentication_required", 401);
  }

  const token = authorization.slice("Bearer ".length);
  let authData: Readonly<{ user: AuthenticatedUser | null }>;
  let authError: unknown;
  try {
    ({ data: authData, error: authError } = await authDb.auth.getUser(token));
  } catch {
    throw new AdminHttpError("request_failed", 500);
  }
  if (authError || !authData.user) {
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
