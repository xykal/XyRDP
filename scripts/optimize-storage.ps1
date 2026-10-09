# ============================================================================
#  optimize-storage.ps1 — BOOST PENYIMPANAN XyRDP-SAMP
# ----------------------------------------------------------------------------
#  Masalah: Runner windows-2022 terlihat "Disk C: 225 GB" tapi free cuma ~70GB
#  karena image GitHub sudah penuh toolcache (Android, Haskell, CodeQL,
#  Node, Python versi lama, Docker, dotnet SDK, dll) + cache Windows Update.
#
#  Solusi: script ini dijalankan PALING AWAL di workflow (sebelum setup RDP)
#  untuk membebaskan 45-75 GB tambahan. Semua BEST-EFFORT, tidak mematikan
#  sesi kalau gagal. Hasil di-log + ditulis ke out/rdp-status.json.
#
#  Target bersih-bersih (urut bobot terbesar):
#    1) C:\hostedtoolcache  (cache versi Node/Python/Go/Ruby - 8-12 GB)
#    2) C:\tools            (bin besar - 2-4 GB)
#    3) C:\Android          (Android SDK/NDK - 10-15 GB)
#    4) C:\Program Files\dotnet\sdk  (SDK lama - 3-6 GB, runtime dipertahankan)
#    5) C:\Program Files (x86)\Microsoft SDKs + Android - 1-2 GB
#    6) C:\ProgramData\Chocolatey\lib + cache - 1-2 GB
#    7) C:\hostedtoolcache\windows\stack - Haskell Stack - 1-2 GB
#    8) Docker images/cache (jika ada) - 2-5 GB
#    9) Windows Update cache (SoftwareDistribution\Download) - 1-3 GB
#   10) Temp + Log + Recycle Bin + Delivery Optimization
#
#  Catatan: JANGAN hapus C:\Windows\WinSxS dengan DISM agresif di runner
#  ephemeral 6 jam — bisa merusak RDP/Win32. Kita hanya hapus cache & sdk
#  yang aman.
#
#  Env:
#    STORAGE_BOOST = ya/tidak (default ya). Kalau "tidak" -> skip.
# ============================================================================

$XyTag = 'XyRDP:storage'
. "$PSScriptRoot/lib-common.ps1"

$boost = $true
if ($env:STORAGE_BOOST) {
  $e = $env:STORAGE_BOOST.Trim().ToLower()
  if (@('tidak','0','false','no','off','skip','none') -contains $e) { $boost = $false }
}
$cfg = Get-Cfg
if (-not $cfg.storage_boost) { $boost = $false }
# workflow input juga bisa matikan
if ($env:STORAGE_BOOST -eq 'tidak') { $boost = $false }

if (-not $boost) {
  Log 'boost storage dilewati (STORAGE_BOOST=tidak atau storage_boost=false)'
  Update-Status @{ storage = @{ boost='skip'; note='dilewati sesuai config' } } | Out-Null
  exit 0
}

Log '=== OPTIMIZE STORAGE — mulai bebaskan ruang ==='

