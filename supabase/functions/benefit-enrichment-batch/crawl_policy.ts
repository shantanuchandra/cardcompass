export type SourceRole = "primary" | "required_supporting" | "supporting";
export type SourceAttemptStatus = "success" | "not_modified" | "failed";

export type SourceAttempt = {
  url: string;
  role: SourceRole;
  status: SourceAttemptStatus;
  httpStatus?: number;
  contentHash?: string;
  etag?: string;
  lastModified?: string;
  errorCode?: string;
  attemptedAt: string;
  parserCacheReusable?: boolean;
  logicalSourceKey?: string;
};

export type CrawlAssessment = {
  complete: boolean;
  reason: string;
  attempts: SourceAttempt[];
};

const SAFE_ERROR_CODES = new Set([
  "corrupt_pdf",
  "deadline_exceeded",
  "empty_document",
  "fetch_budget_exhausted",
  "required_source_overflow",
  "decisive_attempt_overflow",
  "invalid_attempt_history",
  "http_403",
  "http_404",
  "http_410",
  "identity_mismatch",
  "insufficient_evidence",
  "js_challenge",
  "not_a_card",
  "ambiguous_product",
  "oversized",
  "private_address",
  "redirect_rejected",
  "timeout",
  "unapproved_domain",
  "unreachable",
  "unsupported_content",
]);
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
export const MAX_EVIDENCE_CLOCK_SKEW_MS = 5 * 60 * 1000;

export function sanitizedSourceErrorCode(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  return SAFE_ERROR_CODES.has(code) ? code : "unreachable";
}

export function boundedSourceUrl(value: string): string {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return "https://invalid.invalid/";
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "").slice(0, 2048);
  } catch {
    return "https://invalid.invalid/";
  }
}

function bounded(
  value: string | undefined,
  maximum: number,
): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized.slice(0, maximum) : undefined;
}

function sanitizedLogicalSourceKey(
  value: string | undefined,
): string | undefined {
  if (!value?.trim()) return undefined;
  const normalized = value.trim().toLowerCase();
  return /^[0-9a-f]{64}$/.test(normalized) ? normalized : undefined;
}

export function sanitizedSourceAttempt(attempt: SourceAttempt): SourceAttempt {
  const errorCode = attempt.errorCode && SAFE_ERROR_CODES.has(attempt.errorCode)
    ? attempt.errorCode
    : attempt.status === "failed"
    ? "unreachable"
    : undefined;
  const contentHash = bounded(attempt.contentHash, 128);
  return {
    url: boundedSourceUrl(attempt.url),
    role: attempt.role,
    status: attempt.status,
    ...(Number.isInteger(attempt.httpStatus) &&
        Number(attempt.httpStatus) >= 100 && Number(attempt.httpStatus) <= 599
      ? { httpStatus: Number(attempt.httpStatus) }
      : {}),
    ...(contentHash && /^[0-9a-f]{64}$/i.test(contentHash)
      ? { contentHash: contentHash.toLowerCase() }
      : {}),
    ...(bounded(attempt.etag, 256) ? { etag: bounded(attempt.etag, 256) } : {}),
    ...(bounded(attempt.lastModified, 128)
      ? { lastModified: bounded(attempt.lastModified, 128) }
      : {}),
    ...(errorCode ? { errorCode } : {}),
    attemptedAt: bounded(attempt.attemptedAt, 64) ?? "",
    ...(attempt.parserCacheReusable === true
      ? { parserCacheReusable: true }
      : {}),
    ...(sanitizedLogicalSourceKey(attempt.logicalSourceKey)
      ? {
        logicalSourceKey: sanitizedLogicalSourceKey(attempt.logicalSourceKey),
      }
      : {}),
  };
}

function canonicalLogicalSourceUrl(value: string): string {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return "https://invalid.invalid/";
    url.username = "";
    url.password = "";
    url.hash = "";
    url.searchParams.sort();
    return url.toString().replace(/\/$/, "");
  } catch {
    return "https://invalid.invalid/";
  }
}

function logicalSourceIdentity(
  original: SourceAttempt,
  persisted: SourceAttempt,
): string {
  if (persisted.logicalSourceKey) return `digest:${persisted.logicalSourceKey}`;
  if (persisted.role === "primary") return "primary";
  return `url:${canonicalLogicalSourceUrl(original.url)}`;
}

