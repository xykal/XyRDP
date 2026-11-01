# ============================================================================
#  setup-extras.ps1 - MODE EKSTRA (v2: Win10-style, tanpa Tailscale/XyDesk)
# ----------------------------------------------------------------------------
#  Dijalankan SETELAH setup-rdp.ps1 (+ setup-win10.ps1). Semua langkah
#  BEST-EFFORT: satu gagal tidak mematikan sesi.
#
#    1) baca konfigurasi dari repo: assets/rdp-extras.json (ubah dari dashboard)
#    2) LIGHTSHOT   - install otomatis (winget -> installer vendor), auto-run
#    3) TranslucentTB disabled
#    4) WALLPAPER   - assets/wallpaper.* di repo (atau WALLPAPER_URL)
#    5) VERIFIKASI  - user RDP dipastikan anggota grup Administrators
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
  Log "EXTRAS='$env:EXTRAS' - semua langkah ekstra dilewati."
  Update-Status @{ extras = @{ lightshot = 'skip'; wallpaper = 'skip'; wallpaper_file = ''; vscode = 'skip'; notepadpp = 'skip'; admin = $true } } | Out-Null
  exit 0
}

# ---------- 1. Konfigurasi ----------
$cfg = Get-Cfg
if ($env:WALLPAPER_URL) { Log 'WALLPAPER_URL diisi dari input workflow - override file di repo' }
Log "lightshot=$($cfg.lightshot) | wallpaper=$($cfg.wallpaper) | win10_look=$($cfg.win10_look) | VSCode=$($cfg.vscode) | Notepad++=$($cfg.notepadpp)"

# Terapkan tema juga bila pengguna mematikan langkah visual Win10.
$themeMode = if ($cfg.dark_theme) { 0 } else { 1 }
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $transparencyMode 'DWord' | Out-Null
Log "  tema $(if ($cfg.dark_theme) { 'gelap' } else { 'terang' })  diterapkan ke profil Default"

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

function Install-LightshotDirect {
  $exe = Join-Path $env:RUNNER_TEMP 'setup-lightshot.exe'
  try {
    if (-not (Get-File 'https://updater.prntscr.com/builds/setup-lightshot-5.5.0.7.exe' $exe 180)) { return $false }
    # Pinned hash from microsoft/winget-pkgs Skillbrains.Lightshot 5.5.0.7 manifest.
    $expectedHash = '928C2808421DFD487FFA697379548CBE682C0E13AEB595EB89973BA9C515B8A1'
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expectedHash) {
      Log 'Lightshot installer rejected: pinned SHA256 mismatch.'; return $false
    }
    $sig = Get-AuthenticodeSignature -FilePath $exe
    Log "Lightshot pinned SHA256 verified; Authenticode status=$($sig.Status)"
    $installLog = Join-Path $env:RUNNER_TEMP 'lightshot-install.log'
    $proc = Start-Process -FilePath $exe -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/ALLUSERS',('/LOG="{0}"' -f $installLog)) -PassThru
    if (-not $proc.WaitForExit(180000)) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      Log 'Lightshot install timed out after 180 seconds.'; return $false
    }
    $proc.Refresh()
    Log "Lightshot installer exit=$($proc.ExitCode); diagnostic log=$installLog"
    if ($proc.ExitCode -notin @(0,3010)) { return $false }
    return [bool](Find-Lightshot)
  } catch { Log "Lightshot install failed: $($_.Exception.Message)"; return $false }
}

