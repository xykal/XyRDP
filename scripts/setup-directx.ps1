# ============================================================================
#  setup-directx.ps1 - DirectX Juni 2010 (grafis 3D LENGKAP) - mandiri
# ----------------------------------------------------------------------------
#  Dipisah dari setup-samp.ps1 (game dihapus 2026-11-13) supaya dukungan 3D
#  (d3dx9/d3dcompiler/xinput/x3daudio) tetap terpasang untuk aplikasi 3D apa
#  pun. Idempoten: aman dijalankan berulang. Tidak pernah menggagalkan job.
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host ("[directx] " + $m) }

$work = Join-Path $env:TEMP 'xyrdp-directx'
$sys32 = 'C:\Windows\System32'
$wow64 = 'C:\Windows\SysWOW64'
$required = @('d3dx9_24.dll', 'd3dx9_43.dll', 'd3dcompiler_43.dll', 'xinput1_3.dll', 'x3daudio1_7.dll')

function Test-DirectXFiles {
  foreach ($dir in @($sys32, $wow64)) {
    foreach ($f in $required) {
      if (-not (Test-Path (Join-Path $dir $f))) { return $false }
    }
  }
  return $true
}

if (Test-DirectXFiles) {
  Log 'DirectX Juni 2010 sudah lengkap di System32 & SysWOW64.'
  exit 0
}

try {
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  $dxPkg = Join-Path $work 'directx_Jun2010_redist.exe'
  $dxExt = Join-Path $work 'dx_extract'
  Remove-Item $dxExt -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $dxExt -Force | Out-Null

  $dxUrl = 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe'
  if (-not (Test-Path $dxPkg) -or (Get-Item $dxPkg).Length -lt 65536) {
    Log 'Mengunduh DirectX Juni 2010 redistributable...'
    $ok = $false
    foreach ($attempt in 1..3) {
      try {
        & curl.exe -fsSL $dxUrl -o $dxPkg 2>&1 | Out-Null
        if ((Test-Path $dxPkg) -and (Get-Item $dxPkg).Length -gt 65536) { $ok = $true; break }
      } catch {}
      Start-Sleep -Seconds 3
    }
    if (-not $ok) { throw 'Gagal mengunduh paket DirectX Juni 2010.' }
  }

  Log 'Mengekstrak paket DirectX...'
  $p = Start-Process -FilePath $dxPkg -ArgumentList @('/Q', "/T:$dxExt") -Wait -PassThru -WindowStyle Hidden
  if ($p.ExitCode -ne 0) { throw "Ekstraksi gagal exit=$($p.ExitCode)" }

  $dxSetup = Join-Path $dxExt 'DXSETUP.exe'
  if (-not (Test-Path $dxSetup)) { throw 'DXSETUP.exe tidak ditemukan.' }

  Log 'Menjalankan DXSETUP /silent...'
  $p2 = Start-Process -FilePath $dxSetup -ArgumentList @('/silent') -WorkingDirectory $dxExt -Wait -PassThru -WindowStyle Hidden
  if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "DXSETUP gagal exit=$($p2.ExitCode)" }

  if (Test-DirectXFiles) {
    Log 'DirectX Juni 2010 terpasang LENGKAP (3D).'
  } else {
    Log 'Peringatan: verifikasi DLL DirectX belum lengkap.'
  }
} catch {
  Log "Gagal: $($_.Exception.Message) (job dilanjutkan)."
}
exit 0
