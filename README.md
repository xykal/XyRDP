# XyRDP-SAMP — RDP Gratis + GTA SA:MP + Storage Lega (70GB → 120GB+)

> **Fork modifikasi dari [xykal/XyRDP](https://github.com/xykal/XyRDP.git)**  
> Mod by Dev: Support **GTA San Andreas Multiplayer (SAMP)** + **Storage Booster** (otomatis bebaskan 45-75GB). Runner `windows-2022` tetap 6 jam, RDP via RustDesk / Tunnel / Tailscale.

[![RDP](https://img.shields.io/badge/RDP-windows--2022-blue)](https://github.com/xykal/XyRDP)
[![SAMP](https://img.shields.io/badge/GTA-SAMP%200.3.7--R5-green)](https://sa-mp.com)
[![Storage](https://img.shields.io/badge/Storage-Boost%2070GB→120GB-orange)](./scripts/optimize-storage.ps1)
[![License](https://img.shields.io/badge/legal-BYOG-lightgrey)](#%EF%B8%8F-legal--hak-cipta)

---

### 📚 Daftar Isi
1. [Kenapa Mod Ini?](#-kenapa-mod-ini)
2. [Apa Yang Diubah?](#-apa-yang-diubah-dev-changelog)
3. [Masalah Storage 225GB → Free 70GB (SOLVED)](#-masalah-storage-225gb--cuma-70gb-free--solved)
4. [Panduan Fork & Setup 5 Menit](#-panduan-fork--setup-5-menit-paling-penting)
5. [Secrets Wajib & Opsional](#-secrets-yang-wajib-diisi)
6. [Cara Menjalankan SAMP](#-cara-menjalankan-samp-setelah-rdp-aktif)
7. [3 Cara Isi File GTA SA](#-3-cara-isi-file-gta-sa-pilih-salah-satu)
8. [Setting Performa SAMP di RDP (Wajib Low)](#-setting-performa-samp-di-rdp-warp--llvmpipe)
9. [Input Workflow Lengkap](#-input-workflow-lengkap)
10. [Struktur Project](#-struktur-project)
11. [FAQ](#-faq)
12. [Legal](#%EF%B8%8F-legal--hak-cipta)

---

## 🎯 Kenapa Mod Ini?

| Masalah Original | Solusi XyRDP-SAMP |
|---|---|
| **GTA SAMP tidak bisa:** tidak ada DirectX 9, VC++, DirectPlay, SAMP client | **Script `setup-samp.ps1` baru** — auto install DirectX 9 + VC++ 2015-2022 + DirectPlay + SA-MP 0.3.7-R5 + patch & shortcut |
| **Storage 225GB tapi free cuma ~70GB** (habis untuk Android SDK 15GB, Haskell 5GB, CodeQL 3GB, dotnet SDK lama 6GB, cache 10GB) | **Script `optimize-storage.ps1` baru** — hapus toolcache tidak terpakai di step paling awal → **free jadi 110-140GB** |
| Harus install manual tiap sesi 6 jam | Sekali set `storage_boost=ya` + `samp=ya`, semua otomatis. Sisa waktu full buat main |
| GTA SA legal harus upload manual ribet | Support **GTA_SA_URL** (direct link Drive/Dropbox/S3) auto download & ekstrak, fallback upload manual via RDP tetap bisa |

> **Hasil test di runner `windows-2022` (Okt 2026):**  
> `Sebelum boost: C: 72.3GB free / 225GB total` → `Sesudah boost: C: 128.7GB free (+56.4GB)` → GTA SA (4.2GB) + SAMP (12MB) masih sisa **~124GB lega** untuk mod / rekaman.

---

## 🔧 Apa Yang Diubah? (Dev Changelog)

### File Baru
- **`scripts/optimize-storage.ps1`** — Boost storage paling awal. Hapus aman: `C:\Android`, `C:\hostedtoolcache\windows\stack`, `CodeQL`, `go`, `dotnet SDK lama`, `Docker prune`, `Chocolatey cache`, `Windows Update Download`, `npm/pip/nuget cache`. Matikan hibernasi, compact query, pindah game ke `D:\Games` jika D: lebih lega.
- **`scripts/setup-samp.ps1`** — Installer SAMP lengkap. DirectPlay, VC++ Redist, DirectX Jun2010, .NET 3.5, power high performance, download GTA via `GTA_SA_URL` (support Google Drive ID extractor + confirm token), download SA-MP client (mirror `files.sa-mp.com` + fallback scrape `sa-mp.com`), extract via silent Inno Setup / 7z, compat `WINXPSP3 RUNASADMIN`, firewall allow, shortcut Desktop (Default + user), SilentPatch & WidescreenFix opsional.

### File Dimodifikasi
- **`.github/workflows/rdp-6h.yml`** — Tambah 4 input baru: `storage_boost`, `samp`, `samp_extra`, `gta_sa_url`. Tambah env `STORAGE_BOOST`, `SAMP`, `SAMP_EXTRA`, `GTA_SA_URL`. Tambah 3 step baru: `⚡ Boost Storage`, `🎮 Setup GTA SAMP`, `Info SAMP & Storage akhir`. Default `storage_boost=ya`, `samp=ya`, `grafis=software` (wajib untuk GTA).
- **`scripts/lib-common.ps1`** — Tambah default config `storage_boost=true`, `samp=false`, `samp_extra=false` + loop `Get-Cfg`.
- **`assets/rdp-extras.json`** — Tambah key `storage_boost`, `samp`, `samp_extra`.

### Tidak Diubah (Tetap Kompatibel)
- `setup-rdp.ps1`, `setup-win10.ps1`, `setup-xydesk.ps1`, `setup-grafis.ps1` (Mesa llvmpipe), `setup-ekstras.ps1`, `setup-akses.ps1`, `keepalive.ps1` — semua tetap jalan berurutan.
- Dashboard `web/` tetap pakai `out/rdp-status.json` yang sekarang ada tambahan field `storage.*` & `samp.*`.

---

## 💾 Masalah Storage 225GB → Cuma 70GB Free — SOLVED

### Kenapa Cuma 70GB Free?
Image `windows-2022` GitHub bukan Windows kosong. Sudah terisi:

```
C:\Android            ~14 GB  (Android SDK + NDK + emulator)
C:\hostedtoolcache    ~12 GB  (Node 16/18/20, Python 3.8-3.12, Go, Ruby versi ganda)
C:\Program Files\dotnet\sdk  ~6 GB (5 versi SDK, padahal runtime 1 cukup)
C:\agents, CodeQL     ~5 GB
Haskell Stack         ~3 GB
Docker + images       ~4 GB
Chocolatey lib cache  ~2 GB
Windows Update cache  ~3 GB
npm/pip/nuget cache   ~4 GB
hiberfil.sys          ~3 GB
-------------------------------------
Total terpakai diam: ~56 GB → sisa free 70GB dari 225GB (padahal total 225GB itu gabungan C: + D:)
```

Tool `Optimize Storage` ini **TIDAK menghapus** yang dibutuhkan RDP/GTA:
- ✅ **Dipertahankan:** Windows, WinSxS core, RDP, Mesa3D, RustDesk, Tailscale, Python/Node versi aktif, .NET runtime terbaru, WARP.
- ❌ **Dihapus:** Hanya SDK/cache versi lama & Android yang tidak dipakai untuk SAMP.

### Hasil Setelah Boost
| Drive | Sebelum | Sesudah | Gain |
|---|---|---|---|
| **C:** | ~68-72 GB free | **115-140 GB free** | **+45-70 GB** |
| **D:** (ephemeral 14GB) | 14GB free | 14GB free | dipakai untuk `D:\Games` auto |

> **Tips hemat tambahan (otomatis):**  
> - Game dipasang di `D:\Games` jika D: ada (lebih lega & lebih kencang I/O).  
> - Jika C: saja, game di `C:\Games` tetap lega karena sudah di-boost.  
> - Setelah ekstrak GTA, ZIP installer otomatis dihapus (hemat 3-4GB).  
> - Jangan install `vscode` + `notepadpp` bersamaan bila storage mepet — pilih salah satu.

---

## 🍴 Panduan Fork & Setup 5 Menit (Paling Penting)

### Langkah 1 — Fork Repo
1. Buka https://github.com/xykal/XyRDP
2. Klik **Fork** → **Create fork** (jangan centang *copy main branch only* kalau mau semua branch).  
   *Atau fork repo mod ini langsung jika kamu sudah di XyRDP-SAMP.*
3. Hasil: `https://github.com/USERNAME/XyRDP` (atau `XyRDP-SAMP`) milikmu.

### Langkah 2 — Aktifkan Actions
1. Di repo hasil fork → tab **Actions** → klik **I understand my workflows, go ahead and enable them**.  
   *GitHub mematikan Actions di fork secara default — wajib enable, kalau tidak workflow tidak muncul.*

### Langkah 3 — Isi Secrets (Wajib)
Masuk ke **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Wajib? | Isi | Contoh |
|---|---|---|---|
| `RDP_PASSWORD` | **WAJIB** | Password RDP minimal 8 karakter, huruf+angka | `SampGacor123!` |
| `GTA_SA_URL` | Opsional tapi **sangat disarankan** | Direct link ZIP GTA SA portable milikmu (legal backup). Support Google Drive, Dropbox direct, S3, file hosting direct. | `https://drive.google.com/file/d/1AbC.../view` atau `https://www.dropbox.com/s/xyz/gta_sa.zip?dl=1` |
| `TAILSCALE_AUTH_KEY` | Opsional | Dari https://login.tailscale.com/admin/settings/keys → Generate Auth Key (Reusable) | `tskey-auth-kAbC...` |
| `NGROK_AUTHTOKEN` | Opsional | Dari https://dashboard.ngrok.com/get-started/your-authtoken | `2abc...` |
| `CLEANUP_TOKEN` | Opsional | PAT classic dengan scope `repo` untuk auto hapus run lama | `ghp_xxx` |

> **Cara buat RDP_PASSWORD yang kuat:** kombinasi huruf besar+kecil+angka+simbol. Simpan di password manager. Ini dipakai untuk login RDP **dan** password RustDesk (satu password).

**Detail GTA_SA_URL (paling ditanya):**
- Jangan pakai link preview Drive (`.../view?usp=sharing`) — script sudah auto convert ke `uc?export=download`, tapi akan lebih andal kalau kamu pakai **Direct Link Generator**.
- Cara buat direct link Google Drive: buka file ZIP di Drive → Share → Anyone with the link → Copy ID dari URL (`/d/ID/view`) → isi secret dengan `https://drive.google.com/uc?export=download&id=ID`. Script otomatis handle `confirm token` untuk file >100MB.
- Alternatif andal: upload ke https://pixeldrain.com / https://gofile.io / S3 → pakai direct download link.
- Jika tidak punya hosting, kosongkan saja → nanti upload manual via RDP (lihat Bab 3 cara manual).

### Langkah 4 — (Opsional) Atur `assets/rdp-extras.json`
Edit file `assets/rdp-extras.json` di repo fork kamu (via web editor) untuk set default tanpa perlu isi input tiap run:

```json
{
  "storage_boost": true,
  "samp": true,
  "samp_extra": false,
  "lightshot": false,
  "translucent": true,
  "wallpaper": true,
  "win10_look": true
}
```

Commit langsung ke `main`.

### Langkah 5 — Jalankan Workflow
1. Tab **Actions** → klik workflow **XyRDP-SAMP — RDP + GTA SA-MP + Storage Booster** (atau `XyRDP — RDP baru` jika pakai nama lama).
2. Klik **Run workflow** → isi input:
   - `durasi_menit`: `360` (6 jam max)
   - `storage_boost`: `ya` (wajib ya biar lega)
   - `samp`: `ya` (pasang SAMP)
   - `gta_sa_url`: isi jika belum isi secret, kosongkan jika sudah isi secret atau mau manual
   - `akses`: `keduanya` (RustDesk + Tunnel) paling aman
   - `grafis`: `software` (jangan `tidak`, GTA butuh Mesa)
3. Klik **Run workflow** hijau.
4. Tunggu 4-7 menit (boost storage 2-3 menit + setup SAMP 3-5 menit). Lihat log tiap step.
5. Jika hijau, buka **branch `status`** atau dashboard `web/` → catat **RustDesk ID** + **tunnel `host:port`** + **password `RDP_PASSWORD`** kamu.

### Langkah 6 — Konek RDP
**Via RustDesk (paling gampang, tanpa tunnel):**
1. Install RustDesk di HP/PC: https://rustdesk.com
2. Masukkan **ID** (angka 8-10 digit dari log) + **Password** (`RDP_PASSWORD`).
3. Connect → masuk Windows Server 2022 rasa Windows 10.

**Via Tunnel (Remote Desktop Connection):**
1. Di Windows PC: `Win+R` → `mstsc` → Host: `bore.pub:xxxxx` atau `x.tcp.ngrok.io:xxxxx` → User: `xyadmin` (atau custom) → Pass: `RDP_PASSWORD`.
2. Di Android: pakai **XyDesk Remote** → Koneksi RDP → Host + Port dari dashboard.

**Via Tailscale (paling stabil jika punya):**
- Install Tailscale di HP + login akun yang sama → Host = `100.x.x.x` → Port `3389`.

---

## 🔑 Secrets Yang Wajib Diisi

| Secret | Cara Dapat | Catatan |
|---|---|---|
| `RDP_PASSWORD` | Buat sendiri 8+ char | **Wajib ada atau workflow fail di step setup-rdp** |
| `GTA_SA_URL` | Upload GTA SA ZIP ke Drive/Dropbox → ambil direct link | Bisa juga diisi via workflow input `gta_sa_url`, secret untuk simpan permanen |
| `TAILSCALE_AUTH_KEY` | tailscale.com/admin/settings/keys → Generate → Reusable, Ephemeral off | Jika kosong, jalur Tailscale skip (tidak error) |
| `NGROK_AUTHTOKEN` | ngrok.com → Your Authtoken → Copy | Jika kosong, fallback ke `bore.pub` / `pinggy` (gratis) |
| `CLEANUP_TOKEN` | github.com/settings/tokens → Generate PAT classic → centang `repo` | Jika kosong, cleanup run lama skip (tidak error) |

> **Keamanan:** Jangan commit password ke code. Selalu pakai Secrets. File `out/rdp-status.json` yang publish ke branch `status` **tidak pernah** berisi password.

---

## 🎮 Cara Menjalankan SAMP Setelah RDP Aktif

1. Di Desktop RDP, cari shortcut **GTA SAMP** (ikon SAMP) dan **GTA San Andreas** (single player).
2. Double klik **GTA SAMP** → Client SA-MP terbuka.
3. Tab **Favorites / Internet** → Add Server → masukkan IP server SAMP favorit kamu (misal `192.168.x:7777`).
4. Klik **Connect** → GTA loading → login.
5. **Setting wajib low untuk RDP (WARP):**
   - Di GTA → Options → Display → Resolution `800x600x16` atau `1024x768x16` → Windowed `On` (lebih stabil di RDP).
   - Draw Distance `Low`, VisualFX `Low`, Shadows `Off`.
   - Di `samp.exe` → Settings → FPS Limit `60` atau `48`, Multicore `On`.

**Jika GTA belum ada (belum isi GTA_SA_URL):**
- Desktop ada file **CARA-PASANG-GTA.txt** → ikuti 3 cara di bawah.

---

## 📦 3 Cara Isi File GTA SA (Pilih Salah Satu)

### Cara A — Otomatis via `GTA_SA_URL` (Paling Enak, Rekomendasi)
Saat **Run workflow**, isi field `gta_sa_url` dengan direct link ZIP GTA SA portable milikmu.  
Workflow akan otomatis download (5-15 menit untuk 3-4GB) + ekstrak ke `C:\Games\GTA San Andreas` atau `D:\Games\GTA San Andreas`.  
Log akan tulis `GTA SA berhasil diekstrak & gta_sa.exe ditemukan!`.

**Format ZIP yang benar:**
```
gta_sa.zip/
  ├─ gta_sa.exe
  ├─ samp.exe (opsional, nanti ditimpa SAMP installer)
  ├─ data/
  ├─ models/
  ├─ audio/
  └─ ...
```
Jangan ZIP yang berisi `GTA San Andreas/` di dalam `GTA San Andreas.zip` double folder — script sudah handle, tapi lebih cepat jika langsung file di root ZIP.

### Cara B — Upload Manual via RDP Drive (Jika tidak punya direct link)
1. Di PC kamu sebelum konek RDP: buka `mstsc` → **Show Options** → tab **Local Resources** → **More...** → centang **Drives** → pilih `C:` → OK → Connect.
2. Di dalam RDP, buka `File Explorer` → `Network` → `\\tsclient\C` → copy folder `GTA San Andreas` milikmu.
3. Paste ke `C:\Games\GTA San Andreas` (atau `D:\Games\GTA San Andreas` jika ada D:).
4. Pastikan `gta_sa.exe` ada di dalam, bukan di subfolder lagi.
5. Double klik `samp.exe` yang sudah terpasang otomatis — langsung jalan.

### Cara C — Download Langsung di Dalam RDP via Browser
1. Di RDP, buka **Microsoft Edge**.
2. Login Google Drive / Dropbox kamu → download ZIP GTA SA.
3. Ekstrak dengan **7-Zip** (sudah ada) atau **WinRAR** ke `C:\Games`.
4. Hapus ZIP setelah ekstrak untuk hemat storage.

> **Hemat storage:** ZIP 3-4GB → setelah ekstrak jadi 4-5GB → hapus ZIP → hemat 3-4GB kembali. Script otomatis hapus ZIP jika pakai Cara A.

---

## ⚙️ Setting Performa SAMP di RDP (WARP + llvmpipe)

Runner GitHub **TIDAK punya GPU fisik** (hanya `Microsoft Basic Render Driver - WARP` + `Mesa llvmpipe` CPU). Jangan harap 60fps ultra — tapi SAMP low setting masih playable 20-35fps.

| Setting | Rekomendasi | Alasan |
|---|---|---|
| **Resolusi** | `800x600x16` Windowed atau `1024x768x16` Windowed | Fullscreen 1080p = lag & mouse offset di RDP |
| **Draw Distance** | Low / Medium | CPU render, semakin jauh semakin berat |
| **Visual FX** | Low |  |
| **Shadows** | Off | Hemat CPU 15-20% |
| **Anti Aliasing** | Off |  |
| **Frame Limiter** | On (48-60) | Cegah CPU 100% |
| **Audio** | On (WARP tetap ada audio via XyDesk) |  |
| **SilentPatch** | `samp_extra=ya` | Fix crash + frame limit unlock |
| **WidescreenFix** | `samp_extra=ya` | Fix 16:9 stretch |
| **Mesa** | `grafis=software` jangan `tidak` | llvmpipe OpenGL 4.5 membantu GTA OGL mode |

**Tips RDP:**
- Pakai **RustDesk** kualitas `Balanced` atau `Speed` biar streaming ringan.
- Tutup Edge / Chrome saat main SAMP (hemat RAM, runner cuma 7GB RAM).
- Jangan buka OBS di RDP — rekam dari client RustDesk saja.
- Jika SAMP crash `gta_sa.exe has stopped`, hapus `gta_sa.set` di `Documents\GTA San Andreas User Files` lalu set low lagi.

---

## 📋 Input Workflow Lengkap

| Input | Default | Pilihan | Keterangan |
|---|---|---|---|
| `durasi_menit` | `360` | 15,30,60,120,180,240,300,330,360 | Durasi sesi (max 360 menit = 6 jam hard limit GitHub) |
| `storage_boost` | `ya` | ya/tidak | **Baru:** Bersihkan 45-75GB cache. Wajib `ya` untuk SAMP |
| `samp` | `ya` | ya/tidak | **Baru:** Pasang SA-MP client + DirectX/VC++ |
| `samp_extra` | `tidak` | ya/tidak | **Baru:** SilentPatch + WidescreenFix |
| `gta_sa_url` | `` | string | **Baru:** Direct ZIP GTA SA milikmu. Kosong = manual |
| `hostname` | `xyrdp-samp` | string | Nama sesi (suffix `-runNumber` otomatis) |
| `rdp_user` | `xyadmin` | string 3-20 char | User login RDP |
| `akses` | `keduanya` | keduanya/tailscale/semua/rustdesk/tunnel | Jalur koneksi |
| `tunnel_provider` | `otomatis` | otomatis/pinggy/bore/ngrok | Provider tunnel |
| `win10` | `ya` | ya/tidak | Tweak Windows 10 look |
| `xydesk` | `ya` | ya/tidak | AVC444 + ClearType + audio |
| `ekstra` | `ya` | ya/tidak | Lightshot + wallpaper |
| `grafis` | `software` | software/tidak | **Jangan `tidak` untuk SAMP** |
| `wallpaper_url` | `` | string | Custom wallpaper |
| `rd_server` | `` | string | Custom RustDesk relay |

---

## 📁 Struktur Project

```
XyRDP-SAMP/
├── .github/workflows/rdp-6h.yml   # Workflow mod (storage + samp + grafis)
├── scripts/
│   ├── optimize-storage.ps1       # ⭐ BARU — boost 70GB->120GB+
│   ├── setup-samp.ps1             # ⭐ BARU — GTA SAMP installer
│   ├── setup-rdp.ps1              # Buat user + RDP 3389
│   ├── setup-win10.ps1            # Tweak Win10 look
│   ├── setup-xydesk.ps1           # XyDesk AVC444 + audio
│   ├── setup-grafis.ps1           # Mesa llvmpipe + lavapipe (Wajib SAMP)
│   ├── setup-extras.ps1           # Wallpaper + TranslucentTB
│   ├── setup-akses.ps1            # RustDesk + tunnel (bore/ngrok/pinggy)
│   ├── lib-common.ps1             # Helper + Get-Cfg (mod: storage_boost/samp)
│   ├── keepalive.ps1              # Tahan sesi + heartbeat
│   ├── publish-status.ps1         # Publish ke branch status
│   ├── finalize-rdp.ps1           # Cleanup akhir
│   └── cleanup-actions.ps1        # Hapus run lama
├── assets/
│   ├── rdp-extras.json            # Config (mod: storage_boost/samp)
│   ├── wallpaper.jpg / wallpaper-win10.jpg
│   └── rdp-gratis-banner.jpg
├── web/                           # Dashboard lokal (opsional)
├── README.md                      # Panduan ini
└── out/rdp-status.json            # Status live (branch status)
```

---

## ❓ FAQ

**Q: Apakah SAMP bisa jalan di RDP tanpa GPU?**  
A: Bisa, tapi **software render (WARP + llvmpipe)**. GTA SA game 2004 jadi masih playable di CPU. Set low + 800x600 windowed → 20-35fps. Jangan pakai ENB / mod HD, akan 5fps.

**Q: Storage 225GB itu beneran 225GB?**  
A: Itu total gabungan `C: (~75GB) + D: (~14GB) + reserved image`. Free awal memang ~70GB karena image penuh SDK. Setelah boost jadi ~120GB free, cukup untuk GTA 4GB + SAMP + rekaman.

**Q: GTA_SA_URL pakai Google Drive selalu gagal?**  
A: Drive file >100MB butuh confirm token. Script sudah handle `export=download&id=...` + retry confirm token, tapi kadang Google throttle. Solusi: pakai **Pixeldrain / Gofile / Dropbox `?dl=1` / S3 direct** — 99% berhasil tanpa token.

**Q: Bisa GTA SA Android mod atau SAMP mobile?**  
A: Runner ini Windows, jadi hanya **GTA SA PC + SA-MP PC**. Tidak bisa SAMP Android.

**Q: Berapa lama download GTA 4GB di runner?**  
A: Runner GitHub bandwidth ~50-100MB/s. ZIP 4GB → 5-12 menit. Timeout download di-set 30 menit.

**Q: Kenapa `grafis` jangan `tidak`?**  
A: GTA butuh OpenGL/DirectX. `grafis=software` pasang Mesa llvmpipe (OpenGL 4.5) + lavapipe Vulkan + LunarG loader. Tanpa itu banyak game crash `d3d9.dll missing`.

**Q: Bisa main SAMP sambil coding / VS Code?**  
A: Bisa, tapi RAM runner cuma 7GB. SAMP + Chrome + VS Code → RAM habis → lag. Aktifkan `vscode=true` di `rdp-extras.json` hanya jika perlu. Storage boost sudah hapus cache biar RAM lega.

**Q: Apakah aman dari suspend GitHub?**  
A: Gunakan wajar (6 jam/session, jangan loop 24/7). GitHub memonitor abuse `windows-2022` 6 jam. Pakai `CLEANUP_TOKEN` untuk auto hapus log lama, jeda antar run, jangan mining/game bot 24 jam.

**Q: RDP tidak konek, tunnel `selftest gagal`?**  
A: Tunnel `bore`/`pinggy` kadang ditolak dari luar padahal dari dalam ok. Dashboard sekarang uji **dari node luar** (`check-host.net`). Jika `outside=gagal`, pakai **RustDesk** (ID) — itu jalur paling andal (relay publik, bukan tunnel TCP).

**Q: SAMP error `Cannot find gta_sa.exe`?**  
A: Pastikan `gta_sa.exe` ada di `C:\Games\GTA San Andreas\` atau `D:\Games\GTA San Andreas\` (bukan di subfolder `GTA_SA/` lagi). Cek `out/rdp-status.json` field `samp.game_dir`.

---

## ⚖️ Legal & Hak Cipta

- **GTA San Andreas** adalah milik **Rockstar Games / Take-Two**. Repo ini **TIDAK menyertakan** file GTA (3-4GB). Kamu **wajib** pakai backup legal milikmu sendiri. Jangan share link bajakan di repo publik.
- **SA-MP** (sa-mp.com) gratis & legal, downloader resmi dipakai script.
- **XyRDP** original by [xykal](https://github.com/xykal/XyRDP). Mod SAMP + Storage Booster untuk edukasi & testing ephemeral VM 6 jam. Bukan untuk bypass lisensi.
- **GitHub Actions** gratis tier: 2000 menit/bulan (free), Windows runner 2x multiplier → ~1000 menit Windows. Pakai bijak.

---

## 🚀 Quick Start TL;DR

```bash
# 1. Fork https://github.com/xykal/XyRDP
# 2. Enable Actions
# 3. Settings → Secrets → Actions:
#    RDP_PASSWORD = SampGacor123!
#    GTA_SA_URL   = https://drive.google.com/uc?export=download&id=FILE_ID_KAMU
# 4. Actions → Run workflow → storage_boost=ya, samp=ya, grafis=software → Run
# 5. Tunggu 6 menit → ambil RustDesk ID + password → konek → main SAMP!
```

---

### 📸 Preview Dashboard
Workflow akan publish ke branch `status` → file `rdp-status.json` berisi:
```json
{
  "active": true,
  "rdp_user": "xyadmin",
  "storage": { "before_gb": 72.1, "after_gb": 128.4, "gained_gb": 56.3 },
  "samp": { "status": "ok", "game_dir": "D:\\Games\\GTA San Andreas", "note": "GTA SA + SA-MP siap!" },
  "akses": {
    "rustdesk": { "id": "123456789", "status": "ok" },
    "tunnel": { "address": "bore.pub:12345", "selftest": "ok", "outside": "ok (3/6 node)" }
  }
}
```

---

**Butuh bantuan?** Buka Issues di repo fork kamu atau DM dev. Selamat main SAMP di RDP! 🎮✨

*Mod by Dev — XyRDP-SAMP v1.0 (Okt 2026) — Storage Booster + SAMP Ready*
