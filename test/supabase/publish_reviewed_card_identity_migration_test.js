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

test("review staging is one service-only transaction with canonical lock order and CAS ownership", async () => {
  const sql = await migrationSql();
  const stage = functionBody(sql, "stage_card_catalog_identity_review");
  assert.match(stage, /SECURITY INVOKER/i);
  assert.match(stage, /card_catalog_review_stage:/i);
  const stageLock = stage.indexOf("card_catalog_review_stage:");
  const jobLock = stage.indexOf("card_catalog_publication:job:", stageLock);
  const jobRowLock = stage.indexOf("card_discovery_jobs", jobLock);
  const jobForUpdate = stage.indexOf("FOR UPDATE", jobRowLock);
  const reviewRowLock = stage.indexOf(
    "card_catalog_review_queue",
    jobForUpdate,
  );
  const reviewForUpdate = stage.indexOf("FOR UPDATE", reviewRowLock);
  assert.ok(stageLock >= 0, "review stage advisory lock missing");
  assert.ok(
    jobLock > stageLock,
    "job advisory lock precedes stage identity lock",
  );
  assert.ok(
    jobForUpdate > jobLock,
    "job row is not locked after its advisory lock",
  );
  assert.ok(
    reviewForUpdate > jobForUpdate,
    "review row is not locked after the job row",
  );
  assert.match(stage, /expected_job_updated_at/i);
  assert.match(stage, /expected_job_status/i);
  assert.match(stage, /append_catalog_observation_history/i);
  assert.match(stage, /approved|merged|rejected/i);
  assert.match(stage, /material.*semantic|semantic.*material/i);
  assert.match(
    sql,
    /REVOKE ALL ON FUNCTION public\.stage_card_catalog_identity_review\([\s\S]*?FROM PUBLIC, anon, authenticated/i,
  );
  assert.match(
    sql,
    /GRANT EXECUTE ON FUNCTION public\.stage_card_catalog_identity_review\([\s\S]*?TO service_role/i,
  );
  assert.match(sql, /review_stage_lock_order_assertion_failed/i);
  assert.match(sql, /review_stage_authority_assertion_failed/i);
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

test("reviewed admin inputs are server-bound and edit baselines apply only to existing targets", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /review_row\.proposed_fields[\s\S]*_action = 'edit_approve'[\s\S]*annual_fee[\s\S]*joining_fee[\s\S]*apr/i,
    "publication does not reconstruct reviewed fields from the locked proposal",
  );
  assert.match(publish, /immutable_reviewed_field_override/i);
  assert.match(
    publish,
    /edit_target_card_id IS NOT NULL[\s\S]*catalog_baseline_required/i,
    "new-card edit approval still requires a live-card baseline",
  );
  assert.match(
    publish,
    /edit_target_card_id IS NULL[\s\S]*stored_proposal_binding/i,
    "new-card edits are not bound to stored proposal evidence",
  );
});

test("review retry is an audited retained-review reopen and never queues in-flight producer work", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /_action = 'retry'[\s\S]*status = 'review_required'[\s\S]*review_item_id = review_row\.id/i,
  );
  assert.doesNotMatch(
    publish,
    /_action = 'retry'[\s\S]{0,1800}status = 'queued'/i,
    "review retry requeued work without a typed producer",
  );
  assert.match(
    publish,
    /job_row\.status = 'discovering'[\s\S]*stale_catalog_review|stale_catalog_review[\s\S]*job_row\.status = 'discovering'/i,
    "retry can reopen an in-flight discovery job",
  );
  assert.match(
    publish,
    /review_row\.updated_at IS DISTINCT FROM observed_review\.updated_at[\s\S]*job_row\.updated_at IS DISTINCT FROM observed_job\.updated_at/i,
  );
  assert.match(
    publish,
    /WHERE id = review_row\.id[\s\S]*status IS NOT DISTINCT FROM review_row\.status[\s\S]*updated_at IS NOT DISTINCT FROM review_row\.updated_at/i,
  );
  assert.match(
    publish,
    /WHERE id = job_row\.id[\s\S]*status IS NOT DISTINCT FROM job_row\.status[\s\S]*updated_at IS NOT DISTINCT FROM job_row\.updated_at/i,
  );
});

