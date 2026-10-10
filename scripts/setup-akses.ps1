# ============================================================================
#  setup-akses.ps1 — AKSES TUNNEL + TAILSCALE (v3 — tanpa RustDesk)
# ----------------------------------------------------------------------------
#  Jalur:
#   1) TUNNEL TCP ke port 3389 — buat XyDesk Remote / mstsc langsung host:port
#        - pinggy  : a.pinggy.io via SSH (tanpa akun, paling andal 2026-10-03 8/8)
#        - bore    : bore.pub (tanpa akun)
#        - localhost.run : nokey@localhost.run via SSH (tanpa akun)
#        - serveo  : serveo.net via SSH (tanpa akun)
#        - ngrok   : butuh NGROK_AUTHTOKEN (paling stabil bila ada token)
#      Urutan otomatis: ngrok (jika token) -> pinggy -> localhost.run -> serveo -> bore
#   2) TAILSCALE (opsional, bila TAILSCALE_AUTH_KEY ada)
#        - runner masuk tailnet 100.x, HP pakai Tailscale app
#
#  Hasil host:port ditulis ke out/rdp-status.json dan tampil di log.
# ============================================================================

$XyTag = 'XyRDP:akses'
. "$PSScriptRoot/lib-common.ps1"

$u        = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }
$pw       = $env:RDP_PASSWORD
$localPort = 3389
$work     = 'C:\XyRDP\akses'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$mode = if ($env:AKSES) { $env:AKSES.Trim().ToLower() } else { 'tunnel' }
if (@('tunnel','rdp','tailscale','ts','semua','all','both','dua','keduanya') -notcontains $mode) { $mode = 'tunnel' }
if (@('both','dua','keduanya') -contains $mode) { $mode = 'semua' }
if ($mode -eq 'ts') { $mode = 'tailscale' }
if ($mode -eq 'all') { $mode = 'semua' }
$useTunnel = ($mode -in @('tunnel','rdp','semua'))
$useTs     = ($mode -in @('tailscale','semua'))
$tsKey     = if ($env:TAILSCALE_AUTH_KEY) { $env:TAILSCALE_AUTH_KEY } else { $env:TS_AUTHKEY }
$tsKeyTxt  = if ($tsKey) { 'ada' } else { 'TIDAK ADA' }
Log "mode=$mode | tunnel=$useTunnel tailscale=$useTs (kunci $tsKeyTxt)"

$prov = if ($env:TUNNEL_PROVIDER) { $env:TUNNEL_PROVIDER.Trim().ToLower() } else { 'otomatis' }
if (@('otomatis','auto','bore','ngrok','pinggy','ssh','localhost.run','lhr','serveo') -notcontains $prov) { $prov = 'otomatis' }
$ngrokTok = if ($env:NGROK_AUTHTOKEN) { $env:NGROK_AUTHTOKEN } else { $env:NGROK_TOKEN }

Log "mode akses = $mode | provider tunnel = $prov | Tunnel=$useTunnel Tailscale=$useTs"

# ============================================================================
#  helper: jalankan perintah eksternal dengan TIMEOUT KERAS
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

