BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $fix_catalog_identity_alias_conflict_target$
DECLARE
  installed_definition text;
  fixed_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO installed_definition;
  fixed_definition := replace(
    installed_definition,
    'ON CONFLICT (card_id, normalized_alias) DO NOTHING',
    'ON CONFLICT ON CONSTRAINT card_catalog_aliases_card_id_normalized_alias_key DO NOTHING'
  );
  IF fixed_definition IS NOT DISTINCT FROM installed_definition THEN
    RAISE EXCEPTION 'catalog_identity_alias_conflict_target_source_missing';
  END IF;
  EXECUTE fixed_definition;
END;
$fix_catalog_identity_alias_conflict_target$;

DO $fix_catalog_identity_alias_conflict_target_acl$
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
    RAISE EXCEPTION 'catalog_identity_alias_conflict_target_acl_drift';
  END IF;
END;
$fix_catalog_identity_alias_conflict_target_acl$;

COMMIT;