type AttemptEntry = { attempt: SourceAttempt; index: number };

function groupedAttempts(
  attempts: SourceAttempt[],
  persisted: SourceAttempt[],
): Map<string, AttemptEntry[]> {
  const grouped = new Map<string, AttemptEntry[]>();
  for (const [index, attempt] of persisted.entries()) {
    const logicalKey = logicalSourceIdentity(attempts[index], attempt);
    const key = `${attempt.role}:${logicalKey}`;
    grouped.set(key, [...(grouped.get(key) ?? []), { attempt, index }]);
  }
  return grouped;
}

function terminalAttempt(
  entries: AttemptEntry[],
  assessmentTimestamp: number,
): AttemptEntry | null {
  const dated = entries.map((entry) => ({
    ...entry,
    timestamp: utcInstant(entry.attempt.attemptedAt),
  }));
  if (
    dated.some((entry) =>
      entry.timestamp === null ||
      Number(entry.timestamp) > assessmentTimestamp + MAX_EVIDENCE_CLOCK_SKEW_MS
    ) || new Set(dated.map((entry) => entry.timestamp)).size !== dated.length
  ) return null;
  return dated.sort((left, right) =>
    Number(left.timestamp) - Number(right.timestamp) || left.index - right.index
  ).at(-1) ?? null;
}

function successful(attempt: SourceAttempt): boolean {
  if (utcInstant(attempt.attemptedAt) === null) return false;
  if (attempt.status === "success") {
    return (attempt.httpStatus === undefined ||
      (attempt.httpStatus >= 200 && attempt.httpStatus < 300)) &&
      Boolean(attempt.contentHash);
  }
  return attempt.status === "not_modified" && attempt.httpStatus === 304 &&
    attempt.parserCacheReusable === true && Boolean(attempt.contentHash);
}

export function assessCrawlCompleteness(
  attempts: SourceAttempt[],
  assessmentTime: string,
): CrawlAssessment {
  const persisted = attempts.map(sanitizedSourceAttempt);
  const assessmentTimestamp = utcInstant(assessmentTime);
  if (assessmentTimestamp === null) {
    return {
      complete: false,
      reason: "invalid_assessment_time",
      attempts: persisted,
    };
  }
  const grouped = groupedAttempts(attempts, persisted);
  const primaryGroups = [...grouped.entries()].filter(([key]) =>
    key.startsWith("primary:")
  );
  if (primaryGroups.length !== 1) {
    return {
      complete: false,
      reason: primaryGroups.length === 0
        ? "missing_primary"
        : "multiple_primary",
      attempts: persisted,
    };
  }
  const primary = terminalAttempt(primaryGroups[0][1], assessmentTimestamp)
    ?.attempt ?? null;
  if (!primary || !successful(primary)) {
    return {
      complete: false,
      reason: "primary_incomplete",
      attempts: persisted,
    };
  }
  const requiredGroups = [...grouped.entries()].filter(([key]) =>
    key.startsWith("required_supporting:")
  );
  if (
    requiredGroups.some(([, entries]) => {
      const latest = terminalAttempt(entries, assessmentTimestamp)?.attempt ??
        null;
      return !latest || !successful(latest);
    })
  ) {
    return {
      complete: false,
      reason: "required_supporting_incomplete",
      attempts: persisted,
    };
  }
  return { complete: true, reason: "complete", attempts: persisted };
}

