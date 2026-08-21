import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const readWorkflow = () =>
  readFile(
    new URL(".github/workflows/benefit-enrichment-schedule.yml", root),
    "utf8",
  );

test("scheduler invokes scheduled enrichment safely with its dedicated credential", async () => {
  const workflow = await readWorkflow();

  assert.match(
    workflow,
    /schedule:\s*\n\s*-\s*cron:\s*['"]\*\/15 \* \* \* \*['"]/,
  );
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(
    workflow,
    /run_mode:\s*\n\s*description:\s*Benefit enrichment run mode[\s\S]*default:\s*scheduled[\s\S]*options:\s*\n\s*-\s*scheduled\s*\n\s*-\s*pilot/,
  );
  assert.match(
    workflow,
    /if:\s*github\.event_name == 'workflow_dispatch' \|\| vars\.CARD_INGESTION_V6_SCHEDULE_ENABLED == 'true'/,
  );
  assert.match(
    workflow,
    /concurrency:\s*\n\s*group:\s*cardcompass-issuer-crawl\s*\n\s*cancel-in-progress:\s*false/,
  );
  assert.match(workflow, /timeout-minutes:\s*5/);
  assert.match(workflow, /BENEFIT_ENRICHMENT_CRON_SECRET/);
  assert.match(
    workflow,
    /-H\s+"x-cardcompass-cron-secret:\s*\$\{BENEFIT_ENRICHMENT_CRON_SECRET\}"/i,
  );
  assert.match(workflow, /SUPABASE_URL/);
  assert.match(workflow, /run_mode=.*inputs\.run_mode/);
  assert.match(workflow, /retry_count=2/);
  assert.match(
    workflow,
    /if \[\[ "\$run_mode" == "pilot" \]\]; then\s*\n\s*retry_count=0/,
  );
  assert.match(
    workflow,
    /curl\s+--fail-with-body\s+--connect-timeout\s+10\s+--max-time\s+240\s+--retry\s+"\$retry_count"/,
  );
  assert.match(workflow, /-X\s+POST/);
  assert.ok(
    workflow.includes('--data "{\\"runMode\\":\\"${run_mode}\\"}"'),
  );
  assert.match(workflow, /JSON\.parse/);
  assert.match(workflow, /runId/);
  assert.match(workflow, /payload\?\.status === "paused"/);
  assert.match(workflow, /Scheduled enrichment is paused/);
  const referencedSecrets = [
    ...workflow.matchAll(/\bsecrets\.([A-Z0-9_]+)/g),
  ].map((match) => match[1]).sort();
  assert.deepEqual(referencedSecrets, [
    "BENEFIT_ENRICHMENT_CRON_SECRET",
    "SUPABASE_URL",
  ]);
  assert.doesNotMatch(
    workflow,
    /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE|ANON_KEY|SUPABASE_ANON_KEY/i,
  );
});
