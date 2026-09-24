# ============================================================================
#  setup-rdp.ps1 — XyRDP
#  Jalan di windows-latest GitHub Actions runner (Runner Image = Windows
#  Server 2022, user runneradmin sudah admin, jadi semua perintah HKLM aman).
#
#  Tugas:
#   1. Buat user RDP lokal = super admin penuh (password tetap dari secret)
#   2. Buka RDP (port 3389) + set policy biar login nyaman tanpa klik2an
#   3. "Unlock" tweak (UAC off, long path, SmartScreen off, lock screen off, dll)
#   4. Install + join Tailscale, opsional exit node
#   5. Cek reputasi IP publik (deteksi flag datacenter/proxy) -> dicatat ke log
#   6. Tulis out/rdp-status.json (TANPA password) untuk web dashboard
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Log([string]$m) { Write-Host "[XyRDP] $m" }
function Section([string]$m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }

# ---------- 0. Validasi input ----------
Section "0. Cek persiapan"
if (-not $env:RDP_PASSWORD -or $env:RDP_PASSWORD.Length -lt 8) {
  Log "ERROR: secret RDP_PASSWORD belum di-set / terlalu pendek."; exit 1
}
if (-not $env:TAILSCALE_AUTH_KEY -or $env:TAILSCALE_AUTH_KEY -notlike 'tskey-auth-*') {
  Log "ERROR: secret TAILSCALE_AUTH_KEY kosong / format salah (harus tskey-auth-...)."; exit 1
}
$dur = [int]($env:DUR -replace '\D',''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$safeGoogle   = "$($env:SAFE_GOOGLE)"   -eq 'true'
$killDefender = "$($env:KILL_DEFENDER)" -eq 'true'
Log "Durasi sesi : $dur menit"
Log "User RDP    : $env:RDP_USER"
Log "Safe-Google : $safeGoogle | Defender off: $killDefender"

# ---------- 1. User admin super penuh ----------
Section "1. Buat user RDP (super admin, password tetap)"
$u = $env:RDP_USER
$sp = ConvertTo-SecureString $env:RDP_PASSWORD -AsPlainText -Force

if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $u }
New-LocalUser -Name $u -Password $sp -FullName "XyRDP Admin" -Description "Full admin" -PasswordNeverExpires -AccountNeverExpires | Out-Null
Log "User '$u' dibuat (PasswordNeverExpires + tidak bisa lockout-expire)"

foreach ($g in 'Administrators','Remote Desktop Users') {
  try { Add-LocalGroupMember -Group $g -Member $u -ErrorAction Stop; Log "Member of: $g" }
  catch { Log "Skip group $g : $($_.Exception.Message)" }
}

# Full admin token juga lewat jaringan (tanpa UAC token filtering) -> "akses admin super penuh"
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null
# Jangan expire password 42 hari bawaan server
try { wmic useraccount where "name='$u'" set PasswordExpires=FALSE | Out-Null } catch { Log "wmic skip: $($_.Exception.Message)" }
# Ganti password saat login tidak diminta
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v ForceUserLogoff /t REG_DWORD /d 0 /f | Out-Null

# ---------- 2. Buka & konfig RDP ----------
Section "2. Aktifkan Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fSingleSessionPerUser' -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 1 -ErrorAction SilentlyContinue   # negotiate
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 0 -ErrorAction SilentlyContinue # tanpa prompt NLA/CredSSP -> "gaperlu klik"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'MaxIdleTime' -Value 0 -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fRemoveShutdownOptions' -Value 0 -ErrorAction SilentlyContinue
# Tanpa banner "The local policy setting..." saat connect
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'legalnoticecaption' -Value '' -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'legalnoticetext' -Value '' -ErrorAction SilentlyContinue
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDenyTSConnections /t REG_DWORD /d 0 /f | Out-Null

# Firewall: private network + rule RDP & UDP buat tailscale
try { Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop; Log "Network profile -> Private" } catch { Log "Network profile: skip ($($_.Exception.Message))" }
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
netsh advfirewall firewall add rule name="XyRDP TCP 3389" dir=in action=allow protocol=TCP localport=3389 | Out-Null
netsh advfirewall firewall add rule name="XyRDP UDP 3389" dir=in action=allow protocol=UDP localport=3389 | Out-Null
Log "Firewall rule RDP dibuka (hanya reachable via tailnet 100.64.0.0/10, tidak ada port publik)"

