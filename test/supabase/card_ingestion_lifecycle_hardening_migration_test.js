import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';

const repoRoot = new URL('../../', import.meta.url);
const migrationsRoot = new URL('supabase/migrations/', repoRoot);

async function lifecycleMigration() {
  const names = (await readdir(migrationsRoot)).filter((name) =>
    name.endsWith('_card_ingestion_lifecycle_hardening.sql')
  );
  assert.equal(
    names.length,
    1,
    'exactly one CLI-generated lifecycle hardening migration is required',
  );
  assert.match(names[0], /^\d{14}_card_ingestion_lifecycle_hardening\.sql$/);
  return readFile(new URL(names[0], migrationsRoot), 'utf8');
}

function requiredMatch(sql, pattern, description) {
  const match = sql.match(pattern)?.[0];
  assert.ok(match, description);
  return match;
}

function benefitRepairStatement(sql) {
  return requiredMatch(
    sql,
    /WITH normalized AS \([\s\S]*?\)\s*UPDATE public\.benefits AS benefit[\s\S]*?WHERE normalized\.benefit_id = benefit\.benefit_id[\s\S]*?;/i,
    'benefits normalization update is required',
  );
}

function stagingClassificationStatement(sql) {
  return requiredMatch(
    sql,
    /UPDATE public\.card_benefits_staging[\s\S]*?;/i,
    'staging classification update is required',
  );
}

function constraintDefinition(sql, name) {
  return requiredMatch(
    sql,
    new RegExp(`ADD CONSTRAINT ${name}[\\s\\S]*?NOT VALID;`, 'i'),
    `${name} definition is required`,
  );
}

