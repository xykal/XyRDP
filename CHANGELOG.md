# Changelog XyRDP

## 2026-11-13 (update #3) — Modul Native (C/C++/C#/Rust), XyMac OS Launcher, WinRAR, Studio 3D & SEO Founder
- **Modul Native XyRDP (`native/`)**:
  - **Rust (`native/xyrdp-probe`)**: probe handshake RDP X.224 (`0xE0` → `0xD0`) + validator CGNAT Tailscale (`100.64.0.0/10`) & reporter JSON.
  - **C11 (`native/xyrdp-booster`)**: pengunci timer multimedia 1ms (`NtSetTimerResolution` / `timeBeginPeriod`) untuk kelancaran frame pacing DWM 60Hz + pemangkas RAM working-set latar.
  - **C++17 (`native/xyrdp-grafis-check`)**: auditor kesiapan Direct3D 11/12, DirectX Juni 2010, Mesa3D OpenGL 4.6, dan aplikasi Studio.
  - **C# (`native/XyMacLauncher`)**: launcher desktop bergaya macOS (`XyMacLauncher.exe`) dengan **Frosted Pill Dock**, **Top Menu Bar** (`⌘ XyOS`, Finder, Launchpad, Downloads, Terminal, status Tailscale live, jam), **Launchpad overlay**, serta tombol 1-klik kembali ke Taskbar Windows (`mac_launcher=ya` untuk auto-start saat login).
- **WinRAR 7.23 x64** ditambahkan ke `scripts/setup-extras.ps1` (verifikasi SHA-256 resmi + fallback winget + shortcut Desktop).
- **Studio 3D & Utilitas (`scripts/setup-studio-3d.ps1`, input `studio_tools=ya`)**: **Blender 3D 4.2 LTS** (dengan injeksi otomatis Mesa3D OpenGL 4.6 `llvmpipe`) dan **Roblox Studio resmi (`WindowsStudio64`)** (murni IDE kreator bebas kendala Hyper-V, bukan game Roblox Player) beserta utilitas pendukung **WebView2 Runtime** & **FFmpeg CLI**.
- **Perbaikan kritis Auto-Renew (`rdp-6h.yml`)**: menghapus pengiriman string kosong `""` pada input `choice` lawas yang diabaikan agar estafet sesi 6 jam tidak ditolak HTTP 422 oleh GitHub API, serta meneruskan `devtools`, `studio_tools`, dan `mac_launcher`.
- **Web & SEO (`web-next`)**: seksi baru **Tentang & Arsitektur Native** (**Founder: xykal / Haekal Saputra · Tim XyVerse · Dikembangkan di Indonesia**), JSON-LD Schema.org (`Person`, `Organization`, `WebApplication`), keyword SEO diperluas, dan kamus bahasa `en.json` dilengkapi penuh.

## 2026-11-13 (lanjutan) — Toolchain Developer + hapus Discord
- **Toolchain Developer (baru, opt-in `devtools=ya`)**: LLVM (C/C++), .NET SDK 8 (C#), Rust (rustup stable), VS Code. Default tidak dipasang supaya run tetap cepat. Script: `scripts/setup-devtools.ps1`.
- **Discord dihapus** dari workflow & opsi (fitur non-RDP, arahan pemilik: hapus yang tidak berhubungan dengan koneksi RDP). Input `discord` tetap diterima (diabaikan) demi kompatibilitas APK lama.
- Nama step dirapikan: "Runtime aplikasi (VC++/DirectX/.NET)", "Publish status siap pakai (setelah seluruh setup siap)".

## 2026-11-13 — Hapus suite game, runtime cepat, grafis 3D lengkap (permintaan pemilik)

- **Dihapus total:** GTA/SA-MP (+ anti-ban), Suite Game & Studio (Minecraft, Roblox, ETS 2, Blender, MEmu, FiveM), MuMu Player, XyDeskTools Gaming & Tools Hub, halaman `/dashboard/games`.
  Alasan (laporan pemilik): sering `unable to execute`, "kadang gabisa kebuka", dan menambah lama runtime.
- **Runtime cepat (default `runtimes=cepat`):** hanya VC++ 2015-2022 x64+x86 + **DirectX Juni 2010 (3D lengkap)**. Mode `penuh` (manual) menambah VC++ 2010-2013 + .NET 3.5 + VC++ 2005/2008 untuk aplikasi lawas.
- **`scripts/setup-directx.ps1` baru:** instalasi DirectX Juni 2010 mandiri (dipisah dari setup-samp.ps1 yang dihapus), idempoten.
- **Input game workflow (`samp`, `samp_antiban`, `mumu`, `roblox`, `minecraft_java`, `minecraft_bedrock`) tetap diterima** untuk kompatibilitas dispatch APK lama, tetapi **diabaikan** (deskripsi ditandai "(diabaikan)").
- Step workflow yang dihapus: setup-samp, setup-samp-antiban, setup-games, setup-mumu, setup-tools-hub. Step grafis (Mesa3D OpenGL 4.6/D3D12) tetap ada = "Grafis 3D Lengkap".
- Validator `validate-dependencies.yml` disesuaikan (parse setup-directx/setup-runtimes/setup-rdp + uji idempotensi DirectX).
- Dashboard: link & rute "Games" dihapus; label input game ditandai "(fitur dihapus)".

Rencana menyusul di repo XyDesk-Remote (APK): hapus toggle game di layar "Buat RDP",
tombol otomatis "Lihat Status RDP", user online anonim tanpa opt-in, dan fitur transfer file HP↔PC.
