import { writeFile } from 'node:fs/promises';

export function buildPublicEnvModule(environment = process.env) {
  return `export const SUPABASE_URL = ${JSON.stringify(environment.SUPABASE_URL || '')};\nexport const SUPABASE_ANON = ${JSON.stringify(environment.SUPABASE_ANON_KEY || '')};\n`;
}

const output = buildPublicEnvModule();
const target = process.argv[2];

if (target) {
  await writeFile(target, output, { encoding: 'utf8', mode: 0o600 });
} else {
  process.stdout.write(output);
}
