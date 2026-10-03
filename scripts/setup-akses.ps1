# ============================================================================
#  setup-akses.ps1 — akses masuk TANPA Tailscale (v2)
# ----------------------------------------------------------------------------
#  Dua jalur, bisa jalan bareng ("keduanya"):
#
#   1) RUSTDESK  — remote desktop app (klien di PC kamu, gratis, tanpa VPN)
#        - installer dari winget (fallback: GitHub releases rustdesk/rustdesk)
#        - dipasang sebagai service (mode unattended, bisa sampai layar login)
#        - password permanen = RDP_PASSWORD (satu password untuk semua)
#        - server rendezvous/relay memakai server PUBLIK bawaan RustDesk
#          (rs-ny.rustdesk.com / rs-sg.rustdesk.com) -> TIDAK self-host apa pun
#
#   2) TUNNEL TCP ke port 3389 — buat Remote Desktop Connection (mstsc) biasa
#        - bore   : bore.pub, tanpa akun, tanpa daftar  (default)
#        - ngrok  : butuh NGROK_AUTHTOKEN (akun gratis)  (lebih stabil)
#      URL: bore.pub:<port> atau <x>.tcp.ngrok.io:<port>
#
#  Hasil (RustDesk ID + host:port tunnel) ditulis ke out/rdp-status.json dan
#  muncul di dashboard web. Tanpa password apa pun di file itu.
# ============================================================================

$XyTag = 'XyRDP:akses'
. "$PSScriptRoot/lib-common.ps1"

$u        = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }
$pw       = $env:RDP_PASSWORD
$localPort = 3389
$work     = 'C:\XyRDP\akses'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$mode = if ($env:AKSES) { $env:AKSES.Trim().ToLower() } else { 'keduanya' }
if (@('rustdesk', 'rd', 'keduanya', 'both', 'dua', 'tunnel', 'rdp', 'tailscale', 'ts', 'semua', 'all') -notcontains $mode) { $mode = 'keduanya' }
if (@('both', 'dua') -contains $mode) { $mode = 'keduanya' }
if ($mode -eq 'ts') { $mode = 'tailscale' }
if ($mode -eq 'all') { $mode = 'semua' }
$useRd     = ($mode -in @('keduanya', 'rustdesk', 'rd', 'semua'))
$useTunnel = ($mode -in @('keduanya', 'tunnel', 'rdp', 'semua'))
$useTs     = ($mode -in @('tailscale', 'semua'))
$tsKey     = if ($env:TAILSCALE_AUTH_KEY) { $env:TAILSCALE_AUTH_KEY } else { $env:TS_AUTHKEY }
$tsKeyTxt  = if ($tsKey) { 'ada' } else { 'TIDAK ADA' }
Log "mode=$mode | rustdesk=$useRd tunnel=$useTunnel tailscale=$useTs (kunci $tsKeyTxt)"

$prov = if ($env:TUNNEL_PROVIDER) { $env:TUNNEL_PROVIDER.Trim().ToLower() } else { 'otomatis' }
if (@('otomatis', 'auto', 'bore', 'ngrok', 'pinggy', 'ssh') -notcontains $prov) { $prov = 'otomatis' }
$ngrokTok = if ($env:NGROK_AUTHTOKEN) { $env:NGROK_AUTHTOKEN } else { $env:NGROK_TOKEN }

Log "mode akses = $mode | provider tunnel = $prov | RustDesk=$useRd | Tunnel=$useTunnel"