# ============================================================================
#  TUNNEL TCP (RDP 3389) — multi-provider
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
  $tgtTxt = if ($tgt -like '*:*') { "[$tgt]" } else { $tgt }
  Log "  mulai: ngrok tcp $tgtTxt`:$localPort"
  $p = Start-Process -FilePath $ngrokExe -ArgumentList @('tcp', "$tgtTxt`:$localPort", '--log=stdout', '--log-format=json') `
        -RedirectStandardOutput $logF -RedirectStandardError (Join-Path $work 'ngrok.err') -PassThru -WindowStyle Hidden
  $m = Wait-Tunnel $logF 'tcp://([^\":\s]+):(\d+)' 90
  if (-not $m) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; Log '  ngrok: tidak dapat endpoint (timeout / token salah)'; return $null }
  Log "  TUNNEL : $($m.Groups[1].Value):$($m.Groups[2].Value) (ngrok)"
  return @{ provider = 'ngrok'; host = $m.Groups[1].Value; port = [int]$m.Groups[2].Value; pid = $p.Id; log = $logF }
}

function Get-SshCandidates {
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
  foreach ($hp in @(@('a.pinggy.io', 443), @('a.pinggy.io', 22))) {
    try {
      $ok = $false
      $tc = New-Object System.Net.Sockets.TcpClient
      $ok = $tc.ConnectAsync($hp[0], $hp[1]).Wait(7000); $tc.Close()
      Log "  pinggy: TCP $($hp[0]):$($hp[1]) -> $(if ($ok) { 'TERJANGKAU' } else { 'TIDAK terjangkau' })"
    } catch { Log "  pinggy: uji TCP $($hp[0]):$($hp[1]) error: $($_.Exception.Message)" }
  }
  if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
  $tgt = if ($script:RdpTarget -and $script:RdpTarget -ne '::1') { $script:RdpTarget } else { '127.0.0.1' }
  foreach ($ssh in $sshList) {
    $isMsys = ($ssh -match 'Git')
    $kh = if ($isMsys) { '/dev/null' } else { 'NUL' }
    foreach ($port in @(443, 22)) {
      foreach ($attempt in 1..2) {
        Remove-Item $logF, $errF -ErrorAction SilentlyContinue
        Log "  pinggy: klien=$([System.IO.Path]::GetFileName($ssh)) port=$port (coba $attempt, target $tgt`:$localPort)"
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

# localhost.run — SSH ke nokey@localhost.run tanpa akun (coba port 443 dulu)
function Start-LocalhostRun {
  $logF = Join-Path $work 'lhr.log'
  $errF = Join-Path $work 'lhr.err'
  $sshList = Get-SshCandidates
  if (-not $sshList) { Log '  localhost.run: ssh tidak ada'; return $null }
  if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
  $tgt = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
  foreach ($ssh in $sshList) {
    $isMsys = ($ssh -match 'Git')
    $kh = if ($isMsys) { '/dev/null' } else { 'NUL' }
    foreach ($port in @(443, 22)) {
      Remove-Item $logF, $errF -ErrorAction SilentlyContinue
      Log "  localhost.run: klien=$([System.IO.Path]::GetFileName($ssh)) port=$port target $tgt`:$localPort"
      $inF = Join-Path $work 'lhr.in'
      if (-not (Test-Path $inF)) { New-Item -ItemType File -Path $inF -Force | Out-Null }
      # localhost.run: ssh -R 80:localhost:3389 nokey@localhost.run
      $sshArgs = @('-p', "$port", '-T', '-o', 'StrictHostKeyChecking=no', '-o', "UserKnownHostsFile=$kh",
                   '-o', 'ServerAliveInterval=20', '-o', 'ConnectTimeout=15',
                   '-o', 'ExitOnForwardFailure=yes', "-R", "80:$tgt`:$localPort", 'nokey@localhost.run')
      $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -RedirectStandardOutput $logF `
            -RedirectStandardError $errF -RedirectStandardInput $inF -PassThru -WindowStyle Hidden
      $deadline = (Get-Date).AddSeconds(70)
      while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $txt = (@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join '') +
               (@(Get-Content $errF -Raw -ErrorAction SilentlyContinue) -join '')
        # localhost.run mengirim " * forwarded ... " atau URL https://xxx.lhrtunnel.link
        # Untuk TCP, dia memberi port: cari \.lhrtunnel\.link atau host:port
        if ($txt -match '([a-z0-9-]+\.lhrtunnel\.link):?(\d+)?' -or $txt -match 'tcp://([^\s]+):(\d+)' -or $txt -match 'Forwarding TCP.*:(\d+)') {
          # parse fallback: cari host:port generik
          if ($txt -match '([a-zA-Z0-9.-]+\.lhrtunnel\.link)[^\d]*:?\s*(\d+)') {
            $h = $Matches[1]; $pt = [int]$Matches[2]
            Log "  TUNNEL : $h`:$pt (localhost.run)"
            return @{ provider = 'localhost.run'; host = $h; port = $pt; pid = $p.Id; log = $logF }
          }
        }
        # alternatif: localhost.run mencetak "your url is https://xxx-xxx.lhrtunnel.link" plus tcp via same host
        if ($txt -match 'https://([a-z0-9-]+\.lhrtunnel\.link)') {
          $h = $Matches[1]
          # coba tebak port 443 untuk tcp? tapi lhr untuk tcp biasanya random port
          # tunggu baris forwarded
          Start-Sleep -Seconds 3
        }
        if ($p.HasExited) { break }
      }
      $out = ((@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join ' ') -replace '\s+', ' ').Trim()
      $err = ((@(Get-Content $errF -Raw -ErrorAction SilentlyContinue) -join ' ') -replace '\s+', ' ').Trim()
      Log "  localhost.run: gagal port $port - stdout:$($out.Substring(0,[Math]::Min(200,$out.Length))) err:$($err.Substring(0,[Math]::Min(200,$err.Length)))"
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
  Log '  localhost.run: gagal semua percobaan'
  return $null
}