function functionDefinition(sql, name) {
  return requiredMatch(
    sql,
    new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\$\\$;`, 'i'),
    `${name} function is required`,
  );
}

function migrationAssertionBlock(sql, tag) {
  return requiredMatch(
    sql,
    new RegExp(`DO \\$${tag}\\$[\\s\\S]*?\\$${tag}\\$;`, 'i'),
    `${tag} transactional migration assertions are required`,
  );
}

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function sqlSignaturePattern(signature) {
  const openParen = signature.indexOf('(');
  const name = signature.slice(0, openParen);
  const argumentList = signature.slice(openParen + 1, -1).trim();
  const argumentsPattern = argumentList === ''
    ? ''
    : argumentList
      .split(',')
      .map((argument) => escaped(argument.trim()).replaceAll(' ', '\\s+'))
      .join('\\s*,\\s*');
  return `${escaped(name)}\\s*\\(\\s*${argumentsPattern}\\s*\\)`;
}

test('adds only the two lifecycle columns with bounded deployment locks and due indexes', async () => {
  const sql = await lifecycleMigration();

  assert.match(sql, /SET LOCAL lock_timeout\s*=\s*'\d+s'/i);
  assert.match(sql, /SET LOCAL statement_timeout\s*=\s*'\d+s'/i);
  assert.match(
    sql,
    /ALTER TABLE public\.card_catalog_enrichment_jobs[\s\S]*ADD COLUMN IF NOT EXISTS next_run_at timestamptz/i,
  );
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS \w+[\s\S]*ON public\.card_catalog_enrichment_jobs\s*\(\s*parser_version\s*,\s*run_mode\s*,\s*next_run_at\s*,\s*issuer\s*\)[\s\S]*WHERE status IN \(\s*'staged'\s*,\s*'completed'\s*,\s*'review_required'\s*,\s*'quarantined'\s*\)[\s\S]*next_run_at IS NOT NULL/i,
  );
  assert.match(
    sql,
    /ALTER TABLE public\.card_benefit_mapping[\s\S]*ADD COLUMN IF NOT EXISTS retired_at timestamptz/i,
  );
  assert.match(
    sql,
    /CREATE INDEX IF NOT EXISTS \w+[\s\S]*ON public\.card_benefit_mapping\s*\(\s*card_id\s*,\s*display_priority\s*\)[\s\S]*WHERE retired_at IS NULL/i,
  );

  const addedColumns = [...sql.matchAll(
    /ALTER TABLE\s+([a-z_][a-z0-9_.]*)\s+ADD COLUMN(?: IF NOT EXISTS)?\s+([a-z_][a-z0-9_]*)/gi,
  )].map((match) => ({ table: match[1], column: match[2] }));
  assert.deepEqual(addedColumns, [
    {
      table: 'public.card_catalog_enrichment_jobs',
      column: 'next_run_at',
    },
    { table: 'public.card_benefit_mapping', column: 'retired_at' },
  ]);
  assert.doesNotMatch(sql, /CREATE\s+(?:UNLOGGED\s+)?TABLE\b/i);
  assert.doesNotMatch(sql, /DROP\s+(?:TABLE|SCHEMA|COLUMN)\b/i);
});

test('repairs legacy catalog and JSON values before validating strict shapes', async () => {
  const sql = await lifecycleMigration();
  const repair = benefitRepairStatement(sql);

  const discontinuedRepair = sql.search(
    /UPDATE public\.card_catalog[\s\S]*is_discontinued\s*=\s*false[\s\S]*WHERE is_discontinued IS NULL/i,
  );
  const discontinuedNotNull = sql.search(
    /ALTER TABLE public\.card_catalog\s+[\s\S]*ALTER COLUMN is_discontinued SET NOT NULL/i,
  );
  assert.ok(discontinuedRepair >= 0 && discontinuedRepair < discontinuedNotNull);

  assert.match(repair, /SET value_config\s*=\s*normalized\.value_config/i);
  assert.match(repair, /partners\s*=\s*normalized\.partners/i);
  assert.match(repair, /exclusions\s*=\s*normalized\.exclusions/i);
  assert.match(repair, /regions\s*=\s*normalized\.regions/i);
  for (const column of ['value_config', 'partners', 'exclusions', 'regions']) {
    assert.match(
      repair,
      new RegExp(`normalized\\.${column} IS DISTINCT FROM benefit\\.${column}`, 'i'),
      `${column} must participate in the no-op update filter`,
    );
  }

  for (const constraint of [
    'benefits_value_config_object_check',
    'benefits_partners_array_check',
    'benefits_exclusions_object_check',
    'benefits_regions_array_check',
    'card_catalog_enrichment_jobs_result_summary_object_check',
  ]) {
    assert.match(
      sql,
      new RegExp(`ADD CONSTRAINT ${constraint}[\\s\\S]*?NOT VALID`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`VALIDATE CONSTRAINT ${constraint}`, 'i'),
    );
  }

  assert.match(
    constraintDefinition(sql, 'benefits_value_config_object_check'),
    /jsonb_typeof\(value_config\)\s*=\s*'object'/i,
  );
  assert.match(
    constraintDefinition(sql, 'benefits_partners_array_check'),
    /jsonb_typeof\(partners\)\s*=\s*'array'/i,
  );
  assert.match(
    constraintDefinition(sql, 'benefits_regions_array_check'),
    /jsonb_typeof\(regions\)\s*=\s*'array'/i,
  );
  const exclusionsConstraint = constraintDefinition(
    sql,
    'benefits_exclusions_object_check',
  );
  assert.match(exclusionsConstraint, /jsonb_typeof\(exclusions\)\s*=\s*'object'/i);
  for (const key of [
    'days',
    'mcc_codes',
    'merchants',
    'categories',
    'transaction_types',
  ]) {
    assert.match(
      exclusionsConstraint,
      new RegExp(`jsonb_typeof\\(exclusions->'${key}'\\)\\s*=\\s*'array'`, 'i'),
    );
  }
  assert.match(exclusionsConstraint, /jsonb_typeof\(exclusions->'additional'\)\s*=\s*'object'/i);
  assert.match(
    exclusionsConstraint,
    /jsonb_typeof\(exclusions->'additional'->'source_terms'\)\s*=\s*'array'/i,
  );
  assert.match(
    constraintDefinition(
      sql,
      'card_catalog_enrichment_jobs_result_summary_object_check',
    ),
    /jsonb_typeof\(result_summary\)\s*=\s*'object'/i,
  );
  assert.match(
    functionDefinition(sql, 'normalize_benefit_exclusions_shape'),
    /NEW\.exclusions\s*:=\s*public\.normalize_benefit_exclusions_value\(NEW\.exclusions\)/i,
  );
  assert.match(
    sql,
    /CREATE TRIGGER normalize_benefit_exclusions_shape[\s\S]*BEFORE INSERT OR UPDATE OF exclusions[\s\S]*public\.benefits/i,
  );
});

test('losslessly audits mixed exclusion arrays while separating source strings', async () => {
  const normalizer = functionDefinition(
    await lifecycleMigration(),
    'normalize_benefit_exclusions_value',
  );

  assert.match(normalizer, /jsonb_array_elements\(_exclusions\)\s+WITH ORDINALITY/i);
  assert.match(normalizer, /jsonb_typeof\(element\.value\)\s*=\s*'string'[\s\S]*source_terms/i);
  assert.match(normalizer, /jsonb_typeof\(element\.value\)\s*<>\s*'string'[\s\S]*legacy_values/i);
  assert.match(normalizer, /'path'\s*,\s*format\(\s*'\$\[%s\]'/i);
  assert.match(normalizer, /'value'\s*,\s*element\.value/i);
});

test('losslessly audits JSON null, numeric, and boolean root exclusion scalars', async () => {
  const normalizer = functionDefinition(
    await lifecycleMigration(),
    'normalize_benefit_exclusions_value',
  );

  for (const scalarType of ['null', 'number', 'boolean']) {
    assert.match(
      normalizer,
      new RegExp(`root_type IN \\([^)]*'${scalarType}'`, 'i'),
      `${scalarType} roots must enter the lossless audit branch`,
    );
  }
  assert.match(normalizer, /jsonb_build_object\(\s*'path'\s*,\s*'\$'/i);
  assert.match(normalizer, /'value'\s*,\s*_exclusions/i);
});

test('losslessly audits malformed known, additional, and source_terms nested values', async () => {
  const normalizer = functionDefinition(
    await lifecycleMigration(),
    'normalize_benefit_exclusions_value',
  );

  assert.match(normalizer, /FOREACH key_name IN ARRAY ARRAY\[\s*'days'[\s\S]*'transaction_types'/i);
  assert.match(normalizer, /jsonb_typeof\(_exclusions->key_name\)\s*<>\s*'array'/i);
  assert.match(normalizer, /format\(\s*'\$\.%s'\s*,\s*key_name\s*\)/i);
  assert.match(normalizer, /'\$\.additional'/i);
  assert.match(normalizer, /'\$\.additional\.source_terms\[%s\]'/i);
  assert.match(normalizer, /'\$\.additional\.legacy_values'/i);
  assert.match(
    normalizer,
    /normalized_additional\s*:=\s*existing_additional[\s\S]*jsonb_build_object\(\s*'source_terms'\s*,\s*source_terms/i,
  );
  assert.match(
    normalizer,
    /jsonb_build_object\(\s*'legacy_values'\s*,\s*legacy_values/i,
  );
});

test('transactionally verifies exclusion normalization fixtures during migration apply', async () => {
  const sql = await lifecycleMigration();
  const assertions = migrationAssertionBlock(
    sql,
    'exclusion_normalization_assertions',
  );

  for (const fixture of [
    'mixed_root_array',
    'json_null_root',
    'number_root',
    'boolean_root',
    'malformed_nested_values',
    'malformed_additional',
    'malformed_source_terms',
    'flat_v5_string_array',
  ]) {
    assert.match(
      assertions,
      new RegExp(`'${fixture}'`, 'i'),
      `${fixture} must be an explicit runtime fixture`,
    );
  }
  assert.match(
    assertions,
    /'\["legacy string", 42, null, true, \{"raw": "value"\}\]'::jsonb/i,
  );
  for (const auditPath of [
    '$[1]',
    '$[2]',
    '$[3]',
    '$[4]',
    '$.additional.legacy_values',
    '$.additional.source_terms[1]',
    '$.additional.source_terms[2]',
    '$.days',
    '$.mcc_codes',
    '$.merchants',
    '$.categories',
    '$.transaction_types',
    '$.additional',
    '$.additional.source_terms',
  ]) {
    assert.match(assertions, new RegExp(escaped(`"path": "${auditPath}"`)));
  }
  assert.match(assertions, /"note": "preserve me"/i);
  assert.match(assertions, /'\["weekends", "wallets"\]'::jsonb/i);
  assert.match(
    assertions,
    /"additional": \{"source_terms": \["weekends", "wallets"\]\}/i,
  );
  assert.match(
    assertions,
    /actual_value\s*:=\s*public\.normalize_benefit_exclusions_value\(\s*assertion_case\.input_value\s*\)/i,
  );
  assert.match(
    assertions,
    /actual_value IS DISTINCT FROM assertion_case\.expected_value[\s\S]*RAISE EXCEPTION/i,
  );
  assert.match(
    assertions,
    /public\.normalize_benefit_exclusions_value\(actual_value\)\s+IS DISTINCT FROM actual_value[\s\S]*RAISE EXCEPTION/i,
  );
  assert.ok(
    sql.indexOf(assertions) < sql.search(/UPDATE public\.card_catalog\b/i),
    'runtime helper assertions must precede the first table repair',
  );
});

test('classifies legacy staging before enforcing request-specific contracts', async () => {
  const sql = await lifecycleMigration();
  const classificationStatement = stagingClassificationStatement(sql);
  const classification = sql.indexOf(classificationStatement);
  const officialConstraint = sql.search(
    /ADD CONSTRAINT card_benefits_staging_official_shape_check/i,
  );
  const catalogConstraint = sql.search(
    /ADD CONSTRAINT card_benefits_staging_catalog_entry_shape_check/i,
  );
  assert.ok(classification >= 0);
  assert.ok(classification < officialConstraint);
  assert.ok(classification < catalogConstraint);

  assert.match(
    classificationStatement,
    /public\.is_valid_official_source_evidence\(source_evidence\)/i,
  );
  assert.doesNotMatch(classificationStatement, /jsonb_array_length\(source_evidence\)/i);
  assert.match(
    classificationStatement,
    /WHERE nullif\(trim\(request_type\),\s*''\) IS NULL/i,
  );
  const officialShape = constraintDefinition(
    sql,
    'card_benefits_staging_official_shape_check',
  );
  assert.match(
    officialShape,
    /request_type\s*<>\s*'official_benefit_enrichment'[\s\S]*card_id IS NOT NULL[\s\S]*nullif\(trim\(source_url\)[\s\S]*nullif\(trim\(parser_version\)[\s\S]*nullif\(trim\(source_url_hash\)[\s\S]*nullif\(trim\(content_hash\)/i,
  );
  assert.match(
    officialShape,
    /public\.is_valid_official_source_evidence\(source_evidence\)/i,
  );
  assert.doesNotMatch(officialShape, /jsonb_array_length\(source_evidence\)/i);
  assert.match(
    constraintDefinition(sql, 'card_benefits_staging_catalog_entry_shape_check'),
    /request_type\s*<>\s*'catalog_entry'[\s\S]*requested_by IS NOT NULL[\s\S]*jsonb_typeof\(extracted_data\)\s*=\s*'object'/i,
  );
  for (const constraint of [
    'card_benefits_staging_official_shape_check',
    'card_benefits_staging_catalog_entry_shape_check',
  ]) {
    assert.match(
      sql,
      new RegExp(`ADD CONSTRAINT ${constraint}[\\s\\S]*NOT VALID`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`VALIDATE CONSTRAINT ${constraint}`, 'i'),
    );
  }
});

test('transactionally verifies the shared official evidence predicate during migration apply', async () => {
  const sql = await lifecycleMigration();
  const predicate = functionDefinition(
    sql,
    'is_valid_official_source_evidence',
  );
  const assertions = migrationAssertionBlock(
    sql,
    'official_evidence_assertions',
  );

  assert.match(predicate, /RETURNS boolean/i);
  assert.match(predicate, /IMMUTABLE/i);
  assert.match(predicate, /_source_evidence IS NULL[\s\S]*false/i);
  assert.match(predicate, /jsonb_typeof\(_source_evidence\)\s*=\s*'array'/i);
  assert.match(predicate, /jsonb_array_length\(_source_evidence\)\s*>\s*0/i);
  for (const fixture of [
    'sql_null',
    'json_null',
    'string_scalar',
    'number_scalar',
    'boolean_scalar',
    'object',
    'empty_array',
    'non_empty_array',
  ]) {
    assert.match(
      assertions,
      new RegExp(`'${fixture}'`, 'i'),
      `${fixture} must be an explicit runtime fixture`,
    );
  }
  for (const fixture of [
    /'sql_null'\s*,\s*NULL::jsonb\s*,\s*false/i,
    /'json_null'\s*,\s*'null'::jsonb\s*,\s*false/i,
    /'string_scalar'\s*,\s*'"evidence"'::jsonb\s*,\s*false/i,
    /'number_scalar'\s*,\s*'1'::jsonb\s*,\s*false/i,
    /'boolean_scalar'\s*,\s*'true'::jsonb\s*,\s*false/i,
    /'object'\s*,\s*'\{"quote": "evidence"\}'::jsonb\s*,\s*false/i,
    /'empty_array'\s*,\s*'\[\]'::jsonb\s*,\s*false/i,
    /'non_empty_array'\s*,\s*'\[\{"quote": "evidence"\}\]'::jsonb\s*,\s*true/i,
  ]) {
    assert.match(assertions, fixture);
  }
  assert.match(
    assertions,
    /public\.is_valid_official_source_evidence\(assertion_case\.input_value\)\s+IS DISTINCT FROM assertion_case\.expected_value[\s\S]*RAISE EXCEPTION/i,
  );
  assert.ok(
    sql.indexOf(assertions) < sql.search(/UPDATE public\.card_catalog\b/i),
    'runtime evidence assertions must precede the first table repair',
  );
});

test('defines an explicit security-invoker active view with UTC lifecycle filters', async () => {
  const sql = await lifecycleMigration();
  const view = sql.match(
    /CREATE OR REPLACE VIEW public\.active_card_benefits[\s\S]*?;/i,
  )?.[0];

  assert.ok(view, 'active_card_benefits view is required');
  assert.match(view, /WITH\s*\(\s*security_invoker\s*=\s*true\s*\)/i);
  assert.doesNotMatch(view, /SELECT\s+(?:\w+\.)?\*/i);
  for (const column of [
    'mapping_id',
    'card_id',
    'benefit_id',
    'display_priority',
    'is_primary',
    'category_codes',
    'title',
    'description',
    'benefit_category',
    'benefit_type',
    'value_config',
    'partners',
    'exclusions',
    'regions',
    'source_url',
    'valid_from',
    'valid_until',
  ]) assert.match(view, new RegExp(`\\b${column}\\b`, 'i'));
  assert.match(view, /mapping\.retired_at IS NULL\s+OR mapping\.retired_at\s*>\s*now\(\)/i);
  assert.match(view, /benefit\.is_active\s*=\s*true/i);
  assert.match(
    view,
    /timezone\(\s*'UTC'\s*,\s*statement_timestamp\(\)\s*\)::date AS utc_date/i,
  );
  assert.match(view, /benefit\.valid_from IS NULL\s+OR benefit\.valid_from\s*<=\s*database_clock\.utc_date/i);
  assert.match(view, /benefit\.valid_until IS NULL\s+OR benefit\.valid_until\s*>=\s*database_clock\.utc_date/i);
});

test('adds authenticated read policies before narrowing client table and RPC grants', async () => {
  const sql = await lifecycleMigration();

  for (const table of [
    'card_catalog',
    'benefit_categories',
    'benefits',
    'card_benefit_mapping',
  ]) {
    assert.match(sql, new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY`, 'i'));
    assert.match(
      sql,
      new RegExp(`CREATE POLICY[^;]+ON public\\.${table}[^;]+FOR SELECT[^;]+TO authenticated[^;]+USING \\(true\\)`, 'i'),
    );
    assert.match(
      sql,
      new RegExp(`REVOKE INSERT, UPDATE, DELETE ON (?:TABLE )?public\\.${table} FROM (?:PUBLIC, )?anon, authenticated`, 'i'),
    );
  }
  assert.match(sql, /REVOKE ALL ON (?:TABLE )?public\.card_benefits FROM PUBLIC, anon, authenticated/i);
  assert.match(sql, /REVOKE ALL ON (?:TABLE )?public\.active_card_benefits FROM PUBLIC, anon/i);
  assert.match(sql, /GRANT SELECT ON (?:TABLE )?public\.active_card_benefits TO authenticated, service_role/i);

  assert.match(sql, /create_credit_card/i);
  assert.match(sql, /create_or_get_card_catalog/i);
  for (const signature of [
    'normalize_benefit_exclusions_value(jsonb)',
    'is_valid_official_source_evidence(jsonb)',
    'create_or_get_card_catalog(text, text, text, text, numeric, numeric, numeric)',
    'resolve_card_catalog_identity(text, text, text, text, text, text)',
    'initialize_card_benefit_enrichment_pilot(jsonb, text)',
    'claim_card_catalog_enrichment_jobs(integer, integer, text, text)',
    'stage_card_benefit_enrichment(uuid, uuid, text, text, text, text, jsonb, numeric, jsonb, jsonb, jsonb, timestamptz)',
    'finalize_card_catalog_enrichment_job(uuid, uuid, text, uuid, text, jsonb, jsonb, text, timestamptz)',
    'approve_card_benefit_enrichment(uuid, uuid, jsonb)',
    'list_pending_catalog_entry_requests()',
    'approve_catalog_entry_request(uuid, uuid)',
    'reject_catalog_entry_request(uuid, uuid)',
    'review_card_catalog_discovery(uuid, uuid, text, jsonb, uuid, text)',
    'submit_card_catalog_request(uuid, text, text, text)',
  ]) {
    assert.match(
      sql,
      new RegExp(
        `REVOKE ALL ON FUNCTION public\\.${sqlSignaturePattern(signature)}[^;]*FROM PUBLIC, anon, authenticated;`,
        'i',
      ),
      `${signature} must be revoked from every client role in its own statement`,
    );
    assert.match(
      sql,
      new RegExp(
        `GRANT EXECUTE ON FUNCTION public\\.${sqlSignaturePattern(signature)}[^;]*TO service_role;`,
        'i',
      ),
      `${signature} must be granted to service_role in its own statement`,
    );
  }
  assert.doesNotMatch(sql, /auth\.role\s*\(/i);
});
