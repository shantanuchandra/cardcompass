-- Catalog aliases are non-user-specific reference data required by the
-- authenticated app's card matcher. Mutations remain service-role-only.
GRANT SELECT ON public.card_catalog_aliases TO authenticated;

DROP POLICY IF EXISTS "Authenticated users can read catalog aliases"
  ON public.card_catalog_aliases;
CREATE POLICY "Authenticated users can read catalog aliases"
  ON public.card_catalog_aliases
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) IS NOT NULL);