# ============================================================================
#  helper: jalankan perintah eksternal dengan TIMEOUT KERAS
#  (pelajaran dari validasi 2026-10-03: `Start-Process --silent-install -Wait`
#   menggantung selamanya karena installer RustDesk menyalakan proses anak;
#   -Wait menunggu seluruh process tree -> job bisa nyangkut berjam-jam)
# ============================================================================
function Invoke-Cmd([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSec = 60) {
  $tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $outF = Join-Path $work "cmd-$tag.out"
  $errF = Join-Path $work "cmd-$tag.err"
  $res = @{ ok = $false; timeout = $false; code = $null; out = ''; err = '' }
  try {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow `
         -RedirectStandardOutput $outF -RedirectStandardError $errF -ErrorAction Stop
    try {
      $p | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
      $res.ok = $true
      $res.code = $p.ExitCode
    } catch {
      $res.timeout = $true
      try { $p | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    }
  } catch { $res.err = $_.Exception.Message }
  if (Test-Path $outF) { $res.out = (Get-Content $outF -Raw -ErrorAction SilentlyContinue) }
  if (Test-Path $errF) { $res.err = "$($res.err)`n$(Get-Content $errF -Raw -ErrorAction SilentlyContinue)" }
  return $res
}

# tes cepat: apakah ada yang mendengarkan di host:port (dipakai untuk memilih
# target tunnel secara dinamis — di runner windows-2022 RDP ternyata bisa hanya
# listen di IPv6 [::]:3389, sehingga 127.0.0.1 ditolak)
function Test-LocalPort([string]$HostName, [int]$Port, [int]$TimeoutMs = 4000) {
  try {
    $tc = New-Object System.Net.Sockets.TcpClient
    $task = $tc.ConnectAsync($HostName, $Port)
    if ($task.Wait($TimeoutMs) -and -not $task.IsFaulted) { $tc.Close(); return @{ ok = $true; err = '' } }
    $err = if ($task.IsFaulted -and $task.Exception) { $task.Exception.InnerException.Message } else { 'timeout' }
    $tc.Close()
    return @{ ok = $false; err = $err }
  } catch { return @{ ok = $false; err = $_.Exception.Message } }
}

# matikan aplikasi tray RustDesk (kalau ada) supaya CLI & service bersih
function Stop-RustDeskTray {
  try {
    $apps = Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path -like '*RustDesk*' -and $_.SessionId -ne 0 }
    if ($apps) { $apps | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
  } catch {}
}

# ============================================================================
#  BAGIAN 1 — RUSTDESK
# ============================================================================
function Find-RustDesk {
  $cands = @(
    (Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'RustDesk\rustdesk.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\RustDesk\rustdesk.exe')
  )
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  foreach ($roots in @('C:\Program Files', 'C:\Program Files (x86)')) {
    try {
      $g = Get-ChildItem $roots -Recurse -Depth 3 -Filter 'rustdesk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($g) { return $g.FullName }
    } catch {}
  }
  $cmd = Get-Command rustdesk.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

# tunggu sabar sampai binary RustDesk muncul (installer bisa asinkron)
function Wait-RustDeskFiles([int]$maxSec = 300) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $maxSec) {
    if (Find-RustDesk) { return $true }
    Start-Sleep -Seconds 10
  }
  return [bool](Find-RustDesk)
}

function Install-RustDesk {
  # Urutan: MSI (paling andal: msiexec menunggu sampai selesai) -> winget -> exe
  $msi = Get-GhAssetUrl 'rustdesk/rustdesk' '^rustdesk-[0-9.]+-x86_64\.msi$'
  if (-not $msi -and $script:XyFallbackUrls['rustdesk/rustdesk.msi']) {
    $msi = @{ url = $script:XyFallbackUrls['rustdesk/rustdesk.msi']; tag = 'fallback'; name = 'rustdesk-x86_64.msi' }
    Log '  API GitHub tidak tersedia -> pakai URL rilis langsung untuk MSI RustDesk'
  }
  if ($msi) {
    $msiFile = Join-Path $work 'rustdesk-x86_64.msi'
    if (Get-File $msi.url $msiFile 300) {
      Log "  install MSI: $($msi.name) ($($msi.tag))..."
      $r = Invoke-Cmd 'msiexec.exe' @('/i', $msiFile, '/qn', '/norestart', '/l*v', (Join-Path $work 'msi.log')) 600
      if ($r.timeout) { Log '  msiexec TIMEOUT 600s — lanjut verifikasi berkas' }
      else { Log "  msiexec selesai (exit=$($r.code))" }
      if (Wait-RustDeskFiles 120) { return $true }
    } else { Log '  unduh MSI gagal' }
  }
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if ($wg) {
    Log '  mencoba winget (RustDesk.RustDesk)...'
    $r = Invoke-Cmd 'winget' @('install','-e','--id','RustDesk.RustDesk','--source','winget',
                                '--accept-source-agreements','--accept-package-agreements','--disable-interactivity') 300
    if ($r.timeout) { Log '  winget TIMEOUT 300s — lanjut ke installer exe' }
    else { Log ("  winget: " + (Log-Tail "$($r.out)$($r.err)" 1)) }
    Stop-RustDeskTray
    if (Wait-RustDeskFiles 60) { return $true }
  }
  # fallback terakhir: installer exe (asinkron; tunggu sampai 5 menit)
  $asset = Get-GhAssetUrl 'rustdesk/rustdesk' '^rustdesk-[0-9.]+-x86_64\.exe$'
  if (-not $asset -and $script:XyFallbackUrls['rustdesk/rustdesk.exe']) {
    $asset = @{ url = $script:XyFallbackUrls['rustdesk/rustdesk.exe']; tag = 'fallback'; name = 'rustdesk-x86_64.exe' }
  }
  if (-not $asset) { Log '  tidak menemukan installer RustDesk di GitHub releases'; return $false }
  $exe = Join-Path $work $asset.name
  if (-not (Get-File $asset.url $exe 300)) { Log '  unduh installer RustDesk gagal'; return $false }
  Log "  install exe: $($asset.name) ($($asset.tag))..."
  $r = Invoke-Cmd $exe @('--silent-install') 420
  if ($r.timeout) { Log '  installer exe TIMEOUT 420s — verifikasi berkas' }
  else { Log "  installer exe selesai (exit=$($r.code))" }
  Stop-RustDeskTray
  return (Wait-RustDeskFiles 300)
}

$rdStatus = 'skip'; $rdId = ''; $rdServer = 'rs-ny.rustdesk.com / rs-sg.rustdesk.com (server publik RustDesk)'
if ($useRd) {
  Log 'RUSTDESK: menyiapkan...'
  $rdExe = Find-RustDesk
  if (-not $rdExe) { Install-RustDesk | Out-Null; $rdExe = Find-RustDesk }
  if (-not $rdExe) {
    Log '  GAGAL: RustDesk tidak terpasang (sesi tetap jalan lewat tunnel bila ada)'
    $rdStatus = 'gagal'
  } else {
    Log "  terpasang: $rdExe"
    # service (mode unattended: bisa konek walau belum ada user login)
    $svcOk = $false
    try {
      if (-not (Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue)) {
        $r = Invoke-Cmd $rdExe @('--install-service') 90
        if ($r.timeout) { Log '  --install-service TIMEOUT 90s' }
      }
      for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
        if ($svc) { break }
        Start-Sleep -Seconds 3
      }
      $svc = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
      if ($svc) {
        Set-Service -Name 'RustDesk' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
        $svcOk = $true
        Log '  service RustDesk: aktif (mode unattended)'
      } else { Log '  service RustDesk belum terdaftar (lanjut; password/ID tetap dicoba)' }
    } catch { Log "  service RustDesk (tidak kritis): $($_.Exception.Message)" }

    # password permanen = password RDP (biar user hanya perlu 1 password)
    $pwOk = $false
    for ($i = 1; $i -le 3 -and -not $pwOk; $i++) {
      $r = Invoke-Cmd $rdExe @('--password', $pw) 30
      if (-not $r.timeout) { $pwOk = $true } else { Log "  --password TIMEOUT (coba $i/3)"; Start-Sleep -Seconds 3 }
    }
    Log "  password permanen di-set: $(if ($pwOk) { 'ok' } else { 'PERLU CEK MANUAL' })"

    # opsional (lanjutan): server sendiri/terdekat lewat env RD_SERVER
    if ($env:RD_SERVER) {
      try {
        $toml = "# XyRDP`nrendezvous_server = '$($env:RD_SERVER)'`n`n[options]`nrelay-server = '$($env:RD_SERVER)'`n"
        foreach ($p in @(
          'C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config',
          'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config',
          (Join-Path $env:APPDATA 'RustDesk\config')
        )) {
          New-Item -ItemType Directory -Path $p -Force | Out-Null
          Set-Content -Path (Join-Path $p 'RustDesk2.toml') -Value $toml -Encoding utf8
        }
        $rdServer = "$($env:RD_SERVER) (RD_SERVER dari input workflow)"
        Log "  server RustDesk diset: $($env:RD_SERVER) — klien kamu harus pakai server yang sama!"
        Restart-Service -Name 'RustDesk' -Force -ErrorAction SilentlyContinue
      } catch { Log "  set server RustDesk gagal (tidak kritis): $($_.Exception.Message)" }
    }

    # ambil ID (perlu beberapa detik setelah service register ke server)
    for ($i = 1; $i -le 12 -and -not $rdId; $i++) {
      $r = Invoke-Cmd $rdExe @('--get-id') 25
      if ($r.out) {
        foreach ($line in ($r.out -split "`r?`n")) {
          $clean = ($line -replace '\s', '').Trim()
          if ($clean -match '^[0-9]{6,12}$') { $rdId = $clean; break }
        }
      }
      if (-not $rdId) { Start-Sleep -Seconds 5 }
    }
    if ($rdId) {
      Log "  RUSTDESK ID : $rdId"
      Log "  (klien RustDesk kamu -> masukkan ID di atas + password, tanpa VPN)"
      $rdStatus = 'ok'
      # auto-start untuk user RDP
      Open-DefaultHive | Out-Null
      if ($script:HiveLoaded) {
        Set-Reg ($script:DefReg + '\Software\Microsoft\Windows\CurrentVersion\Run') 'RustDesk' $rdExe 'String' | Out-Null
        Close-DefaultHive
      }
      try { Start-Process -FilePath $rdExe -ErrorAction SilentlyContinue } catch {}
    } else {
      Log '  ID RustDesk belum keluar setelah 100 detik (server publik lambat / diblokir).'
      Log '  Cek manual di VM: rustdesk.exe --get-id'
      $rdStatus = 'gagal-id'
    }
  }
}

