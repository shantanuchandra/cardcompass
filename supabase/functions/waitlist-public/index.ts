// Fail-closed placeholder for the launch-blocking Turnstile boundary.
// Do not proxy join_waitlist until the README contract and behavioral tests
// are implemented with externally configured secrets.
Deno.serve(() => new Response(
  JSON.stringify({ status: 'unavailable' }),
  {
    status: 503,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  },
));
