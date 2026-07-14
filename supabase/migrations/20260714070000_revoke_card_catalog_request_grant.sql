-- Migration 20260714060000 granted `authenticated` EXECUTE on
-- submit_card_catalog_request so the Flutter client could call it directly.
-- That was unnecessary: supabase/functions/request-card-catalog-entry
-- already exists as the intended server-side path — it validates input,
-- checks the card URL is HTTPS, and calls this RPC using the service-role
-- key. The Dart client (data_pipeline_debug_service.dart) now calls that
-- edge function instead of the RPC directly, so revoke the broader grant
-- and restore submit_card_catalog_request to service_role-only, matching
-- the rest of the card_catalog/card_benefits_staging write surface locked
-- down in 20260712043000_security_and_email_hardening.sql.
REVOKE EXECUTE ON FUNCTION public.submit_card_catalog_request(uuid, text, text, text)
  FROM authenticated;
