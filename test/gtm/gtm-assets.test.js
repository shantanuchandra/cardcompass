import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const docsRoot = new URL('../../docs/gtm/', import.meta.url);

test('founder-led playbook defines the requested operating cadence and consent safeguards', async () => {
  const playbook = await readFile(new URL('founder-led-playbook.md', docsRoot), 'utf8');

  assert.match(playbook, /8-week/i);
  assert.match(playbook, /twice[- ]weekly/i);
  assert.match(playbook, /10[–-]15/i);
  assert.match(playbook, /every 25 qualified leads/i);
  assert.match(playbook, /Reddit/i);
  assert.match(playbook, /community rules/i);
  assert.match(playbook, /written consent/i);
  assert.match(playbook, /withdraw/i);
});

test('operating scorecard defines computable formulas and thresholds', async () => {
  const scorecard = await readFile(new URL('operating-scorecard.md', docsRoot), 'utf8');

  for (const formula of [
    /Qualified lead rate\s*=\s*qualified leads\s*\/\s*completed applications/i,
    /Application completion rate\s*=\s*completed applications\s*\/\s*waitlist starts/i,
    /Invite activation rate\s*=\s*activated invitees\s*\/\s*invites sent/i,
    /Week-2 retention\s*=\s*invitees active in week 2\s*\/\s*activated invitees/i,
  ]) {
    assert.match(scorecard, formula);
  }
  assert.match(scorecard, /every 25 qualified leads/i);
  assert.match(scorecard, /stop|pause/i);
  assert.match(
    scorecard,
    /Source-qualified rate\s*=\s*qualified submitted applications from source\s*\/\s*submitted applications from source/i,
  );
  assert.match(scorecard, /overall application completion rate.*Plausible starts.*database `enriched_at`/i);
  assert.match(scorecard, /not source-segmented/i);
  assert.match(scorecard, /each activated user.*days 8[–-]14 after their own activation date/i);
  assert.match(scorecard, /Source-qualified rate[\s\S]*≥ overall rate[\s\S]*< 15 percentage points below overall[\s\S]*≥ 15 percentage points below overall/i);
  assert.match(scorecard, /Interview coverage[\s\S]*20–40%[\s\S]*10–<20% or >40%[\s\S]*<10%/i);
});

test('invitation file contains three copy-ready personalized email templates', async () => {
  const emails = await readFile(new URL('invitation-email-templates.md', docsRoot), 'utf8');
  const subjects = [...emails.matchAll(/^Subject:/gm)];

  assert.equal(subjects.length, 3);
  assert.match(emails, /\{\{first_name\}\}/);
  assert.match(emails, /\{\{personalized_reason\}\}/);
  assert.match(emails, /\{\{invite_link\}\}/);
  assert.match(emails, /why you'?re receiving/i);
});
