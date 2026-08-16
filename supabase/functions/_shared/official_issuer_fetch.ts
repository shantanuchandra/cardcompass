import {
  canonicalOfficialUrl,
} from "./card_discovery.ts";

export type OfficialContentPurpose = "document" | "html" | "sitemap";

export type OfficialFetchInput = {
  issuer: string;
  url: string;
  contentPurpose?: OfficialContentPurpose;
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
    contentTypes: new Set(["text/html", "application/xhtml+xml", "application/pdf"]),
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

function raceWithDeadline<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
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
    addresses = await raceWithDeadline(resolveHost(new URL(url).hostname), signal);
  } catch (error) {
    if (signal.aborted || (error instanceof Error && error.message === "timeout")) {
      throw fetchError("timeout");
    }
    throw fetchError("unreachable");
  }
  if (addresses.length === 0) throw fetchError("unreachable");
  if (addresses.some(isPrivateAddress)) throw fetchError("private_address");
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Cancellation is best-effort; the primary failure remains deterministic.
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
      const { done, value } = await raceWithDeadline(reader.read(), controller.signal);
      if (done) break;
      const nextLength = length + value.length;
      if (nextLength > maxBytes) {
        controller.abort();
        await reader.cancel().catch(() => undefined);
        throw fetchError("oversized");
      }
      chunks.push(value);
      length = nextLength;
    }
  } catch (error) {
    if (controller.signal.aborted) await reader.cancel().catch(() => undefined);
    throw error;
  } finally {
    reader.releaseLock();
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

export async function fetchOfficialIssuerResource(
  input: OfficialFetchInput,
): Promise<OfficialFetchResult> {
  const submittedUrl = canonicalInitialUrl(input.issuer, input.url);
  const maxBytes = input.maxBytes ?? DEFAULT_MAX_BYTES;
  const timeoutMs = input.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const fetchImpl = input.fetchImpl ?? fetch;
  const resolveHost = input.resolveHost ?? defaultResolveHost;
  const contentPolicy = CONTENT_POLICIES[input.contentPurpose ?? "document"];
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let url = submittedUrl;

  try {
    for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
      await ensurePublicHost(url, resolveHost, controller.signal);
      let response: Response;
      try {
        response = await raceWithDeadline(fetchImpl(url, {
          redirect: "manual",
          headers: {
            "User-Agent": "CardCompassCatalogBot/1.0 (+catalog verification)",
            Accept: contentPolicy.accept,
          },
          signal: controller.signal,
        }), controller.signal);
      } catch (error) {
        if (controller.signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError") ||
          (error instanceof Error && error.message === "timeout")) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }

      if (response.status >= 300 && response.status < 400) {
        await cancelResponseBody(response);
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

      if (!response.ok) {
        await cancelResponseBody(response);
        throw fetchError("unreachable");
      }
      const contentType = response.headers.get("content-type")?.split(";", 1)[0]
        .trim().toLowerCase() ?? "";
      if (!contentPolicy.contentTypes.has(contentType)) {
        await cancelResponseBody(response);
        throw fetchError("unsupported_content");
      }
      const declaredBytes = Number(response.headers.get("content-length") ?? 0);
      if (declaredBytes > maxBytes) {
        controller.abort();
        await cancelResponseBody(response);
        throw fetchError("oversized");
      }

      let bytes: Uint8Array;
      try {
        bytes = await readResponseBytes(response, maxBytes, controller);
      } catch (error) {
        if (error instanceof Error && error.message === "oversized") throw error;
        if (controller.signal.aborted ||
          (error instanceof DOMException && error.name === "TimeoutError") ||
          (error instanceof Error && error.message === "timeout")) {
          throw fetchError("timeout");
        }
        throw fetchError("unreachable");
      }

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
    }
    throw fetchError("redirect_rejected");
  } finally {
    clearTimeout(timeout);
  }
}
