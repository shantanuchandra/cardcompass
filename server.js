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
  if (url.includes('\0') || segments.includes('..') || segments.includes('.')) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  // Block direct access to .env and server internals
  if (url === '/.env' || url === '/server.js') {
    res.writeHead(403); res.end('Forbidden'); return;
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

  // Serve repository routes first (for existing app assets), then mirror the
  // production deploy root from landing/ for public pages and assets.
  const relativePath = url.replace(/^\/+/, '');
  const candidates = url === '/'
    ? [path.join(landingRoot, 'index.html')]
    : [path.join(__dirname, relativePath), path.join(landingRoot, relativePath)];
  let filePath = candidates.find((candidate) => candidate.startsWith(`${__dirname}${path.sep}`) && fs.existsSync(candidate));

  // Directory → index.html
  if (filePath && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  if (!filePath || !filePath.startsWith(`${__dirname}${path.sep}`) || !fs.existsSync(filePath)) {
    res.writeHead(404); res.end('Not found'); return;
  }

  const ext  = path.extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': mime });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, () => {
  console.log(`[CardCompass] http://localhost:${PORT}`);
  console.log(`  /login  → login page`);
  console.log(`  /       → landing page`);
});
