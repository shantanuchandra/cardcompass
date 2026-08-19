import {
  AdminAccessError,
  type AdminAccessServiceClient,
  resolveAdminActor,
} from "../_shared/admin_access.ts";
import {
  type AdminActor,
  type AdminAuthClient,
  AdminHttpError,
} from "./types.ts";

export async function requireAdmin(
  request: Request,
  authDb: AdminAuthClient,
  serviceDb: AdminAccessServiceClient,
): Promise<AdminActor> {
  try {
    return await resolveAdminActor(request, authDb, serviceDb);
  } catch (error) {
    if (error instanceof AdminAccessError) {
      throw new AdminHttpError(error.code, error.status);
    }
    throw error;
  }
}
