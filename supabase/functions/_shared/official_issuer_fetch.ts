import { canonicalOfficialUrl } from "./card_discovery.ts";
import { extractText as extractUnpdfText, getDocumentProxy } from "unpdf";

declare const officialRobotsCacheBrand: unique symbol;
export type OfficialRobotsCache = {
  readonly [officialRobotsCacheBrand]: true;
};

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
  /** Opaque, bounded cache scoped to one caller-controlled crawl invocation. */
  robotsCache?: OfficialRobotsCache;
};

export type OfficialFetchResult = {
  status: number;
  /** Privacy-bounded display URLs; approved functional queries are omitted. */
  submittedUrl: string;
  finalUrl: string;
  canonicalUrl: string;
  /** Exact approved request identities used for hashing and publication. */
  submittedResourceUrl?: string;
  finalResourceUrl?: string;
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

const MAX_EXTRACTED_PDF_TEXT_BYTES = 1_000_000;
const MAX_INFLATED_PDF_STREAM_BYTES = 8_000_000;
const MAX_PDF_PAGES = 64;
const MAX_PDF_IMAGE_PIXELS = 4_194_304;

type PdfTextBudget = { bytes: number };
type PdfInflateBudget = { bytes: number };

const windows1252PdfBytes = new Map<number, number>([
  [0x20ac, 0x80],
  [0x201a, 0x82],
  [0x0192, 0x83],
  [0x201e, 0x84],
  [0x2026, 0x85],
  [0x2020, 0x86],
  [0x2021, 0x87],
  [0x02c6, 0x88],
  [0x2030, 0x89],
  [0x0160, 0x8a],
  [0x2039, 0x8b],
  [0x0152, 0x8c],
  [0x017d, 0x8e],
  [0x2018, 0x91],
  [0x2019, 0x92],
  [0x201c, 0x93],
  [0x201d, 0x94],
  [0x2022, 0x95],
  [0x2013, 0x96],
  [0x2014, 0x97],
  [0x02dc, 0x98],
  [0x2122, 0x99],
  [0x0161, 0x9a],
  [0x203a, 0x9b],
  [0x0153, 0x9c],
  [0x017e, 0x9e],
  [0x0178, 0x9f],
]);

function pdfBinaryBytes(value: string): Uint8Array {
  return new Uint8Array([...value].map((character) => {
    const codePoint = character.codePointAt(0)!;
    return windows1252PdfBytes.get(codePoint) ?? (codePoint & 0xff);
  }));
}

function retainPdfTextPart(
  parts: string[],
  value: string,
  budget: PdfTextBudget,
): void {
  const bytes = new TextEncoder().encode(value).byteLength;
  if (budget.bytes + bytes > MAX_EXTRACTED_PDF_TEXT_BYTES) {
    throw new OfficialFetchError("oversized");
  }
  budget.bytes += bytes;
  parts.push(value);
}

function textOperators(value: string, budget: PdfTextBudget): string[] {
  const parts: string[] = [];
  for (const match of value.matchAll(/\(((?:\\.|[^\\)])*)\)\s*Tj\b/gs)) {
    retainPdfTextPart(parts, decodePdfLiteral(match[1] ?? ""), budget);
  }
  for (const match of value.matchAll(/\[((?:.|\n|\r)*?)\]\s*TJ\b/g)) {
    for (const literal of (match[1] ?? "").matchAll(/\(((?:\\.|[^\\)])*)\)/g)) {
      retainPdfTextPart(parts, decodePdfLiteral(literal[1] ?? ""), budget);
    }
  }
  return parts;
}

async function inflatePdfStream(
  bytes: Uint8Array,
  budget: PdfInflateBudget,
): Promise<string | null> {
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
        budget.bytes += value.length;
        if (budget.bytes > MAX_INFLATED_PDF_STREAM_BYTES) {
          await reader.cancel();
          throw new OfficialFetchError("oversized");
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
  } catch (error) {
    if (error instanceof OfficialFetchError) throw error;
    return null;
  }
}

