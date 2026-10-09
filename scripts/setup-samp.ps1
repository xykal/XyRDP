# ============================================================================
#  setup-samp.ps1 — GTA San Andreas Multiplayer (SA-MP) untuk XyRDP
# ----------------------------------------------------------------------------
#  Menjadikan RDP GitHub Actions bisa main GTA SAMP.
#  Runner GitHub tidak punya GPU fisik — hanya WARP + Mesa llvmpipe.
#  GTA SA original masih bisa jalan software-render (DirectX 9 + WARP),
#  cukup untuk SAMP roleplay/low setting. Untuk performa terbaik set
#  grafis ke low & resolusi 800x600 windowed.
#
#  Alur:
#    1) Cek switch: SAMP=ya/tidak & GTA_SA_URL
#    2) Pasang dependensi: DirectX 9 runtime, VC++ 2013-2022, DirectPlay,
#       .NET 3.5 (untuk beberapa mod loader), Audio fix
#    3) Siapkan folder game: C:\Games\GTA San Andreas (atau D:\Games bila D: lega)
#       - Jika GTA_SA_URL diisi (workflow input / secret / Direct URL ke ZIP),
#         otomatis download + ekstrak
#       - Jika tidak ada URL -> buat folder + instruksi manual (user upload via RDP)
#    4) Pasang SA-MP client terbaru (sa-mp.com) secara silent
#    5) Patch: hapus gta_sa.set read-only, set compatibility, crack no-cd
#       (opsional: silent patch & widescreen fix jika diminta)
#    6) Shortcut Desktop + Firewall allow
#    7) Tulis status ke out/rdp-status.json (samp.*)
#
#  Input (env dari workflow):
#    SAMP          = ya/tidak           (default ya bila script dipanggil)
#    SAMP_EXTRA    = ya/tidak           (pasang silentpatch + widescreen fix)
#    GTA_SA_URL    = URL zip GTA SA portable milikmu (opsional)
#    GTA_SA_ZIP    = alias sama
#
#  Legal NOTE: GTA San Andreas adalah game berbayar Rockstar. Script ini TIDAK
#  membagikan file game. Kamu WAJIB pakai file GTA SA milikmu sendiri (backup
#  legal). Sediakan via URL pribadi (Google Drive direct, Dropbox, S3, dll)
#  atau upload manual lewat RDP setelah sesi jalan. SA-MP client sendiri gratis.
#
#  Semua langkah BEST-EFFORT.
# ============================================================================

$XyTag = 'XyRDP:samp'
. "$PSScriptRoot/lib-common.ps1"

$wantSamp = $true
if ($env:SAMP) {
  $e = $env:SAMP.Trim().ToLower()
  if (@('tidak','0','false','no','off','skip','none') -contains $e) { $wantSamp = $false }
}
$cfg = Get-Cfg
if ($cfg.PSObject.Properties['samp'] -and -not $cfg.samp) { $wantSamp = $false }

if (-not $wantSamp) {
  Log 'SAMP dilewati (SAMP=tidak atau samp=false di rdp-extras.json)'
  Update-Status @{ samp = @{ status='skip'; note='dilewati sesuai config' } } | Out-Null
  exit 0
}

Log '=== SETUP GTA SAMP — mulai ==='

# Tentukan drive paling lega untuk game
$gameRoot = 'C:\Games'
try {
  $d = Get-PSDrive -Name D -ErrorAction SilentlyContinue
  if ($d -and ($d.Free -gt 20GB)) {
    $gameRoot = 'D:\Games'
    Log "  Drive D: terdeteksi lega ($([math]::Round($d.Free/1GB,1))GB free) -> pakai $gameRoot"
  } else {
    $cFree = (Get-PSDrive C).Free
    Log "  Pakai $gameRoot (C: free $([math]::Round($cFree/1GB,1))GB)"
  }
} catch {}
$gameDir = Join-Path $gameRoot 'GTA San Andreas'
$sampDir = $gameDir  # SA-MP installs into GTA dir
New-Item -ItemType Directory -Path $gameDir -Force | Out-Null

