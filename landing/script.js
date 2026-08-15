import { SUPABASE_URL, SUPABASE_ANON } from '/env.js';
import {
  buildApplicationReceipt,
  buildEnrichmentPayload,
  buildJoinPayload,
  buildPlausibleEvent,
  captureFirstTouch,
  extractEnrichmentToken,
  isValidEmail,
  sanitizeAnalyticsPayload,
  searchCards,
  stripAnalyticsUrl,
  validateQualification,
} from '/landing/waitlist.js';

let supabaseClientPromise = null;

async function getSupabaseClient() {
  if (!SUPABASE_URL || !SUPABASE_ANON) return null;
  supabaseClientPromise ||= import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm')
    .then(({ createClient }) => createClient(SUPABASE_URL, SUPABASE_ANON));
  return supabaseClientPromise;
}

const landingVariant = document.documentElement.dataset.landingVariant || 'receipt_v1';
let attributionStorage = null;
try { attributionStorage = window.localStorage; } catch { /* Storage is optional. */ }
const attribution = captureFirstTouch({
  locationHref: window.location.href,
  referrer: document.referrer,
  variant: landingVariant,
  storage: attributionStorage,
});

window.plausible = window.plausible || function plausible() {
  (window.plausible.q = window.plausible.q || []).push(arguments);
};
window.plausible.init = window.plausible.init || function init(options) {
  window.plausible.o = options || {};
};
window.plausible.init({
  autoCapturePageviews: false,
  logging: false,
  transformRequest: sanitizeAnalyticsPayload,
});

// The configured data-domain tracker is Plausible's legacy-compatible URL.
// Keep a final request guard until a site-specific pa-*.js URL is available:
// old builds ignore init options, while current builds safely sanitize twice.
const nativeFetch = window.fetch.bind(window);
let manualPageviewEnabled = false;
window.fetch = function guardedFetch(input, init = {}) {
  const requestUrl = typeof input === 'string' ? input : input?.url;
  if (requestUrl === 'https://plausible.io/api/event' && typeof init.body === 'string') {
    try {
      const payload = JSON.parse(init.body);
      if (payload.n === 'pageview' && !manualPageviewEnabled) {
        return Promise.resolve(new Response(null, { status: 202 }));
      }
      init = { ...init, body: JSON.stringify(sanitizeAnalyticsPayload(payload)) };
    } catch {
      return Promise.resolve(new Response(null, { status: 202 }));
    }
  }
  return nativeFetch(input, init);
};

const plausibleScript = document.createElement('script');
plausibleScript.async = true;
plausibleScript.dataset.domain = 'cardcompass.in';
plausibleScript.src = 'https://plausible.io/js/script.js';
plausibleScript.addEventListener('load', () => {
  manualPageviewEnabled = true;
  window.plausible('pageview', { url: stripAnalyticsUrl(window.location.href) });
}, { once: true });
document.head.append(plausibleScript);

function track(name, context = {}) {
  const event = buildPlausibleEvent(name, context, window.location.href);
  if (event) window.plausible(event.name, event.options);
}

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const siteHeader = document.getElementById('siteHeader');
const joinForm = document.getElementById('joinForm');
const joinButton = document.getElementById('joinButton');
const emailInput = document.getElementById('email');
const privacyConsent = document.getElementById('privacyConsent');
const stepOne = document.getElementById('waitlistStepOne');
const stepTwo = document.getElementById('waitlistStepTwo');
const qualificationForm = document.getElementById('qualificationForm');
const qualificationButton = document.getElementById('qualificationButton');
const qualificationStatus = document.getElementById('qualificationStatus');
const successState = document.getElementById('waitlistSuccess');
const problemDetail = document.getElementById('problemDetail');
const problemCounter = document.getElementById('problemCounter');
const cardSearch = document.getElementById('cardSearch');
const cardSuggestions = document.getElementById('cardSuggestions');
const selectedCardsElement = document.getElementById('selectedCards');

let activePlacement = 'hero';
let enrichmentToken = null;
let waitlistStartedTracked = false;
let cardCatalog = [];
let selectedCards = [];
let activeSuggestion = -1;

function setBusy(button, busy, busyLabel, idleLabel) {
  button.disabled = busy;
  button.textContent = busy ? busyLabel : idleLabel;
}

function setError(input, errorElement, message) {
  input.setAttribute('aria-invalid', message ? 'true' : 'false');
  errorElement.textContent = message;
}

