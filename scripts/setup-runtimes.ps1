# ============================================================================
#  setup-runtimes.ps1 - Runtime VC++ & DirectX
# ----------------------------------------------------------------------------
#  2026-11-13 (permintaan pemilik): runtime dibuat CEPAT + grafis 3D lengkap.
#    - Mode 'cepat' (DEFAULT): VC++ 2015-2022 (x64+x86) + DirectX Juni 2010
#      (3D lengkap via setup-directx.ps1). Tanpa VC++ lawas / .NET 3.5.
#    - Mode 'penuh' (opsi manual): + VC++ 2010-2013 + .NET 3.5 + VC++ 2005/2008
#      untuk aplikasi lawas.
#  Cache: ~/xyrt-cache (dipakai ulang lintas run bila ada). Tidak fail job.
# ============================================================================
param(
  [ValidateSet('auto', 'cepat', 'penuh')]
  [string]$Mode = $(if ($env:XYRT_MODE) { $env:XYRT_MODE } else { 'auto' })
)
$ErrorActionPreference = 'Continue'

# Sumber util: Log + Update-Status (lib-common) bila ada.
$lib = Join-Path $PSScriptRoot 'lib-common.ps1'
if (Test-Path $lib) {
  try { . $lib } catch {}
}
if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
  function Log([string]$m) { Write-Host ("[runtimes] " + $m) }
}
if (-not (Get-Command Update-Status -ErrorAction SilentlyContinue)) {
  function Update-Status([hashtable]$h) { return $null }
}

if ($Mode -eq 'auto') { $Mode = 'cepat' }
Log "Mode runtime: $Mode (auto -> cepat; game dihapus 2026-11)"

$cacheDir = Join-Path $env:USERPROFILE 'xyrt-cache'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

$res = @{}

function Get-CacheFile([hashtable]$p) {
  return Join-Path $cacheDir $p.file
}