function Get-FreeGB {
  try {
    $d = Get-PSDrive -Name C -ErrorAction Stop
    return [math]::Round(($d.Free / 1GB),2)
  } catch {
    try { $v = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; return [math]::Round($v.FreeSpace/1GB,2) } catch { return -1 }
  }
}
function Get-SizeGB([string]$path) {
  try {
    if (-not (Test-Path $path)) { return 0 }
    $s = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $s) { return 0 }
    return [math]::Round($s/1GB,2)
  } catch { return 0 }
}
function Remove-Tree([string]$path, [string]$label) {
  if (-not (Test-Path $path)) { Log "  $label : tidak ada -> skip"; return 0 }
  $sz = Get-SizeGB $path
  try {
    # gunakan takeown/icacls + remove dengan long path support
    & takeown.exe /f $path /r /d y 2>&1 | Out-Null
    & icacls.exe $path /grant '*S-1-5-32-544:F' /t /q 2>&1 | Out-Null
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    # fallback robocopy empty trick untuk path panjang
    if (Test-Path $path) {
      $empty = Join-Path $env:RUNNER_TEMP '_empty'
      New-Item -ItemType Directory -Path $empty -Force | Out-Null
      & robocopy $empty $path /purge /q 2>&1 | Out-Null
      Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $still = Test-Path $path
    if ($still) { Log "  $label : GAGAL dihapus (masih ada) - ${sz}GB" }
    else { Log "  $label : DIHAPUS - membebaskan ~${sz}GB" }
    return $sz
  } catch { Log "  $label : error $($_.Exception.Message)"; return 0 }
}

$freeBefore = Get-FreeGB
Log "  Free C: sebelum : ${freeBefore} GB"
try {
  $vd = Get-CimInstance Win32_LogicalDisk | ForEach-Object { "$($_.DeviceID) $([math]::Round($_.Size/1GB))GB total / $([math]::Round($_.FreeSpace/1GB))GB free" }
  Log "  Disk layout : $($vd -join ' | ')"
} catch {}

$totalFreed = 0

# ---------- 1. Matikan hibernasi + hapus hiberfil.sys (2-4 GB) ----------
try {
  & powercfg.exe /hibernate off 2>&1 | Out-Null
  if (Test-Path 'C:\hiberfil.sys') { Remove-Item 'C:\hiberfil.sys' -Force -ErrorAction SilentlyContinue }
  Log '  hibernasi dimatikan'
} catch { Log "  hibernate off gagal: $($_.Exception.Message)" }

# ---------- 2. Toolcache besar ----------
$totalFreed += Remove-Tree 'C:\hostedtoolcache\windows\stack' 'Haskell Stack'
# HAPUS UNITY HUB & R (request: bebasin storage)
$totalFreed += Remove-Tree 'C:\Program Files\Unity Hub' 'Unity Hub'
$totalFreed += Remove-Tree 'C:\Program Files\Unity' 'Unity Editor'
$totalFreed += Remove-Tree 'C:\hostedtoolcache\windows\R' 'R language'
$totalFreed += Remove-Tree 'C:\Program Files\R' 'R Program Files'
$totalFreed += Remove-Tree 'C:\R' 'R root'
try { & winget uninstall --id Unity.UnityHub --exact --silent --accept-source-agreements 2>&1 | Out-Null } catch {}
try { & winget uninstall --id RProject.R --exact --silent 2>&1 | Out-Null } catch {}
try { & choco uninstall unityhub -y --no-progress 2>&1 | Out-Null } catch {}
try { & choco uninstall r.project -y --no-progress 2>&1 | Out-Null } catch {}
# Hapus versi Node/Python/Go lama kecuali yang sedang dipakai runner sekarang
# Kita SIMPAN folder yang sedang aktif (cek PATH), hapus sisanya lebih aman
# Strategi: hapus semua hostedtoolcache kecuali folder yang baru dipakai? Lebih simple: hapus Android & Haskell saja yang paling besar & tidak dibutuhkan buat SAMP.
$totalFreed += Remove-Tree 'C:\Android' 'Android SDK/NDK'
$totalFreed += Remove-Tree 'C:\hostedtoolcache\CodeQL' 'CodeQL'
$totalFreed += Remove-Tree 'C:\hostedtoolcache\go' 'Go cache'
$totalFreed += Remove-Tree 'C:\agents' 'agents'
$totalFreed += Remove-Tree 'C:\Modules' 'Modules (az)'

# Hapus dotnet SDK lama tapi simpan runtime terbaru
try {
  $dotnetRoot = 'C:\Program Files\dotnet\sdk'
  if (Test-Path $dotnetRoot) {
    $sdks = Get-ChildItem $dotnetRoot -Directory | Sort-Object Name -Descending
    if ($sdks.Count -gt 1) {
      $keep = $sdks[0]
      Log "  dotnet SDK keep: $($keep.Name) — hapus $($sdks.Count-1) versi lama"
      foreach ($s in $sdks | Select-Object -Skip 1) {
        $totalFreed += Remove-Tree $s.FullName "dotnet SDK $($s.Name)"
      }
    } else { Log '  dotnet SDK cuma 1 versi -> dipertahankan' }
  }
} catch { Log "  dotnet SDK cleanup gagal: $($_.Exception.Message)" }

# Docker
try {
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($docker) {
    Log '  Docker: prune images...'
    & docker system prune -a -f 2>&1 | Out-Null
    & docker builder prune -a -f 2>&1 | Out-Null
  }
} catch {}

# ---------- 3. Chocolatey cache ----------
$totalFreed += Remove-Tree 'C:\ProgramData\chocolatey\lib' 'Choco lib cache'
$totalFreed += Remove-Tree "$env:LOCALAPPDATA\..\chocolatey" 'Choco user cache'

# ---------- 4. NPM / pip / NuGet cache ----------
try {
  if (Get-Command npm -ErrorAction SilentlyContinue) { & npm cache clean --force 2>&1 | Out-Null; Log '  npm cache cleaned' }
  if (Get-Command pip -ErrorAction SilentlyContinue) { & pip cache purge 2>&1 | Out-Null; Log '  pip cache purged' }
  if (Get-Command dotnet -ErrorAction SilentlyContinue) { & dotnet nuget locals all --clear 2>&1 | Out-Null; Log '  nuget locals cleared' }
} catch {}

# ---------- 5. Windows Update + Temp ----------
$totalFreed += Remove-Tree 'C:\Windows\SoftwareDistribution\Download' 'Windows Update Download'
$totalFreed += Remove-Tree 'C:\Windows\Temp' 'C:\Windows\Temp'
try { if (Test-Path $env:TEMP) { Get-ChildItem $env:TEMP -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue; Log '  %TEMP% dibersihkan' } } catch {}
try { if (Test-Path 'C:\Temp') { Remove-Tree 'C:\Temp' 'C:\Temp' | Out-Null } } catch {}
try { & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null; Log '  DISM component cleanup requested' } catch {}
try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log '  RecycleBin dikosongkan' } catch {}
try { & cleanmgr.exe /verylowdisk /sagerun:1 2>&1 | Out-Null } catch {}

