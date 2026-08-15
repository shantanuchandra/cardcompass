const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const TOKEN_RE = /^[0-9a-f]{64}$/;
const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;

const CARD_COUNTS = new Set(['1-2', '3-6', '7+']);
const SPEND_BANDS = new Set(['under-25k', '25k-50k', '50k-1l', '1l-plus']);
const GOALS = new Set(['maximize_rewards', 'track_benefits', 'simplify_card_choices']);
const EVENT_NAMES = new Set([
  'Waitlist Started',
  'Waitlist Joined',
  'Enrichment Submitted',
  'Waitlist Error',
  'Recommendation Preview Changed',
]);
const EVENT_PROP_KEYS = new Set(['placement', 'step', 'variant', 'outcome']);
const ANALYTICS_DOMAIN = 'cardcompass.in';
const UTM_LIMITS = {
  utm_source: 100,
  utm_medium: 100,
  utm_campaign: 150,
  utm_term: 150,
  utm_content: 150,
};
const ATTRIBUTION_KEY = 'cardcompass:first-touch:v1';

function clean(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function cleanWithin(value, limit) {
  const trimmed = clean(value);
  return trimmed && trimmed.length <= limit ? trimmed : null;
}

function cleanSlug(value) {
  const trimmed = clean(value);
  return trimmed && SLUG_RE.test(trimmed) ? trimmed : null;
}

function normalizedCards(values = []) {
  if (!Array.isArray(values)) return [];
  return values.map(clean).filter(Boolean);
}

export function isValidEmail(value) {
  const email = clean(value);
  return Boolean(email && email.length <= 254 && EMAIL_RE.test(email));
}

export function buildJoinPayload({ email, privacyConsent, source, attribution = {} }) {
  return {
    p_email: String(email ?? '').trim().toLowerCase(),
    p_source: cleanSlug(attribution.source) || cleanSlug(source),
    p_utm_source: attribution.utm_source ?? null,
    p_utm_medium: attribution.utm_medium ?? null,
    p_utm_campaign: attribution.utm_campaign ?? null,
    p_utm_term: attribution.utm_term ?? null,
    p_utm_content: attribution.utm_content ?? null,
    p_referrer_path: attribution.referrer_path ?? null,
    p_landing_variant: attribution.landing_variant ?? null,
    p_privacy_consent: privacyConsent === true,
  };
}

export function validateQualification(values = {}) {
  const errors = {};
  const name = clean(values.name);
  const detail = clean(values.problemDetail);
  const cards = normalizedCards(values.topCards);

  if (name && name.length > 100) {
    errors.name = 'Keep your name to 100 characters or fewer.';
  }
  if (!CARD_COUNTS.has(values.cardCount)) {
    errors.cardCount = 'Choose how many cards you hold.';
  }
  if (!SPEND_BANDS.has(values.monthlySpendBand)) {
    errors.monthlySpendBand = 'Choose your monthly card spend.';
  }
  if (!GOALS.has(values.primaryGoal)) {
    errors.primaryGoal = 'Choose what you most want to improve.';
  }
  if (detail && detail.length > 500) {
    errors.problemDetail = 'Keep this to 500 characters or fewer.';
  }
  if (cards.length > 2 || cards.some((card) => card.length > 100)) {
    errors.topCards = 'Choose up to two cards, each under 100 characters.';
  }
  return errors;
}

export function buildEnrichmentPayload(values = {}) {
  const cards = normalizedCards(values.topCards);
  return {
    p_enrichment_token: String(values.token ?? '').trim().toLowerCase(),
    p_name: clean(values.name),
    p_card_count: clean(values.cardCount),
    p_monthly_spend_band: clean(values.monthlySpendBand),
    p_primary_goal: clean(values.primaryGoal),
    p_problem_detail: clean(values.problemDetail),
    p_top_cards: cards.length ? cards : null,
    p_marketing_consent: values.marketingConsent === true,
  };
}

export function extractEnrichmentToken(data) {
  const row = Array.isArray(data) ? data[0] : data;
  const token = clean(row?.enrichment_token)?.toLowerCase();
  if (row?.status !== 'accepted' || !token || !TOKEN_RE.test(token)) {
    throw new Error('The waitlist response could not be verified.');
  }
  return token;
}

export function buildApplicationReceipt(rpcAccepted) {
  if (rpcAccepted !== true) throw new Error('Enrichment was not accepted.');
  return {
    eyebrow: 'Details received',
    title: 'You’re on the waitlist.',
    body: 'We’ve received this step. Keep an eye on your inbox for early-access updates.',
    eventName: 'Enrichment Submitted',
  };
}

function referrerPath(referrer) {
  if (!clean(referrer)) return null;
  try {
    const path = new URL(referrer).pathname;
    return path.startsWith('/') && path.length <= 512 ? path : null;
  } catch {
    return null;
  }
}

function validStoredAttribution(value) {
  if (!value || typeof value !== 'object') return null;
  const keys = [...Object.keys(UTM_LIMITS), 'referrer_path', 'landing_variant'];
  if (!keys.every((key) => Object.hasOwn(value, key))) return null;
  if (Object.hasOwn(value, 'source') && value.source !== null && cleanSlug(value.source) !== value.source) return null;
  if (Object.entries(UTM_LIMITS).some(([key, limit]) => value[key] !== null && cleanWithin(value[key], limit) !== value[key])) return null;
  if (value.referrer_path !== null && (!value.referrer_path.startsWith('/') || value.referrer_path.length > 512)) return null;
  if (value.landing_variant !== null && cleanSlug(value.landing_variant) !== value.landing_variant) return null;
  return { source: value.source ?? null, ...value };
}

export function captureFirstTouch({ locationHref, referrer = '', variant, storage }) {
  try {
    const stored = storage?.getItem(ATTRIBUTION_KEY);
    if (stored) {
      const parsed = validStoredAttribution(JSON.parse(stored));
      if (parsed) return parsed;
    }
  } catch {
    // Storage can be unavailable in private browsing; attribution remains in memory.
  }

  let url;
  try {
    url = new URL(locationHref);
  } catch {
    url = new URL('https://cardcompass.invalid/');
  }

  const attribution = {
    source: cleanSlug(url.searchParams.get('source')),
    utm_source: cleanWithin(url.searchParams.get('utm_source'), UTM_LIMITS.utm_source),
    utm_medium: cleanWithin(url.searchParams.get('utm_medium'), UTM_LIMITS.utm_medium),
    utm_campaign: cleanWithin(url.searchParams.get('utm_campaign'), UTM_LIMITS.utm_campaign),
    utm_term: cleanWithin(url.searchParams.get('utm_term'), UTM_LIMITS.utm_term),
    utm_content: cleanWithin(url.searchParams.get('utm_content'), UTM_LIMITS.utm_content),
    referrer_path: referrerPath(referrer),
    landing_variant: cleanSlug(url.searchParams.get('landing_variant')) || cleanSlug(variant),
  };

  try {
    storage?.setItem(ATTRIBUTION_KEY, JSON.stringify(attribution));
  } catch {
    // The RPC still receives this in-memory first touch when persistence is blocked.
  }
  return attribution;
}

export function stripAnalyticsUrl(value) {
  try {
    const url = new URL(value);
    url.search = '';
    url.hash = '';
    return url.href;
  } catch {
    return null;
  }
}

function safeAnalyticsProps(props) {
  if (!props || typeof props !== 'object' || Array.isArray(props)) return {};
  const safe = {};
  for (const [key, value] of Object.entries(props)) {
    if (EVENT_PROP_KEYS.has(key) && cleanSlug(value)) safe[key] = value.trim();
  }
  return safe;
}

export function sanitizeAnalyticsPayload(payload) {
  const safe = { d: ANALYTICS_DOMAIN, r: '' };
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return safe;

  if (payload.n === 'pageview' || EVENT_NAMES.has(payload.n)) safe.n = payload.n;

  const strippedUrl = stripAnalyticsUrl(payload.u);
  if (strippedUrl) safe.u = strippedUrl;

  if (Object.hasOwn(payload, 'p')) {
    const parsed = typeof payload.p === 'string' ? (() => {
      try { return JSON.parse(payload.p); } catch { return {}; }
    })() : payload.p;
    safe.p = safeAnalyticsProps(parsed);
  }

  return safe;
}

export function buildPlausibleEvent(name, context = {}, currentUrl) {
  if (!EVENT_NAMES.has(name)) return null;
  const options = { props: safeAnalyticsProps(context) };
  const strippedUrl = stripAnalyticsUrl(currentUrl);
  if (strippedUrl) options.url = strippedUrl;
  return { name, options };
}

export function searchCards(cards, query, selectedCards = []) {
  const needle = clean(query)?.toLocaleLowerCase();
  if (!needle || !Array.isArray(cards)) return [];
  const selected = new Set(selectedCards.map((value) => String(value).toLocaleLowerCase()));

  return cards
    .map((card) => ({
      id: String(card.id),
      bank: String(card.bank),
      card_name: String(card.card_name),
      label: `${card.bank} — ${card.card_name}`,
    }))
    .filter((card) => !selected.has(card.label.toLocaleLowerCase()))
    .filter((card) => `${card.bank} ${card.card_name}`.toLocaleLowerCase().includes(needle))
    .slice(0, 8);
}