$resLightshot = 'skip'
if ($cfg.lightshot) {
  Log 'LIGHTSHOT: verified vendor installer, machine-wide install, bounded wait...'
  $lsExe = Find-Lightshot
  if (-not $lsExe) { Install-LightshotDirect | Out-Null; $lsExe = Find-Lightshot }
  # final check: coba cari lagi via registry
  if (-not $lsExe) { Start-Sleep -Seconds 2; $lsExe = Find-Lightshot }
  if ($lsExe) {
    Log "  terpasang: $lsExe"
    Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'Lightshot' ('"{0}"' -f $lsExe) 'String' | Out-Null
    # ensure firewall allow
    # Screenshot capture does not require opening an inbound firewall rule.
    try { Start-Process -FilePath $lsExe -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; $proc=Get-Process -Name 'Lightshot' -ErrorAction SilentlyContinue; if($proc){Log '  Lightshot proses jalan'} else {Log '  Lightshot terpasang tapi proses belum jalan (akan auto-run saat login)'} } catch {}
    # fix: Lightshot kadang butuh Visual C++ redist, sudah diinstall di setup-samp, tapi cek
    $resLightshot = 'ok'
  } else {
    Log '  GAGAL memasang Lightshot (tidak kritis, sesi tetap jalan) - cek log installer vendor'
    $resLightshot = 'gagal'
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
function Install-WingetCodingTool([string]$Label, [string]$Id) {
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) { Log "  $Label dilewati: winget tidak tersedia"; return $false }
  try {
    Log "  memasang $Label dari winget ($Id)..."
    & $winget.Source install --id $Id -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    return $true
  } catch { Log "  winget $Label gagal: $($_.Exception.Message)"; return $false }
}
function Install-VSCodeDirect {
  try {
    Log '  memasang VS Code (installer resmi Microsoft, unduh langsung)...'
    $exe = Join-Path $env:TEMP 'vscode-system-x64.exe'
    & curl.exe -fL --retry 1 --connect-timeout 15 --max-time 180 -sS 'https://update.code.visualstudio.com/latest/win32-x64-system/stable' -o $exe
    if (-not (Test-Path $exe) -or (Get-Item $exe).Length -lt 65536) { Log '  unduhan VS Code gagal'; return }
    $p = Start-Process -FilePath $exe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/MERGETASKS=!runcode', '/ALLUSERS') -Wait -PassThru -WindowStyle Hidden
    Log "  installer VS Code exit=$($p.ExitCode)"
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
  } catch { Log "  VS Code direct gagal: $($_.Exception.Message)" }
}
function Install-NotepadPPDirect {
  try {
    Log '  memasang Notepad++ (installer resmi GitHub, unduh langsung)...'
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest' -TimeoutSec 20
    $asset = $rel.assets | Where-Object { $_.name -match '^npp\..+\.Installer\.x64\.exe$' } | Select-Object -First 1
    if (-not $asset) { Log '  aset installer Notepad++ tidak ditemukan'; return }
    $exe = Join-Path $env:TEMP 'npp-installer-x64.exe'
    & curl.exe -fL --retry 1 --connect-timeout 15 --max-time 180 -sS $asset.browser_download_url -o $exe
    if (-not (Test-Path $exe) -or (Get-Item $exe).Length -lt 65536) { Log '  unduhan Notepad++ gagal'; return }
    $p = Start-Process -FilePath $exe -ArgumentList @('/S') -Wait -PassThru -WindowStyle Hidden
    Log "  installer Notepad++ exit=$($p.ExitCode)"
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
  } catch { Log "  Notepad++ direct gagal: $($_.Exception.Message)" }
}

$resVSCode = 'skip'
if ($cfg.vscode) {
  Log 'VS CODE: cek / pasang...'
  if (Find-VSCode) { $resVSCode = 'sudah ada'; Log '  VS Code sudah tersedia' }
  else {
    # Rantai fallback: winget -> Chocolatey -> installer resmi langsung.
    Install-WingetCodingTool 'VS Code' 'Microsoft.VisualStudioCode' | Out-Null
    if (-not (Find-VSCode)) { Install-ChocoCodingTool 'VS Code' 'vscode.install' | Out-Null }
    if (-not (Find-VSCode)) { Install-VSCodeDirect }
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
    # Rantai fallback: winget -> Chocolatey -> installer resmi langsung.
    Install-WingetCodingTool 'Notepad++' 'Notepad++.Notepad++' | Out-Null
    if (-not (Find-NotepadPP)) { Install-ChocoCodingTool 'Notepad++' 'notepadplusplus.install' | Out-Null }
    if (-not (Find-NotepadPP)) { Install-NotepadPPDirect }
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

  # urutan sumber: input workflow -> simpanan sesi sebelumnya (C:\Persist\Config) -> file di repo (checkout) -> raw github
  if ($env:WALLPAPER_URL) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_download'
      if (Get-File $env:WALLPAPER_URL $tmp 180) {
        $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
        if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'WALLPAPER_URL' }
        else { Log '  URL bukan gambar jpg/png/bmp - diabaikan' }
      }
    } catch { Log "  unduh dari WALLPAPER_URL gagal: $($_.Exception.Message)" }
  }
  if (-not $wpFile -and (Test-Path 'C:\Persist\Config')) {
    $persistedWp = Get-ChildItem -Path 'C:\Persist\Config' -Filter 'wallpaper.*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($persistedWp) {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $ext = $persistedWp.Extension.TrimStart('.').ToLower()
      $wpFile = Join-Path $wpDir "wallpaper.$ext"
      Copy-Item $persistedWp.FullName $wpFile -Force
      $srcUsed = "persist ($($persistedWp.Name))"
    }
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
    try {
      $ext = [IO.Path]::GetExtension($wpFile)
      New-Item -ItemType Directory -Path 'C:\Users\Public\Pictures\XyRDP' -Force -ErrorAction SilentlyContinue | Out-Null
      New-Item -ItemType Directory -Path 'C:\Persist\Config' -Force -ErrorAction SilentlyContinue | Out-Null
      Copy-Item -LiteralPath $wpFile -Destination "C:\Users\Public\Pictures\XyRDP\wallpaper$ext" -Force -ErrorAction SilentlyContinue
      Copy-Item -LiteralPath $wpFile -Destination "C:\Persist\Config\wallpaper$ext" -Force -ErrorAction SilentlyContinue
    } catch {}
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

