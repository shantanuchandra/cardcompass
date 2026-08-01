// CardCompass — Login page: Google OAuth via Supabase
// ES module — loaded with type="module" in index.html

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ---------------------------------------------------------------------------
// Config — swap placeholders before deploying
// ---------------------------------------------------------------------------
const SUPABASE_URL  = 'https://prbcoxqobhjnnfnxevxf.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByYmNveHFvYmhqbm5mbnhldnhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3MjM1NDMsImV4cCI6MjA5OTI5OTU0M30.m0vUEsfu1FtIMw0WMhF7ojpxzMGf-M_xeb1LNdYNhuI';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);

// ---------------------------------------------------------------------------
// Redirect destination after successful sign-in
// ---------------------------------------------------------------------------
const isLocalhost = ['localhost', '127.0.0.1'].includes(window.location.hostname);
// On localhost: redirect to Flutter web dev server (port 54321).
// In prod: redirect to the main app domain.
const REDIRECT_URL = isLocalhost
  ? 'http://localhost:54321'
  : 'https://www.cardcompass.in';

// ---------------------------------------------------------------------------
// DOM refs
// ---------------------------------------------------------------------------
const btn      = document.getElementById('google-btn');
const errorEl  = document.getElementById('error-msg');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function setLoading(on) {
  if (on) {
    btn.classList.add('loading');
    btn.disabled = true;
    btn.setAttribute('aria-busy', 'true');
  } else {
    btn.classList.remove('loading');
    btn.disabled = false;
    btn.removeAttribute('aria-busy');
  }
}

function showError(message) {
  errorEl.textContent = message;
  errorEl.classList.add('visible');
}

function clearError() {
  errorEl.textContent = '';
  errorEl.classList.remove('visible');
}

// ---------------------------------------------------------------------------
// OAuth sign-in
// ---------------------------------------------------------------------------
async function signInWithGoogle() {
  clearError();
  setLoading(true);

  try {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: REDIRECT_URL,
        scopes: 'email profile https://www.googleapis.com/auth/gmail.readonly',
        queryParams: {
          access_type: 'offline',
          prompt: 'consent',
        },
      },
    });

    if (error) throw error;

    // signInWithOAuth redirects the browser — execution stops here on success.
    // If we somehow reach this point, keep the button in loading state until
    // the redirect fires (typically within a few ms).

  } catch (err) {
    setLoading(false);
    const message = err?.message
      ? `Sign-in failed: ${err.message}`
      : 'Something went wrong. Please try again.';
    showError(message);
    console.error('[CardCompass] OAuth error:', err);
  }
}

// ---------------------------------------------------------------------------
// Wire up button
// ---------------------------------------------------------------------------
btn.addEventListener('click', signInWithGoogle);

// ---------------------------------------------------------------------------
// Handle OAuth callback (hash-fragment tokens on return)
// ---------------------------------------------------------------------------
supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN' && session) {
    // Redirect to app — Supabase will have set the session cookie/storage
    window.location.href = REDIRECT_URL;
  }
});
