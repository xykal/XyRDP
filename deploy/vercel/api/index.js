/* ============================================================================
 * XyRDP Dashboard — Vercel catch-all function (Node, tanpa dependency)
 *
 * DUA MODE AKSES
 *  1) ADMIN — login email AUTH_USER + AUTH_PASS, diverifikasi Cloudflare
 *             Turnstile. Sesi cookie HttpOnly terenkripsi; tanpa konfigurasi
 *             kredensial/Turnstile admin tertutup (fail-closed).
 *  2) USER  — pengunjung yang login "Masuk dengan GitHub" (OAuth App). Semua
 *             perintah dijalankan di repo MILIK MEREKA (hasil kopi template),
 *             dengan token OAuth mereka sendiri. Server tidak menyimpan
 *             token/secret mereka: sesi hanya di cookie terenkripsi (AES-GCM).
 *
 * Endpoint: /panduan, /auth/{status,login,callback,logout}, /me, /setup,
 *           /config, /status, /start, /stop, /logs, /extras, /wallpaper
 * ==========================================================================*/
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
let sodium = null;
try { sodium = require('libsodium-wrappers'); } catch(e) { console.warn('libsodium not available', e.message); }

const API = 'https://api.github.com';
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Frame-Options': 'DENY',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'Content-Security-Policy': "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; img-src 'self' data: https://avatars.githubusercontent.com https://raw.githubusercontent.com https://challenges.cloudflare.com; script-src 'self' 'unsafe-inline' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; connect-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; form-action 'self' https://github.com; worker-src 'self' blob:;",
};

const ENV = {
  // --- mode admin (perilaku lama) ---
  token: process.env.GITHUB_TOKEN || '',
  owner: process.env.GH_OWNER || 'xykal',
  repo: process.env.GH_REPO || 'XyRDP',
  workflow: process.env.GH_WORKFLOW || 'rdp-6h.yml',
  branch: process.env.GH_BRANCH || 'main',
  rdp_user: process.env.RDP_USER || 'xyadmin',
  rdp_password: process.env.RDP_PASSWORD || '',
  // --- multi-user (OAuth App) ---
  oauth_id: process.env.GITHUB_OAUTH_CLIENT_ID || '',
  oauth_secret: process.env.GITHUB_OAUTH_CLIENT_SECRET || '',
  session_secret: process.env.SESSION_SECRET || '',
  template: process.env.TEMPLATE_REPO || `${process.env.GH_OWNER || 'xykal'}/${process.env.GH_REPO || 'XyRDP'}`,
  owner_login: (process.env.OWNER_LOGIN || process.env.GH_OWNER || 'xykal').toLowerCase(),
  turnstile_site_key: process.env.TURNSTILE_SITE_KEY || '',
  turnstile_secret: process.env.TURNSTILE_SECRET_KEY || '',
  turnstile_hostname: (process.env.TURNSTILE_HOSTNAME || 'xyrdp-dash.vercel.app').toLowerCase(),
};

const STATUS_BRANCH = 'status';        // branch tempat workflow menulis rdp-status.json
const EXTRAS_PATH = 'assets/rdp-extras.json';
// Pause semua pembuatan/permintaan sesi baru sampai arsitektur RDP dinyatakan sesuai kebijakan host.
const RDP_START_PAUSED = String(process.env.RDP_START_PAUSED || 'false').toLowerCase() === 'true';
const RDP_PAUSE_MESSAGE = 'Sesi RDP baru sedang dijeda. Jangan buat repo/secret baru atau dispatch workflow. GitHub-hosted Actions bukan layanan desktop RDP umum; baca /panduan untuk alasan, langkah pengamanan, dan banding resmi.';
const EXTRAS_DEFAULTS = { lightshot: false, translucent: true, translucent_mode: 'clear', wallpaper: true, wallpaper_file: 'wallpaper.jpg', win10_look: true, win10_badge: true, win10_wallpaper: true, xydesk_host: true, dark_theme: true, lightweight_mode: true, vscode: false, notepadpp: false, rdp_user: 'xyadmin' };
const RDP_USERNAME_RESERVED = new Set(['administrator', 'guest', 'defaultaccount', 'wdagutilityaccount', 'system', 'localservice', 'networkservice', 'con', 'prn', 'aux', 'nul']);
function normalizeRdpUser(value) {
  const name = String(value || '').trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{2,19}$/.test(name) || RDP_USERNAME_RESERVED.has(name.toLowerCase())) return '';
  return name;
}
const WALLPAPER_RE = /^wallpaper\.(jpg|jpeg|png|bmp)$/i;
const SECRETS_REQUIRED = ['RDP_PASSWORD', 'TAILSCALE_AUTH_KEY'];
const SECRETS_OPTIONAL = ['NGROK_AUTHTOKEN', 'CLEANUP_TOKEN'];
const SESSION_TTL_DAYS = 7;
const ADMIN_TTL_SECONDS = 12 * 60 * 60;
const ADMIN_LOGIN_WINDOW_MS = 15 * 60 * 1000;
const ADMIN_LOGIN_MAX_FAILURES = 5;
const adminLoginAttempts = new Map();
function sessionSecretReady() {
  return !!process.env.SESSION_SECRET && Buffer.byteLength(process.env.SESSION_SECRET, 'utf8') >= 32;
}

/* ---------------------------------------------------------------- session -- */
function b64u(buf) { return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function unb64u(str) { return Buffer.from(String(str).replace(/-/g, '+').replace(/_/g, '/'), 'base64'); }
function sessionKey() {
  if (!sessionSecretReady()) throw new Error('SESSION_SECRET belum diatur atau terlalu pendek');
  return crypto.createHash('sha256').update(ENV.session_secret + '|xyrdp-session').digest();
}

function seal(obj) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', sessionKey(), iv);
  const ct = Buffer.concat([c.update(JSON.stringify(obj), 'utf8'), c.final()]);
  return b64u(Buffer.concat([iv, c.getAuthTag(), ct]));
}
function unseal(str) {
  try {
    const raw = unb64u(str);
    if (raw.length < 29) return null;
    const d = crypto.createDecipheriv('aes-256-gcm', sessionKey(), raw.subarray(0, 12));
    d.setAuthTag(raw.subarray(12, 28));
    const out = Buffer.concat([d.update(raw.subarray(28)), d.final()]).toString('utf8');
    return JSON.parse(out);
  } catch { return null; }
}

