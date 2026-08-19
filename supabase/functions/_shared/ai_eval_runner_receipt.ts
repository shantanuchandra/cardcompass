type JsonRecord = Record<string, unknown>;

function exact(row: JsonRecord, keys: readonly string[]): boolean {
  return Object.keys(row).length === keys.length &&
    Object.keys(row).every((key) => keys.includes(key));
}

function processed(value: unknown): boolean {
  return Number.isSafeInteger(value) && (value as number) >= 0 &&
    (value as number) <= 5;
}

/** Validates only the private runner's documented, non-sensitive receipts. */
export function validateAiEvalRunnerReceipt(
  httpStatus: number,
  value: unknown,
  expectedRunId: string,
): void {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("eval_worker_schedule_failed");
  }
  const row = value as JsonRecord;
  if (row.run_id !== expectedRunId || !processed(row.processed)) {
    throw new Error("eval_worker_schedule_failed");
  }
  const status = row.status;
  const running = httpStatus === 202 && status === "running" &&
    exact(row, ["run_id", "status", "processed", "continuation_required"]) &&
    row.continuation_required === true;
  const safeNonClaim = httpStatus === 202 &&
    (status === "not_claimed" || status === "cancelled") &&
    exact(row, ["run_id", "status", "processed"]);
  const terminal = httpStatus === 200 &&
    ["completed", "completed_with_failures", "failed", "cancelled"].includes(
      String(status),
    ) && exact(row, ["run_id", "status", "processed"]);
  const costStop = httpStatus === 200 && status === "completed_with_failures" &&
    exact(row, [
      "run_id",
      "status",
      "processed",
      "safe_failure_category",
    ]) && row.safe_failure_category === "cost_ceiling_reached";
  if (!running && !safeNonClaim && !terminal && !costStop) {
    throw new Error("eval_worker_schedule_failed");
  }
}
