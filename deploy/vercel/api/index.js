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
  if (Date.now() - statusCache.at < 8000) return statusCache.data;
  let data = null;
  try {
    const r = await fetch(STATUS_RAW + `?t=${Math.floor(Date.now() / 60000)}`);
    if (r.ok) data = JSON.parse(await r.text());
  } catch {}
  if (!data) {
    try {
      const c = await gh('GET', `/repos/${CFG.owner}/${CFG.repo}/contents/rdp-status.json?ref=status`);
      if (c && c.content) data = JSON.parse(Buffer.from(c.content, 'base64').toString('utf8'));
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
          const mIp = txt.match(/TAILNET IP\s*:\s*(100\.\d+\.\d+\.\d+)/);
          const mDns = txt.match(/MAGICDNS\s*:\s*(\S+)/);
          const mDur = (txt.match(/Durasi sesi\s*:\s*(\d+) menit/) || [])[1];
          if (mIp) {
            session = {
              active: true, tailscale_ip: mIp[1], tailscale_dns: mDns ? mDns[1] : '',
              rdp_port: 3389, rdp_user: CFG.rdp_user,
              started_at: run.run_started_at || run.created_at,
              expires_at: new Date(Date.parse(run.run_started_at || run.created_at) + (+mDur || 360) * 60000).toISOString(),
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
        ts_hostname: String(body.hostname || 'xyrdp').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 30) || 'xyrdp',
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
    return send(404, { error: 'not found' });
  } catch (e) {
    return send(500, { error: String(e.message || e) });
  }
};
