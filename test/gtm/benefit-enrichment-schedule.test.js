import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const readWorkflow = () =>
  readFile(new URL('.github/workflows/benefit-enrichment-schedule.yml', root), 'utf8');

test('scheduler invokes scheduled enrichment safely with its dedicated credential', async () => {
  const workflow = await readWorkflow();

  assert.match(workflow, /schedule:\s*\n\s*-\s*cron:\s*['"]\*\/15 \* \* \* \*['"]/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /concurrency:\s*[\s\S]*?cancel-in-progress:\s*false/);
  assert.match(workflow, /timeout-minutes:\s*5/);
  assert.match(workflow, /BENEFIT_ENRICHMENT_CRON_SECRET/);
  assert.match(
    workflow,
    /-H\s+"x-cardcompass-cron-secret:\s*\$\{BENEFIT_ENRICHMENT_CRON_SECRET\}"/i,
  );
  assert.match(workflow, /SUPABASE_URL/);
  assert.match(workflow, /curl\s+--fail-with-body\s+--connect-timeout\s+10\s+--max-time\s+240\s+--retry\s+2/);
  assert.match(workflow, /-X\s+POST/);
  assert.match(workflow, /\{\\?"mode\\?":\\?"scheduled\\?"\}/);
  assert.match(workflow, /JSON\.parse/);
  assert.match(workflow, /runId/);
  const referencedSecrets = [
    ...workflow.matchAll(/\bsecrets\.([A-Z0-9_]+)/g),
  ].map((match) => match[1]).sort();
  assert.deepEqual(referencedSecrets, [
    'BENEFIT_ENRICHMENT_CRON_SECRET',
    'SUPABASE_URL',
  ]);
  assert.doesNotMatch(workflow, /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE|ANON_KEY|SUPABASE_ANON_KEY/i);
});