export function compactSourceAttempts(
  attempts: SourceAttempt[],
  assessmentTime: string,
  maximum = 9,
): CrawlAssessment {
  const limit = Math.max(1, Math.trunc(maximum));
  const persisted = attempts.map(sanitizedSourceAttempt);
  const assessmentTimestamp = utcInstant(assessmentTime);
  if (assessmentTimestamp === null) {
    return {
      complete: false,
      reason: "invalid_assessment_time",
      attempts: persisted.slice(0, limit),
    };
  }
  const grouped = groupedAttempts(attempts, persisted);
  const decisive: AttemptEntry[] = [];
  const optional: AttemptEntry[] = [];
  for (const [key, entries] of grouped) {
    const terminal = terminalAttempt(entries, assessmentTimestamp);
    const role = entries[0].attempt.role;
    const target = role === "primary" || role === "required_supporting"
      ? decisive
      : optional;
    if (terminal) {
      target.push(terminal);
      continue;
    }
    if (target === decisive) {
      const representative = entries[0];
      target.push({
        index: representative.index,
        attempt: {
          url: representative.attempt.url,
          role,
          status: "failed",
          errorCode: "invalid_attempt_history",
          attemptedAt: assessmentTime,
          ...(representative.attempt.logicalSourceKey
            ? { logicalSourceKey: representative.attempt.logicalSourceKey }
            : {}),
        },
      });
    }
  }
  decisive.sort((left, right) =>
    Number(left.attempt.role !== "primary") -
      Number(right.attempt.role !== "primary") || left.index - right.index
  );
  optional.sort((left, right) => left.index - right.index);
  if (decisive.length > limit) {
    const retained = decisive.slice(0, limit - 1).map((entry) => entry.attempt);
    retained.push({
      url: "https://invalid.invalid/required-source-overflow",
      role: "required_supporting",
      status: "failed",
      errorCode: "decisive_attempt_overflow",
      attemptedAt: assessmentTime,
    });
    return {
      complete: false,
      reason: "decisive_attempt_overflow",
      attempts: retained,
    };
  }
  const compacted = [...decisive, ...optional.slice(0, limit - decisive.length)]
    .sort((left, right) => left.index - right.index)
    .map((entry) => entry.attempt);
  return assessCrawlCompleteness(compacted, assessmentTime);
}

export function utcInstant(value: string): number | null {
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$/,
  );
  if (!match) return null;
  const [, yearText, monthText, dayText, hourText, minuteText, secondText] =
    match;
  const parts = [
    Number(yearText),
    Number(monthText),
    Number(dayText),
    Number(hourText),
    Number(minuteText),
    Number(secondText),
  ];
  const milliseconds = Number((match[7] ?? "0").padEnd(3, "0"));
  const valueMs = Date.UTC(
    parts[0],
    parts[1] - 1,
    parts[2],
    parts[3],
    parts[4],
    parts[5],
    milliseconds,
  );
  const date = new Date(valueMs);
  if (
    date.getUTCFullYear() !== parts[0] ||
    date.getUTCMonth() + 1 !== parts[1] ||
    date.getUTCDate() !== parts[2] ||
    date.getUTCHours() !== parts[3] ||
    date.getUTCMinutes() !== parts[4] ||
    date.getUTCSeconds() !== parts[5] ||
    date.getUTCMilliseconds() !== milliseconds
  ) return null;
  return valueMs;
}

function utcDate(value: string): number | null {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const parts = match.slice(1).map(Number);
  const valueMs = Date.UTC(parts[0], parts[1] - 1, parts[2]);
  const date = new Date(valueMs);
  return date.getUTCFullYear() === parts[0] &&
      date.getUTCMonth() + 1 === parts[1] && date.getUTCDate() === parts[2]
    ? valueMs
    : null;
}

export function retirementEligibility(input: {
  explicitEndDate?: string | null;
  completeAbsenceObservedAt: string[];
  now: string;
}): { eligible: boolean; reason: string } {
  const nowMs = utcInstant(input.now);
  if (nowMs === null) return { eligible: false, reason: "invalid_now" };
  if (input.explicitEndDate != null && input.explicitEndDate !== "") {
    const endDateMs = utcDate(input.explicitEndDate);
    if (endDateMs === null) {
      return { eligible: false, reason: "invalid_explicit_end_date" };
    }
    const nowDateMs = Date.UTC(
      new Date(nowMs).getUTCFullYear(),
      new Date(nowMs).getUTCMonth(),
      new Date(nowMs).getUTCDate(),
    );
    if (endDateMs < nowDateMs) {
      return { eligible: true, reason: "explicit_past_end_date" };
    }
    return { eligible: false, reason: "explicit_end_date_not_past" };
  }

  const parsed = input.completeAbsenceObservedAt.map(utcInstant);
  if (parsed.some((value) => value === null || value > nowMs)) {
    return { eligible: false, reason: "invalid_observation_history" };
  }
  const independent = [...new Set(parsed as number[])].sort((a, b) => a - b);
  if (
    independent.length >= 2 &&
    independent[independent.length - 1] - independent[0] >= SEVEN_DAYS_MS
  ) {
    return { eligible: true, reason: "two_complete_observations" };
  }
  return { eligible: false, reason: "insufficient_complete_observations" };
}
