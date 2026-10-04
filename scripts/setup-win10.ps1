# ============================================================================
#  setup-win10.ps1 — "Windows 10 look" untuk runner windows-2022
# ----------------------------------------------------------------------------
#  Catatan jujur: runner GitHub TIDAK punya image Windows 10 desktop. Yang
#  dipakai adalah Windows Server 2022 yang secara UI/kernel = Windows 10 21H2
#  (build 20348) — jadi tampilannya sudah Windows 10. Script ini menambahkan
#  yang khas "Windows 10" dan mematikan yang khas "Server":
#
#    1) Server Manager tidak muncul saat login, IE Enhanced Security mati
#    2) Shutdown Event Tracker mati (tidak tanya "alasan shutdown")
#    3) Personalisasi: transparansi, warna aksen di taskbar, taskbar
#       "jangan gabungkan tombol", kotak pencarian, tema gelap taskbar
#    4) Wallpaper + latar login/lock screen bergaya Windows 10
#    5) Ctrl+Alt+Del tidak diwajibkan di layar login (seperti Windows 10)
#    6) Windows Search diaktifkan supaya Start menu bisa mencari
#    7) (opsional) label "Windows 10 Pro" di registry — kosmetik
#
#  Semua langkah BEST-EFFORT: gagal satu tidak mematikan sesi.
#  Konfigurasi: assets/rdp-extras.json -> win10_look / win10_badge /
#  win10_wallpaper (bisa diubah dari dashboard web).
# ============================================================================

$XyTag = 'XyRDP:win10'
. "$PSScriptRoot/lib-common.ps1"

# ---------- 0. master switch ----------
$skip = $false
if ($env:WIN10) { $e = $env:WIN10.Trim().ToLower(); if (@('tidak', '0', 'false', 'no', 'off', 'skip', 'none') -contains $e) { $skip = $true } }
$cfg = Get-Cfg
if (-not $cfg.win10_look) { $skip = $true }
if ($skip) {
  Log 'tweak Windows 10 dilewati (input WIN10=tidak atau win10_look=false di rdp-extras.json)'
  Update-Status @{ win10 = @{ look = 'skip' } } | Out-Null
  exit 0
}
Log "mulai tweak Windows 10 (badge=$($cfg.win10_badge) wallpaper=$($cfg.win10_wallpaper) dark=$($cfg.dark_theme) ringan=$($cfg.lightweight_mode))"

$os = try { Get-CimInstance Win32_OperatingSystem } catch { $null }
Log "  OS terpasang: $($os.Caption) build $($os.Version) — UI-nya sama dengan Windows 10 21H2"

# ---------- 1. buang ciri khas "Server" ----------
Open-DefaultHive | Out-Null

# Server Manager: jangan buka otomatis saat login
Set-RegBoth 'Software\Microsoft\ServerManager' 'DoNotOpenServerManagerAtLogon' 1 'DWord' | Out-Null
# Shutdown Event Tracker: jangan tanya alasan
Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Reliability\Shutdown' 'ShutdownReasonOn' 0 'DWord' | Out-Null
# IE Enhanced Security Configuration (2 key: admin + user)
foreach ($guid in @('{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}', '{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}')) {
  Set-Reg "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Active Setup\Installed Components\$guid" 'IsInstalled' 0 'DWord' | Out-Null
}
Log '  Server Manager & Shutdown Event Tracker dimatikan, IE ESC dimatikan'

# ---------- 2. layar login ala Windows 10 ----------
# Windows 10 tidak mewajibkan Ctrl+Alt+Del di layar login
Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'DisableCAD' 1 'DWord' | Out-Null
# sembunyikan teks versi/edisi di sudut desktop
Set-RegBoth 'Control Panel\Desktop' 'PaintDesktopVersion' 0 'DWord' | Out-Null
# sembunyikan akun Administrator bawaan supaya layar login bersih (job runner
# jalan sebagai runneradmin, jadi tidak terpengaruh)
try { Disable-LocalUser -Name 'Administrator' -ErrorAction Stop; Log '  akun Administrator bawaan dinonaktifkan (layar login bersih)' } catch { Log "  nonaktifkan Administrator dilewati: $($_.Exception.Message)" }