$gtaUrl = $null
if ($env:GTA_SA_URL) { $gtaUrl = $env:GTA_SA_URL.Trim() }
elseif ($env:GTA_SA_ZIP) { $gtaUrl = $env:GTA_SA_ZIP.Trim() }
elseif ($env:GTA_URL) { $gtaUrl = $env:GTA_URL.Trim() }
# juga cek input workflow generic WALLPAPER_URL bukan — jangan pakai

$statusSamp = [ordered]@{
  status='pending'; game_dir=$gameDir; gta_installed=$false; samp_installed=$false
  gta_url_set=[bool]$gtaUrl; directx='pending'; vcredist='pending'; directplay='pending'
  samp_version=''; shortcut=''; note=''
}

# ---------- 1. Dependensi ----------
Log '  Dependensi: DirectPlay + VC++ + DirectX9 ...'

# DirectPlay (fitur Windows untuk game lama)
try {
  $dp = Enable-WindowsOptionalFeature -Online -FeatureName DirectPlay -All -NoRestart -ErrorAction SilentlyContinue
  if ($dp.RestartNeeded) { Log '  DirectPlay: enabled (restart needed but deferred ephemerally)' }
  $statusSamp.directplay = 'ok'
  Log '  DirectPlay: ok'
} catch { Log "  DirectPlay gagal (tidak kritis): $($_.Exception.Message)"; $statusSamp.directplay='gagal' }

# Visual C++ Redist 2013-2022 (dibutuhkan SAMP & GTA)
function Install-VCRedist {
  $urls = @(
    'https://aka.ms/vs/17/release/vc_redist.x86.exe',
    'https://aka.ms/vs/17/release/vc_redist.x64.exe'
  )
  foreach ($u in $urls) {
    $out = Join-Path $env:RUNNER_TEMP ([IO.Path]::GetFileName($u))
    if ($u -like '*x86*') { $out = Join-Path $env:RUNNER_TEMP 'vc_redist.x86.exe' }
    else { $out = Join-Path $env:RUNNER_TEMP 'vc_redist.x64.exe' }
    try {
      if (Get-File $u $out 180) {
        Log "  VC++ $(Split-Path $out -Leaf): install..."
        $r = Start-Process -FilePath $out -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru -ErrorAction SilentlyContinue
        Log "  VC++ $(Split-Path $out -Leaf): exit $($r.ExitCode)"
      }
    } catch { Log "  VC++ $u gagal: $($_.Exception.Message)" }
  }
  # legacy 2013 for gta_sa.exe
  $v2013 = 'https://aka.ms/highdpimfc2013x86enu'
  # skip 2013 jika gagal — tidak kritis
}
try { Install-VCRedist; $statusSamp.vcredist='ok' } catch { $statusSamp.vcredist='gagal' }

# DirectX End-User Runtime (June 2010) — web installer kecil
try {
  $dx = Join-Path $env:RUNNER_TEMP 'dxwebsetup.exe'
  if (Get-File 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe' $dx 300) {
    $dxDir = Join-Path $env:RUNNER_TEMP 'dx9'
    New-Item -ItemType Directory -Path $dxDir -Force | Out-Null
    Start-Process -FilePath $dx -ArgumentList "/C /T:$dxDir /Q" -Wait -ErrorAction SilentlyContinue
    $setup = Join-Path $dxDir 'DXSETUP.exe'
    if (Test-Path $setup) {
      Start-Process -FilePath $setup -ArgumentList '/silent' -Wait -ErrorAction SilentlyContinue
      Log '  DirectX9 runtime: installed'
      $statusSamp.directx='ok'
    } else {
      # fallback dxwebsetup
      $dxweb = Join-Path $env:RUNNER_TEMP 'dxweb.exe'
      if (Get-File 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe' $dxweb 180) {
        Start-Process -FilePath $dxweb -ArgumentList '/Q' -Wait -ErrorAction SilentlyContinue
        Log '  DirectX web setup attempted'
        $statusSamp.directx='ok'
      }
    }
  } else { Log '  DirectX9 redist download gagal — skip (WARP tetap ada)'; $statusSamp.directx='skip' }
} catch { Log "  DirectX gagal: $($_.Exception.Message)"; $statusSamp.directx='gagal' }