function cookieHeader(name, value, maxAge) {
  const secure = process.env.VERCEL_ENV ? '; Secure' : '';
  return `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}
function readCookies(req) {
  const out = {};
  (req.headers.cookie || '').split(';').forEach(part => {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  });
  return out;
}

function adminConfigured() {
  return !!String(process.env.AUTH_USER || '').trim() && !!process.env.AUTH_PASS;
}
function adminLoginReady() {
  return adminConfigured() && sessionSecretReady() && !!ENV.turnstile_site_key && !!ENV.turnstile_secret;
}
function adminCredVersion() {
  return crypto.createHash('sha256')
    .update(String(process.env.AUTH_USER || '').trim().toLowerCase() + '|' + (process.env.AUTH_PASS || '') + '|xyrdp-admin-v2')
    .digest('hex');
}
function credsOk(u, p) {
  if (!adminConfigured()) return false;
  const user = String(u || '').trim().toLowerCase();
  const expectedUser = String(process.env.AUTH_USER || '').trim().toLowerCase();
  if (user !== expectedUser) return false;
  const given = crypto.createHash('sha256').update(String(p || ''), 'utf8').digest();
  const expected = crypto.createHash('sha256').update(String(process.env.AUTH_PASS || ''), 'utf8').digest();
  return crypto.timingSafeEqual(given, expected);
}
function adminOk(req) {
  if (!adminLoginReady()) return false;
  const c = readCookies(req);
  if (!c.sid) return false;
  const s = unseal(c.sid);
  return !!(s && s.k === 'admin' && s.v === adminCredVersion() && s.e && Date.now() < s.e);
}
function clientAddress(req) {
  const raw = req.headers['x-real-ip'] || req.headers['x-forwarded-for'] || req.socket && req.socket.remoteAddress || 'unknown';
  return String(raw).split(',')[0].trim().slice(0, 120) || 'unknown';
}
function loginRate(req, failed = false, reset = false) {
  const key = clientAddress(req), now = Date.now();
  let bucket = adminLoginAttempts.get(key);
  if (!bucket || now - bucket.at >= ADMIN_LOGIN_WINDOW_MS) bucket = { at: now, failures: 0 };
  if (reset) { adminLoginAttempts.delete(key); return { locked: false, retry: 0 }; }
  if (failed) bucket.failures++;
  adminLoginAttempts.set(key, bucket);
  if (adminLoginAttempts.size > 2000) {
    for (const [k, b] of adminLoginAttempts) if (now - b.at >= ADMIN_LOGIN_WINDOW_MS) adminLoginAttempts.delete(k);
  }
  const locked = bucket.failures >= ADMIN_LOGIN_MAX_FAILURES;
  return { locked, retry: locked ? Math.max(1, Math.ceil((ADMIN_LOGIN_WINDOW_MS - (now - bucket.at)) / 1000)) : 0 };
}
async function verifyTurnstile(token, req) {
  if (!sessionSecretReady() || !ENV.turnstile_site_key || !ENV.turnstile_secret) return { ok: false, reason: 'not_configured' };
  if (!token) return { ok: false, reason: 'missing_token' };
  try {
    const body = new URLSearchParams({ secret: ENV.turnstile_secret, response: String(token) });
    const ip = clientAddress(req);
    if (ip && ip !== 'unknown') body.set('remoteip', ip);
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body,
    });
    if (!r.ok) return { ok: false, reason: 'service_unavailable' };
    const result = await r.json();
    if (!result || !result.success) return { ok: false, reason: 'challenge_failed' };
    if (String(result.hostname || '').toLowerCase() !== ENV.turnstile_hostname) return { ok: false, reason: 'hostname_mismatch' };
    // Cloudflare mengembalikan action bila disertakan pada render(); izinkan
    // field kosong dari kompatibilitas provider, tapi tolak action yang berbeda.
    if (result.action && result.action !== 'admin_login') return { ok: false, reason: 'action_mismatch' };
    return { ok: true, reason: '' };
  } catch { return { ok: false, reason: 'service_unavailable' }; }
}
function ghUser(req) {
  if (!sessionSecretReady()) return null;
  const c = readCookies(req);
  if (!c.ghs) return null;
  const s = unseal(c.ghs);
  if (!s || !s.t || !s.r) return null;
  if (s.e && Date.now() > s.e) return null;
  const [o, r] = String(s.r).split('/');
  if (!o || !r) return null;
  return { token: s.t, login: s.l || '', name: s.n || '', avatar: s.a || '', owner: o, repo: r, is_owner: (s.l || '').toLowerCase() === ENV.owner_login };
}

/* ------------------------------------------------------------------ ctx ---- */
// ctx = { kind:'admin'|'user', token, owner, repo, login, rdp_user, rdp_password }
function makeCtx(req) {
  if (adminOk(req)) {
    return {
      kind: 'admin', login: ENV.owner_login, token: ENV.token,
      owner: ENV.owner, repo: ENV.repo, display: `${ENV.owner}/${ENV.repo}`,
      rdp_user: ENV.rdp_user, rdp_password: ENV.rdp_password, has_admin_token: !!ENV.token,
    };
  }
  const u = ghUser(req);
  if (u) {
    return {
      kind: 'user', login: u.login, token: u.token,
      owner: u.owner, repo: u.repo, display: `${u.owner}/${u.repo}`,
      rdp_user: ENV.rdp_user, rdp_password: '', avatar: u.avatar, name: u.name,
      is_owner: u.is_owner, has_admin_token: false,
    };
  }
  return null;
}

/* ------------------------------------------------------- GitHub REST API --- */
async function gh(token, method, apiPath, body) {
  const res = await fetch(API + apiPath, {
    method,
    headers: {
      'User-Agent': 'XyRDP-vc', 'Authorization': `Bearer ${token || ''}`,
      'X-GitHub-Api-Version': '2022-11-28',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    redirect: 'follow',
  });
  if (res.status === 204) return null;
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`GitHub API ${res.status} ${apiPath}: ${text.slice(0, 300)}`);
    err.status = res.status;
    try { err.detail = JSON.parse(text).message; } catch { /* teks biasa */ }
    throw err;
  }
  return text ? JSON.parse(text) : null;
}
async function ghSoft(token, method, apiPath, body) {
  try { return { ok: true, data: await gh(token, method, apiPath, body) }; }
  catch (e) { return { ok: false, status: e.status || 0, error: e.message }; }
}

/* ------------------------------------------------------------ repo helper -- */
async function readRepoFile(ctx, filePath) {
  try {
    const c = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${filePath}?ref=${ctx.branch || ENV.branch}`);
    if (c && c.content) return { json: JSON.parse(Buffer.from(c.content, 'base64').toString('utf8')), sha: c.sha };
  } catch { /* belum ada */ }
  return { json: null, sha: null };
}
function extrasResponse(ctx, cfg, fileExists) {
  const wf = String(cfg.wallpaper_file || 'wallpaper.jpg').replace(/[^a-zA-Z0-9._-]/g, '');
  return {
    config: cfg,
    wallpaper_exists: fileExists,
    wallpaper_url: `https://raw.githubusercontent.com/${ctx.owner}/${ctx.repo}/${ctx.branch || ENV.branch}/assets/${wf}?t=${Date.now()}`,
  };
}
function imageInfo(buf) {
  if (buf.length >= 3 && buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'jpg';
  if (buf.length >= 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'png';
  if (buf.length >= 2 && buf[0] === 0x42 && buf[1] === 0x4D) return 'bmp';
  return null;
}

const statusCache = new Map();   // key: owner/repo -> {at, data}
async function fetchStatusFile(ctx) {
  const key = `${ctx.owner}/${ctx.repo}`;
  const hit = statusCache.get(key);
  if (hit && Date.now() - hit.at < 5000) return hit.data;
  let data = null;
  // Contents API dulu = selalu segar (alamat tunnel berganti tiap sesi; alamat
  // lama bikin klien HP kena "koneksi ditolak/ditutup").
  try {
    const c = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/rdp-status.json?ref=${STATUS_BRANCH}&t=${Date.now()}`);
    if (c && c.content) data = JSON.parse(Buffer.from(c.content, 'base64').toString('utf8'));
  } catch { /* belum ada status */ }
  if (!data) {
    try {
      const r = await fetch(`https://raw.githubusercontent.com/${ctx.owner}/${ctx.repo}/${STATUS_BRANCH}/rdp-status.json?t=${Date.now()}`, { cache: 'no-store' });
      if (r.ok) data = JSON.parse(await r.text());
    } catch { /* diabaikan */ }
  }
  statusCache.set(key, { at: Date.now(), data });
  return data;
}

function unzipEntries(buf) {
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      const n = buf.readUInt16LE(i + 10);
      let off = buf.readUInt32LE(i + 16);
      const out = [];
      for (let k = 0; k < n; k++) {
        if (buf.readUInt32LE(off) !== 0x02014b50) break;
        const method = buf.readUInt16LE(off + 10);
        const csize = buf.readUInt32LE(off + 20);
        const nlen = buf.readUInt16LE(off + 28);
        const elen = buf.readUInt16LE(off + 30);
        const clen = buf.readUInt32LE(off + 32);
        const name = buf.toString('utf8', off + 46, off + 46 + nlen);
        const lhdr = buf.readUInt32LE(off + 42);
        const lnlen = buf.readUInt16LE(lhdr + 26), lelen = buf.readUInt16LE(lhdr + 28);
        const start = lhdr + 30 + lnlen + lelen;
        const data = buf.subarray(start, start + csize);
        let txt = '';
        try { txt = method === 8 ? zlib.inflateRawSync(data).toString('utf8') : data.toString('utf8'); }
        catch { txt = '(gagal dekompresi ' + name + ')'; }
        out.push({ name, txt });
        off += 46 + nlen + elen + clen;
      }
      return out;
    }
  }
  return [{ name: 'raw', txt: buf.toString('utf8') }];
}

