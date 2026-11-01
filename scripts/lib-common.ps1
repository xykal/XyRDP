# ============================================================================
#  lib-common.ps1 - helper bersama untuk semua script XyRDP (v2: Win10-style,
#  akses privat Tailscale). Dipakai dengan cara di-dot-source:
#
#      $XyTag = 'XyRDP:akses'
#      . "$PSScriptRoot/lib-common.ps1"
#
#  Berisi: logger, registry helper, pembaca konfigurasi (assets/rdp-extras.json),
#  pengelola hive profil Default, pembaca/penulis out/rdp-status.json.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# ---------- log ----------
function Log([string]$m) {
  $tag = if ($script:XyTag) { $script:XyTag } else { 'XyRDP' }
  Write-Host ("[{0:HH:mm:ss} UTC][{1}] {2}" -f [DateTime]::UtcNow,$tag,$m)
}

function Log-Tail([string]$text, [int]$lines = 2) {
  (($text -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last $lines) -join ' / '
}

# ---------- registry ----------
# Pelajaran dari validasi nyata (2026-10-03) di runner windows-2022:
#   - 'New-ItemProperty -Force' di value yang SUDAH ADA bisa ditolak
#     "Attempted to perform an unauthorized operation" (butuh hak Create/Delete
#     yang tidak dimiliki Administrators pada sebagian kunci, mis.
#     Terminal Server\fDenyTSConnections, Winlogon\DisableCAD,
#     CurrentVersion\ProductName).
#   - 'Set-ItemProperty' pada value yang sudah ada hanya butuh "Set Value"
#     -> BERHASIL (itu sebabnya script lama jalan).
# Set-Reg sekarang: exists? -> Set-ItemProperty; kalau perlu -> New-ItemProperty
# -> reg.exe add /f -> ambil kepemilikan kunci lalu ulangi.

function To-RegExePath([string]$Path) {
  $p = ($Path -replace '^Registry::', '') -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' -replace '^HKU:\\', 'HKEY_USERS\' -replace '^HKCR:\\', 'HKEY_CLASSES_ROOT\' -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\' -replace '^HKU\\', 'HKEY_USERS\' -replace '^HKCR\\', 'HKEY_CLASSES_ROOT\'
  $map = @{ 'HKEY_LOCAL_MACHINE' = 'HKLM'; 'HKEY_CURRENT_USER' = 'HKCU'; 'HKEY_USERS' = 'HKU'; 'HKEY_CLASSES_ROOT' = 'HKCR'; 'HKEY_CURRENT_CONFIG' = 'HKCC' }
  foreach ($k in $map.Keys) { if ($p.StartsWith($k + '\')) { return ($map[$k] + $p.Substring($k.Length)) } }
  return $null
}

function Normalize-PsRegPath([string]$Path) {
  if ($Path -match '^HKLM\\') { return ('HKLM:\' + $Path.Substring(5)) }
  if ($Path -match '^HKCU\\') { return ('HKCU:\' + $Path.Substring(5)) }
  if ($Path -match '^HKU\\')  { return ('Registry::HKEY_USERS\' + $Path.Substring(4)) }
  if ($Path -match '^HKCR\\') { return ('Registry::HKEY_CLASSES_ROOT\' + $Path.Substring(5)) }
  if ($Path -match '^Registry::HKEY_LOCAL_MACHINE\\') { return ('HKLM:\' + $Path.Substring('Registry::HKEY_LOCAL_MACHINE\'.Length)) }
  if ($Path -match '^Registry::HKEY_CURRENT_USER\\')  { return ('HKCU:\' + $Path.Substring('Registry::HKEY_CURRENT_USER\'.Length)) }
  return $Path
}

function Grant-KeyAccess([string]$Path) {
  # ambil kepemilikan + FullControl untuk user sekarang (dipakai hanya kalau
  # penulisan ditolak; mis. CurrentVersion milik TrustedInstaller).
  # JANGAN PERNAH ubah ACL/owner WinStations\RDP-Tcp karena akan memutus akses TermService (NetworkService) ke listener 3389!
  try {
    if ($Path -match 'WinStations|RDP-Tcp') {
      return $false
    }
    $ident = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $rk = To-RegExePath $Path
    if (-not $rk) { return $false }
    if ($rk.StartsWith('HKLM\')) {
      $hive = [Microsoft.Win32.Registry]::LocalMachine; $sub = $rk.Substring(5)
    } elseif ($rk.StartsWith('HKCU\')) {
      $hive = [Microsoft.Win32.Registry]::CurrentUser; $sub = $rk.Substring(5)
    } else { return $false }

    $key = $hive.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if (-not $key) { return $false }
    $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
    $acl.SetOwner($ident.User); $key.SetAccessControl($acl)
    $acl = $key.GetAccessControl()
    $acl.SetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($ident.Name, 'FullControl', 'Allow')))
    $key.SetAccessControl($acl); $key.Close()
    Log "  reg: kepemilikan kunci diambil ($sub)"
    return $true
  } catch { Log "  reg: ambil kepemilikan gagal: $($_.Exception.Message)"; return $false }
}

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'String') {
  $psPath = Normalize-PsRegPath $Path
  # 1) value sudah ada -> Set-ItemProperty (hak paling minimal)
  $exists = $false
  try { $null = Get-ItemProperty -Path $psPath -Name $Name -ErrorAction Stop; $exists = $true } catch {}
  if ($exists) {
    try { Set-ItemProperty -Path $psPath -Name $Name -Value $Value -ErrorAction Stop; return $true }
    catch { Log "  reg: Set-ItemProperty gagal ($Name): $($_.Exception.Message)" }
  }
  # 2) reg.exe add langsung (tidak merusak key ACL & membuat key/value secara native Win32)
  $rk = To-RegExePath $Path
  if ($rk) {
    $t = switch ("$Type") { 'DWord' { 'REG_DWORD' } 'QWord' { 'REG_QWORD' } 'ExpandString' { 'REG_EXPAND_SZ' } 'MultiString' { 'REG_MULTI_SZ' } default { 'REG_SZ' } }
    $out = & reg add $rk /v $Name /t $t /d $Value /f 2>&1
    if ($LASTEXITCODE -eq 0) { return $true }
    Log "  reg: reg.exe add gagal ($Name): $(Log-Tail "$out" 1)"
  }
  # 3) bikin/set lewat provider PowerShell
  try {
    if (-not (Test-Path $psPath)) { New-Item -Path $psPath -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $psPath -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    return $true
  } catch { Log "  reg: New-ItemProperty gagal ($Name): $($_.Exception.Message)" }
  # 4) ambil kepemilikan kunci, lalu ulangi (kecuali WinStations\RDP-Tcp)
  if (Grant-KeyAccess $Path) {
    try {
      New-ItemProperty -Path $psPath -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
      return $true
    } catch { Log "  reg: masih gagal setelah ambil kepemilikan ($Name): $($_.Exception.Message)" }
  }
  Log "  reg GAGAL total ($Path\$Name)"
  return $false
}

function Get-Reg([string]$Path, [string]$Name) {
  $psPath = Normalize-PsRegPath $Path
  try { return (Get-ItemProperty -Path $psPath -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

# ---------- konfigurasi (assets/rdp-extras.json) ----------
$script:XyCfgDefaults = [ordered]@{
  lightshot        = $false           # jangan jalankan app latar jika tidak diminta
  wallpaper        = $true
  wallpaper_file   = 'wallpaper.jpg'
  win10_look       = $true            # semua tweak tampilan Windows 10
  win10_badge      = $true            # label "Windows 10 Pro" di registry (kosmetik)
  win10_wallpaper  = $true            # pakai wallpaper gaya Windows 10
  xydesk_host      = $true            # host setup untuk klien XyDesk Remote (AVC444/ClearType/audio)
  dark_theme       = $true            # tema aplikasi dan sistem gelap
  lightweight_mode = $true            # matikan hanya layanan latar non-esensial
  vscode           = $false           # IDE tambahan opsional
  notepadpp        = $false           # editor ringan opsional
  rdp_user         = 'xyadmin'        # username RDP default tersimpan per-repo
  storage_boost    = $true            # bersihkan toolcache biar free 70GB -> 120GB+
  debloat          = 'ringan'         # tidak / ringan / full (Edge)
  samp             = $false           # pasang GTA SAMP (butuh GTA_SA_URL atau upload manual)
  samp_extra       = $false           # silentpatch + widescreen fix
}

function Get-CfgBool([object]$o, [string]$n, [bool]$d) {
  if (-not $o) { return $d }
  $p = $o.PSObject.Properties[$n]
  if ($p -and $null -ne $p.Value) { return [bool]$p.Value }
  return $d
}
function Get-CfgStr([object]$o, [string]$n, [string]$d) {
  if (-not $o) { return $d }
  $p = $o.PSObject.Properties[$n]
  if ($p -and $null -ne $p.Value -and "$($p.Value)".Trim()) { return "$($p.Value)".Trim() }
  return $d
}

# Get-Cfg -> pscustomobject berisi semua setting (default + isi repo)
function Get-Cfg {
  $j = $null
  $path = Join-Path (Get-Workspace) 'assets\rdp-extras.json'
  if (Test-Path $path) {
    try { $j = Get-Content $path -Raw | ConvertFrom-Json; Log 'konfigurasi: assets/rdp-extras.json' }
    catch { Log "rdp-extras.json tidak terbaca ($($_.Exception.Message)) - pakai default" }
  } else { Log 'assets/rdp-extras.json tidak ada - pakai default' }

  $c = [pscustomobject]@{}
  foreach ($k in $script:XyCfgDefaults.Keys) {
    $c | Add-Member -NotePropertyName $k -NotePropertyValue $script:XyCfgDefaults[$k] -Force
  }
  if ($j) {
    foreach ($k in @('lightshot','wallpaper','win10_look','win10_badge','win10_wallpaper','xydesk_host','dark_theme','lightweight_mode','vscode','notepadpp','storage_boost','samp','samp_extra')) {
      $c.$k = Get-CfgBool $j $k $c.$k
    }
        $c.debloat          = (Get-CfgStr $j 'debloat' $c.debloat).ToLower()
    $c.wallpaper_file   = (Get-CfgStr $j 'wallpaper_file'   $c.wallpaper_file).ToLower()
    $c.rdp_user         = Get-CfgStr $j 'rdp_user' $c.rdp_user
  }
    return $c
}

# ---------- lokasi repo (Actions: GITHUB_WORKSPACE, lokal: folder script/..) ----------
function Get-Workspace {
  if ($env:GITHUB_WORKSPACE) { return $env:GITHUB_WORKSPACE }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

# ---------- status file (out/rdp-status.json) ----------
function Get-StatusPath {
  return (Join-Path (Get-Workspace) 'out\rdp-status.json')
}

function Read-Status {
  $p = Get-StatusPath
  if (-not (Test-Path $p)) { Log "status: $p belum ada"; return $null }
  try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch { Log "status tidak terbaca: $($_.Exception.Message)"; return $null }
}

# Update-Status @{ key = value } - merge + tulis balik (tanpa password)
function Update-Status([hashtable]$Pairs) {
  $p = Get-StatusPath
  $obj = Read-Status
  if (-not $obj) { $obj = [pscustomobject]@{} }
  foreach ($k in $Pairs.Keys) {
    $obj | Add-Member -NotePropertyName $k -NotePropertyValue $Pairs[$k] -Force
  }
  try {
    New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
    ($obj | ConvertTo-Json -Depth 8) | Set-Content -Path $p -Encoding utf8
    return $true
  } catch { Log "tulis status gagal: $($_.Exception.Message)"; return $false }
}

# ---------- hive profil Default (setting ikut user RDP saat login pertama) ----------
$script:DefHiveKey = 'XyRDP_Def'
$script:DefHive    = 'HKU\XyRDP_Def'
$script:DefReg     = 'Registry::HKEY_USERS\XyRDP_Def'
$script:HiveLoaded = $false

function Open-DefaultHive {
  if ($script:HiveLoaded) { return $true }
  try {
    & reg load $script:DefHive 'C:\Users\Default\NTUSER.DAT' 2>&1 | Out-Null
    Start-Sleep -Milliseconds 600
    if (Test-Path $script:DefReg) { $script:HiveLoaded = $true; Log 'profil Default di-load (setting ikut user RDP saat login pertama)'; return $true }
  } catch { Log "load profil Default gagal: $($_.Exception.Message)" }
  $script:HiveLoaded = $false
  return $false
}

function Close-DefaultHive {
  if (-not $script:HiveLoaded) { return }
  try {
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    & reg unload $script:DefHive 2>&1 | Out-Null
    $script:HiveLoaded = $false
    Log 'profil Default di-unload'
  } catch { Log "unload hive (tidak kritis): $($_.Exception.Message)" }
}

# Set-RegDefault: tulis ke profil Default DAN ke HKCU sesi sekarang
function Set-RegBoth([string]$SubKey, [string]$Name, $Value, [string]$Type = 'DWord') {
  Open-DefaultHive | Out-Null
  if ($script:HiveLoaded) { Set-Reg ($script:DefReg + '\' + $SubKey) $Name $Value $Type | Out-Null }
  Set-Reg ('Registry::HKEY_CURRENT_USER\' + $SubKey) $Name $Value $Type | Out-Null
}

# ---------- util gambar ----------
function Get-ImageExt([byte[]]$b) {
  if ($b.Length -ge 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'jpg' }
  if ($b.Length -ge 8 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
  if ($b.Length -ge 2 -and $b[0] -eq 0x42 -and $b[1] -eq 0x4D) { return 'bmp' }
  return $null
}

# ---------- jaringan ----------
function Get-PrimaryIPv4 {
  try {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
          Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
          Sort-Object -Property SkipAsSource | Select-Object -First 1
    if ($ip) { return $ip.IPAddress }
  } catch {}
  return '0.0.0.0'
}

# ---------------------------------------------------------------------------
#  Kesiapan RDP (pelajaran validasi 2026-10-03 di runner nyata):
#   - "port 3389 LISTENING" TIDAK cukup: listener sempat hilang ~2 menit
#     setelah tweak XyDesk, dan koneksi ke 127.0.0.1 bisa ditolak sementara
#     IP utama VM menerima. Jadi kita tunggu sampai RDP benar-benar menjawab
#     handshake X.224 sebelum tunnel diarahkan ke sana.
# ---------------------------------------------------------------------------

# semua alamat IPv4 non-loopback (kandidat alamat RDP lokal)
function Get-LocalIPv4List {
  $out = @()
  try {
    $out = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
             Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
             Sort-Object -Property @{ Expression = { [int]$_.SkipAsSource } }, InterfaceIndex |
             Select-Object -ExpandProperty IPAddress -Unique)
  } catch {}
  if (-not $out) { $out = @(Get-PrimaryIPv4) }
  return $out
}

# ringkas keadaan listener 3389 (alamat + nama proses) untuk log
function Get-RdpListenerState([int]$Port = 3389) {
  try {
    $l = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if (-not $l) { return 'TIDAK ADA listener' }
    $items = foreach ($x in $l) {
      $pn = '?'; try { $pn = (Get-Process -Id $x.OwningProcess -ErrorAction Stop).ProcessName } catch {}
      "$($x.LocalAddress):$($x.LocalPort) ($pn)"
    }
    return ($items -join ' | ')
  } catch { return "error: $($_.Exception.Message)" }
}

# handshake RDP X.224 ke alamat:port -> @{ ok = bool; detail = teks }
# (Connection Confirm = RDP benar-benar menerima koneksi, bukan cuma TCP terbuka)
function Test-RdpHandshake([string]$Address, [int]$Port = 3389, [int]$TimeoutMs = 8000) {
  $cr = [byte[]](0x03,0x00,0x00,0x13, 0x0e,0xe0,0x00,0x00,0x00,0x00,0x00,
                 0x01,0x00,0x08,0x00,0x03,0x00,0x00,0x00)
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    if (-not $c.ConnectAsync($Address, $Port).Wait($TimeoutMs)) { $c.Close(); return @{ ok = $false; detail = 'timeout connect' } }
    $ns = $c.GetStream()
    $ns.Write($cr, 0, $cr.Length); $ns.Flush()
    $c.ReceiveTimeout = $TimeoutMs
    $buf = New-Object byte[] 64
    $n = $ns.Read($buf, 0, $buf.Length)
    $c.Close()
    if ($n -ge 6 -and $buf[0] -eq 0x03 -and $buf[1] -eq 0x00 -and $buf[5] -in @(0xd0, 0xcf)) {
      $hex = (($buf[0..([Math]::Min($n, 10) - 1)] | ForEach-Object { $_.ToString('x2') }) -join ' ')
      return @{ ok = $true; detail = "X.224 Connection Confirm [$hex]" }
    }
    if ($n -gt 0) {
      $hex = (($buf[0..($n - 1)] | ForEach-Object { $_.ToString('x2') }) -join ' ')
      return @{ ok = $false; detail = "balasan $n byte non-confirm [$hex]" }
    }
    return @{ ok = $false; detail = 'koneksi ditutup tanpa data' }
  } catch { return @{ ok = $false; detail = $_.Exception.Message } }
}

# tunggu sampai ADA alamat lokal yang menjawab handshake RDP; kembalikan alamat
# itu (atau $null). Kalau lama tidak ada, TermService di-restart sekali.
function Wait-RdpReady([int]$TimeoutSec = 240, [int]$Port = 3389) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $lastState = ''
  while ((Get-Date) -lt $deadline) {
    $cands = @('127.0.0.1', '::1') + @(Get-LocalIPv4List) | Select-Object -Unique
    foreach ($c in $cands) {
      $r = Test-RdpHandshake $c $Port
      if ($r.ok) { Log "  RDP SIAP di $c`:$Port - $($r.detail)"; return $c }
    }
    $st = Get-RdpListenerState $Port
    if ($st -ne $lastState) { Log "  listener $Port : $st"; $lastState = $st }
    # CATATAN: restart TermService SENGAJA tidak dilakukan lagi - pada runner
    # GitHub, restart tidak menghidupkan kembali listener 3389 (terbukti di
    # validasi 2026-10-03: menunggu 240s + 150s tetap mati). Kita cukup menunggu
    # dan melaporkan apa adanya; penyebabnya sudah dihindari di setup-xydesk.
    Start-Sleep -Seconds 8
  }
  Log "  RDP belum menjawab handshake setelah ${TimeoutSec}s"
  return $null
}

# probe satu baris: dipakai untuk melacak step mana yang merusak RDP
function Probe-Rdp([string]$Where, [string]$Address = '127.0.0.1') {
  $state = Get-RdpListenerState 3389
  $r = Test-RdpHandshake $Address 3389 5000
  $txt = if ($r.ok) { 'handshake ok' } else { "handshake GAGAL ($($r.detail))" }
  Log "  [probe] $Where -> $txt | listener: $state"
  return $r.ok
}

# ---------------------------------------------------------------------------
#  Spot-check HTTPS dari ALAMAT LAIN (bukan dari VM)
#  Kenapa penting: pada 3 Okt 2026 terbukti tunnel bisa "selftest ok" dari dalam
#  VM (bore.pub:51782 menjawab X.224 dari dalam), TAPI dari internet port itu
#  ditolak (6/8 node luar "connection refused"). Jadi "selftest ok" saja TIDAK
#  cukup - alamat yang dipamerkan ke pengguna harus diuji dari luar.
#  Layanan: check-host.net (tanpa akun, mendukung TCP).
# ---------------------------------------------------------------------------
function Get-OutsideReach([string]$HostName, [int]$Port, [int]$TimeoutSec = 90) {
  $res = @{ ok = $false; detail = 'tidak diuji'; nodesOk = 0; nodesAll = 0 }
  try {
    $u = "https://check-host.net/check-tcp?host=$([uri]::EscapeDataString("$HostName`:$Port"))&max_nodes=6"
    $req = $null
    foreach ($coba in 1..3) {
      try {
        $req = Invoke-RestMethod -Uri $u -Headers @{ 'Accept' = 'application/json'; 'User-Agent' = 'XyRDP' } -TimeoutSec 30
        if ($req.request_id) { break }
      } catch {
        # 403 = check-host membatasi laju (bukan bukti tunnel mati!) -> jangan
        # dipakai untuk memutuskan ganti provider, cukup 'tidak diuji'.
        $res.ok = $null; $res.detail = "tidak bisa diuji dari luar: $($_.Exception.Message)"
        Log "  (uji luar: $($res.detail))"
        Start-Sleep -Seconds 8
      }
    }
    if (-not $req -or -not $req.request_id) {
      if (-not $res.detail) { $res.detail = 'check-host menolak permintaan' }
      return $res
    }
    $rid = $req.request_id
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    Start-Sleep -Seconds 6
    while ((Get-Date) -lt $deadline) {
      $r = Invoke-RestMethod -Uri "https://check-host.net/check-result/$rid" -Headers @{ 'Accept' = 'application/json'; 'User-Agent' = 'XyRDP' } -TimeoutSec 30
      $vals = @($r.PSObject.Properties | ForEach-Object { $_.Value })
      if ($vals.Count -gt 0 -and -not ($vals | Where-Object { $null -eq $_ })) {
        $ok = 0; $all = 0
        foreach ($v in $vals) {
          $all++
          if ($v -is [array] -and $v.Count -gt 0 -and $v[0] -and $v[0].time) { $ok++ }
        }
        $res.nodesOk = $ok; $res.nodesAll = $all; $res.ok = ($ok -gt 0)
        $res.detail = "$ok/$all node luar bisa tersambung"
        return $res
      }
      Start-Sleep -Seconds 6
    }
    $res.detail = 'uji luar tidak selesai (timeout)'
    return $res
  } catch { $res.detail = $_.Exception.Message; return $res }
}

# ---------- unduhan ----------
function Get-File([string]$Url, [string]$OutFile, [int]$TimeoutSec = 120) {
  # curl.exe (ada di runner Windows) -> batas waktu keras, tidak bisa menggantung
  # (kejadian nyata: Invoke-WebRequest ke app.prntscr.com menggantung 20 menit
  #  sampai step timeout & seluruh step sesudahnya ter-skip)
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  for ($i = 1; $i -le 3; $i++) {
    try {
      if ($curl) {
        & $curl.Source -sS -L --connect-timeout 15 --max-time $TimeoutSec -o $OutFile $Url 2>&1 | Out-Null
      } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
      }
      if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) { return $true }
      Log "  unduh kosong (coba $i/3)"
    } catch { Log "  unduh gagal (coba $i/3): $($_.Exception.Message)" }
    Start-Sleep -Seconds 3
  }
  return $false
}

# Get-GhAssetUrl <owner/repo> <regex nama asset> -> url unduhan asset terbaru
# Pakai GITHUB_TOKEN supaya tidak kena rate-limit 403 (kejadian nyata di runner:
# IP bersama GitHub-hosted sering sudah habis kuota API anonim).
function Get-GhAssetUrl([string]$Repo, [string]$NameRegex) {
  $hdrs = @{ 'User-Agent' = 'XyRDP' }
  if ($env:GITHUB_TOKEN) { $hdrs['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
  foreach ($h in @($hdrs, @{ 'User-Agent' = 'XyRDP' })) {
    try {
      $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $h -TimeoutSec 60
      $a = $rel.assets | Where-Object { $_.name -match $NameRegex } | Select-Object -First 1
      if ($a) { return @{ url = $a.browser_download_url; tag = $rel.tag_name; name = $a.name } }
    } catch { Log "  GitHub API ($Repo) gagal: $($_.Exception.Message)" }
  }
  return $null
}

# fallback URL keras (kalau API tidak bisa dipakai sama sekali)
$script:XyFallbackUrls = @{
}

# ---------- 10. Profil Windows Resmi & Unlocker Copy (Anti-Hilang Data Sesi) ----------
function Ensure-UserProfileCreated([string]$UserName) {
  if (-not $UserName) { return $null }
  $targetDir = "C:\Users\$UserName"
  try {
    $acct = New-Object System.Security.Principal.NTAccount($UserName)
    $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier]).Value
    $profKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    if (-not (Test-Path $profKey)) {
      if (-not ('XyWin32Profile' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class XyWin32Profile {
    [DllImport("userenv.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int CreateProfile(
        [MarshalAs(UnmanagedType.LPWStr)] string pszUserSid,
        [MarshalAs(UnmanagedType.LPWStr)] string pszUserName,
        [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszProfilePath,
        uint cchProfilePath);
}
"@ -ErrorAction SilentlyContinue
      }
      $sb = New-Object System.Text.StringBuilder 260
      $hr = [XyWin32Profile]::CreateProfile($sid, $UserName, $sb, 260)
      if ($hr -eq 0 -and $sb.Length -gt 0) {
        $targetDir = $sb.ToString()
        Log "  profil resmi Windows dibuat via CreateProfile: $targetDir (SID=$sid)"
      }
    } else {
      $existingPath = (Get-ItemProperty -Path $profKey -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
      if ($existingPath) { $targetDir = $existingPath }
    }
    # Pastikan ProfileList menunjuk ke folder profil yang konsisten & milik user penuh
    if (-not (Test-Path $targetDir)) {
      New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path $profKey) {
      Set-ItemProperty -Path $profKey -Name 'ProfileImagePath' -Value $targetDir -ErrorAction SilentlyContinue
      Set-ItemProperty -Path $profKey -Name 'State' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    & icacls $targetDir /grant "${UserName}:(OI)(CI)F" /grant "Administrators:(OI)(CI)F" /grant "SYSTEM:(OI)(CI)F" /C /Q 2>&1 | Out-Null
  } catch {
    Log "  Ensure-UserProfileCreated warning: $($_.Exception.Message)"
  }
  return $targetDir
}

function Get-AllUserProfileDirs([string]$UserName) {
  $dirs = New-Object System.Collections.Generic.List[string]
  if ($UserName) {
    try {
      $acct = New-Object System.Security.Principal.NTAccount($UserName)
      $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier]).Value
      $profKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
      if (Test-Path $profKey) {
        $p = (Get-ItemProperty -Path $profKey -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
        if ($p -and (Test-Path $p) -and -not $dirs.Contains($p)) { $dirs.Add($p) }
      }
    } catch {}
    $base = "C:\Users\$UserName"
    if ((Test-Path $base) -and -not $dirs.Contains($base)) { $dirs.Add($base) }
    Get-ChildItem -Path 'C:\Users' -Directory -Filter "$UserName.*" -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $dirs.Contains($_.FullName)) { $dirs.Add($_.FullName) }
    }
  }
  if ($dirs.Count -eq 0 -and $UserName) {
    $dirs.Add("C:\Users\$UserName")
  }
  return $dirs.ToArray()
}

function Copy-FileUnlocked([string]$SourceFile, [string]$DestFile) {
  if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) { return $false }
  try {
    $parent = Split-Path -Path $DestFile -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Copy-Item -LiteralPath $SourceFile -Destination $DestFile -Force -ErrorAction Stop
    return $true
  } catch {
    try {
      $inStream = New-Object System.IO.FileStream($SourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
      try {
        $outStream = New-Object System.IO.FileStream($DestFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
          $inStream.CopyTo($outStream)
        } finally {
          $outStream.Dispose()
        }
      } finally {
        $inStream.Dispose()
      }
      return $true
    } catch {
      return $false
    }
  }
}

function Copy-TreeUnlocked([string]$SourceDir, [string]$DestDir) {
  if (-not (Test-Path -LiteralPath $SourceDir)) { return }
  if (Test-Path -LiteralPath $SourceDir -PathType Leaf) {
    Copy-FileUnlocked $SourceDir $DestDir | Out-Null
    return
  }
  New-Item -ItemType Directory -Path $DestDir -Force -ErrorAction SilentlyContinue | Out-Null
  Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $target = Join-Path $DestDir $_.Name
    if ($_.PSIsContainer) {
      Copy-TreeUnlocked $_.FullName $target
    } else {
      Copy-FileUnlocked $_.FullName $target | Out-Null
    }
  }
}

# ---------- 11. Generator Ikon Unik Desktop (.ico 64x64 ARGB Berwarna) ----------
function New-XyAppIcon([string]$OutIcoPath, [string]$BadgeText, [int]$R1, [int]$G1, [int]$B1, [int]$R2, [int]$G2, [int]$B2, [string]$SubText = '') {
  try {
    if (Test-Path -LiteralPath $OutIcoPath) { return $OutIcoPath }
    $dir = Split-Path -Path $OutIcoPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $bmp = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $rect = New-Object System.Drawing.Rectangle(2, 2, 60, 60)
    $c1 = [System.Drawing.Color]::FromArgb(255, $R1, $G1, $B1)
    $c2 = [System.Drawing.Color]::FromArgb(255, $R2, $G2, $B2)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45.0)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 16
    $path.AddArc(2, 2, $d, $d, 180, 90)
    $path.AddArc(62 - $d, 2, $d, $d, 270, 90)
    $path.AddArc(62 - $d, 62 - $d, $d, $d, 0, 90)
    $path.AddArc(2, 62 - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, 255, 255, 255), 2.0)
    $g.DrawPath($pen, $path)

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    $fontSize = if ($BadgeText.Length -ge 3) { 16.5 } else { 21.0 }
    $font = New-Object System.Drawing.Font('Segoe UI', [float]$fontSize, [System.Drawing.FontStyle]::Bold)
    $textY = if ($SubText) { 26 } else { 32 }
    $g.DrawString($BadgeText, $font, [System.Drawing.Brushes]::White, [System.Drawing.PointF]::new(32.0, [float]$textY), $sf)

    if ($SubText) {
      $subFont = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
      $subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 255, 255, 255))
      $g.DrawString($SubText, $subFont, $subBrush, [System.Drawing.PointF]::new(32.0, 49.0), $sf)
      $subBrush.Dispose()
      $subFont.Dispose()
    }

    $msPng = New-Object System.IO.MemoryStream
    $bmp.Save($msPng, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $msPng.ToArray()
    $msPng.Dispose()
    $font.Dispose(); $pen.Dispose(); $path.Dispose(); $brush.Dispose(); $g.Dispose(); $bmp.Dispose()

    $fs = New-Object System.IO.FileStream($OutIcoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs)
    # ICONDIR header (6 bytes) + ICONDIRENTRY (16 bytes) + PNG payload
    $bw.Write([uint16]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]1)
    $bw.Write([byte]64)
    $bw.Write([byte]64)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$pngBytes.Length)
    $bw.Write([uint32]22)
    $bw.Write($pngBytes)
    $bw.Flush()
    $bw.Dispose()
    $fs.Dispose()
    return $OutIcoPath
  } catch {
    return $null
  }
}

function Ensure-XyDesktopIcons {
  $icoDir = 'C:\XyRDP\icons'
  New-Item -ItemType Directory -Path $icoDir -Force -ErrorAction SilentlyContinue | Out-Null
  New-XyAppIcon "$icoDir\xydesk-dashboard.ico"   'XY'  2   132 199 15  23  42  'DASHBOARD' | Out-Null
  New-XyAppIcon "$icoDir\tlauncher.ico"          'TL'  16  185 129 4   120 87  'CRACKED'   | Out-Null
  New-XyAppIcon "$icoDir\prismlauncher.ico"      'PL'  139 92  246 76  29  149 'MODPACK'   | Out-Null
  New-XyAppIcon "$icoDir\minecraft-official.ico" 'MC'  245 158 11  180 83  9   'OFFICIAL'  | Out-Null
  New-XyAppIcon "$icoDir\roblox-antivm.ico"      'RBX' 239 68  68  153 27  27  'ROBLOX'    | Out-Null
  New-XyAppIcon "$icoDir\samp-launcher.ico"      'SA'  249 115 22  194 65  12  'SA-MP'     | Out-Null
  New-XyAppIcon "$icoDir\samp-antiban.ico"       'FIX' 20  184 166 15  118 110 'ANTI-BAN'  | Out-Null
  New-XyAppIcon "$icoDir\cloud-save.ico"         'CLD' 56  189 248 3   105 161 'SAVE'      | Out-Null
  New-XyAppIcon "$icoDir\persist-folder.ico"     'DIR' 234 179 8   161 98  7   'PERSIST'   | Out-Null
  New-XyAppIcon "$icoDir\bluestacks.ico"         'BS5' 59  130 246 29  78  216 'ANDROID'   | Out-Null
  New-XyAppIcon "$icoDir\mumu.ico"               'MM'  236 72  153 157 23  77  'ANDROID'   | Out-Null
  New-XyAppIcon "$icoDir\memu.ico"               'ME'  16  185 129 5   150 105 'MEMU PLAY' | Out-Null
  New-XyAppIcon "$icoDir\ets2.ico"               'ETS' 245 158 11  180 83  9   'ETS 2'     | Out-Null
  New-XyAppIcon "$icoDir\blender.ico"            '3D'  234 88  12  37  99  235 'BLENDER'   | Out-Null
  New-XyAppIcon "$icoDir\fivem.ico"              'V'   249 115 22  220 38  38  'FiveM'     | Out-Null
  return $icoDir
}

# ---------- Kokohkan dependensi ekstraksi & game (2026-11) ----------

function Get-SevenZipPath {
  # Kembalikan path 7z.exe yang valid; kalau belum terpasang, pasang best-effort
  # (winget -> choco). Tanpa 7-Zip, ekstraksi .rar/.7z diam-diam gagal dan
  # GTA SA / paket game tidak pernah terpasang.
  $cands = @(
    'C:\Program Files\7-Zip\7z.exe',
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
    'C:\XyRDP\tools\7z.exe'
  )
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($winget) {
    try {
      & $winget.Source install --id 7zip.7zip -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    } catch {}
  }
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if ($choco) {
    try { & $choco.Source install 7zip -y --no-progress 2>&1 | Out-Null } catch {}
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  }
  Log '7-Zip tidak tersedia - ekstraksi .rar/.7z akan dilewati'
  return $null
}

function Disable-DefenderForGames {
  # Best-effort pada VM sekali-pakai: cegah karantina false-positive terhadap
  # file game (samp.dll, mod GTA SA, wrapper dgVoodoo, dsb.) yang membuat game
  # "tidak bisa dibuka saat pertama kali".
  try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue | Out-Null
    foreach ($x in @('C:\Games', 'C:\XyRDP', 'C:\Persist', 'C:\Users')) {
      try { Add-MpPreference -ExclusionPath $x -ErrorAction SilentlyContinue } catch {}
    }
    Log 'Defender real-time dimatikan + exclusion folder game (best-effort)'
  } catch { Log "Defender tweak dilewati: $($_.Exception.Message)" }
}

Log 'lib-common dimuat'
