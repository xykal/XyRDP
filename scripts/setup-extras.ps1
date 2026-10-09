# ============================================================================
#  setup-extras.ps1 — MODE EKSTRA (v2: Win10-style, tanpa Tailscale/XyDesk)
# ----------------------------------------------------------------------------
#  Dijalankan SETELAH setup-rdp.ps1 (+ setup-win10.ps1). Semua langkah
#  BEST-EFFORT: satu gagal tidak mematikan sesi.
#
#    1) baca konfigurasi dari repo: assets/rdp-extras.json (ubah dari dashboard)
#    2) LIGHTSHOT   — install otomatis (winget -> installer vendor), auto-run
#    3) TRANSLUCENT — TranslucentTB (portable -> winget) + efek transparansi
#    4) WALLPAPER   — assets/wallpaper.* di repo (atau WALLPAPER_URL)
#    5) VERIFIKASI  — user RDP dipastikan anggota grup Administrators
#    6) rangkum hasil -> out/rdp-status.json (dibaca dashboard web)
#
#  Catatan: VM sekali-pakai. Setting per-user ditulis ke profil Default
#  (C:\Users\Default\NTUSER.DAT) supaya otomatis aktif saat user RDP login.
# ============================================================================

$XyTag = 'XyRDP:ekstra'
. "$PSScriptRoot/lib-common.ps1"

$u = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }

# ---------- 0. master switch ----------
$master = $true
if ($env:EXTRAS) {
  $e = $env:EXTRAS.Trim().ToLower()
  if (@('tidak', '0', 'false', 'no', 'off', 'skip', 'none') -contains $e) { $master = $false }
}
if (-not $master) {
  Log "EXTRAS='$env:EXTRAS' — semua langkah ekstra dilewati."
  Update-Status @{ extras = @{ lightshot = 'skip'; translucent = 'skip'; wallpaper = 'skip'; wallpaper_file = ''; vscode = 'skip'; notepadpp = 'skip'; admin = $true } } | Out-Null
  exit 0
}

# ---------- 1. Konfigurasi ----------
$cfg = Get-Cfg
if ($env:WALLPAPER_URL) { Log 'WALLPAPER_URL diisi dari input workflow — override file di repo' }
Log "lightshot=$($cfg.lightshot) | translucent=$($cfg.translucent) ($($cfg.translucent_mode)) | wallpaper=$($cfg.wallpaper) | win10_look=$($cfg.win10_look) | VSCode=$($cfg.vscode) | Notepad++=$($cfg.notepadpp)"

# Terapkan tema juga bila pengguna mematikan langkah visual Win10.
$themeMode = if ($cfg.dark_theme) { 0 } else { 1 }
$transparencyMode = if ($cfg.translucent) { 1 } else { 0 }
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $transparencyMode 'DWord' | Out-Null
Log "  tema $(if ($cfg.dark_theme) { 'gelap' } else { 'terang' }) + transparency=$($cfg.translucent) diterapkan ke profil Default"

# ---------- 2. LIGHTSHOT ----------
function Find-Lightshot {
  $cands = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Skillbrains\lightshot\Lightshot.exe'),
    (Join-Path $env:ProgramFiles            'Skillbrains\lightshot\Lightshot.exe')
  )
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    try {
      $e = Get-ItemProperty $rk -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -like '*Lightshot*' } | Select-Object -First 1
      if ($e -and $e.InstallLocation) {
        $p = Join-Path $e.InstallLocation 'Lightshot.exe'
        if (Test-Path $p) { return $p }
      }
    } catch {}
  }
  return $null
}

function Install-LightshotWinget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Log '  winget tidak tersedia'; return $false }
  try {
    $o = & winget install -e --id Skillbrains.Lightshot --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
    Log "  winget: $(Log-Tail $o 1)"
    Start-Sleep -Seconds 3
    if (Find-Lightshot) { Log '  winget sukses (Lightshot ditemukan)'; return $true }
    Log '  winget selesai tapi Lightshot belum ditemukan, coba direct...'
    return $false
  } catch { Log "  winget error: $($_.Exception.Message)"; return $false }
}

