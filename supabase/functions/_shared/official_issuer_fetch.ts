import { canonicalOfficialUrl } from "./card_discovery.ts";

export type OfficialContentPurpose = "document" | "html" | "sitemap";

export type OfficialFetchInput = {
  issuer: string;
  url: string;
  contentPurpose?: OfficialContentPurpose;
  maxBytes?: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  resolveHost?: (host: string) => Promise<string[]>;
  robotsAllowed?: (url: string) => Promise<boolean> | boolean;
  parserVersion?: string;
  previous?: {
    parserVersion: string;
    etag?: string;
    lastModified?: string;
    reusableExtraction: boolean;
  };
  forceUnconditional?: boolean;
  now?: () => number;
};

export type OfficialFetchResult = {
  status: number;
  submittedUrl: string;
  finalUrl: string;
  canonicalUrl: string;
  contentType?: string;
  bytes?: Uint8Array;
  text?: string;
  contentHash?: string;
  retrievedAt: string;
  etag?: string;
  lastModified?: string;
  notModified: boolean;
};

export type OfficialFetchAttempt = {
  status?: number;
  code?: string;
  attemptedAt: string;
  retryAfterMs?: number;
};

export type OfficialFetchObservation = {
  disposition:
    | "success"
    | "not_modified"
    | "review_required"
    | "blocked"
    | "failed";
  result?: OfficialFetchResult;
  attempts: OfficialFetchAttempt[];
  reviewReason?: string;
};

export type OfficialFetchObservationInput = OfficialFetchInput & {
  parserVersion: string;
  delay?: (milliseconds: number) => Promise<void> | void;
  maxAttempts?: number;
  maxBackoffMs?: number;
};

export class OfficialFetchError extends Error {
  code: string;
  httpStatus?: number;
  retryAfter?: string;

  constructor(
    code: string,
    options: { httpStatus?: number; retryAfter?: string } = {},
  ) {
    super(code);
    this.name = "OfficialFetchError";
    this.code = code;
    this.httpStatus = options.httpStatus;
    this.retryAfter = options.retryAfter;
  }
}

function decodePdfLiteral(value: string): string {
  return value.replace(/\\([0-7]{1,3}|[nrtbf()\\])/g, (_match, escaped) => {
    if (/^[0-7]+$/.test(escaped)) {
      return String.fromCharCode(Number.parseInt(escaped, 8));
    }
    return ({ n: "\n", r: "\r", t: "\t", b: "\b", f: "\f" } as Record<
      string,
      string
    >)[
      escaped
    ] ?? escaped;
  });
}

function textOperators(value: string): string[] {
  const parts: string[] = [];
  for (const match of value.matchAll(/\(((?:\\.|[^\\)])*)\)\s*Tj\b/gs)) {
    parts.push(decodePdfLiteral(match[1] ?? ""));
  }
  for (const match of value.matchAll(/\[((?:.|\n|\r)*?)\]\s*TJ\b/g)) {
    for (const literal of (match[1] ?? "").matchAll(/\(((?:\\.|[^\\)])*)\)/g)) {
      parts.push(decodePdfLiteral(literal[1] ?? ""));
    }
  }
  return parts;
}

async function inflatePdfStream(bytes: Uint8Array): Promise<string | null> {
  try {
    const stream = new Blob([bytes.slice().buffer]).stream()
      .pipeThrough(new DecompressionStream("deflate"));
    const reader = stream.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > 1_000_000) {
          await reader.cancel();
          return null;
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    const inflated = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      inflated.set(chunk, offset);
      offset += chunk.length;
    }
    return new TextDecoder("latin1").decode(inflated);
  } catch {
    return null;
  }
}

