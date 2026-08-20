import assert from "node:assert/strict";
import test from "node:test";
import { readdir, readFile } from "node:fs/promises";

async function migrationSql() {
  const directory = new URL("../../supabase/migrations/", import.meta.url);
  const files = (await readdir(directory)).filter((name) =>
    name.endsWith("_publish_reviewed_card_identity.sql")
  );
  assert.equal(files.length, 1, "expected exactly one Task 7 migration");
  return await readFile(new URL(files[0], directory), "utf8");
}

function functionBody(sql, name, signaturePattern = "") {
  const match = sql.match(
    new RegExp(
      `CREATE OR REPLACE FUNCTION public\\.${name}\\(${signaturePattern}[\\s\\S]*?\\n\\$\\$;`,
      "i",
    ),
  );
  assert.ok(match, `${name} definition missing`);
  return match[0];
}

test("publication migration exposes exact invoker-only interfaces", async () => {
  const sql = await migrationSql();
  const resolver = functionBody(sql, "resolve_card_catalog_identity");
  const publish = functionBody(sql, "publish_card_catalog_identity");
  const wrapper = functionBody(sql, "review_card_catalog_discovery");
  for (const body of [resolver, publish, wrapper]) {
    assert.match(body, /SECURITY INVOKER/i);
    assert.match(body, /SET search_path = public, extensions, pg_temp/i);
  }
  assert.match(
    sql,
    /publish_card_catalog_identity\(uuid, uuid, uuid, text, jsonb, uuid, text, text\)/i,
  );
  assert.match(
    sql,
    /review_card_catalog_discovery\(uuid, uuid, text, jsonb, uuid, text\)/i,
  );
  for (const role of ["PUBLIC", "anon", "authenticated"]) {
    assert.match(
      sql,
      new RegExp(
        `REVOKE ALL ON FUNCTION public\\.publish_card_catalog_identity\\([\\s\\S]*?FROM [^;]*${role}`,
        "i",
      ),
    );
  }
  assert.match(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.publish_card_catalog_identity\([\s\S]*?TO service_role/i,
  );
});

test("resolver independently reconciles submitted and final hash bindings before mutation", async () => {
  const resolver = functionBody(
    await migrationSql(),
    "resolve_card_catalog_identity",
  );
  assert.match(resolver, /submitted_bound_card[\s\S]*final_bound_card/i);
  assert.match(
    resolver,
    /submitted_bound_card IS NOT NULL[\s\S]*final_bound_card IS NOT NULL[\s\S]*submitted_bound_card <> final_bound_card[\s\S]*conflicting_url_identity/i,
  );
  assert.match(resolver, /url_identity_incompatible/i);
  assert.match(resolver, /normalized_network/i);
  assert.match(resolver, /card_catalog_source_matches_issuer/i);
  assert.match(resolver, /card_type[\s\S]*credit/i);
  assert.match(resolver, /normalized_tier/i);
  assert.match(resolver, /resolved_card_type/i);
  assert.doesNotMatch(resolver, /ORDER BY[^;]*created_at[\s\S]{0,80}LIMIT 1/i);
});

test("resolver serializes one issuer family and rejects incompatible strong siblings", async () => {
  const sql = await migrationSql();
  const resolver = functionBody(sql, "resolve_card_catalog_identity");
  const family = functionBody(sql, "normalize_card_catalog_family");
  assert.match(
    family,
    /world(?:\\s\+)?elite|infinite|signature|platinum|gold/i,
  );
  assert.match(
    resolver,
    /card_catalog_identity:[\s\S]*normalized_family/i,
    "lock namespace still depends on optional variant fields",
  );
  assert.doesNotMatch(
    resolver.match(/pg_advisory_xact_lock[\s\S]{0,450}/i)?.[0] ?? "",
    /normalized_network|normalized_tier/i,
    "present and absent variant requests can take different locks",
  );
  assert.match(resolver, /strong_catalog_identity_conflict/i);
  assert.match(
    resolver,
    /candidate_ids[\s\S]*compatible_candidate_ids[\s\S]*strong_catalog_identity_conflict/i,
  );
  assert.match(
    sql,
    /publication_lock_order_assertions[\s\S]*card_catalog_identity:/i,
  );
  assert.doesNotMatch(
    sql.match(
      /DO \$publication_lock_order_assertions\$[\s\S]*?\$publication_lock_order_assertions\$;/i,
    )?.[0] ?? "",
    /card_catalog_publication:identity:/i,
    "apply-time lock assertion still names the superseded namespace",
  );
  assert.match(sql, /card_catalog_variant_behavior_assertions/i);
  assert.match(
    sql,
    /Axis Bank Privilege Visa Infinite Credit Card[\s\S]*privilegeinfinite/i,
  );
});

test("trusted existing observations are explicit, service-only, and still enqueue v6", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(publish, /observe_existing/i);
  assert.match(
    publish,
    /_action = 'observe_existing'[\s\S]*_review_item_id IS NOT NULL[\s\S]*_actor_id IS NOT NULL/i,
  );
  assert.match(
    publish,
    /strong_existing_official_card[\s\S]*identity_validated/i,
  );
  assert.match(
    publish,
    /observe_existing[\s\S]*resolved_card_id[\s\S]*resolve_card_catalog_identity/i,
  );
  assert.match(
    publish,
    /job_row\.status IN \('resolved', 'rejected'\)[\s\S]*_action = 'observe_existing'[\s\S]*job_row\.resolved_card_id = resolved_card_id/i,
  );
  assert.match(
    publish,
    /INSERT INTO public\.card_catalog_provenance[\s\S]*WHERE NOT EXISTS[\s\S]*submitted_url_hash = submitted_hash[\s\S]*content_hash = publish_card_catalog_identity\.content_hash/i,
  );
  assert.doesNotMatch(
    publish,
    /observed_job\.status = 'resolved'[\s\S]{0,300}RETURN NEXT/i,
  );
  assert.match(publish, /unexpected_enrichment_enqueue/i);
  assert.match(
    publish,
    /observe_existing[\s\S]*observed_job\.review_item_id IS NOT NULL[\s\S]*existing_observation_requires_review/i,
    "review-bound jobs can bypass the admin decision through observe_existing",
  );
});