function Install-LightshotChoco {
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if (-not $choco) { Log '  choco tidak tersedia'; return $false }
  try {
    Log '  coba choco install lightshot...'
    $o = & $choco.Source install lightshot -y --no-progress 2>&1 | Out-String
    Log "  choco: $(Log-Tail $o 1)"
    Start-Sleep -Seconds 4
    if (Find-Lightshot) { Log '  choco sukses'; return $true }
    return $false
  } catch { Log "  choco error: $($_.Exception.Message)"; return $false }
}

function Install-LightshotDirect {
  $exe = Join-Path $env:RUNNER_TEMP 'setup-lightshot.exe'
  try {
    Log '  unduh setup-lightshot.exe (app.prntscr.com)...'
    if (-not (Get-File 'https://app.prntscr.com/build/setup-lightshot.exe' $exe 180)) {
      Log '  unduh dari prntscr gagal, coba mirror GitHub...'
      if (-not (Get-File 'https://github.com/skillbrains/lightshot-installer/releases/latest/download/setup-lightshot.exe' $exe 180)) { Log '  unduh gagal semua mirror'; return $false }
    }
    if ((Get-Item $exe).Length -lt 500KB) { Log '  file installer terlalu kecil, gagal'; return $false }
    Start-Process -FilePath $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait
    Start-Sleep -Seconds 6
    return $true
  } catch { Log "  install langsung gagal: $($_.Exception.Message)"; return $false }
}

$resLightshot = 'skip'
if ($cfg.lightshot) {
  Log 'LIGHTSHOT: cek / install (winget -> choco -> direct)...'
  $lsExe = Find-Lightshot
  if (-not $lsExe) { Install-LightshotWinget | Out-Null; $lsExe = Find-Lightshot }
  if (-not $lsExe) { Install-LightshotChoco | Out-Null; $lsExe = Find-Lightshot }
  if (-not $lsExe) { Install-LightshotDirect | Out-Null; $lsExe = Find-Lightshot }
  # final check: coba cari lagi via registry
  if (-not $lsExe) { Start-Sleep -Seconds 2; $lsExe = Find-Lightshot }
  if ($lsExe) {
    Log "  terpasang: $lsExe"
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'Lightshot' $lsExe 'String' | Out-Null
    # ensure firewall allow
    try { New-NetFirewallRule -DisplayName 'Lightshot' -Direction Inbound -Program $lsExe -Action Allow -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Start-Process -FilePath $lsExe -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; $proc=Get-Process -Name 'Lightshot' -ErrorAction SilentlyContinue; if($proc){Log '  Lightshot proses jalan'} else {Log '  Lightshot terpasang tapi proses belum jalan (akan auto-run saat login)'} } catch {}
    # fix: Lightshot kadang butuh Visual C++ redist, sudah diinstall di setup-samp, tapi cek
    $resLightshot = 'ok'
  } else {
    Log '  GAGAL memasang Lightshot (tidak kritis, sesi tetap jalan) - cek log winget/choco'
    $resLightshot = 'gagal'
  }
}