# serveo.net — SSH -R 0:localhost:3389 serveo.net
function Start-Serveo {
  $logF = Join-Path $work 'serveo.log'
  $errF = Join-Path $work 'serveo.err'
  $sshList = Get-SshCandidates
  if (-not $sshList) { Log '  serveo: ssh tidak ada'; return $null }
  if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
  $tgt = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
  foreach ($ssh in $sshList) {
    $isMsys = ($ssh -match 'Git')
    $kh = if ($isMsys) { '/dev/null' } else { 'NUL' }
    Remove-Item $logF, $errF -ErrorAction SilentlyContinue
    Log "  serveo: klien=$([System.IO.Path]::GetFileName($ssh)) target $tgt`:$localPort"
    $inF = Join-Path $work 'serveo.in'
    if (-not (Test-Path $inF)) { New-Item -ItemType File -Path $inF -Force | Out-Null }
    $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', "UserKnownHostsFile=$kh",
                 '-o', 'ServerAliveInterval=20', '-o', 'ConnectTimeout=15',
                 '-o', 'ExitOnForwardFailure=yes', "-R", "0:$tgt`:$localPort", 'serveo.net')
    $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -RedirectStandardOutput $logF `
          -RedirectStandardError $errF -RedirectStandardInput $inF -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(70)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
      $txt = (@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join '') +
             (@(Get-Content $errF -Raw -ErrorAction SilentlyContinue) -join '')
      # serveo mencetak: Forwarding TCP connections from serveo.net:xxxx
      if ($txt -match 'Forwarding TCP.*from\s+([a-z0-9.-]+):(\d+)' -or $txt -match 'serveo\.net:(\d+)') {
        $h = 'serveo.net'; $pt = 0
        if ($txt -match 'from\s+([a-z0-9.-]+):(\d+)') { $h = $Matches[1]; $pt = [int]$Matches[2] }
        elseif ($txt -match 'serveo\.net:(\d+)') { $h = 'serveo.net'; $pt = [int]$Matches[1] }
        if ($pt -gt 0) {
          Log "  TUNNEL : $h`:$pt (serveo)"
          return @{ provider = 'serveo'; host = $h; port = $pt; pid = $p.Id; log = $logF }
        }
      }
      if ($p.HasExited) { break }
    }
    $out = ((@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join ' ') -replace '\s+', ' ').Trim()
    Log "  serveo: gagal - $out"
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
  Log '  serveo: gagal'
  return $null
}

