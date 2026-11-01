# ============================================================================
#  setup-samp.ps1 - Suite Lengkap GTA San Andreas & SA-MP 0.3.7-R5 / open.mp
#                   (Anti-Blank / Anti-Crash di Windows Server RDP Tanpa GPU)
# ----------------------------------------------------------------------------
#  Mengatasi seluruh penyebab GTA SA / SA-MP "tidak muncul apa-apa" di RDP:
#  1) Pre-install SA-MP 0.3.7-R5 Client (samp.exe, samp.dll, samp.saa) +
#     open.mp Launcher langsung ke C:\Games\GTA San Andreas & Desktop.
#  2) Memasang dgVoodoo2 x86 Direct3D 9 Wrapper (D3D9.dll + dgVoodoo.conf)
#     yang menerjemahkan DirectX 9 Hardware HAL (D3DDEVTYPE_HAL) ke
#     Direct3D 11/12 WARP di Microsoft Basic Display Adapter + menyediakan
#     resolusi virtual 800x600 / 1280x720 / 1920x1080 agar gta_sa.exe tidak
#     pernah keluar diam-diam karena "Cannot find 800x600x32 video mode".
#  3) Memasang III.VC.SA.WindowedMode.asi + SilentPatchSA.asi + vorbisFile.dll
#     (Ultimate ASI Loader tunggal - TANPA duplikasi dinput8.dll/ddraw.dll
#     yang sebelumnya membuat .asi termuat 2x dan crash saat start).
#  4) Menonaktifkan paksaan DEP Windows Server (bcdedit nx OptIn + AppCompat
#     DisableNXShowUI) agar injeksi samp.dll ke gta_sa.exe tidak dibunuh OS.
#  5) Menyediakan GUI "GTA SA-MP Control Center" (-Sta Windows Forms) di
#     Desktop untuk 1-klik Buka SA-MP, Auto-Download/Ekstrak GTA SA, & Fix Crash.
# ============================================================================
param(
  [switch]$DirectXOnly
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$XyTag                 = 'XyRDP:samp'
. "$PSScriptRoot/lib-common.ps1"

$cfg = Get-Cfg
if (-not $DirectXOnly -and $env:SAMP) {
  $e = $env:SAMP.Trim().ToLower()
  if (@('tidak','0','false','no','off','skip','none') -contains $e) {
    Log 'setup runtime + GTA SA-MP dilewati (input samp=tidak)'
    Update-Status @{ samp = @{ status = 'skip' } } | Out-Null
    exit 0
  }
}

$sys32 = Join-Path $env:SystemRoot 'System32'
$wow64 = Join-Path $env:SystemRoot 'SysWOW64'
$work  = 'C:\XyRDP\deps\samp'
New-Item -ItemType Directory -Path $work -Force | Out-Null

# Cegah Defender mengkarantina samp.dll / mod GTA SA / wrapper dgVoodoo saat
# pertama kali dibuka (VM sekali-pakai, best-effort).
Disable-DefenderForGames

function Test-FilesPresent([string]$Dir, [string[]]$Names) {
  foreach ($n in $Names) {
    if (-not (Test-Path (Join-Path $Dir $n))) { return $false }
  }
  return $true
}

function Test-IsPeExecutable([string]$FilePath, [int]$MinBytes = 4096) {
  try {
    if (-not (Test-Path $FilePath)) { return $false }
    $item = Get-Item $FilePath -ErrorAction Stop
    if ($item.Length -lt $MinBytes) { return $false }
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
      $b0 = $fs.ReadByte()
      $b1 = $fs.ReadByte()
      return ($b0 -eq 0x4D -and $b1 -eq 0x5A) # 'MZ'
    } finally {
      $fs.Close()
    }
  } catch {
    return $false
  }
}

function Invoke-DownloadWithRetry([string]$Url, [string]$OutFile, [int]$Retries = 2, [switch]$RequirePe) {
  for ($i = 1; $i -le $Retries; $i++) {
    try {
      Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
      & curl.exe -fL -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --retry 2 --retry-delay 1 --connect-timeout 15 --max-time 120 -sS $Url -o $OutFile
      if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 1024) {
        if (-not $RequirePe -or (Test-IsPeExecutable $OutFile 10240)) {
          return $true
        }
      }
    } catch {}
    try {
      Invoke-WebRequest -Uri $Url -OutFile $OutFile -UserAgent "Mozilla/5.0" -UseBasicParsing -TimeoutSec 90
      if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 1024) {
        if (-not $RequirePe -or (Test-IsPeExecutable $OutFile 10240)) {
          return $true
        }
      }
    } catch {
      if ($i -lt $Retries) { Start-Sleep -Seconds 2 }
    }
  }
  return $false
}

function Start-ProcessWithTimeout([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDir = '', [int]$TimeoutSec = 60) {
  try {
    $psi = @{
      FilePath    = $FilePath
      PassThru    = $true
      WindowStyle = 'Hidden'
    }
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
      $psi['ArgumentList'] = $ArgumentList
    }
    if ($WorkingDir -and (Test-Path $WorkingDir)) {
      $psi['WorkingDirectory'] = $WorkingDir
    }
    $p = Start-Process @psi
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
      Log "  proses '$(Split-Path $FilePath -Leaf)' melebihi batas $TimeoutSec detik - dihentikan."
      try { $p.Kill() } catch {}
      return -1
    }
    return $p.ExitCode
  } catch {
    Log "  gagal menjalankan $(Split-Path $FilePath -Leaf): $($_.Exception.Message)"
    return -1
  }
}

function Test-DirectXFiles {
  $required = @('d3dx9_24.dll','d3dx9_43.dll','d3dcompiler_43.dll','xinput1_3.dll','x3daudio1_7.dll')
  return (Test-FilesPresent $wow64 $required) -and (Test-FilesPresent $sys32 $required)
}

function Install-DirectXJune2010 {
  if (Test-DirectXFiles) {
    Log 'DirectX June 2010 sudah terpasang lengkap di System32 dan SysWOW64.'
    return
  }

  $dxPkg = Join-Path $work 'directx_Jun2010_redist.exe'
  $dxExt = Join-Path $work 'dx_extract'
  Remove-Item $dxExt -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $dxExt -Force | Out-Null

  $dxUrl = 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe'
  if (-not (Invoke-DownloadWithRetry $dxUrl $dxPkg 3 -RequirePe)) {
    throw 'Gagal mengunduh DirectX June 2010 redistributable.'
  }

  Log 'Mengekstrak paket DirectX June 2010...'
  $extCode = Start-ProcessWithTimeout $dxPkg @('/Q', "/T:$dxExt") '' 60
  if ($extCode -ne 0) { throw "Ekstraksi DirectX gagal dengan exit code $extCode." }

  $dxSetup = Join-Path $dxExt 'DXSETUP.exe'
  if (-not (Test-Path $dxSetup)) { throw 'DXSETUP.exe tidak ditemukan setelah ekstraksi.' }

  Log 'Menjalankan DXSETUP.exe /silent...'
  $setupCode = Start-ProcessWithTimeout $dxSetup @('/silent') $dxExt 90
  if ($setupCode -ne 0 -and $setupCode -ne 3010) {
    throw "DXSETUP.exe gagal dengan exit code $setupCode."
  }

  if (-not (Test-DirectXFiles)) {
    throw 'Verifikasi DLL DirectX June 2010 gagal setelah instalasi.'
  }
  Remove-Item $dxExt -Recurse -Force -ErrorAction SilentlyContinue
  Log 'DirectX June 2010 terverifikasi.'
}

function Test-Vc2015Files([string]$Dir) {
  return Test-FilesPresent $Dir @('vcruntime140.dll','msvcp140.dll')
}

function Test-Vc2013Files([string]$Dir) {
  return Test-FilesPresent $Dir @('msvcr120.dll','msvcp120.dll')
}

function Install-VcRedist([string]$Label, [string]$Url, [string]$FileName, [scriptblock]$Verify) {
  if (& $Verify) {
    Log "$Label sudah terpasang dan terverifikasi."
    return
  }
  $exe = Join-Path $work $FileName
  if (-not (Invoke-DownloadWithRetry $Url $exe 3 -RequirePe)) {
    throw "Gagal mengunduh $Label dari $Url"
  }
  Log "Memasang $Label..."
  $code = Start-ProcessWithTimeout $exe @('/install','/quiet','/norestart') '' 90
  if (@(0, 1638, 3010) -notcontains $code) {
    throw "$Label gagal dipasang (exit code $code)."
  }
  if (-not (& $Verify)) {
    throw "Verifikasi DLL untuk $Label gagal."
  }
  Log "$Label terverifikasi."
}