test("publication persists the full reviewed artifact set and validates one v6 enqueue", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  const adoption = functionBody(sql, "adopt_reviewed_card_enrichment_source");
  for (
    const artifact of [
      "card_catalog_aliases",
      "card_catalog_url_keys",
      "card_catalog_provenance",
      "card_catalog_review_audit",
    ]
  ) {
    assert.match(publish, new RegExp(artifact, "i"));
  }
  assert.match(publish, /adopt_reviewed_card_enrichment_source/i);
  assert.match(adoption, /enqueue_card_benefit_enrichment_jobs/i);
  assert.match(publish, /content_hash/i);
  assert.match(publish, /retrieved_at/i);
  assert.match(publish, /before_fields/i);
  assert.match(publish, /after_fields/i);
  assert.match(
    publish,
    /enqueued_count[\s\S]*existing_v6_job_count[\s\S]*unexpected_enrichment_enqueue/i,
  );
  assert.doesNotMatch(
    publish,
    /card_catalog_aliases\s*\([^)]*discovery_job_id/i,
  );
});

test("reviewed page moves preserve one recurring job and its historical observation state", async () => {
  const sql = await migrationSql();
  const adoption = functionBody(sql, "adopt_reviewed_card_enrichment_source");
  assert.match(
    adoption,
    /status NOT IN \([\s\S]*'completed'[\s\S]*'staged'[\s\S]*'quarantined'[\s\S]*'review_required'[\s\S]*'failed'[\s\S]*\)/i,
  );
  assert.match(adoption, /status = 'failed'[\s\S]*next_retry_at IS NOT NULL/i);
  assert.match(
    adoption,
    /reviewed_enrichment_source_busy[\s\S]*ERRCODE = '40001'/i,
  );
  assert.match(
    adoption,
    /SET canonical_url = _canonical_url[\s\S]*final_url_hash = lower\(_final_url_hash\)[\s\S]*job_key = requested_job_key/i,
  );
  assert.doesNotMatch(adoption, /SET[\s\S]{0,400}result_summary\s*=/i);
  assert.doesNotMatch(adoption, /SET[\s\S]{0,400}next_run_at\s*=/i);
  assert.match(
    adoption,
    /existing_job\.job_key = requested_job_key[\s\S]*existing_job\.canonical_url = _canonical_url[\s\S]*existing_job\.content_hash = lower\(_content_hash\)[\s\S]*RETURN NEXT/i,
  );
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(publish, /INSERT INTO public\.card_catalog_provenance/i);
  assert.doesNotMatch(
    publish,
    /card_catalog_provenance[\s\S]{0,1500}ON CONFLICT[\s\S]{0,200}DO UPDATE/i,
    "historical source observations must never be rewritten",
  );
  assert.doesNotMatch(
    publish,
    /DELETE FROM public\.card_catalog_(?:provenance|url_keys)/i,
  );
  assert.match(publish, /legacy_catalog_url_backfill/i);
  assert.match(
    publish,
    /card_row\.card_url[\s\S]*INSERT INTO public\.card_catalog_url_keys[\s\S]*INSERT INTO public\.card_catalog_provenance/i,
  );
  const trigger = sql.match(
    /CREATE TRIGGER schedule_terminal_card_enrichment_observation[\s\S]*?EXECUTE FUNCTION public\.schedule_terminal_card_enrichment_observation\(\);/i,
  )?.[0];
  assert.ok(trigger, "Task 6 terminal scheduler trigger was not retained");
  assert.doesNotMatch(
    trigger,
    /canonical_url/i,
    "page move resets its recurrence clock",
  );
});

