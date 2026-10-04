# XyRDP v2 — Windows "gaya 10" RDP 6 Jam via GitHub Actions
### tanpa self-host · **diakses dari HP pakai klien XyDesk Remote** · jalur utama **Tailscale** · **GPU software bawaan**

> **Update 4 Okt 2026 — Tailscale dipakai lagi dan ini jalur yang TERBUKTI jalan.**
> Input `akses` sekarang: **`tailscale` (default)**, `semua`, `keduanya`, `tunnel`, `rustdesk`.
> Jalur Tailscale menghidupkan node di tailnet-mu (`<hostname>-<run>.<tailnet>.ts.net`):
> dari HP pasang app **Tailscale** + login akun yang sama, lalu **XyDesk Remote →
> Koneksi RDP Penuh** dengan **Host = IP `100.x`** dari dashboard, **Port `3389`**.
> Jalur `tunnel` (bore/ngrok/pinggy) dan `rustdesk` tetap tersedia sebagai alternatif.
>
> **Funnel Tailscale (sudah dicoba 3–4 Okt): berhasil terbit, tapi tidak bisa dipakai klien RDP.**
> Buktinya: `funnel --bg --tcp 10000 tcp://127.0.0.1:3389` → exit 0, `AllowFunnel: true`,
> sertifikat HTTPS terbit, dan alamat `<node>.<tailnet>.ts.net` **muncul di DNS publik**
> (relay `208.111.34.11` / `208.111.35.209`). Namun Tailscale hanya menerima koneksi
> **TLS** di sisi publik ("Funnel only works over TLS-encrypted connections") — handshake
> RDP mentah (X.224) selalu ditutup relay (0 byte). Jadi **mstsc / XyDesk Remote / FreeRDP
> tidak bisa** memakai alamat funnel. Untuk "tanpa app Tailscale di HP" pakai **ngrok TCP**
> (secret `NGROK_AUTHTOKEN`), karena itu TCP mentah.


RDP Windows **gratis** pakai runner `windows-2022` GitHub Actions, diakses
**tanpa VPN dan tanpa server sendiri** — jalur utama dari HP:
**XyDesk Remote** (APK FreeRDP kamu) lewat **tunnel TCP** ke port 3389
(**bore.pub** tanpa akun, atau **ngrok** pakai token gratis).
**RustDesk** disediakan sebagai jalur **cadangan**. Sesi ditahan sampai durasi
(maks 6 jam = batas keras job GitHub), lalu VM musnah sendiri.

```
[HP: XyDesk Remote] --Host+Port--> bore.pub:PORT --> [Windows Server 2022 @ GitHub runner]
[PC: RustDesk/cadangan] ------relay publik-------->      └─ port 3389 + host setup XyDesk
                                                            (AVC444 · ClearType · audio/mic)
                                                            └─ user xyadmin (admin penuh)
```

---

## 1. Soal "Windows 10" — baca ini dulu (jujur)

Runner GitHub **tidak menyediakan image Windows 10 desktop**. Yang tersedia
hanya **Windows Server**, dan sejak **Juni 2026** label `windows-latest` malah
berpindah ke **Windows Server 2025** (tampilannya **Windows 11**). Karena itu:

| Pilihan | Hasil |
|---|---|
| **`windows-2022` + tweak (dipakai di sini)** | Windows Server **2022**, build **10.0.20348** — UI/kernel-nya **sama dengan Windows 10 21H2**. Ditambah `setup-win10.ps1` supaya terasa Windows 10, bukan Server. |
| Windows 10 asli (Pro/Home) | **Tidak bisa** di runner GitHub-hosted. Hanya lewat **self-hosted runner** atau VM/cloud lain — di luar permintaan "tanpa self-host". |

Yang dilakukan `scripts/setup-win10.ps1`:
- **Server Manager** tidak muncul lagi saat login, **Shutdown Event Tracker** mati
  (tidak tanya "alasan shutdown"), **IE Enhanced Security** mati.
- **Layar login ala Windows 10**: `Ctrl+Alt+Del` tidak diwajibkan, teks versi di
  desktop dimatikan, akun `Administrator` bawaan dinonaktifkan (layar login bersih).
- **Personalisasi khas Windows 10**: transparansi, warna aksen di taskbar
  (biru `#0078D7`), taskbar "jangan gabungkan tombol", kotak pencarian + Task View,
  tema gelap taskbar.