# ---------- 3. TRANSLUCENT (taskbar) ----------
function Find-TranslucentTB {
  $cands = @(
    'C:\Tools\TranslucentTB\TranslucentTB.exe',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\TranslucentTB.exe'),
    (Join-Path $env:ProgramFiles 'TranslucentTB\TranslucentTB.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  try {
    $g = Get-ChildItem 'C:\Tools' -Recurse -Filter 'TranslucentTB.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.FullName }
  } catch {}
  return $null
}

function Install-TranslucentTBPortable {
  $dir = 'C:\Tools\TranslucentTB'
  $zip = Join-Path $env:RUNNER_TEMP 'ttb.zip'
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Log '  unduh TranslucentTB portable (GitHub releases)...'
    $urls = @(
      'https://github.com/TranslucentTB/TranslucentTB/releases/latest/download/TranslucentTB-portable-x64.zip',
      'https://github.com/TranslucentTB/TranslucentTB/releases/download/2024.1/TranslucentTB-portable-x64.zip'
    )
    $ok=$false
    foreach($u in $urls){
      if(Get-File $u $zip 180){ if((Get-Item $zip).Length -gt 300KB){ $ok=$true; Log "  unduh sukses dari $u"; break } else { Log "  zip dari $u terlalu kecil"; Remove-Item $zip -Force -ErrorAction SilentlyContinue } }
    }
    if(-not $ok){ Log '  unduh gagal semua mirror'; return $false }
    # clean old
    if(Test-Path $dir){ Get-ChildItem $dir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    # verify exe exists
    if(-not (Test-Path (Join-Path $dir 'TranslucentTB.exe'))){
      $found=Get-ChildItem $dir -Recurse -Filter 'TranslucentTB.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($found){ Log "  ditemukan di $($found.DirectoryName)" }
    }
    return (Test-Path (Join-Path $dir 'TranslucentTB.exe')) -or (Find-TranslucentTB)
  } catch { Log "  portable gagal: $($_.Exception.Message)"; return $false }
}

function Install-TranslucentTBWinget {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    foreach ($id in @('TranslucentTB.TranslucentTB', 'CharlesMilette.TranslucentTB')) {
      try {
        $o = & winget install -e --id $id --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
        Log "  winget ($id): $(Log-Tail $o 1)"
        Start-Sleep -Seconds 3
        if (Find-TranslucentTB) { Log "  winget $id sukses"; return $true }
      } catch { Log "  winget error ($id): $($_.Exception.Message)" }
    }
  }
  # fallback choco
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if ($choco) {
    try {
      Log '  coba choco install translucenttb...'
      $o2 = & $choco.Source install translucenttb -y --no-progress 2>&1 | Out-String
      Log "  choco: $(Log-Tail $o2 1)"
      Start-Sleep -Seconds 3
      if (Find-TranslucentTB) { Log '  choco sukses'; return $true }
    } catch { Log "  choco error: $($_.Exception.Message)" }
  }
  return $false
}

