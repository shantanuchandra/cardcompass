BEGIN;

-- The original enrichment migration added benefit defaults to a queue that
-- already contained catalog-metadata work. Only repair rows whose terminal
-- shape proves they were produced by the legacy catalog worker. Queued or
-- otherwise ambiguous benefits-v1 rows intentionally remain untouched.
LOCK TABLE public.card_catalog_enrichment_jobs IN SHARE ROW EXCLUSIVE MODE;

WITH repairable AS (
  SELECT legacy.id,
    row_number() OVER (
      PARTITION BY legacy.card_id, legacy.final_url_hash
      ORDER BY legacy.created_at, legacy.id
    ) AS identity_rank
  FROM public.card_catalog_enrichment_jobs AS legacy
  WHERE legacy.parser_version = 'benefits-v1'
    AND legacy.run_mode = 'scheduled'
    AND legacy.content_hash IS NOT NULL
    AND legacy.staging_id IS NULL
    AND legacy.result_summary = '{}'::jsonb
    AND legacy.status IN ('completed', 'review_required', 'failed')
    AND NOT EXISTS (
      SELECT 1
      FROM public.card_catalog_enrichment_jobs AS catalog_job
      WHERE catalog_job.card_id = legacy.card_id
        AND catalog_job.final_url_hash = legacy.final_url_hash
        AND catalog_job.parser_version = 'catalog-v1'
        AND catalog_job.id <> legacy.id
    )
)
UPDATE public.card_catalog_enrichment_jobs AS legacy
SET parser_version = 'catalog-v1',
    run_mode = 'manual',
    updated_at = now()
FROM repairable
WHERE legacy.id = repairable.id
  AND repairable.identity_rank = 1;

COMMIT;
