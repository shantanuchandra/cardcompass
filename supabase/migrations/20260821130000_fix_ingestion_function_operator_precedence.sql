BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $fix_ingestion_function_operator_precedence$
DECLARE
  task6_definition text;
  fixed_task6_definition text;
  task7_definition text;
  fixed_task7_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs,public.card_benefits_staging)'::regprocedure
  ) INTO task6_definition;
  fixed_task6_definition := replace(
    task6_definition,
    'decision.value->>''proposal_index''',
    '(decision.value->>''proposal_index'')'
  );
  fixed_task6_definition := replace(
    fixed_task6_definition,
    'decision.value->>''benefit_id''',
    '(decision.value->>''benefit_id'')'
  );
  IF fixed_task6_definition IS NOT DISTINCT FROM task6_definition THEN
    RAISE EXCEPTION 'task6_operator_precedence_source_missing';
  END IF;
  EXECUTE fixed_task6_definition;

  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO task7_definition;
  fixed_task7_definition := replace(
    task7_definition,
    'issuer_quarantine_anchor.evidence->''quarantine_fence''->>''episode''',
    '(issuer_quarantine_anchor.evidence->''quarantine_fence''->>''episode'')'
  );
  IF fixed_task7_definition IS NOT DISTINCT FROM task7_definition THEN
    RAISE EXCEPTION 'task7_operator_precedence_source_missing';
  END IF;
  EXECUTE fixed_task7_definition;
END;
$fix_ingestion_function_operator_precedence$;

DO $fix_ingestion_function_operator_precedence_acl$
BEGIN
  IF NOT has_function_privilege(
       'service_role',
       'public.card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs,public.card_benefits_staging)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs,public.card_benefits_staging)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.card_enrichment_pilot_evidence_is_qualified(public.card_catalog_enrichment_jobs,public.card_benefits_staging)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'ingestion_function_operator_precedence_acl_drift';
  END IF;
END;
$fix_ingestion_function_operator_precedence_acl$;

COMMIT;