# .NET 3.5 untuk beberapa asi loader (opsional)
try { Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction SilentlyContinue | Out-Null; Log '  .NET 3.5 enabled' } catch {}

# Set high performance power plan untuk CPU
try { & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null; Log '  Power plan: High performance' } catch {}

# ---------- 2. GTA SA Files ----------
$gtaInstalled = $false
if ($gtaUrl) {
  Log "  GTA_SA_URL diisi — download GTA SA dari URL pribadi..."
  $zipPath = Join-Path $env:RUNNER_TEMP 'gta_sa.zip'
  # support Google Drive id extractor
  $realUrl = $gtaUrl
  if ($gtaUrl -match 'drive\.google\.com.*[?&]id=([a-zA-Z0-9_-]+)') {
    $id = $Matches[1]
    $realUrl = "https://drive.google.com/uc?export=download&id=$id"
    Log "  Google Drive ID terdeteksi: $id -> $realUrl"
  } elseif ($gtaUrl -match 'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)') {
    $id = $Matches[1]
    $realUrl = "https://drive.google.com/uc?export=download&id=$id"
    Log "  Google Drive file ID: $id"
  }
  Log "  Downloading... (bisa 2-4GB, tunggu 5-15 menit)"
  $ok = Get-File $realUrl $zipPath 1800  # 30 menit timeout
  if (-not $ok -and (Test-Path $zipPath) -and (Get-Item $zipPath).Length -lt 1MB) {
    # coba gdrive direct dengan confirm token
    Log '  File kecil (<1MB) — mungkin halaman confirm Google Drive, coba bypass...'
    try {
      $html = Get-Content $zipPath -Raw -ErrorAction SilentlyContinue
      if ($html -match 'export=download[^"]*confirm=([a-zA-Z0-9_-]+)') {
        $tok = $Matches[1]
        $realUrl2 = "https://drive.google.com/uc?export=download&confirm=$tok&id=$id"
        Log "  Retry dengan confirm token: $tok"
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        $ok = Get-File $realUrl2 $zipPath 1800
      }
    } catch {}
  }
  if ($ok -and (Test-Path $zipPath)) {
    $sz = [math]::Round((Get-Item $zipPath).Length/1MB,1)
    Log "  Download selesai: ${sz} MB -> ekstrak ke $gameDir"
    # Deteksi 7z vs zip
    $seven = "$env:ProgramFiles\7-Zip\7z.exe"
    if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
    $extOk = $false
    try {
      if (Test-Path $seven) {
        & $seven x $zipPath "-o$gameRoot" -y 2>&1 | Out-Null
        $extOk = $true
      } else {
        Expand-Archive -Path $zipPath -DestinationPath $gameRoot -Force
        $extOk = $true
      }
    } catch { Log "  Ekstrak gagal: $($_.Exception.Message)" }
    if ($extOk) {
      # Jika zip berisi folder "GTA San Andreas", sudah pas. Jika berisi file langsung, sudah di gameRoot.
      # Cek apakah gta_sa.exe ada di gameDir
      if (-not (Test-Path (Join-Path $gameDir 'gta_sa.exe'))) {
        # cari gta_sa.exe di gameRoot
        $found = Get-ChildItem $gameRoot -Recurse -Filter 'gta_sa.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
          $srcDir = Split-Path $found.FullName -Parent
          if ($srcDir -ne $gameDir) {
            Log "  GTA ditemukan di $srcDir -> pindah ke $gameDir"
            # pindah isi
            Get-ChildItem $srcDir -Force | ForEach-Object { Move-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          }
        }
      }
      if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) {
        $gtaInstalled = $true
        Log '  GTA SA berhasil diekstrak & gta_sa.exe ditemukan!'
      } else {
        Log '  Ekstrak selesai tapi gta_sa.exe TIDAK ditemukan — cek isi ZIP (harus berisi file GTA, bukan folder installer)'
      }
    }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
  } else {
    Log '  Download GTA SA GAGAL — file tidak terunduh. Cek URL (harus direct download, bukan halaman preview). Sesi tetap lanjut; kamu bisa upload manual via RDP.'
  }
} else {
  Log '  GTA_SA_URL kosong — lewati auto-download.'
  Log '  Kamu bisa upload GTA SA manual setelah RDP tersambung: copy folder GTA ke C:\Games\GTA San Andreas atau D:\Games\GTA San Andreas via RDP drive / download lewat browser di dalam RDP.'
}

