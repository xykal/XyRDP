# ============================================================================
#  keepalive.ps1 — tahan job (dan VM-nya) tetap hidup selama DUR menit,
#  minus buffer supaya cleanup selesai sebelum batas keras 360 menit.
#
#  Tiap 5 menit menulis heartbeat ke log: status akses (Tailscale + tunnel),
#  jumlah sesi RDP aktif, sisa waktu. Tiap 30 menit status ikut
#  di-publish ulang ke branch `status` supaya dashboard tetap segar.
# ============================================================================

$XyTag = 'XyRDP:alive'
. "$PSScriptRoot/lib-common.ps1"

$dur = [int]($env:DUR -replace '\D', ''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$buffer = if ($dur -ge 15) { 6 } else { 2 }
$stop = (Get-Date).AddMinutes($dur - $buffer)
Log "menahan sesi sampai $($stop.ToString('HH:mm:ss')) UTC ($dur menit total, buffer cleanup $buffer menit)"

$nextPublish = (Get-Date).AddMinutes(30)
# Pinggy gratis hanya berlaku 60 menit -> diperpanjang otomatis tiap ~50 menit
$pinggyRenew = (Get-Date).AddMinutes(50)
$stAwal = Read-Status
if ($stAwal -and $stAwal.akses -and $stAwal.akses.tunnel -and $stAwal.akses.tunnel.provider -eq 'pinggy') {
  Log 'catatan: tunnel pinggy (gratis) berumur 60 menit dan akan diperpanjang otomatis'
}
while ((Get-Date) -lt $stop) {
  $left = ($stop - (Get-Date)).ToString('hh\:mm')

  # info akses dari status file
  $tun = '?'; $tsIp = ''
  $st = Read-Status
  if ($st -and $st.akses) {
    if ($st.akses.tunnel -and $st.akses.tunnel.address) { $tun = $st.akses.tunnel.address }
    if ($st.akses.tailscale -and $st.akses.tailscale.ip) { $tsIp = $st.akses.tailscale.ip }
  }
  # Tailscale: pastikan node masih online
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
    }
  }

  # sesi RDP aktif
  $sess = 0
  try {
    $q = (quser 2>$null)
    if ($q) { $sess = @($q | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }).Count }
  } catch {}

  # kesehatan tunnel: handshake X.224 langsung ke endpoint publik (10 detik)
  $tunHealth = ''
  if ($tun -and $tun -match '^(?<h>[^:]+):(?<p>\d+)$') {
    $hr = Test-RdpHandshake $Matches['h'] ([int]$Matches['p']) 10000
    $tunHealth = if ($hr.ok) { 'ok' } else { 'gagal' }
    $stNow = Read-Status
    if ($stNow -and $stNow.akses -and $stNow.akses.tunnel) {
      if ("$($stNow.akses.tunnel.selftest)" -ne $tunHealth) {
        $stNow.akses.tunnel | Add-Member -NotePropertyName 'selftest' -NotePropertyValue $tunHealth -Force
        try { Update-Status @{ akses = $stNow.akses } | Out-Null } catch {}
      }
    }
  }

  Log "hidup • Tailscale=$tsIp • tunnel=$tun$(if ($tunHealth) { " ($tunHealth)" }) • sesi RDP=$sess • sisa=$left"

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
        } else { Log 'perpanjangan pinggy gagal - tunnel tetap coba provider lain' }
      } catch { Log "perpanjangan pinggy error: $($_.Exception.Message)" }
    }
    $pinggyRenew = (Get-Date).AddMinutes(50)
  }

  # publish ulang status tiap 30 menit
  if ((Get-Date) -ge $nextPublish) {
    try {
      Update-Status @{ heartbeat_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | Out-Null
      & "$PSScriptRoot/publish-status.ps1" -Active $true | Out-Null
      Log 'heartbeat: status di-publish ulang'
    } catch { Log "publish heartbeat gagal (tidak kritis): $($_.Exception.Message)" }
    $nextPublish = (Get-Date).AddMinutes(30)
  }

  Start-Sleep -Seconds 300
}
Log 'durasi inti habis — lanjut ke cleanup. Sesi akan mati bersama job.'
exit 0
