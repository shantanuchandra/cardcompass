export function splitSqlStatements(sql) {
  const statements = [];
  let start = 0, quote = null;
  for (let index = 0; index < sql.length; index++) {
    if (quote) {
      if (sql.startsWith(quote, index)) { index += quote.length - 1; quote = null; }
      continue;
    }
    const dollar = sql.slice(index).match(/^\$[a-z0-9_]*\$/i)?.[0];
    if (dollar) { quote = dollar; index += dollar.length - 1; }
    else if (sql[index] === ';') { statements.push(sql.slice(start, index + 1)); start = index + 1; }
  }
  if (sql.slice(start).trim()) statements.push(sql.slice(start));
  return statements;
}

function keyOf(statement) {
  const match = statement.match(/function\s+((?:public|private)\.[a-z0-9_]+)\s*\(([^)]*)\)/i);
  if (!match) return null;
  const args = match[2].split(',').map((arg) => arg.trim()
    .replace(/\s+default\s+[\s\S]*$/i, '').replace(/^[_a-z][_a-z0-9]*\s+/i, '')
    .replace(/\s+/g, ' ').toLowerCase()).join(',');
  return `${match[1].toLowerCase()}(${args})`;
}

export function analyzeFunctionSecurity(files) {
  const state = new Map();
  for (const { sql } of files) for (const raw of splitSqlStatements(sql)) {
    const statement = raw.replace(/--[^\n]*/g, ' ').trim();
    const key = keyOf(statement);
    if (!key) continue;
    if (/^drop\s+function/i.test(statement)) { state.delete(key); continue; }
    if (/^create\s+(?:or\s+replace\s+)?function/i.test(statement)) {
      const prior = state.get(key);
      state.set(key, { key, body: statement, definer: /security\s+definer/i.test(statement),
        publicExecute: prior?.publicExecute ?? true, authenticatedExecute: prior?.authenticatedExecute ?? false });
      continue;
    }
    const current = state.get(key);
    if (!current) continue;
    if (/^alter\s+function/i.test(statement)) {
      if (/security\s+invoker/i.test(statement)) current.definer = false;
      if (/security\s+definer/i.test(statement)) current.definer = true;
    }
    if (/^revoke\s+(?:all|execute)/i.test(statement)) {
      if (/\bfrom\s+[^;]*\bpublic\b/i.test(statement)) current.publicExecute = false;
      if (/\bfrom\s+[^;]*\bauthenticated\b/i.test(statement)) current.authenticatedExecute = false;
    }
    if (/^grant\s+(?:all|execute)/i.test(statement)) {
      if (/\bto\s+[^;]*\bpublic\b/i.test(statement)) current.publicExecute = true;
      if (/\bto\s+[^;]*\bauthenticated\b/i.test(statement)) current.authenticatedExecute = true;
    }
  }
  return [...state.values()];
}

export function discoverUserServiceGateways(files) {
  return files.filter(({ path, source }) => /auth\.getUser\s*\(/.test(source) &&
    /SUPABASE_SERVICE_ROLE_KEY/.test(source) && !/(?:^|\/)admin-[^/]+\//.test(path));
}

export function hasEarlyActiveGate(source) {
  const auth = source.indexOf('.auth.getUser');
  const gate = source.indexOf('requireActiveProfile', auth);
  const tail = source.slice(auth + 12);
  const offset = [tail.indexOf('.from('), tail.indexOf('.rpc('), tail.indexOf('.storage')]
    .filter((value) => value >= 0).sort((a, b) => a - b)[0];
  const privileged = offset === undefined ? source.length : auth + 12 + offset;
  return source.includes('../_shared/active_profile.ts') && gate > auth && gate < privileged;
}
