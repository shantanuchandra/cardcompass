BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $fix_catalog_identity_block_qualification$
DECLARE
  installed_definition text;
  fixed_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO installed_definition;
  fixed_definition := replace(
    installed_definition,
    'AS $function$
DECLARE',
    'AS $function$
<<publish_card_catalog_identity_block>>
DECLARE'
  );
  fixed_definition := replace(
    fixed_definition,
    'publish_card_catalog_identity.',
    'publish_card_catalog_identity_block.'
  );
  IF fixed_definition IS NOT DISTINCT FROM installed_definition
     OR fixed_definition NOT LIKE '%<<publish_card_catalog_identity_block>>%'
     OR fixed_definition NOT LIKE '%publish_card_catalog_identity_block.content_hash%'
     OR fixed_definition NOT LIKE '%publish_card_catalog_identity_block.retrieved_at%'
     OR fixed_definition NOT LIKE '%publish_card_catalog_identity_block.resolved_card_id%'
     OR fixed_definition LIKE '%publish_card_catalog_identity.content_hash%'
     OR fixed_definition LIKE '%publish_card_catalog_identity.retrieved_at%'
     OR fixed_definition LIKE '%publish_card_catalog_identity.resolved_card_id%' THEN
    RAISE EXCEPTION 'catalog_identity_block_qualification_source_missing';
  END IF;
  EXECUTE fixed_definition;
END;
$fix_catalog_identity_block_qualification$;

DO $fix_catalog_identity_block_qualification_acl$
BEGIN
  IF NOT has_function_privilege(
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
    RAISE EXCEPTION 'catalog_identity_block_qualification_acl_drift';
  END IF;
END;
$fix_catalog_identity_block_qualification_acl$;

COMMIT;
