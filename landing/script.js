import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ── Config ──────────────────────────────────────────────────────────────────
// Replace with real values before deploying. These are intentionally visible
// (anon key only — RLS prevents reads; insert+update own row only).
const SUPABASE_URL  = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON = 'YOUR_ANON_KEY';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);

// ── Email validation ─────────────────────────────────────────────────────────
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidEmail(v) {
  return EMAIL_RE.test(v.trim());
}

// ── Waitlist submit ──────────────────────────────────────────────────────────
// Returns { id, alreadyExists } or throws on network error.
async function submitEmail(email) {
  const { data, error } = await supabase
    .from('waitlist')
    .insert({ email: email.trim() })
    .select('id')
    .single();

  if (error) {
    if (error.code === '23505') return { id: null, alreadyExists: true };
    throw error;
  }
  return { id: data.id, alreadyExists: false };
}

// ── Enrichment update ────────────────────────────────────────────────────────
async function submitEnrichment(id, name, cardCount) {
  const update = {};
  if (name.trim())      update.name       = name.trim();
  if (cardCount.trim()) update.card_count = cardCount.trim();
  if (!Object.keys(update).length) return;

  await supabase.from('waitlist').update(update).eq('id', id);
}

// ── Modal ────────────────────────────────────────────────────────────────────
let pendingWaitlistId = null;

const overlay    = document.getElementById('modalOverlay');
const modalForm  = document.getElementById('modalForm');
const modalClose = document.getElementById('modalClose');
const modalSkip  = document.getElementById('modalSkip');

function openModal(waitlistId) {
  pendingWaitlistId = waitlistId;
  overlay.removeAttribute('aria-hidden');
  overlay.classList.add('is-open');
  document.getElementById('modalName').focus();
}

function trapFocus(e) {
  if (!overlay.classList.contains('is-open')) return;
  const focusable = Array.from(overlay.querySelectorAll('input, select, button'));
  const first = focusable[0];
  const last  = focusable[focusable.length - 1];
  if (e.key === 'Tab') {
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault(); last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault(); first.focus();
    }
  }
}

document.addEventListener('keydown', trapFocus);

function closeModal() {
  overlay.setAttribute('aria-hidden', 'true');
  overlay.classList.remove('is-open');
  pendingWaitlistId = null;
}

modalClose.addEventListener('click', closeModal);
modalSkip.addEventListener('click', closeModal);
overlay.addEventListener('click', (e) => { if (e.target === overlay) closeModal(); });

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && overlay.classList.contains('is-open')) closeModal();
});

modalForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!pendingWaitlistId) { closeModal(); return; }
  const name      = document.getElementById('modalName').value;
  const cardCount = document.getElementById('modalCardCount').value;
  try {
    await submitEnrichment(pendingWaitlistId, name, cardCount);
  } catch {
    // enrichment is optional — close modal regardless, failure is non-blocking
  }
  closeModal();
});

// ── Wire a waitlist form ─────────────────────────────────────────────────────
function wireForm(formId, emailInputId, submitBtnId, errorSpanId) {
  const form      = document.getElementById(formId);
  const emailEl   = document.getElementById(emailInputId);
  const submitBtn = document.getElementById(submitBtnId);
  const errorEl   = document.getElementById(errorSpanId);

  emailEl.addEventListener('input', () => {
    const valid = isValidEmail(emailEl.value);
    submitBtn.disabled = !valid;
    if (valid) {
      emailEl.classList.remove('is-invalid');
      errorEl.textContent = '';
    }
  });

  emailEl.addEventListener('blur', () => {
    if (emailEl.value && !isValidEmail(emailEl.value)) {
      emailEl.classList.add('is-invalid');
      errorEl.textContent = 'Please enter a valid email address.';
    }
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (form.classList.contains('joined')) return;
    if (!isValidEmail(emailEl.value)) return;

    submitBtn.disabled = true;
    submitBtn.textContent = 'Joining…';

    try {
      const { id, alreadyExists } = await submitEmail(emailEl.value);

      if (alreadyExists) {
        form.classList.add('joined', 'already-joined');
      } else {
        form.classList.add('joined');
        setTimeout(() => openModal(id), 300);
      }
    } catch {
      submitBtn.disabled = false;
      submitBtn.textContent = 'Get Early Access';
      errorEl.textContent = 'Something went wrong. Please try again.';
    }
  });
}

wireForm('heroForm',   'heroEmail',   'heroSubmitBtn',   'heroEmailError');
wireForm('bottomForm', 'bottomEmail', 'bottomSubmitBtn', 'bottomEmailError');

// ── Nav scroll state ─────────────────────────────────────────────────────────
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.classList.toggle('scrolled', window.scrollY > 40);
}, { passive: true });

// ── Scroll fade-in ───────────────────────────────────────────────────────────
const fadeObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('in-view');
      fadeObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.15 });

document.querySelectorAll('.fade-in').forEach(el => fadeObserver.observe(el));

// ── Count-up animation ───────────────────────────────────────────────────────
const countObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    const el  = entry.target;
    const end = parseInt(el.dataset.count, 10);
    const dur = 1200;
    const start = performance.now();
    function tick(now) {
      const progress = Math.min((now - start) / dur, 1);
      el.textContent = Math.floor(progress * end);
      if (progress < 1) requestAnimationFrame(tick);
      else el.textContent = end;
    }
    requestAnimationFrame(tick);
    countObserver.unobserve(el);
  });
}, { threshold: 0.5 });

document.querySelectorAll('[data-count]').forEach(el => countObserver.observe(el));

// ── Magnetic buttons ─────────────────────────────────────────────────────────
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

if (!prefersReducedMotion) {
  document.querySelectorAll('.magnetic').forEach(el => {
    el.addEventListener('mousemove', (e) => {
      const rect = el.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width  / 2;
      const y = e.clientY - rect.top  - rect.height / 2;
      el.style.transform = `translate(${x * 0.18}px, ${y * 0.18}px)`;
    });
    el.addEventListener('mouseleave', () => {
      el.style.transform = '';
    });
  });
}

// ── Reduced motion: pause SVG blob animations ────────────────────────────────
if (prefersReducedMotion) {
  document.querySelectorAll('.blob-bg animate').forEach(el => el.setAttribute('dur', '99999s'));
}