# ---------- 4b. LIVELY WALLPAPER v2.2.1.0 (60 FPS ANTI-STUCK RDP OPTIMIZATION) ----------
$resLively = 'skip'
try {
  Log 'LIVELY WALLPAPER: mengoptimalkan DWM 60Hz & memasang Lively Wallpaper v2.2.1.0 Anti-Stuck RDP...'
  # 1. Buka kebijakan RDP Wallpaper & Desktop Composition 60 FPS via Policy & WinStations root
  #    PENTING: JANGAN PERNAH memanggil New-Item -Force atau menulis ke WinStations\RDP-Tcp
  #    karena akan menghapus konfigurasi listener RDP 3389 (membuat step Tailscale gagal)!
  $tsPolPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
  if (-not (Test-Path $tsPolPath)) {
    New-Item -Path $tsPolPath -Force -ErrorAction SilentlyContinue | Out-Null
  }
  Set-ItemProperty -Path $tsPolPath -Name 'fDisableWallpaper' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $tsPolPath -Name 'fNoRemoteDesktopWallpaper' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $tsPolPath -Name 'fNoFontSmoothing' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' -Name 'DWMFRAMEINTERVAL' -Value 15 -Type DWord -Force -ErrorAction SilentlyContinue
  Set-RegBoth 'Software\Microsoft\Windows\DWM' 'Composition' 1 'DWord' | Out-Null
  Set-RegBoth 'Software\Microsoft\Windows\DWM' 'CompositionPolicy' 2 'DWord' | Out-Null

  # 2. Cari atau pasang Lively Wallpaper v2.2.1.0 resmi
  function Find-LivelyExe {
    foreach ($cand in @(
      'C:\Program Files (x86)\Lively Wallpaper\Lively.exe',
      'C:\Program Files\Lively Wallpaper\Lively.exe',
      "$env:LOCALAPPDATA\Programs\Lively Wallpaper\Lively.exe",
      "C:\Users\$u\AppData\Local\Programs\Lively Wallpaper\Lively.exe"
    )) {
      if ($cand -and (Test-Path $cand)) { return $cand }
    }
    return $null
  }

  $livelyExe = Find-LivelyExe
  if (-not $livelyExe) {
    $livelySetup = Join-Path $env:RUNNER_TEMP 'lively_setup_x86_full_v2210.exe'
    if (Get-File 'https://github.com/lively-community/lively/releases/download/v2.2.1.0/lively_setup_x86_full_v2210.exe' $livelySetup 240) {
      $lProc = Start-Process -FilePath $livelySetup -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/ALLUSERS') -PassThru -WindowStyle Hidden
      if ($lProc) { $lProc.WaitForExit(180000) | Out-Null }
      Remove-Item $livelySetup -Force -ErrorAction SilentlyContinue
      $livelyExe = Find-LivelyExe
    }
  }

  # 3. Tulis Settings.json Lively Wallpaper dengan RemoteDesktopPause = 1 (AppRules.ignore)
  #    agar Live Wallpaper TIDAK PERNAH PAUSE / STUCK saat diakses dari RDP maupun APK Android!
  $livelySettingsJson = @'
{
  "AppVersion": "2.2.1.0",
  "Language": "en-US",
  "Startup": true,
  "IsFirstRun": false,
  "ControlPanelOpened": true,
  "AppFocusPause": 1,
  "AppFullscreenPause": 1,
  "BatteryPause": 1,
  "RemoteDesktopPause": 1,
  "PowerSaveModePause": 1,
  "DisplayPauseRule": 0,
  "PauseAlgorithm": 0,
  "VideoPlayer": 0,
  "VideoPlayerHwAccel": false,
  "GifPlayer": 0,
  "WebBrowser": 0,
  "KeepAwakeUI": true,
  "LivelyGUIRendering": 1,
  "WallpaperArrangement": 0,
  "SysTrayIcon": true,
  "WebDebugPort": "",
  "AutoDetectOnlineStreams": false,
  "ExtractStreamMetaData": false,
  "WallpaperBundleVersion": 3,
  "AudioVolumeGlobal": 50,
  "AudioOnlyOnDesktop": false,
  "RememberSelectedScreen": true
}
'@
  foreach ($profUser in @($u, 'runneradmin', 'xyadmin', 'Default')) {
    if (-not $profUser) { continue }
    $livelyDataDir = "C:\Users\$profUser\AppData\Local\Lively Wallpaper"
    New-Item -ItemType Directory -Path $livelyDataDir -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content -LiteralPath (Join-Path $livelyDataDir 'Settings.json') -Value $livelySettingsJson -Encoding UTF8 -Force
  }

  # 4. Buat Shortcut Lively Wallpaper di Desktop dengan ikon asli Lively.exe
  if ($livelyExe -and (Test-Path $livelyExe)) {
    Log "  Lively Wallpaper siap di: $livelyExe (RemoteDesktopPause=Ignore / 60Hz Anti-Stuck)"
    foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
      New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
      try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut((Join-Path $desk 'Lively Wallpaper.lnk'))
        $lnk.TargetPath = $livelyExe
        $lnk.WorkingDirectory = Split-Path $livelyExe -Parent
        $lnk.IconLocation = "$livelyExe,0"
        $lnk.Description = 'Lively Wallpaper (60 FPS Live Wallpaper Anti-Stuck RDP)'
        $lnk.Save()
      } catch {}
    }
    $resLively = 'ok'
  }
} catch {
  Log "  Lively Wallpaper setup warning: $($_.Exception.Message)"
}