$resTrans = 'skip'
if ($cfg.translucent) {
  Log "TRANSLUCENT: taskbar mode '$($cfg.translucent_mode)'..."
  # efek transparansi native (kalau setup-win10 dilewati, ini tetap dipasang)
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null

  $ttbExe = Find-TranslucentTB
  if (-not $ttbExe) { Install-TranslucentTBPortable | Out-Null; $ttbExe = Find-TranslucentTB }
  if (-not $ttbExe) { Install-TranslucentTBWinget | Out-Null; $ttbExe = Find-TranslucentTB }
  if ($ttbExe) {
    Log "  TranslucentTB: $ttbExe"
    $mode = $cfg.translucent_mode
    if (@('normal', 'opaque', 'clear', 'blur', 'acrylic', 'transparent') -notcontains $mode) { $mode = 'clear' }
    $ttbDir = Split-Path $ttbExe -Parent
    # always enable native transparency
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null
    try { Set-RegBoth 'Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1 'DWord' | Out-Null } catch {}
    if ($ttbDir -like 'C:\Tools*') {
      $json = "{ \"desktop_appearance\": { \"accent\": \"$mode\", \"color\": \"#00000000\" }, \"hide_tray\": false, \"disable_saving\": false, \"dynamic\": { \"enabled\": true } }"
      try { Set-Content -Path (Join-Path $ttbDir 'settings.json') -Value $json -Encoding utf8 -ErrorAction Stop; Log "  settings.json -> mode=$mode (hous translucent fix: EnableTransparency + AeroPeek)" }
      catch { Log "  settings.json gagal ditulis: $($_.Exception.Message)" }
    } else { Log "  (build MSIX/Store — mode '$mode' diatur via tray icon; translucency native tetap aktif)" }
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'TranslucentTB' $ttbExe 'String' | Out-Null
    # ensure firewall allow & kill old instance then start
    try { Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 } catch {}
    try {
      Start-Process -FilePath $ttbExe -WorkingDirectory $ttbDir -ErrorAction SilentlyContinue; Start-Sleep -Seconds 4
      $proc=Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue
      if ($proc) { Log "  proses TranslucentTB berjalan (tray) PID $($proc.Id) - hous translucent OK" }
      else { Log '  proses TranslucentTB belum terlihat (mungkin butuh login ulang, tapi taskbar sudah transparan via registry)' }
    } catch { Log "  start TranslucentTB gagal: $($_.Exception.Message)" }
    $resTrans = 'ok'
  } else {
    Log '  TranslucentTB gagal dipasang — efek transparansi native (registry) tetap aktif sebagai fallback'
    # fallback: ensure native transparency tetap
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null
    $resTrans = 'sebagian'
  }
}

# ---------- 3b. EDITOR CODING OPSIONAL -------------------------------------
# Git/Node/Python/7-Zip/Visual Studio sudah ada pada image windows-2022.
# Hanya VS Code dan Notepad++ yang ditambahkan bila dipilih di dashboard.
function Find-VSCode {
  foreach ($c in @(
    (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'),
    "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe",
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
  )) { if ($c -and (Test-Path $c)) { return $c } }
  $cmd = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}
function Find-NotepadPP {
  foreach ($c in @(
    (Join-Path $env:ProgramFiles 'Notepad++\notepad++.exe'),
    "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
  )) { if ($c -and (Test-Path $c)) { return $c } }
  $cmd = Get-Command notepad++.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}
function Install-ChocoCodingTool([string]$Label, [string]$Package) {
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if (-not $choco) { Log "  $Label dilewati: Chocolatey tidak tersedia"; return $false }
  try {
    Log "  memasang $Label dari Chocolatey ($Package)..."
    $out = & $choco.Source install $Package -y --no-progress 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($out) { Log "  Chocolatey $Label (exit $code): $(Log-Tail $out 2)" }
    return ($code -eq 0)
  } catch { Log "  pemasangan $Label gagal: $($_.Exception.Message)"; return $false }
}

$resVSCode = 'skip'
if ($cfg.vscode) {
  Log 'VS CODE: cek / pasang...'
  if (Find-VSCode) { $resVSCode = 'sudah ada'; Log '  VS Code sudah tersedia' }
  else {
    Install-ChocoCodingTool 'VS Code' 'vscode.install' | Out-Null
    Start-Sleep -Seconds 2
    $resVSCode = if (Find-VSCode) { 'ok' } else { 'gagal' }
    Log "  VS Code: $resVSCode"
  }
}

$resNotepadPP = 'skip'
if ($cfg.notepadpp) {
  Log 'NOTEPAD++: cek / pasang...'
  if (Find-NotepadPP) { $resNotepadPP = 'sudah ada'; Log '  Notepad++ sudah tersedia' }
  else {
    Install-ChocoCodingTool 'Notepad++' 'notepadplusplus.install' | Out-Null
    Start-Sleep -Seconds 2
    $resNotepadPP = if (Find-NotepadPP) { 'ok' } else { 'gagal' }
    Log "  Notepad++: $resNotepadPP"
  }
}

# ---------- 4. WALLPAPER ----------
function Set-WallpaperLive([string]$imgPath) {
  try {
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class XyWall { [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }' -ErrorAction Stop
    [XyWall]::SystemParametersInfo(20, 0, $imgPath, 3) | Out-Null
    return $true
  } catch { Log "  set live wallpaper gagal: $($_.Exception.Message)"; return $false }
}

$resWall = 'skip'; $wallName = ''
if ($cfg.wallpaper) {
  Log 'WALLPAPER: siapkan gambar...'
  $wpDir = 'C:\XyRDP'
  $wpFile = $null; $srcUsed = ''

  # urutan sumber: input workflow -> file di repo (checkout) -> raw github
  if ($env:WALLPAPER_URL) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_download'
      if (Get-File $env:WALLPAPER_URL $tmp 180) {
        $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
        if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'WALLPAPER_URL' }
        else { Log '  URL bukan gambar jpg/png/bmp — diabaikan' }
      }
    } catch { Log "  unduh dari WALLPAPER_URL gagal: $($_.Exception.Message)" }
  }
  if (-not $wpFile) {
    $repoFile = $null
    foreach ($cand in @("$($cfg.wallpaper_file)", 'wallpaper.jpg', 'wallpaper.jpeg', 'wallpaper.png', 'wallpaper.bmp')) {
      $p = Join-Path (Get-Workspace) "assets\$cand"
      if (Test-Path $p) { $repoFile = $p; break }
    }
    if ($repoFile) {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $ext = [IO.Path]::GetExtension($repoFile).TrimStart('.').ToLower()
      $wpFile = Join-Path $wpDir "wallpaper.$ext"
      Copy-Item $repoFile $wpFile -Force
      $srcUsed = "repo ($(Split-Path $repoFile -Leaf))"
    }
  }
  if (-not $wpFile -and $env:GITHUB_REPOSITORY) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_raw'
      if (Get-File "https://raw.githubusercontent.com/$($env:GITHUB_REPOSITORY)/main/assets/$($cfg.wallpaper_file)" $tmp 120) {
        $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
        if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'raw github' }
      }
    } catch { Log "  raw github tidak ada ($($_.Exception.Message))" }
  }

  if ($wpFile -and (Test-Path $wpFile)) {
    Log "  wallpaper: $wpFile (sumber: $srcUsed)"
    Set-RegBoth 'Control Panel\Desktop' 'Wallpaper'      $wpFile 'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'WallpaperStyle' '10'     'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'TileWallpaper'  '0'      'String' | Out-Null
    if (Set-WallpaperLive $wpFile) { Log '  wallpaper diterapkan ke sesi live' }
    $resWall = 'ok'; $wallName = Split-Path $wpFile -Leaf
  } else {
    Log '  tidak ada wallpaper (upload lewat dashboard atau isi WALLPAPER_URL)'
    $resWall = 'default'
  }
}

