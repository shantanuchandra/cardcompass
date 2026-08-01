// CardCompass — Login page: Google OAuth via Supabase
// ES module — loaded with type="module" in index.html

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON } from '../config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON);

// ---------------------------------------------------------------------------
// Redirect destination after successful sign-in
// ---------------------------------------------------------------------------
const isLocalhost = ['localhost', '127.0.0.1'].includes(window.location.hostname);

// Where to send the user after a successful sign-in.
const APP_URL = isLocalhost ? 'http://localhost:54321/app/' : 'https://www.cardcompass.in/app/';

// Supabase must redirect back to THIS page after OAuth so we can catch the
// session token. Once onAuthStateChange fires SIGNED_IN we forward to APP_URL.
const REDIRECT_URL = isLocalhost
  ? 'http://localhost:8080/login/'
  : 'https://www.cardcompass.in/login/';

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
    window.location.href = APP_URL;
  }
});