test("publication and enqueue share deterministic lock order", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  const benefitLock = publish.indexOf("card_benefit_enrichment_identity:");
  const cardLock = publish.indexOf("FOR UPDATE", benefitLock);
  const reviewLock = publish.indexOf("card_catalog_review_queue", cardLock);
  const enqueue = publish.indexOf(
    "adopt_reviewed_card_enrichment_source",
    reviewLock,
  );
  assert.ok(benefitLock > 0, "benefit identity lock missing");
  assert.ok(cardLock > benefitLock, "card locked before benefit identity");
  assert.ok(reviewLock > cardLock, "review locked before card");
  assert.ok(enqueue > reviewLock, "enqueue called outside shared lock order");
  assert.match(sql, /card_catalog_publication:/i);
  assert.match(sql, /publication_lock_order_assertions/i);
});

test("reviewed fields and lifecycle actions fail closed", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /_action = 'edit_approve'[\s\S]*card_name[\s\S]*network[\s\S]*annual_fee[\s\S]*joining_fee[\s\S]*apr/i,
  );
  assert.match(publish, /mark_discontinued[\s\S]*reactivate/i);
  assert.match(publish, /source_observation/i);
  assert.match(publish, /reason_required/i);
  assert.match(publish, /actor_required/i);
  assert.match(
    publish,
    /public\.users[\s\S]*is_admin[\s\S]*administrator_required/i,
    "central RPC trusts an arbitrary actor UUID",
  );
  assert.match(publish, /catalog_baseline/i);
  assert.match(publish, /stale_catalog_baseline/i);
  assert.match(
    publish,
    /strong_gone_observation[\s\S]*source_status[\s\S]*410[\s\S]*strong_explicit_discontinuation[\s\S]*identity_validated[\s\S]*exact_card_reappearance/i,
  );
  assert.match(
    publish,
    /_action = 'edit_approve'[\s\S]*edit_target_card_id[\s\S]*resolve_card_catalog_identity[\s\S]*edit_target_conflict/i,
  );
  assert.doesNotMatch(
    publish,
    /http_(?:404|410)[\s\S]{0,120}is_discontinued\s*=/i,
  );
  assert.match(
    publish,
    /_action IN \('mark_discontinued', 'reactivate'\)[\s\S]*card_row\.card_type[\s\S]*credit/i,
    "lifecycle publication does not recheck credit-card authority",
  );
  assert.match(
    publish,
    /_action = 'reactivate'[\s\S]*explicit_discontinuation[\s\S]*reactivation_evidence_conflict/i,
    "explicit current discontinuation can still be reviewed as reappearance",
  );
});

