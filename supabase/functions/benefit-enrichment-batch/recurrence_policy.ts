export type ObservationOutcome =
  | "success"
  | "not_modified"
  | "blocked"
  | "missing"
  | "failed";

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;

/**
 * Cross-runtime jitter contract: lowercase and trim the card identifier,
 * encode it as UTF-8, sum its unsigned bytes, then map the sum into the
 * inclusive [-radius, +radius] range. PostgreSQL implements the same steps.
 */
export function deterministicCardJitterDays(
  cardId: string,
  radius: number,
): number {
  const normalized = cardId.trim().toLowerCase();
  if (!normalized || !Number.isInteger(radius) || radius < 0 || radius > 31) {
    throw new Error("invalid_recurrence_policy");
  }
  const byteTotal = new TextEncoder().encode(normalized).reduce(
    (total, byte) => total + byte,
    0,
  );
  return (byteTotal % (2 * radius + 1)) - radius;
}

export function nextObservationAt(input: {
  cardId: string;
  completedAt: string;
  acquisitionStatus: "available" | "discontinued";
  hasActiveCardholder: boolean;
  outcome: ObservationOutcome;
}): string | null {
  const completed = Date.parse(input.completedAt);
  if (
    !Number.isFinite(completed) ||
    !/(?:Z|[+-]\d{2}:\d{2})$/i.test(input.completedAt) ||
    completed > Date.now() + MAX_CLOCK_SKEW_MS
  ) {
    throw new Error("invalid_completed_at");
  }
  if (
    input.acquisitionStatus !== "available" &&
    input.acquisitionStatus !== "discontinued"
  ) {
    throw new Error("invalid_recurrence_policy");
  }
  if (
    input.acquisitionStatus === "discontinued" && !input.hasActiveCardholder
  ) {
    return null;
  }

  const longCadence = input.outcome === "success" ||
    input.outcome === "not_modified";
  if (
    !longCadence &&
    input.outcome !== "blocked" &&
    input.outcome !== "missing" &&
    input.outcome !== "failed"
  ) {
    throw new Error("invalid_recurrence_policy");
  }
  const baseDays = longCadence ? 30 : 7;
  const jitter = deterministicCardJitterDays(input.cardId, longCadence ? 3 : 1);
  return new Date(completed + (baseDays + jitter) * DAY_MS).toISOString();
}