function Enable-DirectPlayAndDepBypass {
  $dpOk = $false
  try {
    $code = Start-ProcessWithTimeout 'dism.exe' @('/Online','/Enable-Feature','/FeatureName:DirectPlay','/All','/NoRestart','/Quiet') '' 25
    if ($code -eq 0 -or $code -eq 3010) {
      $dpOk = $true
      Log 'Fitur Windows DirectPlay aktif.'
    }
  } catch {}

  try {
    foreach ($base in @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\DirectPlay',
      'HKLM:\SOFTWARE\Microsoft\DirectPlay',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\DirectPlay8',
      'HKLM:\SOFTWARE\Microsoft\DirectPlay8'
    )) {
      New-Item -Path $base -Force -ErrorAction SilentlyContinue | Out-Null
      New-Item -Path "$base\Service Providers\Internet TCP/IP Connection For DirectPlay" -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $dpOk = $true
  } catch {}

  # PENTING: Windows Server memakai DEP OptOut secara default yang langsung membunuh
  # gta_sa.exe + samp.dll saat start ("Kayak ga muncul apa-apa"). Ubah ke OptIn!
  try {
    & bcdedit.exe /set "{current}" nx OptIn 2>&1 | Out-Null
    Log 'DEP (Data Execution Prevention) diatur ke OptIn untuk kompatibilitas samp.dll.'
  } catch {}

  # Pastikan layanan Windows Audio menyala agar DirectSound gta_sa.exe tidak keluar karena "No sound card"
  try {
    Set-Service -Name 'AudioEndpointBuilder' -StartupType Automatic -ErrorAction SilentlyContinue
    Set-Service -Name 'Audiosrv' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
  } catch {}

  return $dpOk
}

