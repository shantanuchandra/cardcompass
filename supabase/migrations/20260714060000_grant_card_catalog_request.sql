-- The 2026-07-12 security-hardening migration locked card_catalog writes to
-- service_role and added submit_card_catalog_request as the authenticated
-- path for queuing new-card requests for admin review, but granted EXECUTE
-- only to service_role — leaving it unreachable from the client app. The
-- app's manual "Card URL Required" flow still attempted a direct INSERT into
-- card_catalog, which authenticated cannot do, so every submission failed
-- with a Postgres permission error (surfacing client-side as PGRST116 once
-- .single() found no returned row).
--
-- submit_card_catalog_request is SECURITY DEFINER and does its own
-- validation, per-user rate limiting, and dedup — it only queues a row into
-- card_benefits_staging for review, so granting authenticated EXECUTE does
-- not let clients write to card_catalog directly.
GRANT EXECUTE ON FUNCTION public.submit_card_catalog_request(uuid, text, text, text)
  TO authenticated;
