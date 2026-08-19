-- Read-only card-ingestion release baseline. Each row is ticket-safe metadata.
WITH audited_relations AS (
  SELECT unnest(ARRAY[
    'card_catalog',
    'benefits',
    'card_benefit_mapping',
    'card_benefits_staging',
    'card_catalog_enrichment_jobs',
    'card_catalog_provenance',
    'card_catalog_url_keys',
    'user_cards'
  ]) AS relation_name
), catalog_state AS (
  SELECT catalog.is_discontinued, count(*)::bigint AS row_count
  FROM public.card_catalog AS catalog
  GROUP BY catalog.is_discontinued
), exclusion_types AS (
  SELECT coalesce(jsonb_typeof(benefit.exclusions), 'null') AS exclusion_type,
         count(*)::bigint AS row_count
  FROM public.benefits AS benefit
  GROUP BY coalesce(jsonb_typeof(benefit.exclusions), 'null')
), multi_card_benefits AS (
  SELECT mapping.benefit_id,
         array_agg(DISTINCT mapping.card_id::text ORDER BY mapping.card_id::text) AS catalog_ids
  FROM public.card_benefit_mapping AS mapping
  GROUP BY mapping.benefit_id
  HAVING count(DISTINCT mapping.card_id) > 1
), orphan_mappings AS (
  SELECT mapping.mapping_id, mapping.card_id, mapping.benefit_id
  FROM public.card_benefit_mapping AS mapping
  LEFT JOIN public.card_catalog AS catalog ON catalog.id = mapping.card_id
  LEFT JOIN public.benefits AS benefit ON benefit.benefit_id = mapping.benefit_id
  WHERE catalog.id IS NULL OR benefit.benefit_id IS NULL
), duplicate_mappings AS (
  SELECT mapping.card_id, mapping.benefit_id, count(*)::bigint AS row_count
  FROM public.card_benefit_mapping AS mapping
  GROUP BY mapping.card_id, mapping.benefit_id
  HAVING count(*) > 1
), pending_staging AS (
  SELECT count(*)::bigint AS row_count,
         min(staging.created_at) AS oldest_created_at
  FROM public.card_benefits_staging AS staging
  WHERE staging.status = 'pending'
), job_groups AS (
  SELECT job.status, job.parser_version, job.run_mode, count(*)::bigint AS row_count
  FROM public.card_catalog_enrichment_jobs AS job
  GROUP BY job.status, job.parser_version, job.run_mode
), duplicate_catalog_identities AS (
  SELECT lower(trim(catalog.bank)) AS normalized_issuer,
         lower(regexp_replace(trim(catalog.card_name), '[^a-zA-Z0-9]+', '', 'g')) AS normalized_name,
         coalesce(lower(trim(catalog.network)), '') AS normalized_network,
         array_agg(catalog.id::text ORDER BY catalog.id::text) AS catalog_ids
  FROM public.card_catalog AS catalog
  GROUP BY
    lower(trim(catalog.bank)),
    lower(regexp_replace(trim(catalog.card_name), '[^a-zA-Z0-9]+', '', 'g')),
    coalesce(lower(trim(catalog.network)), '')
  HAVING count(*) > 1
), url_hash_claims AS (
  SELECT provenance.submitted_url_hash AS url_hash, provenance.card_id
  FROM public.card_catalog_provenance AS provenance
  WHERE provenance.submitted_url_hash IS NOT NULL
  UNION ALL
  SELECT provenance.final_url_hash AS url_hash, provenance.card_id
  FROM public.card_catalog_provenance AS provenance
  WHERE provenance.final_url_hash IS NOT NULL
  UNION ALL
  SELECT url_key.url_hash, url_key.card_id
  FROM public.card_catalog_url_keys AS url_key
), url_hash_conflicts AS (
  SELECT claim.url_hash,
         array_agg(DISTINCT claim.card_id::text ORDER BY claim.card_id::text) AS catalog_ids
  FROM url_hash_claims AS claim
  GROUP BY claim.url_hash
  HAVING count(DISTINCT claim.card_id) > 1
), catalog_without_provenance AS (
  SELECT catalog.id
  FROM public.card_catalog AS catalog
  WHERE catalog.card_url ~ '^https://'
    AND NOT EXISTS (
      SELECT 1
      FROM public.card_catalog_provenance AS provenance
      WHERE provenance.card_id = catalog.id
    )
), active_discontinued_user_cards AS (
  SELECT card.catalog_card_id
  FROM public.user_cards AS card
  JOIN public.card_catalog AS catalog ON catalog.id = card.catalog_card_id
  WHERE card.is_active IS TRUE
    AND catalog.is_discontinued IS TRUE
), rls_state AS (
  SELECT relation.relation_name, class.relrowsecurity AS enabled,
         class.relforcerowsecurity AS forced
  FROM audited_relations AS relation
  JOIN pg_namespace AS namespace ON namespace.nspname = 'public'
  JOIN pg_class AS class
    ON class.relnamespace = namespace.oid
   AND class.relname = relation.relation_name
), policy_state AS (
  SELECT policy.tablename, policy.policyname, policy.cmd,
         policy.roles::text AS roles
  FROM pg_policies AS policy
  JOIN audited_relations AS relation ON relation.relation_name = policy.tablename
  WHERE policy.schemaname = 'public'
), grants_by_relation AS (
  SELECT grant_row.table_name, grant_row.grantee, grant_row.privilege_type
  FROM information_schema.role_table_grants AS grant_row
  JOIN audited_relations AS relation ON relation.relation_name = grant_row.table_name
  WHERE grant_row.table_schema = 'public'
), grants_by_function AS (
  SELECT privilege.routine_name, privilege.grantee, privilege.privilege_type
  FROM information_schema.routine_privileges AS privilege
  WHERE privilege.routine_schema = 'public'
)
SELECT
  'catalog_counts_by_discontinued'::text AS check_name,
  coalesce((SELECT sum(row_count) FROM catalog_state), 0)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'is_discontinued', is_discontinued,
      'count', row_count
    ) ORDER BY is_discontinued NULLS FIRST)
    FROM catalog_state
  ), '[]'::jsonb) AS details