# ---------- 5. VERIFIKASI: sesi harus ADMIN ----------
Log 'VERIFIKASI HAK AKSES:'
$adminOk = $false
try {
  $grpExists = Get-LocalGroup -Name 'Administrators' -ErrorAction SilentlyContinue
  $usrExists = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
  if ($grpExists -and $usrExists) {
    $members = Get-LocalGroupMember -Group 'Administrators' | ForEach-Object { ($_.Name -split '\\')[-1] }
    $rdpMembers = @()
    try { $rdpMembers = Get-LocalGroupMember -Group 'Remote Desktop Users' | ForEach-Object { ($_.Name -split '\\')[-1] } } catch {}
    $adminOk = ($members -contains $u)
    $adminTxt = $(if ($adminOk) { 'YA' } else { 'TIDAK' })
    $rdpTxt   = $(if ($rdpMembers -contains $u) { 'YA' } else { 'TIDAK' })
    Log ("  user '{0}' ada: YA | Administrators: {1} | Remote Desktop Users: {2}" -f $u, $adminTxt, $rdpTxt)
    $lf = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
    Log "  LocalAccountTokenFilterPolicy = $lf (1 = token admin penuh untuk sesi jaringan/RDP)"
  } else { Log '  user/grup tidak ditemukan (harusnya dibuat setup-rdp.ps1)' }
} catch { Log "  verifikasi gagal: $($_.Exception.Message)" }

# ---------- 6. Rangkum ke status ----------
Update-Status @{ extras = [ordered]@{
    lightshot      = $resLightshot
    translucent    = $resTrans
    wallpaper      = $resWall
    wallpaper_file = $wallName
    vscode         = $resVSCode
    notepadpp      = $resNotepadPP
    admin          = $adminOk
} } | Out-Null
Close-DefaultHive

$adminTxt = $(if ($adminOk) { 'YA' } else { 'TIDAK' })
Log ("SELESAI — lightshot={0} translucent={1} wallpaper={2} admin={3}" -f $resLightshot, $resTrans, $resWall, $adminTxt)
try { Probe-Rdp 'akhir step' | Out-Null } catch {}

exit 0