# Tidur/hibernate dimatikan biar sesi 6 jam tidak mati; monitor boleh padam
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 15 | Out-Null
Log "Power: sleep/hibernate OFF (hemat: monitor 15 menit)"

# ---------- 3. Unlock / tweak Windows ----------
Section "3. Unlock fitur & tweak kenyamanan"
# Long path
reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f | Out-Null
# UAC off (VM sekali-pakai) -> semua proses admin penuh tanpa prompt
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLinkedConnections /t REG_DWORD /d 1 /f | Out-Null
Log "UAC OFF + linked connections (drive mapping kelihatan di app admin)"
# SmartScreen (Explorer) off, supaya download/file jalan tanpa interstitial
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -PropertyType String -Value 'Off' -Force | Out-Null
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name SmartScreenEnabled -PropertyType String -Value 'Off' -Force | Out-Null
# Lock screen & welcome/consumer nag dimatikan (login = langsung desktop, tanpa klik)
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name NoLockScreen -PropertyType DWord -Value 1 -Force | Out-Null
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableSoftLanding -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableCloudOptimizedContent -PropertyType DWord -Value 1 -Force | Out-Null
# IE ESC off (bawaan Server, bikin browsing ribet)
foreach ($k in 'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8C41-4140E59147BC}',
               'HKLM\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8C41-4140E59147BC}') {
  reg add "$k" /v Version /d 1 /f | Out-Null
  reg add "$k" /v "IsInstalled" /t REG_DWORD /d 1 /f | Out-Null
}
# Auto logon console (kalau VM sempat restart, masuk sendiri) — aman, tidak ada port publik
$pk = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
reg add $pk /v AutoAdminLogon /t REG_SZ /d 1 /f | Out-Null
reg add $pk /v DefaultUserName /t REG_SZ /d $u /f | Out-Null
reg add $pk /v DefaultPassword /t REG_SZ /d $env:RDP_PASSWORD /f | Out-Null  # di VM ephemeral, hilang saat job selesai
reg add $pk /v DefaultDomainName /t REG_SZ /d $env:COMPUTERNAME /f | Out-Null
# Windows Defender (opsional)
if ($killDefender) {
  try {
    Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -ErrorAction Stop
    Log "Defender realtime monitoring OFF"
  } catch { Log "Defender: tidak bisa diubah ($($_.Exception.Message))" }
}
# Chrome: policy biar buka browser langsung bersih, tanpa dialog first-run / promo / reporting
if ($safeGoogle) {
  $gc = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
  New-Item -Path $gc -Force | Out-Null
  New-ItemProperty -Path $gc -Name CloudReportingEnabled        -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $gc -Name CloudUserOptIn                -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $gc -Name MetricsReportingEnabled        -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $gc -Name PromotionalTabsEnabled         -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $gc -Name WelcomePageOnOSUpgradeDisabled -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $gc -Name DnsOverHttpsMode               -PropertyType String -Value 'off' -Force | Out-Null
  Log "Chrome policy diset (first-run off, promo off, reporting off)"
}
Log "Tweak selesai: long path ON, UAC OFF, SmartScreen OFF, lock screen OFF, IE ESC OFF, auto-logon ON"

# ---------- 4. Tailscale ----------
Section "4. Install + join Tailscale"
$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $tsExe)) {
  $msi = Join-Path $env:RUNNER_TEMP 'Tailscale.msi'
  $msiUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi'
  Log "Download installer Tailscale dari $msiUrl ..."
  try { Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing } catch { Log "download msi gagal: $($_.Exception.Message)" }
  $ok = (Test-Path $msi) -and ((Get-Item $msi).Length -gt 1MB)
  if ($ok) {
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
    if (-not (Test-Path $tsExe)) { Log "msiexec exit=$LASTEXITCODE, coba installer exe..." }
  } else { Log "file msi terlalu kecil / tidak terunduh (kemungkinan 404 HTML)" }
  if (-not (Test-Path $tsExe)) {
    $exe = Join-Path $env:RUNNER_TEMP 'tailscale-setup.exe'
    try {
      Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' -OutFile $exe -UseBasicParsing
      if ((Get-Item $exe).Length -gt 1MB) { Start-Process $exe -ArgumentList '/S' -Wait }
    } catch { Log "fallback exe gagal: $($_.Exception.Message)" }
  }
}
if (-not (Test-Path $tsExe)) { Log "ERROR: instalasi Tailscale gagal."; exit 1 }
Log "Tailscale terpasang: $(& $tsExe version)"

