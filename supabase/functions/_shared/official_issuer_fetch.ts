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
    contentHash?: string;
    canonicalBenefitHash?: string;
    sourceIdentityHash?: string;
    finalResourceUrl?: string;
    finalResourceIdentityHash?: string;
    cardIdentityValidated?: boolean;
  };
  forceUnconditional?: boolean;
  allowedQueryParameters?: string[];
  enforceRobots?: boolean;
  deadlineAt?: number;
  now?: () => number;
  /** Internal per-observation cache; callers should not provide this. */
  _robotsCache?: Map<string, RobotsRule[]>;
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
  sourceIdentityHash?: string;
  finalResourceIdentityHash?: string;
};

export type OfficialFetchBodyResult = OfficialFetchResult & {
  notModified: false;
  text: string;
  contentHash: string;
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

export function requireOfficialFetchBody(
  result: OfficialFetchResult,
): OfficialFetchBodyResult {
  if (result.notModified || result.status === 304) {
    throw new OfficialFetchError("unusable_not_modified", {
      httpStatus: result.status,
    });
  }
  if (
    typeof result.text !== "string" ||
    (result.contentType === "application/pdf" &&
      !(result.bytes instanceof Uint8Array)) ||
    !/^[0-9a-f]{64}$/i.test(result.contentHash ?? "")
  ) throw new OfficialFetchError("unsupported_content");
  return result as OfficialFetchBodyResult;
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
  | "robots_invalid"
  | "unapproved_query"
  | "deadline_exceeded"
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

function ipv4Octets(value: string): number[] | null {
  const match = value.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!match) return null;
  const octets = match.slice(1).map(Number);
  return octets.every((part) => part >= 0 && part <= 255) ? octets : null;
}

function ipv4Value(octets: number[]): bigint {
  return octets.reduce((value, octet) => value << 8n | BigInt(octet), 0n);
}

function ipv6Value(words: number[]): bigint {
  return words.reduce((value, word) => value << 16n | BigInt(word), 0n);
}

function inCidr(
  value: bigint,
  base: bigint,
  prefix: number,
  width: number,
): boolean {
  const shift = BigInt(width - prefix);
  return value >> shift === base >> shift;
}

const NON_GLOBAL_IPV4: Array<[string, number]> = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.88.99.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];

function globallyRoutableIpv4(octets: number[]): boolean {
  const value = ipv4Value(octets);
  if (
    value === ipv4Value([192, 0, 0, 9]) ||
    value === ipv4Value([192, 0, 0, 10])
  ) return true;
  return !NON_GLOBAL_IPV4.some(([address, prefix]) =>
    inCidr(value, ipv4Value(ipv4Octets(address)!), prefix, 32)
  );
}

function ipv6Words(value: string): number[] | null {
  const normalized = value.trim().toLowerCase().replace(/^\[|\]$/g, "")
    .split("%")[0];
  if (!normalized.includes(":")) return null;
  const sides = normalized.split("::");
  if (sides.length > 2) return null;
  const parseSide = (side: string): number[] | null => {
    if (!side) return [];
    const parts = side.split(":");
    const words: number[] = [];
    for (const [index, part] of parts.entries()) {
      const ipv4 = ipv4Octets(part);
      if (ipv4 && index === parts.length - 1) {
        words.push(ipv4[0] << 8 | ipv4[1], ipv4[2] << 8 | ipv4[3]);
      } else if (/^[0-9a-f]{1,4}$/.test(part)) {
        words.push(Number.parseInt(part, 16));
      } else {
        return null;
      }
    }
    return words;
  };
  const left = parseSide(sides[0]);
  const right = parseSide(sides[1] ?? "");
  if (!left || !right) return null;
  if (sides.length === 1) return left.length === 8 ? left : null;
  const missing = 8 - left.length - right.length;
  return missing >= 1 ? [...left, ...Array(missing).fill(0), ...right] : null;
}