async function activeRun(ctx) {
  const runs = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/workflows/${ENV.workflow}/runs?per_page=5`);
  const list = runs && runs.workflow_runs ? runs.workflow_runs : [];
  return list[0] || null;
}

async function readLog(ctx, runId) {
  const jobs = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/runs/${runId}/jobs`);
  const job = jobs && jobs.jobs ? jobs.jobs[0] : null;
  if (!job) return '';
  const res = await fetch(`${API}/repos/${ctx.owner}/${ctx.repo}/actions/jobs/${job.id}/logs`, {
    headers: { 'User-Agent': 'XyRDP-vc', 'Authorization': `Bearer ${ctx.token}` }, redirect: 'follow',
  });
  if (!res.ok) throw new Error('log ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  const ct = (res.headers.get('content-type') || '').toLowerCase();
  if (ct.includes('zip') || (buf.length > 4 && buf.readUInt32LE(0) === 0x04034b50)) {
    return unzipEntries(buf).sort((a, b) => a.name.localeCompare(b.name)).map(e => e.txt).join('\n');
  }
  return buf.toString('utf8');
}

function readBody(req, maxBytes = 5 * 1024 * 1024) {
  return new Promise(resolve => {
    let b = '', total = 0, tooLarge = false;
    req.on('data', c => {
      if (tooLarge) return;
      total += c.length;
      if (total > maxBytes) { tooLarge = true; b = ''; return; }
      b += c;
    });
    req.on('end', () => {
      if (tooLarge) return resolve({ __too_large: true });
      try { resolve(JSON.parse(b || '{}')); } catch { resolve({}); }
    });
    req.on('error', () => resolve({}));
  });
}

