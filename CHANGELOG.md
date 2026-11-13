# Changelog XyRDP

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
