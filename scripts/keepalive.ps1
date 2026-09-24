# ============================================================================
#  keepalive.ps1 — menahan job (dan VM-nya) tetap hidup selama DUR menit,
#  minus buffer 6 menit supaya cleanup selesai sebelum limit keras 360 menit.
#  Tiap 5 menit nulis heartbeat: tailnet IP, sisa waktu, jumlah sesi RDP aktif.
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:alive] $m" }

$dur = [int]($env:DUR -replace '\D',''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$buffer = if ($dur -ge 15) { 6 } else { 2 }
$stop = (Get-Date).AddMinutes($dur - $buffer)
Log "menahan sesi sampai $($stop.ToString('HH:mm:ss')) UTC ($dur menit total, buffer cleanup $buffer menit)"

$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
while ((Get-Date) -lt $stop) {
  $left = ($stop - (Get-Date)).ToString('hh\:mm')
  $ip = '?'
  if (Test-Path $tsExe) { $ipx = (& $tsExe ip -4 2>$null | Select-Object -First 1); if ($ipx) { $ip = $ipx } }
  $sess = 0
  try { $sess = @(Get-UserConnection -ErrorAction SilentlyContinue).Count } catch {}
  Log "hidup • tailnet=$ip • sesi RDP aktif=$sess • sisa=$left"
  Start-Sleep -Seconds 300
}
Log "durasi inti habis — lanjut ke cleanup. Sesi akan mati bersama job."
