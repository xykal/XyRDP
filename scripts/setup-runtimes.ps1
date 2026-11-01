# ============================================================================
#  setup-runtimes.ps1 - Runtime wajib aplikasi & game (VC++ / DirectX / .NET)
# ----------------------------------------------------------------------------
#  Mengatasi aplikasi/game "tidak bisa dibuka saat pertama kali" karena
#  VCRUNTIME140.dll, MSVCP*.dll, msvcr*.dll, d3dx9_43, xinput1_3, atau .NET 3.5
#  tidak tersedia. Semua langkah BEST-EFFORT; satu gagal tidak mematikan sesi.
#  Dijalankan untuk semua sesi Windows (tanpa input toggle) karena hampir semua
#  aplikasi butuh minimal VC++ 2015-2022.
# ============================================================================

$XyTag = 'XyRDP:runtimes'
. "$PSScriptRoot/lib-common.ps1"

$res = [ordered]@{}

function Install-Package([string]$Key, [string]$Label, [string]$Url, [string]$ArgList, [string]$VerifyPath) {
  if ($VerifyPath -and (Test-Path $VerifyPath)) { Log "  $Label sudah terpasang"; $script:res[$Key] = 'sudah ada'; return }
  try {
    $exe = Join-Path $env:TEMP ("xyrt_" + [IO.Path]::GetFileName(($Url -split '\?')[0]))
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
    & curl.exe -fL --retry 1 --connect-timeout 15 --max-time 180 -sS $Url -o $exe
    if (-not (Test-Path $exe) -or (Get-Item $exe).Length -lt 65536) {
      Log "  $Label unduhan gagal ($Url)"
      $script:res[$Key] = 'gagal unduh'
      return
    }
    $p = Start-Process -FilePath $exe -ArgumentList $ArgList -Wait -PassThru -WindowStyle Hidden
    Log "  $Label exit=$($p.ExitCode)"
    if ($VerifyPath -and -not (Test-Path $VerifyPath)) { $script:res[$Key] = 'gagal' } else { $script:res[$Key] = 'ok' }
  } catch {
    Log "  $Label gagal: $($_.Exception.Message)"
    $script:res[$Key] = 'gagal'
  }
}

function Install-WingetId([string]$Key, [string]$Label, [string]$Id, [string]$VerifyPath) {
  if ($VerifyPath -and (Test-Path $VerifyPath)) { Log "  $Label sudah terpasang"; $script:res[$Key] = 'sudah ada'; return }
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) { $script:res[$Key] = 'gagal (winget absen)'; Log "  $Label dilewati: winget tidak tersedia"; return }
  try {
    & $winget.Source install --id $Id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    if ($VerifyPath -and -not (Test-Path $VerifyPath)) { $script:res[$Key] = 'gagal' } else { $script:res[$Key] = 'ok' }
    Log "  $Label (winget $Id) -> $($script:res[$Key])"
  } catch {
    $script:res[$Key] = 'gagal'
    Log "  $Label (winget $Id) gagal: $($_.Exception.Message)"
  }
}

Log 'Memasang runtime aplikasi & game (best-effort)...'

# --- VC++ 2015-2022 (paling sering dibutuhkan aplikasi modern) ---
Install-Package 'vc2022x64' 'VC++ 2015-2022 x64' 'https://aka.ms/vs/17/release/vc_redist.x64.exe' '/install /quiet /norestart' 'C:\Windows\System32\vcruntime140.dll'
Install-Package 'vc2022x86' 'VC++ 2015-2022 x86' 'https://aka.ms/vs/17/release/vc_redist.x86.exe' '/install /quiet /norestart' 'C:\Windows\SysWOW64\vcruntime140.dll'