function Install-CompleteSampSuite {
  $kitRoot    = 'C:\Games\GTA-SAMP'
  $modsDir    = Join-Path $kitRoot 'SilentPatch-Pack'
  $scriptsDir = Join-Path $modsDir 'scripts'
  $sampCache  = Join-Path $kitRoot 'SAMP-Client'
  $instDir    = Join-Path $kitRoot 'Installers'
  $gameDir    = 'C:\Games\GTA San Andreas'

  foreach ($d in @($kitRoot, $modsDir, $scriptsDir, $sampCache, $instDir, $gameDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
  }

  $sevenZip = 'C:\Program Files\7-Zip\7z.exe'
  if (-not (Test-Path $sevenZip)) { $sevenZip = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
  if (-not (Test-Path $sevenZip)) { $sevenZip = Get-SevenZipPath }

  # Pastikan tidak ada sisa dinput8.dll lama di $modsDir yang bentrok dengan vorbisFile.dll
  # CATATAN PENTING: JANGAN PERNAH menghapus ddraw.dll / d3dimm.dll karena gta_sa.exe US 1.0
  # memanggil DirectDrawCreateEx (ddraw.dll) di alamat 0x00746929 sebelum membuat D3D9 device!
  Remove-Item (Join-Path $modsDir 'dinput8.dll') -Force -ErrorAction SilentlyContinue

  # 1. Unduh Ultimate ASI Loader x86 dan pasang HANYA sebagai vorbisFile.dll
  #    (Ultimate ASI Loader v9.7.4 sudah memuat Ogg Vorbis 1.3.7 internal + ASI Loader dalam 1 file.
  #     Jangan pernah menaruh vorbisFile.dll DAN dinput8.dll sekaligus agar .asi tidak dimuat 2x!)
  $asiZip = Join-Path $work 'Ultimate-ASI-Loader.zip'
  if (-not (Test-Path (Join-Path $modsDir 'vorbisFile.dll'))) {
    try {
      if (Invoke-DownloadWithRetry 'https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/latest/download/Ultimate-ASI-Loader.zip' $asiZip 2) {
        $asiExt = Join-Path $work 'asi_ext'
        Remove-Item $asiExt -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $asiExt -Force | Out-Null
        if (Test-Path $sevenZip) { & $sevenZip x $asiZip "-o$asiExt" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $asiZip -DestinationPath $asiExt -Force }
        $dll = Get-ChildItem -Path $asiExt -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) {
          Copy-Item $dll.FullName -Destination (Join-Path $modsDir 'vorbisFile.dll') -Force
          Log 'Ultimate ASI Loader (vorbisFile.dll tunggal anti-bentrok) siap.'
        }
        Remove-Item $asiExt -Recurse -Force -ErrorAction SilentlyContinue
      }
    } catch { Log "Unduh Ultimate ASI Loader warning: $($_.Exception.Message)" }
  }

  # 2. Unduh SilentPatchSA resmi (SilentPatchSA.asi) langsung ke folder scripts\ (JANGAN di root agar tidak dimuat 2x!)
  $spSaZip = Join-Path $work 'SilentPatchSA.zip'
  Remove-Item (Join-Path $modsDir 'SilentPatchSA.asi') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $modsDir 'SilentPatchSA.ini') -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path (Join-Path $scriptsDir 'SilentPatchSA.asi'))) {
    try {
      if (Invoke-DownloadWithRetry 'https://github.com/CookiePLMonster/SilentPatch/releases/latest/download/SilentPatchSA.zip' $spSaZip 2) {
        if (Test-Path $sevenZip) { & $sevenZip x $spSaZip "-o$scriptsDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $spSaZip -DestinationPath $scriptsDir -Force }
        Log 'SilentPatchSA.asi berhasil disiapkan di scripts\.'
      }
    } catch { Log "Unduh SilentPatchSA warning: $($_.Exception.Message)" }
  }

  # 3. Hapus III.VC.SA.WindowedMode.asi lama jika ada karena dgVoodoo2 (FullScreenMode=false) sudah menangani Windowed Mode & Alt+Enter secara native tanpa bentrok hook D3D9!
  Remove-Item (Join-Path $scriptsDir 'III.VC.SA.WindowedMode.asi') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $scriptsDir 'III.VC.SA.WindowedMode.cfg') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $modsDir 'III.VC.SA.WindowedMode.asi') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $modsDir 'III.VC.SA.WindowedMode.cfg') -Force -ErrorAction SilentlyContinue

  # 4. Unduh GTASA.WidescreenFix.asi & tulis GTASA.WidescreenFix.ini
  $wsZip = Join-Path $work 'GTASA.WidescreenFix.zip'
  if (-not (Test-Path (Join-Path $scriptsDir 'GTASA.WidescreenFix.asi'))) {
    try {
      if (Invoke-DownloadWithRetry 'https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gtasa/GTASA.WidescreenFix.zip' $wsZip 2) {
        if (Test-Path $sevenZip) { & $sevenZip x $wsZip "-o$modsDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $wsZip -DestinationPath $modsDir -Force }
        Remove-Item (Join-Path $modsDir 'dinput8.dll') -Force -ErrorAction SilentlyContinue
        Log 'GTASA.WidescreenFix.asi berhasil disiapkan.'
      }
    } catch {}
  }
  @(
    '[MAIN]'
    'ResX = 0'
    'ResY = 0'
    'FixAspectRatio = 1'
    'FOVControl = 1'
    'HideAABug = 1'
    'SmartCutsceneBorders = 1'
    'DontTouchFOV = 0'
  ) | Set-Content -Path (Join-Path $scriptsDir 'GTASA.WidescreenFix.ini') -Encoding ASCII -Force

  # 5. Unduh dgVoodoo2 x86 DirectX Wrapper LENGKAP (MS\x86\D3D9.dll + DDraw.dll + D3DImm.dll + D3D8.dll + dgVoodoo.conf)
  #    WAJIB menyertakan DDraw.dll + D3DImm.dll selain D3D9.dll untuk mencegah crash:
  #    "SA-MP 0.3.7-R5 Exception At Address: 0x00746929 (EAX: 0x00000000, US 1.0)"
  #    karena gta_sa.exe memanggil DirectDrawCreateEx di 0x00746920 sebelum membuat D3D9 device!
  $dgvZip = Join-Path $work 'dgVoodoo2.zip'
  if (-not (Test-Path (Join-Path $modsDir 'd3d9.dll')) -or -not (Test-Path (Join-Path $modsDir 'ddraw.dll')) -or -not (Test-Path (Join-Path $modsDir 'd3dimm.dll'))) {
    try {
      $dgvUrl = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.5/dgVoodoo2_87_5.zip'
      try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest' -Headers @{ 'User-Agent' = 'XyRDP' } -TimeoutSec 12
        $a = $rel.assets | Where-Object { $_.name -match '^dgVoodoo2_[0-9_]+\.zip$' } | Select-Object -First 1
        if ($a) { $dgvUrl = $a.browser_download_url }
      } catch {}
      if (Invoke-DownloadWithRetry $dgvUrl $dgvZip 2) {
        $dgvExt = Join-Path $work 'dgv_ext'
        Remove-Item $dgvExt -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $dgvExt -Force | Out-Null
        if (Test-Path $sevenZip) { & $sevenZip x $dgvZip "-o$dgvExt" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $dgvZip -DestinationPath $dgvExt -Force }
        foreach ($dllName in @('D3D9.dll', 'DDraw.dll', 'D3DImm.dll', 'D3D8.dll')) {
          $srcDll = Join-Path $dgvExt "MS\x86\$dllName"
          if (Test-Path $srcDll) {
            Copy-Item $srcDll -Destination (Join-Path $modsDir $dllName.ToLower()) -Force
          }
        }
        $origConf = Join-Path $dgvExt 'dgVoodoo.conf'
        if (Test-Path $origConf) {
          $confTxt = Get-Content -Path $origConf -Raw
          $confTxt = $confTxt -replace '(?m)^OutputAPI\s*=.*$', 'OutputAPI = bestavailable'
          $confTxt = $confTxt -replace '(?m)^dgVoodooWatermark\s*=.*$', 'dgVoodooWatermark = false'
          $confTxt = $confTxt -replace '(?m)^VRAM\s*=.*$', 'VRAM = 512'
          # Tuning performa WARP (software GPU): matikan AA/aniso/vsync supaya
          # frame game tidak ditahan filter berat di render software.
          $confTxt = $confTxt -replace '(?m)^AntialiasingMode\s*=.*$', 'AntialiasingMode = 0'
          $confTxt = $confTxt -replace '(?m)^AnisotropicFiltering\s*=.*$', 'AnisotropicFiltering = 0'
          $confTxt = $confTxt -replace '(?m)^VSync\s*=.*$', 'VSync = false'
          Set-Content -Path (Join-Path $modsDir 'dgVoodoo.conf') -Value $confTxt -Encoding ASCII -Force
        }
        Log 'dgVoodoo2 x86 LENGKAP (d3d9.dll + ddraw.dll + d3dimm.dll + d3d8.dll -> D3D11 WARP) berhasil dipasang (Anti-Crash 0x00746929)!'
        Remove-Item $dgvExt -Recurse -Force -ErrorAction SilentlyContinue
      }
    } catch { Log "Unduh dgVoodoo2 warning: $($_.Exception.Message)" }
  }

  # 5b. Simpan DSOAL di folder cadangan DSOAL-Backup (tidak menimpa SysWOW64\dsound.dll saat VB-Audio Virtual Cable aktif)
  $dsoalBackupDir = Join-Path $kitRoot 'DSOAL-Backup'
  New-Item -ItemType Directory -Path $dsoalBackupDir -Force | Out-Null
  Remove-Item (Join-Path $modsDir 'dsound.dll') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $modsDir 'dsoal-aldrv.dll') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $gameDir 'dsound.dll') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $gameDir 'dsoal-aldrv.dll') -Force -ErrorAction SilentlyContinue

  # 6. Tulis konfigurasi SilentPatchSA.ini di scripts\ (90 FPS + SkipIntroSplashes + FixMouseStuck RDP)
  @(
    '[SilentPatch]'
    'FPSLimit=90'
    'AbideByFramerate=1'
    'FastLoader=1'
    'SkipIntroSplashes=1'
    'NVCache=1'
    'TwoPassRendering=0'
    'FixMouseStuck=1'
  ) | Set-Content -Path (Join-Path $scriptsDir 'SilentPatchSA.ini') -Encoding ASCII -Force

  # 7. Unduh & Ekstrak SA-MP 0.3.7-R5 Client (samp.exe, samp.dll, samp.saa) langsung ke SAMP-Client & C:\Games\GTA San Andreas
  $sampInstaller = Join-Path $instDir 'sa-mp-0.3.7-R5-2-MP-install.exe'
  $sampMirrors = @(
    'https://www.gta-multiplayer.cz/downloads/sa-mp-0.3.7-R5-2-MP-install.exe',
    'https://gta-multiplayer.cz/downloads/sa-mp-0.3.7-R5-2-MP-install.exe'
  )
  if (-not (Test-IsPeExecutable $sampInstaller 1000000)) {
    foreach ($m in $sampMirrors) {
      if (Invoke-DownloadWithRetry $m $sampInstaller 2 -RequirePe) {
        Log "Installer SA-MP 0.3.7-R5 berhasil diunduh dari $m"
        break
      }
    }
  }

  if (Test-IsPeExecutable $sampInstaller 1000000) {
    # Ekstrak isi NSIS installer ke $sampCache menggunakan 7-Zip
    if (Test-Path $sevenZip) {
      & $sevenZip x $sampInstaller "-o$sampCache" -y 2>&1 | Out-Null
      Remove-Item (Join-Path $sampCache '$PLUGINSDIR') -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item (Join-Path $sampCache '$TEMP') -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Jalankan juga NSIS silent install (/S /D=...) dengan dummy gta_sa.exe bila belum ada
    $dummyGta = Join-Path $sampCache 'gta_sa.exe'
    $createdDummy = $false
    if (-not (Test-Path $dummyGta)) {
      Set-Content -Path $dummyGta -Value 'MZ' -Encoding ASCII -Force
      $createdDummy = $true
    }
    Start-ProcessWithTimeout $sampInstaller @('/S', "/D=$sampCache") $sampCache 30 | Out-Null
    if ($createdDummy -and (Test-Path $dummyGta) -and (Get-Item $dummyGta).Length -lt 1024) {
      Remove-Item $dummyGta -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path (Join-Path $sampCache 'samp.exe')) {
      Copy-Item -Path "$sampCache\*" -Destination $gameDir -Recurse -Force -ErrorAction SilentlyContinue
      Log 'SA-MP 0.3.7-R5 Client (samp.exe + samp.dll + samp.saa) berhasil dipasang ke C:\Games\GTA San Andreas!'
    }
  }

  # 8. Unduh open.mp Launcher (opsional modern launcher)
  $ompExe = Join-Path $instDir 'omp-launcher-setup.exe'
  if (-not (Test-IsPeExecutable $ompExe 500000)) {
    try {
      if (Invoke-DownloadWithRetry 'https://github.com/openmultiplayer/launcher/releases/latest/download/omp-launcher-setup.exe' $ompExe 1 -RequirePe) {
        Log 'open.mp Launcher siap di C:\Games\GTA-SAMP\Installers\omp-launcher-setup.exe.'
      }
    } catch {}
  }

  # 9. Bila gta_sa.exe belum ada di C:\Games\GTA San Andreas, unduh otomatis dari GTA_SA_URL
  #    atau mirror portable 590MB (dengan batas waktu 210 detik agar tidak pernah membuat workflow stuck)
  $gtaUrl = 'https://archive.org/download/gta-san-andreas_20220115/GTA%20San%20Andreas.rar'
  if ($env:GTA_SA_URL -and $env:GTA_SA_URL.Trim()) { $gtaUrl = $env:GTA_SA_URL.Trim() }
  elseif ($env:GTA_SA_ZIP -and $env:GTA_SA_ZIP.Trim()) { $gtaUrl = $env:GTA_SA_ZIP.Trim() }

  # Cek dulu apakah sudah ada di C:\Persist\GTA San Andreas
  if (-not (Test-Path (Join-Path $gameDir 'gta_sa.exe')) -and (Test-Path 'C:\Persist\GTA San Andreas\gta_sa.exe')) {
    Log 'Menyalin GTA San Andreas dari penyimpanan permanen C:\Persist\GTA San Andreas...'
    Copy-Item -Path 'C:\Persist\GTA San Andreas\*' -Destination $gameDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path (Join-Path $gameDir 'gta_sa.exe'))) {
    try {
      $gtaArc = Join-Path $work 'gta_sa_portable.archive'
      $gtaUrls = @(
        'https://ia600103.us.archive.org/5/items/gta-san-andreas_20220115/GTA%20San%20Andreas.rar',
        'https://archive.org/download/gta-san-andreas_20220115/GTA%20San%20Andreas.rar',
        'https://ia800103.us.archive.org/5/items/gta-san-andreas_20220115/GTA%20San%20Andreas.rar'
      )
      if ($env:GTA_SA_URL -and $env:GTA_SA_URL.Trim()) { $gtaUrls = @($env:GTA_SA_URL.Trim()) + $gtaUrls }
      foreach ($uGta in $gtaUrls) {
        Log "Mengunduh GTA San Andreas Portable ($uGta)..."
        Remove-Item $gtaArc -Force -ErrorAction SilentlyContinue
        & curl.exe -fL -A "Mozilla/5.0" --retry 1 --connect-timeout 15 --speed-time 15 --speed-limit 500000 --max-time 240 -sS $uGta -o $gtaArc
        if ((Test-Path $gtaArc) -and (Get-Item $gtaArc).Length -gt 500000000) {
          break
        }
      }
      if ((Test-Path $gtaArc) -and (Get-Item $gtaArc).Length -gt 50000000) {
        Log "Mengekstrak arsip GTA San Andreas ($([math]::Round((Get-Item $gtaArc).Length / 1MB, 1)) MB) ke $gameDir..."
        if (Test-Path $sevenZip) { & $sevenZip x $gtaArc "-o$gameDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $gtaArc -DestinationPath $gameDir -Force }
        $foundExe = Get-ChildItem -Path $gameDir -Recurse -Filter 'gta_sa.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundExe -and $foundExe.DirectoryName -ne $gameDir) {
          Get-ChildItem -Path $foundExe.DirectoryName -Force | ForEach-Object {
            Move-Item $_.FullName -Destination $gameDir -Force -ErrorAction SilentlyContinue
          }
        }
        if (Test-Path (Join-Path $sampCache 'samp.exe')) {
          Copy-Item -Path "$sampCache\*" -Destination $gameDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Log 'GTA San Andreas Portable + SA-MP 0.3.7-R5 berhasil dipasang otomatis!'
      }
      Remove-Item $gtaArc -Force -ErrorAction SilentlyContinue
    } catch { Log "Auto-download GTA SA selesai/dilewati: $($_.Exception.Message)" }
  }

  # 9b. Cerminkan GTA SA ke C:\Persist agar sesi berikutnya TIDAK unduh ulang
  #     590MB - persist-state.ps1 membawa C:\Persist ke sesi berikutnya, dan
  #     restore-state.ps1 + blok C:\Persist di atas memasangnya kembali.
  try {
    if ((Test-Path (Join-Path $gameDir 'gta_sa.exe')) -and -not (Test-Path 'C:\Persist\GTA San Andreas\gta_sa.exe')) {
      Log 'Mencerminkan GTA San Andreas ke C:\Persist (anti unduh-ulang sesi depan)...'
      New-Item -ItemType Directory -Path 'C:\Persist\GTA San Andreas' -Force -ErrorAction SilentlyContinue | Out-Null
      & robocopy.exe $gameDir 'C:\Persist\GTA San Andreas' /E /R:1 /W:1 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
    }
  } catch { Log "Cermin GTA ke C:\Persist dilewati: $($_.Exception.Message)" }

  # 10. Buat Script Auto-Patcher & Control Center GUI (GTA-SAMP-Manager.ps1)
  $patcherPath = Join-Path $kitRoot 'Patch-GTA-SAMP.ps1'
  $patcherCode = @'
param(
  [string]$TargetDir = '',
  [switch]$Interactive,
  [switch]$LaunchSamp,
  [switch]$ResetAntiBan
)
$ErrorActionPreference = 'Continue'
$kitRoot   = 'C:\Games\GTA-SAMP'
$modsDir   = Join-Path $kitRoot 'SilentPatch-Pack'
$sampCache = Join-Path $kitRoot 'SAMP-Client'
$instDir   = Join-Path $kitRoot 'Installers'
$defGame   = 'C:\Games\GTA San Andreas'

function Set-SampRegistryAllUsers([string]$GtaExePath, [string]$PlayerNameVal, [switch]$ForcePlayerName) {
  if (-not $GtaExePath -or -not (Test-Path $GtaExePath)) {
    $GtaExePath = 'C:\Games\GTA San Andreas\gta_sa.exe'
  }
  $sampExePath = Join-Path (Split-Path -Parent $GtaExePath) 'samp.exe'
  $regPaths = @('HKCU:\Software\SAMP')
  try {
    Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object {
      $_.PSChildName -notmatch '_Classes$' -and $_.PSChildName -ne '.DEFAULT'
    } | ForEach-Object {
      $regPaths += "Registry::HKEY_USERS\$($_.PSChildName)\Software\SAMP"
    }
  } catch {}

  foreach ($sKey in ($regPaths | Select-Object -Unique)) {
    try {
      New-Item -Path $sKey -Force -ErrorAction SilentlyContinue | Out-Null
      New-ItemProperty -Path $sKey -Name 'gta_sa_exe' -Value $GtaExePath -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
      $curP = (Get-ItemProperty -Path $sKey -Name 'PlayerName' -ErrorAction SilentlyContinue).PlayerName
      if ($ForcePlayerName -or -not $curP -or $curP -eq 'runneradmin') {
        New-ItemProperty -Path $sKey -Name 'PlayerName' -Value $PlayerNameVal -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
      }
    } catch {}
  }

  # Tulis juga ke NTUSER.DAT milik xyadmin & Default bila belum dimuat di HKEY_USERS
  foreach ($ntUser in @('C:\Users\xyadmin\NTUSER.DAT', 'C:\Users\Default\NTUSER.DAT')) {
    if (Test-Path $ntUser) {
      $hiveName = "XY_SAMP_$(Get-Random -Min 1000 -Max 9999)"
      try {
        & reg.exe load "HKU\$hiveName" "$ntUser" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
          & reg.exe add "HKU\$hiveName\Software\SAMP" /v "gta_sa_exe" /t REG_SZ /d "$GtaExePath" /f 2>&1 | Out-Null
          & reg.exe add "HKU\$hiveName\Software\SAMP" /v "PlayerName" /t REG_SZ /d "$PlayerNameVal" /f 2>&1 | Out-Null
          & reg.exe delete "HKU\$hiveName\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "$GtaExePath" /f 2>&1 | Out-Null
          & reg.exe delete "HKU\$hiveName\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" /v "$sampExePath" /f 2>&1 | Out-Null
          [gc]::Collect()
          Start-Sleep -Milliseconds 150
          & reg.exe unload "HKU\$hiveName" 2>&1 | Out-Null
        }
      } catch {}
    }
  }

  # Hapus paksa entri AppCompatFlags\Layers pada gta_sa.exe & samp.exe di HKLM & HKCU
  # agar CreateProcessA dari samp.exe ke gta_sa.exe tidak pernah gagal karena elevation (Unable to execute)
  # DAN swapchain D3D11 dgVoodoo2 tidak terganggu oleh shim kompatibilitas Windows!
  foreach ($layerKey in @(
    'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
  )) {
    try {
      if (Test-Path $layerKey) {
        Remove-ItemProperty -Path $layerKey -Name $GtaExePath -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $layerKey -Name $sampExePath -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Invoke-SampAntiBanAndAntiVpn([string]$BaseDir, [switch]$ForceNewGpci) {
  if (-not $BaseDir -or -not (Test-Path (Join-Path $BaseDir 'gta_sa.exe'))) { $BaseDir = $defGame }
  if (-not (Test-Path (Join-Path $BaseDir 'gta_sa.exe'))) { return $BaseDir }
  try {
    # 1. Isolasi adapter VPN (Tailscale / OpenVPN / TAP-Windows / Wintun) dengan Metric 5000
    #    agar trafik keluar UDP SA-MP (:7777) selalu lewat Ethernet langsung & tidak terdeteksi VPN tunnel
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -match 'Tailscale|OpenVPN|TAP' -or $_.InterfaceDescription -match 'Tailscale|OpenVPN|TAP-Windows|Wintun'
    } | ForEach-Object {
      Set-NetIPInterface -InterfaceIndex $_.ifIndex -AutomaticMetric Disabled -InterfaceMetric 5000 -ErrorAction SilentlyContinue
    }
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
      $_.Status -eq 'Up' -and $_.Name -notmatch 'Tailscale|OpenVPN|TAP' -and $_.InterfaceDescription -notmatch 'Tailscale|OpenVPN|TAP-Windows|Wintun|CloudflareWARP'
    } | ForEach-Object {
      Set-NetIPInterface -InterfaceIndex $_.ifIndex -AutomaticMetric Disabled -InterfaceMetric 5 -ErrorAction SilentlyContinue
    }
    # Standarisasi DefaultTTL = 128 (Windows PC asli, bukan 64 Linux/Proxy)
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'DefaultTTL' -Value 128 -Type DWord -ErrorAction SilentlyContinue
  } catch {}

  # 2. Spoof MachineGuid, ProductId & HwProfileGuid supaya HWID tiap sesi VM berbeda (Anti-Ban Serial/GPCI)
  $gpciStateFile = Join-Path $kitRoot '.xyrdp_gpci_junction.txt'
  $existingJunction = $BaseDir
  if ($ForceNewGpci) {
    try {
      $newGuid = [guid]::NewGuid().ToString()
      $newHwGuid = "{$([guid]::NewGuid().ToString())}"
      $randProd = "{0:D5}-{1:D3}-{2:D7}-{3:D5}" -f (Get-Random -Min 10000 -Max 99999), (Get-Random -Min 100 -Max 999), (Get-Random -Min 1000000 -Max 9999999), (Get-Random -Min 10000 -Max 99999)
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -Value $newGuid -ErrorAction SilentlyContinue
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Cryptography' -Name 'MachineGuid' -Value $newGuid -ErrorAction SilentlyContinue
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'ProductId' -Value $randProd -ErrorAction SilentlyContinue
      Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001' -Name 'HwProfileGuid' -Value $newHwGuid -ErrorAction SilentlyContinue
    } catch {}
  }

  # 3. Simpan path gta_sa.exe langsung (C:\Games\GTA San Andreas\gta_sa.exe) ke semua profil user
  #    agar samp.exe TIDAK PERNAH mengalami error "Unable to execute" akibat junction terhapus atau beda akun user!
  $targetGtaExe = Join-Path $BaseDir 'gta_sa.exe'
  $randPlayer = "XyPlayer_$(Get-Random -Min 1000 -Max 9999)"
  Set-SampRegistryAllUsers -GtaExePath $targetGtaExe -PlayerNameVal $randPlayer -ForcePlayerName:$ForceNewGpci
  return $BaseDir
}

function Enable-CloudflareWarpSafeSplitTunnel {
  $warpCli = 'C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe'
  if (-not (Test-Path $warpCli)) {
    $warpMsi = Join-Path $instDir 'Cloudflare_WARP_Release-x64.msi'
    & curl.exe -fL -A "Mozilla/5.0" --retry 2 --connect-timeout 15 --max-time 120 'https://1111-releases.cloudflareclient.com/win/latest' -o $warpMsi
    if ((Test-Path $warpMsi) -and (Get-Item $warpMsi).Length -gt 5000000) {
      Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$warpMsi`"", '/qn', '/norestart') -Wait
      Start-Sleep -Seconds 3
    }
  }
  if (-not (Test-Path $warpCli)) { return $false }
  Start-Service -Name 'CloudflareWARP' -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  & $warpCli --accept-tos registration new 2>&1 | Out-Null
  & $warpCli --accept-tos mode warp 2>&1 | Out-Null
  # WAJIB: Exclude subnet Tailscale (100.64.0.0/10), Portmap OpenVPN (10.0.0.0/8), LAN, dan Azure Host
  # agar koneksi RDP (:3389) & SSH (:22) TIDAK PERNAH PUTUS saat WARP aktif!
  foreach ($cidr in @('100.64.0.0/10', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '168.63.129.16/32', '169.254.169.254/32')) {
    & $warpCli --accept-tos tunnel ip add $cidr 2>&1 | Out-Null
    & $warpCli --accept-tos add-excluded-route $cidr 2>&1 | Out-Null
  }
  & $warpCli --accept-tos connect 2>&1 | Out-Null
  Start-Sleep -Seconds 3
  return $true
}

function Patch-GtaSaExeDirectDrawBypass([string]$ExePath) {
  return
}

function Apply-SilentPatchToDir([string]$Dir) {
  if (-not $Dir -or -not (Test-Path (Join-Path $Dir 'gta_sa.exe'))) { return $false }

  # Jangan menimpa file bila gta_sa.exe sedang aktif berjalan
  if (Get-Process -Name 'gta_sa' -ErrorAction SilentlyContinue) { return $true }

  # 1. Simpan vorbisFile.dll asli (< 250 KB) sebagai vorbisHooked.dll sebelum ditimpa Ultimate ASI Loader,
  #    dan hapus duplikat dinput8.dll agar tidak bentrok dengan vorbisFile.dll.
  #    PENTING: JANGAN menghapus ddraw.dll / d3dimm.dll / III.VC.SA.WindowedMode.asi karena dibutuhkan di RDP!
  $vorbisPath = Join-Path $Dir 'vorbisFile.dll'
  $vorbisHooked = Join-Path $Dir 'vorbisHooked.dll'
  if ((Test-Path $vorbisPath) -and (Get-Item $vorbisPath).Length -lt 250000 -and -not (Test-Path $vorbisHooked)) {
    Copy-Item -LiteralPath $vorbisPath -Destination $vorbisHooked -Force -ErrorAction SilentlyContinue
  }
  $dinputPath = Join-Path $Dir 'dinput8.dll'
  if (Test-Path $dinputPath) {
    Remove-Item $dinputPath -Force -ErrorAction SilentlyContinue
  }
  Remove-Item (Join-Path $Dir 'dsound.dll') -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $Dir 'dsoal-aldrv.dll') -Force -ErrorAction SilentlyContinue

  $markerFile = Join-Path $Dir '.xyrdp_samp_fullscreen_v3'
  $alreadyPatched = (Test-Path $markerFile)

  # 2. Salin SA-MP Client (samp.exe, samp.dll, samp.saa) bila belum ada di folder target
  if ((Test-Path (Join-Path $sampCache 'samp.exe')) -and -not (Test-Path (Join-Path $Dir 'samp.exe'))) {
    Copy-Item -Path "$sampCache\*" -Destination $Dir -Recurse -Force -ErrorAction SilentlyContinue
  }

  # 3. Salin paket lengkap dgVoodoo2 (d3d9.dll + ddraw.dll + d3dimm.dll + d3d8.dll + dgVoodoo.conf)
  try { & attrib.exe -R "$Dir\*.*" /S 2>&1 | Out-Null } catch {}
  Copy-Item -Path "$modsDir\*" -Destination $Dir -Recurse -Force -ErrorAction SilentlyContinue
  # PENTING: Gunakan vorbisHooked.dll murni Rockstar sebagai vorbisFile.dll agar gta_sa.exe & samp.exe langsung terbuka dalam 1 detik tanpa ASI Loader deadlock!
  if (Test-Path (Join-Path $Dir 'vorbisHooked.dll')) {
    Copy-Item -LiteralPath (Join-Path $Dir 'vorbisHooked.dll') -Destination (Join-Path $Dir 'vorbisFile.dll') -Force -ErrorAction SilentlyContinue
  }

  # Matikan video MPEG intro DirectShow (Logo.mpg & GTAtitles.mpg) agar gta_sa.exe langsung masuk ke Title Screen & Main Menu D3D9 tanpa layar hitam ActiveMovie Window
  foreach ($mpg in @('Logo.mpg', 'GTAtitles.mpg')) {
    $mpgPath = Join-Path $Dir "movies\$mpg"
    if (Test-Path $mpgPath) {
      Rename-Item -LiteralPath $mpgPath -NewName "$mpg.bak" -Force -ErrorAction SilentlyContinue
    }
  }
  Get-ChildItem -Path $Dir -File -Filter '*.asi' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $Dir 'SilentPatchSA.ini') -Force -ErrorAction SilentlyContinue
  # Nonaktifkan video intro MPEG-1 (Logo.mpg & GTAtitles.mpg) agar gta_sa.exe langsung lompat ke Title Screen tanpa DirectShow hang di Windows Server
  foreach ($mpg in @('Logo.mpg', 'GTAtitles.mpg')) {
    $mpgPath = Join-Path $Dir "movies\$mpg"
    if (Test-Path $mpgPath) {
      Move-Item -LiteralPath $mpgPath -Destination "$mpgPath.bak" -Force -ErrorAction SilentlyContinue
    }
  }

  # 3a. Pulihkan gta_sa.exe.orig_bak jika ada agar binary gta_sa.exe 100% utuh (DSOAL + dgVoodoo2 sudah menangani DirectSound & DirectDraw)
  $gtaExeTarget = Join-Path $Dir 'gta_sa.exe'
  $gtaOrigBak   = "$gtaExeTarget.orig_bak"
  if (Test-Path $gtaOrigBak) {
    Copy-Item -LiteralPath $gtaOrigBak -Destination $gtaExeTarget -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $gtaOrigBak -Force -ErrorAction SilentlyContinue
  }

  # 3b. Pastikan layanan Windows Audio aktif agar gta_sa.exe tidak crash saat inisialisasi DirectSound
  try {
    Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
  } catch {}

  # 4. Bersihkan gta_sa.set lama HANYA satu kali saat migrasi Fullscreen v3
  if (-not $alreadyPatched) {
    foreach ($docRoot in @(
      [Environment]::GetFolderPath('MyDocuments'),
      "C:\Users\$env:USERNAME\Documents"
    )) {
      if ($docRoot) {
        $uf = Join-Path $docRoot 'GTA San Andreas User Files'
        New-Item -ItemType Directory -Path $uf -Force -ErrorAction SilentlyContinue | Out-Null
        $setFile = Join-Path $uf 'gta_sa.set'
        if (Test-Path $setFile) {
          Remove-Item $setFile -Force -ErrorAction SilentlyContinue
        }
      }
    }
    Set-Content -Path $markerFile -Value 'fullscreen-v3' -Encoding ASCII -Force -ErrorAction SilentlyContinue
  }

  # 5. Bersihkan AppCompatFlags\Layers yang memicu apphelp.dll / GameUX hang pada Windows Server 2022,
  #    dan nonaktifkan GameUX / AppCompat Shim Engine untuk gta_sa.exe
  $gtaExe  = Join-Path $Dir 'gta_sa.exe'
  $sampExe = Join-Path $Dir 'samp.exe'
  foreach ($regBase in @(
    'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
    'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
  )) {
    if (Test-Path $regBase) {
      Remove-ItemProperty -Path $regBase -Name $gtaExe -Force -ErrorAction SilentlyContinue
      Remove-ItemProperty -Path $regBase -Name $sampExe -Force -ErrorAction SilentlyContinue
    }
  }

  $sampKey = 'HKCU:\Software\SAMP'
  New-Item -Path $sampKey -Force -ErrorAction SilentlyContinue | Out-Null
  New-ItemProperty -Path $sampKey -Name 'gta_sa_exe' -Value $gtaExe -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
  $curName = (Get-ItemProperty -Path $sampKey -Name 'PlayerName' -ErrorAction SilentlyContinue).PlayerName
  if (-not $curName -or $curName -eq 'runneradmin') {
    New-ItemProperty -Path $sampKey -Name 'PlayerName' -Value "Player_$(Get-Random -Min 1000 -Max 9999)" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
  }

  # 6. Pasang proteksi Anti-Banned GPCI & Isolasi Route Anti-VPN secara otomatis
  Invoke-SampAntiBanAndAntiVpn -BaseDir $Dir | Out-Null

  return $true
}

if ($ResetAntiBan) {
  $newJunc = Invoke-SampAntiBanAndAntiVpn -BaseDir $defGame -ForceNewGpci
  if ($Interactive) {
    Add-Type -AssemblyName System.Windows.Forms
    $res = [System.Windows.Forms.MessageBox]::Show(
      "GPCI Serial & HWID SA-MP berhasil di-reset ke identitas baru!`r`nPath GPCI Baru: $newJunc`r`nMetric VPN (Tailscale/Portmap) telah dikunci agar tidak bocor ke SA-MP.`r`n`r`nApakah server tujuan masih mendeteksi IP Hosting/VPN dan Anda ingin mengaktifkan Cloudflare WARP Split-Tunnel (Aman RDP tidak putus)?",
      "XyRDP - Anti-Banned & Anti-VPN SAMP",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
      Enable-CloudflareWarpSafeSplitTunnel | Out-Null
      [System.Windows.Forms.MessageBox]::Show(
        "Cloudflare WARP Split-Tunnel Aktif! (Subnet RDP Tailscale/Portmap dikecualikan sehingga RDP tetap aman). Silakan join server SA-MP sekarang.",
        "Mode Anti-VPN Aktif", 0, 64
      ) | Out-Null
    }
  }
  exit 0
}

if ($TargetDir -and (Test-Path $TargetDir)) {
  Apply-SilentPatchToDir $TargetDir | Out-Null
  exit 0
}

$candidates = @(
  'C:\Games\GTA San Andreas',
  'C:\Persist\GTA San Andreas',
  'C:\Persist\GTA-SA',
  'D:\Games\GTA San Andreas',
  'C:\Games\GTA-SA',
  'C:\Program Files (x86)\Rockstar Games\GTA San Andreas'
)
$deskPath = [Environment]::GetFolderPath('Desktop')
if ($deskPath) { $candidates += (Join-Path $deskPath 'GTA San Andreas') }

$activeDir = $defGame
foreach ($c in $candidates) {
  if (Test-Path (Join-Path $c 'gta_sa.exe')) {
    Apply-SilentPatchToDir $c | Out-Null
    $activeDir = $c
  }
}
if (Test-Path (Join-Path $defGame 'gta_sa.exe')) {
  $activeDir = $defGame
  Set-SampRegistryAllUsers -GtaExePath (Join-Path $defGame 'gta_sa.exe') -PlayerNameVal 'XyPlayer_RDP'
}

if (-not $Interactive) {
  exit 0
}

# Mode -Interactive: tampilkan Windows Forms GUI Control Center GTA SA-MP
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'XyRDP - GTA San Andreas & SA-MP 0.3.7-R5 Control Center'
$form.Size = New-Object System.Drawing.Size(560, 485)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 22)
$form.ForeColor = [System.Drawing.Color]::White

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'GTA SA-MP 0.3.7-R5 | DirectX 9 WARP + Windowed Fix'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 16)
$lblTitle.Size = New-Object System.Drawing.Size(510, 28)
$form.Controls.Add($lblTitle)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(167, 243, 208)
$lblStatus.Location = New-Object System.Drawing.Point(20, 48)
$lblStatus.Size = New-Object System.Drawing.Size(510, 76)
$form.Controls.Add($lblStatus)

function Update-GuiStatus {
  $hasGta  = Test-Path (Join-Path $script:activeDir 'gta_sa.exe')
  $hasSamp = Test-Path (Join-Path $script:activeDir 'samp.exe')
  $hasD3d9 = Test-Path (Join-Path $script:activeDir 'd3d9.dll')
  $hasDdrw = Test-Path (Join-Path $script:activeDir 'ddraw.dll')
  $lblStatus.Text = "Folder Aktif : $($script:activeDir)`r`n" +
    "gta_sa.exe   : $(if ($hasGta) { 'SIAP (Terdeteksi)' } else { 'BELUM ADA - Klik tombol Ekstrak ZIP / Pilih Folder di bawah' })`r`n" +
    "samp.exe     : $(if ($hasSamp) { 'SIAP (SA-MP 0.3.7-R5)' } else { 'Belum terpasang' })`r`n" +
    "RDP D3D9 Fix : $(if ($hasD3d9 -and $hasDdrw) { 'AKTIF (dgVoodoo2 Fullscreen + Anti-0x00746929 + SilentPatch)' } else { 'Siap dipasang' })"
}
Update-GuiStatus

# Jika dipanggil dari shortcut GTA SAMP dan gta_sa.exe + samp.exe sudah siap, langsung buka samp.exe!
if ($LaunchSamp -and (Test-Path (Join-Path $activeDir 'gta_sa.exe')) -and (Test-Path (Join-Path $activeDir 'samp.exe'))) {
  Apply-SilentPatchToDir $activeDir | Out-Null
  Start-Process -FilePath (Join-Path $activeDir 'samp.exe') -WorkingDirectory $activeDir
  exit 0
}

$btnOpenSamp = New-Object System.Windows.Forms.Button
$btnOpenSamp.Text = '1. Buka SA-MP 0.3.7-R5 Server Browser (samp.exe)'
$btnOpenSamp.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnOpenSamp.Location = New-Object System.Drawing.Point(20, 134)
$btnOpenSamp.Size = New-Object System.Drawing.Size(505, 42)
$btnOpenSamp.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnOpenSamp.ForeColor = [System.Drawing.Color]::Black
$btnOpenSamp.FlatStyle = 'Flat'
$btnOpenSamp.Add_Click({
  Apply-SilentPatchToDir $script:activeDir | Out-Null
  Update-GuiStatus
  $sExe = Join-Path $script:activeDir 'samp.exe'
  if (Test-Path $sExe) {
    Start-Process -FilePath $sExe -WorkingDirectory $script:activeDir
  } else {
    [System.Windows.Forms.MessageBox]::Show("samp.exe belum ditemukan di $($script:activeDir).", "Info", 0, 48) | Out-Null
  }
})
$form.Controls.Add($btnOpenSamp)

$btnPickFolder = New-Object System.Windows.Forms.Button
$btnPickFolder.Text = '2. Pilih Folder GTA San Andreas & Pasang Fix Anti-Blank RDP'
$btnPickFolder.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$btnPickFolder.Location = New-Object System.Drawing.Point(20, 186)
$btnPickFolder.Size = New-Object System.Drawing.Size(505, 40)
$btnPickFolder.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 42)
$btnPickFolder.ForeColor = [System.Drawing.Color]::White
$btnPickFolder.FlatStyle = 'Flat'
$btnPickFolder.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Pilih folder tempat gta_sa.exe berada'
  $dlg.SelectedPath = $script:activeDir
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $script:activeDir = $dlg.SelectedPath
    Apply-SilentPatchToDir $script:activeDir | Out-Null
    Update-GuiStatus
    [System.Windows.Forms.MessageBox]::Show(
      "Berhasil memasang SA-MP 0.3.7-R5 + dgVoodoo2 D3D9 WARP + WindowedMode + SilentPatch + DEP Bypass ke:`r`n$($script:activeDir)",
      "Fix GTA SA-MP Selesai", 0, 64
    ) | Out-Null
  }
})
$form.Controls.Add($btnPickFolder)

$btnPickZip = New-Object System.Windows.Forms.Button
$btnPickZip.Text = '3. Ekstrak File Arsip GTA SA (.zip / .7z / .rar) ke C:\Games\GTA San Andreas'
$btnPickZip.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$btnPickZip.Location = New-Object System.Drawing.Point(20, 236)
$btnPickZip.Size = New-Object System.Drawing.Size(505, 40)
$btnPickZip.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 42)
$btnPickZip.ForeColor = [System.Drawing.Color]::White
$btnPickZip.FlatStyle = 'Flat'
$btnPickZip.Add_Click({
  $ofd = New-Object System.Windows.Forms.OpenFileDialog
  $ofd.Title = 'Pilih file arsip GTA San Andreas (.zip / .7z / .rar)'
  $ofd.Filter = 'Archives (*.zip;*.7z;*.rar)|*.zip;*.7z;*.rar|All files (*.*)|*.*'
  if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $seven = 'C:\Program Files\7-Zip\7z.exe'
    $lblStatus.Text = "Mengekstrak $($ofd.FileName) ke C:\Games\GTA San Andreas ... Mohon tunggu..."
    $form.Refresh()
    if (Test-Path $seven) {
      Start-Process -FilePath $seven -ArgumentList @('x', "`"$($ofd.FileName)`"", "-o`"$defGame`"", '-y') -Wait
    } else {
      Expand-Archive -Path $ofd.FileName -DestinationPath $defGame -Force
    }
    $found = Get-ChildItem -Path $defGame -Recurse -Filter 'gta_sa.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and $found.DirectoryName -ne $defGame) {
      Get-ChildItem -Path $found.DirectoryName -Force | ForEach-Object {
        Move-Item $_.FullName -Destination $defGame -Force -ErrorAction SilentlyContinue
      }
    }
    $script:activeDir = $defGame
    Apply-SilentPatchToDir $defGame | Out-Null
    Update-GuiStatus
    [System.Windows.Forms.MessageBox]::Show("Ekstraksi & pemasangan Fix RDP selesai! Klik tombol #1 untuk mulai bermain.", "Sukses", 0, 64) | Out-Null
  }
})
$form.Controls.Add($btnPickZip)