# ============================================================================
#  BAGIAN 2 — TUNNEL TCP (RDP 3389)
# ============================================================================
function Wait-Tunnel([string]$logFile, [string]$regex, [int]$timeoutSec = 90) {
  for ($i = 0; $i -lt $timeoutSec; $i++) {
    if (Test-Path $logFile) {
      $txt = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
      if ($txt) {
        $m = [regex]::Match($txt, $regex, 'IgnoreCase')
        if ($m.Success) { return $m }
      }
    }
    Start-Sleep -Seconds 1
  }
  return $null
}

function Start-Bore {
  Log '  bore: siapkan binary...'
  $dir = Join-Path $work 'bore'
  $boreExe = Join-Path $dir 'bore.exe'
  if (-not (Test-Path $boreExe)) {
    $asset = Get-GhAssetUrl 'ekzhang/bore' 'x86_64-pc-windows-msvc\.zip$'
    if (-not $asset) { $asset = @{ url = $script:XyFallbackUrls['ekzhang/bore.zip']; tag = 'fallback'; name = 'bore-win64.zip' } }
    $zip = Join-Path $work 'bore.zip'
    if (-not (Get-File $asset.url $zip 180)) { Log '  unduh bore gagal'; return $null }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    # zip bisa punya subfolder
    if (-not (Test-Path $boreExe)) {
      $g = Get-ChildItem $dir -Recurse -Filter 'bore.exe' | Select-Object -First 1
      if ($g) { $boreExe = $g.FullName }
    }
  }
  if (-not (Test-Path $boreExe)) { Log '  bore.exe tidak ada'; return $null }
  $logF = Join-Path $work 'bore.log'
  Remove-Item $logF -ErrorAction SilentlyContinue
  $tgt = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
  Log "  mulai: bore local $localPort --local-host $tgt --to bore.pub"
  # --local-host eksplisit (bukan 'localhost'): hindari salah pilih IPv4/IPv6
  $p = Start-Process -FilePath $boreExe -ArgumentList @('local', "$localPort", '--local-host', $tgt, '--to', 'bore.pub') `
        -RedirectStandardOutput $logF -RedirectStandardError (Join-Path $work 'bore.err') -PassThru -WindowStyle Hidden
  $m = Wait-Tunnel $logF 'listening at\s+([^\s:]+):(\d+)' 90
  if (-not $m) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; Log '  bore: tidak dapat endpoint (timeout)'; return $null }
  Log "  TUNNEL : $($m.Groups[1].Value):$($m.Groups[2].Value) (bore, tanpa akun)"
  return @{ provider = 'bore'; host = $m.Groups[1].Value; port = [int]$m.Groups[2].Value; pid = $p.Id; log = $logF }
}

function Start-Ngrok {
  if (-not $ngrokTok) { Log '  ngrok: NGROK_AUTHTOKEN tidak di-set — dilewati'; return $null }
  $dir = Join-Path $work 'ngrok'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $ngrokExe = Join-Path $dir 'ngrok.exe'
  if (-not (Test-Path $ngrokExe)) {
    $zip = Join-Path $work 'ngrok.zip'
    if (-not (Get-File 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' $zip 180)) { Log '  unduh ngrok gagal'; return $null }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
  }
  if (-not (Test-Path $ngrokExe)) { Log '  ngrok.exe tidak ada'; return $null }
  try { & $ngrokExe config add-authtoken $ngrokTok 2>&1 | Out-Null } catch { Log "  ngrok authtoken: $($_.Exception.Message)" }
  $logF = Join-Path $work 'ngrok.log'
  Remove-Item $logF -ErrorAction SilentlyContinue
  $tgt = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
  $tgtTxt = if ($tgt -like '*:*') { "[$tgt]" } else { $tgt }   # IPv6 perlu kurung siku
  Log "  mulai: ngrok tcp $tgtTxt`:$localPort"
  $p = Start-Process -FilePath $ngrokExe -ArgumentList @('tcp', "$tgtTxt`:$localPort", '--log=stdout', '--log-format=json') `
        -RedirectStandardOutput $logF -RedirectStandardError (Join-Path $work 'ngrok.err') -PassThru -WindowStyle Hidden
  $m = Wait-Tunnel $logF 'tcp://([^":\s]+):(\d+)' 90
  if (-not $m) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; Log '  ngrok: tidak dapat endpoint (timeout / token salah)'; return $null }
  Log "  TUNNEL : $($m.Groups[1].Value):$($m.Groups[2].Value) (ngrok)"
  return @{ provider = 'ngrok'; host = $m.Groups[1].Value; port = [int]$m.Groups[2].Value; pid = $p.Id; log = $logF }
}

# ---------------------------------------------------------------------------
#  Pinggy: tunnel TCP lewat SSH (port 443) — TANPA akun, tanpa daftar.
#  Terverifikasi 3 Okt 2026 dari node luar (8/8 tersambung, termasuk Vietnam),
#  sementara bore.pub pada sesi yang sama DITOLAK dari luar (6/8 node gagal)
#  padahal "selftest ok" dari dalam VM. Urutan otomatis sekarang:
#  pinggy -> ngrok (kalau ada token) -> bore.
# ---------------------------------------------------------------------------
function Get-SshCandidates {
  # Urutan penting: ssh bawaan Git (MSYS) berperilaku seperti ssh Linux dan
  # mencetak keluaran server dengan benar. ssh.exe Windows OpenSSH di runner
  # terbukti keluar TANPA keluaran apa pun (diagnostik run 37150390456).
  $cands = @(
    "$env:ProgramFiles\Git\usr\bin\ssh.exe",
    "$env:ProgramFiles\Git\bin\ssh.exe",
    'C:\Program Files\Git\usr\bin\ssh.exe',
    "$env:ProgramFiles\OpenSSH\ssh.exe",
    "$env:SystemRoot\System32\OpenSSH\ssh.exe"
  )
  $c = Get-Command ssh -ErrorAction SilentlyContinue
  if ($c) { $cands += $c.Source }
  return @($cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)
}

function Start-Pinggy {
  $logF = Join-Path $work 'pinggy.log'
  $errF = Join-Path $work 'pinggy.err'
  $sshList = Get-SshCandidates
  if (-not $sshList -or $sshList.Count -eq 0) { Log '  pinggy: ssh.exe tidak ditemukan - dilewati'; return $null }

  # diagnostik jaringan: server pinggy terjangkau dari VM ini?
  foreach ($hp in @(@('a.pinggy.io', 443), @('a.pinggy.io', 22))) {
    try {
      $ok = $false
      $tc = New-Object System.Net.Sockets.TcpClient
      $ok = $tc.ConnectAsync($hp[0], $hp[1]).Wait(7000); $tc.Close()
      Log "  pinggy: TCP $($hp[0]):$($hp[1]) -> $(if ($ok) { 'TERJANGKAU' } else { 'TIDAK terjangkau' })"
    } catch { Log "  pinggy: uji TCP $($hp[0]):$($hp[1]) error: $($_.Exception.Message)" }
  }
  if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }   # MSYS ssh butuh HOME

  $tgt = if ($script:RdpTarget -and $script:RdpTarget -ne '::1') { $script:RdpTarget } else { '127.0.0.1' }
  foreach ($ssh in $sshList) {
    $isMsys = ($ssh -match 'Git')
    $kh = if ($isMsys) { '/dev/null' } else { 'NUL' }
    foreach ($port in @(443, 22)) {
      foreach ($attempt in 1..2) {
        Remove-Item $logF, $errF -ErrorAction SilentlyContinue
        Log "  pinggy: klien=$([System.IO.Path]::GetFileName($ssh)) port=$port (coba $attempt, target $tgt`:$localPort)"
        # WAJIB: beri stdin yang valid (file kosong = EOF). Kalau stdin tidak valid,
        # ssh tidak meminta channel sesi dan server pinggy TIDAK mengirim banner
        # yang memuat tcp://... -> tunnel terbentuk tapi alamatnya tidak pernah
        # kita ketahui (persis kejadian di run 37150390456 & 37151286900).
        $inF = Join-Path $work 'pinggy.in'
        if (-not (Test-Path $inF)) { New-Item -ItemType File -Path $inF -Force | Out-Null }
        $sshArgs = @('-p', "$port", '-T', '-o', 'StrictHostKeyChecking=no', '-o', "UserKnownHostsFile=$kh",
                     '-o', 'LogLevel=INFO', '-o', 'ServerAliveInterval=20', '-o', 'ConnectTimeout=15',
                     '-o', 'ExitOnForwardFailure=yes', "-R0:$tgt`:$localPort", 'tcp@a.pinggy.io')
        $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -RedirectStandardOutput $logF `
              -RedirectStandardError $errF -RedirectStandardInput $inF -PassThru -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(70)
        while ((Get-Date) -lt $deadline) {
          Start-Sleep -Seconds 2
          $txt = (@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join '') +
                 (@(Get-Content $errF -Raw -ErrorAction SilentlyContinue) -join '')
          if ($txt -match 'tcp://([a-zA-Z0-9.-]+):(\d+)') {
            $h = $Matches[1]; $pt = [int]$Matches[2]
            Log "  TUNNEL : $h`:$pt (pinggy, tanpa akun)"
            return @{ provider = 'pinggy'; host = $h; port = $pt; pid = $p.Id; log = $logF }
          }
          if ($p.HasExited) { break }
        }
        $out = ((@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join ' ') -replace '\s+', ' ').Trim()
        $err = ((@(Get-Content $errF -Raw -ErrorAction SilentlyContinue) -join ' ') -replace '\s+', ' ').Trim()
        $code = 'masih jalan'; try { if ($p.HasExited) { $code = "exit=$($p.ExitCode)" } } catch {}
        Log "  pinggy: gagal ($code)."
        Log "    stdout($($out.Length) char): $($out.Substring(0, [Math]::Min(300, $out.Length)))"
        Log "    stderr($($err.Length) char): $($err.Substring(0, [Math]::Min(300, $err.Length)))"
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
      }
    }
  }
  Log '  pinggy: semua klien/port gagal - tidak dapat endpoint'
  return $null
}

