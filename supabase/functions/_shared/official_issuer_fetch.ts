import {
  canonicalOfficialUrl,
} from "./card_discovery.ts";

export type OfficialFetchInput = {
  issuer: string;
  url: string;
  maxBytes?: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  resolveHost?: (host: string) => Promise<string[]>;
};

export type OfficialFetchResult = {
  submittedUrl: string;
  finalUrl: string;
  canonicalUrl: string;
  contentType: string;
  bytes: Uint8Array;
  text: string;
  contentHash: string;
  retrievedAt: string;
};

type OfficialFetchCode =
  | "unapproved_domain"
  | "private_address"
  | "redirect_rejected"
  | "unsupported_content"
  | "oversized"
  | "timeout"
  | "unreachable";

const DEFAULT_MAX_BYTES = 8 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 12_000;
const MAX_REDIRECTS = 4;
const ALLOWED_CONTENT_TYPES = new Set([
  "text/html",
  "application/xhtml+xml",
  "application/pdf",
  // Discovery uses issuer-published sitemaps as an official URL source.
  "application/xml",
  "text/xml",
]);

function fetchError(code: OfficialFetchCode): Error {
  return new Error(code);
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
      (first === 169 && second === 254) ||
      (first === 172 && second >= 16 && second <= 31) ||
      (first === 192 && second === 168);
  }
  return value === "::" || value === "::1" ||
    /^fc|^fd/.test(value) || /^fe[89ab]/.test(value);
}

async function defaultResolveHost(host: string): Promise<string[]> {
  const responses = await Promise.allSettled([
    Deno.resolveDns(host, "A"),
    Deno.resolveDns(host, "AAAA"),
  ]);
  return responses.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
}

async function ensurePublicHost(
  url: string,
  resolveHost: (host: string) => Promise<string[]>,
): Promise<void> {
  let addresses: string[];
  try {
    addresses = await resolveHost(new URL(url).hostname);
  } catch {
    throw fetchError("unreachable");
  }
  if (addresses.length === 0) throw fetchError("unreachable");
  if (addresses.some(isPrivateAddress)) throw fetchError("private_address");
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

export async function fetchOfficialIssuerResource(
  input: OfficialFetchInput,
): Promise<OfficialFetchResult> {
  const submittedUrl = canonicalInitialUrl(input.issuer, input.url);
  const maxBytes = input.maxBytes ?? DEFAULT_MAX_BYTES;
  const timeoutMs = input.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const fetchImpl = input.fetchImpl ?? fetch;
  const resolveHost = input.resolveHost ?? defaultResolveHost;
  let url = submittedUrl;

  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
    await ensurePublicHost(url, resolveHost);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const signal = controller.signal;
    try {
      let response: Response;
      try {
        response = await fetchImpl(url, {
          redirect: "manual",
          headers: {
            "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
            Accept: "text/html,application/xhtml+xml,application/pdf;q=0.8",
          },
          signal,
        });
      } catch (error) {
        if (signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError")) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (!location) throw fetchError("redirect_rejected");
        let redirectUrl: string;
        try {
          redirectUrl = new URL(location, url).toString();
        } catch {
          throw fetchError("redirect_rejected");
        }
        url = canonicalRedirectUrl(input.issuer, redirectUrl);
        continue;
      }

      if (!response.ok) throw fetchError("unreachable");
      const contentType = response.headers.get("content-type")?.split(";", 1)[0]
        .trim().toLowerCase() ?? "";
      if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
        throw fetchError("unsupported_content");
      }
      const declaredBytes = Number(response.headers.get("content-length") ?? 0);
      if (declaredBytes > maxBytes) throw fetchError("oversized");

      let bytes: Uint8Array;
      try {
        bytes = new Uint8Array(await response.arrayBuffer());
      } catch (error) {
        if (signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError")) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }
      if (bytes.length > maxBytes) throw fetchError("oversized");

      return {
        submittedUrl,
        finalUrl: url,
        canonicalUrl: url,
        contentType,
        bytes,
        text: contentType === "application/pdf" ? "" : new TextDecoder().decode(bytes),
        contentHash: await sha256(bytes),
        retrievedAt: new Date().toISOString(),
      };
    } finally {
      clearTimeout(timeout);
    }
  }
  throw fetchError("redirect_rejected");
}
