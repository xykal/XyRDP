# Changelog XyRDP-SAMP Mod

## v1.0 — 2026-10-09 — Initial SAMP + Storage Booster Mod
- **Added `scripts/optimize-storage.ps1`**: bebaskan 45-75GB (Android/Haskell/CodeQL/dotnet lama/cache)
- **Added `scripts/setup-samp.ps1`**: auto install GTA SAMP 0.3.7-R5 + DirectX9 + VC++ + DirectPlay + compat + shortcut
- **Modified `.github/workflows/rdp-6h.yml`**: tambah inputs `storage_boost`, `samp`, `samp_extra`, `gta_sa_url` + 3 steps baru
- **Modified `scripts/lib-common.ps1`**: tambah defaults `storage_boost`, `samp`, `samp_extra`
- **Modified `assets/rdp-extras.json`**: tambah keys SAMP
- **Added `README.md`**: panduan lengkap + storage solved + fork setup
- **Added `PANDUAN-FORK.md`**: step-by-step fork khusus
- Tested on `windows-2022` image Okt 2026: before 72GB free → after 128GB free

### Known Limitations
- GTA SA butuh file legal milik user (BYOG)
- WARP llvmpipe = 20-35fps low setting
- Pinggy tunnel 60 menit → auto renew via keepalive (alamat baru)