function isPrivateAddress(address: string): boolean {
  const value = address.trim().toLowerCase().replace(/^\[|\]$/g, "");
  const directIpv4 = ipv4Octets(value);
  if (directIpv4) return !globallyRoutableIpv4(directIpv4);
  const words = ipv6Words(value);
  if (!words) return true;
  const mapped = words.slice(0, 5).every((word) => word === 0) &&
    words[5] === 0xffff;
  if (mapped) {
    return !globallyRoutableIpv4([
      words[6] >> 8,
      words[6] & 0xff,
      words[7] >> 8,
      words[7] & 0xff,
    ]);
  }
  const value6 = ipv6Value(words);
  const cidr6 = (address: string, prefix: number) =>
    inCidr(value6, ipv6Value(ipv6Words(address)!), prefix, 128);
  const nonGlobal = [
    ["::", 128],
    ["::1", 128],
    ["64:ff9b:1::", 48],
    ["100::", 64],
    ["2001::", 32],
    ["2001:2::", 48],
    ["2001:10::", 28],
    ["2001:20::", 28],
    ["2001:db8::", 32],
    ["2002::", 16],
    ["3fff::", 20],
    ["5f00::", 16],
    ["fc00::", 7],
    ["fe80::", 10],
    ["ff00::", 8],
  ] as Array<[string, number]>;
  if (cidr6("64:ff9b::", 96)) return false;
  return !cidr6("2000::", 3) ||
    nonGlobal.some(([base, prefix]) => cidr6(base, prefix));
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

const SENSITIVE_QUERY_KEY =
  /(?:token|session|secret|password|passwd|credential|auth|signature|sig|key|code|state|nonce|gclid|fbclid|^utm_)/i;
const SAFE_FUNCTIONAL_QUERY_KEYS = new Set([
  "document",
  "doc",
  "file",
  "filename",
  "lang",
  "language",
  "locale",
  "version",
  "variant",
]);

export function approvedStoredQueryParameters(value: string): string[] {
  try {
    const keys = [...new Set(new URL(value).searchParams.keys())];
    return keys.length <= 16 &&
        keys.every((key) =>
          SAFE_FUNCTIONAL_QUERY_KEYS.has(key.toLowerCase()) &&
          !SENSITIVE_QUERY_KEY.test(key)
        )
      ? keys
      : [];
  } catch {
    return [];
  }
}

function approvedRequestUrl(
  issuer: string,
  url: string,
  allowedQueryParameters: string[] = [],
): string {
  try {
    const canonical = new URL(canonicalOfficialUrl(issuer, url));
    const allowed = new Set(
      allowedQueryParameters.map((key) => key.trim().toLowerCase()).filter(
        (key) =>
          key && SAFE_FUNCTIONAL_QUERY_KEYS.has(key) &&
          !SENSITIVE_QUERY_KEY.test(key),
      ),
    );
    const entries = [...canonical.searchParams.entries()];
    if (
      entries.some(([key]) =>
        SENSITIVE_QUERY_KEY.test(key) ||
        !SAFE_FUNCTIONAL_QUERY_KEYS.has(key.toLowerCase()) ||
        !allowed.has(key.toLowerCase())
      )
    ) throw fetchError("unapproved_query");
    const kept = entries;
    canonical.search = "";
    for (const [key, value] of kept) canonical.searchParams.append(key, value);
    return canonical.toString();
  } catch (error) {
    if (error instanceof OfficialFetchError) throw error;
    throw fetchError("unapproved_domain");
  }
}

function canonicalRedirectUrl(
  issuer: string,
  url: string,
  allowedQueryParameters: string[] = [],
): string {
  try {
    return approvedRequestUrl(issuer, url, allowedQueryParameters);
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

function safeDisplayUrl(value: string | undefined): string | null {
  try {
    return value ? displayUrl(value) : null;
  } catch {
    return null;
  }
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
  const bomCharset = bytes.length >= 3 && bytes[0] === 0xef &&
      bytes[1] === 0xbb && bytes[2] === 0xbf
    ? "utf-8"
    : bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe
    ? "utf-16le"
    : bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff
    ? "utf-16be"
    : undefined;
  const normalized = charset === "iso-8859-1"
    ? "windows-1252"
    : charset ?? bomCharset;
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
  const checkpoint = [
    ...normalized.matchAll(
      /<(?:title|h1|h2)[^>]*>([\s\S]*?)<\/(?:title|h1|h2)>/gi,
    ),
  ].map((match) => match[1].replace(/<[^>]+>/g, " ")).join(" ");
  if (
    /(?:page\s+not\s+found|error\s*404|\b404\b|requested\s+page\s+(?:does\s+not\s+exist|was\s+not\s+found)|can(?:not|'t)\s+find\s+(?:that|this|the)\s+page)/i
      .test(checkpoint)
  ) throw fetchError("soft_404", { httpStatus: 200 });
  if (
    /(?:captcha|security\s+check|access\s+denied|request\s+rejected|verify\s+(?:you\s+are\s+)?human|checking\s+your\s+browser|enable\s+cookies\s+to\s+continue)/i
      .test(checkpoint) ||
    /(?:cloudflare\s+ray|automated\s+requests?\s+(?:are\s+)?blocked|<input[^>]+type=["']password|<form[^>]+(?:login|sign[-_ ]?in))/i
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

function reusablePreviousBinding(
  input: OfficialFetchInput,
  sourceIdentityHash: string,
): boolean {
  const previous = input.previous;
  if (
    input.forceUnconditional || !previous || !input.parserVersion ||
    previous.parserVersion !== input.parserVersion ||
    previous.reusableExtraction !== true ||
    previous.cardIdentityValidated !== true ||
    previous.sourceIdentityHash !== sourceIdentityHash ||
    !/^[0-9a-f]{64}$/i.test(previous.contentHash ?? "") ||
    !/^[0-9a-f]{64}$/i.test(previous.canonicalBenefitHash ?? "") ||
    !/^[0-9a-f]{64}$/i.test(previous.finalResourceIdentityHash ?? "") ||
    !safeDisplayUrl(previous.finalResourceUrl)
  ) return false;
  return true;
}

async function conditionalHeadersForHop(
  input: OfficialFetchInput,
  currentUrl: string,
  sourceIdentityHash: string,
): Promise<Record<string, string>> {
  if (!reusablePreviousBinding(input, sourceIdentityHash)) return {};
  const previous = input.previous!;
  const currentIdentityHash = await sha256(
    new TextEncoder().encode(currentUrl),
  );
  if (
    displayUrl(currentUrl) !== safeDisplayUrl(previous.finalResourceUrl) ||
    currentIdentityHash !== previous.finalResourceIdentityHash
  ) return {};
  return {
    ...(boundedHeader(previous.etag ?? null)
      ? { "If-None-Match": boundedHeader(previous.etag ?? null)! }
      : {}),
    ...(boundedHeader(previous.lastModified ?? null)
      ? {
        "If-Modified-Since": boundedHeader(
          previous.lastModified ?? null,
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

function ensureBeforeDeadline(input: OfficialFetchInput): void {
  if (
    input.deadlineAt !== undefined &&
    (input.now ?? Date.now)() >= input.deadlineAt
  ) throw fetchError("deadline_exceeded");
}

type RobotsRule = {
  allow: boolean;
  pattern: string;
  specificity: number;
};

const ROBOTS_USER_AGENT = "cardcompasscatalogbot";
const MAX_ROBOTS_BYTES = 256 * 1024;
const MAX_ROBOTS_LINES = 10_000;

function normalizeRobotsPattern(value: string): string {
  let normalized = "";
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    const escaped = value.slice(index).match(/^%([0-9a-f]{2})/i);
    if (escaped) {
      const byte = Number.parseInt(escaped[1], 16);
      const decoded = String.fromCharCode(byte);
      normalized += /[A-Za-z0-9._~-]/.test(decoded)
        ? decoded
        : `%${escaped[1].toUpperCase()}`;
      index += 2;
      continue;
    }
    normalized += character.charCodeAt(0) > 0x7f
      ? encodeURI(character)
      : character;
  }
  return normalized;
}

function parseRobotsRules(text: string): RobotsRule[] {
  if (/<(?:!doctype\s+html|html|head|body)\b/i.test(text.slice(0, 2_048))) {
    throw fetchError("robots_invalid");
  }
  const rawLines = text.split(/\r?\n/);
  if (
    rawLines.length > MAX_ROBOTS_LINES ||
    rawLines.some((line) => line.length > 2_048)
  ) throw fetchError("robots_invalid");
  const groups: Array<{ agents: string[]; rules: RobotsRule[] }> = [];
  let agents: string[] = [];
  let rules: RobotsRule[] = [];
  const flush = () => {
    if (agents.length > 0) groups.push({ agents, rules });
    agents = [];
    rules = [];
  };
  for (const rawLine of text.slice(0, 256 * 1024).split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    if (!line) continue;
    const separator = line.indexOf(":");
    if (separator <= 0) throw fetchError("robots_invalid");
    const field = line.slice(0, separator).trim().toLowerCase();
    const value = line.slice(separator + 1).trim();
    if (field === "user-agent") {
      if (!value) throw fetchError("robots_invalid");
      if (rules.length > 0) flush();
      agents.push(value.toLowerCase());
    } else if ((field === "allow" || field === "disallow") && agents.length) {
      if (value) {
        const pattern = normalizeRobotsPattern(value);
        rules.push({
          allow: field === "allow",
          pattern,
          specificity: pattern.replace(/\*/g, "").replace(/\$$/, "").length,
        });
      }
    } else if (field === "allow" || field === "disallow") {
      throw fetchError("robots_invalid");
    }
  }
  flush();
  const exact = groups.filter((group) =>
    group.agents.some((agent) => agent === ROBOTS_USER_AGENT)
  );
  const selected = exact.length > 0
    ? exact
    : groups.filter((group) => group.agents.includes("*"));
  return selected.flatMap((group) => group.rules);
}

function robotsPermit(rules: RobotsRule[], url: string): boolean {
  const parsed = new URL(url);
  const target = normalizeRobotsPattern(`${parsed.pathname}${parsed.search}`);
  const matching = rules.filter((rule) => {
    const terminal = rule.pattern.endsWith("$");
    const source = (terminal ? rule.pattern.slice(0, -1) : rule.pattern)
      .split("*")
      .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
      .join(".*");
    return new RegExp(`^${source}${terminal ? "$" : ""}`).test(target);
  })
    .sort((left, right) =>
      right.specificity - left.specificity || Number(right.allow) -
        Number(left.allow)
    );
  return matching[0]?.allow ?? true;
}

export async function fetchOfficialIssuerResource(
  input: OfficialFetchInput,
): Promise<OfficialFetchResult> {
  ensureBeforeDeadline(input);
  const exactSubmittedUrl = input.url.trim();
  const submittedRequestUrl = approvedRequestUrl(
    input.issuer,
    exactSubmittedUrl,
    input.allowedQueryParameters,
  );
  const maxBytes = input.maxBytes ?? DEFAULT_MAX_BYTES;
  const now = input.now ?? Date.now;
  const remainingAtStart = input.deadlineAt === undefined
    ? Number.POSITIVE_INFINITY
    : input.deadlineAt - now();
  if (remainingAtStart <= 0) throw fetchError("deadline_exceeded");
  const timeoutMs = Math.min(
    input.timeoutMs ?? DEFAULT_TIMEOUT_MS,
    remainingAtStart,
  );
  const fetchImpl = input.fetchImpl ?? fetch;
  const resolveHost = input.resolveHost ?? defaultResolveHost;
  const contentPolicy = CONTENT_POLICIES[input.contentPurpose ?? "document"];
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let url = submittedRequestUrl;
  const visited = new Set<string>();
  const robotsByHost = input._robotsCache ?? new Map<string, RobotsRule[]>();
  const sourceIdentityHash = await sha256(
    new TextEncoder().encode(submittedRequestUrl),
  );

  const productionRobotsAllowed = async (targetUrl: string) => {
    const target = new URL(targetUrl);
    let rules = robotsByHost.get(target.host);
    if (!rules) {
      ensureBeforeDeadline(input);
      const robotsUrl = `${target.protocol}//${target.host}/robots.txt`;
      await ensurePublicHost(robotsUrl, resolveHost, controller.signal);
      ensureBeforeDeadline(input);
      let response: Response;
      try {
        response = await raceWithDeadline(
          fetchImpl(robotsUrl, {
            redirect: "manual",
            headers: {
              "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
              Accept: "text/plain",
            },
            signal: controller.signal,
          }),
          controller.signal,
        );
      } catch {
        if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
          throw fetchError("deadline_exceeded");
        }
        throw fetchError("robots_disallowed");
      }
      if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
        cancelResponseBody(response);
        throw fetchError("deadline_exceeded");
      }
      if (response.status === 404) {
        // A genuinely missing robots resource permits crawling. Transport,
        // malformed, redirect, oversized, and other HTTP outcomes fail closed.
        cancelResponseBody(response);
        rules = [];
      } else if (!response.ok || response.status >= 300) {
        cancelResponseBody(response);
        throw fetchError("robots_disallowed");
      } else {
        let bytes: Uint8Array;
        try {
          const metadata = contentMetadata(
            response.headers.get("content-type"),
          );
          if (
            metadata.mime !== "text/plain" ||
            (metadata.charset && metadata.charset !== "utf-8" &&
              metadata.charset !== "utf8")
          ) throw fetchError("robots_invalid");
          bytes = await readResponseBytes(
            response,
            MAX_ROBOTS_BYTES,
            controller,
          );
        } catch {
          throw fetchError("robots_invalid");
        }
        try {
          rules = parseRobotsRules(
            new TextDecoder("utf-8", { fatal: true }).decode(bytes),
          );
        } catch (error) {
          if (error instanceof OfficialFetchError) throw error;
          throw fetchError("robots_invalid");
        }
        ensureBeforeDeadline(input);
      }
      robotsByHost.set(target.host, rules);
    }
    return robotsPermit(rules, targetUrl);
  };

  try {
    for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
      ensureBeforeDeadline(input);
      if (visited.has(url)) throw fetchError("redirect_rejected");
      visited.add(url);
      if (input.robotsAllowed || input.enforceRobots) {
        try {
          ensureBeforeDeadline(input);
          const allowed = input.robotsAllowed
            ? await input.robotsAllowed(url)
            : await productionRobotsAllowed(url);
          if (!allowed) {
            throw fetchError("robots_disallowed");
          }
        } catch (error) {
          if (error instanceof OfficialFetchError) throw error;
          throw fetchError("robots_disallowed");
        }
      }
      ensureBeforeDeadline(input);
      await ensurePublicHost(url, resolveHost, controller.signal);
      ensureBeforeDeadline(input);
      let response: Response;
      const requestHeaders = await conditionalHeadersForHop(
        input,
        url,
        sourceIdentityHash,
      );
      ensureBeforeDeadline(input);
      try {
        response = await raceWithDeadline(
          fetchImpl(url, {
            redirect: "manual",
            headers: {
              "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
              Accept: contentPolicy.accept,
              ...requestHeaders,
            },
            signal: controller.signal,
          }),
          controller.signal,
        );
      } catch (error) {
        if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
          throw fetchError("deadline_exceeded");
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
      if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
        cancelResponseBody(response);
        throw fetchError("deadline_exceeded");
      }

      const retrievedAt = new Date((input.now ?? Date.now)()).toISOString();
      if (response.status === 304) {
        cancelResponseBody(response);
        const finalResourceIdentityHash = await sha256(
          new TextEncoder().encode(url),
        );
        return {
          status: 304,
          submittedUrl: displayUrl(submittedRequestUrl),
          finalUrl: displayUrl(url),
          canonicalUrl: displayUrl(url),
          retrievedAt,
          contentHash: input.previous?.contentHash,
          etag: boundedHeader(response.headers.get("etag")) ??
            boundedHeader(input.previous?.etag ?? null),
          lastModified: boundedHeader(response.headers.get("last-modified")) ??
            boundedHeader(input.previous?.lastModified ?? null),
          notModified: true,
          sourceIdentityHash,
          finalResourceIdentityHash,
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
        url = canonicalRedirectUrl(
          input.issuer,
          redirectUrl,
          input.allowedQueryParameters,
        );
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
      ensureBeforeDeadline(input);
      try {
        bytes = await readResponseBytes(response, maxBytes, controller);
      } catch (error) {
        if (error instanceof Error && error.message === "oversized") {
          throw error;
        }
        if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
          throw fetchError("deadline_exceeded");
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
      ensureBeforeDeadline(input);

      const result: OfficialFetchResult = {
        status: response.status,
        submittedUrl: displayUrl(submittedRequestUrl),
        finalUrl: displayUrl(url),
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
        sourceIdentityHash,
        finalResourceIdentityHash: await sha256(
          new TextEncoder().encode(url),
        ),
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
): number | undefined {
  if (!value) return undefined;
  const seconds = Number(value);
  const parsed = value.trim() !== "" && Number.isFinite(seconds) && seconds >= 0
    ? seconds * 1000
    : Date.parse(value) - now;
  return Number.isFinite(parsed) && parsed >= 0
    ? Math.min(maximum, parsed)
    : undefined;
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
  const robotsCache = new Map<string, RobotsRule[]>();
  const waitBeforeRetry = async (milliseconds: number): Promise<boolean> => {
    if (input.deadlineAt !== undefined) {
      const remaining = input.deadlineAt - now();
      if (remaining <= 0 || milliseconds > remaining) return false;
    }
    await delay(milliseconds);
    return input.deadlineAt === undefined || now() < input.deadlineAt;
  };
  const deadlineObservation = (): OfficialFetchObservation => {
    attempts.push({
      code: "deadline_exceeded",
      attemptedAt: new Date(now()).toISOString(),
    });
    return {
      disposition: "failed",
      attempts,
      reviewReason: "deadline_exceeded",
    };
  };

  for (let index = 0; index < maxAttempts; index += 1) {
    if (input.deadlineAt !== undefined && now() >= input.deadlineAt) {
      const attemptedAt = new Date(now()).toISOString();
      attempts.push({ code: "deadline_exceeded", attemptedAt });
      return {
        disposition: "failed",
        attempts,
        reviewReason: "deadline_exceeded",
      };
    }
    try {
      const result = await fetchOfficialIssuerResource({
        ...input,
        forceUnconditional,
        _robotsCache: robotsCache,
      });
      attempts.push({ status: result.status, attemptedAt: result.retrievedAt });
      if (result.notModified) {
        const reusable304 = reusablePreviousBinding(
          input,
          result.sourceIdentityHash ?? "",
        ) &&
          Boolean(input.previous?.etag || input.previous?.lastModified) &&
          Boolean(result.contentHash) &&
          result.finalResourceIdentityHash ===
            input.previous?.finalResourceIdentityHash &&
          result.finalUrl === input.previous?.finalResourceUrl &&
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
          const backoff = Math.min(maxBackoffMs, 1000 * 2 ** index);
          if (!await waitBeforeRetry(backoff)) return deadlineObservation();
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
      if (
        failure.code === "robots_invalid" ||
        failure.code === "unapproved_query"
      ) {
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
      if (!await waitBeforeRetry(backoff)) return deadlineObservation();
    }
  }
  return { disposition: "failed", attempts, reviewReason: "retry_exhausted" };
}
