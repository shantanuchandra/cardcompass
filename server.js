// Minimal dev server: serves static files + injects .env as /env.js
// Usage: node server.js [port]   (default 8080)
// Never exposes the raw .env file — only the parsed values via /env.js.

import http from 'http';
import fs   from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT      = Number(process.argv[2]) || 8080;
const landingRoot = path.join(__dirname, 'landing');
const appRoot = path.join(__dirname, 'build', 'web');

const SENSITIVE_BASENAMES = new Set([
  'dart_defines.json',
  'package.json',
  'package-lock.json',
  'pubspec.lock',
  'pubspec.yaml',
  'schema.sql',
  'server.js',
]);
const SENSITIVE_EXTENSIONS = new Set(['.dart', '.lock', '.md', '.sql', '.toml', '.yaml', '.yml']);

// ── Load env vars ────────────────────────────────────────────────────────────
// Production: set SUPABASE_URL and SUPABASE_ANON_KEY in the deployment platform.
// Local dev:  copy .env.example → .env and fill in values.
function loadEnv() {
  const env = {
    SUPABASE_URL:      process.env.SUPABASE_URL      || '',
    SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY || '',
  };

  // In local dev, supplement with .env file for any missing values
  const file = path.join(__dirname, '.env');
  if (fs.existsSync(file)) {
    const parsed = Object.fromEntries(
      fs.readFileSync(file, 'utf8')
        .split('\n')
        .map(l => l.trim())
        .filter(l => l && !l.startsWith('#'))
        .map(l => { const i = l.indexOf('='); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; })
    );
    if (!env.SUPABASE_URL)      env.SUPABASE_URL      = parsed.SUPABASE_URL      || '';
    if (!env.SUPABASE_ANON_KEY) env.SUPABASE_ANON_KEY = parsed.SUPABASE_ANON_KEY || '';
  } else if (!env.SUPABASE_URL) {
    console.warn('[server] .env not found and no env vars set — copy .env.example to .env');
  }

  return env;
}

// ── MIME types ───────────────────────────────────────────────────────────────
const MIME = {
  '.html': 'text/html',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.json': 'application/json',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.txt':  'text/plain',
  '.woff2':'font/woff2',
};

// ── Server ───────────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  let url;
  try {
    url = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    res.writeHead(400); res.end('Bad request'); return;
  }

  const segments = url.split('/');
  const basename = segments.at(-1)?.toLowerCase() || '';
  if (
    url.includes('\0')
    || url.includes('\\')
    || segments.some((segment) => segment === '..' || segment === '.' || segment.startsWith('.'))
    || segments.some((segment) => ['.git', 'supabase'].includes(segment.toLowerCase()))
    || SENSITIVE_BASENAMES.has(basename)
    || SENSITIVE_EXTENSIONS.has(path.extname(basename))
  ) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  if (!['GET', 'HEAD'].includes(req.method || 'GET')) {
    res.writeHead(405, { Allow: 'GET, HEAD' }); res.end('Method not allowed'); return;
  }

  if (url === '/login' || url === '/login/') {
    res.writeHead(302, { Location: '/app/#/login', 'Cache-Control': 'no-store' });
    res.end();
    return;
  }

  // Inject env values as a JS module — never exposes raw .env
  if (url === '/env.js') {
    const env = loadEnv();
    const body = `export const SUPABASE_URL = ${JSON.stringify(env.SUPABASE_URL || '')};
export const SUPABASE_ANON = ${JSON.stringify(env.SUPABASE_ANON_KEY || '')};
`;
    res.writeHead(200, { 'Content-Type': 'application/javascript', 'Cache-Control': 'no-store' });
    res.end(body);
    return;
  }

  // Each URL namespace maps to one public root. Repository files outside
  // these roots are never candidates for static serving.
  let publicRoot = landingRoot;
  let publicPath = url;
  if (url === '/app' || url.startsWith('/app/')) {
    publicRoot = appRoot;
    publicPath = url.slice('/app'.length) || '/';
  }

  const resolvedRoot = path.resolve(publicRoot);
  let filePath = path.resolve(resolvedRoot, `.${publicPath}`);
  const isWithinRoot = (candidate) => candidate === resolvedRoot || candidate.startsWith(`${resolvedRoot}${path.sep}`);
  if (!isWithinRoot(filePath)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  // Directory → index.html
  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  if (!isWithinRoot(filePath) || !fs.existsSync(filePath)) {
    res.writeHead(404); res.end('Not found'); return;
  }

  const realRoot = fs.realpathSync(resolvedRoot);
  const realFilePath = fs.realpathSync(filePath);
  if (realFilePath !== realRoot && !realFilePath.startsWith(`${realRoot}${path.sep}`)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  const ext  = path.extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': mime });
  if (req.method === 'HEAD') res.end();
  else fs.createReadStream(realFilePath).pipe(res);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[CardCompass] http://localhost:${PORT}`);
  console.log(`  /       → landing page`);
});