/* --------------------------------------------- status repo user (setup) ---- */
async function repoState(ctx) {
  const spec = { owner: ctx.owner, repo: ctx.repo, exists: false, private: null, default_branch: null, secrets: [], missing_required: SECRETS_REQUIRED.slice(), missing_optional: SECRETS_OPTIONAL.slice(), actions_enabled: null, workflow_permissions: null, error: '' };
  const info = await ghSoft(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}`);
  if (!info.ok) {
    if (info.status === 401) { spec.error = 'token'; return spec; }
    if (info.status === 404) return spec;                 // belum dibuat
    spec.error = info.error;
    return spec;
  }
  spec.exists = true;
  spec.private = !!info.data.private;
  spec.default_branch = info.data.default_branch || 'main';
  spec.html_url = info.data.html_url;
  const sec = await ghSoft(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/secrets?per_page=100`);
  if (sec.ok && sec.data && Array.isArray(sec.data.secrets)) {
    spec.secrets = sec.data.secrets.map(s => s.name);
    spec.missing_required = SECRETS_REQUIRED.filter(n => !spec.secrets.includes(n));
    spec.missing_optional = SECRETS_OPTIONAL.filter(n => !spec.secrets.includes(n));
  } else if (sec.status === 401) { spec.error = 'token'; return spec; }
  const perms = await ghSoft(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/permissions`);
  if (perms.ok && perms.data) spec.actions_enabled = !!perms.data.enabled;
  const wfperms = await ghSoft(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/permissions/workflow`);
  if (wfperms.ok && wfperms.data) spec.workflow_permissions = wfperms.data.default_workflow_permissions || null;
  spec.ready = spec.exists && spec.missing_required.length === 0;
  return spec;
}

async function configureRepo(ctx) {
  const notes = [];
  const a = await ghSoft(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/actions/permissions`, { enabled: true, allowed_actions: 'all' });
  notes.push(a.ok ? 'Actions diaktifkan' : `Actions: gagal (${a.status})`);
  const w = await ghSoft(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/actions/permissions/workflow`, { default_workflow_permissions: 'write', can_approve_pull_request_reviews: false });
  notes.push(w.ok ? 'izin tulis GITHUB_TOKEN diset' : `izin tulis: gagal (${w.status})`);
  return notes;
}

