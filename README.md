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
| `scripts/setup-rdp.ps1` | Semua aksi: bikin admin, buka RDP, tweak/unlock, cek reputasi IP |
| `scripts/keepalive.ps1` | Loop penahan sesi + heartbeat tiap 5 menit |
| `scripts/publish-status.ps1` | Tulis `rdp-status.json` ke branch `status` (dibaca web) |
| `scripts/finalize-rdp.ps1` | Logout Tailscale (+hapus device jika ada API token) |
| `web/` | Dashboard lokal (Node, tanpa dependency, bukan GitHub Pages) |

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
   → http://localhost:4173 → tombol **▶ NYALAKAN RDP**.
   (atau manual: Actions → “XyRDP - Windows RDP 6 Jam” → Run workflow)
3. Tunggu ±2–4 menit. Setelah status **LIVE**, dashboard menampilkan **IP Tailscale**.
4. Remote Desktop Connection → alamat `100.x.x.x` → login `xyadmin` + password tetap.
5. Sesi mati sendiri mendekati jam ke-6. Mau mati sekarang? tombol **■ MATIKAN**.

## Akses admin “super penuh” yang di-unlock
- User `xyadmin` ∈ **Administrators** + Remote Desktop Users, password tidak expire
- `LocalAccountTokenFilterPolicy=1` → token admin penuh untuk login jaringan (bisa UAC-elevated remote)
- UAC dimatikan, SmartScreen off, IE ESC off, long path on, sleep/hibernate off
- RDP tanpa prompt NLA/CredSSP (`UserAuthentication=0`) + banner login dihapus → connect langsung masuk
- Auto-logon console aktif (VM ephemeral, registry ikut musnah bersama VM)
- Tailscale terpasang; transfer file bisa pakai Drive/OneDrive dari browser (catatan: `tailscale --ssh` tidak didukung di Windows sejak v1.98+, jadi sengaja tidak diaktifkan)
- Chrome di-tweak: no first-run, no promo tab, no cloud reporting, DoH off

## Jujur soal “IP bagus biar login Google aman tanpa klik”
Yang **bisa** dijamin workflow ini: tweak Windows/Chrome mengurangi dialog
first-run/promo/SmartScreen, dan sesi login kamu **tidak di-sniff siapa pun**
karena trafik lewat tailnet terenkripsi.

Yang **tidak bisa** dijamin siapa pun pada skema ini: reputasi IP di sisi Google.
Runner GitHub = IP **datacenter Microsoft Azure**; Google sering minta
“verifikasi keamanan” untuk akun baru di IP datacenter, sekeren apa pun tweak-nya.
Makanya workflow ini:
1. **mengecek reputasi IP tiap run** (`ip-api`) dan menulisnya ke log + dashboard:
   `CLEAN` (tidak kena flag hosting/proxy) atau `FLAGGED-DATACENTER`;
2. mendukung input **`exit_node`**: jalankan Tailscale di perangkat rumah (HP lama /
   Raspberry Pi / PC) → isi nama node-nya → seluruh trafik Chrome keluar lewat IP
   residential kamu. **Ini satu-satunya cara “terkonfirmasi aman” yang realistis.**
   (Trafik RDP tetap langsung ke VM, yang lewat exit node hanya internet-out.)

Tips tambahan: login ke akun Google yang **sudah lama + ada history** di IP
tersebut, jangan akun baru, jangan ganti-ganti IP di tengah sesi, dan simpan
sesi login (checkbox “tetap login”) biar tidak perlu login ulang tiap sesi 6 jam.

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
