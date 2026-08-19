import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';

export const psqlArgs = ['-X', '-A', '-t', '--set', 'ON_ERROR_STOP=1', '--file', '-'];

export function derivePgConnection(databaseUrl, databaseName, inheritedEnv = process.env) {
  const parsed = new URL(databaseUrl);
  assert.ok(['postgres:', 'postgresql:'].includes(parsed.protocol), 'integration database URL must use PostgreSQL');
  assert.ok(parsed.hostname === '' || ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname), 'integration tests refuse non-loopback PostgreSQL servers');
  assert.match(databaseName, /^[a-zA-Z0-9_]+$/, 'database name must be identifier-safe');
  const env = {};
  for (const name of ['PATH', 'LANG', 'LC_ALL', 'TMPDIR', 'SYSTEMROOT']) {
    if (inheritedEnv[name]) env[name] = inheritedEnv[name];
  }
  env.PGHOST = parsed.hostname || '/tmp';
  env.PGPORT = parsed.port || '5432';
  env.PGDATABASE = databaseName;
  env.PGPASSFILE = '/dev/null';
  env.PGSERVICEFILE = '/dev/null';
  if (parsed.username) env.PGUSER = decodeURIComponent(parsed.username);
  if (parsed.password) env.PGPASSWORD = decodeURIComponent(parsed.password);
  const supportedOptions = new Map([
    ['sslmode', 'PGSSLMODE'], ['sslcert', 'PGSSLCERT'], ['sslkey', 'PGSSLKEY'],
    ['sslrootcert', 'PGSSLROOTCERT'], ['sslcrl', 'PGSSLCRL'], ['sslcrldir', 'PGSSLCRLDIR'],
    ['sslcertmode', 'PGSSLCERTMODE'], ['sslnegotiation', 'PGSSLNEGOTIATION'], ['sslsni', 'PGSSNI'],
    ['channel_binding', 'PGCHANNELBINDING'], ['connect_timeout', 'PGCONNECT_TIMEOUT'],
    ['target_session_attrs', 'PGTARGETSESSIONATTRS'], ['application_name', 'PGAPPNAME'], ['options', 'PGOPTIONS'],
  ]);
  for (const [name] of parsed.searchParams) assert.ok(supportedOptions.has(name), `unsupported PostgreSQL URL option: ${name}`);
  for (const [parameter, variable] of supportedOptions) {
    if (parsed.searchParams.has(parameter)) env[variable] = parsed.searchParams.get(parameter);
  }
  return { env, secrets: [databaseUrl, env.PGPASSWORD].filter(Boolean) };
}

export function redactSecrets(value, secrets) {
  return secrets.reduce((redacted, secret) => redacted.replaceAll(secret, '[REDACTED]'), String(value ?? ''));
}

export function psql(connection, sql) {
  const result = spawnSync('psql', psqlArgs, { input: sql, encoding: 'utf8', env: connection.env });
  if (result.status !== 0) throw new Error(`PostgreSQL integration command failed:\n${redactSecrets(result.stderr, connection.secrets)}`);
  return result.stdout.trim();
}

export function psqlAsync(connection, sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('psql', psqlArgs, { stdio: ['pipe', 'pipe', 'pipe'], env: connection.env });
    let stderr = '';
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0 ? resolve() : reject(new Error(`PostgreSQL integration command failed:\n${redactSecrets(stderr, connection.secrets)}`)));
    child.stdin.end(sql);
  });
}

export function ensureRoles(adminConnection, roles, runPsql = psql) {
  const created = [];
  try {
    for (const role of roles) {
      assert.match(role, /^[a-z_]+$/);
      if (!runPsql(adminConnection, `select exists (select 1 from pg_roles where rolname = '${role}');`).endsWith('t')) {
        runPsql(adminConnection, `create role ${role} nologin;`);
        created.push(role);
      }
    }
    return created;
  } catch (error) {
    for (const role of [...created].reverse()) {
      runPsql(adminConnection, `drop role if exists ${role};`);
    }
    throw error;
  }
}

export function dropDisposableDatabase(adminConnection, databaseName, createdRoles = []) {
  assert.match(databaseName, /^[a-z_]+\d+_\d+$/);
  try { psql(adminConnection, `drop database if exists "${databaseName}" with (force);`); }
  finally { for (const role of [...createdRoles].reverse()) psql(adminConnection, `drop role if exists ${role};`); }
}
