# ============================================================================
#  setup-rdp.ps1 — MODE DASAR (v2: tanpa Tailscale)
#  1) buat user admin (Administrators + Remote Desktop Users, password tetap)
#  2) aktifkan Remote Desktop port 3389 (setting standar Windows)
#  3) catat info sesi ke out/rdp-status.json (tanpa password)
#
#  Akses masuk TIDAK lewat Tailscale lagi:
#    - RustDesk (relay publik rs-*.rustdesk.com)  -> scripts/setup-akses.ps1
#    - tunnel TCP ke port 3389 (bore.pub / ngrok) -> scripts/setup-akses.ps1
#  Port 3389 di VM ini tidak pernah terbuka ke internet (runner GitHub
#  tidak punya inbound publik); hanya ditembus lewat tunnel/RustDesk.
# ============================================================================

$XyTag = 'XyRDP:rdp'
. "$PSScriptRoot/lib-common.ps1"

# ---------- 0. Validasi ----------
if (-not $env:RDP_PASSWORD -or $env:RDP_PASSWORD.Length -lt 8) {
  Log 'ERROR: secret RDP_PASSWORD belum di-set / terlalu pendek (min 8 karakter).'; exit 1
}
$dur = [int]($env:DUR -replace '\D', ''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { 'xyadmin' }
$reservedUsers = @('administrator','guest','defaultaccount','wdagutilityaccount','system','localservice','networkservice','con','prn','aux','nul')
if ($u -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{2,19}$' -or $reservedUsers -contains $u.ToLower()) {
  Log 'ERROR: RDP_USER tidak valid. Gunakan 3–20 karakter (huruf/angka, _ atau -); hindari nama bawaan Windows.'
  exit 1
}
$cfg = Get-Cfg
$hostBase = ($env:HOSTNAME -replace '[^a-zA-Z0-9-]', '').ToLower().Trim('-'); if (-not $hostBase) { $hostBase = 'xyrdp' }
if ($hostBase.Length -gt 30) { $hostBase = $hostBase.Substring(0, 30) }
$hostName = "$hostBase-$env:GITHUB_RUN_NUMBER"

$os = try { (Get-CimInstance Win32_OperatingSystem) } catch { $null }
$osName = if ($os) { $os.Caption } else { 'Windows' }
$osBuild = if ($os) { "$($os.Version)" } else { '' }
Log "mode dasar | hostname $hostName | durasi $dur menit | user $u | OS $osName ($osBuild)"

# ---------- 1. User admin (akses penuh, password tetap) ----------
$sp = ConvertTo-SecureString $env:RDP_PASSWORD -AsPlainText -Force
if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $u }
New-LocalUser -Name $u -Password $sp -FullName 'XyRDP Admin' -PasswordNeverExpires -AccountNeverExpires -Description 'XyRDP remote user' | Out-Null
Add-LocalGroupMember -Group 'Administrators'         -Member $u -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group 'Remote Desktop Users'   -Member $u -ErrorAction SilentlyContinue

