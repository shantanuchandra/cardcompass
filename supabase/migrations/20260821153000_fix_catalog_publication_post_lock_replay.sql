BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $fix_catalog_publication_post_lock_replay$
DECLARE
  installed_definition text;
  fixed_definition text;
  old_fragment constant text := $old$
    observed_job := job_row;
  END IF;

  IF _review_item_id IS NOT NULL$old$;
  new_fragment constant text := $new$
    observed_job := job_row;
  ELSIF _review_item_id IS NOT NULL
     AND _action NOT IN ('retry', 'reject') THEN
    -- post_advisory_publication_replay_refresh: another publication may have
    -- completed while this request waited for the job advisory. Refresh the
    -- immutable replay snapshot without taking row locks before the shared
    -- URL/identity/card lock order.
    SELECT job.* INTO observed_job
    FROM public.card_discovery_jobs AS job
    WHERE job.id = _discovery_job_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'discovery_job_not_found'; END IF;
    SELECT review.* INTO observed_review
    FROM public.card_catalog_review_queue AS review
    WHERE review.id = _review_item_id
      AND review.discovery_job_id = observed_job.id;
    IF NOT FOUND THEN RAISE EXCEPTION 'review_item_not_found'; END IF;
    review_row := observed_review;
  END IF;

  IF _review_item_id IS NOT NULL$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.publish_card_catalog_identity(uuid,uuid,uuid,text,jsonb,uuid,text,text)'::regprocedure
  ) INTO installed_definition;
  fixed_definition := replace(installed_definition, old_fragment, new_fragment);
  IF fixed_definition IS NOT DISTINCT FROM installed_definition
     OR fixed_definition NOT LIKE '%post_advisory_publication_replay_refresh%'
     OR fixed_definition NOT LIKE '%SELECT job.* INTO observed_job%'
     OR fixed_definition NOT LIKE '%SELECT review.* INTO observed_review%' THEN
    RAISE EXCEPTION 'catalog_publication_post_lock_replay_source_missing';
  END IF;
  EXECUTE fixed_definition;
END;
$fix_catalog_publication_post_lock_replay$;

DO $fix_catalog_publication_post_lock_replay_acl$
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
    RAISE EXCEPTION 'catalog_publication_post_lock_replay_acl_drift';
  END IF;
END;
$fix_catalog_publication_post_lock_replay_acl$;

COMMIT;