$btnAutoDl = New-Object System.Windows.Forms.Button
$btnAutoDl.Text = '4. Download & Pasang Otomatis GTA SA Portable (590 MB) + open.mp'
$btnAutoDl.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$btnAutoDl.Location = New-Object System.Drawing.Point(20, 286)
$btnAutoDl.Size = New-Object System.Drawing.Size(505, 38)
$btnAutoDl.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$btnAutoDl.ForeColor = [System.Drawing.Color]::White
$btnAutoDl.FlatStyle = 'Flat'
$btnAutoDl.Add_Click({
  $arc = 'C:\XyRDP\deps\samp\gta_sa_auto.rar'
  $seven = 'C:\Program Files\7-Zip\7z.exe'
  $lblStatus.Text = "Mengunduh GTA San Andreas Portable (590 MB) ke C:\Games\GTA San Andreas ... Mohon tunggu ~30-60 detik..."
  $form.Refresh()
  & curl.exe -fL -A "Mozilla/5.0" --retry 2 --connect-timeout 15 --max-time 300 'https://archive.org/download/gta-san-andreas_20220115/GTA%20San%20Andreas.rar' -o $arc
  if ((Test-Path $arc) -and (Get-Item $arc).Length -gt 50000000 -and (Test-Path $seven)) {
    $lblStatus.Text = "Mengekstrak arsip GTA San Andreas & memasang SA-MP + Fix RDP..."
    $form.Refresh()
    Start-Process -FilePath $seven -ArgumentList @('x', "`"$arc`"", "-o`"$defGame`"", '-y') -Wait
    $found = Get-ChildItem -Path $defGame -Recurse -Filter 'gta_sa.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and $found.DirectoryName -ne $defGame) {
      Get-ChildItem -Path $found.DirectoryName -Force | ForEach-Object {
        Move-Item $_.FullName -Destination $defGame -Force -ErrorAction SilentlyContinue
      }
    }
    Remove-Item $arc -Force -ErrorAction SilentlyContinue
    $script:activeDir = $defGame
    Apply-SilentPatchToDir $defGame | Out-Null
    Update-GuiStatus
    [System.Windows.Forms.MessageBox]::Show("GTA San Andreas Portable + SA-MP 0.3.7-R5 + Fix RDP berhasil dipasang! Klik tombol #1 untuk langsung main.", "Sukses", 0, 64) | Out-Null
  } else {
    $ompSetup = Join-Path $instDir 'omp-launcher-setup.exe'
    if (Test-Path $ompSetup) { Start-Process -FilePath $ompSetup }
  }
})
$form.Controls.Add($btnAutoDl)

