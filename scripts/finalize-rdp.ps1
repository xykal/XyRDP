# ============================================================================
#  finalize-rdp.ps1 — dijalankan setelah sesi berakhir (selalu, apa pun hasil):
#    1) matikan jalur akses: proses tunnel (pinggy/bore/ngrok/ssh)
#    2) Tailscale: down + logout supaya node tidak menumpuk
# ============================================================================

$XyTag = 'XyRDP:fin'
. "$PSScriptRoot/lib-common.ps1"

# ---------- 1. Tunnel ----------
$killed = 0
foreach ($name in @('bore', 'ngrok', 'ssh')) {
  $ps = Get-Process -Name $name -ErrorAction SilentlyContinue
  if ($ps) { $ps | Stop-Process -Force -ErrorAction SilentlyContinue; $killed += @($ps).Count; Log "proses $name dihentikan ($(@($ps).Count))" }
}
if ($killed -eq 0) { Log 'tidak ada proses tunnel yang berjalan' }

# ---------- 2. Tailscale: turunkan + logout ----------
foreach ($p in @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
  if (Test-Path $p) {
    try { & $p down 2>&1 | Out-Null; Log 'tailscale: down (node dinonaktifkan)' } catch {}
    try { & $p logout 2>&1 | Out-Null; Log 'tailscale: logout (node dilepas dari tailnet)' } catch {}
    break
  }
}

Log 'selesai. VM akan dihancurkan GitHub setelah job ini berakhir.'
exit 0