test("reviewed edit and lifecycle proposals are optimistically bound to the live catalog", async () => {
  const sql = await migrationSql();
  const baseline = functionBody(sql, "card_catalog_baseline_matches");
  const publish = functionBody(sql, "publish_card_catalog_identity");
  const lifecycle = functionBody(sql, "stage_card_catalog_lifecycle_review");
  assert.match(baseline, /_updated_at/i);
  assert.match(baseline, /_annual_fee/i);
  assert.match(baseline, /_is_discontinued/i);
  assert.match(publish, /card_catalog_baseline_matches\(/i);
  assert.match(lifecycle, /catalog_baseline/i);
  assert.match(sql, /pending_edit_baseline_assertion_failed/i);
  assert.match(sql, /pending_lifecycle_baseline_assertion_failed/i);
});

test("recurring lifecycle review staging is bounded, idempotent, and excludes weak absence", async () => {
  const sql = await migrationSql();
  const lifecycle = functionBody(sql, "stage_card_catalog_lifecycle_review");
  assert.match(lifecycle, /strong_gone_observation/i);
  assert.match(lifecycle, /strong_explicit_discontinuation/i);
  assert.match(lifecycle, /exact_card_reappearance/i);
  assert.match(lifecycle, /identity_validated/i);
  assert.match(lifecycle, /source_status/i);
  assert.match(lifecycle, /catalog_baseline/i);
  assert.match(lifecycle, /ON CONFLICT|maybe_existing|existing_review/i);
  assert.doesNotMatch(lifecycle, /is_discontinued\s*=/i);
  assert.doesNotMatch(lifecycle, /http_404/i);
  assert.match(
    lifecycle,
    /content_hash[\s\S]*source_observation_hash[\s\S]*dedupe/i,
    "material lifecycle evidence is not versioned",
  );
  assert.match(
    lifecycle,
    /octet_length\(_source_observation::text\)[\s\S]*16384/i,
  );
  assert.match(
    lifecycle,
    /observation_kind IS DISTINCT FROM 'exact_card_reappearance'[\s\S]*explicit_discontinuation[\s\S]*invalid_catalog_lifecycle_review/i,
  );
});

test("terminal cleanup requires authoritative database admin membership", async () => {
  const terminalize = functionBody(
    await migrationSql(),
    "terminalize_calculator_review_rows",
  );
  assert.match(terminalize, /public\.users[\s\S]*is_admin/i);
  assert.match(terminalize, /administrator_required/i);
});

test("reviewed unheld discontinuation documents the sole zero-v6 acquisition exception", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /unheld_reviewed_discontinuation[\s\S]*existing_v6_job_count := 0[\s\S]*enqueued_count := 0/i,
  );
});

test("SQL resource identity matches bounded TypeScript functional-query policy", async () => {
  const sql = await migrationSql();
  const canonical = functionBody(sql, "canonical_card_resource_url");
  const issuerMatch = functionBody(sql, "card_catalog_source_matches_issuer");
  assert.match(canonical, /query_count > 8/i);
  assert.match(canonical, /length\(query_key\) > 64/i);
  assert.match(canonical, /length\(query_value\) > 512/i);
  assert.match(canonical, /query_key ~ '\^utm_'/i);
  assert.match(canonical, /'document'[\s\S]*'variant'/i);
  assert.match(canonical, /decode_card_resource_component/i);
  assert.match(canonical, /normalize_card_resource_path/i);
  assert.match(issuerMatch, /axis\.bank\.in/i);
  assert.match(issuerMatch, /americanexpress\.com/i);
  assert.match(issuerMatch, /hostname LIKE '%\.' \|\| approved\.domain/i);
  assert.match(sql, /encoded_query_key_parity_assertion_failed/i);
  assert.match(sql, /dot_path_parity_assertion_failed/i);
  assert.match(sql, /query_order_duplicate_parity_assertion_failed/i);
});

test("publication validates submitted and final issuer domains independently", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /card_catalog_source_matches_issuer\(issuer, submitted_url\)/i,
  );
  assert.match(
    publish,
    /card_catalog_source_matches_issuer\(issuer, final_url\)/i,
  );
});

test("retry reopens retained review work and replay equality includes reason and merge target", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /_action = 'retry'[\s\S]*status = 'pending'[\s\S]*review_item_id = review_row\.id/i,
  );
  assert.match(
    publish,
    /review_row\.status NOT IN \('pending', 'rejected'\)/i,
  );
  assert.match(
    publish,
    /_action IN \('retry', 'reject', 'mark_discontinued', 'reactivate'\)[\s\S]*reason_required/i,
  );
  assert.match(publish, /replay_audit\.details->>'reason'/i);
  assert.match(publish, /replay_audit\.details->>'merge_card_id'/i);
  assert.match(publish, /'merge_card_id', _merge_card_id/i);
});