- **Windows Search diaktifkan** → Start menu bisa mencari aplikasi.
- **Wallpaper** `assets/wallpaper-win10.jpg` dipasang ke sesi + **latar layar login**
  (dikompres otomatis < 256 KB supaya dipakai LogonUI), fallback ke `assets/wallpaper.*`.
- **(Opsional, kosmetik)** label registry **"Windows 10 Pro / 22H2"**
  (`ProductName`, `EditionID`, `DisplayVersion`, `ProductType=WinNT`) — supaya
  aplikasi yang membaca registry menganggapnya Windows 10. **Tidak** mengubah
  kernel sebenarnya; `winver`/About bisa tetap menampilkan nama Server karena
  branding di `branding\Basebrd` milik TrustedInstaller tidak diubah.

Semua tweak bisa dimatikan: input workflow **`win10: tidak`**, atau toggle
**"Tweak tampilan"** / **"Label Windows 10 Pro"** di dashboard (tersimpan di
`assets/rdp-extras.json`).

---

## 2. Jalur akses (tanpa Tailscale, tanpa self-host)

| Jalur | Cara pakai di sisimu | Butuh akun? |
|---|---|---|
| **Tailscale** (default, terbukti) | Pasang app **Tailscale** di HP + login akun yang sama → **XyDesk Remote** → Host = **IP `100.x`** dari dashboard, Port `3389`. Funnel `<node>.<tailnet>.ts.net:10000` **tidak dipakai** (hanya klien TLS) | **Akun Tailscale** (yang punya tailnet) |
| **Tunnel RDP** → **XyDesk Remote (HP)** / `mstsc` | Di app: mode **Koneksi RDP Penuh** → Host = `bore.pub` (atau `x.tcp.ngrok.io`), Port = angka dari dashboard → login `xyadmin` + password. Di PC: Remote Desktop Connection ke alamat yang sama | **Tidak** (bore.pub) · ngrok pakai token akun gratis |
| **RustDesk** (cadangan) | Unduh klien gratis di [rustdesk.com/download](https://rustdesk.com/download) → masukkan **RustDesk ID** + **password** dari dashboard | **Tidak** — relay publik bawaan (`rs-ny/rs-sg.rustdesk.com`) |

Detail di `scripts/setup-akses.ps1`:
- **RustDesk**: install via `winget` (fallback installer GitHub releases),
  dipasang **sebagai service** (mode *unattended*, bisa konek sampai layar
  login/UAC), **password permanen = `RDP_PASSWORD`** (satu password untuk
  RustDesk + RDP), lalu ID diambil (`rustdesk.exe --get-id`) dan ditulis ke
  status → tampil di dashboard. Input **`rd_server`** (lanjutan) opsional kalau
  nanti mau pakai server RustDesk sendiri/terdekat — default tetap publik.
- **Tunnel**: `bore local 3389 --to bore.pub` (tanpa akun, port acak) atau
  `ngrok tcp 3389` (butuh secret `NGROK_AUTHTOKEN`). Proses berjalan selama sesi,
  dibunuh di step Finalize. **serveo.net tidak dipakai** karena tunnel TCP
  gratisnya hanya bertahan 10 menit (tidak cocok untuk sesi 6 jam).

### Khusus XyDesk Remote (klien yang kamu pakai dari HP)

Hasil penelusuran repo `xykal/XyDesk-Remote` (v0.5.34) yang dipakai di sini:

- Klien XyDesk punya **dua mode**: **Koneksi RDP Penuh** (Host + Port + domain +
  RD Gateway + SSH tunneling + WoL) dan **Koneksi PC (ID 10-digit & Password)**
  yang masih **Tahap Pengembangan/Experimental** (butuh `XyDeskRemoteHost.exe`
  + QUIC UDP 4433). Artinya jalur yang bisa dipakai dari runner GitHub sekarang
  adalah **mode RDP Penuh**, dan struktur `ConnectionProfile(host, port = 3389)`
  klien menerima **host + port bebas** → **tunnel TCP langsung cocok**, tanpa
  diubah apa pun di sisi klien.
- `scripts/setup-xydesk.ps1` = versi **inline** dari `rdp.xydesk.my.id/host.ps1`
  (v0.5.34) yang dulu diambil lewat internet. Isinya: RDP multi-session
  (`fSingleSessionPerUser=0`), **audio out + mic** hidup, kebijakan **AVC444
  4:4:4** + hardware encode + VGAdapter, **font smoothing yang benar**
  (`fNoFontSmoothing=0` + `AllowFontAntiAlias=1` di `WinStations\RDP-Tcp` —
  kunci yang *benar-benar* dibaca Windows, temuan commit XyDesk-Remote v0.5.30),
  dan firewall **TCP/UDP 3389 + UDP 4433**.
- **Batas yang jujur**: **audio bridge QUIC XyDesk (UDP 4433) tidak bisa lewat
  tunnel TCP** — relay TCP hanya meneruskan TCP. Port UDP-nya tetap dibuka di VM
  (siap kalau HP reach UDP langsung, mis. LAN/tailnet), dan klien akan gagal
  probe QUIC lalu **otomatis fallback ke audio RDP** (suara tetap ada).
  Mic HP → PC lewat QUIC juga tidak tersedia di jalur tunnel.
- Sertifikat RDP VM sekali-pakai → kalau klien menanyakan sertifikat, terima saja.
- Skala layar: klienmu sudah dikembalikan default **100%** (v0.5.30); kalau di
  sesi ini Windows memaksa 125%, teks bisa terlihat pecah — jaga di 100%.

> Catatan keamanan: tunnel membuat **port 3389 VM terbuka ke internet** selama
> sesi. Rem-nya: password panjang (`RDP_PASSWORD`) + NLA Windows. VM ini juga
> sekali-pakai dan hidup maksimal 6 jam. Kalau itu terlalu terbuka bagimu,
> pilih input `akses: rustdesk` (tanpa tunnel sama sekali).

---

## 3. Isi repo

| Path | Fungsi |
|---|---|
| `.github/workflows/rdp-6h.yml` | Workflow utama (runner `windows-2022`, timeout 360 menit) |
| `scripts/lib-common.ps1` | Helper bersama: logger, registry, hive profil Default, pembaca status, unduhan |
| `scripts/setup-rdp.ps1` | User admin + RDP 3389 + tulis status awal |
| `scripts/setup-win10.ps1` | **Tweak "Windows 10 look"** (Server Manager, personalisasi, wallpaper, label) |
| `scripts/setup-xydesk.ps1` | **Host setup XyDesk Remote** (AVC444 + ClearType + multi-session + audio/mic + UDP 4433) |
| `scripts/setup-grafis.ps1` | **GPU software**: Mesa3D llvmpipe (OpenGL 4.5+/4.6 core, sistem-wide) + lavapipe (Vulkan CPU) + lapor `grafis.*` ke status |
| `scripts/setup-akses.ps1` | **Tailscale (IP 100.x, default) + funnel (opsional) + RustDesk + tunnel RDP** |
| `scripts/setup-extras.ps1` | Lightshot + TranslucentTB + wallpaper (dari `assets/`) |
| `scripts/keepalive.ps1` | Penahan sesi + heartbeat tiap 5 menit + publish status tiap 30 menit |
| `scripts/publish-status.ps1` | Tulis `rdp-status.json` ke branch `status` (dibaca web) |
| `scripts/finalize-rdp.ps1` | Matikan RustDesk + tunnel, bersihkan kredensial lokal |
| `scripts/cleanup-actions.ps1` | Hapus run Actions lama + log-nya (simpan `KEEP_RUNS` terbaru) |
| `assets/rdp-extras.json` | Konfigurasi ekstra (diubah dari dashboard) |
| `assets/wallpaper-win10.jpg` | Wallpaper default gaya Windows 10 (+ latar layar login) |
| `web/` | Dashboard lokal (Node ≥ 18, tanpa dependency, tanpa install apa pun) |
| `deploy/vercel/` | Dashboard versi hosting (catch-all function + login cookie admin **dan** login GitHub multi-user) |

**Tailscale dipakai lagi** (sejak 3 Okt) sebagai jalur utama: auth key dari secret
`TAILSCALE_AUTH_KEY` — pakai kunci **ephemeral** supaya node otomatis terhapus saat
sesi mati. API/OAuth dan input `exit_node` tetap tidak dipakai.
**XyDesk host dikembalikan** — bukan lagi dengan mengambil `host.ps1` dari
internet, tapi **inline di repo** (`scripts/setup-xydesk.ps1`) supaya tidak
bergantung pada domain luar. "XyDesk ID" (turunan IP) tetap dibuang karena mode
ID 10-digit masih Experimental dan tidak dipakai jalur tunnel.

---

## 4. Cara pakai

1. **Dashboard**: buka URL dashboard-mu (deploy `deploy/vercel/` — lihat §6 — atau
   jalankan lokal `cd web && node server.js` → http://localhost:4173; jalur ini
   tidak butuh `npm install`, Node ≥ 18).
2. Pilih **durasi**, **hostname**, **jalur akses** (`keduanya` / `rustdesk` /
   `tunnel`), **provider tunnel** (`otomatis` / `bore` / `ngrok`), dan toggle
   **Tampilan Windows 10** → tombol **NYALAKAN**.
   (Manual: Actions → “XyRDP - Windows 10 Style RDP 6 Jam” → Run workflow.)
3. Tunggu **±3–5 menit** sampai status **AKTIF**. Panel **Koneksi** akan
   menampilkan **RustDesk ID** dan **alamat tunnel** (mis. `bore.pub:47321`).
4. Masuk dari HP dengan **XyDesk Remote** → **Koneksi RDP Penuh** →
   **Host** = bagian sebelum `:` dari alamat tunnel (mis. `bore.pub`),
   **Port** = angkanya (mis. `47321`) → login `xyadmin` + password.
   Dari PC: **Remote Desktop Connection** ke alamat tunnel yang sama.
   RustDesk (kalau dipilih) tinggal masukkan **ID** + password yang sama.
4b. **Jalur Tailscale (default):** di HP buka app **Tailscale** (login akun yang sama
   dengan tailnet), lalu **XyDesk Remote → Koneksi RDP Penuh** → **Host = IP `100.x`**
   dari panel Koneksi (mis. `100.81.187.66`), **Port `3389`** → login `xyadmin` + password.
   Alamat funnel `<node>.<tailnet>.ts.net:10000` **jangan dipakai** klien RDP: funnel
   hanya menerima klien TLS.
5. Sesi mati sendiri mendekati jam ke-6. Mau mati sekarang → tombol **MATIKAN**.

---

## 5. Secrets & input

**Wajib** (Settings repo → Secrets and variables → Actions):

| Secret | Isi |
|---|---|
| `RDP_PASSWORD` | password **tetap** user `xyadmin` — sekaligus password RustDesk. Min 8 karakter |

**Opsional**:

| Secret | Guna |
|---|---|
| `NGROK_AUTHTOKEN` | mengaktifkan provider ngrok (authtoken dari dashboard ngrok, gratis). Kosong = pakai bore.pub |
| `CLEANUP_TOKEN` | PAT scope `repo` untuk hapus run Actions lama (tanpa ini run lama menumpuk) |

`TAILSCALE_AUTH_KEY` **dipakai lagi** untuk jalur `tailscale`/`semua` (isi dengan auth
key tailnet; kunci ephemeral paling aman). `TAILSCALE_API_TOKEN`, `TAILSCALE_CLIENT_ID/SECRET`
tetap tidak dipakai.

Input workflow (`Run workflow`):

| Input | Isi |
|---|---|
| `durasi_menit` | 15 … 360 (batas keras job GitHub) |
| `grafis` | `software` (default) = pasang Mesa3D llvmpipe (OpenGL 4.5+/4.6 core) + lavapipe (Vulkan) + loader LunarG supaya aplikasi yang butuh OpenGL/Vulkan bisa jalan; `tidak` = lewati. Runner GitHub **tidak punya GPU fisik** (adapter = Microsoft Basic Render Driver/WARP), jadi ini renderer CPU — 3D berat tetap lambat, tanpa NVENC |
| `hostname` | nama sesi (dapat suffix nomor run, mis. `xyrdp-42`) |
| `akses` | `tunnel` (default — jalur XyDesk/mstsc) · `keduanya` · `rustdesk` |
| `tunnel_provider` | `otomatis` · `bore` · `ngrok` |
| `win10` | `ya` (default) / `tidak` — tweak tampilan Windows 10 |
| `xydesk` | `ya` (default) / `tidak` — host setup XyDesk (AVC444 + ClearType + audio + UDP 4433) |
| `ekstra` | `ya` (default) / `tidak` — Lightshot + wallpaper + taskbar translucent |
| `wallpaper_url` | URL wallpaper sendiri (jpg/png/bmp); kosong = `assets/wallpaper*` |
| `rd_server` | *(lanjutan)* server RustDesk sendiri/terdekat, mis. `rs-sg.rustdesk.com`; kosong = server publik |

---

## 6. Dashboard

### Lokal
```bash
cd web
node server.js          # butuh Node >= 18, tanpa npm install
# → http://localhost:4173
```
`web/config.json` (gitignored):
```json
{ "token": "ghp_...", "owner": "xykal", "repo": "XyRDP", "workflow": "rdp-6h.yml",
  "branch": "main", "port": 4173, "rdp_user": "xyadmin", "rdp_password": "..." }
```
Token = PAT scope `repo` (dispatch run, baca log, tulis `assets/`).
Dashboard **lokal** tidak punya login (memang untuk PC sendiri).

### Deploy ke Vercel (tanpa apa pun yang jalan di PC-mu)
Env vars project: `GITHUB_TOKEN`, `RDP_PASSWORD`, `AUTH_USER`, `AUTH_PASS`
(+ opsional `GH_OWNER` `GH_REPO` `GH_WORKFLOW` `GH_BRANCH` `RDP_USER`).
Endpoint API butuh sesi (cookie `sid`, HttpOnly); halaman login custom.
Redeploy setelah ubah kode:
```bash
cd deploy/vercel && npx vercel deploy --prod --yes --token <VercelToken>
```

### Mode multi-user: "Masuk dengan GitHub" (orang lain pakai repo mereka sendiri)

Dashboard yang di-hosting bisa dipakai banyak orang **tanpa mereka menyentuh
repo/secret punyamu**: tiap pengunjung login GitHub, dashboard membuatkan
**repo kerja milik mereka sendiri** (kopi dari template `xykal/XyRDP`), lalu
semua sesi RDP mereka jalan di repo itu — kuota Actions, token, dan Tailscale
mereka sendiri. Token/secret mereka **tidak disimpan di server**: sesi hanya
ada di cookie browser terenkripsi (AES-256-GCM), dan `RDP_PASSWORD` /
`TAILSCALE_AUTH_KEY` hanya di repo mereka.

Sekali saja (pemilik dashboard):
1. GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**.
   *Application name* bebas, *Homepage URL* = URL dashboard
   (`https://<dashboard-mu>`), *Authorization callback URL* =
   `https://<dashboard-mu>/api/auth/callback` (wajib persis).
2. Isi `GITHUB_OAUTH_CLIENT_ID` + `GITHUB_OAUTH_CLIENT_SECRET` (dari OAuth App)
   dan `SESSION_SECRET` (string acak panjang) di env Vercel. Opsional:
   `TEMPLATE_REPO` (default `GH_OWNER/GH_REPO`) dan `OWNER_LOGIN`.
3. Repo template harus publik + ditandai template (Settings → centang
   **Template repository**, atau `PATCH /repos/{owner}/{repo}` `is_template=true`).

Alur pengguna lain:
1. Buka dashboard → **Masuk dengan GitHub** (approve scope `repo`) → panel
   **Repo kamu** muncul: klik **BUAT REPO DARI TEMPLATE** (repo `XyRDP` di akun
   mereka dibuat + izin Actions dirapikan otomatis).
2. Isi 2 secret wajib di repo mereka — `RDP_PASSWORD` (sandi login RDP) dan
   `TAILSCALE_AUTH_KEY` (auth key *reusable* dari akun Tailscale mereka) —
   lewat tombol **BUKA SECRETS** di panel. `NGROK_AUTHTOKEN`/`CLEANUP_TOKEN`
   opsional.
3. Klik **PERIKSA / RAPIKKAN LAGI** → tombol **NYALAKAN** aktif. Kata sandi RDP
   disimpan **di browser mereka** (localStorage) supaya tombol SALIN berfungsi;
   server tidak pernah tahu.

Catatan jujur: mode ini memberi pengunjung kendali atas **repo mereka sendiri**
(termasuk membuat repo + membaca secret-list lewat token mereka). Server hanya
memegang cookie sesi terenkripsi; jangan bagikan `SESSION_SECRET`.

Panel **Tampilan** di dashboard: upload wallpaper (drag & drop, otomatis
dikecilkan maks 1920px), toggle **TranslucentTB** (+mode), **Lightshot**,
**Tweak tampilan Windows 10**, **Label "Windows 10 Pro"**. Perubahan ditulis ke
`assets/rdp-extras.json` di repo → berlaku di sesi **berikutnya** (VM sekali-pakai,
tidak ada yang bisa di-apply live).

---

## 7. Struktur status (branch `status` → `rdp-status.json`)

```json
{
  "active": true,
  "hostname": "xyrdp-7",
  "os": "Microsoft Windows Server 2022 Datacenter", "os_build": "10.0.20348",
  "os_style": "Windows 10 look",
  "rdp_user": "xyadmin", "rdp_port": 3389,
  "rdp_listen": ":::3389 (svchost) | 0.0.0.0:3389 (svchost) + handshake ok via 127.0.0.1",
  "rdp_denyts": true,
  "started_at": "…", "expires_at": "…",
  "akses": {
    "mode": "keduanya",
    "rustdesk": { "status": "ok", "id": "1234567890", "server": "server publik bawaan" },
    "tunnel":   { "status": "ok", "provider": "bore", "host": "bore.pub", "port": 47321,
                  "address": "bore.pub:47321",
                  "rdp_local": "127.0.0.1 -> terbuka",
                  "selftest": "ok",            // handshake RDP X.224 lewat endpoint publik
                  "note2": "Tunnel sudah diuji end-to-end (…)" }
  },
  "xydesk": { "host": "ok", "denyts": "ok", "multisession": "ok", "avc444": "ok",
              "fontsmoothing": "ok (ClearType profil Default)",
              "audio_out": "ok (fDisableAudio=)", "audio_mic": "ok (fDisableAudioCapture=0)",
              "rdp_ready": "127.0.0.1 (handshake OK)",
              "rdp_probe": "awal=True multi=True audio=True grafis=True clear=True fw=True svc=True" },
  "win10": { "look": "ok", "badge": "ok", "wallpaper": "ok", "search": "ok" },
  "extras": { "lightshot": "ok", "translucent": "ok", "wallpaper": "ok",
              "wallpaper_file": "wallpaper-win10.jpg", "admin": true }
}
```
Saat sesi mati: `active=false`, `stopped_at` diisi, dan **ID RustDesk + alamat
tunnel dikosongkan** dari file publik (tidak ada endpoint nyangkut di branch
`status`). Password **tidak pernah** masuk log/commit/file status.

---

## 8. Batas & risiko yang wajib tahu

- ⚠️ **ToS GitHub**: Actions untuk build/test, bukan VPS interaktif — RDP 6 jam-an
  berisiko **suspend akun**. Jangan pakai akun utama.
- **Kuota**: runner Windows dihitung 2×. Free plan 2000 menit/bulan ⇒ ≈2 sesi 6 jam.
- **6 jam** batas keras runner hosted: `timeout-minutes: 360` + loop berhenti di
  menit ~354 supaya cleanup rapi.
- **RustDesk publik**: relay pihak ketiga (gratis, tanpa jaminan). Kalau sedang
  down/lambat, ID tidak muncul → pakai jalur tunnel, atau set `rd_server`.
- **bore.pub**: server publik komunitas, port acak, tanpa jaminan uptime; kalau
  gagal membuat tunnel, jalur RustDesk tetap jalan (dan sebaliknya).
- **Login Google di dalam VM**: VM sekali-pakai + IP datacenter (Azure) = selalu
  dianggap perangkat asing → verifikasi HP/SMS bisa muncul. Tidak ada tweak yang
  menghapus itu (dulu bisa "disiasati" pakai Tailscale exit node; sekarang tidak).
- VM sekali-pakai: apa pun di `C:\` hilang setelah job selesai. Simpan data ke
  Google Drive/OneDrive lewat browser di dalam VM.
- Runner **`windows-2022`** masih didukung, tapi jangan kaget kalau suatu saat
  di-deprecate — kalau itu terjadi, ganti `runs-on` ke image Server terbaru dan
  tweak di `setup-win10.ps1` tetap relevan (tampilan jadi mirip Windows 11).

---

## 9. Troubleshooting

| Gejala | Penyebab / solusi |
|---|---|
| `ERROR: secret RDP_PASSWORD …` | Secret belum diset / kurang dari 8 karakter |
| RustDesk ID kosong di dashboard | Service RustDesk belum register ke server publik. Cek log step **Setup akses**; coba sesi berikutnya, atau isi `rd_server` |
| Tidak bisa konek RustDesk | Pastikan klienmu memakai server yang sama (default = publik). Kalau kamu set `RD_SERVER`, klienmu juga harus diarahkan ke server itu |
| Tunnel tidak muncul | bore.pub sedang sibuk, atau token ngrok salah/kosong. Provider `otomatis` mencoba ngrok lalu bore. Kalau `ngrok` dipilih tapi token kosong, jalur ini dilewati |
| Step "Setup akses" lama sekali | Sudah dikasih timeout keras (installer RustDesk 420s, winget 300s, ambil ID 12×25s, tunnel 90s) + `timeout-minutes` per step. Kalau RustDesk gagal, script lanjut ke tunnel — sesi tidak pernah nyangkut |
| `mstsc` menolak konek | Pakai alamat **persis** `host:port` dari dashboard; tunnel hidup hanya selama sesi |
| Taskbar tidak translucent | Efek native tetap aktif; TranslucentTB portable butuh Windows 10/11 — kalau gagal, ganti mode via tray icon |
| Label "Windows 10 Pro" | Kosmetik (registry). `winver`/About bisa tetap menampilkan nama Server — branding Windows di folder `branding` milik TrustedInstaller, tidak diubah |
| Log `butuh secret CLEANUP_TOKEN` | Tanpa PAT scope `repo`, run lama tidak bisa dihapus (GITHUB_TOKEN Actions cuma `actions:read`) |
| Funnel Tailscale, bisa dipakai mstsc/XyDesk? | **Tidak.** Sisi publik funnel selalu TLS; klien RDP mentah (X.224) langsung ditutup relay (0 byte). Pakai **IP `100.x`** (app Tailscale) atau **ngrok TCP** |
| XyDesk: teks di sesi tampak pecah | Pastikan skala Windows **100%** (klien v0.5.30 default 100%) dan `xydesk=ya` (font smoothing aktif); cek log step "Host setup XyDesk" |
| XyDesk: tidak ada suara dari PC | Lewat tunnel TCP, audio lewat kanal RDP biasa — pastikan `Audiosrv` jalan (dicek di setup-xydesk) dan audio tidak di-mute di klien. QUIC UDP 4433 hanya untuk LAN/jalur UDP |
| XyDesk: "Direct QUIC" tidak aktif | Wajar di jalur tunnel (UDP 4433 tidak lewat relay TCP) — sesi tetap jalan lewat RDP; QUIC hanya untuk Koneksi PC (ID) yang masih Experimental |
| XyDesk: sertifikat RDP ditanya | Terima saja — VM sekali-pakai, sertifikatnya dibuat ulang tiap sesi |
| **HP: "koneksi ditolak / ditutup" padahal VM jalan** | 99% karena **alamat tunnel milik sesi lain**: port berganti setiap sesi baru. Pastikan sesi berstatus **AKTIF** dan alamat dibaca **dari dashboard/status sesi yang sedang jalan** (baris peringatan di dashboard berbunyi "✅ Alamat ini segar dari sesi …"). Sesudah menekan **Stop**, alamat lama **tidak berlaku lagi** |
| Dashboard menampilkan alamat lama | Sudah diperbaiki: status dibaca via Contents API (selalu segar), bukan CDN raw yang bisa tertinggal ±5 menit |
| **Tunnel "selftest ok" tapi HP tetap "connection refused"** | Temuan 3 Okt 2026: bore.pub **menerima** koneksi dari dalam VM tetapi **menolak** dari internet (6/8 node luar gagal; diuji dengan `tools/cek-tunnel.py`). Karena itu sekarang ada **verifikasi dari luar** (`akses.tunnel.outside`) dan bila gagal, XyRDP otomatis pindah provider. Urutan otomatis: **ngrok (kalau ada token) → pinggy → bore** |
| Address pinggy berubah tiap ~60 menit | Wajar: tier gratis pinggy berbatas 60 menit. Keepalive memperpanjang otomatis tiap ~50 menit dan **alamatnya berganti** (dashboard selalu menampilkan yang terbaru). Untuk 6 jam tanpa ganti alamat: set secret **`NGROK_AUTHTOKEN`** (akun gratis ngrok) dan pakai `tunnel_provider=ngrok` |
| Tunnel "hidup" tapi klien tidak bisa masuk (`selftest: gagal`) | Cek `akses.tunnel.note2` + `rdp_local` di dashboard. Script sudah menunggu RDP benar-benar menjawab handshake X.224 sebelum mengarahkan tunnel, dan mencoba ulang sekali dengan target terbaru. Kalau tetap gagal, pakai jalur RustDesk untuk sesi itu |
| `rdp_probe` ada yang `False` | Salah satu tweak XyDesk merusak listener 3389. Nilai yang benar semuanya `True`; kalau ada `False`, kirim log step "Host setup XyDesk" — probe per fase menunjuk fase persisnya |
| Kenapa `audio_out` cuma `ok (fDisableAudio=)` | Artinya nilai itu **tidak ada** di image (= default Windows: audio aktif). XyRDP sengaja **tidak menulis** kunci `WinStations\RDP-Tcp` (lihat §10) |

---

## 10. Kenapa XyRDP tidak menyentuh `WinStations\RDP-Tcp` (temuan uji 3 Okt 2026)

Uji berulang di runner GitHub-hosted `windows-2022` menunjukkan hal yang tidak
kelihatan dari dokumentasi: **menulis nilai di**

```
HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
```

(`fDisableAudio`, `fDisableAudioCapture`, `fNoFontSmoothing`, `AllowFontAntiAlias`
— persis yang dipakai skrip host XyDesk umum) memaksa TermService **membangun ulang
listener RDP**, dan di runner GitHub listener itu **tidak kembali sehat** — port
3389 berhenti melayani, handshake X.224 tidak pernah dibalas, dan restart
`TermService` **tidak menolong**. Akibatnya tunnel "hidup" tapi tidak tembus.

Karena itu di v2:

- kunci itu **hanya dibaca** (audit) dan nilainya dilaporkan apa adanya di status;
- **ClearType** dipasang lewat **profil Default** (`FontSmoothing=2`,
  `FontSmoothingType=2` di `HKCU\Control Panel\Desktop`) — efek teks tajam untuk
  klien XyDesk tanpa menyentuh kunci WinStation;
- **audio capture** lewat kunci **kebijakan** (`fDisableAudioCapture=0`);
- setiap fase tweak diakhiri **probe handshake X.224** (`rdp_probe`), jadi kalau
  ada regresi langsung kelihatan fase mana penyebabnya.

### Uji dari LUAR, bukan cuma dari VM (pelajaran 3 Okt 2026)

Ternyata "selftest ok" **tidak cukup**: pada sesi #49, `bore.pub:51782` menjawab
handshake RDP X.224 dari dalam VM, tetapi dari internet port itu **ditolak**:

```
cek-tunnel.py bore.pub:51782  ->  0-1/8 node luar tersambung (connection refused)
cek-tunnel.py portquiz.net:51782 (kontrol)      ->  8/8 tersambung
cek-tunnel.py pinggy (tunnel uji)               ->  8/8 tersambung (termasuk Asia)
```

Karena itu v2 sekarang: (1) menguji alamat tunnel dari node luar sebelum
mengumumkannya (`akses.tunnel.outside`), (2) memindahkan provider otomatis bila
tidak terbukti, dan (3) memakai **pinggy** sebagai jalur pertama (tanpa akun,
terbukti 8/8 dari node luar).

### Bukti uji (run nyata, 3 Okt 2026)

```
rdp_listen : :::3389 (svchost) | 0.0.0.0:3389 (svchost) + handshake ok via 127.0.0.1
rdp_probe  : awal=True multi=True audio=True grafis=True clear=True fw=True svc=True
rdp_ready  : 127.0.0.1 (handshake OK)
tunnel     : bore.pub:35570  selftest=ok  (X.224 Connection Confirm lewat endpoint publik)
rustdesk   : id 226636470, service jalan
```

Self-test tunnel dilakukan **dari dalam VM ke endpoint publik lalu kembali ke
port 3389** — itu jalur yang sama dengan klienmu di HP. (Kalau kamu ingin
memastikan sendiri: buka XyDesk Remote → **Koneksi RDP Penuh** → Host/Port dari
dashboard → login `xyadmin`.)