# ---------- 3. personalisasi ala Windows 10 ----------
$themeMode = if ($cfg.dark_theme) { 0 } else { 1 }
$transparencyMode = if ($cfg.translucent) { 1 } else { 0 }
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $transparencyMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'ColorPrevalence'   1 'DWord' | Out-Null   # warna aksen di taskbar (khas Win10)
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' $themeMode 'DWord' | Out-Null
Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'   $themeMode 'DWord' | Out-Null
# taskbar: jangan gabungkan tombol (default Win10), kotak pencarian, tombol Task View
$adv = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-RegBoth $adv 'TaskbarGlomLevel'      2 'DWord' | Out-Null
Set-RegBoth $adv 'TaskbarSmallIcons'     0 'DWord' | Out-Null
Set-RegBoth $adv 'SearchboxTaskbarMode'  2 'DWord' | Out-Null
Set-RegBoth $adv 'ShowTaskViewButton'    1 'DWord' | Out-Null
Set-RegBoth $adv 'EnableAutoTray'        0 'DWord' | Out-Null
# warna aksen biru Windows 10 (#0078D7)
$dwm = 'Software\Microsoft\Windows\DWM'
Set-RegBoth $dwm 'ColorPrevalence'     1 'DWord'  | Out-Null
Set-RegBoth $dwm 'AccentColor'         0xffd77800 'DWord' | Out-Null   # ABGR
Set-RegBoth $dwm 'ColorizationColor'   0xc40078d7 'DWord' | Out-Null
Set-RegBoth $dwm 'ColorizationAfterglow' 0xc40078d7 'DWord' | Out-Null
Set-RegBoth $dwm 'EnableWindowColorization' 1 'DWord' | Out-Null
Log "  personalisasi diterapkan (tema=$(if ($cfg.dark_theme) { 'gelap' } else { 'terang' }), transparansi=$($cfg.translucent), aksen, taskbar)"

# ---------- 4. Windows Search diaktifkan (Start menu bisa mencari) ----------
try {
  Set-Service -Name WSearch -StartupType Automatic -ErrorAction Stop
  Start-Service -Name WSearch -ErrorAction Stop
  Log '  layanan Windows Search: aktif (Start menu bisa mencari aplikasi)'
  $searchStatus = 'ok'
} catch { Log "  Windows Search tidak bisa diaktifkan (tidak kritis): $($_.Exception.Message)"; $searchStatus = 'gagal' }

# ---------- 5. wallpaper & latar login ----------
function Get-Win10WallpaperFile {
  $names = @()
  # Pilihan dashboard/current config harus didahulukan; wallpaper-win10.* hanya
  # fallback. Kalau tidak, gambar bawaan lama akan menimpa wallpaper upload.
  if ($cfg.wallpaper_file) { $names += @($cfg.wallpaper_file) }
  if ($cfg.win10_wallpaper) { $names += @('wallpaper-win10.jpg', 'wallpaper-win10.png') }
  $names += @('wallpaper.jpg', 'wallpaper.jpeg', 'wallpaper.png', 'wallpaper.bmp')
  foreach ($n in $names) {
    $p = Join-Path (Get-Workspace) "assets\$n"
    if (Test-Path $p) { return $p }
  }
  if ($env:GITHUB_REPOSITORY -and $cfg.wallpaper_file) {
    $tmp = Join-Path $env:RUNNER_TEMP 'wp-win10.jpg'
    $rawName = [IO.Path]::GetFileName($cfg.wallpaper_file)
    if (Get-File "https://raw.githubusercontent.com/$($env:GITHUB_REPOSITORY)/main/assets/$rawName" $tmp 120) { return $tmp }
  }
  return $null
}

# Resize + kompres ke JPEG < 256 KB (batas latar layar login Windows)
function Save-LogonBackground([string]$Src, [string]$Dst, [int]$MaxKB = 240) {
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $img = [System.Drawing.Image]::FromFile($Src)
    $w = 1920; $h = [int]($img.Height * (1920.0 / $img.Width)); if ($h -gt 1080) { $h = 1080; $w = [int]($img.Width * (1080.0 / $img.Height)) }
    foreach ($q in @(85, 75, 65, 55)) {
      $bmp = New-Object System.Drawing.Bitmap($w, $h)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose()
      $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
      $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
      $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$q)
      $bmp.Save($Dst, $enc, $ep)
      $bmp.Dispose()
      $kb = [math]::Round((Get-Item $Dst).Length / 1KB)
      if ($kb -le $MaxKB) { Log "  latar login: ${w}x${h}, ${kb} KB (kualitas $q)"; $img.Dispose(); return $true }
    }
    $img.Dispose()
    Log "  latar login: $([math]::Round((Get-Item $Dst).Length / 1KB)) KB (di atas batas 256 KB, Windows mungkin mengabaikan)"
    return $true
  } catch { Log "  gagal menyiapkan latar login: $($_.Exception.Message)"; return $false }
}