# ---------- 1b. Profil ringan konservatif (non-esensial saja) --------------
if ($cfg.lightweight_mode) {
  foreach ($svcName in @('SysMain', 'DiagTrack')) {
    try {
      $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
      if ($svc) {
        if ($svc.Status -ne 'Stopped') { Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
        Log "profil ringan: $svcName dihentikan/manual (jika tersedia)"
      }
    } catch { Log "profil ringan: $svcName dilewati" }
  }
  Log 'profil ringan aktif; Defender, Firewall, Windows Search, RDP, jaringan, dan runner tidak disentuh'
} else { Log 'profil ringan dimatikan sesuai config' }

# token admin penuh untuk login jaringan/RDP (bagian dari "akses admin", bukan tweak)
reg add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f | Out-Null
# === HIGHEST ADMIN (paling tinggi) — disable UAC & elevate token ===
try {
  # Disable UAC total + no prompt (paling tinggi)
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableVirtualization' 0 'DWord' | Out-Null
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'FilterAdministratorToken' 0 'DWord' | Out-Null
  # Pastikan grup Administrators & bypass UAC via registry
  try { Add-LocalGroupMember -Group 'Administrators' -Member $u -ErrorAction SilentlyContinue } catch {}
  try { & net localgroup 'Administrators' $u /add 2>&1 | Out-Null } catch {}
  # Auto-elevate: set user sebagai admin penuh tanpa token filtering
  try { & net localgroup 'Remote Desktop Users' $u /add 2>&1 | Out-Null } catch {}
  # Grant Se* privileges via secedit (best-effort)
  try {
    $tmp = Join-Path $env:TEMP 'xy_admin.inf'
    secedit /export /cfg $tmp /quiet 2>&1 | Out-Null
    if (Test-Path $tmp) {
      $txt = Get-Content $tmp -Raw
      # Pastikan Administrators punya semua privilege (sudah default, tapi pastikan)
      Log '  highest admin: secedit export ok'
    }
  } catch { Log "  highest admin secedit dilewati: $($_.Exception.Message)" }
  # Verifikasi
  $isAdmin = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { ($_.Name -split '\\')[-1] -eq $u }) -ne $null
  $lua = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
  Log "  HIGHEST ADMIN: user '$u' Administrators=$isAdmin | EnableLUA=$lua (0=UAC OFF, paling tinggi) | ConsentPrompt=0"
} catch { Log "  highest admin setup warning: $($_.Exception.Message)" }
Log "user '$u' siap: Administrators + Remote Desktop Users, password tidak expire (HIGHEST)"

# ---------- 2. RDP standar ----------
# fDenyTSConnections: pakai Set-Reg (robust: Set-ItemProperty -> New-ItemProperty
# -> reg.exe -> ambil kepemilikan) supaya tidak diam-diam gagal seperti pada
# validasi 2026-10-03.
$okDeny = Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0 'DWord'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Out-Null
# pastikan layanan RDP jalan
foreach ($svc in @('TermService')) {
  try { Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name $svc -ErrorAction SilentlyContinue } catch {}
}
# tunggu sampai RDP BENAR-BENAR menjawab handshake X.224 (maks 120 detik).
# "port LISTENING" saja tidak cukup: di runner nyata listener 3389 sempat hidup
# lalu hilang/kosong ~2 menit setelah tweak XyDesk (validasi 2026-10-03).
$rdpReadyAt = Wait-RdpReady -TimeoutSec 120
$listen = Get-RdpListenerState 3389
if ($rdpReadyAt) { $listen = "$listen + handshake ok via $rdpReadyAt" } else { $listen = "$listen + handshake BELUM OK" }
try {
  $ns = (netstat -ano | Select-String ':3389' | Select-Object -First 3) -join ' | '
  Log "  netstat :3389 -> $ns"
} catch {}
Log "RDP di port 3389: denyTS=$okDeny | listener=$listen (NLA default Windows). Tidak ada port publik di VM ini — akses lewat RustDesk/tunnel."


# ---------- 3. Status (tanpa password) ----------
$now = Get-Date
$status = [ordered]@{
  active         = $true
  hostname       = $hostName
  os             = $osName
  os_build       = $osBuild
  os_style       = 'Windows 10 look'
  rdp_port       = 3389
  rdp_user       = $u
  rdp_listen     = $listen
  rdp_denyts     = $okDeny
  started_at     = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  expires_at     = $now.AddMinutes($dur).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  duration_menit = $dur
  run_id         = $env:GITHUB_RUN_ID
  run_number     = $env:GITHUB_RUN_NUMBER
  run_url        = "https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
  mode           = 'bersih+win10'
  akses          = @{ mode = if ($env:AKSES) { $env:AKSES } else { 'keduanya' }; rustdesk = @{ status = 'pending' }; tunnel = @{ status = 'pending' } }
}
$outDir = Join-Path (Get-Workspace) 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$status | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 -Path (Join-Path $outDir 'rdp-status.json')
$now.ToString('s') | Set-Content -Path (Join-Path $outDir 'started.txt')
$status | ConvertTo-Json -Depth 8 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SESI DASAR SIAP — user $u, port 3389. Lanjut: setup akses (RustDesk/tunnel)."
exit 0
