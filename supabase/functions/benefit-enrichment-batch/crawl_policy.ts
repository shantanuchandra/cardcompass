export type SourceRole = "primary" | "required_supporting" | "supporting";
export type SourceAttemptStatus = "success" | "not_modified" | "failed";

export type SourceAttemptInput = {
  /** Exact canonical URL passed to the trusted fetcher. Never persisted. */
  requestedUrl: string;
  /** Redirect-resolved URL used only for the sanitized display URL. */
  finalUrl?: string;
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
  /** Internally derived SHA-256 of the full canonical requested URL. */
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
  "invalid_source_url",
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
    if (
      url.protocol !== "https:" || !url.hostname || url.username ||
      url.password || url.hash
    ) return "invalid-source";
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "").slice(0, 2048);
  } catch {
    return "invalid-source";
  }
}

function bounded(
  value: string | undefined,
  maximum: number,
): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized.slice(0, maximum) : undefined;
}

function rightRotate(value: number, amount: number): number {
  return (value >>> amount) | (value << (32 - amount));
}

function sha256(value: string): string {
  const constants = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  const bytes = [...new TextEncoder().encode(value)];
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push(high >>> shift & 255);
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push(low >>> shift & 255);
  const hash = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  for (let offset = 0; offset < bytes.length; offset += 64) {
    const words = new Array<number>(64);
    for (let index = 0; index < 16; index++) {
      const start = offset + index * 4;
      words[index] = (bytes[start] << 24) | (bytes[start + 1] << 16) |
        (bytes[start + 2] << 8) | bytes[start + 3];
    }
    for (let index = 16; index < 64; index++) {
      const s0 = rightRotate(words[index - 15], 7) ^
        rightRotate(words[index - 15], 18) ^ (words[index - 15] >>> 3);
      const s1 = rightRotate(words[index - 2], 17) ^
        rightRotate(words[index - 2], 19) ^ (words[index - 2] >>> 10);
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) | 0;
    }
    let [a, b, c, d, e, f, g, h] = hash;
    for (let index = 0; index < 64; index++) {
      const s1 = rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25);
      const choice = (e & f) ^ (~e & g);
      const temp1 = (h + s1 + choice + constants[index] + words[index]) | 0;
      const s0 = rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (s0 + majority) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }
    for (const [index, value] of [a, b, c, d, e, f, g, h].entries()) {
      hash[index] = (hash[index] + value) | 0;
    }
  }
  return hash.map((part) => (part >>> 0).toString(16).padStart(8, "0"))
    .join("");
}

export function sanitizedSourceAttempt(
  attempt: SourceAttemptInput,
): SourceAttempt {
  const errorCode = attempt.errorCode && SAFE_ERROR_CODES.has(attempt.errorCode)
    ? attempt.errorCode
    : attempt.status === "failed"
    ? "unreachable"
    : undefined;
  const contentHash = bounded(attempt.contentHash, 128);
  const requestedUrl = canonicalLogicalSourceUrl(attempt.requestedUrl);
  const finalUrl = canonicalLogicalSourceUrl(
    attempt.finalUrl ?? attempt.requestedUrl,
  );
  if (!requestedUrl || !finalUrl) {
    return {
      url: "invalid-source",
      role: attempt.role,
      status: "failed",
      errorCode: "invalid_source_url",
      attemptedAt: bounded(attempt.attemptedAt, 64) ?? "",
    };
  }
  return {
    url: boundedSourceUrl(finalUrl),
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
    logicalSourceKey: sourceIdentityDigest(requestedUrl),
  };
}

function canonicalLogicalSourceUrl(value: string): string | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || !url.hostname || url.username ||
      url.password || url.hash
    ) return null;
    url.searchParams.sort();
    return url.toString().replace(/\/$/, "");
  } catch {
    return null;
  }
}

export function sourceIdentityDigest(value: string): string {
  const canonical = canonicalLogicalSourceUrl(value);
  if (!canonical) throw new Error("invalid_source_url");
  return sha256(canonical);
}

type AttemptEntry = { attempt: SourceAttempt; index: number };

function groupedAttempts(
  persisted: SourceAttempt[],
): Map<string, AttemptEntry[]> {
  const grouped = new Map<string, AttemptEntry[]>();
  for (const [index, attempt] of persisted.entries()) {
    const logicalKey = attempt.logicalSourceKey ?? `unproven:${index}`;
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
  attempts: SourceAttemptInput[],
  assessmentTime: string,
): CrawlAssessment {
  const persisted = attempts.map(sanitizedSourceAttempt);
  return assessPreparedAttempts(persisted, assessmentTime);
}

function assessPreparedAttempts(
  persisted: SourceAttempt[],
  assessmentTime: string,
): CrawlAssessment {
  const assessmentTimestamp = utcInstant(assessmentTime);
  if (assessmentTimestamp === null) {
    return {
      complete: false,
      reason: "invalid_assessment_time",
      attempts: persisted,
    };
  }
  const grouped = groupedAttempts(persisted);
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
  const persisted = attempts;
  const assessmentTimestamp = utcInstant(assessmentTime);
  if (assessmentTimestamp === null) {
    return {
      complete: false,
      reason: "invalid_assessment_time",
      attempts: persisted.slice(0, limit),
    };
  }
  const grouped = groupedAttempts(persisted);
  const decisive: AttemptEntry[] = [];
  const optional: AttemptEntry[] = [];
  for (const entries of grouped.values()) {
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
      url: "invalid-source",
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
  return assessPreparedAttempts(compacted, assessmentTime);
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