# ---------------------------------------------------------------------------
#  TAILSCALE
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
  Log "  tailscale: IP=$ip4 magicdns=$dns state=$stTxt"
  $funnel = 'tidak aktif'; $funnelAddr = ''
  $f = @{ code = 1; out = ''; err = "dilewati (mode '$env:AKSES' bukan 'semua')" }
  if ("$env:AKSES" -eq 'semua') {
    $f = Invoke-Cmd $tsExe @('funnel', '--bg', '--tcp', '10000', 'tcp://127.0.0.1:3389') 60
    if ($f.code -ne 0) {
      $srv = Invoke-Cmd $tsExe @('serve', '--bg', '--tcp', '10000', 'tcp://127.0.0.1:3389') 60
      if ($srv.code -eq 0) { $f = Invoke-Cmd $tsExe @('funnel', '--bg', '--tcp', '10000') 60 }
    }
  }
  if ($f.code -eq 0) {
    $funnel = 'ok'
    if ($dns) { $funnelAddr = (($dns.TrimEnd('.')) + ':10000') }
    Log "  tailscale: FUNNEL OK -> $funnelAddr (hanya berguna untuk klien TLS - RDP mentah tidak bisa)"
  } else {
    $tail = (("$($f.err) $($f.out)") -replace '\s+', ' ').Trim()
    Log "  tailscale: funnel tidak aktif (exit=$($f.code)$(if ($tail) { ': ' + $tail.Substring(0, [Math]::Min(150, $tail.Length)) })) - jalur IP 100.x tetap jalan"
  }
  return @{ exe = $tsExe; ip = $ip4; magicdns = $dns; host = $tsHost; funnel = $funnel; funnel_addr = $funnelAddr }
}