/* ------------------------------------------------------------- handler ----- */
module.exports = async (req, res) => {
  const send = (code, obj, type = 'application/json', headers = {}) => {
    const body = type === 'application/json' ? JSON.stringify(obj) : obj;
    res.writeHead(code, Object.assign({ 'Content-Type': type + '; charset=utf-8', 'Cache-Control': 'no-store' }, SECURITY_HEADERS, headers));
    res.end(body);
  };
  const redirect = (loc, cookies) => {
    const h = Object.assign({ Location: loc, 'Cache-Control': 'no-store' }, SECURITY_HEADERS);
    if (cookies && cookies.length) h['Set-Cookie'] = cookies;
    res.writeHead(302, h);
    res.end();
  };
  const origin = (() => {
    const proto = (req.headers['x-forwarded-proto'] || 'https').split(',')[0];
    const host = req.headers['x-forwarded-host'] || req.headers.host || 'localhost';
    return `${proto}://${host}`;
  })();

  try {
    const url = new URL(req.url, 'http://x');
    const p = url.pathname.replace(/^\/api\/?/, '/');

    // ---- halaman: selalu boleh (berisi layar login tanpa data sensitif) ----
    if (p === '/' || p === '/index.html') {
      try {
        return send(200, fs.readFileSync(path.join(__dirname, '..', 'assets', 'index.html'), 'utf8'), 'text/html');
      } catch { return send(200, '<h1>XyRDP</h1>', 'text/html'); }
    }
    if (p === '/panduan' || p === '/guide') {
      try {
        return send(200, fs.readFileSync(path.join(__dirname, '..', 'assets', 'panduan.html'), 'utf8'), 'text/html');
      } catch { return send(404, '<h1>Panduan belum tersedia</h1>', 'text/html'); }
    }

    /* ============================ AUTH ==================================== */
    if (req.method === 'GET' && p === '/auth/status') {
      const ctx = makeCtx(req);
      return send(200, {
        oauth_ready: !!(ENV.oauth_id && ENV.oauth_secret && sessionSecretReady()),
        admin_login: adminConfigured(),
        admin_login_ready: adminLoginReady(),
        open_admin: false,
        turnstile_required: adminConfigured(),
        turnstile_site_key: ENV.turnstile_site_key,
        template: ENV.template,
        rdp_start_paused: RDP_START_PAUSED,
        pause_message: RDP_START_PAUSED ? RDP_PAUSE_MESSAGE : '',
        mode: ctx ? ctx.kind : null,
        login: ctx && ctx.kind === 'user' ? ctx.login : (ctx ? ENV.owner_login : null),
        repo: ctx ? `${ctx.owner}/${ctx.repo}` : null,
      });
    }

    if (req.method === 'GET' && p === '/auth/login') {
      if (!ENV.oauth_id || !ENV.oauth_secret || !sessionSecretReady()) return redirect('/?err=oauth_belum_dikonfigurasi');
      const state = b64u(crypto.randomBytes(16));
      const cb = `${origin}/api/auth/callback`;
      const loc = 'https://github.com/login/oauth/authorize'
        + `?client_id=${encodeURIComponent(ENV.oauth_id)}`
        + `&redirect_uri=${encodeURIComponent(cb)}`
        + `&scope=${encodeURIComponent('repo')}`
        + `&state=${state}&allow_signup=0`;
      return redirect(loc, [cookieHeader('ost', state, 900)]);
    }

    if (req.method === 'GET' && p === '/auth/callback') {
      const code = url.searchParams.get('code');
      const state = url.searchParams.get('state') || '';
      const cookies = readCookies(req);
      if (!code) return redirect('/?err=github_batal');
      if (!cookies.ost || cookies.ost !== state) return redirect('/?err=state_tidak_cocok');
      const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'User-Agent': 'XyRDP-vc' },
        body: JSON.stringify({ client_id: ENV.oauth_id, client_secret: ENV.oauth_secret, code, redirect_uri: `${origin}/api/auth/callback` }),
      });
      const tok = await tokenRes.json().catch(() => ({}));
      if (!tok.access_token) return redirect('/?err=' + encodeURIComponent(tok.error || 'token_github_gagal'));
      const meRes = await fetch(API + '/user', { headers: { 'User-Agent': 'XyRDP-vc', 'Authorization': `Bearer ${tok.access_token}`, 'X-GitHub-Api-Version': '2022-11-28' } });
      if (!meRes.ok) return redirect('/?err=profil_github_gagal');
      const me = await meRes.json();
      const payload = {
        t: tok.access_token, l: me.login, n: me.name || '', a: me.avatar_url || '',
        r: `${me.login}/${ENV.repo}`,
        e: Date.now() + SESSION_TTL_DAYS * 24 * 3600 * 1000,
      };
      return redirect('/', [cookieHeader('ghs', seal(payload), SESSION_TTL_DAYS * 24 * 3600), cookieHeader('ost', '', 0)]);
    }

    if (req.method === 'POST' && p === '/auth/logout') {
      res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Set-Cookie': [cookieHeader('ghs', '', 0), cookieHeader('sid', '', 0)] }, SECURITY_HEADERS));
      return res.end(JSON.stringify({ ok: true }));
    }

    // Login admin: email allowlist + kata sandi + verifikasi Turnstile wajib.
    if (req.method === 'POST' && p === '/login') {
      if (!adminLoginReady()) return send(503, { error: 'Login admin dikunci: konfigurasi kredensial, SESSION_SECRET, atau Cloudflare Turnstile belum lengkap.' });
      const rate = loginRate(req);
      if (rate.locked) return send(429, { error: 'Terlalu banyak percobaan login. Coba lagi setelah beberapa menit.' }, 'application/json', { 'Retry-After': String(rate.retry) });
      const body = await readBody(req, 16 * 1024);
      if (body.__too_large) return send(413, { error: 'Permintaan login terlalu besar.' });
      const human = await verifyTurnstile(String(body.turnstile || ''), req);
      if (!human.ok) {
        console.warn('[XyRDP] Admin login ditolak Turnstile:', human.reason);
        const failed = loginRate(req, true);
        if (failed.locked) return send(429, { error: 'Terlalu banyak percobaan login. Coba lagi setelah beberapa menit.' }, 'application/json', { 'Retry-After': String(failed.retry) });
        return send(403, { error: 'Verifikasi Cloudflare gagal atau kedaluwarsa. Selesaikan widget lagi, lalu coba masuk.' });
      }
      if (!credsOk(String(body.user || ''), String(body.pass || ''))) {
        console.warn('[XyRDP] Admin login ditolak: email/sandi tidak cocok.');
        const failed = loginRate(req, true);
        if (failed.locked) return send(429, { error: 'Terlalu banyak percobaan login. Coba lagi setelah beberapa menit.' }, 'application/json', { 'Retry-After': String(failed.retry) });
        return send(403, { error: 'Email admin atau kata sandi salah. Pastikan memakai email admin yang diizinkan dan periksa Caps Lock.' });
      }
      loginRate(req, false, true);
      const sid = seal({ k: 'admin', v: adminCredVersion(), e: Date.now() + ADMIN_TTL_SECONDS * 1000 });
      res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Set-Cookie': cookieHeader('sid', sid, ADMIN_TTL_SECONDS) }, SECURITY_HEADERS));
      return res.end(JSON.stringify({ ok: true }));
    }

    /* ============================ GATE ==================================== */
    const ctx = makeCtx(req);
    if (!ctx) return send(403, { error: 'unauthorized', need_login: true });

    /* ============================ /me ===================================== */
    if (req.method === 'GET' && p === '/me') {
      if (ctx.kind === 'admin') {
        const st = await ghSoft(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}`);
        return send(200, {
          mode: 'admin', login: ENV.owner_login, owner: ctx.owner, repo: ctx.repo,
          repo_url: `https://github.com/${ctx.owner}/${ctx.repo}`,
          repo_exists: st.ok, private: st.ok ? !!st.data.private : null,
          ready: st.ok, template: ENV.template, oauth_ready: !!(ENV.oauth_id && ENV.oauth_secret && sessionSecretReady()),
          secrets_url: `https://github.com/${ctx.owner}/${ctx.repo}/settings/secrets/actions`,
          rdp_start_paused: RDP_START_PAUSED,
        });
      }
      const st = await repoState(ctx);
      if (st.error === 'token') return send(401, { error: 'Token GitHub kamu sudah tidak berlaku — silakan login lagi.', need_login: true });
      return send(200, {
        mode: 'user', login: ctx.login, name: ctx.name, avatar: ctx.avatar,
        owner: ctx.owner, repo: ctx.repo, repo_url: `https://github.com/${ctx.owner}/${ctx.repo}`,
        repo_exists: st.exists, private: st.private, default_branch: st.default_branch,
        secrets: st.secrets, missing_required: st.missing_required, missing_optional: st.missing_optional,
        actions_enabled: st.actions_enabled, workflow_permissions: st.workflow_permissions,
        ready: !!st.ready, is_owner: !!ctx.is_owner,
        template: ENV.template,
        template_url: `https://github.com/${ENV.template}`,
        secrets_url: `https://github.com/${ctx.owner}/${ctx.repo}/settings/secrets/actions`,
        setup_note: st.error || '', rdp_start_paused: RDP_START_PAUSED,
      });
    }

    /* ============================ /setup ================================== */
    // Buat repo user dari template (kalau belum ada) + rapikan izin Actions.
    if (req.method === 'POST' && p === '/setup') {
      if (RDP_START_PAUSED) return send(423, { error: RDP_PAUSE_MESSAGE, paused: true });
      if (ctx.kind === 'admin') return send(400, { error: 'Mode admin: repo sudah diatur lewat env Vercel.' });
      const body = await readBody(req);
      const name = String(body.name || ENV.repo).replace(/[^A-Za-z0-9._-]/g, '').slice(0, 90) || ENV.repo;
      const isPrivate = !!body.private;
      const notes = [];
      let st = await repoState(ctx);
      if (st.error === 'token') return send(401, { error: 'Token GitHub kamu sudah tidak berlaku — login lagi.', need_login: true });
      if (!st.exists) {
        const [tplOwner, tplRepo] = ENV.template.split('/');
        const gen = await ghSoft(ctx.token, 'POST', `/repos/${tplOwner}/${tplRepo}/generate`, {
          owner: ctx.login, name, description: 'Sesi RDP Windows (XyRDP) — otomatis dari template',
          include_all_branches: false, private: isPrivate,
        });
        if (!gen.ok) {
          return send(gen.status === 422 ? 422 : 500, {
            error: gen.status === 422
              ? `Tidak bisa membuat repo "${ctx.login}/${name}" — kemungkinan nama itu sudah dipakai di akunmu (atau invalid). Ganti nama lalu coba lagi.`
              : `Gagal membuat repo dari template: ${gen.error}`,
          });
        }
        notes.push(`Repo dibuat: ${ctx.login}/${name} (dari template ${ENV.template})`);
        if (name !== ctx.repo) {
          // nama repo beda dari default → sesi ikut pindah supaya nyambung
          ctx.repo = name;
          const payload = {
            t: ctx.token, l: ctx.login, n: ctx.name || '', a: ctx.avatar || '',
            r: `${ctx.login}/${name}`, e: Date.now() + SESSION_TTL_DAYS * 24 * 3600 * 1000,
          };
          res.setHeader('Set-Cookie', cookieHeader('ghs', seal(payload), SESSION_TTL_DAYS * 24 * 3600));
          notes.push(`Sesi dipindah ke ${ctx.login}/${name}`);
        }
      }
      // --- Web tidak ikut ke fork (cuma repo script) ---
      if (st && !st.exists) {
        try {
          const webFiles = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/web?ref=${ctx.branch || ENV.branch}`).catch(()=>null);
          const vercelFiles = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/deploy?ref=${ctx.branch || ENV.branch}`).catch(()=>null);
          // delete web folder content (best-effort, tidak gagalkan setup)
          const toDelete = [];
          if (Array.isArray(webFiles)) toDelete.push(...webFiles.map(f=>f.path));
          if (Array.isArray(vercelFiles)) toDelete.push(...vercelFiles.filter(f=>f.name==='vercel').map(f=>f.path));
          for (const fp of toDelete.slice(0,20)) {
            try {
              const cur = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${fp}?ref=${ctx.branch || ENV.branch}`);
              if (cur && cur.sha) {
                await gh(ctx.token, 'DELETE', `/repos/${ctx.owner}/${ctx.repo}/contents/${fp}`, { message: 'chore: hapus web dari fork (credit: KallAncrit)', sha: cur.sha, branch: ctx.branch || ENV.branch });
                notes.push(`web/${fp} dihapus dari fork`);
              }
            } catch(e){ /* ignore */ }
          }
          // also try to delete single web files if listing failed
        } catch(e){ console.warn('web cleanup fork failed', e.message); }
      }
      const cfgNotes = await configureRepo(ctx);
      const fresh = await repoState(ctx);
      return send(200, { ok: true, notes: notes.concat(cfgNotes), me: {
        owner: ctx.owner, repo: ctx.repo, repo_exists: fresh.exists, ready: !!fresh.ready,
        missing_required: fresh.missing_required, secrets: fresh.secrets,
        actions_enabled: fresh.actions_enabled, workflow_permissions: fresh.workflow_permissions,
      } });
    }

    /* ============================ /config ================================= */
    if (req.method === 'GET' && p === '/config') {
      const base = {
        owner: ctx.owner, repo: ctx.repo, workflow: ENV.workflow, rdp_user: ctx.rdp_user, rdp_port: 3389,
        mode: ctx.kind, login: ctx.login, template: ENV.template,
        repo_url: `https://github.com/${ctx.owner}/${ctx.repo}`,
        oauth_ready: !!(ENV.oauth_id && ENV.oauth_secret && sessionSecretReady()),
        rdp_start_paused: RDP_START_PAUSED,
        password_from_secret: ctx.kind === 'user',
      };
      if (ctx.kind === 'admin') return send(200, Object.assign(base, { rdp_password: ctx.rdp_password }));
      const st = await repoState(ctx);
      base.secrets_url = `https://github.com/${ctx.owner}/${ctx.repo}/settings/secrets/actions`;
      base.rdp_password = '';
      base.repo_exists = st.exists;
      base.missing_required = st.missing_required;
      base.ready = !!st.ready;
      return send(200, base);
    }

    /* ============================ /status ================================= */
    if (req.method === 'GET' && p === '/status') {
      const [file, run] = await Promise.all([fetchStatusFile(ctx), activeRun(ctx).catch(() => null)]);
      let session = file;
      if ((!session || !session.active) && run && (run.status === 'in_progress' || run.status === 'queued')) {
        try {
          const txt = await readLog(ctx, run.id);
          const mRd = txt.match(/RUSTDESK ID\s*:\s*([0-9][0-9\s]{5,14})/);
          const mTun = txt.match(/TUNNEL\s*:\s*([A-Za-z0-9.\-]+):(\d+)/);
          if (mRd || mTun) {
            const rdId = mRd ? mRd[1].replace(/\s+/g, '') : '';
            session = {
              active: true,
              rdp_port: 3389, rdp_user: ctx.rdp_user,
              started_at: run.run_started_at || run.created_at,
              expires_at: new Date(Date.parse(run.run_started_at || run.created_at) + 360 * 60000).toISOString(),
              akses: {
                mode: 'keduanya',
                rustdesk: { status: rdId ? 'ok' : 'pending', id: rdId, server: 'server publik bawaan' },
                tunnel: {
                  status: mTun ? 'ok' : 'pending', provider: '', host: mTun ? mTun[1] : '',
                  port: mTun ? Number(mTun[2]) : 0, address: mTun ? `${mTun[1]}:${mTun[2]}` : '',
                },
              },
              source: 'log',
            };
          }
        } catch { /* log belum siap */ }
      }
      return send(200, {
        session,
        repo: `${ctx.owner}/${ctx.repo}`,
        run: run ? { id: run.id, status: run.status, conclusion: run.conclusion, created_at: run.run_started_at || run.created_at, html_url: run.html_url } : null,
      });
    }

    /* ============================ /start ================================== */
    if (req.method === 'POST' && p === '/start') {
      if (RDP_START_PAUSED) return send(423, { error: RDP_PAUSE_MESSAGE, paused: true });
      if (ctx.kind === 'user') {
        const st = await repoState(ctx);
        if (st.error === 'token') return send(401, { error: 'Token GitHub kamu sudah tidak berlaku — login lagi.', need_login: true });
        if (!st.exists) return send(400, { error: `Repo ${ctx.owner}/${ctx.repo} belum ada. Buka panel "Repo kamu" → Tombol "BUAT REPO DARI TEMPLATE".` });
        if (st.missing_required.length) return send(400, { error: `Secret repo kamu belum lengkap: ${st.missing_required.join(', ')}. Isi dulu di ${ctx.owner}/${ctx.repo} → Settings → Secrets and variables → Actions.` });
      }
      const body = await readBody(req);
      const rdpUser = normalizeRdpUser(body.rdp_user || 'xyadmin');
      if (!rdpUser) return send(400, { error: 'Username RDP harus 3–20 karakter: huruf/angka, lalu huruf, angka, _ atau -. Hindari nama akun bawaan Windows.' });
      const inputs = {
        durasi_menit: String(body.durasi || '360'),
        hostname: String(body.hostname || 'xyrdp').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 30) || 'xyrdp',
        rdp_user: rdpUser,
        akses: ['keduanya', 'tailscale', 'semua', 'rustdesk', 'tunnel'].includes(String(body.akses)) ? String(body.akses) : 'tailscale',
        tunnel_provider: ['otomatis', 'bore', 'ngrok'].includes(String(body.tunnel_provider)) ? String(body.tunnel_provider) : 'otomatis',
        win10: (body.win10 === 'tidak' ? 'tidak' : 'ya'),
        grafis: (body.grafis === 'tidak' ? 'tidak' : 'software'),
      };
      await gh(ctx.token, 'POST', `/repos/${ctx.owner}/${ctx.repo}/actions/workflows/${ENV.workflow}/dispatches`, { ref: ctx.branch || ENV.branch, inputs });
      return send(200, { ok: true, inputs, repo: `${ctx.owner}/${ctx.repo}` });
    }

    /* ============================ /stop =================================== */
    if (req.method === 'POST' && p === '/stop') {
      const body = await readBody(req);
      let runId = body.run_id;
      if (!runId) {
        const run = await activeRun(ctx);
        if (!run) return send(400, { error: 'tidak ada run untuk di-stop' });
        runId = run.id;
      }
      await gh(ctx.token, 'POST', `/repos/${ctx.owner}/${ctx.repo}/actions/runs/${runId}/cancel`, {});
      return send(200, { ok: true, run_id: runId });
    }

    /* ============================ /logs =================================== */
    if (req.method === 'GET' && p === '/logs') {
      let runId = url.searchParams.get('run_id');
      if (!runId) {
        const run = await activeRun(ctx);
        if (!run) return send(400, { error: 'belum ada run' });
        runId = run.id;
      }
      const txt = await readLog(ctx, Number(runId));
      const lines = txt.split('\n');
      return send(200, { run_id: runId, total_lines: lines.length, log: lines.slice(-600).join('\n') });
    }

    /* ============================ /extras ================================= */
    if (req.method === 'GET' && p === '/extras') {
      const { json } = await readRepoFile(ctx, EXTRAS_PATH);
      const cfg = Object.assign({}, EXTRAS_DEFAULTS, json || {});
      return send(200, extrasResponse(ctx, cfg, !!(json && json.wallpaper_file)));
    }
    if (req.method === 'POST' && p === '/extras') {
      if (RDP_START_PAUSED) return send(423, { error: RDP_PAUSE_MESSAGE, paused: true });
      const body = await readBody(req);
      const { json: cur, sha } = await readRepoFile(ctx, EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cur || {});
      for (const k of ['lightshot', 'translucent', 'wallpaper', 'xydesk_host', 'win10_look', 'win10_badge', 'win10_wallpaper', 'dark_theme', 'lightweight_mode', 'vscode', 'notepadpp']) {
        if (k in body) next[k] = !!body[k];
      }
      if ('rdp_user' in body) {
        const rdpUser = normalizeRdpUser(body.rdp_user || 'xyadmin');
        if (!rdpUser) return send(400, { error: 'Username RDP harus 3–20 karakter: huruf/angka, lalu huruf, angka, _ atau -. Hindari nama akun bawaan Windows.' });
        next.rdp_user = rdpUser;
      }
      if (body.translucent_mode) {
        const m = String(body.translucent_mode).toLowerCase();
        if (['normal', 'opaque', 'clear', 'blur', 'acrylic'].includes(m)) next.translucent_mode = m;
      }
      const content = Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64');
      await gh(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/contents/${EXTRAS_PATH}`,
        { message: 'XyRDP: update konfigurasi ekstra (via dashboard)', content, branch: ctx.branch || ENV.branch, ...(sha ? { sha } : {}) });
      return send(200, { ok: true, config: next });
    }

    /* ============================ /wallpaper ============================== */
    if (req.method === 'POST' && p === '/wallpaper') {
      if (RDP_START_PAUSED) return send(423, { error: RDP_PAUSE_MESSAGE, paused: true });
      const body = await readBody(req);
      const m = /^data:image\/(png|jpe?g|bmp);base64,([A-Za-z0-9+/=\s]+)$/.exec(String(body.image || ''));
      if (!m) return send(400, { error: 'Format gambar tidak didukung (jpg/png/bmp)' });
      const buf = Buffer.from(m[2].replace(/\s+/g, ''), 'base64');
      if (buf.length > 3 * 1024 * 1024) return send(400, { error: 'Ukuran gambar maksimal 3 MB (dashboard mengecilkan otomatis)' });
      const ext = imageInfo(buf);
      if (!ext) return send(400, { error: 'File bukan gambar jpg/png/bmp yang valid' });
      const br = ctx.branch || ENV.branch;
      const target = `assets/wallpaper.${ext}`;
      // hapus wallpaper lama dengan ekstensi berbeda supaya tidak dobel
      try {
        const list = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/assets?ref=${br}`);
        if (Array.isArray(list)) {
          for (const f of list) {
            if (WALLPAPER_RE.test(f.name) && f.name !== `wallpaper.${ext}`) {
              await gh(ctx.token, 'DELETE', `/repos/${ctx.owner}/${ctx.repo}/contents/${f.path}`,
                { message: `XyRDP: hapus ${f.name} (diganti wallpaper baru)`, sha: f.sha, branch: br });
            }
          }
        }
      } catch { /* abaikan */ }
      let curSha = null;
      try { const cur = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${target}?ref=${br}`); curSha = cur && cur.sha; } catch { /* file baru */ }
      await gh(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/contents/${target}`, {
        message: `XyRDP: wallpaper baru (${Math.round(buf.length / 1024)} KB, via dashboard)`,
        content: buf.toString('base64'), branch: br, ...(curSha ? { sha: curSha } : {}),
      });
      const { json: cfgJson, sha: cfgSha } = await readRepoFile(ctx, EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cfgJson || {}, { wallpaper: true, wallpaper_file: `wallpaper.${ext}` });
      await gh(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/contents/${EXTRAS_PATH}`, {
        message: 'XyRDP: aktifkan wallpaper baru (via dashboard)',
        content: Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64'), branch: br, ...(cfgSha ? { sha: cfgSha } : {}),
      });
      return send(200, { ok: true, file: `wallpaper.${ext}`, size_kb: Math.round(buf.length / 1024) });
    }

    /* ============================ /repo — Folder browser (scripts repo) ================ */
    if (p.startsWith('/repo/')) {
      const sub = p.replace('/repo','');
      if (req.method === 'GET' && sub === '/contents') {
        const reqPath = String(url.searchParams.get('path') || '').replace(/^\/+/, '').replace(/\.\./g,'');
        try {
          const data = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${reqPath}?ref=${ctx.branch || ENV.branch}`);
          return send(200, { path: reqPath, data });
        } catch(e){ return send(e.status||500, { error: e.message }); }
      }
      if (req.method === 'GET' && sub === '/file') {
        const reqPath = String(url.searchParams.get('path') || '').replace(/^\/+/, '');
        try {
          const data = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${reqPath}?ref=${ctx.branch || ENV.branch}`);
          if (data && data.content) {
            const text = Buffer.from(data.content, 'base64').toString('utf8');
            return send(200, { path: reqPath, sha: data.sha, content: text, size: data.size });
          }
          return send(404, { error: 'bukan file' });
        } catch(e){ return send(e.status||500, { error: e.message }); }
      }
      if (req.method === 'PUT' && sub === '/file') {
        const body = await readBody(req, 512*1024);
        const reqPath = String(body.path || '').replace(/^\/+/, '');
        const content = String(body.content||'');
        const message = String(body.message||`update ${reqPath} via dash (credit: KallAncrit)`);
        if (!reqPath) return send(400, { error: 'path kosong' });
        try {
          let sha = body.sha;
          if (!sha) {
            try { const cur = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/contents/${reqPath}?ref=${ctx.branch || ENV.branch}`); sha = cur.sha; } catch{}
          }
          const b64 = Buffer.from(content, 'utf8').toString('base64');
          const putBody = { message, content: b64, branch: ctx.branch || ENV.branch };
          if (sha) putBody.sha = sha;
          const res = await gh(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/contents/${reqPath}`, putBody);
          return send(200, { ok: true, path: reqPath, commit: res.commit && res.commit.sha });
        } catch(e){ return send(e.status||500, { error: e.message }); }
      }
      return send(404, { error: 'repo endpoint tidak dikenal' });
    }

    /* ============================ /secrets — set via dashboard (flexibel per akun) ======= */
    if (req.method === 'GET' && p === '/secrets') {
      const st = await repoState(ctx);
      if (st.error === 'token') return send(401, { error: 'Token GitHub tidak valid — login lagi.', need_login: true });
      return send(200, {
        owner: ctx.owner, repo: ctx.repo,
        secrets: st.secrets,
        missing_required: st.missing_required,
        missing_optional: st.missing_optional,
        ready: !!st.ready,
        required: SECRETS_REQUIRED,
        optional: SECRETS_OPTIONAL,
      });
    }
    if (req.method === 'POST' && p === '/secrets') {
      if (RDP_START_PAUSED) return send(423, { error: RDP_PAUSE_MESSAGE, paused: true });
      const body = await readBody(req, 64 * 1024);
      if (body.__too_large) return send(413, { error: 'Payload terlalu besar' });
      // Validasi RDP_PASSWORD minimal 8 char jika diisi
      const toSet = {};
      for (const name of [...SECRETS_REQUIRED, ...SECRETS_OPTIONAL]) {
        if (name in body) {
          const v = String(body[name] || '').trim();
          if (v) toSet[name] = v;
          else if (SECRETS_REQUIRED.includes(name) && (body[name] !== undefined)) {
            // jika user kosongkan required, jangan hapus — kasih error
            return send(400, { error: `${name} tidak boleh kosong` });
          }
        }
      }
      if (!Object.keys(toSet).length) return send(400, { error: 'Tidak ada secret yang diisi' });
      if ('RDP_PASSWORD' in toSet && toSet.RDP_PASSWORD.length < 8) {
        return send(400, { error: 'RDP_PASSWORD minimal 8 karakter' });
      }
      // butuh kunci publik repo
      let pub;
      try {
        pub = await gh(ctx.token, 'GET', `/repos/${ctx.owner}/${ctx.repo}/actions/secrets/public-key`);
      } catch (e) {
        return send(e.status === 404 ? 400 : 500, { error: `Gagal ambil public-key repo: ${e.message}` });
      }
      if (!sodium) {
        try { sodium = require('libsodium-wrappers'); } catch(e) { return send(500, { error: 'libsodium belum terinstall di server' }); }
      }
      await sodium.ready;
      const results = [];
      for (const [name, value] of Object.entries(toSet)) {
        try {
          const publicKey = sodium.from_base64(pub.key, sodium.base64_variants.ORIGINAL);
          const encrypted = sodium.crypto_box_seal(sodium.from_string(value), publicKey);
          const encrypted_value = sodium.to_base64(encrypted, sodium.base64_variants.ORIGINAL);
          await gh(ctx.token, 'PUT', `/repos/${ctx.owner}/${ctx.repo}/actions/secrets/${name}`, {
            encrypted_value, key_id: pub.key_id
          });
          results.push({ name, ok: true });
        } catch (e) {
          results.push({ name, ok: false, error: e.message });
        }
      }
      const failed = results.filter(r => !r.ok);
      if (failed.length) return send(500, { error: `Sebagian gagal: ${failed.map(f=>f.name+':'+f.error).join(', ')}`, results });
      const fresh = await repoState(ctx);
      return send(200, { ok: true, results, secrets: fresh.secrets, missing_required: fresh.missing_required, ready: !!fresh.ready });
    }

    return send(404, { error: 'not found' });
  } catch (e) {
    if (e && e.status === 401) return send(401, { error: 'Token GitHub tidak valid / kedaluwarsa — silakan login lagi.', need_login: true });
    return send(500, { error: String((e && e.message) || e) });
  }
};
