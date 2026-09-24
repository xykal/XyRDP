# ============================================================================
#  finalize-rdp.ps1 — dijalankan setelah sesi berakhir:
#  1) baca device ID dari tailscale status (SEBELUM logout)
#  2) tailscale logout (node ephemeral -> otomatis terhapus dari tailnet)
#  3) opsional: hapus device via Tailscale API kalau secret TAILSCALE_API_TOKEN diset
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:fin] $m" }

$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$self = $null
if (Test-Path $tsExe) {
  try { $self = (& $tsExe status --json 2>$null | ConvertFrom-Json).Self } catch {}

  Log "tailscale logout..."
  & $tsExe logout 2>&1 | Out-Null
} else { Log "tailscale tidak ada — skip" }

if ($env:TAILSCALE_API_TOKEN -and $self -and $self.ID) {
  try {
    $hdr = @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($env:TAILSCALE_API_TOKEN):")))" }
    $tid = (Invoke-RestMethod 'https://api.tailscale.com/api/v2/tailnet/-/user' -Headers $hdr).tailnet
    $devs = Invoke-RestMethod "https://api.tailscale.com/api/v2/tailnet/$tid/devices" -Headers $hdr
    $mine = @($devs.devices | Where-Object { $_.id -eq $self.ID })
    foreach ($d in $mine) {
      Invoke-RestMethod -Method Delete -Uri "https://api.tailscale.com/api/v2/tailnet/$tid/devices/$($d.id)" -Headers $hdr | Out-Null
      Log "device $($d.name) dihapus dari tailnet"
    }
  } catch { Log "hapus device gagal (tidak kritis): $($_.Exception.Message)" }
} else {
  Log "TAILSCALE_API_TOKEN tidak diset / device id tak diketahui — node dibiarkan offline di admin console (tidak berbahaya, key ephemeral = autohapus)."
}

Log "selesai. VM akan dihancurkan GitHub setelah job ini berakhir."
