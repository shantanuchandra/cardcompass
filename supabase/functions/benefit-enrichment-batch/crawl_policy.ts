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

function sanitizedAttempt(attempt: SourceAttempt): SourceAttempt {
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
  };
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
): CrawlAssessment {
  const persisted = attempts.map(sanitizedAttempt);
  const primary = persisted.filter((attempt) => attempt.role === "primary");
  if (primary.length !== 1) {
    return {
      complete: false,
      reason: primary.length === 0 ? "missing_primary" : "multiple_primary",
      attempts: persisted,
    };
  }
  if (!successful(primary[0])) {
    return {
      complete: false,
      reason: "primary_incomplete",
      attempts: persisted,
    };
  }
  if (
    persisted.some((attempt) =>
      attempt.role === "required_supporting" && !successful(attempt)
    )
  ) {
    return {
      complete: false,
      reason: "required_supporting_incomplete",
      attempts: persisted,
    };
  }
  return { complete: true, reason: "complete", attempts: persisted };
}

function utcInstant(value: string): number | null {
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
