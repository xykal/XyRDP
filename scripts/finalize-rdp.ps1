# RdpFree: disconnect only its Tailscale session, never kill unrelated SSH processes.
$XyTag='RdpFree:finalize'
. "$PSScriptRoot/lib-common.ps1"
$exe="$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $exe) {
  try { & $exe down 2>$null | Out-Null; & $exe logout 2>$null | Out-Null } catch { Log 'Tailscale perlu diperiksa pemilik tailnet' }
}
Log 'Sesi dihentikan. Mesin self-hosted tidak dihapus otomatis.'
Log 'Tunnel Tailscale ditutup; konfigurasi privat lokal dibersihkan.'
