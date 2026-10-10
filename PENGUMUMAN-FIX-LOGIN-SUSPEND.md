# PENGUMUMAN — Fix Login Tiap Refresh & Anti-Suspend (10 Okt 2026)

> **Update wajib untuk semua user fork.** Sync fork kamu sekarang — fix sudah di `main` (`5c7df72` REVISI TOTAL web login — anti login loop).

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

## 4. Wallpaper hitam & Mikrofon — FIX `1c0b668`

**Wallpaper hitam itu bawaan Windows Server, bukan XyDesk.** XyDesk cuma host RDP — `mstsc` & XyDesk lihat sesi yang sama. Repo sudah ada `assets/wallpaper.jpg` + `wallpaper-win10.jpg` + `rdp-extras.json: wallpaper=true`. Jika masih hitam:

- **Client matikan wallpaper** (paling sering):  
  - `mstsc` → `Show Options` → `Experience` → centang `Desktop background / Wallpaper`  
  - `XyDesk Remote` → `Settings` → `Wallpaper` → **ON** (OFF = sengaja hitam irit 30% bandwidth)
- **Fix `1c0b668`:** `setup-xydesk.ps1` sekarang set `fNoRemoteDesktopWallpaper=0` + `WallpaperStyle=10` via Policy (tanpa tulis `WinStations` biar `3389` gak mati) → run berikutnya wallpaper **pasti tampil** kalau client ON. Upload baru via dashboard `Settings → Upload Wallpaper` juga langsung kepasang.

**Mikrofon — BISA & SUDAH AKTIF:**
- Host sekarang: `fDisableAudio=0` + `fDisableAudioCapture=0` + `AudioQualityMode=2 (High)` + `AudioEndpointBuilder` jalan (Policy override). Log: `mic HP redirect aktif`.
- **XyDesk:** HP → `Settings` → `Apps` → `XyDesk` → `Permissions` → `Microphone Allow` → XyDesk → `Settings` → `Enable Microphone ON` → di RDP `mmsys.cpl` → `Recording` → `Remote Audio` → test `Sound Recorder`.
- **mstsc:** edit `.rdp` tambah `audiomode:i:0` + `audiocapturemode:i:1` + `microphone:redirection:i:1`.

## 5. SAMP — Pasti Bisa (YouTube + Link Valid, Gak Ngerti Pun Jadi) — Update Terbaru

**SAMP gratis, GTA SA wajib punya sendiri (backup legal).** Script kita auto pasang SAMP client + DirectPlay + VC++ + DirectX anti-DxError + shortcut + firewall. Kamu cuma sediakan GTA SA.

**Cara A paling gampang — Otomatis via `GTA_SA_URL` (1 klik):**
1. Upload ZIP GTA SA portable milikmu (isi `gta_sa.exe` + `models`/`data` ~2-4GB) ke **Google Drive** → Share → `Anyone with the link` → Copy link `https://drive.google.com/file/d/1AbC.../view` (Dropbox `?dl=1` / MediaFire juga bisa)
2. Repo fork → `Settings` → `Secrets and variables` → `Actions` → `New secret` → Name `GTA_SA_URL` → Value paste link (script auto jadi `https://drive.google.com/uc?export=download&id=...` + handle `confirm token`)
3. Dashboard / Actions → `RdpFree — RDP 6 Jam` → `Run workflow` → `samp: ya`, `samp_extra: ya` → Start. Log `🎮 Setup GTA SAMP` akan `Download → ekstrak ke D:\Games\GTA San Andreas → SA-MP install → shortcut GTA SAMP.lnk di Desktop`.

**Cara B — Manual via RDP (kalau gak pakai link):**
1. Start tanpa `GTA_SA_URL` → connect XyDesk/mstsc
2. Di dalam RDP buka Chrome → download GTA SA portable kamu, atau dari PC: `mstsc` → `Show Options` → `Local Resources` → `More` → centang `Drives C:` → di RDP buka `\\tsclient\C` → copy folder `GTA San Andreas` ke `D:\Games\GTA San Andreas`
3. Shortcut `GTA SAMP.lnk` sudah ada di Desktop → double klik `samp.exe` → connect server.

