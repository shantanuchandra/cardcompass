const absoluteHttpUrl = /https?:\/\/[^\s<>"']+/gi;
const hrefAttribute = /(\bhref\s*=\s*)(["'])([\s\S]*?)(\2)/gi;

export function safeHttpsDisplayUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 16_384) return null;
  try {
    const url = new URL(value.trim());
    if (url.protocol !== "https:" || !url.hostname) return null;
    url.username = "";
    url.password = "";
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "").slice(0, 2_048);
  } catch {
    return null;
  }
}

function safeHrefValue(value: string): string {
  const trimmed = value.trim();
  if (/^https?:\/\//i.test(trimmed)) {
    return safeHttpsDisplayUrl(trimmed) ?? "[redacted-url]";
  }
  if (trimmed.startsWith("//")) {
    return safeHttpsDisplayUrl(`https:${trimmed}`) ?? "[redacted-url]";
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed)) return "[redacted-url]";
  const safe = trimmed.split(/[?#]/, 1)[0];
  return /(?:^|[\\/])[^\\/]*@/.test(safe)
    ? "[redacted-url]"
    : safe.slice(0, 2_048);
}

/** Redacts URL secrets before source text can enter parser or admin payloads. */
export function redactSensitiveUrlsInText(value: string): string {
  return value
    .replace(
      hrefAttribute,
      (_match, prefix: string, quote: string, href: string) =>
        `${prefix}${quote}${safeHrefValue(href)}${quote}`,
    )
    .replace(
      absoluteHttpUrl,
      (candidate) => safeHttpsDisplayUrl(candidate) ?? "[redacted-url]",
    );
}

export function redactSensitiveUrlsInValue(value: unknown): unknown {
  if (typeof value === "string") return redactSensitiveUrlsInText(value);
  if (Array.isArray(value)) return value.map(redactSensitiveUrlsInValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => [
        key,
        redactSensitiveUrlsInValue(item),
      ]),
    );
  }
  return value;
}
