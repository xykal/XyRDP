# XyRDP — Windows RDP 6 Jam via GitHub Actions + Tailscale

RDP Windows Server **gratis** pakai runner `windows-latest` GitHub Actions,
diakses lewat **Tailscale** (tidak ada port publik), sesi ditahan **pas 6 jam**
(batas keras job GitHub), lalu VM musnah sendiri.

```
[Kamu] --Tailscale(100.x.x.x)--> [Windows Server 2022 @ GitHub runner] <--diatur-- workflow rdp-6h.yml
                                      └─ RDP :3389, user xyadmin (admin penuh)
```

## Isi repo
| Path | Fungsi |
|---|---|
| `.github/workflows/rdp-6h.yml` | Workflow utama: boot VM, setup RDP, join Tailscale, tahan 6 jam |
| `scripts/setup-rdp.ps1` | MODE BERSIH: bikin admin, buka RDP, join Tailscale (tanpa tweak lain) |
| `scripts/keepalive.ps1` | Loop penahan sesi + heartbeat tiap 5 menit |
| `scripts/publish-status.ps1` | Tulis `rdp-status.json` ke branch `status` (dibaca web) |
| `scripts/finalize-rdp.ps1` | Logout Tailscale (+hapus device jika ada API token) |
| `web/` | Dashboard lokal (Node, tanpa dependency) |
| `deploy/vercel/` | Versi dashboard untuk hosting di Vercel (catch-all function + Basic Auth) |

## Dashboard Vercel (produksi)
URL produksi: **https://xyrdp-dash.vercel.app** — halaman terbuka tanpa login; SEMUA endpoint API butuh sesi.
Login lewat form di web (custom, tanpa dialog browser); cookie `sid` HttpOnly 7 hari. Header `Authorization: Basic`
tetap diterima sebagai fallback untuk curl/skrip. Kredensial dari env `AUTH_USER` / `AUTH_PASS` (bukan dari repo).
UI: tanpa emoji, tanpa alert/confirm bawaan browser; stop sesi pakai tombol konfirmasi dua-klik.

Env vars yang dipakai project `xyrdp-dash` (set via dashboard Vercel → Settings → Environment Variables, atau API):

| Key | Type | Isi |
|---|---|---|
| `GITHUB_TOKEN` | sensitive | PAT dengan scope `repo` (buat dispatch/cancel/read logs) |
| `RDP_PASSWORD` | sensitive | password tetap RDP (sama dgn secret Actions) |
| `AUTH_USER` / `AUTH_PASS` | plain/sensitive | login Basic Auth web |
| `GH_OWNER` `GH_REPO` `GH_WORKFLOW` `GH_BRANCH` `RDP_USER` | plain | `xykal` `XyRDP` `rdp-6h.yml` `main` `xyadmin` |

Redeploy setelah ubah kode:
```bash
cd deploy/vercel && npx vercel deploy --prod --yes --token <VercelToken>
```
Config penting: `vercel.json` pakai `routes` legacy `/(.*) -> /api/index.js` supaya semua path lewat function (auth cookie dipegang aplikasi, bukan popup browser), dan `includeFiles: assets/**` supaya `index.html` ikut ke-bundle ke function.

## Secrets repo (sudah dipasang)
- `RDP_PASSWORD` — password **tetap** untuk user `xyadmin`
- `TAILSCALE_AUTH_KEY` — auth key tailnet (harus `tskey-auth-...`)
- `TAILSCALE_API_TOKEN` — *opsional*, kalau mau device otomatis dihapus dari admin console

Password RDP **tidak pernah** muncul di log, commit, atau file status — hanya
disimpan lokal di `web/config.json`.

## Cara pakai
1. Install **Tailscale** di PC/HP kamu, login ke **tailnet yang sama** dengan auth key di atas.
2. Buka dashboard:
   ```bash
   cd web && node server.js      # butuh Node >= 18, tidak perlu npm install
   ```
   → http://localhost:4173 → tombol **NYALAKAN RDP**.
   (atau manual: Actions → “XyRDP - Windows RDP 6 Jam” → Run workflow)
