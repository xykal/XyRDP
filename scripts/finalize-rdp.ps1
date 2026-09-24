# ============================================================================
#  finalize-rdp.ps1 — dibakar setelah sesi berakhir: putuskan Tailscale supaya
#  node "logout" (kalau tailnet-mu pakai ephemeral key, node otomatis terhapus).
#  Opsional: hapus device dari tailnet kalau secret TAILSCALE_API_TOKEN diset.
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:fin] $m" }

$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
  Log "tailscale logout..."
  & $tsExe logout 2>&1 | Out-Null
} else { Log "tailscale tidak ada — skip" }

if ($env:TAILSCALE_API_TOKEN) {
  try {
    Log "hapus device dari tailnet via API..."
    $self = (& $tsExe status --json 2>$null | ConvertFrom-Json).Self
    if ($self -and $self.ID) {
      $tid = (Invoke-RestMethod -Uri 'https://api.tailscale.com/api/v2/tailnet/-/user' -Headers @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:TAILSCALE_API_TOKEN + ':')))" }).tailnet
      $pair = "$($env:TAILSCALE_API_TOKEN):"
      $hdr  = @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair)))" }
      $devs = Invoke-RestMethod "https://api.tailscale.com/api/v2/tailnet/$tid/devices" -Headers $hdr
      $mine = $devs.devices | Where-Object { $_.id -eq $self.ID }
      foreach ($d in $mine) {
        Invoke-RestMethod -Method Delete "https://api.tailscale.com/api/v2/tailnet/$tid/devices/$($d.id)" -Headers $hdr | Out-Null
        Log "device $($d.name) dihapus dari tailnet"
      }
    }
  } catch { Log "hapus device gagal (tidak kritis): $($_.Exception.Message)" }
} else {
  Log "TAILSCALE_API_TOKEN tidak diset — device dibiarkan offline di admin console (bisa dihapus manual, tidak berbahaya)."
}

Log "selesai. VM akan dihancurkan GitHub setelah job ini berakhir."