$tunStatus = 'skip'; $tun = $null; $localOk = $false; $stOk = 'skip'; $reachOk = 'skip'; $reachTxt = ''
if ($useTunnel) {
  Log "TUNNEL TCP (RDP $localPort): menyiapkan..."
  try {
    $all = Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue |
           ForEach-Object { "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess)" }
    if ($all) { Log "  listener $localPort : $($all -join ' | ')" } else { Log "  listener $localPort : TIDAK ADA" }
  } catch {}
  $ownIp = Get-PrimaryIPv4
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

  $rdpTarget = Wait-RdpReady -TimeoutSec 240
  if ($rdpTarget) {
    Log "  target lokal tunnel: $rdpTarget`:$localPort (handshake X.224 terbukti)"
  } else {
    $rdpTarget = if ($ownIp -and $ownIp -ne '0.0.0.0') { $ownIp } else { '127.0.0.1' }
    Log "  PERINGATAN: RDP belum menjawab handshake di alamat mana pun setelah 240s — tunnel tetap dicoba dengan $rdpTarget"
  }
  $script:RdpTarget = $rdpTarget

  # daftar provider berurutan untuk otomatis (ngrok paling andal jika token ada)
  $autoOrder = @()
  if ($ngrokTok) { $autoOrder += 'ngrok' }
  $autoOrder += @('pinggy','bore')
  # localhost.run dan serveo ditambahkan sebagai fallback terakhir (kadang lambat)
  # tapi tetap dicoba biar ada opsi tanpa token

  function Try-OneProvider([string]$name) {
    switch ($name) {
      'ngrok'         { return (Start-Ngrok) }
      'pinggy'        { return (Start-Pinggy) }
      'bore'          { return (Start-Bore) }
      'localhost.run' { return (Start-LocalhostRun) }
      'lhr'           { return (Start-LocalhostRun) }
      'serveo'        { return (Start-Serveo) }
      default         { return $null }
    }
  }

  # kalau provider spesifik dipilih, hanya coba itu
  $providersToTry = @()
  if ($prov -ne 'otomatis' -and $prov -ne 'auto') {
    $providersToTry = @($prov)
  } else {
    $providersToTry = $autoOrder
  }

  $foundUsable = $false
  # loop luar: coba setiap provider sampai dapat yang outside ok atau selftest ok + tidak diuji
  foreach ($pName in $providersToTry) {
    Log "  mencoba provider: $pName ..."
    $tun = Try-OneProvider $pName
    if (-not $tun) { Log "  $pName gagal membuat endpoint — lanjut provider berikutnya"; continue }

    $tunStatus = 'ok'
    Log '  RDP lewat tunnel: buka XyDesk Remote / mstsc ke alamat di atas'
    Log "  listener $localPort sekarang: $(Get-RdpListenerState $localPort)"

    # self-test dulu (cepat, dari dalam VM)
    $stOk = 'gagal'
    for ($try = 1; $try -le 4 -and $stOk -ne 'ok'; $try++) {
      $r = Test-RdpHandshake $tun.host $tun.port 15000
      if ($r.ok) {
        $stOk = 'ok'
        Log "  SELF-TEST OK (coba $try) — $($tun.host):$($tun.port) tembus ke port $localPort VM [$($r.detail)]"
      } else {
        Log "  self-test (coba $try) gagal: $($r.detail)"
        if ($try -lt 4) { Start-Sleep -Seconds 8 }
      }
    }
    if ($stOk -ne 'ok') {
      Log "  $pName self-test gagal — matikan dan coba provider lain"
      try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}
      $tun = $null; $tunStatus = 'gagal'
      continue
    }

    # uji dari luar (penting untuk validasi beneran)
    $reach = Get-OutsideReach $tun.host $tun.port 90
    $reachOk = if ($reach.ok -eq $true) { 'ok' } elseif ($reach.ok -eq $false) { 'gagal' } else { 'tidak diuji' }
    $reachTxt = $reach.detail
    if ($reach.ok -eq $true) { Log "  UJI DARI LUAR OK - $reachTxt bisa menembus $($tun.host):$($tun.port)" }
    elseif ($reach.ok -eq $false) { Log "  UJI DARI LUAR GAGAL - $reachTxt (alamat ini kemungkinan tidak bisa dipakai dari HP)" }
    else { Log "  UJI DARI LUAR TIDAK DIUJI - $reachTxt (rate-limit check-host, anggap usable bila self-test ok)" }

    # keputusan:
    if ($reachOk -eq 'ok' -or $reachOk -eq 'tidak diuji') {
      Log "  PROVIDER $pName DITERIMA (selftest ok, luar $reachOk) — VALIDASI TUNNEL BERHASIL"
      $foundUsable = $true
      break
    } else {
      # luar gagal — coba provider berikutnya (jangan langsung buang, tapi prioritaskan yang tembus)
      Log "  $pName tembus self-test tapi GAGAL dari luar — coba provider lain..."
      try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}
      $tun = $null; $tunStatus = 'gagal'
      continue
    }
  }

  # fallback tambahan: jika otomatis dan semua gagal, coba urutan kedua (lhr + serveo) yang lebih lambat
  if (-not $foundUsable -and $prov -in @('otomatis','auto')) {
    $extraProviders = @('localhost.run','serveo')
    foreach ($pName in $extraProviders) {
      if ($providersToTry -contains $pName) { continue }
      Log "  fallback extra provider: $pName ..."
      $tun = Try-OneProvider $pName
      if (-not $tun) { continue }
      $tunStatus = 'ok'
      $stOk = 'gagal'
      for ($try = 1; $try -le 4 -and $stOk -ne 'ok'; $try++) {
        $r = Test-RdpHandshake $tun.host $tun.port 15000
        if ($r.ok) { $stOk = 'ok'; Log "  SELF-TEST OK — $($tun.host):$($tun.port) [$($r.detail)]" }
        else { Start-Sleep -Seconds 5 }
      }
      if ($stOk -ne 'ok') { try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}; $tun = $null; continue }
      $reach = Get-OutsideReach $tun.host $tun.port 90
      $reachOk = if ($reach.ok -eq $true) { 'ok' } elseif ($reach.ok -eq $false) { 'gagal' } else { 'tidak diuji' }
      $reachTxt = $reach.detail
      if ($reachOk -eq 'ok' -or $reachOk -eq 'tidak diuji') { $foundUsable = $true; break }
      else { try { Stop-Process -Id $tun.pid -Force -ErrorAction SilentlyContinue } catch {}; $tun = $null }
    }
  }

  if (-not $tun) {
    $tunStatus = 'gagal'
    Log '  GAGAL membuat tunnel yang VALID (semua provider gagal outside/selftest).'
    Log '  Tips: isi secret NGROK_AUTHTOKEN untuk jalur ngrok yang paling andal.'
  } else {
    $tgt2 = if ($script:RdpTarget) { $script:RdpTarget } else { '127.0.0.1' }
    $localOk = (Test-LocalPort $tgt2 $localPort 5000).ok
    Log "  RDP lokal $tgt2`:$localPort -> $(if ($localOk) { 'TERBUKA' } else { 'TERTUTUP' })"
    Log "  TUNNEL FINAL: $($tun.provider) $($tun.host):$($tun.port) selftest=$stOk luar=$reachOk — SIAP untuk XyDesk Remote"
  }
}