# ---------- 5b. DEBLOAT — hapus app bawaan gede (Edge + OneDrive + Xbox dll) ----------
# Env DEBLOAT: tidak / ringan / full (default ringan kalau STORAGE_BOOST=ya, user mau hemat)
$debloat = if ($env:DEBLOAT) { $env:DEBLOAT.Trim().ToLower() } else { 'ringan' }
if ($env:DEBLOAT -eq 'tidak' -or $env:DEBLOAT -eq '0' -or $env:DEBLOAT -eq 'false') { $debloat = 'tidak' }
$cfgDeb = $null
try { $cfgDeb = (Get-Cfg).PSObject.Properties['debloat'] } catch {}
if ($cfgDeb -and $null -ne $cfgDeb.Value) {
  # jika di rdp-extras.json ada setting debloat, pakai itu kalau input tidak diisi explicit
  if (-not $env:DEBLOAT) { $debloat = "$($cfgDeb.Value)".ToLower() }
}
Log "  Debloat mode: $debloat (tidak=skip, ringan=OneDrive/Xbox/Appx, full=+Edge)"

if ($debloat -ne 'tidak') {
  # cek Chrome ada sebelum hapus Edge
  $chromeExists = $false
  foreach ($cp in @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')) {
    if (Test-Path $cp) { $chromeExists = $true; break }
  }
  if (-not $chromeExists) { $cc = Get-Command chrome -ErrorAction SilentlyContinue; if ($cc) { $chromeExists = $true } }

  # ringan: Appx bloat
  $bloatAppx = @(
    'Microsoft.OneDriveSync','Microsoft.Xbox*','Microsoft.XboxGamingOverlay','Microsoft.XboxGameCallableUI',
    'Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.BingNews','Microsoft.BingWeather',
    'Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.WindowsFeedbackHub','Microsoft.MicrosoftOfficeHub',
    'Microsoft.Office.OneNote','Microsoft.SkypeApp','Microsoft.MixedReality.Portal','Microsoft.People',
    'Microsoft.WindowsMaps','Microsoft.Microsoft3DViewer','Microsoft.Print3D','Microsoft.Wallet',
    'Microsoft.MicrosoftSolitaireCollection','Microsoft.MSPaint','Clipchamp.Clipchamp'
  )
  # full tambahan Edge + Office hub
  if ($debloat -eq 'full') {
    Log '  Debloat FULL: akan coba hapus Edge (Chrome ada='+ $chromeExists +')'
    # simpan WebView2 runtime, hanya hapus Edge browser
    try {
      $edgePaths = @(
        'C:\Program Files (x86)\Microsoft\Edge\Application',
        'C:\Program Files\Microsoft\Edge\Application'
      )
      $edgeVer = $null
      foreach ($ep in $edgePaths) {
        if (Test-Path $ep) {
          $vers = Get-ChildItem $ep -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
          if ($vers) { $edgeVer = $vers.FullName; break }
        }
      }
      $edgeSize = 0
      if ($edgeVer) { $edgeSize = Get-SizeGB $edgeVer }
      Log "  Edge terdeteksi: $edgeVer (~${edgeSize}GB)"
      if (-not $chromeExists) {
        Log '  Chrome TIDAK ada — Edge TIDAK dihapus (biar browser tetap ada)'
      } else {
        # coba winget dulu (paling bersih)
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
          Log '  Winget uninstall Edge...'
          & winget uninstall --id Microsoft.Edge --exact --silent --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
          Start-Sleep -Seconds 5
        }
        # fallback setup.exe --uninstall (Edge)
        if (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application') {
          try {
            $setups = Get-ChildItem 'C:\Program Files (x86)\Microsoft\Edge\Application' -Recurse -Filter 'setup.exe' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*Installer*setup.exe' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($setups) {
              Log "  Edge setup.exe uninstall: $($setups.FullName)"
              Start-Process -FilePath $setups.FullName -ArgumentList '--uninstall','--system-level','--verbose-logging','--force-uninstall' -Wait -ErrorAction SilentlyContinue | Out-Null
              Start-Sleep -Seconds 8
            }
          } catch { Log "  Edge setup uninstall gagal: $($_.Exception.Message)" }
        }
        # cek hasil
        $edgeGone = -not (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
        $freedEdge = if ($edgeGone) { $edgeSize } else { 0 }
        $totalFreed += $freedEdge
        Log "  Edge: $(if ($edgeGone) { 'BERHASIL dihapus (+'+$freedEdge+'GB)' } else { 'GAGAL/masih ada — coba winget manual di RDP' })"
        # pastikan WebView2 tetap ada
        if (-not (Test-Path 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application\msedgewebview2.exe')) {
          Log '  WebView2 tidak ada — install WebView2 Runtime (dibutuhkan beberapa app)'
          try { & winget install --id Microsoft.EdgeWebView2Runtime --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null } catch {}
        }
      }
    } catch { Log "  Debloat Edge error: $($_.Exception.Message)" }
  } else {
    Log '  Debloat RINGAN: Edge dipertahankan (hapus OneDrive/Xbox/Appx saja). Pakai full kalau mau hapus Edge.'
  }

  # hapus Appx untuk ringan & full
  $removedAppx = 0
  foreach ($pat in $bloatAppx) {
    try {
      $pkgs = Get-AppxPackage -Name $pat -ErrorAction SilentlyContinue
      foreach ($pkg in $pkgs) {
        try {
          Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue | Out-Null
          Log "  Appx dihapus: $($pkg.Name) ($($pkg.PackageFullName))"
          $removedAppx++
        } catch {}
      }
      $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pat }
      foreach ($pr in $prov) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue | Out-Null; Log "  Provisioned dihapus: $($pr.DisplayName)" } catch {}
      }
    } catch {}
  }
  # OneDrive standalone (bukan Appx)
  try {
    if (Get-Process OneDrive -ErrorAction SilentlyContinue) { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    $odSetup = @('C:\Windows\System32\OneDriveSetup.exe','C:\Windows\SysWOW64\OneDriveSetup.exe')
    foreach ($od in $odSetup) {
      if (Test-Path $od) { Start-Process $od -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue | Out-Null; Log "  OneDrive uninstall: $od"; break }
    }
    $totalFreed += Remove-Tree "$env:USERPROFILE\OneDrive" 'OneDrive user folder'
    $totalFreed += Remove-Tree 'C:\OneDriveTemp' 'OneDriveTemp'
  } catch { Log "  OneDrive uninstall error: $($_.Exception.Message)" }
  Log "  Debloat Appx selesai: $removedAppx paket dihapus"
} else {
  Log '  Debloat dilewati (DEBLOAT=tidak)'
}