# --- VC++ 2013 / 2012 / 2010 (aplikasi & game lawas) ---
Install-Package 'vc2013x64' 'VC++ 2013 x64' 'https://aka.ms/vs/12/release/vc_redist.x64.exe' '/install /quiet /norestart' 'C:\Windows\System32\msvcr120.dll'
Install-Package 'vc2013x86' 'VC++ 2013 x86' 'https://aka.ms/vs/12/release/vc_redist.x86.exe' '/install /quiet /norestart' 'C:\Windows\SysWOW64\msvcr120.dll'
Install-Package 'vc2012x64' 'VC++ 2012 x64' 'https://aka.ms/vs/11/release/vc_redist.x64.exe' '/install /quiet /norestart' 'C:\Windows\System32\msvcr110.dll'
Install-Package 'vc2012x86' 'VC++ 2012 x86' 'https://aka.ms/vs/11/release/vc_redist.x86.exe' '/install /quiet /norestart' 'C:\Windows\SysWOW64\msvcr110.dll'
Install-Package 'vc2010x64' 'VC++ 2010 x64' 'https://aka.ms/vs/10/release/vc_redist.x64.exe' '/install /quiet /norestart' 'C:\Windows\System32\msvcr100.dll'
Install-Package 'vc2010x86' 'VC++ 2010 x86' 'https://aka.ms/vs/10/release/vc_redist.x86.exe' '/install /quiet /norestart' 'C:\Windows\SysWOW64\msvcr100.dll'

# --- Fallback winget bila unduhan langsung gagal ---
foreach ($fb in @(
    @('vc2013x64', 'Microsoft.VCRedist.2013.x64', 'C:\Windows\System32\msvcr120.dll'),
    @('vc2013x86', 'Microsoft.VCRedist.2013.x86', 'C:\Windows\SysWOW64\msvcr120.dll'),
    @('vc2012x64', 'Microsoft.VCRedist.2012.x64', 'C:\Windows\System32\msvcr110.dll'),
    @('vc2012x86', 'Microsoft.VCRedist.2012.x86', 'C:\Windows\SysWOW64\msvcr110.dll'),
    @('vc2010x64', 'Microsoft.VCRedist.2010.x64', 'C:\Windows\System32\msvcr100.dll'),
    @('vc2010x86', 'Microsoft.VCRedist.2010.x86', 'C:\Windows\SysWOW64\msvcr100.dll')
  )) {
  if ($res[$fb[0]] -notin @('ok', 'sudah ada')) {
    Install-WingetId $fb[0] "VC++ fallback $($fb[0])" $fb[1] $fb[2]
  }
}

# --- VC++ 2008 / 2005 (game era GTA SA); aka.ms tidak punya vs/9 -> winget ---
Install-WingetId 'vc2008x64' 'VC++ 2008 x64' 'Microsoft.VCRedist.2008.x64' 'C:\Windows\System32\msvcr90.dll'
Install-WingetId 'vc2008x86' 'VC++ 2008 x86' 'Microsoft.VCRedist.2008.x86' 'C:\Windows\SysWOW64\msvcr90.dll'
Install-WingetId 'vc2005x64' 'VC++ 2005 x64' 'Microsoft.VCRedist.2005.x64' $null
Install-WingetId 'vc2005x86' 'VC++ 2005 x86' 'Microsoft.VCRedist.2005.x86' $null

# --- DirectX June 2010 (d3dx9_43, xinput1_3, dsound) via suite SA-MP ---
try {
  & "$PSScriptRoot\setup-samp.ps1" -DirectXOnly
  if (Test-Path 'C:\Windows\System32\d3dx9_43.dll') { $res['directx9'] = 'ok' } else { $res['directx9'] = 'gagal' }
} catch {
  $res['directx9'] = 'gagal'
  Log "  DirectX gagal: $($_.Exception.Message)"
}

# --- .NET 3.5 (banyak installer lawas menolak jalan tanpa ini) ---
try {
  if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') {
    $res['net35'] = 'sudah ada'
  } else {
    & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /Quiet /NoRestart 2>&1 | Out-Null
    if (Test-Path 'C:\Windows\Microsoft.NET\Framework\v3.5') { $res['net35'] = 'ok' } else { $res['net35'] = 'gagal' }
    Log "  .NET 3.5 -> $($res['net35'])"
  }
} catch { $res['net35'] = 'gagal' }

Update-Status @{ runtimes = $res } | Out-Null
Log "SELESAI runtimes: $(($res.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
exit 0