$wallStatus = 'skip'
$wpFile = Get-Win10WallpaperFile
if ($wpFile) {
  try {
    New-Item -ItemType Directory -Path 'C:\XyRDP' -Force | Out-Null
    $ext = [IO.Path]::GetExtension($wpFile).TrimStart('.').ToLower(); if (-not $ext) { $ext = 'jpg' }
    $local = "C:\XyRDP\wallpaper-win10.$ext"
    Copy-Item $wpFile $local -Force
    # desktop wallpaper (profil Default + sesi sekarang)
    Set-RegBoth 'Control Panel\Desktop' 'Wallpaper'      $local 'String' | Out-Null
    Set-RegBoth 'Control Panel\Desktop' 'WallpaperStyle' '10'    'String' | Out-Null   # 10 = Fill
    Set-RegBoth 'Control Panel\Desktop' 'TileWallpaper'  '0'     'String' | Out-Null
    try {
      Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class XyWall { [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }' -ErrorAction Stop
      [XyWall]::SystemParametersInfo(20, 0, $local, 3) | Out-Null
    } catch {}
    # layar login / lock screen
    $oobe = 'C:\Windows\System32\oobe\info\backgrounds'
    New-Item -ItemType Directory -Path $oobe -Force | Out-Null
    Save-LogonBackground $local (Join-Path $oobe 'backgroundDefault.jpg') | Out-Null
    Set-Reg 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\Background' 'OEMBackground' 1 'DWord' | Out-Null
    $wallStatus = 'ok'
    Log "  wallpaper diterapkan: $local (+ latar layar login)"
  } catch { Log "  wallpaper gagal: $($_.Exception.Message)"; $wallStatus = 'gagal' }
} else {
  Log '  tidak ada file wallpaper di assets/ — wallpaper bawaan dipakai'
  $wallStatus = 'default'
}

# ---------- 6. (opsional) label "Windows 10 Pro" di registry ----------
$badgeStatus = 'skip'
if ($cfg.win10_badge) {
  try {
    $cv = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $b1 = Set-Reg $cv 'ProductName'     'Windows 10 Pro' 'String'
    $b2 = Set-Reg $cv 'EditionID'       'Professional'   'String'
    $b3 = Set-Reg $cv 'CompositionEditionID' 'Professional' 'String'
    $b4 = Set-Reg $cv 'DisplayVersion'  '22H2'           'String'
    $badgewins = @($b1, $b2, $b3, $b4 | Where-Object { $_ }).Count
    # ProductType: key ini milik TrustedInstaller -> ambil kepemilikan dulu
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\ProductOptions', $true)
    if (-not $key) {
      $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\ProductOptions',
              [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
      $ident = [System.Security.Principal.WindowsIdentity]::GetCurrent()
      $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
      $acl.SetOwner($ident.User); $key.SetAccessControl($acl)
      $acl = $key.GetAccessControl()
      $acl.SetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($ident.Name, 'FullControl', 'Allow')))
      $key.SetAccessControl($acl)
    }
    $key.SetValue('ProductType', 'WinNT', [Microsoft.Win32.RegistryValueKind]::String)
    $key.Close()
    Log "  label registry: Windows 10 Pro / 22H2 (ProductType=WinNT, $badgewins/4 kunci nama produk berhasil)"
    $badgeStatus = if ($badgewins -ge 3) { 'ok' } else { "sebagian ($badgewins/4)" }
  } catch { Log "  label Windows 10 gagal (tidak kritis): $($_.Exception.Message)"; $badgeStatus = 'gagal' }
} else {
  Log '  label Windows 10 dimatikan (win10_badge=false) — sistem tetap menampilkan nama Windows Server'
}

Close-DefaultHive

# ---------- 7. rangkum ke status ----------
Update-Status @{ win10 = [ordered]@{
    look = 'ok'; badge = $badgeStatus; wallpaper = $wallStatus; search = $searchStatus
    os = if ($os) { $os.Caption } else { 'Windows' }
    note = 'Tampilan Windows 10 (UI Windows Server 2022 = kernel/UI Windows 10 21H2)'
} } | Out-Null

Log "SELESAI — win10 look=ok badge=$badgeStatus wallpaper=$wallStatus search=$searchStatus"
try { Probe-Rdp 'akhir step' | Out-Null } catch {}

exit 0
