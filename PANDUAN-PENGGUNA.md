# XyRDP — panduan pengguna

**Dashboard:** [xyrdp-dash.vercel.app](https://xyrdp-dash.vercel.app)

**Panduan visual interaktif:** [xyrdp-dash.vercel.app/panduan](https://xyrdp-dash.vercel.app/panduan)

Sesi RDP kamu berjalan di **repo GitHub milikmu sendiri**. Pemilik dashboard tidak menjalankan sesi di repo pribadinya untuk pengguna lain.

## 1. Login dan buat repo

1. Buka dashboard, lalu tekan **Masuk dengan GitHub**.
2. Setujui akses GitHub setelah membaca halaman izin.
3. Di panel **Repo kamu**, pilih nama serta visibilitas repo, lalu tekan **BUAT REPO DARI TEMPLATE**.
4. Repo baru akan muncul di akunmu, misalnya `<username>/XyRDP`.

## 2. Isi dua secret wajib

Tekan **BUKA SECRETS** untuk membuka pengaturan repo. Masuk ke `Settings → Secrets and variables → Actions` lalu tambahkan:

| Nama secret | Nilai |
|---|---|
| `RDP_PASSWORD` | Kata sandi unik untuk login desktop RDP. Disarankan minimal 16 karakter ASCII, campuran huruf besar/kecil, angka, dan simbol sederhana. Jangan gunakan sandi GitHub/email. |
| `TAILSCALE_AUTH_KEY` | Auth key dari akun Tailscale-mu. Buat lewat **Admin Console → Settings → Keys**; reusable diperlukan untuk alur ini dan ephemeral disarankan jika tersedia. |

Secret opsional:

| Nama | Kegunaan |
|---|---|
| `NGROK_AUTHTOKEN` | Tunnel RDP melalui akun ngrok |
| `CLEANUP_TOKEN` | Menghapus run Actions lama secara otomatis |

**Jangan kirim nilai secret melalui chat, issue publik, screenshot, atau commit.** Isikan langsung di GitHub. Dashboard hanya memeriksa nama secret.

## 3. Nyalakan sesi

1. Kembali ke dashboard dan tekan **PERIKSA / RAPIKKAN LAGI** sampai repo berstatus **siap**.
2. Di panel **Tampilan**, atur username RDP default dan editor opsional. Username disimpan di repo dan berlaku untuk sesi baru (3–20 karakter ASCII; huruf/angka di awal, lalu huruf, angka, `_` atau `-`).
3. Pilih durasi dan jalur. Untuk HP, gunakan **Tailscale**.
4. Tekan **NYALAKAN** sekali. Tunggu beberapa menit sampai status dashboard berubah menjadi **AKTIF**.
5. Di HP, buka Tailscale dan login ke akun yang membuat auth key.
6. Buka **XyDesk Remote → Koneksi RDP Penuh**:
   - Host: IP `100.x` terbaru dari dashboard.
   - Port: `3389`.
   - User: username yang tampil di dashboard (default `xyadmin`).
   - Password: nilai secret `RDP_PASSWORD` yang kamu masukkan sendiri.

Jangan gunakan IP dari sesi lama: alamat berubah saat sesi baru dimulai.

## 4. Wallpaper dan tampilan

Wallpaper bawaan XyCloud sudah tertanam di repo template (`assets/wallpaper.jpg` dan `assets/wallpaper-win10.jpg`). Workflow menerapkannya ke desktop sesi serta latar login. Perubahan wallpaper melalui panel **Tampilan** dashboard berlaku pada sesi berikutnya. Tema gelap dan transparansi taskbar aktif secara default; opsi profil ringan hanya menonaktifkan layanan cache/telemetri non-esensial jika tersedia.

## 5. Coding dan aplikasi opsional

Image `windows-2022` sudah menyediakan Git, Node.js, Python, 7-Zip, .NET, Java, Visual Studio 2022, CMake, GCC/GDB. VS Code dan Notepad++ dapat dipilih di dashboard sebelum sesi berjalan; keduanya default tidak dipasang agar startup tetap ringan. Pengaturan berlaku pada sesi baru.

## 6. Batasan dan keamanan

- Ini **Windows Server 2022 dengan tampilan Windows 10-style**, bukan Windows 10 desktop asli.
- Runner GitHub-hosted bersifat sementara; file lokal dapat hilang ketika sesi selesai. Simpan file penting di penyimpanan milikmu sendiri.
- RAM standar runner ditentukan GitHub dan tidak bisa dinaikkan lewat script; dashboard menampilkan snapshot RAM akhir setup, bukan angka live. Lihat [spesifikasi runner GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- GPU software (Mesa llvmpipe/lavapipe) memakai CPU; tidak ada GPU fisik. Aplikasi 2D/sebagian game ringan mungkin berjalan, tetapi game 3D tidak dijamin.
- Satu sesi dapat berjalan maksimal 6 jam dan berhenti otomatis. Gunakan **MATIKAN** setelah selesai.
- Workflow memeriksa bahwa pemicu adalah pemilik repo sebelum job runner dijalankan. Kolaborator non-pemilik tidak dapat memulai job RDP.
- Kuota dan penggunaan gratis mengikuti plan/kebijakan GitHub dan layanan terkait. Periksa ketentuan akunmu.
- Repo dari template adalah salinan mandiri; update baru di template tidak otomatis muncul di repo yang sudah dibuat.
- Hindari menyimpan data rahasia di VM sementara dan gunakan sandi RDP khusus, bukan sandi yang dipakai di layanan lain.

## Komunitas

- [Join Saluran XyVerse Technology Global di WhatsApp](https://whatsapp.com/channel/0029VbB7nwuJZg3ym6UQ4Z1L)
- [Gabung Grup XyCloud di WhatsApp](https://chat.whatsapp.com/DpROBXmeUHJGcXecfxP6n7?s=cl&p=a&ilr=2&amv=0)
- [Kembali ke dashboard](https://xyrdp-dash.vercel.app)
