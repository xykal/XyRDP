# ============================================================================
#  setup-runtimes.ps1 - Runtime aplikasi & game (VC++ / DirectX / .NET)
# ----------------------------------------------------------------------------
#  1.1.29 (cepat): unduhan diparalelkan (curl --parallel), installer di-cache di
#  %USERPROFILE%\xyrt-cache (di-persist lewat actions/cache oleh workflow), dan
#  runtime dibagi dua tingkat:
#    - Mode cepat : VC++ 2010-2022 x64+x86 (cukup untuk hampir semua aplikasi).
#    - Mode penuh : + VC++ 2008/2005 (winget), DirectX June 2010, .NET 3.5 —
#      untuk sesi game/legacy (SA-MP, Roblox, Minecraft, emulator).
#    - Mode auto  : workflow yang memutuskan (penuh bila ada toggle game).
#  Semua langkah BEST-EFFORT; satu gagal tidak mematikan sesi.
# ============================================================================

param([string]$Mode = 'penuh')

$XyTag = 'XyRDP:runtimes'
. "$PSScriptRoot/lib-common.ps1"

if ($env:XYRT_MODE) { $Mode = $env:XYRT_MODE }
if ($Mode -notin @('cepat', 'penuh', 'auto')) { $Mode = 'penuh' }
if ($Mode -eq 'auto') { $Mode = 'penuh' }   # fallback manual: aman = penuh

$cacheDir = if ($env:XYRT_CACHE) { $env:XYRT_CACHE } else { Join-Path $env:USERPROFILE 'xyrt-cache' }
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$res = [ordered]@{}
$res['mode'] = $Mode

