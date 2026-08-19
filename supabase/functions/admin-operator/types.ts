export type AdminActor = Readonly<{ id: string }>;

export type AdminAuthClient = Readonly<{
  auth: Readonly<{
    getUser: (token: string) => Promise<
      Readonly<{
        data: Readonly<{ user: AdminActor | null }>;
        error: unknown;
      }>
    >;
  }>;
}>;

export type AdminDatabaseError = Readonly<{ message?: string }>;

export type AdminDatabaseResult<T = unknown> = Readonly<{
  data: T;
  error: AdminDatabaseError | null;
}>;

export type AdminDatabaseFilter = Readonly<{
  eq: (column: string, value: unknown) => AdminDatabaseFilter;
  order: (
    column: string,
    options?: Readonly<{ ascending?: boolean; nullsFirst?: boolean }>,
  ) => AdminDatabaseFilter;
  range: (
    from: number,
    to: number,
  ) => PromiseLike<AdminDatabaseResult<unknown[]>>;
}>;

export type AdminDatabaseTable = Readonly<{
  select: (columns: string) => AdminDatabaseFilter;
}>;

export type AdminDatabaseClient = Readonly<{
  from: (table: string) => AdminDatabaseTable;
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<AdminDatabaseResult>;
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
