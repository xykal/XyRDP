/* ============================================================================
 * XyRDP Dashboard — Vercel catch-all function (Node, tanpa dependency)
 * Route: /api/*  (config, status, start, stop, logs)
 * Auth : Basic Auth via env AUTH_USER / AUTH_PASS (401 = browser minta login)
 * Config dibaca dari env vars Vercel, BUKAN file:
 *   GITHUB_TOKEN, GH_OWNER, GH_REPO, GH_WORKFLOW, GH_BRANCH, RDP_USER, RDP_PASSWORD
 * ==========================================================================*/
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const CFG = {
  token: process.env.GITHUB_TOKEN || '',
  owner: process.env.GH_OWNER || 'xykal',
  repo: process.env.GH_REPO || 'XyRDP',
  workflow: process.env.GH_WORKFLOW || 'rdp-6h.yml',
  branch: process.env.GH_BRANCH || 'main',
  rdp_user: process.env.RDP_USER || 'xyadmin',
  rdp_password: process.env.RDP_PASSWORD || '(set env RDP_PASSWORD di Vercel)',
};
const STATUS_RAW = `https://raw.githubusercontent.com/${CFG.owner}/${CFG.repo}/status/rdp-status.json`;
const API = 'https://api.github.com';

// ---- konfigurasi ekstra (assets/rdp-extras.json di repo) + wallpaper ----
const EXTRAS_PATH = 'assets/rdp-extras.json';
const EXTRAS_DEFAULTS = { lightshot: true, translucent: true, translucent_mode: 'clear', wallpaper: true, wallpaper_file: 'wallpaper.jpg', win10_look: true, win10_badge: true, win10_wallpaper: true, xydesk_host: true };
const WALLPAPER_RE = /^wallpaper\.(jpg|jpeg|png|bmp)$/i;

