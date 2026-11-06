# RdpFree

Dashboard: **https://rdpfree.projectkal.my.id** · Credit: **KallAncrit**

Windows RDP melalui **Tailscale privat**, dengan dashboard Next.js/Cloudflare dan integrasi API native XyDesk Remote. Tidak ada Pinggy, bore, ngrok, Serveo, localhost.run, Funnel, atau relay publik pada workflow aktif.

## Mulai

1. Login identitas GitHub di `/login` (scope `read:user`). Login tidak memberikan akses repository.
2. Pasang GitHub App secara terpisah di `/dashboard/connection`, pilih repository yang diizinkan. Owner layanan harus mendaftarkan App dahulu di halaman admin tersembunyi `/admin/github-app`.
3. Buat repository dari template dengan nama pilihanmu. Token operasi biasa hanya mendapat Contents/Metadata read, Actions/Secrets write. Manifest baru juga meminta Administration write untuk fitur hapus repo setelah konfirmasi pemilik; token hak hapus dibuat terpisah. App tetap tidak dapat menulis atau membersihkan folder source. Template manual tetap menyalin folder web.
4. Isi `RDP_PASSWORD` dan `TAILSCALE_AUTH_KEY` lewat Setup. Hubungkan HP ke tailnet yang sama. Jangan membagikan auth key atau password.
5. Atur sesi di Settings, jalankan dari Home. Password tidak dicetak, di-Base64, atau dijadikan artefak workflow. Reveal/copy tetap melalui vault dashboard yang terautentikasi.

`xyadmin` adalah username default; `runneradmin` hanya bila dipilih eksplisit. Workflow mengubah kebijakan Windows termasuk UAC dan akun administrator. Gunakan mesin khusus/disposable, **bukan komputer kerja utama**. Durasi job maksimal 360 menit termasuk setup; waktu persiapan mengurangi sisa sesi. Sesi GitHub-hosted bukan layanan PC gaming dan tidak ada jaminan bebas suspend.

## Games dan media

Halaman `/dashboard/games` menyimpan pilihan persiapan SA-MP, Roblox, Minecraft Java dan Bedrock serta menampilkan status Windows pada sesi aktif. Pengaturan berlaku pada run berikutnya. Start/stop yang tersedia saat ini adalah **sesi workflow**, bukan proses game di desktop. Login, pemasangan interaktif, launch, dan stop game dilakukan lewat XyDesk. **Kontrol proses game langsung dari dashboard belum tersedia.**

Persiapan game hanya berjalan pada runner Windows self-hosted khusus milikmu, berlabel `self-hosted`, `Windows`, `X64`, `rdpfree`. Jangan izinkan workflow/PR dari pihak tidak tepercaya memakai runner ini. Finalize memutus Tailscale, tetapi tidak menghapus akun, aplikasi, atau perubahan sistem pada mesin self-hosted; reset image setelah pemakaian.

- **SA-MP**: membutuhkan GTA SA milikmu. Installer/dependensi atau keberadaan EXE bukan bukti berhasil masuk server. GTA SA yang sudah terpasang dicerminkan ke `C:\Persist` supaya sesi berikutnya tidak mengunduh ulang.
- **Runtime aplikasi**: VC++ 2005-2022, DirectX June 2010, dan .NET 3.5 dipasang otomatis (`scripts/setup-runtimes.ps1`) supaya aplikasi bisa dibuka pada percobaan pertama. VS Code/Notepad++ memakai rantai fallback winget → Chocolatey → installer resmi bila salah satunya tidak tersedia.
- **Roblox**: installer resmi dengan signature diverifikasi. VM dapat ditolak Roblox. Tidak ada spoofing BIOS, penghapusan driver VM, atau bypass anti-cheat.
- **Minecraft Java**: launcher resmi, akun berlisensi dan dukungan OpenGL/GPU tetap diperlukan.
- **Minecraft Bedrock**: Windows desktop dengan Store/Xbox. Windows Server tidak didukung oleh setup ini. Instalasi dan login Store tetap interaktif.
- **Wallpaper**: wallpaper anime XyVerse asli dari assets/wallpaper.jpg diterapkan pada profil pengguna saat logon, bukan hanya HKCU milik runner. Wallpaper otomatis aktif tanpa pilihan ya/tidak atau URL pengganti. Klien juga harus mengaktifkan desktop wallpaper.
- **Mikrofon**: host mengizinkan kanal audio capture RDP; XyDesk harus mengaktifkan input dan meminta izin Android. Uji Windows Settings > Sound > Input. Perangkat bernama “Remote Audio” pada **Input** adalah recording, berbeda dari output speaker.

