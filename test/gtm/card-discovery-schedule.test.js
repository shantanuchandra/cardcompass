import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../../", import.meta.url);
const readWorkflow = (name) =>
  readFile(new URL(`.github/workflows/${name}`, root), "utf8");

test("daily issuer discovery uses the shared non-cancelling crawl lane and existing credential", async () => {
  const [discovery, enrichment] = await Promise.all([
    readWorkflow("card-discovery-schedule.yml"),
    readWorkflow("benefit-enrichment-schedule.yml"),
  ]);
  for (
    const [name, workflow] of [
      ["discovery", discovery],
      ["enrichment", enrichment],
    ]
  ) {
    assert.match(
      workflow,
      /concurrency:\s*\n\s*group:\s*cardcompass-issuer-crawl\s*\n\s*cancel-in-progress:\s*false/,
      `${name} workflow is outside the repository-wide issuer crawl lane`,
    );
    assert.match(workflow, /timeout-minutes:\s*5/);
  }

  assert.match(discovery, /schedule:\s*\n\s*-\s*cron:\s*['"][^'"]+['"]/);
  assert.match(discovery, /workflow_dispatch:/);
  assert.match(
    discovery,
    /run_mode:[\s\S]*type:\s*choice[\s\S]*options:[\s\S]*- scheduled[\s\S]*- manual/,
  );
  assert.match(
    discovery,
    /if:\s*github\.event_name == 'workflow_dispatch' \|\| vars\.CARD_DISCOVERY_SCHEDULE_ENABLED == 'true'/,
  );
  assert.match(
    discovery,
    /curl\s+--fail-with-body\s+--connect-timeout\s+10\s+--max-time\s+240/,
  );
  assert.match(
    discovery,
    /-H\s+"x-cardcompass-cron-secret:\s*\$\{BENEFIT_ENRICHMENT_CRON_SECRET\}"/i,
  );
  assert.match(
    discovery,
    /DISCOVERY_RUN_MODE/,
  );
  assert.match(discovery, /payload\?\.status === "paused"/);
  assert.match(discovery, /SUPABASE_FUNCTION_URL/);
  assert.doesNotMatch(
    discovery,
    /SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY|ANON_KEY/i,
  );
  const referencedSecrets = [
    ...discovery.matchAll(/\bsecrets\.([A-Z0-9_]+)/g),
  ].map((match) => match[1]).sort();
  assert.deepEqual(referencedSecrets, [
    "BENEFIT_ENRICHMENT_CRON_SECRET",
    "SUPABASE_FUNCTION_URL",
  ]);
});