async function extractPdfText(bytes: Uint8Array): Promise<string> {
  const raw = new TextDecoder("latin1").decode(bytes);
  if (!raw.startsWith("%PDF-")) throw new Error("unsupported_content");
  const parts = textOperators(raw);
  for (const match of raw.matchAll(/stream\r?\n([\s\S]*?)\r?\nendstream/g)) {
    const streamStart = match.index ?? 0;
    const dictionary = raw.slice(Math.max(0, streamStart - 500), streamStart);
    if (!/\/FlateDecode\b/.test(dictionary)) continue;
    const encoded = new Uint8Array(
      [...(match[1] ?? "")].map((character) => character.charCodeAt(0) & 0xff),
    );
    const inflated = await inflatePdfStream(encoded);
    if (inflated) parts.push(...textOperators(inflated));
  }
  return parts.join(" ").replace(/[\u0000-\u001f]+/g, " ")
    .replace(/\s+/g, " ").trim().slice(0, 1_000_000);
}

export async function officialResourceText(
  resource: OfficialFetchResult,
): Promise<string> {
  if (resource.contentType !== "application/pdf") return resource.text ?? "";
  if (!resource.bytes) return "";
  try {
    return await extractPdfText(resource.bytes);
  } catch {
    return "";
  }
}

type OfficialFetchCode =
  | "unapproved_domain"
  | "private_address"
  | "redirect_rejected"
  | "unsupported_content"
  | "oversized"
  | "timeout"
  | "unreachable"
  | "http_401"
  | "http_403"
  | "http_404"
  | "http_410"
  | "http_429"
  | "http_5xx"
  | "soft_404"
  | "challenge_page"
  | "empty_shell"
  | "unsupported_charset"
  | "robots_disallowed"
  | "identity_review";

type ContentPolicy = {
  accept: string;
  contentTypes: Set<string>;
};

const DEFAULT_MAX_BYTES = 8 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 12_000;
const MAX_REDIRECTS = 4;
const CONTENT_POLICIES: Record<OfficialContentPurpose, ContentPolicy> = {
  document: {
    accept: "text/html,application/xhtml+xml,application/pdf;q=0.8",
    contentTypes: new Set([
      "text/html",
      "application/xhtml+xml",
      "application/pdf",
    ]),
  },
  html: {
    accept: "text/html,application/xhtml+xml",
    contentTypes: new Set(["text/html", "application/xhtml+xml"]),
  },
  sitemap: {
    accept: "application/xml,text/xml;q=0.9",
    contentTypes: new Set(["application/xml", "text/xml"]),
  },
};

function fetchError(
  code: OfficialFetchCode,
  options: { httpStatus?: number; retryAfter?: string } = {},
): OfficialFetchError {
  return new OfficialFetchError(code, options);
}

function isPrivateAddress(address: string): boolean {
  const value = address.trim().toLowerCase().replace(/^\[|\]$/g, "");
  const mappedIpv4 = value.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mappedIpv4) return isPrivateAddress(mappedIpv4[1]);
  const ipv4 = value.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (ipv4) {
    const octets = ipv4.slice(1).map(Number);
    if (octets.some((part) => part < 0 || part > 255)) return true;
    const [first, second] = octets;
    return first === 0 || first === 10 || first === 127 ||
      (first === 100 && second >= 64 && second <= 127) ||
      (first === 169 && second === 254) ||
      (first === 172 && second >= 16 && second <= 31) ||
      (first === 192 && second === 0) ||
      (first === 192 && second === 168) ||
      (first === 198 && (second === 18 || second === 19)) ||
      first >= 224;
  }
  return value === "::" || value === "::1" ||
    /^fc|^fd/.test(value) || /^fe[89ab]/.test(value) || /^ff/.test(value);
}

async function defaultResolveHost(host: string): Promise<string[]> {
  // Supabase Edge fetch does not expose peer pinning. We therefore reject unsafe
  // DNS answers before each request, while issuer-domain allowlisting remains the
  // supported boundary against DNS rebinding between resolution and connection.
  const responses = await Promise.allSettled([
    Deno.resolveDns(host, "A"),
    Deno.resolveDns(host, "AAAA"),
  ]);
  return responses.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
}

