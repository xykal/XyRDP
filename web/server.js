/* ============================================================================
 * RdpFree Dashboard — server.js (tanpa dependency, Node >= 18)
 * Menjalankan & memantau workflow "RdpFree" di GitHub Actions lewat REST API.
 * Password RDP disimpan LOKAL di config.json — tidak pernah ke repo publik.
 * Jalankan:  node server.js   → http://localhost:4173
 * ==========================================================================*/
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const { token, owner, repo, workflow = 'rdp-6h.yml', branch = 'main', port = 4173 } = CFG;
// Token GitHub pada config.json tidak boleh terekspos ke jaringan lokal.
const host = process.env.HOST || '127.0.0.1';
const STATUS_RAW = `https://raw.githubusercontent.com/${owner}/${repo}/status/rdp-status.json`;
const API = 'https://api.github.com';
const UA = { 'User-Agent': 'RdpFree-dash', 'Authorization': `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' };

let statusCache = { at: 0, data: null };

async function gh(method, apiPath, body) {
  const res = await fetch(API + apiPath, {
    method,
    headers: { ...UA, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    redirect: 'follow',
  });
  if (res.status === 204) return null;
  const text = await res.text();
  if (!res.ok) throw new Error(`GitHub API ${res.status} ${apiPath}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

async function fetchStatusFile() {
  if (Date.now() - statusCache.at < 5000) return statusCache.data;
  let data = null;
  // Contents API DULU: selalu segar (tanpa cache CDN). Ini penting karena alamat
  // tunnel berganti tiap sesi — kalau dashboard menyajikan alamat lama, klien di
  // HP akan kena "koneksi ditolak/ditutup" (temuan 3 Okt: 3 sesi beruntun gagal
  // karena alamat yang dipakai bukan alamat sesi yang sedang jalan).
  try {
    const c = await gh('GET', `/repos/${owner}/${repo}/contents/rdp-status.json?ref=status&t=${Date.now()}`);
    if (c && c.content) data = JSON.parse(Buffer.from(c.content, 'base64').toString('utf8'));
  } catch { /* branch status belum ada / API sedang dibatasi */ }
  if (!data) {
    try {
      const r = await fetch(STATUS_RAW + `?t=${Date.now()}`, { cache: 'no-store' });
      if (r.ok) data = JSON.parse(await r.text());
    } catch { /* raw belum tersedia */ }
  }
  statusCache = { at: Date.now(), data };
  return data;
}

// ---- unzip kecil murni JS buat log Actions (format zip) ----
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
  throw new Error('bukan file zip');
}

async function activeRun() {
  const runs = await gh('GET', `/repos/${owner}/${repo}/actions/workflows/${workflow}/runs?per_page=5`);
  const list = runs && runs.workflow_runs ? runs.workflow_runs : [];
  return list[0] || null;
}

