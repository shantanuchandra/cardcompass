-- Match the mapping-health report to the exact widened predicate used by
-- SupabaseMovieDealsDataSource. The benefits schema exposes benefit_category,
-- not scalar category/subcategory columns.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_movie_benefit_mapping_health()
RETURNS TABLE (metric text, value bigint)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH movie_benefits AS (
    SELECT benefit.benefit_id
    FROM public.benefits AS benefit
    WHERE benefit.is_active = true
      AND (
        benefit.benefit_category = 'entertainment'
        OR benefit.value_config ->> 'category' ILIKE '%movie%'
        OR benefit.value_config ->> 'discount_type' ILIKE '%movie%'
        OR benefit.title ILIKE '%movie%'
        OR benefit.description ILIKE '%movie%'
        OR benefit.title ILIKE '%cinema%'
        OR benefit.description ILIKE '%cinema%'
        OR benefit.title ILIKE '%bookmyshow%'
        OR benefit.description ILIKE '%bookmyshow%'
        OR benefit.title ILIKE '%pvr%'
        OR benefit.description ILIKE '%pvr%'
        OR benefit.title ILIKE '%inox%'
        OR benefit.description ILIKE '%inox%'
        OR benefit.title ILIKE '%cinepolis%'
        OR benefit.description ILIKE '%cinepolis%'
      )
  ), mapped_movie_benefits AS (
    SELECT DISTINCT movie.benefit_id
    FROM movie_benefits AS movie
    JOIN public.card_benefit_mapping AS mapping
      ON mapping.benefit_id = movie.benefit_id
  )
  SELECT 'active_movie_benefits'::text, count(*)::bigint
  FROM movie_benefits
  UNION ALL
  SELECT 'mapped_active_movie_benefits'::text, count(*)::bigint
  FROM mapped_movie_benefits
  UNION ALL
  SELECT 'orphaned_active_movie_benefits'::text,
         (SELECT count(*) FROM movie_benefits) - count(*)
  FROM mapped_movie_benefits;
END;
$$;

REVOKE ALL ON FUNCTION public.get_movie_benefit_mapping_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_movie_benefit_mapping_health()
  TO service_role;

COMMIT;