function raceWithDeadline<T>(
  operation: Promise<T>,
  signal: AbortSignal,
): Promise<T> {
  if (signal.aborted) return Promise.reject(fetchError("timeout"));
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => {
      cleanup();
      reject(fetchError("timeout"));
    };
    const cleanup = () => signal.removeEventListener("abort", onAbort);
    signal.addEventListener("abort", onAbort, { once: true });
    operation.then(
      (value) => {
        cleanup();
        resolve(value);
      },
      (error) => {
        cleanup();
        reject(error);
      },
    );
  });
}

async function ensurePublicHost(
  url: string,
  resolveHost: (host: string) => Promise<string[]>,
  signal: AbortSignal,
): Promise<void> {
  let addresses: string[];
  try {
    addresses = await raceWithDeadline(
      resolveHost(new URL(url).hostname),
      signal,
    );
  } catch (error) {
    if (
      signal.aborted || (error instanceof Error && error.message === "timeout")
    ) {
      throw fetchError("timeout");
    }
    throw fetchError("unreachable");
  }
  if (addresses.length === 0) throw fetchError("unreachable");
  if (addresses.some(isPrivateAddress)) throw fetchError("private_address");
}

function cancelResponseBody(response: Response): void {
  try {
    void response.body?.cancel().catch(() => undefined);
  } catch {
    // Cancellation is best-effort; the primary failure remains deterministic.
  }
}

function cancelReader(reader: ReadableStreamDefaultReader<Uint8Array>): void {
  try {
    void reader.cancel().catch(() => undefined);
  } catch {
    // Cancellation is best-effort; the primary failure remains deterministic.
  }
}

function releaseReader(reader: ReadableStreamDefaultReader<Uint8Array>): void {
  try {
    reader.releaseLock();
  } catch {
    // A timed-out read can still own the lock; do not replace its failure code.
  }
}

async function readResponseBytes(
  response: Response,
  maxBytes: number,
  controller: AbortController,
): Promise<Uint8Array> {
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await raceWithDeadline(
        reader.read(),
        controller.signal,
      );
      if (done) break;
      const nextLength = length + value.length;
      if (nextLength > maxBytes) {
        controller.abort();
        cancelReader(reader);
        throw fetchError("oversized");
      }
      chunks.push(value);
      length = nextLength;
    }
  } catch (error) {
    if (controller.signal.aborted) cancelReader(reader);
    throw error;
  } finally {
    releaseReader(reader);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes.slice().buffer as ArrayBuffer,
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function canonicalInitialUrl(issuer: string, url: string): string {
  try {
    return canonicalOfficialUrl(issuer, url);
  } catch {
    throw fetchError("unapproved_domain");
  }
}

function canonicalRedirectUrl(issuer: string, url: string): string {
  try {
    return canonicalOfficialUrl(issuer, url);
  } catch {
    throw fetchError("redirect_rejected");
  }
}

function displayUrl(value: string): string {
  const url = new URL(value);
  url.username = "";
  url.password = "";
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/$/, "");
}

function boundedHeader(value: string | null): string | undefined {
  const normalized = value?.replace(/[\r\n\u0000-\u001f\u007f]/g, "").trim();
  return normalized ? normalized.slice(0, 512) : undefined;
}