**Link SAMP valid (script coba semua mirror otomatis, gak perlu manual):**
- `https://files.sa-mp.com/sa-mp-0.3.7-R5-1-MP-install.exe` (official)
- `https://sa-mp.mp/downloads/` (mirror baru official)
- `https://gta-multiplayer.cz/downloads/sa-mp-0.3.7-R5-2-MP-install.exe`
- Fallback scrape `sa-mp.com/download.php` + `gta-multiplayer.cz` — kalau mau manual di RDP buka `https://sa-mp.mp/downloads/` → 0.3.7-R5-1 → install ke `D:\Games\GTA San Andreas`.

**YouTube tutor paling jelas:**
- How to play GTA SAMP 2024 → https://www.youtube.com/watch?v=OHwnAK9SvFY
- SAMP Setup Guide (0:22 instalasi) → https://www.youtube.com/watch?v=GFWaoZnkRKM
- Cari `cara pasang GTA SAMP` — intinya `GTA 1.0 US` + `sa-mp-0.3.7-R5-1-MP-install.exe` → pilih folder GTA → samp.exe. Wajib `GTA SA 1.0 US` (gta_sa.exe ~14MB), downgrade kalau Steam.

**Kalau masih DxError:** sudah anti-DxError — script cek `d3dx9_43.dll` dulu, skip Jun2010 kalau sudah ada, WARP backup. Log `skip (sudah ada)` bukan gagal.

## 6. Info lain

- **Roblox Player gak kebuka:** runner Hyper-V → anti-cheat block. Pakai **Roblox Studio** saja.
- **Minecraft 20 fps:** 2 vCPU + Mesa software. Set `rdp-extras.json` → `lightweight_mode:true`, `translucent:false`, `win10_look:false`, pakai Sodium.

---
Credit: **KallAncrit** • RdpFree • Web tidak ikut ke fork — cuma repo script.
**Update `d5e554f` — Disk lega maksimal + DirectX anti-DxError:**
- `optimize-storage.ps1` default **full debloat** (bukan ringan): Edge **beneran dihapus paksa** (folder `Edge`/`EdgeCore` + semua shortcut `*Edge*.lnk` di `Public/Desktop`/`Default/Desktop`/`Start Menu` HABIS), Unity Hub/Editor + R + OneDrive + Xbox + Clipchamp Appx HABIS, plus `DeliveryOptimization cache`, `vcpkg`, `hostedtoolcache/stack` — free **110-140GB** (log `Edge: BERHASIL dihapus HABIS`). WebView2 tetap dipertahankan biar app tidak error. Chrome tidak wajib lagi — Edge tetap dihapus kalau `full`.
- `setup-samp.ps1` DirectX **anti-DxError**: cek `d3dx9_43.dll` dulu (skip jika sudah ada), extract `Jun2010` dengan exit code + baca `C:\Windows\Logs\DirectX.log`, kalau `DxError` → fallback `WARP` (`skip` tidak fatal, GTA SA tetap jalan software). Jadi tidak lagi error install.
- Default `RDP_USER` tetap `xyadmin` (bukan `runneradmin`). Pakai `runneradmin` hanya jika kamu isi `RDP_USER=runneradmin` di workflow (highest bawaan). Jadi **jangan pakai runneradmin** kalau mau user terpisah — biarin default.

**Update `5c7df72` — REVISI TOTAL web login (orang udah login masih nampilin login):**
- Backend `api/index.js`: `cookieHeader` Secure via `x-forwarded-proto` + `VERCEL_ENV` (sebelumnya kadang tidak kekirim), `ghUserDebug` reason (`no_cookie`, `unseal_failed`, `expired`), `/auth/status` return `debug` + sliding refresh `ghs` 30d jika sisa <7d (sebelumnya langsung expired logout), semua `Set-Cookie` pakai `req`.
- Frontend `index.html`: `boot()` timeout 7s + retry 2x, fallback `localStorage 12h`, tidak langsung `showLogin` saat network 500, `api()` `credentials:include` + `me_at`, `showLogin` tampilkan debug di `ghNote`.

Live: `xyrdp-dash.vercel.app` (Vercel `5c7df72`) + workflow `1c0b668` wallpaper/mic + `d5e554f` disk/DirectX + `5c7df72` web revisi total.
