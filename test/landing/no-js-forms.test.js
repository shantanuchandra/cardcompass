import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('every waitlist form fails closed to a non-query POST action without JavaScript', async () => {
  const html = await readFile(new URL('../../landing/index.html', import.meta.url), 'utf8');
  const forms = [...html.matchAll(/<form\b[^>]*\bid="(?:joinForm|qualificationForm)"[^>]*>/g)]
    .map(([markup]) => markup);

  assert.equal(forms.length, 2);
  for (const form of forms) {
    assert.match(form, /\bmethod="post"/i);
    assert.match(form, /\baction="\/waitlist-unavailable\/"/i);
    assert.doesNotMatch(form, /\baction="[^"]*\?/i);
  }
});
