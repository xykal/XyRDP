# PANDUAN FORK XyRDP-SAMP — Step-by-Step Bergambar (Teks)

> File ini versi ringkas dari README, fokus hanya ke **forks setup** biar tidak bingung.

## 1. Fork
1. Login GitHub kamu.
2. Buka https://github.com/xykal/XyRDP (atau link repo mod yang kamu dapat).
3. Klik tombol **Fork** di kanan atas → **Create fork** → tunggu selesai.
4. Sekarang kamu punya `github.com/NAMA_KAMU/XyRDP` (atau `XyRDP-SAMP`).

## 2. Enable Actions
- Di repo hasil fork → klik tab **Actions** → klik **Enable workflows** (hijau).
- Jika tidak di-enable, workflow tidak akan muncul di list.

## 3. Isi Secrets
- Masuk **Settings** (tab repo) → **Secrets and variables** → **Actions** → **New repository secret**.

### Wajib:
- Name: `RDP_PASSWORD` → Value: `PasswordKamu123!` (min 8 char) → Add secret

### Sangat disarankan untuk SAMP & Storage Lega:
- Name: `GTA_SA_URL` → Value: direct link ZIP GTA SA portable kamu
  - Contoh Google Drive: `https://drive.google.com/uc?export=download&id=1a2b3c4d5e`
  - Contoh Dropbox: `https://www.dropbox.com/s/xyz123/gta_sa.zip?dl=1`
  - Kosongkan jika mau upload manual via RDP (bisa juga isi saat Run workflow)

### Opsional (tapi bikin koneksi stabil):
- `NGROK_AUTHTOKEN` → dari ngrok.com
- `TAILSCALE_AUTH_KEY` → dari tailscale.com/admin/settings/keys
- `CLEANUP_TOKEN` → PAT `repo` scope untuk auto hapus log lama

## 4. (Opsional) Edit Config Default
- Buka `assets/rdp-extras.json` → klik pensil ✏️ → ubah:
  ```json
  "storage_boost": true,
  "samp": true,
  "samp_extra": false
  ```
- Commit langsung ke `main`.

## 5. Jalankan RDP
- Tab **Actions** → pilih workflow **XyRDP-SAMP — RDP + GTA SA-MP + Storage Booster** → **Run workflow** →
  - `storage_boost`: `ya`
  - `samp`: `ya`
  - `gta_sa_url`: isi jika belum isi secret (atau kosongkan)
  - `akses`: `keduanya`
  - `grafis`: `software`
- Klik **Run workflow** hijau → tunggu workflow jadi hijau (4-7 menit).

## 6. Ambil Info Koneksi
- Klik workflow run yang hijau → lihat log **Setup akses** → catat **RUSTDESK ID** & **TUNNEL host:port**.
- Atau buka branch `status` → file `rdp-status.json` → lihat `akses.rustdesk.id` & `akses.tunnel.address`.
- Password = isi `RDP_PASSWORD` kamu.

## 7. Konek dari HP/PC
- **RustDesk:** ID + Password → Connect
- **mstsc / XyDesk Remote:** Host = `bore.pub:PORT` atau `x.tcp.ngrok.io:PORT` + User `xyadmin` + Password

## 8. Main SAMP
- Di Desktop RDP cari **GTA SAMP.lnk** → double klik → add server IP → Connect.
- Jika GTA belum ada: ikuti `CARA-PASANG-GTA.txt` di Desktop → copy GTA ke `C:\Games\GTA San Andreas`.

## 9. Matikan / Perpanjang
- Workflow otomatis mati setelah durasi habis (max 360 menit). Untuk perpanjang, Run workflow lagi.
- Jangan spam run tiap detik — GitHub rate limit. Jeda 1-2 menit antar run.

## 10. Troubleshooting Cepat
- Workflow merah di `setup-rdp` → cek `RDP_PASSWORD` belum diisi / terlalu pendek.
- SAMP status `partial` → cek log `🎮 Setup GTA SAMP` → GTA belum ada → upload manual.
- Tunnel `outside=gagal` → pakai RustDesk ID saja (lebih andal).
- Storage masih 70GB → pastikan input `storage_boost=ya` (bukan `tidak`).

Selesai — selamat main! 🎮