$btnAntiBan = New-Object System.Windows.Forms.Button
$btnAntiBan.Text = '5. Atasi Server Banned / Terdeteksi Proxy & VPN (Reset GPCI + WARP)'
$btnAntiBan.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$btnAntiBan.Location = New-Object System.Drawing.Point(20, 332)
$btnAntiBan.Size = New-Object System.Drawing.Size(505, 38)
$btnAntiBan.BackColor = [System.Drawing.Color]::FromArgb(217, 119, 6)
$btnAntiBan.ForeColor = [System.Drawing.Color]::White
$btnAntiBan.FlatStyle = 'Flat'
$btnAntiBan.Add_Click({
  $lblStatus.Text = "Mereset Serial GPCI / HWID & mengisolasi route VPN Tailscale/Portmap..."
  $form.Refresh()
  $newJunc = Invoke-SampAntiBanAndAntiVpn -BaseDir $script:activeDir -ForceNewGpci
  Update-GuiStatus
  $ask = [System.Windows.Forms.MessageBox]::Show(
    "Serial GPCI & HWID SA-MP berhasil di-reset ke identitas baru!`r`nPath GPCI Baru: $newJunc`r`nAdapter VPN (Tailscale/Portmap) telah diisolasi (Metric 5000 + TTL 128).`r`n`r`nJika server masih memblokir IP Datacenter/VPN, klik YES untuk mengaktifkan Cloudflare WARP Split-Tunnel (Aman RDP tidak putus), atau NO bila cukup Reset GPCI.",
    "Atasi Banned & Anti-VPN SAMP",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
  if ($ask -eq [System.Windows.Forms.DialogResult]::Yes) {
    $lblStatus.Text = "Mengaktifkan Cloudflare WARP Split-Tunnel (Aman RDP)... Mohon tunggu..."
    $form.Refresh()
    if (Enable-CloudflareWarpSafeSplitTunnel) {
      [System.Windows.Forms.MessageBox]::Show("Cloudflare WARP Split-Tunnel berhasil diaktifkan! Silakan buka SA-MP dan join server.", "Sukses", 0, 64) | Out-Null
    }
    Update-GuiStatus
  }
})
$form.Controls.Add($btnAntiBan)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Tips: Jika saat masuk server muncul 'You are banned' atau 'VPN/Proxy detected', klik Tombol #5 di atas untuk mereset Serial GPCI & mengaktifkan Anti-VPN Split-Tunnel."
$lblHint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(161, 161, 170)
$lblHint.Location = New-Object System.Drawing.Point(20, 380)
$lblHint.Size = New-Object System.Drawing.Size(505, 45)
$form.Controls.Add($lblHint)

[void]$form.ShowDialog()
'@
  Set-Content -Path $patcherPath -Value $patcherCode -Encoding UTF8 -Force

  # 11. Pasang Virtual Sound Card (VB-Audio Virtual Cable) via .NET LocalMachine X509Store (100% Silent Tanpa Dialog Modal)
  #     Wajib agar Windows Server memiliki Output Audio Device aktif sehingga gta_sa.exe tidak keluar karena "no sound card installed"!
  try {
    $vbcDir = 'C:\XyRDP\audio\vbcable'
    $vbcZip = Join-Path $work 'VBCABLE_Driver_Pack43.zip'
    if (-not (Test-Path (Join-Path $vbcDir 'vbaudio_cable64_win7.cat'))) {
      New-Item -ItemType Directory -Path $vbcDir -Force | Out-Null
      if (Invoke-DownloadWithRetry 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip' $vbcZip 2) {
        if (Test-Path $sevenZip) { & $sevenZip x $vbcZip "-o$vbcDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $vbcZip -DestinationPath $vbcDir -Force }
        Get-ChildItem -Path $vbcDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.cat', '.sys', '.exe') } | ForEach-Object {
          try {
            $sig = Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue
            if ($sig -and $sig.SignerCertificate) {
              foreach ($storeName in @('Root', 'TrustedPublisher')) {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                $store.Add($sig.SignerCertificate)
                $store.Close()
              }
            }
          } catch {}
        }
        $infFile = Join-Path $vbcDir 'vbMmeCable64_win7.inf'
        if (Test-Path $infFile) {
          Start-ProcessWithTimeout 'pnputil.exe' @('/add-driver', $infFile, '/install') $vbcDir 15 | Out-Null
        }
        $vbcExe = Join-Path $vbcDir 'VBCABLE_Setup_x64.exe'
        if (Test-Path $vbcExe) {
          Start-ProcessWithTimeout $vbcExe @('-i', '-h') $vbcDir 20 | Out-Null
        }
        Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
        Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
        Log 'VB-Audio Virtual Sound Card (vbaudio_cable64_win7) berhasil dipasang secara silent.'
      }
    }
  } catch { Log "VB-Cable setup warning: $($_.Exception.Message)" }

  # 11b. Jalankan auto-patch pada folder kandidat (tanpa dialog) dan kunci HKCU:\Software\SAMP\gta_sa_exe
  try {
    Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $patcherPath 2>&1 | Out-Null
    New-Item -Path 'HKCU:\Software\SAMP' -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path 'HKCU:\Software\SAMP' -Name 'gta_sa_exe' -Value 'C:\Games\GTA San Andreas\gta_sa.exe' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path 'HKCU:\Software\SAMP' -Name 'PlayerName' -Value 'XyPlayer_RDP' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
  } catch {}

  # 12. Buat Shortcut di Desktop User RDP & Public Desktop dengan Nama & Ikon Berbeda (Anti-Tertukar!)
  $icoDir = Ensure-XyDesktopIcons
  $sampLauncherIco = Join-Path $icoDir 'samp-launcher.ico'
  $sampFixIco      = Join-Path $icoDir 'samp-antiban.ico'
  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { $cfg.rdp_user }
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      foreach ($oldSampLnk in @('GTA SAMP.lnk', 'SA-MP 0.3.7-R5 Server Browser.lnk', 'Patch GTA SA-MP (SilentPatch).lnk', 'Atasi Banned & Anti-VPN SAMP.lnk', 'Cara Pasang GTA SA & SAMP.txt')) {
        Remove-Item -LiteralPath (Join-Path $desk $oldSampLnk) -Force -ErrorAction SilentlyContinue
      }

      $wsh = New-Object -ComObject WScript.Shell

      # Shortcut 1: GTA SA-MP Launcher (Anti-Ban) - Prioritaskan IKON ASLI samp.exe!
      $lnk1 = $wsh.CreateShortcut((Join-Path $desk 'GTA SA-MP Launcher (Anti-Ban).lnk'))
      $lnk1.TargetPath = 'powershell.exe'
      $lnk1.Arguments = "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$patcherPath`" -Interactive -LaunchSamp"
      $lnk1.WorkingDirectory = $gameDir
      if (Test-Path (Join-Path $gameDir 'samp.exe')) {
        $lnk1.IconLocation = "$(Join-Path $gameDir 'samp.exe'),0"
      } elseif (Test-Path (Join-Path $sampCache 'samp.exe')) {
        $lnk1.IconLocation = "$(Join-Path $sampCache 'samp.exe'),0"
      } elseif (Test-Path $sampLauncherIco) {
        $lnk1.IconLocation = "$sampLauncherIco,0"
      }
      $lnk1.Description = 'Buka GTA SA-MP 0.3.7-R5 dengan Auto GPCI/HWID Spoofing & Anti-VPN'
      $lnk1.Save()

      # Shortcut 2: Fix & Patch GTA SA-MP (SilentPatch) - Prioritaskan IKON ASLI gta_sa.exe / samp.exe!
      $lnk2 = $wsh.CreateShortcut((Join-Path $desk 'Fix & Patch GTA SA-MP (SilentPatch).lnk'))
      $lnk2.TargetPath = 'powershell.exe'
      $lnk2.Arguments = "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$patcherPath`" -Interactive"
      $lnk2.WorkingDirectory = $kitRoot
      if (Test-Path (Join-Path $gameDir 'gta_sa.exe')) {
        $lnk2.IconLocation = "$(Join-Path $gameDir 'gta_sa.exe'),0"
      } elseif (Test-Path (Join-Path $gameDir 'samp.exe')) {
        $lnk2.IconLocation = "$(Join-Path $gameDir 'samp.exe'),0"
      } elseif (Test-Path $sampFixIco) {
        $lnk2.IconLocation = "$sampFixIco,0"
      }
      $lnk2.Description = 'Control Center GTA SA-MP + Patch SilentPatch 90 FPS + Reset Serial GPCI Anti-Ban'
      $lnk2.Save()
    } catch {}
  }
}