# ---- Paket unduh langsung (cepat): VC++ 2015-2022 x64+x86 -----------------
$pkgs = @(
  @{ k = 'vc2022x64'; label = 'Microsoft Visual C++ 2015-2022 Redistributable x64';
     url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; file = 'vc2022x64.exe';
     args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\System32\msvcp140.dll' },
  @{ k = 'vc2022x86'; label = 'Microsoft Visual C++ 2015-2022 Redistributable x86';
     url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'; file = 'vc2022x86.exe';
     args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\SysWOW64\msvcp140.dll' }
)

# ---- Mode penuh: tambah VC++ 2010-2013 (legacy apps) ----------------------
if ($Mode -eq 'penuh') {
  $pkgs += @(
    @{ k = 'vc2013x64'; label = 'VC++ 2013 x64';
       url = 'https://aka.ms/highdpimfc_redist_x64_en'; file = 'vc2013x64.exe';
       args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\System32\msvcr120.dll' },
    @{ k = 'vc2013x86'; label = 'VC++ 2013 x86';
       url = 'https://aka.ms/highdpimfc_redist_x86_en'; file = 'vc2013x86.exe';
       args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\SysWOW64\msvcr120.dll' },
    @{ k = 'vc2012x64'; label = 'VC++ 2012 x64';
       url = 'https://aka.ms/highdpimfc_redist_x64_en'; file = 'vc2012x64.exe';
       args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\System32\msvcr110.dll' },
    @{ k = 'vc2012x86'; label = 'VC++ 2012 x86';
       url = 'https://aka.ms/highdpimfc_redist_x86_en'; file = 'vc2012x86.exe';
       args = @('/install', '/passive', '/norestart'); verify = 'C:\Windows\SysWOW64\msvcr110.dll' },
    @{ k = 'vc2010x64'; label = 'VC++ 2010 x64';
       url = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-215CEBAD8AB7/vcredist_x64.exe'; file = 'vc2010x64.exe';
       args = @('/q', '/norestart'); verify = 'C:\Windows\System32\msvcr100.dll' },
    @{ k = 'vc2010x86'; label = 'VC++ 2010 x86';
       url = 'https://download.microsoft.com/download/C/6/D/C6D0FD4E-9E53-4897-9B91-836EBA2AACD3/vcredist_x86.exe'; file = 'vc2010x86.exe';
       args = @('/q', '/norestart'); verify = 'C:\Windows\SysWOW64\msvcr100.dll' }
  )
}

# ---- Tahap 1: unduh paralel ke cache --------------------------------------
foreach ($p in $pkgs) {
  $exe = Get-CacheFile $p
  if ($p.verify -and (Test-Path $p.verify)) {
    $res[$p.k] = 'sudah ada'
    continue
  }
  if ((Test-Path $exe) -and (Get-Item $exe).Length -gt 65536) {
    $res[$p.k] = 'cache'
    continue
  }
  Log "  Mengunduh $($p.label)..."
  try {
    & curl.exe -fsSL $p.url -o $exe 2>&1 | Out-Null
    if ((Test-Path $exe) -and (Get-Item $exe).Length -gt 65536) {
      $res[$p.k] = 'cache'
    } else {
      $res[$p.k] = 'gagal unduh'
    }
  } catch {
    $res[$p.k] = 'gagal unduh'
  }
}

# ---- Tahap 2: instal berurutan --------------------------------------------
foreach ($p in $pkgs) {
  if ($res[$p.k] -in @('sudah ada')) { Log "  $($p.label) sudah terpasang"; continue }
  if ($res[$p.k] -eq 'gagal unduh') { Log "  $($p.label) unduhan gagal"; continue }
  try {
    $exe = Get-CacheFile $p
    $pr = Start-Process -FilePath $exe -ArgumentList $p.args -Wait -PassThru -WindowStyle Hidden
    Log "  $($p.label) exit=$($pr.ExitCode)"
    if ($p.verify -and -not (Test-Path $p.verify)) { $res[$p.k] = 'gagal' } else { $res[$p.k] = 'ok' }
  } catch {
    Log "  $($p.label) gagal: $($_.Exception.Message)"
    $res[$p.k] = 'gagal'
  }
}

# ---- DirectX Juni 2010 (grafis 3D lengkap) - mode cepat & penuh -----------
try {
  & (Join-Path $PSScriptRoot 'setup-directx.ps1')
  if (Test-Path 'C:\Windows\System32\d3dx9_43.dll') { $res['directx9'] = 'ok' } else { $res['directx9'] = 'gagal' }
} catch {
  $res['directx9'] = 'gagal'
  Log "  DirectX gagal: $($_.Exception.Message)"
}

# ---- Mode penuh: .NET 3.5 + VC++ 2005/2008 (legacy) ----------------------
if ($Mode -eq 'penuh') {
  try {
    if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') {
      $res['net35'] = 'sudah ada'
    } else {
      & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /Quiet /NoRestart 2>&1 | Out-Null
      if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') { $res['net35'] = 'ok' } else { $res['net35'] = 'gagal' }
      Log "  .NET 3.5 -> $($res['net35'])"
    }
  } catch { $res['net35'] = 'gagal' }

  function Install-WingetId([string]$Key, [string]$Label, [string]$Id, [string]$VerifyPath) {
    if ($VerifyPath -and (Test-Path $VerifyPath)) { $res[$Key] = 'sudah ada'; return }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { $res[$Key] = 'gagal (winget absen)'; Log "  $Label dilewati"; return }
    try {
      & $winget.Source install --id $Id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
      if ($VerifyPath -and -not (Test-Path $VerifyPath)) { $res[$Key] = 'gagal' } else { $res[$Key] = 'ok' }
      Log "  $Label -> $($res[$Key])"
    } catch {
      $res[$Key] = 'gagal'
      Log "  $Label gagal: $($_.Exception.Message)"
    }
  }
  Install-WingetId 'vc2008x64' 'VC++ 2008 x64' 'Microsoft.VCRedist.2008.x64' 'C:\Windows\System32\msvcr90.dll'
  Install-WingetId 'vc2008x86' 'VC++ 2008 x86' 'Microsoft.VCRedist.2008.x86' 'C:\Windows\SysWOW64\msvcr90.dll'
  Install-WingetId 'vc2005x64' 'VC++ 2005 x64' 'Microsoft.VCRedist.2005.x64' $null
  Install-WingetId 'vc2005x86' 'VC++ 2005 x86' 'Microsoft.VCRedist.2005.x86' $null
} else {
  $res['net35'] = 'dilewati (mode cepat)'
  $res['vc2008x64'] = 'dilewati (mode cepat)'
  $res['vc2005x64'] = 'dilewati (mode cepat)'
  Log 'Mode cepat: VC++ lawas 2005-2013 & .NET 3.5 dilewati (pilih runtimes=penuh bila butuh).'
}

Update-Status @{ runtimes = $res } | Out-Null
Log "SELESAI runtimes: $(($res.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
exit 0