UNION ALL
SELECT
  'benefit_exclusions_jsonb_type'::text AS check_name,
  coalesce((SELECT sum(row_count) FROM exclusion_types), 0)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((
    SELECT jsonb_agg(jsonb_build_object('jsonb_type', exclusion_type, 'count', row_count)
      ORDER BY exclusion_type)
    FROM exclusion_types
  ), '[]'::jsonb) AS details
UNION ALL
SELECT
  'benefits_mapped_to_multiple_cards'::text AS check_name,
  (SELECT count(*) FROM multi_card_benefits)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(to_jsonb(catalog_ids) ORDER BY catalog_ids::text)
    FROM multi_card_benefits), '[]'::jsonb) AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('catalog_ids', catalog_ids)
    ORDER BY catalog_ids::text) FROM multi_card_benefits), '[]'::jsonb) AS details
UNION ALL
SELECT
  'orphan_card_benefit_mappings'::text AS check_name,
  (SELECT count(*) FROM orphan_mappings)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(DISTINCT card_id::text ORDER BY card_id::text)
    FROM orphan_mappings), '[]'::jsonb) AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('catalog_id', card_id) ORDER BY card_id::text)
    FROM orphan_mappings), '[]'::jsonb) AS details
UNION ALL
SELECT
  'duplicate_card_benefit_mappings'::text AS check_name,
  (SELECT count(*) FROM duplicate_mappings)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(card_id::text ORDER BY card_id::text) FROM duplicate_mappings), '[]'::jsonb) AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('catalog_id', card_id, 'count', row_count)
    ORDER BY card_id::text) FROM duplicate_mappings), '[]'::jsonb) AS details