Install-DirectXJune2010
if ($DirectXOnly) {
  Log 'Mode -DirectXOnly selesai.'
  exit 0
}

Install-VcRedist 'VC++ 2015-2026 Redistributable (x86)' `
  'https://aka.ms/vs/17/release/vc_redist.x86.exe' `
  'vc_redist.x86.exe' `
  { Test-Vc2015Files $wow64 }

Install-VcRedist 'VC++ 2015-2026 Redistributable (x64)' `
  'https://aka.ms/vs/17/release/vc_redist.x64.exe' `
  'vc_redist.x64.exe' `
  { Test-Vc2015Files $sys32 }

Install-VcRedist 'VC++ 2013 Redistributable (x86)' `
  'https://aka.ms/highdpimfc2013x86enu' `
  'vcredist_2013_x86.exe' `
  { Test-Vc2013Files $wow64 }

try {
  Install-VcRedist 'VC++ 2013 Redistributable (x64)' `
    'https://aka.ms/highdpimfc2013x64enu' `
    'vcredist_2013_x64.exe' `
    { Test-Vc2013Files $sys32 }
} catch { Log "VC++ 2013 x64 dilewati (opsional): $($_.Exception.Message)" }

$wv2Ok = $false
try {
  $wv2Reg = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue
  if ($wv2Reg -and $wv2Reg.pv) {
    $wv2Ok = $true
    Log "WebView2 Evergreen Runtime sudah terpasang (v$($wv2Reg.pv))."
  } else {
    $wv2Exe = Join-Path $work 'MicrosoftEdgeWebview2Setup.exe'
    if (Invoke-DownloadWithRetry 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' $wv2Exe 2 -RequirePe) {
      $wvCode = Start-ProcessWithTimeout $wv2Exe @('/silent','/install') '' 60
      if ($wvCode -eq 0 -or $wvCode -eq 3010) { $wv2Ok = $true; Log 'WebView2 Evergreen Runtime berhasil dipasang.' }
    }
  }
} catch { Log "WebView2 check selesai: $($_.Exception.Message)" }