test("compatibility wrapper delegates without duplicating publication artifacts", async () => {
  const wrapper = functionBody(
    await migrationSql(),
    "review_card_catalog_discovery",
  );
  assert.match(wrapper, /RETURN QUERY[\s\S]*publish_card_catalog_identity/i);
  assert.doesNotMatch(wrapper, /INSERT INTO public\.card_catalog/i);
  assert.doesNotMatch(wrapper, /INSERT INTO public\.card_catalog_aliases/i);
});

test("legacy manual catalog approval is routed through reviewed publication", async () => {
  const approval = functionBody(
    await migrationSql(),
    "approve_catalog_entry_request",
  );
  assert.match(approval, /publish_card_catalog_identity/i);
  assert.doesNotMatch(approval, /INSERT INTO public\.card_catalog\s*\(/i);
});

test("migration retains review history and eliminates delete cleanup contracts", async () => {
  const sql = await migrationSql();
  assert.match(sql, /calculator_review_terminal/i);
  assert.doesNotMatch(
    sql,
    /DELETE FROM public\.card_(?:discovery_jobs|catalog_review_queue|catalog_review_audit)/i,
  );
  assert.doesNotMatch(sql, /ON DELETE CASCADE/i);
  assert.match(
    sql,
    /card_discovery_jobs_user_id_fkey[\s\S]*ON DELETE SET NULL/i,
  );
  assert.match(
    sql,
    /card_catalog_review_queue_discovery_job_id_fkey[\s\S]*ON DELETE RESTRICT/i,
  );
  assert.match(
    sql,
    /card_catalog_review_audit_review_item_id_fkey[\s\S]*ON DELETE RESTRICT/i,
  );
  assert.match(sql, /mark_discontinued/i);
  assert.match(sql, /reactivate/i);
});

test("migration self-assertions guard signatures, grants, locks, and rollback lane", async () => {
  const sql = await migrationSql();
  assert.match(sql, /publish_reviewed_card_identity_assertions/i);
  assert.match(sql, /benefits-v6/i);
  assert.match(sql, /benefits-v5/i);
  assert.match(sql, /COMMIT;/i);
});

test("production entry paths cannot bypass reviewed publication", async () => {
  const paths = {
    discovery: new URL(
      "../../supabase/functions/card-discovery/index.ts",
      import.meta.url,
    ),
    admin: new URL(
      "../../supabase/functions/admin-catalog-entry/index.ts",
      import.meta.url,
    ),
    enrichment: new URL(
      "../../supabase/functions/catalog-enrichment/index.ts",
      import.meta.url,
    ),
    crawler: new URL(
      "../../supabase/functions/_shared/issuer_card_crawl.ts",
      import.meta.url,
    ),
    recurring: new URL(
      "../../supabase/functions/benefit-enrichment-batch/index.ts",
      import.meta.url,
    ),
  };
  const sources = Object.fromEntries(
    await Promise.all(
      Object.entries(paths).map(async (
        [name, path],
      ) => [name, await readFile(path, "utf8")]),
    ),
  );
  for (const [name, source] of Object.entries(sources)) {
    assert.doesNotMatch(
      source,
      /from\(["']card_catalog["']\)[\s\S]{0,100}\.(?:insert|upsert|update)\(/,
      `${name} directly mutates the canonical catalog`,
    );
    assert.doesNotMatch(
      source,
      /card_catalog_aliases[\s\S]{0,180}discovery_job_id/,
      `${name} writes the nonexistent alias discovery column`,
    );
  }
  assert.match(sources.admin, /publishReviewedCardIdentity\(db,/);
  assert.match(sources.discovery, /action:\s*["']observe_existing["']/);
  assert.match(sources.crawler, /action:\s*["']observe_existing["']/);
  assert.match(sources.recurring, /proposeCatalogLifecycleReview\(/);
  assert.match(sources.recurring, /catalogLifecycleSuggestion\(/);
  assert.doesNotMatch(sources.discovery, /function markResolved\(/);
  assert.match(sources.discovery, /authenticated_source_requires_admin_review/);
  assert.match(sources.enrichment, /catalog_review_context_required/);
  assert.doesNotMatch(sources.crawler, /resolve_card_catalog_identity/);
});