async function extractLegacyPdfText(bytes: Uint8Array): Promise<string> {
  const raw = new TextDecoder("latin1").decode(bytes);
  if (!raw.startsWith("%PDF-")) throw new Error("unsupported_content");
  const budget: PdfTextBudget = { bytes: 0 };
  const inflateBudget: PdfInflateBudget = { bytes: 0 };
  const parts = textOperators(raw, budget);
  for (const match of raw.matchAll(/stream\r?\n([\s\S]*?)\r?\nendstream/g)) {
    const streamStart = match.index ?? 0;
    const dictionary = raw.slice(Math.max(0, streamStart - 500), streamStart);
    if (!/\/FlateDecode\b/.test(dictionary)) continue;
    const encoded = pdfBinaryBytes(match[1] ?? "");
    const inflated = await inflatePdfStream(encoded, inflateBudget);
    if (inflated) parts.push(...textOperators(inflated, budget));
  }
  return parts.join(" ").replace(/[\u0000-\u001f]+/g, " ")
    .replace(/\s+/g, " ").trim();
}

function boundedPdfText(value: string): string {
  // PDF.js retains useful text-line boundaries. Keep them: flattening a table
  // turns adjacent monetary values into phone/card-number shaped runs and also
  // makes unrelated product rows look like one benefit sentence.
  const normalized = value.replace(/\r\n?/g, "\n")
    .replace(/[\u0000-\u0009\u000b-\u001f]+/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (
    new TextEncoder().encode(normalized).byteLength >
      MAX_EXTRACTED_PDF_TEXT_BYTES
  ) throw new OfficialFetchError("oversized");
  return normalized;
}

async function extractPdfText(bytes: Uint8Array): Promise<string> {
  let document: Awaited<ReturnType<typeof getDocumentProxy>> | undefined;
  try {
    document = await getDocumentProxy(bytes.slice(), {
      disableFontFace: true,
      maxImageSize: MAX_PDF_IMAGE_PIXELS,
      useSystemFonts: false,
      verbosity: 0,
    });
    if (document.numPages < 1 || document.numPages > MAX_PDF_PAGES) {
      throw new OfficialFetchError("oversized");
    }
    const extracted = await extractUnpdfText(document, { mergePages: true });
    const text = Array.isArray(extracted.text)
      ? extracted.text.join("\n")
      : extracted.text;
    const normalized = boundedPdfText(text);
    if (normalized) return normalized;
  } catch (error) {
    if (error instanceof OfficialFetchError) throw error;
    // Retain the bounded legacy parser for malformed but locally readable
    // issuer fixtures and older PDFs that PDF.js cannot resolve.
  } finally {
    await document?.cleanup();
  }
  return await extractLegacyPdfText(bytes);
}

export async function officialResourceText(
  resource: OfficialFetchResult,
): Promise<string> {
  if (resource.contentType === "application/json") {
    let parsed: unknown;
    try {
      parsed = JSON.parse(
        resource.bytes
          ? new TextDecoder().decode(resource.bytes)
          : resource.text ?? "",
      );
    } catch {
      throw new OfficialFetchError("unsupported_content");
    }
    const values: string[] = [];
    let nodes = 0;
    let bytes = 0;
    const retain = (value: unknown): void => {
      nodes += 1;
      if (nodes > 16_384) throw new OfficialFetchError("oversized");
      if (typeof value === "string") {
        const normalized = value.replace(/\r\n?/g, "\n").trim();
        if (!normalized) return;
        const visible = normalized.replace(/<[^>]+>/g, " ")
          .replace(/\s+/g, " ").trim();
        if (
          /^(?:what|which|how|when|where|why|can|will|does|is|are)\b[^?]*\?$/i
            .test(visible)
        ) return;
        bytes += new TextEncoder().encode(normalized).byteLength;
        if (bytes > MAX_EXTRACTED_PDF_TEXT_BYTES) {
          throw new OfficialFetchError("oversized");
        }
        values.push(normalized);
        return;
      }
      if (Array.isArray(value)) {
        for (const item of value) retain(item);
        return;
      }
      if (value && typeof value === "object") {
        for (const item of Object.values(value as Record<string, unknown>)) {
          retain(item);
        }
      }
    };
    retain(parsed);
    if (values.length === 0) throw new OfficialFetchError("empty_shell");
    return values.join("\n");
  }
  if (resource.contentType !== "application/pdf") return resource.text ?? "";
  if (!resource.bytes) return "";
  try {
    return await extractPdfText(resource.bytes);
  } catch (error) {
    if (error instanceof OfficialFetchError) throw error;
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
    accept:
      "text/html,application/xhtml+xml,application/pdf;q=0.8,application/json;q=0.7",
    contentTypes: new Set([
      "text/html",
      "application/xhtml+xml",
      "application/pdf",
      "application/json",
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
const MAX_REQUEST_URL_LENGTH = 2_048;
const MAX_QUERY_PARAMETERS = 8;
const MAX_QUERY_KEY_LENGTH = 64;
const MAX_QUERY_VALUE_LENGTH = 512;

function isTrackingQueryKey(key: string): boolean {
  return /^utm_/i.test(key) || ["gclid", "fbclid", "sfvrsn"].includes(
    key.toLowerCase(),
  );
}

function removeTrackingQuery(url: URL): void {
  if (!url.search) return;
  const rawParts = url.search.slice(1).split("&");
  const entries = [...url.searchParams.entries()];
  const retained = rawParts.filter((_, index) =>
    !isTrackingQueryKey(entries[index]?.[0] ?? "")
  );
  url.search = retained.length > 0 ? `?${retained.join("&")}` : "";
}

function boundedQueryEntries(url: URL): Array<[string, string]> {
  const entries = [...url.searchParams.entries()];
  if (
    entries.length > MAX_QUERY_PARAMETERS ||
    entries.some(([key, value]) =>
      key.length === 0 || key.length > MAX_QUERY_KEY_LENGTH ||
      value.length > MAX_QUERY_VALUE_LENGTH
    )
  ) throw fetchError("unapproved_query");
  return entries;
}

function validateRawQueryEncoding(value: string): void {
  const queryStart = value.indexOf("?");
  if (queryStart < 0) return;
  const fragmentStart = value.indexOf("#", queryStart);
  const query = value.slice(
    queryStart + 1,
    fragmentStart < 0 ? undefined : fragmentStart,
  );
  if (
    query.length === 0 || query.split("&").some((part) => part.length === 0)
  ) {
    throw fetchError("unapproved_query");
  }
  for (const component of query.split(/[&=]/)) {
    if (/%(?![0-9a-f]{2})/i.test(component)) {
      throw fetchError("unapproved_query");
    }
    try {
      decodeURIComponent(component.replace(/\+/g, "%20"));
    } catch {
      throw fetchError("unapproved_query");
    }
  }
}

export function approvedStoredQueryParameters(value: string): string[] {
  try {
    if (value.trim().length > MAX_REQUEST_URL_LENGTH) return [];
    validateRawQueryEncoding(value.trim());
    const url = new URL(value);
    boundedQueryEntries(url);
    removeTrackingQuery(url);
    const entries = boundedQueryEntries(url);
    const keys = [...new Set(entries.map(([key]) => key))];
    return keys.every((key) =>
        SAFE_FUNCTIONAL_QUERY_KEYS.has(key.toLowerCase()) &&
        !SENSITIVE_QUERY_KEY.test(key)
      )
      ? keys
      : [];
  } catch {
    return [];
  }
}

export function canonicalOfficialRequestUrl(
  issuer: string,
  url: string,
  allowedQueryParameters: string[] = [],
): string {
  try {
    const exact = url.trim();
    if (exact.length > MAX_REQUEST_URL_LENGTH) {
      throw fetchError("unapproved_query");
    }
    validateRawQueryEncoding(exact);
    const submitted = new URL(exact);
    boundedQueryEntries(submitted);
    removeTrackingQuery(submitted);
    const entries = boundedQueryEntries(submitted);
    const allowed = new Set(
      allowedQueryParameters.map((key) => key.trim().toLowerCase()).filter(
        (key) =>
          key && SAFE_FUNCTIONAL_QUERY_KEYS.has(key) &&
          !SENSITIVE_QUERY_KEY.test(key),
      ),
    );
    if (
      entries.some(([key]) =>
        SENSITIVE_QUERY_KEY.test(key) ||
        !SAFE_FUNCTIONAL_QUERY_KEYS.has(key.toLowerCase()) ||
        !allowed.has(key.toLowerCase())
      )
    ) throw fetchError("unapproved_query");
    const exactSearch = submitted.search;
    submitted.search = "";
    submitted.hash = "";
    const canonical = new URL(
      canonicalOfficialUrl(issuer, submitted.toString()),
    );
    canonical.search = exactSearch;
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
    return canonicalOfficialRequestUrl(issuer, url, allowedQueryParameters);
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

type RobotsCacheEntry = {
  rules: RobotsRule[];
  expiresAt: number;
};

const robotsCacheState = new WeakMap<object, Map<string, RobotsCacheEntry>>();
const MAX_ROBOTS_CACHE_ENTRIES = 16;
const ROBOTS_CACHE_TTL_MS = 5 * 60 * 1_000;

export function createOfficialRobotsCache(): OfficialRobotsCache {
  const cache = Object.freeze({}) as OfficialRobotsCache;
  robotsCacheState.set(cache, new Map());
  return cache;
}

function robotsEntries(
  cache: OfficialRobotsCache | object,
): Map<string, RobotsCacheEntry> {
  let entries = robotsCacheState.get(cache);
  if (!entries) {
    entries = new Map();
    robotsCacheState.set(cache, entries);
  }
  return entries;
}

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
  const submittedRequestUrl = canonicalOfficialRequestUrl(
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
  const robotsCache = input.robotsCache ?? createOfficialRobotsCache();
  const robotsByHost = robotsEntries(robotsCache);
  const sourceIdentityHash = await sha256(
    new TextEncoder().encode(submittedRequestUrl),
  );

  const productionRobotsAllowed = async (targetUrl: string) => {
    const target = new URL(targetUrl);
    const cacheKey = `${target.protocol}//${target.host}|${ROBOTS_USER_AGENT}`;
    const cached = robotsByHost.get(cacheKey);
    if (cached && cached.expiresAt <= now()) robotsByHost.delete(cacheKey);
    let rules = cached && cached.expiresAt > now() ? cached.rules : undefined;
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
            metadata.mime !== "text/plain" &&
            metadata.mime !== "text/x-robots"
          ) throw fetchError("robots_invalid");
          bytes = await readResponseBytes(
            response,
            MAX_ROBOTS_BYTES,
            controller,
          );
          if (
            metadata.charset && metadata.charset !== "utf-8" &&
            metadata.charset !== "utf8" &&
            bytes.some((byte) => byte >= 0x80)
          ) throw fetchError("robots_invalid");
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
      if (robotsByHost.size >= MAX_ROBOTS_CACHE_ENTRIES) {
        robotsByHost.delete(robotsByHost.keys().next().value!);
      }
      robotsByHost.set(cacheKey, {
        rules,
        expiresAt: now() + ROBOTS_CACHE_TTL_MS,
      });
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
          submittedResourceUrl: submittedRequestUrl,
          finalResourceUrl: url,
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
        submittedResourceUrl: submittedRequestUrl,
        finalResourceUrl: url,
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
  const robotsCache = input.robotsCache ?? createOfficialRobotsCache();
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
        robotsCache,
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
          (result.finalResourceUrl ?? result.finalUrl) ===
            input.previous?.finalResourceUrl &&
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
