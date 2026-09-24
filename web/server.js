/* ============================================================================
 * XyRDP Dashboard — server.js (tanpa dependency, Node >= 18)
 * Menjalankan & memantau workflow "XyRDP" di GitHub Actions lewat REST API.
 * Password RDP disimpan LOKAL di config.json — tidak pernah ke repo publik.
 * Jalankan:  node server.js   → http://localhost:4173
 * ==========================================================================*/
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const { token, owner, repo, workflow = 'rdp-6h.yml', branch = 'main', port = 4173 } = CFG;
const STATUS_RAW = `https://raw.githubusercontent.com/${owner}/${repo}/status/rdp-status.json`;
const API = 'https://api.github.com';
const UA = { 'User-Agent': 'XyRDP-dash', 'Authorization': `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' };

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
  if (Date.now() - statusCache.at < 8000) return statusCache.data;
  let data = null;
  try {
    const r = await fetch(STATUS_RAW + `?t=${Math.floor(Date.now() / 60000)}`);
    if (r.ok) data = JSON.parse(await r.text());
  } catch { /* raw belum tersedia */ }
  if (!data) {
    // fallback: baca lewat API (bypass cache raw)
    try {
      const c = await gh('GET', `/repos/${owner}/${repo}/contents/rdp-status.json?ref=status`);
      if (c && c.content) data = JSON.parse(Buffer.from(c.content, 'base64').toString('utf8'));
    } catch { /* branch status belum ada */ }
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
      let runView = null;
      if (run) {
        runView = {
          id: run.id, status: run.status, conclusion: run.conclusion,
          created_at: run.run_started_at || run.created_at, html_url: run.html_url,
        };
      }
      return send(200, { session: file, run: runView });
    }

    if (req.method === 'POST' && url.pathname === '/api/start') {
      let body = '';
      req.on('data', c => body += c);
      await new Promise(r => req.on('end', r));
      const p = JSON.parse(body || '{}');
      const inputs = {
        durasi_menit: String(p.durasi || '360'),
        ts_hostname: String(p.hostname || 'xyrdp').replace(/[^a-zA-Z0-9-]/g, '').slice(0, 30) || 'xyrdp',
        exit_node: String(p.exit_node || ''),
        aman_google: p.aman_google === false ? 'false' : 'true',
        mati_defender: p.mati_defender === false ? 'false' : 'true',
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

    return send(404, { error: 'not found' });
  } catch (e) {
    return send(500, { error: String(e.message || e) });
  }
}

http.createServer(handle).listen(port, '0.0.0.0', () =>
  console.log(`XyRDP dashboard: http://localhost:${port}  (repo: ${owner}/${repo})`));