async function readRepoFile(path) {
  try {
    const c = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/contents/${path}?ref=${CFG.branch}`);
    if (c && c.content) return { json: JSON.parse(Buffer.from(c.content, 'base64').toString('utf8')), sha: c.sha };
  } catch { /* belum ada */ }
  return { json: null, sha: null };
}
function extrasResponse(cfg, fileExists) {
  const wf = String(cfg.wallpaper_file || 'wallpaper.jpg').replace(/[^a-zA-Z0-9._-]/g, '');
  return {
    config: cfg,
    wallpaper_exists: fileExists,
    wallpaper_url: `https://raw.githubusercontent.com/${CFG.owner}/${CFG.repo}/${CFG.branch}/assets/${wf}?t=${Date.now()}`,
  };
}
function imageInfo(buf) {
  if (buf.length >= 3 && buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'jpg';
  if (buf.length >= 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'png';
  if (buf.length >= 2 && buf[0] === 0x42 && buf[1] === 0x4D) return 'bmp';
  return null;
}

async function gh(method, apiPath, body) {
  const res = await fetch(API + apiPath, {
    method,
    headers: {
      'User-Agent': 'XyRDP-vc', 'Authorization': `Bearer ${CFG.token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    redirect: 'follow',
  });
  if (res.status === 204) return null;
  const text = await res.text();
  if (!res.ok) throw new Error(`GitHub API ${res.status} ${apiPath}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

let statusCache = { at: 0, data: null };
async function fetchStatusFile() {
  if (Date.now() - statusCache.at < 5000) return statusCache.data;
  let data = null;
  // Contents API dulu = selalu segar (alamat tunnel berganti tiap sesi; alamat
  // lama bikin klien HP kena "koneksi ditolak/ditutup").
  try {
    const c = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/contents/rdp-status.json?ref=status&t=${Date.now()}`);
    if (c && c.content) data = JSON.parse(Buffer.from(c.content, 'base64').toString('utf8'));
  } catch {}
  if (!data) {
    try {
      const r = await fetch(STATUS_RAW + `?t=${Date.now()}`, { cache: 'no-store' });
      if (r.ok) data = JSON.parse(await r.text());
    } catch {}
  }
  statusCache = { at: Date.now(), data };
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
        const clen = buf.readUInt16LE(off + 32);
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

async function activeRun() {
  const runs = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/actions/workflows/${CFG.workflow}/runs?per_page=5`);
  const list = runs && runs.workflow_runs ? runs.workflow_runs : [];
  return list[0] || null;
}

async function readLog(runId) {
  const jobs = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/actions/runs/${runId}/jobs`);
  const job = jobs && jobs.jobs ? jobs.jobs[0] : null;
  if (!job) return '';
  const res = await fetch(`${API}/repos/${CFG.owner}/${CFG.repo}/actions/jobs/${job.id}/logs`, {
    headers: { 'User-Agent': 'XyRDP-vc', 'Authorization': `Bearer ${CFG.token}` }, redirect: 'follow',
  });
  if (!res.ok) throw new Error('log ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  const ct = (res.headers.get('content-type') || '').toLowerCase();
  if (ct.includes('zip') || (buf.length > 4 && buf.readUInt32LE(0) === 0x04034b50)) {
    return unzipEntries(buf).sort((a, b) => a.name.localeCompare(b.name)).map(e => e.txt).join('\n');
  }
  return buf.toString('utf8');
}

function readBody(req) {
  return new Promise(resolve => {
    let b = '';
    req.on('data', c => b += c);
    req.on('end', () => { try { resolve(JSON.parse(b || '{}')); } catch { resolve({}); } });
  });
}

// ---- auth: cookie login (form custom, tanpa popup browser) + fallback header Basic ----
const crypto = require('crypto');
function sessionCookie() {
  return crypto.createHash('sha256')
    .update(((process.env.AUTH_USER) || '') + '|' + (process.env.AUTH_PASS || '') + '|xyrdp-sid')
    .digest('hex').slice(0, 48);
}
function credsOk(u, p) {
  return u === (process.env.AUTH_USER || '') && p === (process.env.AUTH_PASS || '');
}
function authOk(req) {
  if (!process.env.AUTH_PASS) return true;
  const m = (req.headers.cookie || '').match(/sid=([a-f0-9]{48})/);
  if (m && m[1] === sessionCookie()) return true;
  const h = req.headers.authorization || '';
  if (h.startsWith('Basic ')) {
    const [u, ...ps] = Buffer.from(h.slice(6), 'base64').toString('utf8').split(':');
    return credsOk(u, ps.join(':'));
  }
  return false;
}

module.exports = async (req, res) => {
  const send = (code, obj, type = 'application/json') => {
    const body = type === 'application/json' ? JSON.stringify(obj) : obj;
    res.writeHead(code, { 'Content-Type': type + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(body);
  };
  try {
    const url = new URL(req.url, 'http://x');
    const p = url.pathname.replace(/^\/api\/?/, '/');

    // halaman (berisi form login; tanpa data sensitif) selalu boleh diakses
    if (p === '/' || p === '/index.html') {
      try {
        return send(200, fs.readFileSync(path.join(__dirname, '..', 'assets', 'index.html')), 'text/html');
      } catch { return send(200, '<h1>XyRDP</h1>', 'text/html'); }
    }

    // endpoint login: verifikasi kredensial lalu set cookie
    if (req.method === 'POST' && p === '/login') {
      if (!process.env.AUTH_PASS) return send(200, { ok: true, note: 'auth tidak aktif' });
      const body = await readBody(req);
      if (!credsOk(String(body.user || ''), String(body.pass || '')))
        return send(403, { error: 'Kredensial salah' });
      res.setHeader('Set-Cookie',
        `sid=${sessionCookie()}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${7 * 24 * 3600}${process.env.VERCEL_ENV === 'production' ? '; Secure' : ''}`);
      return send(200, { ok: true });
    }

    if (!authOk(req)) return send(403, { error: 'unauthorized' });

    if (req.method === 'GET' && p === '/config') {
      return send(200, { owner: CFG.owner, repo: CFG.repo, workflow: CFG.workflow, rdp_user: CFG.rdp_user, rdp_password: CFG.rdp_password, rdp_port: 3389 });
    }
    if (req.method === 'GET' && p === '/status') {
      const [file, run] = await Promise.all([fetchStatusFile(), activeRun()]);
      let session = file;
      if ((!session || !session.active) && run && (run.status === 'in_progress' || run.status === 'queued')) {
        try {
          const txt = await readLog(run.id);
          const mRd = txt.match(/RUSTDESK ID\s*:\s*([0-9][0-9\s]{5,14})/);
          const mTun = txt.match(/TUNNEL\s*:\s*([A-Za-z0-9.\-]+):(\d+)/);
          if (mRd || mTun) {
            const rdId = mRd ? mRd[1].replace(/\s+/g, '') : '';
            session = {
              active: true,
              rdp_port: 3389, rdp_user: CFG.rdp_user,
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
        } catch {}
      }
      return send(200, { session, run: run ? { id: run.id, status: run.status, conclusion: run.conclusion, created_at: run.run_started_at || run.created_at, html_url: run.html_url } : null });
    }
    if (req.method === 'POST' && p === '/start') {
      const body = await readBody(req);
      const inputs = {
        durasi_menit: String(body.durasi || '360'),
        hostname: String(body.hostname || 'xyrdp').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 30) || 'xyrdp',
        akses: ['keduanya', 'tailscale', 'semua', 'rustdesk', 'tunnel'].includes(String(body.akses)) ? String(body.akses) : 'tailscale',
        tunnel_provider: ['otomatis', 'bore', 'ngrok'].includes(String(body.tunnel_provider)) ? String(body.tunnel_provider) : 'otomatis',
        win10: (body.win10 === 'tidak' ? 'tidak' : 'ya'),
        grafis: (body.grafis === 'tidak' ? 'tidak' : 'software'),
      };
      await gh('POST', `/repos/${CFG.owner}/${CFG.repo}/actions/workflows/${CFG.workflow}/dispatches`, { ref: CFG.branch, inputs });
      return send(200, { ok: true, inputs });
    }
    if (req.method === 'POST' && p === '/stop') {
      const body = await readBody(req);
      let runId = body.run_id;
      if (!runId) {
        const run = await activeRun();
        if (!run) return send(400, { error: 'tidak ada run untuk di-stop' });
        runId = run.id;
      }
      await gh('POST', `/repos/${CFG.owner}/${CFG.repo}/actions/runs/${runId}/cancel`, {});
      return send(200, { ok: true, run_id: runId });
    }
    if (req.method === 'GET' && p === '/logs') {
      let runId = url.searchParams.get('run_id');
      if (!runId) {
        const run = await activeRun();
        if (!run) return send(400, { error: 'belum ada run' });
        runId = run.id;
      }
      const txt = await readLog(Number(runId));
      const lines = txt.split('\n');
      return send(200, { run_id: runId, total_lines: lines.length, log: lines.slice(-600).join('\n') });
    }
    if (req.method === 'GET' && p === '/extras') {
      const { json } = await readRepoFile(EXTRAS_PATH);
      const cfg = Object.assign({}, EXTRAS_DEFAULTS, json || {});
      return send(200, extrasResponse(cfg, !!(json && json.wallpaper_file)));
    }
    if (req.method === 'POST' && p === '/extras') {
      const body = await readBody(req);
      const { json: cur, sha } = await readRepoFile(EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cur || {});
      for (const k of ['lightshot', 'translucent', 'wallpaper', 'xydesk_host', 'win10_look', 'win10_badge', 'win10_wallpaper']) {
        if (k in body) next[k] = !!body[k];
      }
      if (body.translucent_mode) {
        const m = String(body.translucent_mode).toLowerCase();
        if (['normal', 'opaque', 'clear', 'blur', 'acrylic'].includes(m)) next.translucent_mode = m;
      }
      const content = Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64');
      await gh('PUT', `/repos/${CFG.owner}/${CFG.repo}/contents/${EXTRAS_PATH}`,
        { message: 'XyRDP: update konfigurasi ekstra (via dashboard)', content, branch: CFG.branch, ...(sha ? { sha } : {}) });
      return send(200, { ok: true, config: next });
    }
    if (req.method === 'POST' && p === '/wallpaper') {
      const body = await readBody(req);
      const m = /^data:image\/(png|jpe?g|bmp);base64,([A-Za-z0-9+/=\s]+)$/.exec(String(body.image || ''));
      if (!m) return send(400, { error: 'Format gambar tidak didukung (jpg/png/bmp)' });
      const buf = Buffer.from(m[2].replace(/\s+/g, ''), 'base64');
      if (buf.length > 3 * 1024 * 1024) return send(400, { error: 'Ukuran gambar maksimal 3 MB (dashboard mengecilkan otomatis)' });
      const ext = imageInfo(buf);
      if (!ext) return send(400, { error: 'File bukan gambar jpg/png/bmp yang valid' });
      const target = `assets/wallpaper.${ext}`;
      // hapus wallpaper lama dengan ekstensi berbeda supaya tidak dobel
      try {
        const list = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/contents/assets?ref=${CFG.branch}`);
        if (Array.isArray(list)) {
          for (const f of list) {
            if (WALLPAPER_RE.test(f.name) && f.name !== `wallpaper.${ext}`) {
              await gh('DELETE', `/repos/${CFG.owner}/${CFG.repo}/contents/${f.path}`,
                { message: `XyRDP: hapus ${f.name} (diganti wallpaper baru)`, sha: f.sha, branch: CFG.branch });
            }
          }
        }
      } catch { /* abaikan */ }
      let curSha = null;
      try { const cur = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/contents/${target}?ref=${CFG.branch}`); curSha = cur && cur.sha; } catch { /* file baru */ }
      await gh('PUT', `/repos/${CFG.owner}/${CFG.repo}/contents/${target}`, {
        message: `XyRDP: wallpaper baru (${Math.round(buf.length / 1024)} KB, via dashboard)`,
        content: buf.toString('base64'), branch: CFG.branch, ...(curSha ? { sha: curSha } : {}),
      });
      const { json: cfgJson, sha: cfgSha } = await readRepoFile(EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cfgJson || {}, { wallpaper: true, wallpaper_file: `wallpaper.${ext}` });
      await gh('PUT', `/repos/${CFG.owner}/${CFG.repo}/contents/${EXTRAS_PATH}`, {
        message: 'XyRDP: aktifkan wallpaper baru (via dashboard)',
        content: Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64'), branch: CFG.branch, ...(cfgSha ? { sha: cfgSha } : {}),
      });
      return send(200, { ok: true, file: `wallpaper.${ext}`, size_kb: Math.round(buf.length / 1024) });
    }
    return send(404, { error: 'not found' });
  } catch (e) {
    return send(500, { error: String(e.message || e) });
  }
};