# ---------------------------------------------------------------------------
#  TAILSCALE (jalur yang sudah lama terbukti jalan dari runner GitHub):
#  runner masuk tailnet kamu sebagai node 100.x, lalu HP (XyDesk Remote/mstsc)
#  menyambung ke IP itu. Tanpa port publik, tanpa relay pihak ketiga.
#  Bonus: dicoba `tailscale funnel` -> alamat publik <node>.<tailnet>.ts.net:10000
#  yang bisa dipakai TANPA memasang apa pun di HP (kalau tailnet mengizinkan).
# ---------------------------------------------------------------------------
function Get-TsExe {
  foreach ($p in @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Install-Tailscale {
  $tsExe = Get-TsExe
  if ($tsExe) { return $tsExe }
  $msi = Join-Path $work 'tailscale.msi'
  if (Get-File 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' $msi 240) {
    $r = Invoke-Cmd 'msiexec.exe' @('/i', $msi, '/qn', '/norestart') 420
    Log "  tailscale: msiexec exit=$($r.code)"
  }
  $tsExe = Get-TsExe
  if (-not $tsExe) {
    $exe = Join-Path $work 'tailscale-setup.exe'
    if (Get-File 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' $exe 240) {
      $r2 = Invoke-Cmd $exe @('/S') 420
      Log "  tailscale: installer exe exit=$($r2.code)"
    }
  }
  return (Get-TsExe)
}

function Start-Tailscale {
  $tsExe = Install-Tailscale
  if (-not $tsExe) { Log '  tailscale: instalasi gagal (msi & exe)'; return $null }
  if (-not $tsKey) { Log '  tailscale: kunci auth kosong / tidak diteruskan workflow'; return $null }
  $ver = ((Invoke-Cmd $tsExe @('version') 30).out -split "`n" | Select-Object -First 1)
  Log "  tailscale: versi $ver"
  $tsHost = ($env:HOSTNAME -replace '[^a-zA-Z0-9-]', '').ToLower().Trim('-'); if (-not $tsHost) { $tsHost = 'xyrdp' }
  if ($tsHost.Length -gt 24) { $tsHost = $tsHost.Substring(0, 24) }
  $tsHost = "$tsHost-$env:GITHUB_RUN_NUMBER"
  Log "  tailscale: up sebagai '$tsHost'..."
  # --accept-dns=false: jangan utak-atik DNS runner
  $up = Invoke-Cmd $tsExe @('up', "--authkey=$tsKey", "--hostname=$tsHost", '--accept-dns=false', '--timeout=90s') 180
  if ($up.code -ne 0) {
    Log "  tailscale: up exit=$($up.code) - ulangi tanpa --accept-dns"
    $up = Invoke-Cmd $tsExe @('up', "--authkey=$tsKey", "--hostname=$tsHost", '--timeout=90s') 180
  }
  $ip4 = ''
  for ($i = 1; $i -le 30 -and -not $ip4; $i++) {
    $r = Invoke-Cmd $tsExe @('ip', '-4') 20
    if ($r.ok -and $r.out) {
      $line = ($r.out -split "`n" | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' } | Select-Object -First 1)
      if ($line) { $ip4 = $line.Trim() }
    }
    if (-not $ip4) { Start-Sleep -Seconds 2 }
  }
  if (-not $ip4) { Log '  tailscale: TIDAK dapat IP 100.x (kunci salah/kedaluwarsa/tailnet menolak)'; return $null }
  $dns = ''; $stTxt = ''
  $sr = Invoke-Cmd $tsExe @('status', '--json') 30
  if ($sr.ok -and $sr.out) {
    try { $j = $sr.out | ConvertFrom-Json; $dns = "$($j.Self.DNSName)"; $stTxt = "$($j.BackendState)" } catch {}
  }
  $capMap = ''
  try { if ($j -and $j.Self -and $j.Self.CapMap) { $capMap = (@($j.Self.CapMap.PSObject.Properties.Name) -join ',') } } catch {}
  Log "  tailscale: IP=$ip4 magicdns=$dns state=$stTxt capmap=[$capMap]"

  # bonus: funnel (alamat publik tanpa app Tailscale di HP) - best effort + diagnostik mentah
  $funnel = 'tidak aktif'; $funnelAddr = ''; $fRaw = ''
  $f = Invoke-Cmd $tsExe @('funnel', '--bg', '--tcp', '10000', 'tcp://127.0.0.1:3389') 60
  $fo = (("$($f.out)" + ' | ' + "$($f.err)") -replace '\s+', ' ').Trim()
  $fRaw = 'funnel exit=' + $f.code + ' msg=' + $fo
  if ($f.code -ne 0) {
    $srv = Invoke-Cmd $tsExe @('serve', '--bg', '--tcp', '10000', 'tcp://127.0.0.1:3389') 60
    $so = (("$($srv.out)" + ' | ' + "$($srv.err)") -replace '\s+', ' ').Trim()
    $fRaw = $fRaw + ' || serve exit=' + $srv.code + ' msg=' + $so
    if ($srv.code -eq 0) {
      $f = Invoke-Cmd $tsExe @('funnel', '--bg', '--tcp', '10000') 60
      $fo2 = (("$($f.out)" + ' | ' + "$($f.err)") -replace '\s+', ' ').Trim()
      $fRaw = $fRaw + ' || funnel2 exit=' + $f.code + ' msg=' + $fo2
    }
  }
  $fsr = Invoke-Cmd $tsExe @('funnel', 'status', '--json') 45
  if (-not $fsr.out) { $fsr = Invoke-Cmd $tsExe @('funnel', 'status') 45 }
  $fso = (("$($fsr.out)" + ' | ' + "$($fsr.err)") -replace '\s+', ' ').Trim()
  $fRaw = $fRaw + ' || status exit=' + $fsr.code + ' msg=' + $fso
  if ($dns) {
    $ct = Invoke-Cmd $tsExe @('cert', ($dns.TrimEnd('.'))) 180
    $co = (("$($ct.out)" + ' | ' + "$($ct.err)") -replace '\s+', ' ').Trim()
    $fRaw = $fRaw + ' || cert exit=' + $ct.code + ' msg=' + $co
  }
  if ($f.code -eq 0) {
    $funnel = 'ok'
    if ($dns) { $funnelAddr = (($dns.TrimEnd('.')) + ':10000') }
    Log "  tailscale: FUNNEL OK -> $funnelAddr (bisa dipakai dari HP tanpa app Tailscale)"
  } else {
    $tail = (("$($f.err) $($f.out)") -replace '\s+', ' ').Trim()
    Log "  tailscale: funnel tidak aktif (exit=$($f.code)$(if ($tail) { ': ' + $tail.Substring(0, [Math]::Min(150, $tail.Length)) })) - jalur IP 100.x tetap jalan"
  }
  if ($fRaw.Length -gt 1200) { $fRaw = $fRaw.Substring(0, 1200) }
  Log ('  tailscale: diagnostik-funnel -> ' + $fRaw)
  return @{ exe = $tsExe; ip = $ip4; magicdns = $dns; host = $tsHost; funnel = $funnel; funnel_addr = $funnelAddr; raw = $fRaw }
}

$tunStatus = 'skip'; $tun = $null; $localOk = $false; $stOk = 'skip'; $reachOk = 'skip'; $reachTxt = ''
if ($useTunnel) {
  Log "TUNNEL TCP (RDP $localPort): menyiapkan..."
  # --- pilih target lokal RDP (IPv4 dulu, lalu IPv6) + catat semua listener ---
  try {
    $all = Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue |
           ForEach-Object { "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess)" }
    if ($all) { Log "  listener $localPort : $($all -join ' | ')" } else { Log "  listener $localPort : TIDAK ADA" }
  } catch {}
  $ownIp = Get-PrimaryIPv4

  # --- DIAGNOSTIK: pemilik listener 3389, TermService, firewall ---
  try {
    Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
      $pn = '?'; try { $pn = (Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName } catch {}
      Log "  diag: listener $($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess) ($pn)"
    }
    $svc = Get-Service TermService -ErrorAction SilentlyContinue
    if ($svc) { Log "  diag: TermService=$($svc.Status)" }
    $fp = Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name):enabled=$($_.Enabled)/inbound=$($_.DefaultInboundAction)" }
    if ($fp) { Log "  diag: firewall -> $($fp -join ' ')" }
    $fr = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name):$($_.Enabled)/$($_.Action)/$($_.Profile)" }
    if ($fr) { Log "  diag: aturan RDP -> $($fr -join ' | ')" } else { Log '  diag: tidak ada aturan grup Remote Desktop' }
  } catch { Log "  diag error: $($_.Exception.Message)" }

  # --- tunggu sampai RDP benar-benar menjawab handshake, lalu pilih alamatnya ---
  # (sekadar TCP terbuka tidak cukup: di runner nyata 172.31.240.1:3389 menerima
  #  TCP tapi tidak pernah membalas X.224 — tunnel jadi "hidup tapi tidak tembus")
  $rdpTarget = Wait-RdpReady -TimeoutSec 240
  if ($rdpTarget) {
    Log "  target lokal tunnel: $rdpTarget`:$localPort (handshake X.224 terbukti)"
  } else {
    $rdpTarget = if ($ownIp -and $ownIp -ne '0.0.0.0') { $ownIp } else { '127.0.0.1' }
    Log "  PERINGATAN: RDP belum menjawab handshake di alamat mana pun setelah 240s — tunnel tetap dicoba dengan $rdpTarget"
  }
  $script:RdpTarget = $rdpTarget

  # --- buat tunnel; kalau tidak tembus, cek ulang RDP lalu ulangi sekali lagi ---
  for ($att = 1; $att -le 2; $att++) {
    if ($prov -in @('pinggy', 'ssh')) { $tun = Start-Pinggy }
    elseif ($prov -eq 'ngrok') { $tun = Start-Ngrok }
    elseif ($prov -eq 'bore') { $tun = Start-Bore }
    else {
      # ngrok dulu bila token tersedia: satu koneksi keluar 443 + hostname
      # anycast (tidak butuh 'pairing' seperti bore / remote-forward SSH)
      if ($ngrokTok) { $tun = Start-Ngrok }
      if (-not $tun) { $tun = Start-Pinggy }
      if (-not $tun) { $tun = Start-Bore }
      if (-not $tun) { Log '  (tips: isi secret NGROK_AUTHTOKEN = jalur paling andal di runner GitHub)' }
    }
    if (-not $tun) { $tunStatus = 'gagal'; Log "  GAGAL membuat tunnel (percobaan $att)."; break }

    $tunStatus = 'ok'
    Log '  RDP lewat tunnel: buka Remote Desktop Connection ke alamat di atas'
    Log "  listener $localPort sekarang: $(Get-RdpListenerState $localPort)"

    # --- VERIFIKASI DARI LUAR (yang benar-benar dilihat klien HP) ---
    $reach = Get-OutsideReach $tun.host $tun.port 90
    $reachOk = if ($reach.ok -eq $true) { 'ok' } elseif ($reach.ok -eq $false) { 'gagal' } else { 'tidak diuji' }
    $reachTxt = $reach.detail
    if ($reach.ok) { Log "  UJI DARI LUAR OK - $reachTxt bisa menembus $($tun.host):$($tun.port)" }
    else { Log "  UJI DARI LUAR GAGAL - $reachTxt (alamat ini kemungkinan tidak bisa dipakai dari HP)" }

    # --- self-test end-to-end: handshake X.224 lewat endpoint publik ---
    $stOk = 'gagal'
    for ($try = 1; $try -le 4 -and $stOk -ne 'ok'; $try++) {
      $r = Test-RdpHandshake $tun.host $tun.port 15000
      if ($r.ok) {
        $stOk = 'ok'
        Log "  SELF-TEST OK (coba $try) — $($tun.host):$($tun.port) benar-benar tembus ke port $localPort VM [$($r.detail)]"
      } else {
        Log "  self-test (coba $try) gagal: $($r.detail)"
        if ($try -lt 4) { Start-Sleep -Seconds 8 }
      }
    }

    if ($stOk -eq 'ok' -and $reachOk -ne 'gagal') { break }

    # tunnel hidup tapi belum terbukti dari luar -> ganti provider lain
    if ($att -eq 1 -and $stOk -eq 'ok' -and $reachOk -eq 'gagal') {
      Log "  '$($tun.provider)' tembus dari dalam VM tapi TIDAK dari luar - ganti provider..."
      try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}
      $tun = $null
      if ($prov -in @('otomatis', 'auto', 'pinggy', 'ssh')) { $tun = Start-Pinggy }
      if (-not $tun -and $ngrokTok) { $tun = Start-Ngrok }
      if (-not $tun) { $tun = Start-Bore }
      if ($tun) {
        $stOk = 'gagal'
        for ($try2 = 1; $try2 -le 4 -and $stOk -ne 'ok'; $try2++) {
          $r2 = Test-RdpHandshake $tun.host $tun.port 15000
          if ($r2.ok) { $stOk = 'ok'; Log "  SELF-TEST OK - $($tun.host):$($tun.port) [$($r2.detail)]" }
          else { Start-Sleep -Seconds 8 }
        }
        $reach = Get-OutsideReach $tun.host $tun.port 90
        $reachOk = if ($reach.ok -eq $true) { 'ok' } elseif ($reach.ok -eq $false) { 'gagal' } else { 'tidak diuji' }
        $reachTxt = "$($reach.detail) [provider $($tun.provider)]"
        Log "  uji luar (provider baru $($tun.provider)): $reachTxt"
        if ($stOk -eq 'ok' -and $reachOk -ne 'gagal') { break }
      }
    }

    # RDP di VM belum sehat -> cek ulang, kalau berubah ulangi tunnel
    if ($att -eq 1) {
      Log '  tunnel belum tembus — cek ulang kesiapan RDP lalu ulangi tunnel dengan target terbaru'
      $t2 = Wait-RdpReady -TimeoutSec 150
      if ($t2) { $rdpTarget = $t2; $script:RdpTarget = $t2; Log "  target terbaru: $t2`:$localPort" }
      else { Log '  RDP masih belum menjawab handshake lokal' }
      try { Log "  log $($tun.provider) (4 baris terakhir): $((Get-Content $tun.log -Tail 4 -ErrorAction SilentlyContinue) -join ' / ')" } catch {}
      try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}
      $tun = $null
      Start-Sleep -Seconds 5
    }
  }

  if (-not $tun) {
    $tunStatus = 'gagal'
    Log '  GAGAL membuat tunnel. Sesi tetap jalan — pakai jalur RustDesk.'
  } else {
    $tgt2 = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
    $localOk = (Test-LocalPort $tgt2 $localPort 5000).ok
    Log "  RDP lokal $tgt2`:$localPort -> $(if ($localOk) { 'TERBUKA' } else { 'TERTUTUP (RDP mungkin belum jalan!)' })"
  }
}