# Daftar paket unduh-langsung (semua = tingkat "cepat").
# VerifyPath kosong = tidak diverifikasi berkas (instal tetap dicek exit code).
$pkgs = @(
  @{ k = 'vc2022x64'; label = 'VC++ 2015-2022 x64'; url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\System32\vcruntime140.dll' },
  @{ k = 'vc2022x86'; label = 'VC++ 2015-2022 x86'; url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\SysWOW64\vcruntime140.dll' },
  @{ k = 'vc2013x64'; label = 'VC++ 2013 x64'; url = 'https://aka.ms/vs/12/release/vc_redist.x64.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\System32\msvcr120.dll' },
  @{ k = 'vc2013x86'; label = 'VC++ 2013 x86'; url = 'https://aka.ms/vs/12/release/vc_redist.x86.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\SysWOW64\msvcr120.dll' },
  @{ k = 'vc2012x64'; label = 'VC++ 2012 x64'; url = 'https://aka.ms/vs/11/release/vc_redist.x64.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\System32\msvcr110.dll' },
  @{ k = 'vc2012x86'; label = 'VC++ 2012 x86'; url = 'https://aka.ms/vs/11/release/vc_redist.x86.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\SysWOW64\msvcr110.dll' },
  @{ k = 'vc2010x64'; label = 'VC++ 2010 x64'; url = 'https://aka.ms/vs/10/release/vc_redist.x64.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\System32\msvcr100.dll' },
  @{ k = 'vc2010x86'; label = 'VC++ 2010 x86'; url = 'https://aka.ms/vs/10/release/vc_redist.x86.exe'; args = '/install /quiet /norestart'; verify = 'C:\Windows\SysWOW64\msvcr100.dll' }
)

function Get-CacheFile([hashtable]$p) {
  Join-Path $cacheDir ((($p.url -split '\?')[0] -split '/')[-1])
}

# ---- Tahap 1: unduh PARALEL hanya yang belum ada di cache/terpasang --------
$need = @()
foreach ($p in $pkgs) {
  if ($p.verify -and (Test-Path $p.verify)) { $res[$p.k] = 'sudah ada'; continue }
  $exe = Get-CacheFile $p
  if ((Test-Path $exe) -and (Get-Item $exe).Length -gt 65536) { $res[$p.k] = 'cache'; continue }
  $need += $p
}
if ($need.Count -gt 0) {
  Log ("Mengunduh {0} installer runtime (paralel, cache: {1})..." -f $need.Count, $cacheDir)
  $curlArgs = @('-fL', '--retry', '2', '--connect-timeout', '15', '--max-time', '300', '-sS', '--parallel', '--parallel-max', '6')
  foreach ($p in $need) { $curlArgs += @('-o', (Get-CacheFile $p), $p.url) }
  & curl.exe @curlArgs
  foreach ($p in $need) {
    $exe = Get-CacheFile $p
    if (-not (Test-Path $exe) -or (Get-Item $exe).Length -lt 65536) {
      Remove-Item $exe -Force -ErrorAction SilentlyContinue
      $res[$p.k] = 'gagal unduh'
    }
  }
}

# ---- Tahap 2: instal berurutan (quiet; unduhan sudah selesai) -------------
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

# ---- Fallback winget bila unduhan langsung gagal (hanya yang gagal) --------
function Install-WingetId([string]$Key, [string]$Label, [string]$Id, [string]$VerifyPath) {
  if ($VerifyPath -and (Test-Path $VerifyPath)) { $res[$Key] = 'sudah ada'; return }
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) { $res[$Key] = 'gagal (winget absen)'; Log "  $Label dilewati: winget tidak tersedia"; return }
  try {
    & $winget.Source install --id $Id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    if ($VerifyPath -and -not (Test-Path $VerifyPath)) { $res[$Key] = 'gagal' } else { $res[$Key] = 'ok' }
    Log "  $Label (winget $Id) -> $($res[$Key])"
  } catch {
    $res[$Key] = 'gagal'
    Log "  $Label (winget $Id) gagal: $($_.Exception.Message)"
  }
}

foreach ($fb in @(
    @('vc2013x64', 'Microsoft.VCRedist.2013.x64', 'C:\Windows\System32\msvcr120.dll'),
    @('vc2013x86', 'Microsoft.VCRedist.2013.x86', 'C:\Windows\SysWOW64\msvcr120.dll'),
    @('vc2012x64', 'Microsoft.VCRedist.2012.x64', 'C:\Windows\System32\msvcr110.dll'),
    @('vc2012x86', 'Microsoft.VCRedist.2012.x86', 'C:\Windows\SysWOW64\msvcr110.dll'),
    @('vc2010x64', 'Microsoft.VCRedist.2010.x64', 'C:\Windows\System32\msvcr100.dll'),
    @('vc2010x86', 'Microsoft.VCRedist.2010.x86', 'C:\Windows\SysWOW64\msvcr100.dll')
  )) {
  if ($res[$fb[0]] -notin @('ok', 'sudah ada', 'cache')) {
    Install-WingetId $fb[0] "VC++ fallback $($fb[0])" $fb[1] $fb[2]
  }
}
# catatan: status 'cache' sudah berubah jadi 'ok'/'gagal' pada tahap instal.

# ---- Tingkat PENUH: legacy untuk game ------------------------------------
if ($Mode -eq 'penuh') {
  Install-WingetId 'vc2008x64' 'VC++ 2008 x64' 'Microsoft.VCRedist.2008.x64' 'C:\Windows\System32\msvcr90.dll'
  Install-WingetId 'vc2008x86' 'VC++ 2008 x86' 'Microsoft.VCRedist.2008.x86' 'C:\Windows\SysWOW64\msvcr90.dll'
  Install-WingetId 'vc2005x64' 'VC++ 2005 x64' 'Microsoft.VCRedist.2005.x64' $null
  Install-WingetId 'vc2005x86' 'VC++ 2005 x86' 'Microsoft.VCRedist.2005.x86' $null

  try {
    & "$PSScriptRoot\setup-samp.ps1" -DirectXOnly
    if (Test-Path 'C:\Windows\System32\d3dx9_43.dll') { $res['directx9'] = 'ok' } else { $res['directx9'] = 'gagal' }
  } catch {
    $res['directx9'] = 'gagal'
    Log "  DirectX gagal: $($_.Exception.Message)"
  }

  try {
    if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') {
      $res['net35'] = 'sudah ada'
    } else {
      & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /Quiet /NoRestart 2>&1 | Out-Null
      if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') { $res['net35'] = 'ok' } else { $res['net35'] = 'gagal' }
      Log "  .NET 3.5 -> $($res['net35'])"
    }
  } catch { $res['net35'] = 'gagal' }
} else {
  $res['directx9'] = 'dilewati (mode cepat)'
  $res['net35'] = 'dilewati (mode cepat)'
  $res['vc2008x64'] = 'dilewati (mode cepat)'
  $res['vc2005x64'] = 'dilewati (mode cepat)'
  Log 'Mode cepat: VC++ 2005-2008, DirectX, dan .NET 3.5 dilewati (pilih runtimes=penuh bila butuh game lawas).'
}

Update-Status @{ runtimes = $res } | Out-Null
Log "SELESAI runtimes: $(($res.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
exit 0