function clearJoinErrors() {
  setError(emailInput, document.getElementById('emailError'), '');
  privacyConsent.setAttribute('aria-invalid', 'false');
  document.getElementById('privacyError').textContent = '';
}

function revealQualification() {
  stepOne.hidden = true;
  stepTwo.hidden = false;
  document.querySelector('[data-step-marker="1"]').classList.remove('is-current');
  document.querySelector('[data-step-marker="2"]').classList.add('is-current');
  document.querySelector('[data-step-marker="2"]').setAttribute('aria-current', 'step');
  document.getElementById('name').focus();
}

document.querySelectorAll('[data-waitlist-entry]').forEach((link) => {
  link.addEventListener('click', () => {
    activePlacement = link.dataset.waitlistEntry || 'hero';
    joinForm.dataset.placement = activePlacement;
  });
});

emailInput.addEventListener('focus', () => {
  if (waitlistStartedTracked) return;
  waitlistStartedTracked = true;
  track('Waitlist Started', {
    placement: activePlacement,
    step: 'email',
    variant: landingVariant,
  });
}, { once: true });

emailInput.addEventListener('input', () => {
  if (emailInput.getAttribute('aria-invalid') === 'true') {
    setError(emailInput, document.getElementById('emailError'), '');
  }
});

privacyConsent.addEventListener('change', () => {
  if (privacyConsent.checked) {
    privacyConsent.setAttribute('aria-invalid', 'false');
    document.getElementById('privacyError').textContent = '';
  }
});

joinForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearJoinErrors();

  let firstInvalid = null;
  if (!isValidEmail(emailInput.value)) {
    setError(emailInput, document.getElementById('emailError'), 'Enter a valid email address.');
    firstInvalid = emailInput;
  }
  if (!privacyConsent.checked) {
    privacyConsent.setAttribute('aria-invalid', 'true');
    document.getElementById('privacyError').textContent = 'Privacy consent is required to join.';
    firstInvalid ||= privacyConsent;
  }
  if (firstInvalid) {
    firstInvalid.focus();
    return;
  }

  if (!SUPABASE_URL || !SUPABASE_ANON) {
    setError(emailInput, document.getElementById('emailError'), 'Waitlist signups are temporarily unavailable. Please try again later.');
    track('Waitlist Error', { placement: activePlacement, step: 'email', variant: landingVariant, outcome: 'config_missing' });
    return;
  }

  setBusy(joinButton, true, 'Joining…', 'Continue');
  try {
    const supabase = await getSupabaseClient();
    if (!supabase) throw new Error('Waitlist is not configured.');
    const payload = buildJoinPayload({
      email: emailInput.value,
      privacyConsent: privacyConsent.checked,
      source: `landing_${activePlacement}`,
      attribution,
    });
    const { data, error } = await supabase.rpc('join_waitlist', payload);
    if (error) throw error;
    enrichmentToken = extractEnrichmentToken(data);
    track('Waitlist Joined', { placement: activePlacement, step: 'email', variant: landingVariant, outcome: 'accepted' });
    revealQualification();
  } catch {
    setError(emailInput, document.getElementById('emailError'), 'We could not join the waitlist. Check your connection and try again.');
    track('Waitlist Error', { placement: activePlacement, step: 'email', variant: landingVariant, outcome: 'rpc_failure' });
  } finally {
    setBusy(joinButton, false, 'Joining…', 'Continue');
  }
});

function qualificationValues() {
  return {
    name: document.getElementById('name').value,
    cardCount: document.getElementById('cardCount').value,
    monthlySpendBand: document.getElementById('monthlySpendBand').value,
    primaryGoal: document.getElementById('primaryGoal').value,
    problemDetail: problemDetail.value,
    topCards: selectedCards,
    marketingConsent: document.getElementById('marketingConsent').checked,
  };
}

const qualificationFields = {
  name: document.getElementById('name'),
  cardCount: document.getElementById('cardCount'),
  monthlySpendBand: document.getElementById('monthlySpendBand'),
  primaryGoal: document.getElementById('primaryGoal'),
  problemDetail,
  topCards: cardSearch,
};