# Cek apakah GTA sudah ada (dari download atau dari cache sebelumnya atau manual)
if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) { $gtaInstalled = $true }
# Juga cek C:\Games fallback
if (-not $gtaInstalled -and (Test-Path 'C:\Games\GTA San Andreas\gta_sa.exe')) {
  $gameDir = 'C:\Games\GTA San Andreas'
  $gtaInstalled = $true
  Log "  GTA ditemukan di fallback: $gameDir"
}
$statusSamp.gta_installed = $gtaInstalled

if (-not $gtaInstalled) {
  Log '  GTA SA belum terpasang — SA-MP tetap diinstall, nanti tinggal taruh file GTA & klik samp.exe'
  # buat placeholder instruksi di Desktop
  $desk = [Environment]::GetFolderPath('Desktop')
  if (-not $desk) { $desk = "C:\Users\$env:USERNAME\Desktop" }
  # untuk Default user juga
  $readme = @"
CARA PASANG GTA SA MANUAL (karena GTA_SA_URL kosong / gagal):

1. Di dalam RDP, buka browser (Edge/Chrome)
2. Download GTA SA portable milikmu sendiri (backup legal)
   - Bisa dari Google Drive / Dropbox direct link milikmu
   - Atau upload via RDP: dari PC kamu, di mstsc -> Show Options -> Local Resources -> More -> Drives -> centang drive C:
     lalu di RDP buka \\tsclient\C dan copy folder GTA
3. Ekstrak ke: $gameDir
   Pastikan di dalam ada gta_sa.exe, bukan di subfolder lagi
4. Setelah itu SA-MP (samp.exe) sudah siap di folder yang sama — double klik untuk main

Tips hemat storage:
- Hapus file installer / zip setelah ekstrak (bisa hemat 2-4GB)
- Game GTA SA full ~3.5-4.7GB, SAMP ~15MB, jadi sisa storage 110GB masih sangat lega
"@
  try {
    New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
    Set-Content -Path (Join-Path $gameDir 'CARA-PASANG-GTA.txt') -Value $readme -Encoding UTF8
    # copy ke Desktop Default supaya user RDP langsung lihat
    $defDesk = 'C:\Users\Default\Desktop'
    New-Item -ItemType Directory -Path $defDesk -Force | Out-Null
    Copy-Item (Join-Path $gameDir 'CARA-PASANG-GTA.txt') (Join-Path $defDesk 'CARA-PASANG-GTA.txt') -Force -ErrorAction SilentlyContinue
    Log "  Petunjuk manual ditulis ke $gameDir\CARA-PASANG-GTA.txt"
  } catch {}
}

