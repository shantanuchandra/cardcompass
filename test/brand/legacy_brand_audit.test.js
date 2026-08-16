import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

function dartSources(dir = 'lib') {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) return dartSources(target);
    return entry.name.endsWith('.dart') ? [fs.readFileSync(target, 'utf8')] : [];
  }).join('\n');
}

test('product UI contains no legacy cyberpunk identity', () => {
  const dart = dartSources();
  assert.doesNotMatch(dart, /neonGlow|cyanGradient|#00F5FF|#8B5CF6/i);
  assert.doesNotMatch(dart, /GoogleFonts\.(inter|spaceGrotesk)/);
  assert.doesNotMatch(dart, /AppColors\.|AppSpacing\.|AppRadius\./);
});

test('brand documentation names the canonical semantic roles', () => {
  const html = fs.readFileSync('landing/design-system.html', 'utf8');
  for (const role of ['Ink', 'Paper', 'Ledger', 'Signal', 'Reward']) {
    assert.match(html, new RegExp(role, 'i'));
  }
  assert.doesNotMatch(html, /cyberpunk|neon glow/i);
});
