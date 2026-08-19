export type ActiveProfileState =
  | "active"
  | "inactive"
  | "missing"
  | "unavailable";

export async function readActiveProfile(
  db: any,
  capturedUserId: string,
): Promise<ActiveProfileState> {
  try {
    const { data, error } = await db.from("users").select("id,is_active")
      .eq("id", capturedUserId).maybeSingle();
    if (error) return "unavailable";
    if (!data || data.id !== capturedUserId) return "missing";
    if (data.is_active === true) return "active";
    if (data.is_active === false) return "inactive";
    return "unavailable";
  } catch {
    return "unavailable";
  }
}

export class ActiveProfileError extends Error {
  constructor(
    readonly code: "account_inactive" | "profile_unavailable",
    readonly status: 403 | 503,
  ) {
    super(code);
  }
}

export async function requireActiveProfile(db: any, capturedUserId: string) {
  const state = await readActiveProfile(db, capturedUserId);
  if (state === "active") return;
  if (state === "inactive") {
    throw new ActiveProfileError("account_inactive", 403);
  }
  throw new ActiveProfileError("profile_unavailable", 503);
}