function showQualificationErrors(errors) {
  let firstInvalid = null;
  for (const [key, input] of Object.entries(qualificationFields)) {
    const errorElement = document.getElementById(`${key}Error`);
    setError(input, errorElement, errors[key] || '');
    if (errors[key] && !firstInvalid) firstInvalid = input;
  }
  firstInvalid?.focus();
}

qualificationForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  qualificationStatus.textContent = '';
  const values = qualificationValues();
  const errors = validateQualification(values);
  showQualificationErrors(errors);
  if (Object.keys(errors).length) return;

  if (!SUPABASE_URL || !SUPABASE_ANON || !enrichmentToken) {
    qualificationStatus.textContent = 'Your secure application session expired. Please reload and join again.';
    track('Waitlist Error', { placement: activePlacement, step: 'qualification', variant: landingVariant, outcome: 'session_missing' });
    return;
  }

  setBusy(qualificationButton, true, 'Saving…', 'Complete my application');
  try {
    const supabase = await getSupabaseClient();
    if (!supabase) throw new Error('Waitlist is not configured.');
    const payload = buildEnrichmentPayload({ token: enrichmentToken, ...values });
    const { data, error } = await supabase.rpc('enrich_waitlist', payload);
    if (error || data !== true) throw error || new Error('Enrichment was not accepted');
    const applicationReceipt = buildApplicationReceipt(data);
    enrichmentToken = null;
    stepTwo.hidden = true;
    document.querySelector('.step-meter').hidden = true;
    document.getElementById('successEyebrow').textContent = applicationReceipt.eyebrow;
    document.getElementById('successTitle').textContent = applicationReceipt.title;
    document.getElementById('successBody').textContent = applicationReceipt.body;
    successState.hidden = false;
    track(applicationReceipt.eventName, { placement: activePlacement, step: 'qualification', variant: landingVariant, outcome: 'accepted' });
    successState.focus();
  } catch {
    qualificationStatus.textContent = 'We could not save your answers. Check your connection and try again.';
    track('Waitlist Error', { placement: activePlacement, step: 'qualification', variant: landingVariant, outcome: 'rpc_failure' });
  } finally {
    setBusy(qualificationButton, false, 'Saving…', 'Complete my application');
  }
});

problemDetail.addEventListener('input', () => {
  problemCounter.textContent = `${problemDetail.value.length} / 500`;
});

function renderSelectedCards() {
  selectedCardsElement.replaceChildren();
  selectedCards.forEach((label, index) => {
    const chip = document.createElement('span');
    chip.className = 'card-chip';
    chip.textContent = label;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.setAttribute('aria-label', `Remove ${label}`);
    remove.textContent = '×';
    remove.addEventListener('click', () => {
      selectedCards.splice(index, 1);
      renderSelectedCards();
      updateSuggestions();
    });
    chip.append(remove);
    selectedCardsElement.append(chip);
  });
  cardSearch.disabled = selectedCards.length >= 2;
  cardSearch.placeholder = selectedCards.length >= 2 ? 'Two cards selected' : 'Search bank or card name';
}

function chooseCard(label) {
  if (selectedCards.length >= 2 || selectedCards.includes(label)) return;
  selectedCards.push(label);
  cardSearch.value = '';
  cardSearch.setAttribute('aria-expanded', 'false');
  cardSearch.removeAttribute('aria-activedescendant');
  cardSuggestions.hidden = true;
  renderSelectedCards();
  document.getElementById('topCardsError').textContent = '';
}