3. Tunggu ±2–4 menit. Setelah status **LIVE**, dashboard menampilkan **IP Tailscale**.
4. Remote Desktop Connection → alamat `100.x.x.x` → login `xyadmin` + password tetap.
5. Sesi mati sendiri mendekati jam ke-6. Mau mati sekarang? tombol **MATIKAN**.

## Mode bersih (default sekarang)
Session = Windows Server **apa adanya**. Yang dilakukan script HANYA:
- Buat user `xyadmin` ∈ **Administrators** + Remote Desktop Users (password tetap, tidak expire)
- `LocalAccountTokenFilterPolicy=1` → supaya login jaringan dapat token admin penuh (ini bagian dari “akses admin”, bukan tweak)
- Aktifkan Remote Desktop port 3389 dengan setting default Windows (NLA ON) + rule firewall grup “Remote Desktop”
- Install + join Tailscale, tulis status

Tidak ada lagi: tweak UAC/Defender/SmartScreen/Chrome/auto-logon, dan cek reputasi IP sudah dihapus.
Semua itu justru menambah variabel; sesuai request, balik ke vanilla.

## Login Google dari dalam RDP — fakta jujurnya
Google menantang login berdasarkan **perangkat baru + IP datacenter (Azure)**,
bukan karena setting di Windows. VM-nya sekali-pakai, jadi tiap sesi = “perangkat
asing” di mata Google dan prompt verifikasi (notif HP / telepon / SMS) bisa muncul
kapan pun; tidak ada tweak yang bisa menghapus itu.

Yang tetap didukung kalau mau IP keluar yang “bersih”: input `exit_node`
(Advanced, isi manual lewat Actions UI) — jalankan Tailscale di perangkat rumah
lalu advertise exit node; trafik Chrome keluar dari IP residential.

## Batas & risiko yang wajib tahu
- ⚠️ **ToS GitHub**: Actions diperuntukkan build/test, bukan VPS interaktif.
  Suka tidak suka, RDP-an 6 jam-an punya risiko **suspend akun** (public repo +
  tidak agresif menekan risiko, tapi tidak menghilangkan). Jangan pakai akun utama.
- **Kuota**: Windows runner dihitung 2×. Free plan 2000 menit/bulan ⇒ ≈2 sesi 6 jam.
- **6 jam** adalah batas keras runner hosted — tidak bisa lebih; `timeout-minutes: 360`
  + loop berhenti di menit ~354 supaya cleanup rapi (status menjadi `inactive`).
- Repo sengaja **public** (sesuai preferensi untuk hindari suspend). Tidak ada
  rahasia apa pun yang di-commit: token hidup di Secrets + config lokal.
- Ini VM sekali-pakai: apa pun di `C:\` hilang setelah job selesai. Simpan data
  ke Google Drive/OneDrive lewat browser.

## Struktur status (branch `status` → `rdp-status.json`)
```json
{ "active": true, "tailscale_ip": "100.x.y.z", "tailscale_dns": "xyrdp-12.tailnet.ts.net",
  "rdp_user": "xyadmin", "started_at": "...", "expires_at": "...", "public_ip": "20.x...", "ip_note": "..." }
```
Web mem-poll file ini + status run; tidak ada server perantara yang di-hosting.

## Troubleshooting
| Gejala | Penyebab umum |
|---|---|
| `ERROR: secret RDP_PASSWORD/TAILSCALE_AUTH_KEY` | Secrets belum diset / nama salah |
| `tidak dapat IP Tailscale` | Auth key kadaluarsa/revoked, atau tailnet butuh “add devices manually”. Buat key baru (recommend centang **Ephemeral** + **Reusable**) |
| RDP connect ditolak | Pastikan Tailscale di perangkatmu login ke tailnet yang sama (`tailscale status` harus melihat `xyrdp-*`) |
| Google tetap minta verifikasi | Wajar untuk IP datacenter — pakai `exit_node` |
| Run kedua “menggantung” | Sengaja: `concurrency` mengantrekan agar tidak 2 VM sekaligus |
