import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const migrationPath = path.join(
  process.cwd(),
  'supabase/migrations/20260821153000_fix_catalog_publication_post_lock_replay.sql',
);

test('forward migration refreshes publication replay state after the job advisory', () => {
  const sql = fs.readFileSync(migrationPath, 'utf8');
  assert.match(
    sql,
    /old_fragment[\s\S]*observed_job := job_row[\s\S]*post_advisory_publication_replay_refresh/i,
  );
  assert.match(
    sql,
    /SELECT job\.\* INTO observed_job[\s\S]*SELECT review\.\* INTO observed_review/i,
  );
  assert.match(
    sql,
    /_review_item_id IS NOT NULL[\s\S]*_action NOT IN \('retry', 'reject'\)/i,
  );
  assert.doesNotMatch(
    sql,
    /post_advisory_publication_replay_refresh[\s\S]{0,800}FOR UPDATE/i,
  );
  assert.match(
    sql,
    /catalog_publication_post_lock_replay_source_missing/i,
  );
});
