export type AdminActor = Readonly<{ id: string }>;

export type AdminActionContext = Readonly<{
  actor: AdminActor;
  requestId: string | null;
  db: unknown;
}>;

export type AdminHttpErrorCode =
  | "authentication_required"
  | "administrator_access_required"
  | "request_failed";

export class AdminHttpError extends Error {
  constructor(public readonly code: AdminHttpErrorCode, public readonly status: number) {
    super(code);
    this.name = "AdminHttpError";
  }
}