function updateSuggestions() {
  const matches = searchCards(cardCatalog, cardSearch.value, selectedCards);
  cardSuggestions.replaceChildren();
  activeSuggestion = -1;
  cardSearch.removeAttribute('aria-activedescendant');
  matches.forEach((card) => {
    const item = document.createElement('li');
    item.id = `card-option-${card.id.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
    item.setAttribute('role', 'option');
    item.setAttribute('aria-selected', 'false');
    item.dataset.label = card.label;
    item.textContent = card.label;
    item.addEventListener('pointerdown', (event) => event.preventDefault());
    item.addEventListener('click', () => chooseCard(card.label));
    cardSuggestions.append(item);
  });
  const open = matches.length > 0 && selectedCards.length < 2;
  cardSuggestions.hidden = !open;
  cardSearch.setAttribute('aria-expanded', String(open));
}

function moveSuggestion(direction) {
  const options = [...cardSuggestions.querySelectorAll('[role="option"]')];
  if (!options.length) return;
  activeSuggestion = (activeSuggestion + direction + options.length) % options.length;
  options.forEach((option, index) => {
    const active = index === activeSuggestion;
    option.classList.toggle('is-active', active);
    option.setAttribute('aria-selected', String(active));
  });
  cardSearch.setAttribute('aria-activedescendant', options[activeSuggestion].id);
  options[activeSuggestion].scrollIntoView({ block: 'nearest' });
}

cardSearch.addEventListener('input', updateSuggestions);
cardSearch.addEventListener('focus', updateSuggestions);
cardSearch.addEventListener('blur', () => {
  cardSuggestions.hidden = true;
  cardSearch.setAttribute('aria-expanded', 'false');
  cardSearch.removeAttribute('aria-activedescendant');
});
cardSearch.addEventListener('keydown', (event) => {
  if (event.key === 'ArrowDown') {
    event.preventDefault();
    moveSuggestion(1);
  } else if (event.key === 'ArrowUp') {
    event.preventDefault();
    moveSuggestion(-1);
  } else if (event.key === 'Enter' && activeSuggestion >= 0) {
    event.preventDefault();
    const activeOption = cardSuggestions.querySelectorAll('[role="option"]')[activeSuggestion];
    if (activeOption) chooseCard(activeOption.dataset.label);
  } else if (event.key === 'Escape') {
    cardSuggestions.hidden = true;
    cardSearch.setAttribute('aria-expanded', 'false');
    cardSearch.removeAttribute('aria-activedescendant');
  }
});

fetch('/landing/card-catalog.json', { cache: 'force-cache' })
  .then((response) => response.ok ? response.json() : Promise.reject(new Error('catalog unavailable')))
  .then((cards) => { cardCatalog = Array.isArray(cards) ? cards : []; })
  .catch(() => { cardCatalog = []; });

const scenarios = {
  groceries: {
    number: 'CC-0815-01', merchant: 'Neighbourhood grocery', amount: '₹2,400', card: 'Example Cashback Card',
    value: '₹120', rate: '5% cashback', caveat: 'Category eligibility and monthly cashback cap',
    reason: 'Higher example return than the other cards in this demo wallet',
  },
  dining: {
    number: 'CC-0815-02', merchant: 'Weekend restaurant', amount: '₹3,200', card: 'Example Dining Card',
    value: '₹320', rate: '10% example value', caveat: 'Partner restaurant list and per-transaction cap',
    reason: 'Partner offer beats the base rewards in this illustrative comparison',
  },
  movies: {
    number: 'CC-0815-03', merchant: 'Two cinema tickets', amount: '₹900', card: 'Example Movie Card',
    value: '₹450', rate: 'Illustrative BOGO', caveat: 'Booking channel, ticket limit, and monthly usage',
    reason: 'The example ticket benefit is worth more than a standard earn rate here',
  },
};

const receiptFields = {
  number: document.getElementById('receiptNumber'),
  merchant: document.getElementById('receiptMerchant'),
  amount: document.getElementById('receiptAmount'),
  card: document.getElementById('receiptCard'),
  value: document.getElementById('receiptReturn'),
  rate: document.getElementById('receiptRate'),
  caveat: document.getElementById('receiptCaveat'),
  reason: document.getElementById('receiptReason'),
};
const receipt = document.getElementById('decisionReceipt');

function updateReceipt(scenarioName) {
  const scenario = scenarios[scenarioName];
  if (!scenario) return;
  document.querySelectorAll('.scenario-tab').forEach((tab) => {
    const active = tab.dataset.scenario === scenarioName;
    tab.classList.toggle('is-active', active);
    tab.setAttribute('aria-pressed', String(active));
  });
  receipt.classList.add('is-updating');
  const apply = () => {
    Object.entries(receiptFields).forEach(([key, element]) => { element.textContent = scenario[key]; });
    receipt.classList.remove('is-updating');
  };
  prefersReducedMotion ? apply() : window.setTimeout(apply, 120);
  track('Recommendation Preview Changed', { variant: landingVariant, outcome: scenarioName });
}

document.querySelectorAll('.scenario-tab').forEach((tab) => {
  tab.addEventListener('click', () => updateReceipt(tab.dataset.scenario));
});

function updateHeader() {
  siteHeader.classList.toggle('is-scrolled', window.scrollY > 24);
}
window.addEventListener('scroll', updateHeader, { passive: true });
updateHeader();
