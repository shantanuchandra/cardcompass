export type AdminActor = Readonly<{ id: string }>;

export type AdminDatabaseError = Readonly<{ message?: string }>;

export type AdminDatabaseClient = Readonly<{
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<
    Readonly<{
      data: unknown;
      error: AdminDatabaseError | null;
    }>
  >;
}>;

export type AdminActionContext = Readonly<{
  actor: AdminActor;
  requestId: string | null;
  db: AdminDatabaseClient;
}>;

export type AdminHttpErrorCode =
  | "authentication_required"
  | "administrator_access_required"
  | "invalid_request"
  | "not_found"
  | "state_conflict"
  | "reason_required"
  | "request_failed";

export class AdminHttpError extends Error {
  constructor(
    public readonly code: AdminHttpErrorCode,
    public readonly status: number,
  ) {
    super(code);
    this.name = "AdminHttpError";
  }
}
