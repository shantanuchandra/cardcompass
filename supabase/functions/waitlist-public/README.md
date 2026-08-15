# Waitlist public Edge boundary contract (launch-blocking)

This boundary is intentionally not marked complete or wired into production. The database honeypot and hashed-email bucket limit repeated calls for one normalized address, but they cannot provide trustworthy client-IP or CAPTCHA enforcement.

The checked-in `index.ts` is a fail-closed 503 placeholder. Before broad acquisition, replace it and test the implementation against this contract:

1. Accept `POST` only from the exact configured CardCompass origin; reject missing or mismatched `Origin`.
2. Require a Turnstile token and validate it server-side with `TURNSTILE_SECRET_KEY`, the expected hostname and expected action. Forward the request IP only to Turnstile verification; never store or log raw IP.
3. Forward only the allow-listed `join_waitlist` fields to Supabase using a server-only secret/service role. Never return or log server credentials.
4. Preserve the database's success-shaped duplicate response, apply bounded request/body timeouts, and return a neutral unavailable response when required secrets are absent.
5. After the Edge boundary is verified, revoke direct browser execution of `join_waitlist`, point the landing client to this function, and rerun duplicate/decoy, rate, CORS, missing-secret and Turnstile-failure tests.

Required external configuration: `TURNSTILE_SECRET_KEY`, the corresponding public site key, `WAITLIST_ALLOWED_ORIGIN`, and a server-only Supabase key. Until those exist and the behavioral tests pass, production launch remains blocked.
