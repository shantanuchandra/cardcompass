-- A reviewed fee/page edit must not re-validate unrelated legacy sibling
-- identities unless the target actually moves family, network, or tier.
--
-- Fresh databases already receive the guarded body from Task 7. This patch
-- upgrades databases where the later candidate-scope repair was installed
-- against the older unguarded publisher, without changing the function
-- signature, grants, or schema shape.
DO $migration$
DECLARE
  publisher regprocedure := to_regprocedure(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'
  );
  publisher_body text;
  conflict_start_marker constant text :=
    'WITH family_candidates AS MATERIALIZED (';
  conflict_end_marker constant text := E'        IF new_family_conflict IS NOT NULL THEN\n          RAISE EXCEPTION ''edit_target_conflict'';\n        END IF;\n        -- Validate stored column/name network agreement even if the review did';
  identity_change_guard constant text := E'        IF edit_old_identity_lock IS DISTINCT FROM edit_new_identity_lock\n           OR (\n                reviewed_network IS NOT NULL\n                AND public.card_catalog_effective_network(\n                  edit_target_network, edit_target_name, edit_target_bank\n                ) IS DISTINCT FROM reviewed_network\n              )\n           OR public.normalize_card_catalog_tier(edit_target_name)\n                IS DISTINCT FROM reviewed_tier THEN';
  resolver_marker constant text := $resolver$
        resolved_card_id := public.resolve_card_catalog_identity(
          edit_target_bank, edit_target_name, edit_target_network,
          final_url, submitted_hash, final_hash
        );
        IF resolved_card_id <> edit_target_card_id THEN
          RAISE EXCEPTION 'edit_target_conflict';
        END IF;$resolver$;
  page_only_binding constant text := $binding$
        -- page_only_edit_url_binding: an unchanged explicit identity is already
        -- bound by its locked target and baseline. Reconcile both URL histories
        -- directly so malformed unrelated siblings cannot block a fee/page edit.
        IF edit_old_identity_lock IS NOT DISTINCT FROM edit_new_identity_lock
           AND (
             reviewed_network IS NULL
             OR public.card_catalog_effective_network(
                  edit_target_network, edit_target_name, edit_target_bank
                ) IS NOT DISTINCT FROM reviewed_network
           )
           AND public.normalize_card_catalog_tier(edit_target_name)
                IS NOT DISTINCT FROM reviewed_tier THEN
          IF EXISTS (
            SELECT 1
            FROM (
              SELECT key.card_id
              FROM public.card_catalog_url_keys AS key
              WHERE key.url_hash IN (submitted_hash, final_hash)
              UNION
              SELECT provenance.card_id
              FROM public.card_catalog_provenance AS provenance
              WHERE provenance.submitted_url_hash IN (submitted_hash, final_hash)
                 OR provenance.final_url_hash IN (submitted_hash, final_hash)
            ) AS bound
            WHERE bound.card_id <> edit_target_card_id
          ) THEN
            RAISE EXCEPTION 'edit_target_conflict';
          END IF;
          resolved_card_id := edit_target_card_id;
        ELSE
          resolved_card_id := public.resolve_card_catalog_identity(
            edit_target_bank, edit_target_name, edit_target_network,
            final_url, submitted_hash, final_hash
          );
          IF resolved_card_id <> edit_target_card_id THEN
            RAISE EXCEPTION 'edit_target_conflict';
          END IF;
        END IF;$binding$;
  publisher_changed boolean := false;
BEGIN
  IF publisher IS NULL THEN
    RAISE EXCEPTION 'catalog_publication_function_missing';
  END IF;

  SELECT routine.prosrc INTO publisher_body
  FROM pg_proc AS routine
  WHERE routine.oid = publisher::oid;

  IF strpos(publisher_body, identity_change_guard) = 0 THEN
    IF (
      length(publisher_body) - length(replace(
        publisher_body, conflict_start_marker, ''
      ))
    ) / length(conflict_start_marker) <> 1
       OR (
         length(publisher_body) - length(replace(
           publisher_body, conflict_end_marker, ''
         ))
       ) / length(conflict_end_marker) <> 1 THEN
      RAISE EXCEPTION 'catalog_page_only_edit_patch_anchor_mismatch';
    END IF;

    publisher_body := replace(
      publisher_body,
      conflict_start_marker,
      identity_change_guard || E'\n          WITH family_candidates AS MATERIALIZED ('
    );
    publisher_body := replace(
      publisher_body,
      conflict_end_marker,
      E'          IF new_family_conflict IS NOT NULL THEN\n            RAISE EXCEPTION ''edit_target_conflict'';\n          END IF;\n        END IF;\n        -- Validate stored column/name network agreement even if the review did'
    );
    publisher_changed := true;
  END IF;

  IF strpos(publisher_body, 'page_only_edit_url_binding') = 0 THEN
    IF (
      length(publisher_body) - length(replace(
        publisher_body, resolver_marker, ''
      ))
    ) / length(resolver_marker) <> 1 THEN
      RAISE EXCEPTION 'catalog_page_only_edit_resolver_anchor_mismatch';
    END IF;
    publisher_body := replace(
      publisher_body, resolver_marker, page_only_binding
    );
    publisher_changed := true;
  END IF;

  IF publisher_changed THEN
    EXECUTE format(
      $definition$
      CREATE OR REPLACE FUNCTION public.publish_card_catalog_identity(
        _discovery_job_id uuid,
        _review_item_id uuid,
        _actor_id uuid,
        _action text,
        _reviewed_fields jsonb,
        _merge_card_id uuid,
        _reason text,
        _parser_version text
      ) RETURNS TABLE (card_id uuid, job_id uuid, resulting_status text)
      LANGUAGE plpgsql
      SECURITY INVOKER
      SET search_path = public, extensions, pg_temp
      AS %L
      $definition$,
      publisher_body
    );
  END IF;

  IF strpos(
    pg_get_functiondef(publisher),
    'IF edit_old_identity_lock IS DISTINCT FROM edit_new_identity_lock'
  ) = 0 THEN
    RAISE EXCEPTION 'catalog_page_only_edit_guard_missing';
  END IF;
  IF strpos(
    pg_get_functiondef(publisher),
    'page_only_edit_url_binding'
  ) = 0 THEN
    RAISE EXCEPTION 'catalog_page_only_edit_binding_missing';
  END IF;
  IF has_function_privilege(
    'authenticated', publisher, 'EXECUTE'
  ) OR NOT has_function_privilege('service_role', publisher, 'EXECUTE') THEN
    RAISE EXCEPTION 'catalog_publication_acl_changed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc AS routine
    WHERE routine.oid = publisher::oid AND routine.prosecdef
  ) THEN
    RAISE EXCEPTION 'catalog_publication_security_mode_changed';
  END IF;
END;
$migration$;