function contentMetadata(value: string | null): {
  mime: string;
  charset?: string;
} {
  if (!value || !value.includes("/")) throw fetchError("unsupported_content");
  const parts = value.split(";").map((part) => part.trim());
  const mime = parts.shift()?.toLowerCase() ?? "";
  const charsetPart = parts.find((part) => /^charset\s*=/i.test(part));
  const charset = charsetPart?.replace(/^charset\s*=\s*/i, "")
    .replace(/^['"]|['"]$/g, "").toLowerCase();
  return { mime, ...(charset ? { charset } : {}) };
}

function decodeText(bytes: Uint8Array, charset?: string): string {
  const normalized = charset === "iso-8859-1" ? "windows-1252" : charset;
  try {
    return new TextDecoder(normalized || "utf-8", { fatal: true }).decode(
      bytes,
    );
  } catch {
    throw fetchError("unsupported_charset");
  }
}

function validateHtmlBody(text: string): void {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (
    /(?:page\s+not\s+found|error\s*404|<h1[^>]*>\s*404\b|requested\s+page\s+(?:does\s+not\s+exist|was\s+not\s+found))/i
      .test(normalized)
  ) throw fetchError("soft_404", { httpStatus: 200 });
  if (
    /(?:captcha|access\s+denied|verify\s+(?:you\s+are\s+)?human|cloudflare\s+ray|<input[^>]+type=["']password|<form[^>]+(?:login|sign[-_ ]?in))/i
      .test(normalized)
  ) throw fetchError("challenge_page", { httpStatus: 200 });
  const withoutScripts = normalized
    .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ").replace(/&nbsp;/gi, " ").trim();
  if (/<script\b/i.test(normalized) && withoutScripts.length < 20) {
    throw fetchError("empty_shell", { httpStatus: 200 });
  }
}

function statusError(response: Response): OfficialFetchError {
  const status = response.status;
  const code: OfficialFetchCode = status === 401
    ? "http_401"
    : status === 403
    ? "http_403"
    : status === 404
    ? "http_404"
    : status === 410
    ? "http_410"
    : status === 429
    ? "http_429"
    : status >= 500
    ? "http_5xx"
    : "unreachable";
  return fetchError(code, {
    httpStatus: status,
    ...(status === 429
      ? { retryAfter: boundedHeader(response.headers.get("retry-after")) }
      : {}),
  });
}

function conditionalHeaders(input: OfficialFetchInput): Record<string, string> {
  if (
    input.forceUnconditional || !input.previous || !input.parserVersion ||
    input.previous.parserVersion !== input.parserVersion
  ) return {};
  return {
    ...(boundedHeader(input.previous.etag ?? null)
      ? { "If-None-Match": boundedHeader(input.previous.etag ?? null)! }
      : {}),
    ...(boundedHeader(input.previous.lastModified ?? null)
      ? {
        "If-Modified-Since": boundedHeader(
          input.previous.lastModified ?? null,
        )!,
      }
      : {}),
  };
}

function redirectNeedsIdentityReview(value: string): boolean {
  const path = new URL(value).pathname.replace(/\/$/, "").toLowerCase();
  return /\/(?:login|log-in|signin|sign-in|apply|application)(?:\/|$)/.test(
    path,
  ) || /^\/(?:cards?\/credit-cards?|credit-cards?)$/.test(path);
}

export async function fetchOfficialIssuerResource(
  input: OfficialFetchInput,
): Promise<OfficialFetchResult> {
  const exactSubmittedUrl = input.url.trim();
  const submittedRequestUrl = canonicalInitialUrl(
    input.issuer,
    exactSubmittedUrl,
  );
  const maxBytes = input.maxBytes ?? DEFAULT_MAX_BYTES;
  const timeoutMs = input.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const fetchImpl = input.fetchImpl ?? fetch;
  const resolveHost = input.resolveHost ?? defaultResolveHost;
  const contentPolicy = CONTENT_POLICIES[input.contentPurpose ?? "document"];
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let url = submittedRequestUrl;
  const visited = new Set<string>();

  try {
    for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
      if (visited.has(url)) throw fetchError("redirect_rejected");
      visited.add(url);
      if (input.robotsAllowed) {
        try {
          if (!await input.robotsAllowed(url)) {
            throw fetchError("robots_disallowed");
          }
        } catch (error) {
          if (error instanceof OfficialFetchError) throw error;
          throw fetchError("robots_disallowed");
        }
      }
      await ensurePublicHost(url, resolveHost, controller.signal);
      let response: Response;
      try {
        response = await raceWithDeadline(
          fetchImpl(url, {
            redirect: "manual",
            headers: {
              "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
              Accept: contentPolicy.accept,
              ...conditionalHeaders(input),
            },
            signal: controller.signal,
          }),
          controller.signal,
        );
      } catch (error) {
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError") ||
          (error instanceof Error && error.message === "timeout")
        ) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }

      const retrievedAt = new Date((input.now ?? Date.now)()).toISOString();
      if (response.status === 304) {
        cancelResponseBody(response);
        return {
          status: 304,
          submittedUrl: exactSubmittedUrl,
          finalUrl: url,
          canonicalUrl: displayUrl(url),
          retrievedAt,
          etag: boundedHeader(response.headers.get("etag")) ??
            boundedHeader(input.previous?.etag ?? null),
          lastModified: boundedHeader(response.headers.get("last-modified")) ??
            boundedHeader(input.previous?.lastModified ?? null),
          notModified: true,
        };
      }
      if (response.status >= 300 && response.status < 400) {
        cancelResponseBody(response);
        if (redirects >= MAX_REDIRECTS) {
          throw fetchError("redirect_rejected");
        }
        const location = response.headers.get("location");
        if (!location) throw fetchError("redirect_rejected");
        let redirectUrl: string;
        try {
          redirectUrl = new URL(location, url).toString();
        } catch {
          throw fetchError("redirect_rejected");
        }
        url = canonicalRedirectUrl(input.issuer, redirectUrl);
        if (redirectNeedsIdentityReview(url)) {
          throw fetchError("identity_review");
        }
        continue;
      }

      if (!response.ok) {
        cancelResponseBody(response);
        throw statusError(response);
      }
      const metadata = contentMetadata(response.headers.get("content-type"));
      const contentType = metadata.mime;
      if (!contentPolicy.contentTypes.has(contentType)) {
        cancelResponseBody(response);
        throw fetchError("unsupported_content");
      }
      const declaredBytes = Number(response.headers.get("content-length") ?? 0);
      if (declaredBytes > maxBytes) {
        controller.abort();
        cancelResponseBody(response);
        throw fetchError("oversized");
      }

      let bytes: Uint8Array;
      try {
        bytes = await readResponseBytes(response, maxBytes, controller);
      } catch (error) {
        if (error instanceof Error && error.message === "oversized") {
          throw error;
        }
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError") ||
          (error instanceof Error && error.message === "timeout")
        ) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }

      const result: OfficialFetchResult = {
        status: response.status,
        submittedUrl: exactSubmittedUrl,
        finalUrl: url,
        canonicalUrl: displayUrl(url),
        contentType,
        bytes,
        text: contentType === "application/pdf"
          ? ""
          : decodeText(bytes, metadata.charset),
        contentHash: await sha256(bytes),
        retrievedAt,
        etag: boundedHeader(response.headers.get("etag")),
        lastModified: boundedHeader(response.headers.get("last-modified")),
        notModified: false,
      };
      result.text = await officialResourceText(result);
      if (
        contentType === "text/html" || contentType === "application/xhtml+xml"
      ) {
        validateHtmlBody(result.text);
      }
      return result;
    }
    throw fetchError("redirect_rejected");
  } finally {
    clearTimeout(timeout);
  }
}

function retryAfterMilliseconds(
  value: string | undefined,
  now: number,
  maximum: number,
): number {
  if (!value) return 0;
  const seconds = Number(value);
  const parsed = Number.isFinite(seconds) && seconds >= 0
    ? seconds * 1000
    : Date.parse(value) - now;
  return Math.min(maximum, Math.max(0, Number.isFinite(parsed) ? parsed : 0));
}

/** Executes the bounded source-observation retry matrix without hiding attempts. */
export async function fetchOfficialIssuerObservation(
  input: OfficialFetchObservationInput,
): Promise<OfficialFetchObservation> {
  const maxAttempts = Math.min(6, Math.max(1, input.maxAttempts ?? 3));
  const maxBackoffMs = Math.min(
    120_000,
    Math.max(0, input.maxBackoffMs ?? 30_000),
  );
  const delay = input.delay ??
    ((milliseconds: number) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)));
  const now = input.now ?? Date.now;
  const attempts: OfficialFetchAttempt[] = [];
  let forceUnconditional = input.forceUnconditional === true;
  let unusable304Fallback = false;

  for (let index = 0; index < maxAttempts; index += 1) {
    try {
      const result = await fetchOfficialIssuerResource({
        ...input,
        forceUnconditional,
      });
      attempts.push({ status: result.status, attemptedAt: result.retrievedAt });
      if (result.notModified) {
        const reusable304 = input.previous?.reusableExtraction === true &&
          input.previous.parserVersion === input.parserVersion &&
          Boolean(input.previous.etag || input.previous.lastModified) &&
          !forceUnconditional;
        if (reusable304) {
          return { disposition: "not_modified", result, attempts };
        }
        if (!forceUnconditional && index + 1 < maxAttempts) {
          forceUnconditional = true;
          unusable304Fallback = true;
          continue;
        }
        return {
          disposition: "failed",
          result,
          attempts,
          reviewReason: "unusable_not_modified",
        };
      }
      return { disposition: "success", result, attempts };
    } catch (error) {
      const failure = error instanceof OfficialFetchError
        ? error
        : fetchError("unreachable");
      const attemptedAt = new Date(now()).toISOString();
      const retryAfterMs = failure.code === "http_429"
        ? retryAfterMilliseconds(failure.retryAfter, now(), maxBackoffMs)
        : undefined;
      attempts.push({
        ...(failure.httpStatus ? { status: failure.httpStatus } : {}),
        code: failure.code,
        attemptedAt,
        ...(retryAfterMs !== undefined ? { retryAfterMs } : {}),
      });

      if (unusable304Fallback) {
        return { disposition: "failed", attempts, reviewReason: failure.code };
      }

      if (failure.code === "http_410") {
        return {
          disposition: "review_required",
          attempts,
          reviewReason: "http_410",
        };
      }
      if (
        failure.code === "http_401" || failure.code === "http_403" ||
        failure.code === "challenge_page" || failure.code === "empty_shell" ||
        failure.code === "robots_disallowed" ||
        failure.code === "redirect_rejected" ||
        failure.code === "private_address" ||
        failure.code === "unapproved_domain"
      ) {
        return { disposition: "blocked", attempts, reviewReason: failure.code };
      }
      if (failure.code === "soft_404") {
        const soft404Count = attempts.filter((attempt) =>
          attempt.code === "soft_404"
        ).length;
        if (soft404Count < 2 && index + 1 < maxAttempts) {
          await delay(Math.min(maxBackoffMs, 1000 * 2 ** index));
          continue;
        }
        return {
          disposition: "review_required",
          attempts,
          reviewReason: "persistent_soft_404",
        };
      }
      if (failure.code === "identity_review") {
        return {
          disposition: "review_required",
          attempts,
          reviewReason: failure.code,
        };
      }
      const retryable = failure.code === "http_404" ||
        failure.code === "http_429" || failure.code === "http_5xx" ||
        failure.code === "timeout" || failure.code === "unreachable";
      const anotherAttempt = index + 1 < maxAttempts &&
        (failure.code !== "http_404" ||
          attempts.filter((attempt) => attempt.code === "http_404").length < 2);
      if (!retryable || !anotherAttempt) {
        if (failure.code === "http_404") {
          return {
            disposition: "review_required",
            attempts,
            reviewReason: "persistent_404",
          };
        }
        return { disposition: "failed", attempts, reviewReason: failure.code };
      }
      const backoff = retryAfterMs ?? Math.min(
        maxBackoffMs,
        1000 * 2 ** index,
      );
      await delay(backoff);
    }
  }
  return { disposition: "failed", attempts, reviewReason: "retry_exhausted" };
}
