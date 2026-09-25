# ============================================================================
#  setup-rdp.ps1 — MODE BERSIH (standar)
#  Tidak ada tweak Windows/Chrome, tidak ada cek reputasi IP.
#  Hanya: (1) user admin + (2) aktifkan RDP + (3) Tailscale + (4) status file.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
function Log([string]$m) { Write-Host "[XyRDP] $m" }

# ---------- 0. Validasi ----------
if (-not $env:RDP_PASSWORD -or $env:RDP_PASSWORD.Length -lt 8) {
  Log "ERROR: secret RDP_PASSWORD belum di-set / terlalu pendek."; exit 1
}
if (-not $env:TAILSCALE_AUTH_KEY -or $env:TAILSCALE_AUTH_KEY -notlike 'tskey-auth-*') {
  Log "ERROR: secret TAILSCALE_AUTH_KEY kosong / format salah (harus tskey-auth-...)."; exit 1
}
$dur = [int]($env:DUR -replace '\D',''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$u = $env:RDP_USER
Log "Mode: bersih/standar | durasi $dur menit | user $u"

# ---------- 1. User admin (akses penuh, password tetap) ----------
$sp = ConvertTo-SecureString $env:RDP_PASSWORD -AsPlainText -Force
if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $u }
New-LocalUser -Name $u -Password $sp -FullName "XyRDP Admin" -PasswordNeverExpires -AccountNeverExpires | Out-Null
Add-LocalGroupMember -Group "Administrators"     -Member $u -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Desktop Users" -Member $u -ErrorAction SilentlyContinue
# token admin penuh utk login jaringan (ini bagian dari "akses admin", bukan tweak)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null
Log "User '$u' siap: Administrators + Remote Desktop Users, password tetap tidak expire"

# ---------- 2. RDP standar ----------
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
Log "RDP aktif di port 3389 (NLA default Windows, tanpa perubahan lain). Hanya reachable via tailnet."

# ---------- 3. Tailscale ----------
$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $tsExe)) {
  $msi = Join-Path $env:RUNNER_TEMP 'Tailscale.msi'
  try { Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing } catch { Log "download msi gagal: $($_.Exception.Message)" }
  $ok = (Test-Path $msi) -and ((Get-Item $msi).Length -gt 1MB)
  if ($ok) { Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait }
  if (-not (Test-Path $tsExe)) {
    Log "msi gagal, fallback installer exe..."
    $exe = Join-Path $env:RUNNER_TEMP 'tailscale-setup.exe'
    try {
      Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' -OutFile $exe -UseBasicParsing
      if ((Get-Item $exe).Length -gt 1MB) { Start-Process $exe -ArgumentList '/S' -Wait }
    } catch { Log "fallback exe gagal: $($_.Exception.Message)" }
  }
}
if (-not (Test-Path $tsExe)) { Log "ERROR: instalasi Tailscale gagal."; exit 1 }
Log "Tailscale $(& $tsExe version)"

$hostBase = ($env:TS_HOSTNAME -replace '[^a-zA-Z0-9-]','').ToLower().Trim('-')
if (-not $hostBase) { $hostBase = 'xyrdp' }
if ($hostBase.Length -gt 30) { $hostBase = $hostBase.Substring(0,30) }
$hostName = "$hostBase-$env:GITHUB_RUN_NUMBER"

$upArgs = @('up', "--authkey=$($env:TAILSCALE_AUTH_KEY)", "--hostname=$hostName")
if ($env:EXIT_NODE) { $upArgs += @("--exit-node=$($env:EXIT_NODE)", '--exit-node-allow-lan-access') }
Log "tailscale up sebagai '$hostName'$(if ($env:EXIT_NODE) { " (exit node: $env:EXIT_NODE)" })"
& $tsExe @upArgs
if ($LASTEXITCODE -ne 0 -and $env:EXIT_NODE) {
  Log "EXIT_NODE gagal, retry tanpa exit node..."
  & $tsExe @($upArgs | Where-Object { $_ -notlike '--exit-node*' })
}

$ip4 = ''
for ($i = 0; $i -lt 30; $i++) {
  $ip4 = (& $tsExe ip -4 2>$null | Select-Object -First 1)
  if ($ip4) { break }
  Start-Sleep -Seconds 2
}
if (-not $ip4) { Log "ERROR: tidak dapat IP Tailscale (authkey salah / tailnet menolak)."; exit 1 }
$dns = ''
try { $dns = ((& $tsExe status --json | ConvertFrom-Json).Self.DNSName) } catch {}
Log "TAILNET IP : $ip4"
Log "MAGICDNS   : $dns"

# ---------- 4. Status (tanpa password) ----------
$now = Get-Date
$status = [ordered]@{
  active         = $true
  tailscale_ip   = $ip4
  tailscale_dns  = $dns
  ts_hostname    = $hostName
  rdp_port       = 3389
  rdp_user       = $u
  started_at     = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  expires_at     = $now.AddMinutes($dur).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  duration_menit = $dur
  run_id         = $env:GITHUB_RUN_ID
  run_number     = $env:GITHUB_RUN_NUMBER
  run_url        = "https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
  mode           = 'bersih'
}
$outDir = Join-Path $env:GITHUB_WORKSPACE 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$status | ConvertTo-Json | Set-Content -Encoding utf8 -Path (Join-Path $outDir 'rdp-status.json')
$now.ToString('s') | Set-Content -Path (Join-Path $outDir 'started.txt')
$status | ConvertTo-Json | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SESI SIAP (bersih). Remote Desktop ke: $ip4 :3389, user $u, login Tailscale dulu di perangkatmu."