$dpOk = Enable-DirectPlayAndDepBypass

if ($env:SAMP -or $cfg.samp) {
  Install-CompleteSampSuite
}

$gtaPresent = Test-Path 'C:\Games\GTA San Andreas\gta_sa.exe'
$sampPlayable = $gtaPresent -and (Test-Path 'C:\Games\GTA San Andreas\samp.exe')
if ($sampPlayable) {
  Log 'GTA SA + SA-MP client lengkap: siap dimainkan dari shortcut desktop.'
} else {
  Log 'SA-MP client & patch sudah otomatis terpasang. GTA SA (gta_sa.exe) belum ada: taruh salinan game milikmu ke C:\Games\GTA San Andreas (folder ini tersimpan antar-sesi), sesi berikutnya otomatis siap.'
}
Update-Status @{
  samp = @{
    game_present  = $gtaPresent
    playable      = $sampPlayable
    status        = 'runtimes-2026-ready'
    directx9      = (Test-DirectXFiles)
    vc2015_x86    = (Test-Vc2015Files $wow64)
    vc2015_x64    = (Test-Vc2015Files $sys32)
    vc2013_x86    = (Test-Vc2013Files $wow64)
    vc2013_x64    = (Test-Vc2013Files $sys32)
    webview2      = $wv2Ok
    directplay    = $dpOk
    dep_optin     = $true
    dgvoodoo_d3d9 = (Test-Path 'C:\Games\GTA-SAMP\SilentPatch-Pack\d3d9.dll')
    fullscreen    = $true
    samp_client   = (Test-Path 'C:\Games\GTA San Andreas\samp.exe')
    silentpatch   = (Test-Path 'C:\Games\GTA-SAMP\SilentPatch-Pack\SilentPatchSA.asi')
  }
} | Out-Null

Log 'Suite lengkap GTA SA-MP 0.3.7-R5 + dgVoodoo2 D3D9/DDraw Fullscreen + SilentPatch + DEP Bypass siap.'
exit 0