# ============================================================================
#  TAILSCALE (opsional)
# ============================================================================
$tsStatus = 'skip'; $ts = $null
if ($useTs) {
  Log 'TAILSCALE: menyiapkan...'
  $ts = Start-Tailscale
  if ($ts) { $tsStatus = 'ok' } else { $tsStatus = 'gagal'; Log '  GAGAL menyiapkan Tailscale.' }
}

# ============================================================================
#  RANGKUMAN -> out/rdp-status.json
# ============================================================================
$aksesObj = [ordered]@{
  mode     = $mode
  tailscale = [ordered]@{
    status      = $tsStatus
    ip          = if ($ts) { $ts.ip } else { '' }
    magicdns    = if ($ts) { $ts.magicdns } else { '' }
    hostname    = if ($ts) { $ts.host } else { '' }
    funnel      = if ($ts) { $ts.funnel } else { '' }
    funnel_addr = if ($ts) { $ts.funnel_addr } else { '' }
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
    note2      = if ($tun -and $stOk -eq 'ok' -and $reachOk -eq 'ok') { 'Tunnel VALID dua arah: handshake RDP dari dalam DAN luar — siap pakai XyDesk Remote' }
                 elseif ($tun -and $stOk -eq 'ok' -and $reachOk -eq 'tidak diuji') { 'Tunnel VALID (self-test ok, luar tidak diuji karena rate-limit — hampir pasti bisa dari HP)' }
                 elseif ($tun -and $reachOk -eq 'gagal') { 'Tunnel hidup di VM tetapi TERBUKTI tidak terbuka dari luar — coba provider lain atau pakai Tailscale' }
                 elseif ($tun -and $stOk -eq 'ok') { 'Tunnel siap; uji luar pending — coba dari HP' }
                 elseif ($tun) { 'Tunnel hidup, handshake belum lolos — coba lagi sebentar' }
                 else { '' }
    note       = 'Isi Host+Port ini di XyDesk Remote (Koneksi RDP) atau mstsc; user ' + $u
  }
}
Update-Status @{ akses = $aksesObj } | Out-Null
try {
  $osMemory = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
  $mem = [ordered]@{
    total_mb = [int][math]::Round($osMemory.TotalVisibleMemorySize / 1024)
    available_mb = [int][math]::Round($osMemory.FreePhysicalMemory / 1024)
    measured = 'akhir setup'
  }
  Update-Status @{ memory = $mem } | Out-Null
  Log "RAM akhir setup: $($mem.available_mb) MB tersedia dari $($mem.total_mb) MB (snapshot; bukan angka live)"
} catch { Log 'RAM snapshot tidak tersedia' }
$aksesObj | ConvertTo-Json -Depth 8 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SELESAI — tailscale=$tsStatus$(if ($ts) { " ($($ts.ip))" }) tunnel=$tunStatus$(if ($tun) { " ($($tun.provider) $($tun.host):$($tun.port), selftest=$stOk, luar=$reachOk)" }) — TANPA RustDesk"
exit 0