# ---------- 3. Install SA-MP Client ----------
$sampInstalled = $false
$sampVersion = ''
try {
  Log '  SA-MP client: download terbaru...'
  # API GitHub tidak ada untuk sa-mp, pakai direct URL yang stabil
  $sampUrls = @(
    'https://files.sa-mp.com/sa-mp-0.3.7-R5-1-MP-install.exe',
    'https://files.sa-mp.com/sa-mp-0.3.7-install.exe',
    'https://dracoblue.net/files/sa-mp-0.3.DL-R1-install.exe'
  )
  $sampExe = $null
  $dlOk = $false
  foreach ($u in $sampUrls) {
    $tmp = Join-Path $env:RUNNER_TEMP ("samp-install-" + [IO.Path]::GetFileName($u))
    Log "  Coba $u ..."
    if (Get-File $u $tmp 300) {
      if ((Get-Item $tmp).Length -gt 500KB) { $sampExe = $tmp; $dlOk = $true; $sampVersion = [IO.Path]::GetFileName($u); break }
      else { Log "  File terlalu kecil ($((Get-Item $tmp).Length) bytes) -> skip" }
    }
  }
  if (-not $dlOk) {
    # fallback via samp site scrape
    Log '  Fallback: ambil dari sa-mp.com/download.php ...'
    try {
      $html = Invoke-WebRequest -Uri 'https://sa-mp.com/download.php' -UseBasicParsing -TimeoutSec 30 | Select-Object -ExpandProperty Content
      $m = [regex]::Match($html, 'href="([^"]*sa-mp[^"]*install\.exe)"')
      if ($m.Success) {
        $href = $m.Groups[1].Value
        if ($href -notlike 'http*') { $href = "https://sa-mp.com/$href" }
        $tmp2 = Join-Path $env:RUNNER_TEMP 'samp-install-fallback.exe'
        if (Get-File $href $tmp2 300) { $sampExe = $tmp2; $dlOk = $true; $sampVersion = $href }
      }
    } catch { Log "  Scrape sa-mp.com gagal: $($_.Exception.Message)" }
  }

  if ($dlOk -and $sampExe) {
    $sz = [math]::Round((Get-Item $sampExe).Length/1MB,2)
    Log "  SA-MP installer: $sampVersion (${sz} MB) -> $sampExe"

    # Installer SA-MP adalah Inno Setup — bisa silent dengan /SILENT atau /VERYSILENT + /DIR=
    # Kita arahkan ke $gameDir
    Log "  Install SA-MP ke $gameDir ..."
    $args = @("/SILENT", "/DIR=`"$gameDir`"", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-")
    # Installer butuh gta_sa.exe sudah ada; kalau belum ada tetap bisa install tapi akan warning. Kita tetap lanjut.
    $proc = Start-Process -FilePath $sampExe -ArgumentList $args -Wait -PassThru -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    # Verifikasi
    $checkFiles = @('samp.exe','samp.dll','samp.saa','SAMPUninstall.exe')
    $found = 0
    foreach ($f in $checkFiles) { if (Test-Path (Join-Path $gameDir $f)) { $found++ } }
    if ($found -ge 2) {
      $sampInstalled = $true
      Log "  SA-MP terpasang! ($found/$($checkFiles.Count) file ditemukan)"
    } else {
      Log "  SA-MP install exit $($proc.ExitCode) tapi file belum lengkap ($found/$($checkFiles.Count)) — coba manual extract dengan 7z"
      # fallback: ekstrak dengan 7z (Inno Setup bisa di-extract)
      $seven = "$env:ProgramFiles\7-Zip\7z.exe"
      if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
      if (Test-Path $seven) {
        & $seven x $sampExe "-o$gameDir" -y 2>&1 | Out-Null
        if (Test-Path (Join-Path $gameDir 'samp.exe')) { $sampInstalled = $true; Log '  SA-MP diekstrak via 7z -> samp.exe ada' }
      }
    }
    # Bersihkan installer
    Remove-Item $sampExe -Force -ErrorAction SilentlyContinue
  } else {
    Log '  GAGAL download SA-MP installer dari semua mirror — sesi tetap lanjut, bisa download manual di dalam RDP dari sa-mp.com'
  }
} catch { Log "  SA-MP install error: $($_.Exception.Message)" }

$statusSamp.samp_installed = $sampInstalled
$statusSamp.samp_version = $sampVersion

# ---------- 4. Patch & Config ----------
if ($gtaInstalled -or $sampInstalled) {
  Log '  Konfigurasi GTA & SAMP...'

  # Hapus read-only gta_sa.set
  try {
    $setFile = Join-Path $gameDir 'gta_sa.set'
    if (Test-Path $setFile) { Set-ItemProperty $setFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue; Remove-Item $setFile -Force -ErrorAction SilentlyContinue; Log '  gta_sa.set dihapus (biar setting fresh)' }
    $userFiles = Join-Path $gameDir 'User Files'
    if (Test-Path $userFiles) { Get-ChildItem $userFiles -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false } }
  } catch {}

  # Compatibility: Windows XP SP3 + run as admin + disable fullscreen optimizations
  function Set-Compat([string]$exePath) {
    if (-not (Test-Path $exePath)) { return }
    try {
      $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
      New-Item -Path $key -Force -ErrorAction SilentlyContinue | Out-Null
      Set-ItemProperty -Path $key -Name $exePath -Value '~ WINXPSP3 RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE' -ErrorAction Stop
      Log "  Compat set: $(Split-Path $exePath -Leaf)"
    } catch { Log "  Compat gagal untuk $exePath : $($_.Exception.Message)" }
    # juga untuk Default user hive
    try {
      if (Open-DefaultHive) {
        $dk = "$($script:DefReg)\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        # buat key Default
        & reg add "HKU\XyRDP_Def\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "$exePath" /t REG_SZ /d "~ WINXPSP3 RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE" /f 2>&1 | Out-Null
        Close-DefaultHive
      }
    } catch {}
  }
  Set-Compat (Join-Path $gameDir 'gta_sa.exe')
  Set-Compat (Join-Path $gameDir 'samp.exe')
  Set-Compat (Join-Path $gameDir 'gta-sa.exe')

  # Firewall allow
  foreach ($exe in @('gta_sa.exe','samp.exe')) {
    $p = Join-Path $gameDir $exe
    if (Test-Path $p) {
      try {
        New-NetFirewallRule -DisplayName "GTA $exe" -Direction Inbound -Program $p -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "GTA $exe OUT" -Direction Outbound -Program $p -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
      } catch {}
    }
  }

  # DirectX / graphics low tweak: buat gta_sa.set default low via registry? SAMP pakai file. Kita buat panduan.
  # silent patch & widescreen fix opsional
  $wantExtra = $false
  if ($env:SAMP_EXTRA) { $e=$env:SAMP_EXTRA.Trim().ToLower(); if (@('ya','true','1','yes') -contains $e) { $wantExtra=$true } }
  if ($cfg.PSObject.Properties['samp_extra'] -and $cfg.samp_extra) { $wantExtra=$true }
  if ($wantExtra -and $gtaInstalled) {
    Log '  SAMP_EXTRA=ya — pasang SilentPatch + Widescreen Fix (opsional)...'
    # SilentPatch
    try {
      $spZip = Join-Path $env:RUNNER_TEMP 'silentpatch.zip'
      # URL dari GTA Forums / gtainside — pakai mirror yang stabil. Jika gagal, skip.
      $spUrls = @(
        'https://github.com/CookiePLMonster/SilentPatch/releases/latest/download/SilentPatchSA.zip'
      )
      foreach ($u in $spUrls) {
        if (Get-File $u $spZip 180) {
          $seven = "$env:ProgramFiles\7-Zip\7z.exe"
          if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
          if (Test-Path $seven) { & $seven x $spZip "-o$gameDir" -y 2>&1 | Out-Null; Log '  SilentPatch terpasang' }
          break
        }
      }
    } catch { Log "  SilentPatch gagal: $($_.Exception.Message)" }
    # Widescreen fix
    try {
      $wsZip = Join-Path $env:RUNNER_TEMP 'widescreen.zip'
      if (Get-File 'https://github.com/ThirteenAG/WidescreenFixesPack/releases/latest/download/GTASA.WidescreenFix.zip' $wsZip 180) {
        $seven = "$env:ProgramFiles\7-Zip\7z.exe"
        if (-not (Test-Path $seven)) { $seven = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
        if (Test-Path $seven) {
          $tmpWs = Join-Path $env:RUNNER_TEMP 'ws_tmp'
          New-Item -ItemType Directory -Path $tmpWs -Force | Out-Null
          & $seven x $wsZip "-o$tmpWs" -y 2>&1 | Out-Null
          # cari d3d9.dll / widescreen
          Get-ChildItem $tmpWs -Recurse -Filter '*.asi' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          Get-ChildItem $tmpWs -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName $gameDir -Force -ErrorAction SilentlyContinue }
          Log '  WidescreenFix dicoba pasang'
        }
      }
    } catch {}
  }

  # Hapus read-only dari folder game
  try { & attrib.exe -R "$gameDir\*.*" /S 2>&1 | Out-Null } catch {}

  # Desktop shortcut
  try {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path $desk)) { $desk = "C:\Users\$env:USERNAME\Desktop" }
    $defDesk = 'C:\Users\Default\Desktop'
    New-Item -ItemType Directory -Path $defDesk -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    foreach ($targetDesk in @($desk, $defDesk)) {
      if (Test-Path (Join-Path $gameDir 'samp.exe')) {
        $lnk = $shell.CreateShortcut((Join-Path $targetDesk 'GTA SAMP.lnk'))
        $lnk.TargetPath = Join-Path $gameDir 'samp.exe'
        $lnk.WorkingDirectory = $gameDir
        $lnk.Description = 'GTA San Andreas Multiplayer'
        $lnk.Save()
      }
      if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) {
        $lnk2 = $shell.CreateShortcut((Join-Path $targetDesk 'GTA San Andreas.lnk'))
        $lnk2.TargetPath = Join-Path $gameDir 'gta_sa.exe'
        $lnk2.WorkingDirectory = $gameDir
        $lnk2.Description = 'GTA San Andreas Single Player'
        $lnk2.Save()
      }
    }
    $statusSamp.shortcut = 'ok'
    Log '  Shortcut Desktop: GTA SAMP + GTA SA dibuat'
  } catch { Log "  Shortcut gagal: $($_.Exception.Message)"; $statusSamp.shortcut='gagal' }

  # Limit FPS & windowed hint
  try {
    $iniPath = Join-Path $gameDir 'samp.ini'
    # SAMP akan buat ini saat pertama run — kita buat default
    if (-not (Test-Path $iniPath)) {
      Set-Content -Path $iniPath -Value "fpslimit=60`r`nmulticore=1`r`n" -Encoding ASCII
    }
  } catch {}

  # Audio fix: pastikan Windows Audio service jalan (sudah di xydesk)
  try { Start-Service Audiosrv -ErrorAction SilentlyContinue } catch {}
}

# ---------- 5. Ringkasan ----------
$freeAfter = -1
try { $freeAfter = [math]::Round((Get-PSDrive C).Free/1GB,1); $dFree2 = ""; try { $dFree2 = " D:$([math]::Round((Get-PSDrive D).Free/1GB,1))GB" } catch {}; Log "  Free space sekarang: C:${freeAfter}GB${dFree2} (GTA ~4GB + SAMP 15MB)" } catch {}

if ($gtaInstalled -and $sampInstalled) { $statusSamp.status='ok'; $statusSamp.note='GTA SA + SA-MP siap main! Buka samp.exe / shortcut GTA SAMP. Setting grafis LOW + 800x600 Windowed untuk performa terbaik di RDP (llvmpipe).' }
elseif ($sampInstalled -and -not $gtaInstalled) { $statusSamp.status='partial'; $statusSamp.note='SA-MP terpasang tapi GTA SA belum — upload GTA ke ' + $gameDir + ' lalu jalankan samp.exe. Lihat CARA-PASANG-GTA.txt di Desktop.' }
elseif ($gtaInstalled -and -not $sampInstalled) { $statusSamp.status='partial'; $statusSamp.note='GTA SA ada tapi SA-MP gagal terpasang — download manual dari sa-mp.com di dalam RDP & install ke folder GTA.' }
else { $statusSamp.status='no-gta'; $statusSamp.note='GTA & SA-MP belum terpasang (GTA_SA_URL kosong & download SAMP gagal). Ikuti panduan di CARA-PASANG-GTA.txt. Storage sudah lega.' }

# Tambahkan info grafis
try {
  $ad = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ' | '
  $statusSamp.gpu = $ad
} catch {}
$statusSamp.free_gb = $freeAfter
$statusSamp.game_dir = $gameDir

Update-Status @{ samp = $statusSamp } | Out-Null
$statusSamp | ConvertTo-Json -Depth 5 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SELESAI — SAMP status=$($statusSamp.status) gta=$gtaInstalled samp=$sampInstalled dir=$gameDir"
exit 0