# ============================================================================
#  BAGIAN 3 - TAILSCALE (opsional)
# ============================================================================
$tsStatus = 'skip'; $ts = $null
if ($useTs) {
  Log 'TAILSCALE: menyiapkan...'
  $ts = Start-Tailscale
  if ($ts) { $tsStatus = 'ok' } else { $tsStatus = 'gagal'; Log '  GAGAL menyiapkan Tailscale. Jalur lain (RustDesk/tunnel) tetap dipakai.' }
}

# ============================================================================
#  RANGKUMAN -> out/rdp-status.json
# ============================================================================
$aksesObj = [ordered]@{
  mode     = $mode
  rustdesk = [ordered]@{
    status  = $rdStatus
    service = $svcOk
    id      = $rdId
    server = $rdServer
    client = 'Unduh app RustDesk (gratis) -> masukkan ID + password'
  }
  tailscale = [ordered]@{
    status      = $tsStatus
    ip          = if ($ts) { $ts.ip } else { '' }
    magicdns    = if ($ts) { $ts.magicdns } else { '' }
    hostname    = if ($ts) { $ts.host } else { '' }
    funnel      = if ($ts) { $ts.funnel } else { '' }
    funnel_addr = if ($ts) { $ts.funnel_addr } else { '' }
    funnel_raw  = if ($ts -and $ts.raw) { $ts.raw } else { '' }
    note        = if ($ts) { "Di HP: pasang app Tailscale + login akun yang sama, lalu Host=$($ts.ip) Port=$localPort di XyDesk Remote (atau mstsc). Funnel: $(if ($ts.funnel_addr) { $ts.funnel_addr } else { 'tidak aktif' })" }
                  elseif ($useTs) { 'Tailscale gagal disiapkan (cek secret TAILSCALE_AUTH_KEY / log step Setup akses)' }
                  else { 'tidak dipakai di sesi ini' }
  }
  tunnel   = [ordered]@{
    status     = $tunStatus
    provider   = if ($tun) { $tun.provider } else { '' }
    host       = if ($tun) { $tun.host } else { '' }
    port       = if ($tun) { $tun.port } else { 0 }
    address    = if ($tun) { "$($tun.host):$($tun.port)" } else { '' }
    rdp_local  = if ($tun) { "$(if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }) -> $(if ($localOk) { 'terbuka' } else { 'tertutup' })" } else { '' }
    selftest   = if ($tun) { $stOk } else { '' }
    outside    = if ($tun) { "$reachOk ($reachTxt)" } else { '' }
    note2      = if ($tun -and $stOk -eq 'ok' -and $reachOk -eq 'ok') { 'Tunnel diuji dua arah: handshake RDP dari dalam VM DAN dari node luar — inilah yang dilihat HP kamu' }
                 elseif ($tun -and $reachOk -eq 'gagal') { 'Tunnel hidup di VM tetapi TERBUKTI tidak terbuka dari luar — pakai jalur RustDesk untuk sesi ini' }
                 elseif ($tun -and $stOk -eq 'ok') { 'Tunnel siap; uji dari luar tidak bisa dijalankan (batas layanan uji) — kalau HP gagal, pakai RustDesk' }
                 elseif ($tun) { 'Tunnel hidup, handshake RDP dari dalam belum lolos — coba lagi sebentar' }
                 else { '' }
    note       = 'Isi Host+Port ini di XyDesk Remote (Koneksi RDP) atau mstsc; user ' + $u
  }
}
Update-Status @{ akses = $aksesObj } | Out-Null
$aksesObj | ConvertTo-Json -Depth 8 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SELESAI — tailscale=$tsStatus$(if ($ts) { " ($($ts.ip))" }) rustdesk=$rdStatus$(if ($rdId) { " ($rdId)" }) tunnel=$tunStatus$(if ($tun) { " ($($tun.provider) $($tun.host):$($tun.port), selftest=$stOk, luar=$reachOk)" })"
exit 0
