export function oauthAppCallbackUrl(currentUrl) {
  let current;
  try {
    current = new URL(currentUrl);
  } catch {
    return null;
  }

  const code = current.searchParams.get('code');
  if (!code || code.length > 2048) return null;

  const target = new URL('/app/', current.origin);
  target.searchParams.set('code', code);
  return target.toString();
}

if (typeof window !== 'undefined') {
  const target = oauthAppCallbackUrl(window.location.href);
  if (target) window.location.replace(target);
}
