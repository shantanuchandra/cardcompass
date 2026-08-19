const absoluteHttpUrl = /https?:\/\/[^\s<>"']+/gi;
const hrefAttribute = /(\bhref\s*=\s*)(["'])([\s\S]*?)(\2)/gi;
const structuralEncoding =
  /%(?:3a|2f|3f|23|40|5b|5d)|&#(?:x(?:3a|2f|3f|23|40)|(?:58|47|63|35|64));?|&(?:colon|sol|quest|num|commat);/gi;
const secretBearingReference =
  /(?:https?:\/\/|\/\/|(?:[a-z0-9-]+\.)+[a-z]{2,}(?=[:/]))[^\s<>"']*|\/(?:[^\s<>"']*)?[?#][^\s<>"']*|[?#](?:[^\s<>"']+)/gi;
const structuredUserInfo =
  /(^|[\s("'`])([^\s@/?#:<>'"]+)(?::([^\s@/?#<>'"]*))?@(\[[0-9a-f:.]+\]|(?:\d{1,3}\.){3}\d{1,3}|(?:[a-z0-9-]+\.)+[a-z0-9-]+|localhost|[a-z0-9-]+)((?::\d+)?(?:\/[^\s<>"']*|[?#][^\s<>"']*)?)(?=$|[\s),;'"`])/gi;

const MAX_PRESENTATION_INPUT = 16_384;
const MAX_STRUCTURAL_DECODE_PASSES = 4;

function decodeStructuralEncoding(value: string): string {
  let decoded = value.slice(0, MAX_PRESENTATION_INPUT);
  for (let pass = 0; pass < MAX_STRUCTURAL_DECODE_PASSES; pass += 1) {
    const next = decoded
      // Decode a percent-encoded entity only as a unit. This detects mixed
      // encodings without turning ordinary prose such as "100%25" into "%".
      .replace(
        /%26%23(x?(?:3a|2f|3f|23|40|58|47|63|35|64))%3b/gi,
        "&#$1;",
      )
      // Peel percent layers only when they lead to a structural delimiter.
      .replace(/%25(?=(?:25){0,2}(?:3a|2f|3f|23|40|5b|5d))/gi, "%")
      // Likewise, unwrap ampersands only when the result remains a structural
      // named/numeric entity; unrelated HTML prose remains untouched.
      .replace(
        /&amp;(?=(?:amp;){0,2}(?:#(?:x(?:3a|2f|3f|23|40)|(?:58|47|63|35|64));?|(?:colon|sol|quest|num|commat);))/gi,
        "&",
      )
      .replace(structuralEncoding, (match) => {
        const normalized = match.toLowerCase().replace(/;$/, "");
        if (["%3a", "&#x3a", "&#58", "&colon"].includes(normalized)) {
          return ":";
        }
        if (["%2f", "&#x2f", "&#47", "&sol"].includes(normalized)) {
          return "/";
        }
        if (["%3f", "&#x3f", "&#63", "&quest"].includes(normalized)) {
          return "?";
        }
        if (["%23", "&#x23", "&#35", "&num"].includes(normalized)) {
          return "#";
        }
        if (normalized === "%5b") return "[";
        if (normalized === "%5d") return "]";
        return "@";
      });
    if (next === decoded) break;
    decoded = next.slice(0, MAX_PRESENTATION_INPUT);
  }
  return decoded;
}

export function safeHttpsDisplayUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > MAX_PRESENTATION_INPUT) {
    return null;
  }
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
  const decoded = decodeStructuralEncoding(value);
  const redacted = decoded
    .replace(
      hrefAttribute,
      (_match, prefix: string, quote: string, href: string) =>
        `${prefix}${quote}${safeHrefValue(href)}${quote}`,
    )
    .replace(
      absoluteHttpUrl,
      (candidate) => safeHttpsDisplayUrl(candidate) ?? "[redacted-url]",
    )
    .replace(
      structuredUserInfo,
      (
        candidate,
        prefix: string,
        _username: string,
        password: string | undefined,
        safeHost: string,
        structuredTail: string,
      ) => {
        const hostIsExplicit = safeHost.startsWith("[") ||
          /^(?:\d{1,3}\.){3}\d{1,3}$/i.test(safeHost) ||
          safeHost.toLowerCase() === "localhost" || !safeHost.includes(".");
        const urlLike = password !== undefined || structuredTail.length > 0 ||
          hostIsExplicit;
        return urlLike ? `${prefix}${safeHost}${structuredTail}` : candidate;
      },
    )
    .replace(secretBearingReference, (candidate) => {
      const boundary = candidate.search(/[?#]/);
      const base = boundary >= 0 ? candidate.slice(0, boundary) : candidate;
      if (/^https?:\/\//i.test(candidate)) {
        return safeHttpsDisplayUrl(candidate) ?? "[redacted-url]";
      }
      if (candidate.startsWith("//")) {
        return safeHttpsDisplayUrl(`https:${candidate}`)?.replace(
          /^https:/,
          "",
        ) ??
          "[redacted-url]";
      }
      return base || "[redacted-url]";
    });
  // Structural decoding is a bounded detection probe. Preserve ordinary
  // percent/entity prose byte-for-byte unless it revealed a URL credential or
  // secret-bearing reference that was actually redacted.
  return redacted === decoded ? value : redacted;
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