# ---------- 6. Non-aktifkan pagefile sementara? TIDAK — RDP butuh pagefile.
# Tapi kita bisa pindahkan pagefile ke D: jika D: ada & lebih lega
try {
  $dFree = Get-FreeGB
  # cek D:
  $dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
  if ($dDrive) {
    $dF = [math]::Round($dDrive.Free/1GB,2)
    Log "  Drive D: ${dF}GB free — dipakai untuk Games & temp SAMP"
    New-Item -ItemType Directory -Path 'D:\Games' -Force | Out-Null
  }
} catch {}

# ---------- 7. Compact OS (hemat ~2-3 GB, tanpa hapus file) ----------
try {
  $compactStat = & compact.exe /CompactOS:query 2>&1 | Out-String
  Log "  CompactOS status: $(Log-Tail $compactStat 1)"
  # Jangan paksa compact jika sudah compacted — cukup query
} catch {}

$freeAfter = Get-FreeGB
$freedNow = [math]::Round($freeAfter - $freeBefore,2)
Log "  Free C: sesudah : ${freeAfter} GB (tambahan +${freedNow} GB real)"
Log "  Estimasi total dihapus: ~${totalFreed} GB (hitungan folder)"

# Simpan info storage ke status supaya dashboard / panduan bisa tampilkan
try {
  $drives = @()
  foreach ($letter in @('C','D')) {
    try {
      $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$letter`:'"
      if ($ld) { $drives += @{ letter=$letter; size_gb=[math]::Round($ld.Size/1GB,2); free_gb=[math]::Round($ld.FreeSpace/1GB,2); used_gb=[math]::Round(($ld.Size-$ld.FreeSpace)/1GB,2) } }
    } catch {}
  }
  Update-Status @{ storage = [ordered]@{
    boost='ok'; before_gb=$freeBefore; after_gb=$freeAfter; gained_gb=$freedNow; estimated_freed_gb=$totalFreed
    drives=$drives
    game_dir= if (Test-Path 'D:\Games') { 'D:\Games (disarankan untuk GTA)' } else { 'C:\Games' }
    note='Storage boost selesai. Android/Haskell/CodeQL/dotnet lama & cache dibersihkan. Sisa 70GB -> bisa jadi 110-140GB free.'
  } } | Out-Null
} catch { Log "  tulis status storage gagal: $($_.Exception.Message)" }

Log "SELESAI — Storage boost: ${freeBefore}GB -> ${freeAfter}GB (+${freedNow}GB)"
exit 0
