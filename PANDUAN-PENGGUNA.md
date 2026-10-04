# XyRDP — panduan untuk pengguna (orang lain yang mau ikut pakai)

Dashboard: **https://xyrdp-dash.vercel.app** — semua sesi RDP kamu jalan di
**repo GitHub milikmu sendiri**. Pemilik dashboard tidak bisa melihat token,
secret, atau sesi RDP-mu.

## 1. Masuk & bikin repo kerja

1. Buka dashboard → **Masuk dengan GitHub** → *Authorize*.
   (Minta izin scope `repo` supaya bisa membuat repo & menjalankan Actions-mu.)
2. Di panel **Repo kamu**, klik **BUAT REPO DARI TEMPLATE**.
   - Repo `<username-mu>/XyRDP` dibuat (kopi dari template), izin Actions dirapikan otomatis.
   - Pilih **Publik** supaya menit Actions gratis **tanpa batas** (privat = kuota 2000 menit/bulan).

## 2. Isi 2 secret (wajib) — hanya ini

Tombol **BUKA SECRETS** membawa ke `Settings → Secrets and variables → Actions`
di repo kamu. Tambahkan *New repository secret*:

| Secret | Isi apa |
|---|---|
| `RDP_PASSWORD` | kata sandi login RDP sesi-mu (bebas, tapi kuat — ini sandi administrator VM) |
| `TAILSCALE_AUTH_KEY` | auth key dari **akun Tailscale-mu**: admin console → **Settings → Keys → Generate auth key** → pilih **Reusable** + *Ephemeral* (opsional) |

Opsional:

| Secret | Isi apa |
|---|---|
| `NGROK_AUTHTOKEN` | kalau mau pakai ngrok sebagai jalur tunnel (akun gratis ngrok) |
| `CLEANUP_TOKEN` | PAT scope `repo` milikmu, untuk hapus run lama otomatis |

## 3. Nyalakan sesi

1. Kembali ke dashboard → **PERIKSA / RAPIKKAN LAGI** (sampai pill jadi **siap**).
2. Atur durasi, jalur akses (**Tailscale** direkomendasikan), lalu **NYALAKAN**.
   VM siap ±3–5 menit; status berubah **AKTIF**.
3. Di HP: pasang app **Tailscale** → login akun yang sama → buka klien
   **XyDesk Remote** → **Koneksi RDP Penuh** → Host = **IP `100.x`** dari baris
   Tailscale di dashboard, Port = **3389**, user **`xyadmin`** + `RDP_PASSWORD`-mu.
4. Tombol **MATIKAN** menghentikan VM kapan saja; tanpa itu VM mati sendiri
   setelah durasi habis.

## Hal yang perlu kamu tahu

- **Ini VM sementara.** Setiap sesi = VM baru dari nol: file yang kamu simpan
  di dalam hilang saat sesi berakhir (kecuali kamu upload sendiri ke
  cloud/Drive). Kata sandi, wallpaper, dan setelan ekstra tetap karena
  tersimpan di repo/secret-mu.
- **Repo kamu = kendali sesi.** Kalau Actions di repo itu dimatikan atau
  workflow diubah, sesi ikut berhenti.
- **Grafis = software (CPU).** Runner GitHub tidak punya GPU fisik; Mesa
  llvmpipe/lavapipe dipasang supaya aplikasi yang butuh OpenGL/Vulkan bisa
  jalan. 3D berat & render video tetap lambat.
- **Kuota.** Repo publik: menit Actions gratis tanpa batas. Repo privat: 2000
  menit/bulan; satu sesi 6 jam ≈ 360 menit.
- **Jangan pakai untuk hal sensitif.** VM ada di infrastruktur GitHub, dan
  sandi RDP-mu tersimpan sebagai secret di repo-mu (aman, tapi tetap sandi
  sekali-pakai yang tidak kamu pakai di tempat lain).

## Buat key Tailscale (sekali saja)

1. https://login.tailscale.com/admin/settings/keys
2. **Generate auth key** → **Reusable** → (opsional) *Ephemeral* & masa berlaku.
3. Salin `tskey-auth-...` → tempel sebagai secret `TAILSCALE_AUTH_KEY` di repo kamu.

Punya key itu, kamu punya tailnet sendiri — sesi RDP-mu **tidak** lewat akun
Tailscale pemilik dashboard.