UNION ALL
SELECT
  'pending_staging_age_and_count'::text AS check_name,
  (SELECT row_count FROM pending_staging)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  jsonb_build_object(
    'oldest_created_at', (SELECT oldest_created_at FROM pending_staging),
    'oldest_age', CASE WHEN (SELECT oldest_created_at FROM pending_staging) IS NULL THEN NULL
      ELSE now() - (SELECT oldest_created_at FROM pending_staging) END
  ) AS details
UNION ALL
SELECT
  'enrichment_jobs_by_status_parser_and_mode'::text AS check_name,
  coalesce((SELECT sum(row_count) FROM job_groups), 0)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('status', status, 'parser_version', parser_version,
    'run_mode', run_mode, 'count', row_count) ORDER BY status, parser_version, run_mode)
    FROM job_groups), '[]'::jsonb) AS details
UNION ALL
SELECT
  'duplicate_normalized_catalog_identity'::text AS check_name,
  (SELECT count(*) FROM duplicate_catalog_identities)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(to_jsonb(catalog_ids) ORDER BY normalized_issuer, normalized_name, normalized_network)
    FROM duplicate_catalog_identities), '[]'::jsonb) AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('catalog_ids', catalog_ids)
    ORDER BY normalized_issuer, normalized_name, normalized_network)
    FROM duplicate_catalog_identities), '[]'::jsonb) AS details
UNION ALL
SELECT
  'submitted_final_url_key_conflicts'::text AS check_name,
  (SELECT count(*) FROM url_hash_conflicts)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(to_jsonb(catalog_ids) ORDER BY catalog_ids::text) FROM url_hash_conflicts), '[]'::jsonb) AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('catalog_ids', catalog_ids)
    ORDER BY catalog_ids::text) FROM url_hash_conflicts), '[]'::jsonb) AS details
UNION ALL
SELECT
  'missing_url_provenance'::text AS check_name,
  (SELECT count(*) FROM catalog_without_provenance)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(id::text ORDER BY id::text) FROM catalog_without_provenance), '[]'::jsonb) AS catalog_ids,
  jsonb_build_object('criterion', 'catalog card_url has no provenance row') AS details
UNION ALL
SELECT
  'active_user_cards_on_discontinued_catalog'::text AS check_name,
  (SELECT count(*) FROM active_discontinued_user_cards)::bigint AS finding_count,
  coalesce((SELECT jsonb_agg(DISTINCT catalog_card_id::text ORDER BY catalog_card_id::text)
    FROM active_discontinued_user_cards), '[]'::jsonb) AS catalog_ids,
  jsonb_build_object('affected_active_card_rows', (SELECT count(*) FROM active_discontinued_user_cards)) AS details
UNION ALL
SELECT
  'table_rls_state'::text AS check_name,
  (SELECT count(*) FROM rls_state WHERE NOT enabled)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('relation', relation_name, 'rls_enabled', enabled,
    'rls_forced', forced) ORDER BY relation_name) FROM rls_state), '[]'::jsonb) AS details
UNION ALL
SELECT
  'table_policies'::text AS check_name,
  (SELECT count(*) FROM policy_state)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('relation', tablename, 'policy', policyname,
    'command', cmd, 'roles', roles) ORDER BY tablename, policyname) FROM policy_state), '[]'::jsonb) AS details
UNION ALL
SELECT
  'relation_grants'::text AS check_name,
  (SELECT count(*) FROM grants_by_relation)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('relation', table_name, 'grantee', grantee,
    'privilege', privilege_type) ORDER BY table_name, grantee, privilege_type)
    FROM grants_by_relation), '[]'::jsonb) AS details
UNION ALL
SELECT
  'function_grants'::text AS check_name,
  (SELECT count(*) FROM grants_by_function)::bigint AS finding_count,
  '[]'::jsonb AS catalog_ids,
  coalesce((SELECT jsonb_agg(jsonb_build_object('function', routine_name, 'grantee', grantee,
    'privilege', privilege_type) ORDER BY routine_name, grantee, privilege_type)
    FROM grants_by_function), '[]'::jsonb) AS details
ORDER BY check_name;