async function readLog(runId) {
  const jobs = await gh('GET', `/repos/${owner}/${repo}/actions/runs/${runId}/jobs`);
  const job = jobs && jobs.jobs ? jobs.jobs[0] : null;
  if (!job) return '';
  const res = await fetch(`${API}/repos/${owner}/${repo}/actions/jobs/${job.id}/logs`, { headers: UA, redirect: 'follow' });
  if (!res.ok) throw new Error('log ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  const ct = (res.headers.get('content-type') || '').toLowerCase();
  if (ct.includes('zip') || (buf.length > 4 && buf.readUInt32LE(0) === 0x04034b50)) {
    const entries = unzipEntries(buf).sort((a, b) => a.name.localeCompare(b.name));
    return entries.map(e => e.txt).join('\n');
  }
  return buf.toString('utf8'); // GitHub kini memberi job log sebagai text/plain
}

// ---- konfigurasi ekstra (assets/rdp-extras.json di repo) + wallpaper ----
const EXTRAS_PATH = 'assets/rdp-extras.json';
const EXTRAS_DEFAULTS = { lightshot: true, translucent: true, translucent_mode: 'clear', wallpaper: true, wallpaper_file: 'wallpaper.jpg', win10_look: true, win10_badge: true, win10_wallpaper: true, xydesk_host: true };
const WALLPAPER_RE = /^wallpaper\.(jpg|jpeg|png|bmp)$/i;

async function readRepoFile(path) {
  try {
    const c = await gh('GET', `/repos/${owner}/${repo}/contents/${path}?ref=${branch}`);
    if (c && c.content) return { json: JSON.parse(Buffer.from(c.content, 'base64').toString('utf8')), sha: c.sha };
  } catch { /* belum ada */ }
  return { json: null, sha: null };
}
function extrasResponse(cfg, fileExists) {
  const wf = String(cfg.wallpaper_file || 'wallpaper.jpg').replace(/[^a-zA-Z0-9._-]/g, '');
  return {
    config: cfg,
    wallpaper_exists: fileExists,
    wallpaper_url: `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/assets/${wf}?t=${Date.now()}`,
  };
}
function imageInfo(buf) {
  if (buf.length >= 3 && buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'jpg';
  if (buf.length >= 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4E && buf[3] === 0x47) return 'png';
  if (buf.length >= 2 && buf[0] === 0x42 && buf[1] === 0x4D) return 'bmp';
  return null;
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const send = (code, obj, type = 'application/json') => {
    const body = type === 'application/json' ? JSON.stringify(obj) : obj;
    res.writeHead(code, { 'Content-Type': type + '; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(body);
  };
  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      return send(200, fs.readFileSync(path.join(__dirname, 'public', 'index.html')), 'text/html');
    }
    if (req.method === 'GET' && (url.pathname === '/panduan' || url.pathname === '/guide')) {
      return send(200, fs.readFileSync(path.join(__dirname, 'public', 'panduan.html')), 'text/html');
    }

    if (req.method === 'GET' && url.pathname === '/api/auth/status') {
      return send(200, { oauth_ready: false, admin_login: false, open_admin: true, mode: 'admin', login: owner, repo: `${owner}/${repo}`, local_mode: true });
    }
    if (req.method === 'GET' && url.pathname === '/api/me') {
      return send(200, { mode: 'admin', login: owner, owner, repo, repo_url: `https://github.com/${owner}/${repo}`, repo_exists: true, ready: true, local_mode: true });
    }
    if (req.method === 'POST' && url.pathname === '/api/auth/logout') {
      return send(200, { ok: true });
    }
    if (req.method === 'GET' && url.pathname === '/api/config') {
      return send(200, {
        owner, repo, workflow,
        rdp_user: CFG.rdp_user || 'xyadmin',
        rdp_password: CFG.rdp_password || '(set rdp_password di web/config.json)',
        rdp_port: 3389,
      });
    }

    if (req.method === 'GET' && url.pathname === '/api/status') {
      const [file, run] = await Promise.all([fetchStatusFile(), activeRun()]);
      let session = file;
      // fallback: status file belum ada → ekstrak IP dari log run aktif
      if ((!session || !session.active) && run && (run.status === 'in_progress' || run.status === 'queued')) {
        try {
          const txt = await readLog(run.id);
          const mRd = txt.match(/RUSTDESK ID\s*:\s*([0-9][0-9\s]{5,14})/);
          const mTun = txt.match(/TUNNEL\s*:\s*([A-Za-z0-9.\-]+):(\d+)/);
          if (mRd || mTun) {
            const rdId = mRd ? mRd[1].replace(/\s+/g, '') : '';
            session = {
              active: true,
              rdp_port: 3389, rdp_user: CFG.rdp_user || 'xyadmin',
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
        } catch { /* log belum tersedia */ }
      }
      let runView = null;
      if (run) {
        runView = {
          id: run.id, status: run.status, conclusion: run.conclusion,
          created_at: run.run_started_at || run.created_at, html_url: run.html_url,
        };
      }
      return send(200, { session, run: runView });
    }

    if (req.method === 'POST' && url.pathname === '/api/start') {
      let body = '';
      req.on('data', c => body += c);
      await new Promise(r => req.on('end', r));
      const p = JSON.parse(body || '{}');
      const inputs = {
        durasi_menit: String(p.durasi || '360'),
        hostname: String(p.hostname || 'xyrdp').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 30) || 'xyrdp',
        akses: ['keduanya', 'rustdesk', 'tunnel'].includes(String(p.akses)) ? String(p.akses) : 'keduanya',
        tunnel_provider: ['otomatis', 'bore', 'ngrok'].includes(String(p.tunnel_provider)) ? String(p.tunnel_provider) : 'otomatis',
        win10: (p.win10 === 'tidak' ? 'tidak' : 'ya'),
      };
      await gh('POST', `/repos/${owner}/${repo}/actions/workflows/${workflow}/dispatches`, { ref: branch, inputs });
      return send(200, { ok: true, inputs });
    }

    if (req.method === 'POST' && url.pathname === '/api/stop') {
      let body = '';
      req.on('data', c => body += c);
      await new Promise(r => req.on('end', r));
      const p = JSON.parse(body || '{}');
      let runId = p.run_id;
      if (!runId) {
        const run = await activeRun();
        if (!run) return send(400, { error: 'tidak ada run untuk di-stop' });
        runId = run.id;
      }
      await gh('POST', `/repos/${owner}/${repo}/actions/runs/${runId}/cancel`, {});
      return send(200, { ok: true, run_id: runId });
    }

    if (req.method === 'GET' && url.pathname === '/api/logs') {
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

    if (req.method === 'GET' && url.pathname === '/api/extras') {
      const { json } = await readRepoFile(EXTRAS_PATH);
      const cfg = Object.assign({}, EXTRAS_DEFAULTS, json || {});
      return send(200, extrasResponse(cfg, !!(json && json.wallpaper_file)));
    }

    if (req.method === 'POST' && url.pathname === '/api/extras') {
      let body = '';
      req.on('data', c => body += c);
      await new Promise(r => req.on('end', r));
      const p = JSON.parse(body || '{}');
      const { json: cur, sha } = await readRepoFile(EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cur || {});
      for (const k of ['lightshot', 'translucent', 'wallpaper', 'xydesk_host']) {
        if (k in p) next[k] = !!p[k];
      }
      for (const k of ['win10_look', 'win10_badge', 'win10_wallpaper']) {
        if (k in p) next[k] = !!p[k];
      }
      if (p.translucent_mode) {
        const m = String(p.translucent_mode).toLowerCase();
        if (['normal', 'opaque', 'clear', 'blur', 'acrylic'].includes(m)) next.translucent_mode = m;
      }
      const content = Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64');
      await gh('PUT', `/repos/${owner}/${repo}/contents/${EXTRAS_PATH}`,
        { message: 'RdpFree: update konfigurasi ekstra (via dashboard)', content, branch, ...(sha ? { sha } : {}) });
      return send(200, { ok: true, config: next });
    }

    if (req.method === 'POST' && url.pathname === '/api/wallpaper') {
      let body = '';
      req.on('data', c => body += c);
      await new Promise(r => req.on('end', r));
      const p = JSON.parse(body || '{}');
      const m = /^data:image\/(png|jpe?g|bmp);base64,([A-Za-z0-9+/=\s]+)$/.exec(String(p.image || ''));
      if (!m) return send(400, { error: 'Format gambar tidak didukung (jpg/png/bmp)' });
      const buf = Buffer.from(m[2].replace(/\s+/g, ''), 'base64');
      if (buf.length > 3 * 1024 * 1024) return send(400, { error: 'Ukuran gambar maksimal 3 MB (dashboard mengecilkan otomatis)' });
      const ext = imageInfo(buf);
      if (!ext) return send(400, { error: 'File bukan gambar jpg/png/bmp yang valid' });
      const target = `assets/wallpaper.${ext}`;
      // hapus wallpaper lama dengan ekstensi berbeda supaya tidak dobel
      try {
        const list = await gh('GET', `/repos/${owner}/${repo}/contents/assets?ref=${branch}`);
        if (Array.isArray(list)) {
          for (const f of list) {
            if (WALLPAPER_RE.test(f.name) && f.name !== `wallpaper.${ext}`) {
              await gh('DELETE', `/repos/${owner}/${repo}/contents/${f.path}`,
                { message: `RdpFree: hapus ${f.name} (diganti wallpaper baru)`, sha: f.sha, branch });
            }
          }
        }
      } catch { /* abaikan */ }
      let curSha = null;
      try { const cur = await gh('GET', `/repos/${owner}/${repo}/contents/${target}?ref=${branch}`); curSha = cur && cur.sha; } catch { /* file baru */ }
      await gh('PUT', `/repos/${owner}/${repo}/contents/${target}`, {
        message: `RdpFree: wallpaper baru (${Math.round(buf.length / 1024)} KB, via dashboard)`,
        content: buf.toString('base64'), branch, ...(curSha ? { sha: curSha } : {}),
      });
      const { json: cfgJson, sha: cfgSha } = await readRepoFile(EXTRAS_PATH);
      const next = Object.assign({}, EXTRAS_DEFAULTS, cfgJson || {}, { wallpaper: true, wallpaper_file: `wallpaper.${ext}` });
      await gh('PUT', `/repos/${owner}/${repo}/contents/${EXTRAS_PATH}`, {
        message: 'RdpFree: aktifkan wallpaper baru (via dashboard)',
        content: Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8').toString('base64'), branch, ...(cfgSha ? { sha: cfgSha } : {}),
      });
      return send(200, { ok: true, file: `wallpaper.${ext}`, size_kb: Math.round(buf.length / 1024) });
    }

    return send(404, { error: 'not found' });
  } catch (e) {
    return send(500, { error: String(e.message || e) });
  }
}

const displayHost = host === '0.0.0.0' ? 'localhost' : host;
http.createServer(handle).listen(port, host, () =>
  console.log(`RdpFree dashboard: http://${displayHost}:${port} (bound ${host}; repo: ${owner}/${repo})`));
