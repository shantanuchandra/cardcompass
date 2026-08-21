BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $fix_catalog_identity_conflict_candidate_scope$
DECLARE
  installed_definition text;
  fixed_definition text;
  fragment_start integer;
  fragment_end integer;
  old_fragment text;
  new_fragment constant text := $new$
WITH family_candidates AS MATERIALIZED (
          SELECT conflict.id, conflict.bank, conflict.card_name, conflict.network
          FROM public.card_catalog AS conflict
          WHERE conflict.id <> edit_target_card_id
            AND lower(trim(conflict.bank)) = lower(trim(issuer))
            AND lower(trim(coalesce(conflict.card_type, ''))) = 'credit'
            AND coalesce(
              nullif(public.normalize_card_catalog_family(conflict.card_name), ''),
              public.normalize_card_catalog_product(conflict.card_name)
            ) = coalesce(
              nullif(public.normalize_card_catalog_family(reviewed_name), ''),
              public.normalize_card_catalog_product(reviewed_name)
            )
        ), compatible_candidates AS MATERIALIZED (
          SELECT conflict.id
          FROM family_candidates AS conflict
          WHERE public.card_catalog_effective_network(
              conflict.network, conflict.card_name, conflict.bank
            ) IS NOT DISTINCT FROM reviewed_network
            AND public.normalize_card_catalog_tier(conflict.card_name)
              IS NOT DISTINCT FROM reviewed_tier
        )
        SELECT conflict.id INTO new_family_conflict
        FROM public.card_catalog AS conflict
        JOIN compatible_candidates AS candidate ON candidate.id = conflict.id
        ORDER BY conflict.id
        LIMIT 1
        FOR UPDATE OF conflict;$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO installed_definition;
  fragment_start := strpos(
    installed_definition,
    'SELECT conflict.id INTO new_family_conflict'
  );
  fragment_end := strpos(
    installed_definition,
    'IF new_family_conflict IS NOT NULL'
  );
  IF fragment_start = 0 OR fragment_end <= fragment_start THEN
    RAISE EXCEPTION 'catalog_identity_conflict_candidate_scope_source_missing';
  END IF;
  old_fragment := substring(
    installed_definition FROM fragment_start FOR fragment_end - fragment_start
  );
  IF old_fragment NOT LIKE '%FROM public.card_catalog AS conflict%'
     OR old_fragment NOT LIKE '%card_catalog_effective_network%'
     OR old_fragment NOT LIKE '%FOR UPDATE%' THEN
    RAISE EXCEPTION 'catalog_identity_conflict_candidate_scope_source_missing';
  END IF;
  fixed_definition := substring(installed_definition FROM 1 FOR fragment_start - 1) ||
    new_fragment || E'\n        ' || substring(installed_definition FROM fragment_end);
  IF fixed_definition IS NOT DISTINCT FROM installed_definition
     OR fixed_definition NOT LIKE '%WITH family_candidates AS MATERIALIZED%'
     OR fixed_definition NOT LIKE '%FROM family_candidates AS conflict%'
     OR fixed_definition NOT LIKE '%FOR UPDATE OF conflict%' THEN
    RAISE EXCEPTION 'catalog_identity_conflict_candidate_scope_source_missing';
  END IF;
  EXECUTE fixed_definition;
END;
$fix_catalog_identity_conflict_candidate_scope$;

DO $fix_catalog_identity_conflict_candidate_scope_acl$
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
    RAISE EXCEPTION 'catalog_identity_conflict_candidate_scope_acl_drift';
  END IF;
END;
$fix_catalog_identity_conflict_candidate_scope_acl$;

COMMIT;