Status `installer_ready`, `installed_unverified`, `store_required`, `unsupported_environment`, dan `requires_self_hosted` bukan klaim berhasil bermain. Wallpaper/mikrofon dan game belum lulus pengujian Windows + perangkat Android end-to-end.

## Update repository lama

Workflow baru bertanda `# rdpfree-workflow-schema: 3`. Dashboard menolak dispatch ke workflow lama agar parameter game/media baru tidak salah dikirim. Sinkronkan `.github/workflows/rdp-6h.yml`, seluruh `scripts/`, dan `assets/` dari repository ini. GitHub App tidak punya izin menulis source, jadi pembaruan dilakukan pemilik repository. Pengaturan tersimpan `tunnel`/`semua` dimigrasikan ke Tailscale; SA-MP default lama dinonaktifkan sampai pemilik memilih mesin khusus secara eksplisit.

## Source dan akses

- `.github/workflows/rdp-6h.yml`: Windows session + persiapan host.
- `scripts/`: skrip Windows; `assets/`: wallpaper dan konfigurasi.
- `web-next/`: dashboard Next.js/OpenNext/Cloudflare aktif. Folder `deploy/` (konfigurasi Vercel) dan dokumentasi lama adalah arsip; kode tunnel lama (`railway-frp/`, `relay-panel/`, `web/`, `setup-public-tunnel.ps1`) sudah dihapus — tunnel hanya Tailscale.
- Admin tetap tersembunyi, login email/password + Turnstile; tidak dipindah ke GitHub login.
- Native API: lihat `web-next/docs/XYDESK-API.md`. Token terikat repository dan dapat dicabut. Token OAuth native lama perlu dibuat ulang setelah pemisahan App.
- Login terpisah tidak mencegah suspend. Untuk akun tester yang ditangguhkan, review hanya melalui GitHub Support; penyebab tidak dapat disimpulkan dari 404 atau pola login saja.

## Validasi

Lint, TypeScript, build OpenNext, unit tests dan browser mobile smoke tersedia/diuji. Skrip PowerShell diparse dengan PowerShell 7; parser bukan pengujian instalasi Windows. Tes UI game memakai mock API tanpa menyalakan runner atau game. Instalasi App nyata memerlukan persetujuan owner. Jangan menganggap hasil-hasil ini sebagai sertifikasi kompatibilitas game atau audio end-to-end.


## Panduan repo dan hapus lewat dashboard

Alur: buat repo dari template dahulu → konfirmasi “Repo saya sudah dibuat” → izinkan akses repository melalui GitHub App (Only select repositories) → pilih repo → isi secrets → mulai sesi. Install App berarti otorisasi, bukan membuat repo atau mengunduh aplikasi HP.

Hapus repo tersedia di `/dashboard/connection`, khusus login GitHub pemilik repo pribadi. Ketik nama lengkap `owner/repo` dan setujui dampak penghapusan; workflow aktif/antre harus berhenti. Repo sumber layanan dilindungi dan token XyDesk tidak dapat menghapus. App yang sudah terdaftar perlu Administration: Read and write dan persetujuan pembaruan dari pemilik instalasi. Izin Administration lebih luas daripada delete-only; GitHub tidak menyediakan scope hapus khusus untuk installation token. Token biasa tetap tanpa Administration. Pengujian destructive menggunakan mock, bukan menghapus repo pengguna.