test("edit destination conflict distinguishes strong-compatible duplicates from sibling variants", async () => {
  const publish = functionBody(
    await migrationSql(),
    "publish_card_catalog_identity",
  );
  assert.match(
    publish,
    /new_family_conflict[\s\S]*card_catalog_effective_network[\s\S]*normalize_card_catalog_tier/i,
  );
  assert.match(
    publish,
    /new_family_conflict[\s\S]*reviewed_network[\s\S]*reviewed_tier/i,
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
    /content_hash[\s\S]*source_observation_(?:semantic_)?hash[\s\S]*dedupe/i,
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
  assert.doesNotMatch(terminalize, /LIKE\s+'%calculator%'/i);
  assert.match(terminalize, /non_product_calculator_resource/i);
  assert.match(terminalize, /explicit_admin_confirmation/i);
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
  assert.match(sources.recurring, /catalogLifecycleObservationAction\(/);
  assert.doesNotMatch(sources.discovery, /function markResolved\(/);
  assert.match(sources.discovery, /authenticated_source_requires_admin_review/);
  assert.match(sources.enrichment, /catalog_review_context_required/);
  assert.doesNotMatch(sources.crawler, /resolve_card_catalog_identity/);
  for (const name of ["discovery", "crawler", "enrichment"]) {
    assert.match(
      sources[name],
      /stageCatalogIdentityReview\(/,
      `${name} does not use transactional review staging`,
    );
    assert.doesNotMatch(
      sources[name],
      /from\(["']card_catalog_review_queue["']\)[\s\S]{0,120}\.(?:insert|update|upsert)\(/,
      `${name} still writes a review outside the staging transaction`,
    );
    assert.doesNotMatch(
      sources[name],
      /from\(["']card_discovery_jobs["']\)[\s\S]{0,160}\.update\(\{[\s\S]{0,160}review_item_id/i,
      `${name} still links review work outside the staging transaction`,
    );
  }
});

test("submitted URL discovery fetches before version creation and preserves a prior terminal result on timeout", async () => {
  const source = await readFile(
    new URL(
      "../../supabase/functions/card-discovery/index.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const branch = source.slice(source.indexOf('if (action === "resolve_url")'));
  const findPrior = branch.indexOf("findPriorSubmittedRequestJob(");
  const fetch = branch.indexOf("fetchSubmittedUrlObservation(");
  const version = branch.indexOf("versionSubmittedObservationJob(");
  const failure = branch.indexOf("catch (error)", version);
  const failureAnchorInsert = branch.indexOf("upsertDiscoveryJob(", failure);
  assert.ok(
    findPrior >= 0 && fetch > findPrior,
    "prior terminal anchor is not loaded before fetch",
  );
  assert.ok(
    version > fetch,
    "a persisted content job is created before successful fetch",
  );
  assert.ok(
    failureAnchorInsert > failure,
    "failure work is inserted before fetch outcome exists",
  );
  assert.match(
    branch.slice(failure, failureAnchorInsert),
    /priorJob[\s\S]*terminalDiscoveryStatus[\s\S]*publicDiscoveryResult\(priorJob/i,
    "fetch failure does not preserve the prior terminal outcome",
  );
  const versionFunction = source.slice(
    source.indexOf("export async function versionSubmittedObservationJob"),
    source.indexOf("async function claimSubmittedObservationJob"),
  );
  assert.doesNotMatch(
    versionFunction,
    /\.update\(/,
    "immutable observation versioning rewrites an anchor/job",
  );
  assert.match(versionFunction, /request_anchor_key/i);
  assert.match(versionFunction, /semantic_product_hash/i);
});

test("trusted observation authority is revalidated under the publication locks before mutation", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  const jobLock = publish.indexOf("card_catalog_publication:job:");
  const lockedObserve = publish.indexOf("observe_existing_locked_revalidation");
  const resolver = publish.indexOf("resolve_card_catalog_identity(");
  assert.ok(jobLock >= 0, "publication job advisory lock missing");
  assert.ok(
    lockedObserve > jobLock && resolver > lockedObserve,
    "observe_existing can mutate identity before locked review/status revalidation",
  );
  assert.match(
    publish.slice(lockedObserve, resolver),
    /FOR UPDATE[\s\S]*review_item_id[\s\S]*status[\s\S]*pending_review/i,
  );
  assert.match(sql, /observe_existing_locked_revalidation_assertion_failed/i);
});

test("reviewed rename locks old and new identity families and rejects a conflicting destination", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(
    publish,
    /edit_old_identity_lock[\s\S]*edit_new_identity_lock[\s\S]*least\([\s\S]*greatest\([\s\S]*pg_advisory_xact_lock/i,
  );
  assert.match(
    publish,
    /new_family_conflict[\s\S]*edit_target_conflict/i,
    "rename does not recheck the destination family under both locks",
  );
  assert.match(sql, /rename_dual_family_lock_assertion_failed/i);
});

test("legacy URL backfill always has a nonnull deterministic observation timestamp", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(
    publish,
    /legacy_provenance_retrieved_at[\s\S]*coalesce\([\s\S]*card_row\.updated_at[\s\S]*retrieved_at[\s\S]*statement_timestamp\(\)/i,
  );
  assert.doesNotMatch(
    publish,
    /'legacy_catalog_url_backfill'[\s\S]{0,180}'admin',\s*card_row\.updated_at/i,
  );
  assert.match(sql, /legacy_provenance_timestamp_assertion_failed/i);
});

test("lifecycle evidence is chronological, semantic, bounded, and supersedes stale opposite work", async () => {
  const sql = await migrationSql();
  const lifecycle = functionBody(sql, "stage_card_catalog_lifecycle_review");
  const publisher = functionBody(sql, "publish_card_catalog_identity");
  assert.match(lifecycle, /observe_current/i);
  assert.match(
    lifecycle,
    /lifecycle_observed_at[\s\S]*interval '5 minutes'[\s\S]*stale_catalog_lifecycle_observation/i,
  );
  assert.match(
    lifecycle,
    /latest_lifecycle_job_id[\s\S]*lifecycle_state[\s\S]*superseded_by_newer_lifecycle_observation[\s\S]*status = 'rejected'/i,
  );
  assert.match(
    lifecycle,
    /catalog_lifecycle_semantic_observation[\s\S]*source_observation_semantic_hash/i,
  );
  assert.doesNotMatch(
    lifecycle,
    /lifecycle_dedupe_key[\s\S]{0,500}coalesce\(lower\(_content_hash\)/i,
    "raw response hash incorrectly versions semantic lifecycle work",
  );
  assert.match(
    lifecycle,
    /catalog_baseline\s*-\s*array\['updated_at',\s*'version_observed_at'\]/i,
    "transport/version timestamps incorrectly version lifecycle work",
  );
  assert.match(
    lifecycle,
    /append_catalog_observation_history/i,
    "lifecycle history is still unbounded or duplicate-appending",
  );
  assert.match(
    publisher,
    /latest_lifecycle_job_id[\s\S]*stale_catalog_lifecycle_review/i,
    "admin lifecycle approval does not prove its review is latest",
  );
  assert.match(sql, /lifecycle_latest_evidence_assertion_failed/i);
});

test("network authority combines stored column and product name without a legacy wildcard", async () => {
  const sql = await migrationSql();
  const resolver = functionBody(sql, "resolve_card_catalog_identity");
  const publisher = functionBody(sql, "publish_card_catalog_identity");
  assert.match(sql, /card_catalog_effective_network\(text, text, text\)/i);
  assert.match(
    resolver,
    /card_catalog_effective_network\(catalog\.network, catalog\.card_name, catalog\.bank\)/i,
  );
  assert.match(publisher, /card_catalog_effective_network/i);
  assert.match(sql, /stored_network_conflict/i);
  assert.match(sql, /amex_tier_identity_assertion_failed/i);
});

test("retry and reject exact replays return their retained terminal/current state without duplicate audit", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(
    publish,
    /idempotent_retry_reject_replay[\s\S]*replay_audit\.actor_id[\s\S]*replay_audit\.action[\s\S]*reason[\s\S]*merge_card_id/i,
  );
  assert.match(
    publish,
    /_action = 'retry'[\s\S]*review_row\.status = 'pending'[\s\S]*job_row\.status = 'review_required'/i,
  );
  assert.match(
    publish,
    /_action = 'reject'[\s\S]*review_row\.status = 'rejected'[\s\S]*job_row\.status = 'rejected'/i,
  );
  assert.match(sql, /retry_reject_replay_assertion_failed/i);
});

test("reviewed fields have an exact whole-envelope allowlist, privacy, and recursive SQL bounds", async () => {
  const sql = await migrationSql();
  const publish = functionBody(sql, "publish_card_catalog_identity");
  assert.match(sql, /card_catalog_json_envelope_valid\(jsonb, integer\)/i);
  assert.match(sql, /card_catalog_json_contains_sensitive_url\(jsonb\)/i);
  assert.match(
    sql,
    /FOR ascii_code IN 32\.\.126 LOOP[\s\S]*to_hex\(ascii_code\)/i,
    "SQL privacy scan does not decode percent-encoded sensitive-key letters",
  );
  assert.match(
    publish,
    /jsonb_object_keys\(fields\)[\s\S]*reviewed_field_allowlist[\s\S]*unknown_reviewed_field/i,
  );
  assert.match(publish, /octet_length\(fields::text\)[\s\S]*16384/i);
  assert.match(
    sql,
    /https%253A%252F%252Fuser%253Apass%2540example\.com%252Fcard%253Ftoken%253Dsecret/i,
  );
  assert.match(
    sql,
    /%2574%256f%256b%2565%256e%253dsecret/i,
  );
  assert.match(
    sql,
    /reviewed_fields_envelope_multilayer_privacy_assertion_failed/i,
  );
});

test("resource canonicalization fails closed on empty query separators in SQL and TypeScript parity assertions", async () => {
  const sql = await migrationSql();
  const canonical = functionBody(sql, "canonical_card_resource_url");
  assert.match(canonical, /query_part\.part = ''[\s\S]*unapproved_query/i);
  assert.match(sql, /empty_query_separator_parity_assertion_failed/i);
});