# ---------- 5. VERIFIKASI: sesi harus ADMIN ----------
Log 'VERIFIKASI HAK AKSES:'
$adminOk = $false
try {
  $grpExists = Get-LocalGroup -Name 'Administrators' -ErrorAction SilentlyContinue
  $usrExists = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
  if ($grpExists -and $usrExists) {
    $members = Get-LocalGroupMember -Group 'Administrators' | ForEach-Object { ($_.Name -split '\\')[-1] }
    # Highest admin check: UAC
    $lua2 = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $cpa = Get-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $rdpMembers = @()
    try { $rdpMembers = Get-LocalGroupMember -Group 'Remote Desktop Users' | ForEach-Object { ($_.Name -split '\\')[-1] } } catch {}
    $adminOk = ($members -contains $u)
    $adminTxt = $(if ($adminOk) { 'YA' } else { 'TIDAK' })
    $rdpTxt   = $(if ($rdpMembers -contains $u) { 'YA' } else { 'TIDAK' })
    Log ("  user '{0}' ada: YA | Administrators: {1} | Remote Desktop Users: {2} | HIGHEST ADMIN (UAC OFF): EnableLUA={3} Consent={4}" -f $u, $adminTxt, $rdpTxt, $lua2, $cpa)
    $lf = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
    Log "  LocalAccountTokenFilterPolicy = $lf (1 = token admin penuh untuk sesi jaringan/RDP)"
  } else { Log '  user/grup tidak ditemukan (harusnya dibuat setup-rdp.ps1)' }
} catch { Log "  verifikasi gagal: $($_.Exception.Message)" }

# ---------- 6. Build & Pasang XyDeskTools.exe (Gaming & Tools Hub) ----------
try {
  $toolsHubScript = Join-Path $PSScriptRoot 'setup-tools-hub.ps1'
  if (Test-Path $toolsHubScript) {
    & $toolsHubScript
  }
} catch {
  Log "setup-tools-hub warning: $($_.Exception.Message)"
}

# ---------- 7. Rangkum ke status ----------
Update-Status @{ extras = [ordered]@{
    lightshot      = $resLightshot
        wallpaper      = $resWall
    wallpaper_file = $wallName
    vscode         = $resVSCode
    notepadpp      = $resNotepadPP
    admin          = $adminOk
} } | Out-Null
Close-DefaultHive

$adminTxt = $(if ($adminOk) { 'YA' } else { 'TIDAK' })
Log ("SELESAI - lightshot={0} wallpaper={1} admin={2}" -f $resLightshot, $resWall, $adminTxt)
try { Probe-Rdp 'akhir step' | Out-Null } catch {}

exit 0
