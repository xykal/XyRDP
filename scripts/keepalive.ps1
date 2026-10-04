# ============================================================================
#  keepalive.ps1 — tahan job (dan VM-nya) tetap hidup selama DUR menit,
#  minus buffer supaya cleanup selesai sebelum batas keras 360 menit.
#
#  Tiap 5 menit menulis heartbeat ke log: status akses (RustDesk ID +
#  tunnel), jumlah sesi RDP aktif, sisa waktu. Tiap 30 menit status ikut
#  di-publish ulang ke branch `status` supaya dashboard tetap segar.
# ============================================================================

$XyTag = 'XyRDP:alive'
. "$PSScriptRoot/lib-common.ps1"

# jalankan exe dengan batas waktu keras (menggantung = musuh utama di runner)
function Invoke-Ts([string]$exe, [string[]]$args, [int]$sec = 60) {
  $res = @{ code = $null; out = '' }
  $o = Join-Path $env:TEMP ("ts-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
  try {
    $p = Start-Process -FilePath $exe -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $o -ErrorAction Stop
    try { $p | Wait-Process -Timeout $sec -ErrorAction Stop; $res.code = $p.ExitCode }
    catch { $res.code = -1; try { $p | Stop-Process -Force -ErrorAction SilentlyContinue } catch {} }
  } catch {}
  if (Test-Path $o) { $res.out = (Get-Content $o -Raw -ErrorAction SilentlyContinue) }
  return $res
}

$dur = [int]($env:DUR -replace '\D', ''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$buffer = if ($dur -ge 15) { 6 } else { 2 }
$stop = (Get-Date).AddMinutes($dur - $buffer)
Log "menahan sesi sampai $($stop.ToString('HH:mm:ss')) UTC ($dur menit total, buffer cleanup $buffer menit)"

$nextPublish = (Get-Date).AddMinutes(30)
# Pinggy gratis hanya berlaku 60 menit -> diperpanjang otomatis tiap ~50 menit
# (alamat baru! dashboard akan menampilkan alamat terbaru; klien perlu masuk
#  ulang dengan alamat itu, atau pakai RustDesk)
$pinggyRenew = (Get-Date).AddMinutes(50)
$pinggyPid = 0
$stAwal = Read-Status
if ($stAwal -and $stAwal.akses -and $stAwal.akses.tunnel -and $stAwal.akses.tunnel.provider -eq 'pinggy') {
  Log 'catatan: tunnel pinggy (gratis) berumur 60 menit dan akan diperpanjang otomatis'
}
while ((Get-Date) -lt $stop) {
  $left = ($stop - (Get-Date)).ToString('hh\:mm')

  # info akses dari status file (sudah diisi setup-akses.ps1)
  $rdId = '?'; $tun = '?'; $tsIp = ''; $tsFunnel = ''; $tsDnsPub = ''
  $st = Read-Status
  if ($st -and $st.akses) {
    if ($st.akses.rustdesk -and $st.akses.rustdesk.id) { $rdId = $st.akses.rustdesk.id }
    if ($st.akses.tunnel -and $st.akses.tunnel.address) { $tun = $st.akses.tunnel.address }
    if ($st.akses.tailscale -and $st.akses.tailscale.ip) { $tsIp = $st.akses.tailscale.ip }
  }
  # Tailscale: pastikan node masih online (kalau tidak, coba naikkan lagi)
  if ($tsIp) {
    $tsExe = $null
    foreach ($p in @("$env:ProgramFiles\Tailscale\tailscale.exe", "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
      if (Test-Path $p) { $tsExe = $p; break }
    }
    if ($tsExe) {
      $stt = (& $tsExe status --json 2>$null | ConvertFrom-Json)
      if ($stt -and $stt.BackendState -ne 'Running') {
        Log "tailscale: state=$($stt.BackendState) - percobaan naik ulang"
        try { & $tsExe up --timeout=60s 2>&1 | Out-Null } catch {}
      }
      # funnel: dipasang ulang tiap siklus (idempoten) supaya ingress tetap terbit,
      # lalu dicek dari node: apakah <node>.<tailnet>.ts.net sudah ada di DNS publik.
      try {
        $fx = Invoke-Ts $tsExe @('funnel', '--bg', '--tcp', '10000', 'tcp://127.0.0.1:3389') 60
        $tsFunnel = if ($fx.code -eq 0) { 'ok' } else { "gagal($($fx.code))" }
        $dnsName = "$($stt.Self.DNSName)".TrimEnd('.')
        if ($dnsName) {
          $cur = Get-Command curl.exe -ErrorAction SilentlyContinue
          $jx = Join-Path $env:TEMP 'xyrdp-dns.json'
          if ($cur) { & $cur.Source -sS -m 20 -o $jx "https://dns.google/resolve?name=$dnsName&type=A" 2>&1 | Out-Null }
          $ips = @()
          try {
            $dj = Get-Content $jx -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            $ips = @($dj.Answer | Where-Object { $_.type -eq 1 } | ForEach-Object { $_.data })
          } catch {}
          $tsDnsPub = if ($ips.Count -gt 0) { ($ips -join ',') } else { 'belum' }
          $stNow = Read-Status
          $oldPub = ''
          if ($stNow -and $stNow.akses -and $stNow.akses.tailscale) { $oldPub = "$($stNow.akses.tailscale.dns_publik)" }
          if ($stNow -and $stNow.akses -and $stNow.akses.tailscale) {
            $stNow.akses.tailscale.funnel = $tsFunnel
            $stNow.akses.tailscale.dns_publik = $tsDnsPub
            $stNow.akses.tailscale.dns_check_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            try { Update-Status @{ akses = $stNow.akses } | Out-Null } catch {}
            if ($tsDnsPub -ne 'belum' -and $oldPub -ne $tsDnsPub) {
              try { & "$PSScriptRoot/publish-status.ps1" -Active $true | Out-Null } catch {}
              Log "FUNNEL TERBIT di DNS publik: $dnsName -> $tsDnsPub"
            }
          }
        }
      } catch { Log "cek funnel gagal (tidak kritis): $($_.Exception.Message)" }
    }
  }

  # sesi RDP aktif
  $sess = 0
  try {
    $q = (quser 2>$null)
    if ($q) { $sess = @($q | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }).Count }
  } catch {}

  # klien RustDesk yang sedang terhubung (proses tambahan selain service)
  $rdProc = 0
  try { $rdProc = @(Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue).Count } catch {}

  # kesehatan tunnel: handshake X.224 langsung ke endpoint publik (10 detik)
  $tunHealth = ''
  if ($tun -and $tun -match '^(?<h>[^:]+):(?<p>\d+)$') {
    $hr = Test-RdpHandshake $Matches['h'] ([int]$Matches['p']) 10000
    $tunHealth = if ($hr.ok) { 'ok' } else { 'gagal' }
    # PENTING: Update-Status mengganti key level atas — jadi ambil objek akses
    # utuh dulu, ubah selftest-nya, baru tulis balik (jangan kirim potongan).
    $stNow = Read-Status
    if ($stNow -and $stNow.akses -and $stNow.akses.tunnel) {
      if ("$($stNow.akses.tunnel.selftest)" -ne $tunHealth) {
        $stNow.akses.tunnel | Add-Member -NotePropertyName 'selftest' -NotePropertyValue $tunHealth -Force
        try { Update-Status @{ akses = $stNow.akses } | Out-Null } catch {}
      }
    }
  }

  Log "hidup • Tailscale=$tsIp • funnel=$(if ($tsFunnel) { $tsFunnel } else { '?' }) dns=$(if ($tsDnsPub) { $tsDnsPub } else { '?' }) • RustDesk=$rdId • tunnel=$tun$(if ($tunHealth) { " ($tunHealth)" }) • sesi RDP=$sess • proses RD=$rdProc • sisa=$left"

  # perpanjang tunnel pinggy sebelum kedaluwarsa (60 menit)
  if ((Get-Date) -ge $pinggyRenew) {
    $stP = Read-Status
    if ($stP -and $stP.akses -and $stP.akses.tunnel -and $stP.akses.tunnel.provider -eq 'pinggy') {
      Log 'pinggy mendekati kedaluwarsa (60 menit) - menghidupkan tunnel baru...'
      try {
        Get-Process ssh -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.StartTime -lt (Get-Date).AddMinutes(-45) } | Stop-Process -Force -ErrorAction SilentlyContinue
        $ssh = (Get-Command ssh -ErrorAction SilentlyContinue).Source
        $logF = 'C:\XyRDP\akses\pinggy.log'
        Remove-Item $logF -ErrorAction SilentlyContinue
        $tgt = if ($stP.akses.tunnel.rdp_local -match '^([0-9.]+)') { $Matches[1] } else { '127.0.0.1' }
        Start-Process -FilePath $ssh -ArgumentList @('-p','443','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL','-o','ServerAliveInterval=20',"-R0:$tgt`:3389",'tcp@a.pinggy.io') -RedirectStandardOutput $logF -RedirectStandardError 'C:\XyRDP\akses\pinggy.err' -PassThru -WindowStyle Hidden | Out-Null
        $novo = $null
        for ($k = 1; $k -le 20 -and -not $novo; $k++) {
          Start-Sleep -Seconds 3
          $txt = (@(Get-Content $logF -Raw -ErrorAction SilentlyContinue) -join '') + (@(Get-Content 'C:\XyRDP\akses\pinggy.err' -Raw -ErrorAction SilentlyContinue) -join '')
          if ($txt -match 'tcp://([a-zA-Z0-9.-]+):(\d+)') { $novo = @{ h = $Matches[1]; p = [int]$Matches[2] } }
        }
        if ($novo) {
          $stP.akses.tunnel.host = $novo.h
          $stP.akses.tunnel.port = $novo.p
          $stP.akses.tunnel.address = "$($novo.h):$($novo.p)"
          Update-Status @{ akses = $stP.akses } | Out-Null
          & "$PSScriptRoot/publish-status.ps1" -Active $true | Out-Null
          Log "pinggy diperpanjang -> alamat BARU $($novo.h):$($novo.p) (masuk ulang dengan alamat ini)"
        } else { Log 'perpanjangan pinggy gagal - jalur RustDesk tetap jalan' }
      } catch { Log "perpanjangan pinggy error: $($_.Exception.Message)" }
    }
    $pinggyRenew = (Get-Date).AddMinutes(50)
  }

  # publish ulang status tiap 30 menit (heartbeat untuk dashboard)
  if ((Get-Date) -ge $nextPublish) {
    try {
      Update-Status @{ heartbeat_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | Out-Null
      & "$PSScriptRoot/publish-status.ps1" -Active $true | Out-Null
      Log 'heartbeat: status di-publish ulang'
    } catch { Log "publish heartbeat gagal (tidak kritis): $($_.Exception.Message)" }
    $nextPublish = (Get-Date).AddMinutes(30)
# Pinggy gratis hanya berlaku 60 menit -> diperpanjang otomatis tiap ~50 menit
# (alamat baru! dashboard akan menampilkan alamat terbaru; klien perlu masuk
#  ulang dengan alamat itu, atau pakai RustDesk)
$pinggyRenew = (Get-Date).AddMinutes(50)
$pinggyPid = 0
$stAwal = Read-Status
if ($stAwal -and $stAwal.akses -and $stAwal.akses.tunnel -and $stAwal.akses.tunnel.provider -eq 'pinggy') {
  Log 'catatan: tunnel pinggy (gratis) berumur 60 menit dan akan diperpanjang otomatis'
}
  }

  Start-Sleep -Seconds 300
}
Log 'durasi inti habis — lanjut ke cleanup. Sesi akan mati bersama job.'
exit 0
