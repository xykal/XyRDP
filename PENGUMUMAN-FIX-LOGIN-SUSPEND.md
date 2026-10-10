# PENGUMUMAN — Fix Login Tiap Refresh & Anti-Suspend (10 Okt 2026)

> **Update wajib untuk semua user fork.** Sync fork kamu sekarang — fix sudah di `main` (`d1f0603`).

## 1. Login tiap refresh — SUDAH FIX (tidak risih lagi)

**Masalah sebelumnya:** tiap refresh browser disuruh login lagi.

**Fix:**
- Frontend sekarang kirim cookie dengan `credentials: 'include'` (sebelumnya tidak) → session `ghs`/`sid` (AES-256-GCM) kekirim tiap request
- Masa aktif diperpanjang **7 hari → 30 hari** (GitHub) dan **12 jam → 30 hari** (admin)
- Cache `localStorage: xyrdp_me_cache` — refresh tetap masuk dashboard dulu sambil cek di background

**Action kamu (sekali saja setelah update ini live di Vercel ~1 menit):**
1. Buka `xyrdp-dash.vercel.app` → jika masih diminta login, **Clear cookie** untuk site (Chrome: ikon gembok → Cookies → hapus `ghs` & `sid`) atau `Ctrl+Shift+Del` → Cookies
2. Login ulang sekali → selanjutnya **tahan 30 hari**, refresh tidak logout lagi
3. Jangan ganti `SESSION_SECRET` di Vercel (≥32 char). Kalau diganti, semua user logout.

## 2. Kenapa login via Dashboard bisa kena suspend, padahal fork manual aman?

| Cara | Aman? | Kenapa |
|---|---|---|
| **Fork manual di github.com** (`xykal/XyRDP` → `Use this template` → `Create new repository`) | **PALING AMAN** | Aksi native GitHub. Rate limit per akun kamu. Workflow jalan di repo `kamu/RdpFree` pakai token kamu. Tidak lewat IP Vercel. |
| **Dashboard “Masuk dengan GitHub” (OAuth)** | Berisiko jika spam | Dashboard pakai token kamu untuk `generate repo` + `set secrets` + `dispatch workflow` via **API dari IP Vercel**. Kalau banyak user klik “Buat Repo” + “Start” barengan dalam 1-2 menit → terdeteksi **automation spam / abuse** → flag suspend. |

**Fix anti-suspend di dashboard (sudah live):**
- **Limit 2× Start per 5 menit per user/IP** → kalau kelebihan: `429 Tunggu Xs lagi`
- **Blokir dispatch jika masih ada run `queued/in_progress`** → harus `Stop` dulu
- Semua dijelaskan di `/panduan` bagian baru

**Cara aman pakai dashboard:**
1. **Paling aman: fork manual dulu** di github.com (beri nama `RdpFree`), tunggu 1-2 menit, baru login dashboard (otomatis pakai `kamu/RdpFree`)
2. Jangan spam “Buat Repo” / “Start” — tunggu run selesai
3. Jangan bikin 5+ repo RDP dalam sejam pakai 1 akun
4. Isi secret wajib: `RDP_PASSWORD` (min 8) + `TAILSCALE_AUTH_KEY` (`tskey-auth-...` jangan share publik). Opsional: `GTA_SA_URL` untuk SAMP

## 3. Cara sync fork kamu (dapat fix boost stuck + login)

**Paling cepat (web):**
1. Buka fork kamu `github.com/kamu/RdpFree` → tombol **Sync fork** → **Update branch** (atau `Fetch upstream` jika belum pernah)
2. Jika tombol tidak ada: `Settings` → `Actions` → `General` → pastikan **Allow all actions** + **Workflow permissions: Read and write**
3. Cek `Actions` tab → workflow `RdpFree — RDP 6 Jam` aktif (jangan Disable)

**Via git (alternatif):**
```bash
git clone https://github.com/kamu/RdpFree.git
cd RdpFree
git remote add upstream https://github.com/xykal/XyRDP.git
git fetch upstream
git merge upstream/main
git push origin main
```

Setelah sync, boost tidak akan stuck lagi (sebelumnya `Get-ChildItem -Recurse` di `C:\Android` bikin hang 10 menit → sekarang FAST `3m25s` terbukti run #86). Cek di `Actions` → log `⚡ Boost Storage`.

## 4. Info cepat issue lain

- **SAMP gak reaksi:** isi secret `GTA_SA_URL` (link direct ZIP GTA SA portable, Google Drive direct/Dropbox/S3). Tanpa itu SAMP skip.
- **Roblox Player gak kebuka:** runner GitHub adalah **Hyper-V VM** — Roblox anti-cheat deteksi hypervisor → block. `setup-roblox.ps1` sudah VM-hide tapi tetap tidak 100%. Gunakan **Roblox Studio** saja di RDP, atau main via browser.
- **Minecraft 20 fps:** runner cuma 2 vCPU + software GPU (Mesa). Set `assets/rdp-extras.json` → `lightweight_mode:true`, `translucent:false`, `win10_look:false`, pakai Sodium/Fabric low-spec.

---
Credit: **KallAncrit** • RdpFree • Web tidak ikut ke fork — cuma repo script.
Live: `xyrdp-dash.vercel.app` (Vercel auto-deploy dari `main`) — fix login 30d sudah live.
