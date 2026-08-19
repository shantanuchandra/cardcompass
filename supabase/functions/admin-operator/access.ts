import type { AdminActionContext } from "./types.ts";

export type AdminActionHandler = (
  body: Record<string, unknown>,
  context: AdminActionContext,
) => Promise<unknown>;

export const accessActionHandlers: Readonly<
  Record<string, AdminActionHandler>
> = {
  access: async () => ({ is_admin: true }),
};