$hostBase = ($env:TS_HOSTNAME -replace '[^a-zA-Z0-9-]','').ToLower().Trim('-')
if (-not $hostBase) { $hostBase = 'xyrdp' }
if ($hostBase.Length -gt 30) { $hostBase = $hostBase.Substring(0,30) }
$hostName = "$hostBase-$env:GITHUB_RUN_NUMBER"

Log "tailscale up sebagai '$hostName' (+ Tailscale SSH)"
$upArgs = @('up', "--authkey=$($env:TAILSCALE_AUTH_KEY)", "--hostname=$hostName", '--ssh', '--accept-routes=true')
if ($env:EXIT_NODE) {
  Log "Exit node diminta: $env:EXIT_NODE"
  $upArgs += @("--exit-node=$($env:EXIT_NODE)", '--exit-node-allow-lan-access')
}
& $tsExe @upArgs
$tsOk = $LASTEXITCODE -eq 0
if (-not $tsOk -and $env:EXIT_NODE) {
  Log "EXIT_NODE gagal, retry tanpa exit node..."
  & $tsExe @($upArgs | Where-Object { $_ -notlike '--exit-node*' })
}

$ip4 = ''; for ($i=0; $i -lt 30; $i++) {
  $ip4 = (& $tsExe ip -4 2>$null | Select-Object -First 1)
  if ($ip4) { break }
  Start-Sleep -Seconds 2
}
if (-not $ip4) { Log "ERROR: tidak dapat IP Tailscale (authkey salah / tailnet menolak)."; exit 1 }
$dns = ''
try { $st = (& $tsExe status --json | ConvertFrom-Json); $dns = $st.Self.DNSName } catch {}
Log "TAILNET IP : $ip4"
Log "MAGICDNS   : $dns"

# ---------- 5. Cek reputasi IP publik (konfirmasi jujur) ----------
Section "5. Cek IP keluar (publik) yang dilihat Google"
$pub = $null
try { $pub = Invoke-RestMethod 'http://ip-api.com/json/?fields=status,country,regionName,city,isp,as,query,proxy,hosting' -TimeoutSec 15 } catch { Log "ip-api tidak menjawab: $($_.Exception.Message)" }
$ipNote = 'unknown'
if ($pub) {
  Log "IP publik : $($pub.query) | $($pub.country) | $($pub.isp)"
  if ($pub.hosting -or $pub.proxy) {
    $ipNote = 'FLAGGED-DATACENTER'
    Log "PERINGATAN: IP terdeteksi hosting/proxy ($($pub.'as')). Google berpeluang minta verifikasi."
    Log "Solusi paling ampuh: isi input exit_node dengan node residential (mis. PC/HP/VM rumah yang ikut tailnet)."
  } else {
    $ipNote = 'CLEAN'
    Log "IP tidak kena flag hosting/proxy. Bagus."
  }
} else { $ipNote = 'UNKNOWN' }

# ---------- 6. Tulis status (TANPA PASSWORD) ----------
Section "6. Tulis out/rdp-status.json"
$now = Get-Date
$status = [ordered]@{
  active          = $true
  tailscale_ip    = $ip4
  tailscale_dns   = $dns
  ts_hostname     = $hostName
  rdp_port        = 3389
  rdp_user        = $u
  public_ip       = if ($pub) { $pub.query } else { 'n/a' }
  public_country  = if ($pub) { $pub.country } else { 'n/a' }
  public_isp      = if ($pub) { $pub.isp } else { 'n/a' }
  ip_note         = $ipNote
  started_at      = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  expires_at      = $now.AddMinutes($dur).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  duration_menit  = $dur
  run_id          = $env:GITHUB_RUN_ID
  run_number      = $env:GITHUB_RUN_NUMBER
  run_url         = "https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
  exit_node       = if ($env:EXIT_NODE) { $env:EXIT_NODE } else { '' }
}
$outDir = Join-Path $env:GITHUB_WORKSPACE 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$status | ConvertTo-Json | Set-Content -Encoding utf8 -Path (Join-Path $env:GITHUB_WORKSPACE 'out\rdp-status.json')
$now.ToString('s') | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE 'out\started.txt')
$status | ConvertTo-Json | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log ""
Log "SESI SIAP. Connect dari aplikasi Remote Desktop:"
Log "  Address : $ip4 (atau $dns)  Port: 3389"
Log "  Username: $u   Password: (yang tetap, ada di web dashboard / secret RDP_PASSWORD)"
Log "  Syarat  : perangkat kamu harus login ke TAILNET yang sama."
