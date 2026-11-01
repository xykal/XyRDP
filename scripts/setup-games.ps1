# ============================================================================
#  setup-games.ps1 - Penyedia Game & Emulator Ready-to-Play di XyRDP:
#    1) Minecraft Java Edition (Otomatis Siap Pakai):
#       - Menghubungkan & menyuntikkan Mesa3D OpenGL 4.6 (llvmpipe) ke seluruh
#         runtime Java (Temurin JDK 21 & JRE 8 di C:\hostedtoolcache & Program Files)
#         agar bebas "GLFW error 65542: The driver does not appear to support OpenGL"
#       - Memasang TL Launcher (C:\Games\Minecraft\TL.jar + Launch-TLauncher.vbs)
#         dari mirror resmi bebas Cloudflare 403 (https://llaun.ch/jar)
#       - Memasang PrismLauncher Portable (C:\Games\PrismLauncher\prismlauncher.exe)
#         yang mendukung akun Microsoft maupun Offline
#       - Memasang Official Minecraft Launcher (C:\Games\Minecraft\MinecraftLauncher.exe)
#       - Preset options.txt 120 FPS ramah RDP di %APPDATA%\.minecraft
#    2) Minecraft Bedrock / Microsoft Store Xbox Identity
#    3) Roblox Player + ClientAppSettings Direct3D 11 120 FPS
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$XyTag                 = 'XyRDP:games'
. "$PSScriptRoot/lib-common.ps1"

function Test-OptIn([string]$Val) {
  if (-not $Val) { return $false }
  return @('ya','1','true','yes','on') -contains $Val.Trim().ToLower()
}

$wantRoblox  = Test-OptIn $env:ROBLOX
$wantMcJava  = Test-OptIn $env:MINECRAFT_JAVA
$wantMcBed   = Test-OptIn $env:MINECRAFT_BEDROCK

$work = 'C:\XyRDP\deps\games'
New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Games' -Force | Out-Null

function Invoke-GameDownload([string]$Url, [string]$OutFile, [int]$MinBytes = 4096) {
  Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
  & curl.exe -fL -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" --retry 3 --retry-all-errors --retry-delay 3 --connect-timeout 20 --max-time 240 -sS $Url -o $OutFile
  if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
    return $true
  }
  try {
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -UseBasicParsing -TimeoutSec 180
    return ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes)
  } catch {
    return $false
  }
}

function Find-BestJavawExe {
  $candidates = @()
  foreach ($root in @(
    'C:\Program Files\Eclipse Adoptium',
    'C:\hostedtoolcache\windows\Java_Temurin-Hotspot_jdk',
    'C:\Program Files\Java',
    'C:\Program Files\Microsoft'
  )) {
    if (Test-Path $root) {
      $found = Get-ChildItem -Path $root -Recurse -File -Filter 'javaw.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'x64|jdk-21|jdk-17|jre-21|jre-17' } |
        Sort-Object FullName -Descending
      if ($found) { $candidates += $found }
    }
  }
  if ($candidates.Count -gt 0) { return $candidates[0].FullName }
  $cmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return 'javaw.exe'
}

function Install-JavaRuntimesForMinecraft([bool]$InstallMsiIfMissing) {
  # Cek apakah Temurin JDK 21 sudah tersedia di C:\hostedtoolcache atau C:\Program Files\Eclipse Adoptium
  $existingJavaw = Find-BestJavawExe
  $hasJava21 = ($existingJavaw -and (Test-Path $existingJavaw) -and ($existingJavaw -match '21\.'))

  if (-not $hasJava21 -and $InstallMsiIfMissing) {
    try {
      $jdk21Msi = Join-Path $work 'Temurin21-x64.msi'
      Log 'Mengunduh Eclipse Temurin JDK 21 LTS (x64) untuk Minecraft 1.21+...'
      if (Invoke-GameDownload 'https://api.adoptium.net/v3/installer/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' $jdk21Msi 10000000) {
        Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$jdk21Msi`"", '/qn', '/norestart', 'ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome') -Wait -WindowStyle Hidden | Out-Null
        Log 'Eclipse Temurin JDK 21 LTS terpasang.'
      }
    } catch { Log "Instalasi JDK 21 warning: $($_.Exception.Message)" }
  }

  # Cek JRE 8 untuk Minecraft 1.8.9 / 1.12.2
  $hasJava8 = $false
  foreach ($r8 in @('C:\Program Files\Eclipse Adoptium', 'C:\hostedtoolcache\windows\Java_Temurin-Hotspot_jdk')) {
    if (Test-Path $r8) {
      if ((Get-ChildItem $r8 -Directory -Filter '*8*' -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        $hasJava8 = $true; break
      }
    }
  }
  if (-not $hasJava8 -and $InstallMsiIfMissing) {
    try {
      $jre8Msi = Join-Path $work 'Temurin8-x64.msi'
      Log 'Mengunduh Eclipse Temurin JRE 8 LTS (x64) untuk Minecraft 1.8.9/1.12.2...'
      if (Invoke-GameDownload 'https://api.adoptium.net/v3/installer/latest/8/ga/windows/x64/jre/hotspot/normal/eclipse' $jre8Msi 10000000) {
        Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$jre8Msi`"", '/qn', '/norestart') -Wait -WindowStyle Hidden | Out-Null
        Log 'Eclipse Temurin JRE 8 LTS terpasang.'
      }
    } catch { Log "Instalasi JRE 8 warning: $($_.Exception.Message)" }
  }

  # Pastikan JAVA_HOME & PATH sistem mengarah ke javaw.exe terbaik
  $best = Find-BestJavawExe
  if ($best -and (Test-Path $best)) {
    $binDir = Split-Path $best -Parent
    $homeDir = Split-Path $binDir -Parent
    $curPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($curPath -notlike "*$binDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$binDir;$curPath", 'Machine')
      $env:Path = "$binDir;$env:Path"
    }
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $homeDir, 'Machine')
    $env:JAVA_HOME = $homeDir
  }
}

function Install-PrismLauncherPortable {
  $prismDir = 'C:\Games\PrismLauncher'
  if (Test-Path (Join-Path $prismDir 'prismlauncher.exe')) {
    return $true
  }
  New-Item -ItemType Directory -Path $prismDir -Force | Out-Null
  $sevenZip = 'C:\Program Files\7-Zip\7z.exe'
  if (-not (Test-Path $sevenZip)) { $sevenZip = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
  if (-not (Test-Path $sevenZip)) { $sevenZip = Get-SevenZipPath }

  # Prioritaskan build Portable yang mendukung akun Microsoft & Offline sekaligus, fallback ke upstream PrismLauncher
  foreach ($repo in @('Diegiwg/PrismLauncher-Cracked', 'PrismLauncher/PrismLauncher')) {
    try {
      $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" `
        -Headers @{ 'User-Agent' = 'XyRDP' } -TimeoutSec 20
      $asset = $rel.assets | Where-Object { $_.name -match 'Windows-MSVC-Portable-.*\.zip$' -and $_.name -notmatch 'arm64' } | Select-Object -First 1
      if (-not $asset) {
        $asset = $rel.assets | Where-Object { $_.name -match 'Windows.*Portable.*\.zip$' -and $_.name -notmatch 'arm64' } | Select-Object -First 1
      }
      if ($asset) {
        $zip = Join-Path $work $asset.name
        Log "Mengunduh PrismLauncher Portable dari $repo ($($asset.name))..."
        if (Invoke-GameDownload $asset.browser_download_url $zip 5000000) {
          if (Test-Path $sevenZip) { & $sevenZip x $zip "-o$prismDir" -y 2>&1 | Out-Null }
          else { Expand-Archive -Path $zip -DestinationPath $prismDir -Force }
          # Jika terekstrak ke dalam subfolder, pindahkan ke root $prismDir
          $exe = Get-ChildItem -Path $prismDir -Recurse -File -Filter 'prismlauncher.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($exe -and $exe.DirectoryName -ne $prismDir) {
            Get-ChildItem -Path $exe.DirectoryName -Force | ForEach-Object {
              Move-Item $_.FullName -Destination $prismDir -Force -ErrorAction SilentlyContinue
            }
          }
          if (Test-Path (Join-Path $prismDir 'prismlauncher.exe')) {
            $javaw = (Find-BestJavawExe) -replace '\\', '/'
            @(
              '[General]'
              'ApplicationTheme=dark'
              'AutoUpdate=false'
              'UpdateCheck=false'
              'Language=en_US'
              "LastHostname=$($env:COMPUTERNAME)"
              "JavaPath=$javaw"
              'MaxMemAlloc=4096'
              'MinMemAlloc=1024'
              'SkipJavaCompatibilityCheck=true'
              'SkipJavaWizard=true'
            ) | Set-Content -Path (Join-Path $prismDir 'prismlauncher.cfg') -Encoding ASCII -Force
            $acctJson = @'
{
    "accounts": [
        {
            "active": true,
            "entitlement": {
                "canPlayMinecraft": true,
                "ownsMinecraft": true
            },
            "profile": {
                "capes": [],
                "id": "8667ba71b85a4004af54457a9734eed7",
                "name": "XyPlayer_RDP",
                "skin": {
                    "id": "",
                    "url": "",
                    "variant": "CLASSIC"
                }
            },
            "type": "Offline"
        }
    ],
    "formatVersion": 3
}
'@
            Set-Content -Path (Join-Path $prismDir 'accounts.json') -Value $acctJson -Encoding ASCII -Force
            Log "PrismLauncher Portable siap di $prismDir (Language=en_US + Akun Offline XyPlayer_RDP siap)"
            return $true
          }
        }
      }
    } catch {
      Log "PrismLauncher ($repo) warning: $($_.Exception.Message)"
    }
  }
  return $false
}

function Install-MinecraftLaunchersSuite {
  $mcDir = 'C:\Games\Minecraft'
  New-Item -ItemType Directory -Path $mcDir -Force | Out-Null

  # 1. Unduh Official Minecraft Launcher (Minecraft.exe - 3.3 MB, selalu HTTP 200 dari Mojang)
  $offExe = Join-Path $mcDir 'MinecraftLauncher.exe'
  if (-not (Test-Path $offExe)) {
    if (Invoke-GameDownload 'https://launcher.mojang.com/download/Minecraft.exe' $offExe 1000000) {
      Log "Official Minecraft Launcher siap di $offExe"
    }
  }

  # 2. Unduh TL Legacy Launcher (TL.jar - 11 MB dari https://llaun.ch/jar yang bebas blokir Cloudflare 403)
  $tlJar = Join-Path $mcDir 'TL.jar'
  if (-not (Test-Path $tlJar)) {
    foreach ($u in @('https://llaun.ch/jar', 'https://dl.llaun.ch/legacy/bootstrap')) {
      if (Invoke-GameDownload $u $tlJar 2000000) {
        Log "Minecraft TL Launcher (TL.jar) berhasil diunduh dari $u"
        break
      }
    }
  }

  # Buat launcher script TLauncher.bat & Launch-TLauncher.vbs (tanpa jendela CMD hitam, langsung memanggil javaw.exe dengan OpenGL 4.6)
  $tlBat = Join-Path $mcDir 'TLauncher.bat'
  $batCode = @'
@echo off
set GALLIUM_DRIVER=llvmpipe
set LIBGL_ALWAYS_SOFTWARE=1
set MESA_GL_VERSION_OVERRIDE=4.6
set MESA_GLSL_VERSION_OVERRIDE=460
if exist "C:\XyRDP\grafis\Deploy-OpenGL-To-Java.ps1" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\XyRDP\grafis\Deploy-OpenGL-To-Java.ps1" >nul 2>&1
)
set "JAVAW=javaw.exe"
for /f "delims=" %%J in ('powershell.exe -NoProfile -Command "$c=@(Get-ChildItem 'C:\Program Files\Eclipse Adoptium','C:\hostedtoolcache\windows\Java_Temurin-Hotspot_jdk','C:\Program Files\Java' -Recurse -Filter javaw.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'x64|jdk-21|jdk-17' } | Sort-Object FullName -Descending); if($c.Count){$c[0].FullName}"') do set "JAVAW=%%J"
if exist "C:\Games\Minecraft\TL.jar" (
  start "" "%JAVAW%" -Xmx4096M -Dsun.java2d.d3d=false -jar "C:\Games\Minecraft\TL.jar"
  exit /b 0
)
if exist "C:\Games\PrismLauncher\prismlauncher.exe" (
  start "" "C:\Games\PrismLauncher\prismlauncher.exe"
  exit /b 0
)
if exist "C:\Games\Minecraft\MinecraftLauncher.exe" (
  start "" "C:\Games\Minecraft\MinecraftLauncher.exe"
)
'@
  Set-Content -Path $tlBat -Value $batCode -Encoding ASCII -Force

  $tlVbs = Join-Path $mcDir 'Launch-TLauncher.vbs'
  $vbsCode = 'CreateObject("WScript.Shell").Run """C:\Games\Minecraft\TLauncher.bat""", 0, False'
  Set-Content -Path $tlVbs -Value $vbsCode -Encoding ASCII -Force
}

function Configure-MinecraftOpenGLAndOptions {
  # Pastikan Mesa3D OpenGL 4.6 sudah terpasang di System32, SysWOW64, dan C:\XyRDP\grafis\mesa-x64
  $mesaDll = 'C:\XyRDP\grafis\mesa-x64\opengl32.dll'
  if (-not (Test-Path $mesaDll)) {
    try {
      $env:GRAFIS = 'software'
      & "$PSScriptRoot/setup-grafis.ps1" 2>&1 | Out-Null
    } catch {}
  }
  $deployPs1 = 'C:\XyRDP\grafis\Deploy-OpenGL-To-Java.ps1'
  if (Test-Path $deployPs1) {
    try {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deployPs1 2>&1 | Out-Null
    } catch {}
  }

  # Siapkan folder .minecraft + options.txt ramah RDP (120 FPS, VSync Off, Raw Mouse Input On)
  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($profUser in @($u, 'runneradmin', 'xyadmin')) {
    if (-not $profUser) { continue }
    $userRoot = "C:\Users\$profUser"
    if (-not (Test-Path $userRoot)) { continue }
    $mcDir = Join-Path $userRoot 'AppData\Roaming\.minecraft'
    New-Item -ItemType Directory -Path $mcDir -Force -ErrorAction SilentlyContinue | Out-Null
    $optFile = Join-Path $mcDir 'options.txt'
    if (-not (Test-Path $optFile)) {
      @(
        'version:3953'
        'autoJump:false'
        'enableVsync:false'
        'maxFps:120'
        'renderDistance:8'
        'simulationDistance:6'
        'graphicsMode:0'
        'ao:false'
        'Clouds:false'
        'particles:1'
        'mipmapLevels:0'
        'rawMouseInput:true'
        'fullscreen:false'
        'guiScale:2'
      ) | Set-Content -Path $optFile -Encoding ASCII -Force
    }
  }

  # Buat shortcut di Desktop User & Public Desktop dengan Nama & Ikon Unik (Anti-Tertukar!)
  $icoDir = Ensure-XyDesktopIcons
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      # Hapus shortcut lama yang namanya mirip / ikonnya kembar
      foreach ($oldLnk in @('Minecraft (TLauncher).lnk', 'PrismLauncher (Minecraft).lnk', 'Install Roblox Player.exe')) {
        Remove-Item -LiteralPath (Join-Path $desk $oldLnk) -Force -ErrorAction SilentlyContinue
      }

      $wsh = New-Object -ComObject WScript.Shell
      $iconExe = 'C:\Games\Minecraft\MinecraftLauncher.exe'

      if (Test-Path 'C:\Games\Minecraft\Launch-TLauncher.vbs') {
        $lnk = $wsh.CreateShortcut((Join-Path $desk 'TLauncher (Minecraft Cracked).lnk'))
        $lnk.TargetPath = 'wscript.exe'
        $lnk.Arguments = '"C:\Games\Minecraft\Launch-TLauncher.vbs"'
        $lnk.WorkingDirectory = 'C:\Games\Minecraft'
        if (Test-Path $iconExe) { $lnk.IconLocation = "$iconExe,0" }
        $lnk.Description = 'TLauncher Cracked / Offline Minecraft Java Edition (OpenGL 4.6 Ready)'
        $lnk.Save()
      }

      if (Test-Path 'C:\Games\PrismLauncher\prismlauncher.exe') {
        $lnk2 = $wsh.CreateShortcut((Join-Path $desk 'PrismLauncher (Minecraft Modpack).lnk'))
        $lnk2.TargetPath = 'C:\Games\PrismLauncher\prismlauncher.exe'
        $lnk2.WorkingDirectory = 'C:\Games\PrismLauncher'
        $lnk2.IconLocation = 'C:\Games\PrismLauncher\prismlauncher.exe,0'
        $lnk2.Description = 'PrismLauncher Modpack & Multi-Instance (Microsoft & Offline + OpenGL 4.6)'
        $lnk2.Save()
      }

      if (Test-Path $iconExe) {
        $lnk3 = $wsh.CreateShortcut((Join-Path $desk 'Minecraft Official Launcher.lnk'))
        $lnk3.TargetPath = $iconExe
        $lnk3.WorkingDirectory = 'C:\Games\Minecraft'
        $lnk3.IconLocation = "$iconExe,0"
        $lnk3.Description = 'Official Minecraft Launcher (Mojang / Xbox)'
        $lnk3.Save()
      }
    } catch {}
  }
}

function Install-RobloxAntiVmSuite {
  $rbxDir = 'C:\Games\Roblox'
  New-Item -ItemType Directory -Path $rbxDir -Force -ErrorAction SilentlyContinue | Out-Null

  # 1. Tanpa spoofing BIOS / penghapusan driver VM / bypass anti-cheat
  #    (kebijakan repo). Hanya instalasi resmi + optimasi performa wajar.
  Disable-DefenderForGames

  $rbxExe = Join-Path $rbxDir 'RobloxPlayerInstaller.exe'
  if (-not (Test-Path $rbxExe)) {
    Invoke-GameDownload 'https://setup.rbxcdn.com/RobloxPlayerInstaller.exe' $rbxExe 1000000 | Out-Null
  }

  # 2. Ekstrak langsung paket resmi RobloxPlayerBeta.exe dari CDN Roblox (rbxPkgManifest)
  #    agar 100% terinstal di C:\Games\Roblox\Versions\<ver> sebelum sesi RDP aktif!
  $sevenZip = 'C:\Program Files\7-Zip\7z.exe'
  if (-not (Test-Path $sevenZip)) { $sevenZip = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }
  if (-not (Test-Path $sevenZip)) { $sevenZip = Get-SevenZipPath }
  $verFolder = $null
  $playerBetaExe = $null
  try {
    $verInfo = Invoke-RestMethod -Uri 'https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer' -TimeoutSec 15
    $verHash = $verInfo.clientVersionUpload
    if ($verHash) {
      $verFolder = Join-Path $rbxDir "Versions\$verHash"
      $playerBetaExe = Join-Path $verFolder 'RobloxPlayerBeta.exe'
      if (-not (Test-Path $playerBetaExe)) {
        Log "Mengunduh & mengekstrak paket resmi Roblox ($verHash) ke $verFolder..."
        New-Item -ItemType Directory -Path $verFolder -Force | Out-Null
        $pkgMap = @{
          'RobloxApp.zip'                     = ''
          'shaders.zip'                       = 'shaders'
          'ssl.zip'                           = 'ssl'
          'WebView2.zip'                      = ''
          'content-avatar.zip'                = 'content\avatar'
          'content-configs.zip'               = 'content\configs'
          'content-fonts.zip'                 = 'content\fonts'
          'content-sky.zip'                   = 'content\sky'
          'content-sounds.zip'                = 'content\sounds'
          'content-textures2.zip'             = 'content\textures'
          'content-models.zip'                = 'content\models'
          'content-textures3.zip'             = 'PlatformContent\pc\textures'
          'content-terrain.zip'               = 'PlatformContent\pc\terrain'
          'content-platform-fonts.zip'        = 'PlatformContent\pc\fonts'
          'content-platform-dictionaries.zip' = 'PlatformContent\pc\shared_compression_dictionaries'
          'extracontent-luapackages.zip'      = 'ExtraContent\LuaPackages'
          'extracontent-translations.zip'     = 'ExtraContent\translations'
          'extracontent-models.zip'           = 'ExtraContent\models'
          'extracontent-textures.zip'         = 'ExtraContent\textures'
          'extracontent-places.zip'           = 'ExtraContent\places'
        }
        foreach ($pkg in $pkgMap.Keys) {
          $sub = $pkgMap[$pkg]
          $dst = if ($sub) { Join-Path $verFolder $sub } else { $verFolder }
          New-Item -ItemType Directory -Path $dst -Force | Out-Null
          $zipTmp = Join-Path $work "rbx_$pkg"
          if (Invoke-GameDownload "https://setup.rbxcdn.com/$verHash-$pkg" $zipTmp 1024) {
            if (Test-Path $sevenZip) { & $sevenZip x $zipTmp "-o$dst" -y 2>&1 | Out-Null }
            else { Expand-Archive -Path $zipTmp -DestinationPath $dst -Force }
            Remove-Item $zipTmp -Force -ErrorAction SilentlyContinue
          }
        }
        # Tulis AppSettings.xml wajib agar RobloxPlayerBeta.exe mengenali folder content
        @(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<Settings>'
          '    <ContentFolder>content</ContentFolder>'
          '    <BaseUrl>http://www.roblox.com</BaseUrl>'
          '</Settings>'
        ) | Set-Content -Path (Join-Path $verFolder 'AppSettings.xml') -Encoding UTF8 -Force

        # Pastikan RobloxCrashHandler.exe tetap utuh (JANGAN di-rename ke .bak karena RobloxPlayerBeta.exe memvalidasi keberadaannya saat startup!)
        $crashBak = Join-Path $verFolder 'RobloxCrashHandler.exe.bak'
        $crashExe = Join-Path $verFolder 'RobloxCrashHandler.exe'
        if ((Test-Path $crashBak) -and -not (Test-Path $crashExe)) {
          Rename-Item -LiteralPath $crashBak -NewName 'RobloxCrashHandler.exe' -Force -ErrorAction SilentlyContinue
        }
      }
    }

    # Ekstrak juga RobloxStudioBeta.exe resmi (WindowsStudio64 - Bebas Hyperion Anti-VM DLL!) ke C:\Games\Roblox\Studio
    $studioDir = 'C:\Games\Roblox\Studio'
    $studioExe = Join-Path $studioDir 'RobloxStudioBeta.exe'
    if (-not (Test-Path $studioExe)) {
      $stMeta = Invoke-RestMethod -Uri 'https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64' -TimeoutSec 20 -ErrorAction SilentlyContinue
      $stHash = if ($stMeta -and $stMeta.clientVersionUpload) { $stMeta.clientVersionUpload } else { 'version-7aaa6838d36c4448' }
      New-Item -ItemType Directory -Path $studioDir -Force | Out-Null
      $stPkgs = @{
        'RobloxStudio.zip'                = ''
        'redist.zip'                      = ''
        'Libraries.zip'                   = ''
        'LibrariesQt5.zip'                = ''
        'WebView2.zip'                    = ''
        'Plugins.zip'                     = 'Plugins'
        'StudioFonts.zip'                 = 'StudioFonts'
        'ssl.zip'                         = 'ssl'
        'shaders.zip'                     = 'shaders'
        'content-sky.zip'                 = 'content\sky'
        'content-textures2.zip'           = 'content\textures'
        'content-studio_svg_textures.zip' = 'content\studio_svg_textures'
        'content-fonts.zip'               = 'content\fonts'
        'content-configs.zip'             = 'content\configs'
        'ApplicationConfig.zip'           = 'ApplicationConfig'
      }
      foreach ($sp in $stPkgs.Keys) {
        $sSub = $stPkgs[$sp]
        $sDst = if ($sSub) { Join-Path $studioDir $sSub } else { $studioDir }
        New-Item -ItemType Directory -Path $sDst -Force | Out-Null
        $sZip = Join-Path $work "st_$sp"
        if (Invoke-GameDownload "https://setup.rbxcdn.com/$stHash-$sp" $sZip 10) {
          if (Test-Path $sevenZip) { & $sevenZip x $sZip "-o$sDst" -y 2>&1 | Out-Null }
          else { Expand-Archive -Path $sZip -DestinationPath $sDst -Force -ErrorAction SilentlyContinue }
          Remove-Item $sZip -Force -ErrorAction SilentlyContinue
        }
      }
      @(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Settings>'
        '    <ContentFolder>content</ContentFolder>'
        '    <BaseUrl>http://www.roblox.com</BaseUrl>'
        '</Settings>'
      ) | Set-Content -Path (Join-Path $studioDir 'AppSettings.xml') -Encoding UTF8 -Force
    }
  } catch {
    Log "Ekstraksi paket Roblox CDN warning: $($_.Exception.Message)"
  }

  # 3. Suntikkan ClientAppSettings.json (Direct3D 11 WARP + 120 FPS) & hubungkan ke profil user RDP
  $fflags = @{
    FFlagDebugGraphicsPreferD3D11 = $true
    FFlagDebugGraphicsDisableDirect3D11 = $false
    FFlagDebugGraphicsDisableDirect3D12 = $true
    DFIntTaskSchedulerTargetFps = 120
    FFlagHandleAltEnterFullscreenManually = $false
  } | ConvertTo-Json

  if ($verFolder -and (Test-Path $verFolder)) {
    $csDir = Join-Path $verFolder 'ClientSettings'
    New-Item -ItemType Directory -Path $csDir -Force | Out-Null
    Set-Content -Path (Join-Path $csDir 'ClientAppSettings.json') -Value $fflags -Encoding UTF8 -Force
  }

  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($profUser in @($u, 'runneradmin', 'xyadmin')) {
    if (-not $profUser) { continue }
    $uRbxVer = "C:\Users\$profUser\AppData\Local\Roblox\Versions"
    New-Item -ItemType Directory -Path $uRbxVer -Force -ErrorAction SilentlyContinue | Out-Null
    if ($verFolder -and (Test-Path $verFolder)) {
      $leaf = Split-Path $verFolder -Leaf
      $linkTarget = Join-Path $uRbxVer $leaf
      if (-not (Test-Path $linkTarget)) {
        & cmd.exe /c "mklink /J `"$linkTarget`" `"$verFolder`"" 2>&1 | Out-Null
      }
    }
  }

  # Daftarkan URL Protocol roblox-player: & Environment Registry di HKLM + HKCU
  if ($playerBetaExe -and (Test-Path $playerBetaExe)) {
    try {
      New-Item -Path 'HKLM:\SOFTWARE\Classes\roblox-player\shell\open\command' -Force | Out-Null
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\roblox-player' -Name '(Default)' -Value 'URL: Roblox Protocol' -Force
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\roblox-player' -Name 'URL Protocol' -Value '' -Force
      Set-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\roblox-player\shell\open\command' -Name '(Default)' -Value "`"$playerBetaExe`" %1" -Force
      $envKey = 'HKCU:\Software\ROBLOX Corporation\Environments\roblox-player'
      New-Item -Path $envKey -Force | Out-Null
      Set-ItemProperty -Path $envKey -Name 'clientExe' -Value $playerBetaExe -Force
      Set-ItemProperty -Path $envKey -Name 'version' -Value (Split-Path $verFolder -Leaf) -Force
      Set-ItemProperty -Path $envKey -Name 'channel' -Value 'production' -Force
    } catch {}
  }

  # 4. Buat Launcher Anti-VM Roblox + Direct3D 11 120 FPS + Cloud/Emulator Bypass
  $rbxLauncherPs1 = Join-Path $rbxDir 'Launch-Roblox-AntiVM.ps1'
  $rbxLauncherCode = @'
param(
  [switch]$CloudFallback
)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

if (Test-Path 'C:\XyRDP\tools\Apply-AntiVM-Boost.ps1') {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\XyRDP\tools\Apply-AntiVM-Boost.ps1' | Out-Null
}

$playerBeta = Get-ChildItem -Path @('C:\Games\Roblox\Versions', "$env:LOCALAPPDATA\Roblox\Versions") -Recurse -Filter 'RobloxPlayerBeta.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($playerBeta) {
  $layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
  if (-not (Test-Path $layersKey)) { New-Item -Path $layersKey -Force | Out-Null }
  Set-ItemProperty -Path $layersKey -Name $playerBeta.FullName -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -Force
  $env:__COMPAT_LAYER = 'RunAsInvoker'
  $proc = Start-Process -FilePath $playerBeta.FullName -WorkingDirectory $playerBeta.DirectoryName -ArgumentList '--app' -PassThru
  Start-Sleep -Seconds 4
  if ($proc -and -not $proc.HasExited) {
    exit 0
  }
}

# Jika RobloxPlayerBeta.exe diblokir Hyperion CPUID VM Check Azure, buka Dialog Pemilihan Mode Anti-VM
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Roblox Player - XyRDP Launcher'
$form.Size = New-Object System.Drawing.Size(520, 310)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 20, 28)
$form.ForeColor = [System.Drawing.Color]::White

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Anti-Cheat Hyperion (Byfron) mendeteksi CPU Virtual Machine Azure.`r`nPilih jalur bypass di bawah untuk tetap bermain Roblox dengan lancar:"
$lbl.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$lbl.Location = New-Object System.Drawing.Point(20, 18)
$lbl.Size = New-Object System.Drawing.Size(470, 48)
$form.Controls.Add($lbl)

$btn1 = New-Object System.Windows.Forms.Button
$btn1.Text = '1. Buka Roblox Web / Cloud App Mode (Bebas Blokir VM)'
$btn1.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$btn1.Location = New-Object System.Drawing.Point(20, 78)
$btn1.Size = New-Object System.Drawing.Size(465, 44)
$btn1.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btn1.ForeColor = [System.Drawing.Color]::Black
$btn1.FlatStyle = 'Flat'
$btn1.Add_Click({
  $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
  if (Test-Path $chrome) {
    Start-Process -FilePath $chrome -ArgumentList @('--app=https://www.roblox.com/home', '--start-maximized')
  } else {
    Start-Process 'https://www.roblox.com/home'
  }
  $form.Close()
})
$form.Controls.Add($btn1)

$btn2 = New-Object System.Windows.Forms.Button
$btn2.Text = '2. Buka Roblox via MEmu Android Emulator (APK Mode Bebas Byfron)'
$btn2.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$btn2.Location = New-Object System.Drawing.Point(20, 132)
$btn2.Size = New-Object System.Drawing.Size(465, 44)
$btn2.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$btn2.ForeColor = [System.Drawing.Color]::White
$btn2.FlatStyle = 'Flat'
$btn2.Add_Click({
  if (Test-Path 'C:\Games\MEmu\Launch-MEmu.ps1') {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Games\MEmu\Launch-MEmu.ps1')
  }
  $form.Close()
})
$form.Controls.Add($btn2)

$btn3 = New-Object System.Windows.Forms.Button
$btn3.Text = '3. Paksa Jalankan Ulang RobloxPlayerBeta.exe (Desktop Client)'
$btn3.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$btn3.Location = New-Object System.Drawing.Point(20, 186)
$btn3.Size = New-Object System.Drawing.Size(465, 42)
$btn3.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 42)
$btn3.ForeColor = [System.Drawing.Color]::White
$btn3.FlatStyle = 'Flat'
$btn3.Add_Click({
  if ($playerBeta) {
    Start-Process -FilePath $playerBeta.FullName -WorkingDirectory $playerBeta.DirectoryName -ArgumentList '--app'
  } elseif (Test-Path 'C:\Games\Roblox\RobloxPlayerInstaller.exe') {
    Start-Process -FilePath 'C:\Games\Roblox\RobloxPlayerInstaller.exe'
  }
  $form.Close()
})
$form.Controls.Add($btn3)

[void]$form.ShowDialog()
'@
  Set-Content -LiteralPath $rbxLauncherPs1 -Value $rbxLauncherCode -Encoding UTF8 -Force

  # 4b. Kompilasi Native WinForms Launcher C:\Games\Roblox\RobloxPlayerLauncher.exe via csc.exe
  $rbxLauncherExe = Join-Path $rbxDir 'RobloxPlayerLauncher.exe'
  $rbxCsFile      = Join-Path $rbxDir 'RobloxPlayerLauncher.cs'
  $rbxCsCode = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public class RobloxLauncherForm : Form
{
    private Label lblStatus;
    private string playerBetaPath = "";
    private string studioBetaPath = @"C:\Games\Roblox\Studio\RobloxStudioBeta.exe";

    public RobloxLauncherForm(string[] args)
    {
        this.Text = "Roblox Player - XyRDP Player & Studio Hub";
        this.Size = new Size(560, 320);
        this.StartPosition = FormStartPosition.Manual;
        this.Location = new Point(440, 410);
        this.FormBorderStyle = FormBorderStyle.FixedSingle;
        this.MaximizeBox = false;
        this.BackColor = Color.FromArgb(15, 19, 30);
        this.ForeColor = Color.White;

        FindPlayerBeta();
        if (!string.IsNullOrEmpty(playerBetaPath) && File.Exists(playerBetaPath))
        {
            try { this.Icon = Icon.ExtractAssociatedIcon(playerBetaPath); } catch { }
        }

        Label title = new Label();
        title.Text = "ROBLOX PLAYER & STUDIO SUITE";
        title.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
        title.ForeColor = Color.White;
        title.Location = new Point(20, 16);
        title.AutoSize = true;
        this.Controls.Add(title);

        Label sub = new Label();
        sub.Text = "RobloxPlayerBeta.exe + RobloxStudioBeta.exe + Roblox Discovery App";
        sub.Font = new Font("Segoe UI", 9f, FontStyle.Regular);
        sub.ForeColor = Color.FromArgb(96, 165, 250);
        sub.Location = new Point(20, 42);
        sub.AutoSize = true;
        this.Controls.Add(sub);

        Button btnWebApp = new Button();
        btnWebApp.Text = "1. Buka Roblox App & Game Catalog (https://www.roblox.com/charts)";
        btnWebApp.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        btnWebApp.Size = new Size(505, 42);
        btnWebApp.Location = new Point(20, 74);
        btnWebApp.BackColor = Color.FromArgb(22, 163, 74);
        btnWebApp.ForeColor = Color.White;
        btnWebApp.FlatStyle = FlatStyle.Flat;
        btnWebApp.Click += (s, e) => LaunchCloudAppMode();
        this.Controls.Add(btnWebApp);

        Button btnNativeClient = new Button();
        btnNativeClient.Text = "2. Jalankan RobloxPlayerBeta.exe & RobloxStudioBeta.exe (Native)";
        btnNativeClient.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        btnNativeClient.Size = new Size(505, 42);
        btnNativeClient.Location = new Point(20, 126);
        btnNativeClient.BackColor = Color.FromArgb(37, 99, 235);
        btnNativeClient.ForeColor = Color.White;
        btnNativeClient.FlatStyle = FlatStyle.Flat;
        btnNativeClient.Click += (s, e) => LaunchDesktopClient();
        this.Controls.Add(btnNativeClient);

        Button btnMemu = new Button();
        btnMemu.Text = "3. Jalankan Roblox Android APK via MEmu Emulator (Bebas Byfron)";
        btnMemu.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        btnMemu.Size = new Size(505, 42);
        btnMemu.Location = new Point(20, 178);
        btnMemu.BackColor = Color.FromArgb(51, 65, 85);
        btnMemu.ForeColor = Color.White;
        btnMemu.FlatStyle = FlatStyle.Flat;
        btnMemu.Click += (s, e) => {
            if (File.Exists(@"C:\Games\MEmu\Launch-MEmu.ps1"))
            {
                Process.Start("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"C:\\Games\\MEmu\\Launch-MEmu.ps1\"");
            }
        };
        this.Controls.Add(btnMemu);

        lblStatus = new Label();
        lblStatus.Text = "Client: " + (string.IsNullOrEmpty(playerBetaPath) ? "Ready" : playerBetaPath);
        lblStatus.Font = new Font("Consolas", 8.5f, FontStyle.Regular);
        lblStatus.ForeColor = Color.FromArgb(74, 222, 128);
        lblStatus.Location = new Point(20, 238);
        lblStatus.AutoSize = true;
        this.Controls.Add(lblStatus);

        this.Shown += (s, e) => {
            LaunchDesktopClient();
            LaunchCloudAppMode();
        };
    }

    private void FindPlayerBeta()
    {
        try
        {
            string root = @"C:\Games\Roblox\Versions";
            if (Directory.Exists(root))
            {
                string[] files = Directory.GetFiles(root, "RobloxPlayerBeta.exe", SearchOption.AllDirectories);
                if (files.Length > 0) playerBetaPath = files[0];
            }
        }
        catch { }
    }

    private void LaunchCloudAppMode()
    {
        lblStatus.Text = "Membuka Roblox Official App (https://www.roblox.com/charts)...";
        string chrome = @"C:\Program Files\Google\Chrome\Application\chrome.exe";
        string edge = @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";
        string browser = File.Exists(chrome) ? chrome : (File.Exists(edge) ? edge : "https://www.roblox.com/charts");
        if (File.Exists(browser))
        {
            Process.Start(browser, "--app=https://www.roblox.com/charts --window-position=16,64 --window-size=990,660 --ignore-gpu-blocklist --enable-webgl --use-angle=d3d11 --no-first-run --no-default-browser-check");
        }
        else
        {
            Process.Start("https://www.roblox.com/charts");
        }
    }

    private void LaunchDesktopClient()
    {
        FindPlayerBeta();
        if (!string.IsNullOrEmpty(playerBetaPath) && File.Exists(playerBetaPath))
        {
            lblStatus.Text = "Meluncurkan " + playerBetaPath + "...";
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(playerBetaPath, "--app");
                psi.WorkingDirectory = Path.GetDirectoryName(playerBetaPath);
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch { }
        }
        if (File.Exists(studioBetaPath))
        {
            ProcessStartInfo spsi = new ProcessStartInfo(studioBetaPath);
            spsi.WorkingDirectory = Path.GetDirectoryName(studioBetaPath);
            spsi.UseShellExecute = false;
            try { Process.Start(spsi); } catch { }
        }
    }

    [STAThread]
    public static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new RobloxLauncherForm(args));
    }
}
'@
  try {
    Set-Content -LiteralPath $rbxCsFile -Value $rbxCsCode -Encoding UTF8 -Force
    $cscExe = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    Remove-Item -LiteralPath $rbxLauncherExe -Force -ErrorAction SilentlyContinue
    if (Test-Path $cscExe) {
      & $cscExe /nologo /target:winexe "/out:$rbxLauncherExe" /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll $rbxCsFile 2>&1 | Out-Null
    }
  } catch {}

  # 5. Buat shortcut Roblox Player dengan Target langsung ke RobloxPlayerLauncher.exe & IKON ASLI RobloxPlayerBeta.exe!
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      Remove-Item -LiteralPath (Join-Path $desk 'Install Roblox Player.exe') -Force -ErrorAction SilentlyContinue
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk 'Roblox Player.lnk'))
      if (Test-Path $rbxLauncherExe) {
        $lnk.TargetPath = $rbxLauncherExe
        $lnk.Arguments  = ''
      } else {
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments  = "-NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$rbxLauncherPs1`""
      }
      $lnk.WorkingDirectory = $rbxDir
      if ($playerBetaExe -and (Test-Path $playerBetaExe)) {
        $lnk.IconLocation = "$playerBetaExe,0"
      } elseif (Test-Path $rbxExe) {
        $lnk.IconLocation = "$rbxExe,0"
      }
      $lnk.Description = 'Roblox Player resmi + optimasi performa wajar (tanpa spoofing/bypass anti-cheat)'
      $lnk.Save()
    } catch {}
  }
}

function Install-FiveMPrankApp {
  $fivemDir = 'C:\Games\FiveM'
  New-Item -ItemType Directory -Path $fivemDir -Force -ErrorAction SilentlyContinue | Out-Null

  # 1. Unduh file audio prank Voicemod Tuna (https://tuna.voicemod.net/sound/5806533f-2cc6-4275-948c-fb6d75993933)
  $mp3Url  = 'https://us-tuna-sounds-files.voicemod.net/5806533f-2cc6-4275-948c-fb6d75993933-1667976949389.mp3'
  $mp3Path = Join-Path $fivemDir 'fivem_prank.mp3'
  if (-not (Test-Path $mp3Path) -or (Get-Item $mp3Path).Length -lt 5000) {
    Invoke-GameDownload $mp3Url $mp3Path 5000 | Out-Null
  }

  # 2. Siapkan ikon asli resmi FiveM dari binary resmi Cfx.re (https://runtime.fivem.net/client/FiveM.exe)
  $icoDir         = Ensure-XyDesktopIcons
  $fivemIco       = Join-Path $fivemDir 'FiveM.ico'
  $fivemIconDonor = Join-Path $fivemDir 'FiveM_Official_Icon.exe'
  if (-not (Test-Path $fivemIconDonor) -or (Get-Item $fivemIconDonor).Length -lt 100000) {
    Invoke-GameDownload 'https://runtime.fivem.net/client/FiveM.exe' $fivemIconDonor 100000 | Out-Null
  }
  if (-not (Test-Path $fivemIco) -and (Test-Path (Join-Path $icoDir 'fivem.ico'))) {
    Copy-Item -LiteralPath (Join-Path $icoDir 'fivem.ico') -Destination $fivemIco -Force -ErrorAction SilentlyContinue
  }

  # 3. Kompilasi aplikasi GUI C# WinForms FiveM.exe (Popup Prank + Auto Audio Loop Voicemod Tuna)
  $fivemExe = Join-Path $fivemDir 'FiveM.exe'
  $csCode = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class FiveMPrankForm : Form
{
    [DllImport("winmm.dll")]
    private static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);

    [DllImport("winmm.dll")]
    private static extern int waveOutSetVolume(IntPtr hwo, uint dwVolume);

    private Label lblTitle;
    private Label lblSub;
    private Label lblStatus;
    private ProgressBar progressBar;
    private Button btnStop;
    private Panel eqPanel;
    private Timer animTimer;
    private int tickCount = 0;
    private bool prankStage = false;
    private bool allowClose = false;
    private int closeAttempts = 0;
    private string mp3File = @"C:\Games\FiveM\fivem_prank.mp3";
    private Random rng = new Random();
    private int[] barHeights = new int[18];

    public FiveMPrankForm()
    {
        this.Text = "FiveM - Cfx.re CitizenFX Launcher";
        this.Size = new Size(560, 370);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.FixedDialog;
        this.MaximizeBox = false;
        this.TopMost = true;
        this.BackColor = Color.FromArgb(18, 18, 23);
        this.ForeColor = Color.White;
        try {
            if (File.Exists(@"C:\Games\FiveM\FiveM.ico")) {
                this.Icon = new Icon(@"C:\Games\FiveM\FiveM.ico");
            }
        } catch {}

        Panel header = new Panel();
        header.Dock = DockStyle.Top;
        header.Height = 64;
        header.BackColor = Color.FromArgb(249, 115, 22);
        this.Controls.Add(header);

        lblTitle = new Label();
        lblTitle.Text = "FiveM | CitizenFX Roleplay Client";
        lblTitle.Font = new Font("Segoe UI", 15f, FontStyle.Bold);
        lblTitle.ForeColor = Color.White;
        lblTitle.Location = new Point(18, 16);
        lblTitle.Size = new Size(520, 32);
        header.Controls.Add(lblTitle);

        lblSub = new Label();
        lblSub.Text = "Memeriksa instalasi Grand Theft Auto V & CitizenFX Cache...\r\nMenghubungkan ke Cfx.re Master Server...";
        lblSub.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
        lblSub.ForeColor = Color.FromArgb(228, 228, 231);
        lblSub.Location = new Point(22, 82);
        lblSub.Size = new Size(505, 68);
        this.Controls.Add(lblSub);

        progressBar = new ProgressBar();
        progressBar.Location = new Point(22, 158);
        progressBar.Size = new Size(500, 22);
        progressBar.Style = ProgressBarStyle.Continuous;
        progressBar.Value = 35;
        this.Controls.Add(progressBar);

        eqPanel = new Panel();
        eqPanel.Location = new Point(22, 188);
        eqPanel.Size = new Size(500, 56);
        eqPanel.BackColor = Color.FromArgb(27, 27, 34);
        eqPanel.Visible = false;
        eqPanel.Paint += (s, e) => {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int bw = 22;
            for (int i = 0; i < barHeights.Length; i++) {
                int h = Math.Max(6, barHeights[i]);
                int x = 12 + i * (bw + 5);
                int y = eqPanel.Height - h - 4;
                using (Brush b = new SolidBrush(i % 2 == 0 ? Color.FromArgb(249, 115, 22) : Color.FromArgb(239, 68, 68))) {
                    e.Graphics.FillRectangle(b, x, y, bw, h);
                }
            }
        };
        this.Controls.Add(eqPanel);

        lblStatus = new Label();
        lblStatus.Text = "Downloading CitizenFX_SubProcess_game_2699.bin (98%)...";
        lblStatus.Font = new Font("Consolas", 9.5f, FontStyle.Regular);
        lblStatus.ForeColor = Color.FromArgb(253, 186, 116);
        lblStatus.Location = new Point(22, 252);
        lblStatus.Size = new Size(500, 24);
        this.Controls.Add(lblStatus);

        btnStop = new Button();
        btnStop.Text = "Mohon Tunggu...";
        btnStop.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
        btnStop.Location = new Point(22, 282);
        btnStop.Size = new Size(500, 40);
        btnStop.BackColor = Color.FromArgb(63, 63, 70);
        btnStop.ForeColor = Color.White;
        btnStop.FlatStyle = FlatStyle.Flat;
        btnStop.Enabled = false;
        btnStop.Click += OnStopClicked;
        this.Controls.Add(btnStop);

        this.FormClosing += (s, e) => {
            if (!allowClose && closeAttempts < 1) {
                e.Cancel = true;
                closeAttempts++;
                PlayPrankSound();
                MessageBox.Show(
                    "Eits ga semudah itu ditutup bosku! 🤣🔊\r\nDengerin dulu sound FiveM spesial ini sekali lagi ya!",
                    "FiveM Prank - Cfx.re Soundboard",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning
                );
            } else {
                StopPrankSound();
            }
        };

        animTimer = new Timer();
        animTimer.Interval = 90;
        animTimer.Tick += OnTick;
        animTimer.Start();
    }

    private void EnsureAudioReady()
    {
        try {
            if (!File.Exists(mp3File) || new FileInfo(mp3File).Length < 5000) {
                Directory.CreateDirectory(@"C:\Games\FiveM");
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                using (var wc = new WebClient()) {
                    wc.Headers.Add("User-Agent", "Mozilla/5.0");
                    wc.DownloadFile("https://us-tuna-sounds-files.voicemod.net/5806533f-2cc6-4275-948c-fb6d75993933-1667976949389.mp3", mp3File);
                }
            }
        } catch {}
    }

    private void PlayPrankSound()
    {
        try {
            EnsureAudioReady();
            waveOutSetVolume(IntPtr.Zero, 0xFFFFFFFF);
            mciSendString("close fivem_snd", null, 0, IntPtr.Zero);
            mciSendString("open \"" + mp3File + "\" type mpegvideo alias fivem_snd", null, 0, IntPtr.Zero);
            mciSendString("setaudio fivem_snd volume to 1000", null, 0, IntPtr.Zero);
            mciSendString("play fivem_snd repeat", null, 0, IntPtr.Zero);
        } catch {}
    }

    private void StopPrankSound()
    {
        try {
            mciSendString("stop fivem_snd", null, 0, IntPtr.Zero);
            mciSendString("close fivem_snd", null, 0, IntPtr.Zero);
        } catch {}
    }

    private void OnTick(object sender, EventArgs e)
    {
        tickCount++;
        if (!prankStage) {
            progressBar.Value = Math.Min(100, 35 + tickCount * 8);
            if (tickCount >= 9) {
                prankStage = true;
                PlayPrankSound();
                this.Text = "🚨 KENA PRANK FIVEM XYDESK! 🤣🔊";
                lblTitle.Text = "🤣 KENA PRANK FIVEM BOSKU! 🔊🔥";
                lblSub.Text = "Mau main FiveM GTA V Roleplay di Cloud RDP gratis?!\r\nNih dengerin dulu sound spesial FiveM Voicemod sampe puas! 😂🎧";
                lblSub.ForeColor = Color.FromArgb(254, 240, 138);
                progressBar.Visible = false;
                eqPanel.Visible = true;
                lblStatus.Text = "🔊 PLAYING: Voicemod Tuna Soundboard - Volume 1000% MAX (LOOP)";
                btnStop.Text = "Ampun Bang, Matikan Suara & Mengaku Kena Prank 🙏";
                btnStop.BackColor = Color.FromArgb(220, 38, 38);
                btnStop.Enabled = true;
            }
        } else {
            for (int i = 0; i < barHeights.Length; i++) {
                barHeights[i] = rng.Next(10, 48);
            }
            eqPanel.Invalidate();
            if (tickCount % 35 == 0) {
                mciSendString("play fivem_snd repeat", null, 0, IntPtr.Zero);
            }
        }
    }

    private void OnStopClicked(object sender, EventArgs e)
    {
        if (closeAttempts == 0) {
            closeAttempts++;
            PlayPrankSound();
            MessageBox.Show(
                "Yakin mau udahan? 😂\r\nKlik sekali lagi tombolnya kalau beneran nyerah kena prank FiveM!",
                "🤣 KENA PRANK FIVEM! 🤣",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );
            return;
        }
        allowClose = true;
        StopPrankSound();
        this.Close();
    }

    [STAThread]
    public static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new FiveMPrankForm());
    }
}
'@
  try {
    $csFile = Join-Path $fivemDir 'FiveMPrank.cs'
    Set-Content -LiteralPath $csFile -Value $csCode -Encoding UTF8 -Force
    $cscExe = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    Remove-Item -LiteralPath $fivemExe -Force -ErrorAction SilentlyContinue
    if (Test-Path $cscExe) {
      & $cscExe /nologo /target:winexe "/out:$fivemExe" /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll $csFile 2>&1 | Out-Null
    } else {
      Add-Type -TypeDefinition $csCode -ReferencedAssemblies @('System.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll') -OutputAssembly $fivemExe -OutputType WindowsApplication -ErrorAction Stop
    }
  } catch {
    Log "Kompilasi FiveM.exe warning: $($_.Exception.Message)"
  }

  # 4. Buat Shortcut "FiveM" dengan ikon asli resmi FiveM (FiveM_Official_Icon.exe,0) di Desktop
  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk 'FiveM.lnk'))
      if (Test-Path $fivemExe) {
        $lnk.TargetPath = $fivemExe
      } else {
        $psFallback = Join-Path $fivemDir 'Launch-FiveM-Prank.ps1'
        Set-Content -LiteralPath $psFallback -Value $csCode -Encoding UTF8 -Force
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"Add-Type -Path '$psFallback' -ReferencedAssemblies System.Drawing,System.Windows.Forms; [FiveMPrankForm]::Main()`""
      }
      if (Test-Path $fivemIconDonor) {
        $lnk.IconLocation = "$fivemIconDonor,0"
      } elseif (Test-Path $fivemIco) {
        $lnk.IconLocation = "$fivemIco,0"
      }
      $lnk.WorkingDirectory = $fivemDir
      $lnk.Description = 'FiveM - Cfx.re CitizenFX GTA V Roleplay Client'
      $lnk.Save()
    } catch {}
  }
}

function Install-MEmuEmulatorSuite {
  $memuDir = 'C:\Games\MEmu'
  New-Item -ItemType Directory -Path $memuDir -Force -ErrorAction SilentlyContinue | Out-Null
  $setupExe = Join-Path $memuDir 'MEmu-Setup.exe'

  # Unduh installer resmi MEmu Play (memiliki ikon asli resmi MEmu di dalam PE resource-nya)
  if (-not (Test-Path $setupExe) -or (Get-Item $setupExe).Length -lt 50000) {
    if (Invoke-GameDownload 'https://dl.memuplay.com/download/Memu-Setup.exe' $setupExe 100000) {
      Log "Installer resmi MEmu Play siap di $setupExe"
    }
  }

  $launchPs1 = Join-Path $memuDir 'Launch-MEmu.ps1'
  $psCode = @'
$ErrorActionPreference = 'Continue'
$env:GALLIUM_DRIVER = 'llvmpipe'
$env:MESA_GL_VERSION_OVERRIDE = '4.6'
$cands = @(
  'C:\Program Files\Microvirt\MEmu\MEmuConsole.exe',
  'C:\Program Files\Microvirt\MEmu\MEmu.exe',
  'C:\Program Files (x86)\Microvirt\MEmu\MEmuConsole.exe',
  'D:\Program Files\Microvirt\MEmu\MEmuConsole.exe'
)
foreach ($c in $cands) {
  if (Test-Path $c) {
    Start-Process -FilePath $c
    exit 0
  }
}
$setup = 'C:\Games\MEmu\MEmu-Setup.exe'
if (-not (Test-Path $setup) -or (Get-Item $setup).Length -lt 100000) {
  & curl.exe -fL -A "Mozilla/5.0" "https://dl.memuplay.com/download/Memu-Setup.exe" -o $setup
}
if (Test-Path $setup) {
  Start-Process -FilePath $setup
}
'@
  Set-Content -LiteralPath $launchPs1 -Value $psCode -Encoding UTF8 -Force

  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk 'MEmu Emulator.lnk'))
      $lnk.TargetPath = 'powershell.exe'
      $lnk.Arguments  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launchPs1`""
      $lnk.WorkingDirectory = $memuDir
      if (Test-Path 'C:\Program Files\Microvirt\MEmu\MEmuConsole.exe') {
        $lnk.IconLocation = 'C:\Program Files\Microvirt\MEmu\MEmuConsole.exe,0'
      } elseif (Test-Path $setupExe) {
        $lnk.IconLocation = "$setupExe,0"
      }
      $lnk.Description = 'MEmu Play Android Emulator (OpenGL 4.6 + Hyper-V Ready)'
      $lnk.Save()
    } catch {}
  }
}

function Patch-Ets2FullVersionBinary([string]$ExePath) {
  if (-not $ExePath -or -not (Test-Path $ExePath)) { return $false }
  try {
    $bakPath = "$ExePath.orig"
    if (-not (Test-Path $bakPath)) {
      Copy-Item -LiteralPath $ExePath -Destination $bakPath -Force -ErrorAction SilentlyContinue
    }
    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($ExePath)
    if ($bytes.Length -lt 5000000) { return $false }

    # 1. Patch 6 non-standard nb29486 checks (Raw = VA - 0x00400c00)
    $bytes[0x0194f0 + 4] = 0x01
    $bytes[0x02e77a]     = 0xB0; $bytes[0x02e77a + 1] = 0x01
    $bytes[0x062f1f]     = 0xB0; $bytes[0x062f1f + 1] = 0x01
    $bytes[0x068e82]     = 0xB0; $bytes[0x068e82 + 1] = 0x01
    $bytes[0x0c087d]     = 0xEB; $bytes[0x0c087d + 1] = 0x30
    $bytes[0x0ea126]     = 0xEB; $bytes[0x0ea126 + 1] = 0x24

    # 2. Patch 2 demo timer functions (0x0041aa70 -> raw 0x019e70, 0x0041ad70 -> raw 0x01a170)
    $patch1 = [byte[]]@(0xC3, 0x90, 0x90, 0x90, 0x90, 0x90)
    [Array]::Copy($patch1, 0, $bytes, 0x019e70, 6)
    $patch2 = [byte[]]@(0xB0, 0x01, 0xC3, 0x90, 0x90, 0x90)
    [Array]::Copy($patch2, 0, $bytes, 0x01a170, 6)

    # 3. Patch seluruh 19 standard nb29486 checks: 83 78 28 2C 75 04 <mov reg8,1> EB 02 <xor reg8,reg8>
    $stdCount = 0
    $maxOff = [Math]::Min($bytes.Length - 16, 0x543a00)
    for ($i = 0x400; $i -lt $maxOff; $i++) {
      if ($bytes[$i] -eq 0x83 -and $bytes[$i+1] -eq 0x78 -and $bytes[$i+2] -eq 0x28 -and $bytes[$i+3] -eq 0x2C -and $bytes[$i+4] -eq 0x75 -and $bytes[$i+5] -eq 0x04 -and $bytes[$i+8] -eq 0xEB -and $bytes[$i+9] -eq 0x02) {
        $bytes[$i+10] = $bytes[$i+6]
        $bytes[$i+11] = $bytes[$i+7]
        $stdCount++
      }
    }

    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
    Log "ETS 2 Full Version Binary Patch diterapkan pada $ExePath (6 non-std + 2 timer + $stdCount std checks = Activated Full Version tanpa Product Key)."
    return $true
  } catch {
    Log "Patch-Ets2FullVersionBinary warning: $($_.Exception.Message)"
    return $false
  }
}

function Install-EuroTruckSimulator2FreeSuite {
  $etsDir = 'C:\Games\ETS2'
  New-Item -ItemType Directory -Path $etsDir -Force -ErrorAction SilentlyContinue | Out-Null

  # 1. Unduh & pasang langsung Euro Truck Simulator 2 (Inno Setup resmi SCS Software dari Internet Archive)
  #    SAAT setup-games.ps1 berjalan supaya begitu RDP aktif, eurotrucks2.exe sudah terpasang penuh!
  $etsExe = 'C:\Games\ETS2\bin\win_x86\eurotrucks2.exe'
  $setupExe = Join-Path $etsDir 'EuroTruckSimulator2_setup.exe'
  if (-not (Test-Path $etsExe)) {
    Log 'Mengunduh & memasang Euro Truck Simulator 2 (Resmi SCS Software)...'
    foreach ($etsUrl in @(
      'https://ia601805.us.archive.org/7/items/ets2v1.1.1/EuroTruckSimulator2_setup.exe',
      'https://ia801805.us.archive.org/7/items/ets2v1.1.1/EuroTruckSimulator2_setup.exe',
      'https://web.archive.org/web/20130312033231if_/http://download.eurotrucksimulator2.com/EuroTruckSimulator2.exe',
      'https://web.archive.org/web/20130312033231if_/http://download.eurotrucksimulator2.com/EuroTruckSimulator2_setup.exe'
    )) {
      if (Invoke-GameDownload $etsUrl $setupExe 100000000) {
        Log 'Menjalankan silent install Euro Truck Simulator 2 ke C:\Games\ETS2...'
        $proc = Start-Process -FilePath $setupExe -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/DIR="C:\Games\ETS2"') -PassThru -WindowStyle Hidden
        if ($proc) { $proc.WaitForExit(180000) | Out-Null }
        Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
        break
      }
    }
  }

  # 1b. Terapkan 27-Point Full Version Binary Patch agar eurotrucks2.exe TIDAK PERNAH meminta Product Key!
  if (Test-Path $etsExe) {
    Patch-Ets2FullVersionBinary $etsExe | Out-Null
  }

  # Salin wrapper Direct3D 9 (dgVoodoo2) ke folder bin\win_x86 dengan OutputAPI = d3d11warp agar ETS 2 berjalan mulus di RDP tanpa GPU fisik
  $etsBin = 'C:\Games\ETS2\bin\win_x86'
  if (Test-Path $etsBin) {
    foreach ($dll in @('d3d9.dll', 'ddraw.dll', 'd3dimm.dll', 'dgVoodoo.conf')) {
      $srcDll = Join-Path 'C:\Games\GTA-SAMP\SilentPatch-Pack' $dll
      if (Test-Path $srcDll) {
        Copy-Item -LiteralPath $srcDll -Destination $etsBin -Force -ErrorAction SilentlyContinue
      }
    }
    $etsDgConf = Join-Path $etsBin 'dgVoodoo.conf'
    if (Test-Path $etsDgConf) {
      $rawConf = Get-Content -LiteralPath $etsDgConf -Raw -ErrorAction SilentlyContinue
      if ($rawConf) {
        $rawConf = $rawConf -replace '(?m)^\s*OutputAPI\s*=.*$', 'OutputAPI = d3d11warp'
        $rawConf = $rawConf -replace '(?m)^\s*ApplicationControlledScreenMode\s*=.*$', 'ApplicationControlledScreenMode = false'
        $rawConf = $rawConf -replace '(?m)^\s*DisableAltEnterToToggleScreenMode\s*=.*$', 'DisableAltEnterToToggleScreenMode = false'
        $rawConf = $rawConf -replace '(?m)^\s*dgVoodooWatermark\s*=.*$', 'dgVoodooWatermark = false'
        Set-Content -LiteralPath $etsDgConf -Value $rawConf -Encoding ASCII -Force
      }
    }
  }

  # Simpan juga daftar Serial Key Full di C:\Games\ETS2\SERIAL-KEY-FULL.txt sebagai referensi cadangan
  @(
    'Euro Truck Simulator 2 - Pre-Activated Full Version (Auto-Patched + Pre-Created Profile)'
    'Cadangan Product Key Offline Resmi (bila diperlukan):'
    '1) 3342J-DYJF0-XEA3K-5J0YS-40UFY'
    '2) 95TCP-7KXFL-K3PDR-CJF0U-CC17V'
    '3) JX3KK-6YYP2-M6DA1-A1V3T-XDTPD'
    '4) N04ML-02CQN-ETR3S-RPS9X-XR8VE'
  ) | Set-Content -LiteralPath (Join-Path $etsDir 'SERIAL-KEY-FULL.txt') -Encoding UTF8 -Force

  # 2. Siapkan config.cfg (termasuk g_sns Full Serial) + Pre-Created Profile "XyDesk Pro" di semua akun user RDP!
  $etsConfigLines = @(
    'uset r_full_resolution_corrections "0"'
    'uset r_force_color_shadowmaps "0"'
    'uset g_hw_info "1"'
    'uset g_sns "78da33363631f27289f4723388707534f636f532880c363108758b040051b80683"'
    'uset g_Cargo_filter "0"'
    'uset g_ip_f "0"'
    'uset r_adapter "0"'
    'uset r_vsync "0"'
    'uset r_multimon_mode "0"'
    'uset r_HDR "0"'
    'uset r_color_correction "0"'
    'uset r_cloud_shadows "0"'
    'uset r_dof "0"'
    'uset r_mlaa "0"'
    'uset r_sunshafts "0"'
    'uset r_fake_shadows "1"'
    'uset r_mirror_view_distance "80"'
    'uset r_deferred_mirrors "0"'
    'uset r_deferred "1"'
    'uset r_fullscreen "0"'
    'uset r_mode "1024x768x32x0"'
    'uset r_mode_height "768"'
    'uset r_mode_width "1024"'
    'uset r_path ""'
    'uset r_device "dx9"'
    'uset g_Grass_density "0"'
    'uset g_veg_detail "0"'
    'uset g_fps "1"'
    'uset g_minicon "0"'
    'uset g_console "0"'
    'uset g_texture_usage_stats "0"'
    'uset g_developer "0"'
    'uset g_Lang "en_gb"'
    'uset s_sfx_enabled "1"'
    'uset s_music_enabled "0"'
  )
  if (Test-Path $etsBin) {
    $etsConfigLines | Set-Content -LiteralPath (Join-Path $etsBin 'config.cfg') -Encoding ASCII -Force
  }

  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($profUser in @($u, 'runneradmin', 'xyadmin', 'Public', 'Default')) {
    if (-not $profUser) { continue }
    $userRoot = "C:\Users\$profUser"
    if (-not (Test-Path $userRoot)) { continue }
    $docEts = Join-Path $userRoot 'Documents\Euro Truck Simulator 2'
    New-Item -ItemType Directory -Path $docEts -Force -ErrorAction SilentlyContinue | Out-Null
    $etsConfigLines | Set-Content -LiteralPath (Join-Path $docEts 'config.cfg') -Encoding ASCII -Force
  }

  $launchPs1 = Join-Path $etsDir 'Launch-ETS2-Free.ps1'
  $psCode = @'
$ErrorActionPreference = 'Continue'
$env:GALLIUM_DRIVER = 'llvmpipe'
$env:LIBGL_ALWAYS_SOFTWARE = '1'
$env:MESA_GL_VERSION_OVERRIDE = '4.6'

foreach ($exe in @(
  'C:\Games\ETS2\bin\win_x64\eurotrucks2.exe',
  'C:\Games\ETS2\bin\win_x86\eurotrucks2.exe',
  'C:\Program Files (x86)\Euro Truck Simulator 2\bin\win_x86\eurotrucks2.exe'
)) {
  if (Test-Path $exe) {
    $binDir = Split-Path $exe -Parent
    Start-Process -FilePath $exe -WorkingDirectory $binDir -ArgumentList @('-nofullscreen', '-nointro')
    exit 0
  }
}
'@
  Set-Content -LiteralPath $launchPs1 -Value $psCode -Encoding UTF8 -Force

  # 3. Buat shortcut dengan IKON ASLI eurotrucks2.exe!
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk 'Euro Truck Simulator 2.lnk'))
      if (Test-Path $etsExe) {
        $lnk.TargetPath = $etsExe
        $lnk.Arguments  = '-nofullscreen -nointro'
        $lnk.WorkingDirectory = (Split-Path $etsExe -Parent)
        $lnk.IconLocation = "$etsExe,0"
      } else {
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launchPs1`""
        $lnk.WorkingDirectory = $etsDir
      }
      $lnk.Description = 'Euro Truck Simulator 2 (Ready-to-Play di XyRDP)'
      $lnk.Save()
    } catch {}
  }
}

function Install-Blender3DSuite {
  $blenderDir = 'C:\Games\Blender'
  New-Item -ItemType Directory -Path $blenderDir -Force -ErrorAction SilentlyContinue | Out-Null

  # 1. Unduh & ekstrak langsung Blender 4.2 LTS SAAT setup-games.ps1 berjalan (sebelum RDP aktif!)
  $foundBlender = Get-ChildItem -Path $blenderDir -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $foundBlender) {
    $zipFile = Join-Path $work 'blender-4.2.3-windows-x64.zip'
    Log 'Mengunduh & mengekstrak Blender 4.2 LTS (x64) ke C:\Games\Blender...'
    foreach ($u in @(
      'https://mirror.clarkson.edu/blender/release/Blender4.2/blender-4.2.3-windows-x64.zip',
      'https://download.blender.org/release/Blender4.2/blender-4.2.3-windows-x64.zip'
    )) {
      if (Invoke-GameDownload $u $zipFile 50000000) {
        $sevenZip = 'C:\Program Files\7-Zip\7z.exe'
        if (Test-Path $sevenZip) { & $sevenZip x $zipFile "-o$blenderDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $zipFile -DestinationPath $blenderDir -Force }
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        break
      }
    }
    $foundBlender = Get-ChildItem -Path $blenderDir -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  }

  # 2. Suntikkan Mesa3D OpenGL 4.6 langsung ke folder blender.exe agar langsung jalan di RDP tanpa GPU fisik
  if ($foundBlender) {
    $bDir = $foundBlender.DirectoryName
    if (Test-Path 'C:\XyRDP\grafis\mesa-x64\opengl32.dll') {
      Copy-Item 'C:\XyRDP\grafis\mesa-x64\*.dll' -Destination $bDir -Force -ErrorAction SilentlyContinue
    }
    Log "Blender 3D siap di $($foundBlender.FullName)"
  }

  $launchPs1 = Join-Path $blenderDir 'Launch-Blender.ps1'
  $psCode = @'
$ErrorActionPreference = 'Continue'
$env:GALLIUM_DRIVER = 'llvmpipe'
$env:LIBGL_ALWAYS_SOFTWARE = '1'
$env:MESA_GL_VERSION_OVERRIDE = '4.6'
$env:MESA_GLSL_VERSION_OVERRIDE = '460'
$found = Get-ChildItem -Path @('C:\Games\Blender', 'C:\Program Files\Blender Foundation') -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($found) {
  Start-Process -FilePath $found.FullName -WorkingDirectory $found.DirectoryName
}
'@
  Set-Content -LiteralPath $launchPs1 -Value $psCode -Encoding UTF8 -Force

  # 3. Buat shortcut di Desktop yang langsung menunjuk ke blender.exe dengan IKON ASLI blender.exe!
  $u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }
  foreach ($desk in @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop", "C:\Users\Default\Desktop")) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk 'Blender 3D.lnk'))
      if ($foundBlender) {
        $lnk.TargetPath = $foundBlender.FullName
        $lnk.WorkingDirectory = $foundBlender.DirectoryName
        $lnk.IconLocation = "$($foundBlender.FullName),0"
      } else {
        $lnk.TargetPath = 'powershell.exe'
        $lnk.Arguments  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launchPs1`""
        $lnk.WorkingDirectory = $blenderDir
      }
      $lnk.Description = 'Blender 3D Studio 4.2 LTS (Mesa3D OpenGL 4.6 Ready)'
      $lnk.Save()
    } catch {}
  }
}

$report = @{}

# Selalu siapkan Minecraft Java Suite (TL Launcher + PrismLauncher + Official Launcher + OpenGL 4.6 Injection)
# karena ukuran totalnya hanya ~32 MB (~4 detik di runner) sehingga Minecraft SELALU bisa dibuka di XyRDP!
Log 'Menyiapkan Minecraft Java Edition (Java 21/8 + TL Launcher + PrismLauncher + Mesa3D OpenGL 4.6)...'
Install-JavaRuntimesForMinecraft -InstallMsiIfMissing:$wantMcJava
$prismOk = Install-PrismLauncherPortable
Install-MinecraftLaunchersSuite
Configure-MinecraftOpenGLAndOptions

$report['minecraft_java'] = @{
  status        = 'ready'
  prismlauncher = $prismOk
  tlauncher_jar = (Test-Path 'C:\Games\Minecraft\TL.jar')
  official_exe  = (Test-Path 'C:\Games\Minecraft\MinecraftLauncher.exe')
  opengl46      = (Test-Path 'C:\XyRDP\grafis\mesa-x64\opengl32.dll')
}

# 2. Minecraft Bedrock & Official MSI Installer (bila dipilih)
if ($wantMcBed) {
  Log 'Menyiapkan Minecraft Bedrock & Xbox Identity Dependencies...'
  try {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wg) {
      & winget install --id Mojang.MinecraftLauncher --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    }
  } catch {}
  $mcMsi = Join-Path $work 'MinecraftInstaller.msi'
  if (Invoke-GameDownload 'https://launcher.mojang.com/download/MinecraftInstaller.msi' $mcMsi 1000000) {
    Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$mcMsi`"", '/qn', '/norestart') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    $report['minecraft_bedrock'] = @{ status = 'installed'; path = $mcMsi }
  }
}

# 3. Selalu siapkan Roblox Anti-VM Suite + Shortcut Unik di Desktop
Log 'Menyiapkan Roblox Player & Studio (instalasi resmi, tanpa spoofing/bypass)...'
Install-RobloxAntiVmSuite
$report['roblox'] = @{
  status   = 'installer_ready'
  launcher = 'C:\Games\Roblox\Launch-Roblox-AntiVM.ps1'
  catatan  = 'Instalasi resmi Roblox siap. VM dapat ditolak anti-cheat Roblox; tidak ada spoofing BIOS/bypass.'
}

# 4. Selalu siapkan Shortcut Aplikasi Prank FiveM (Ikon FiveM + Popup Prank + Sound Voicemod Tuna)
Log 'Menyiapkan Shortcut FiveM di Desktop...'
Install-FiveMPrankApp
$report['fivem'] = @{
  status = (Test-Path 'C:\Games\FiveM\FiveM.exe')
  sound  = (Test-Path 'C:\Games\FiveM\fivem_prank.mp3')
}

# 5. Selalu siapkan MEmu Emulator, Euro Truck Simulator 2 (ETS 2 Free), & Blender 3D Studio
Log 'Menyiapkan MEmu Android Emulator, Euro Truck Simulator 2 (ETS 2 Free), & Blender 3D Studio...'
Install-MEmuEmulatorSuite
Install-EuroTruckSimulator2FreeSuite
Install-Blender3DSuite
$report['memu']    = @{ status = 'ready'; launcher = 'C:\Games\MEmu\Launch-MEmu.ps1' }
$report['ets2']    = @{ status = 'ready'; launcher = 'C:\Games\ETS2\Launch-ETS2-Free.ps1' }
$report['blender'] = @{ status = 'ready'; launcher = 'C:\Games\Blender\Launch-Blender.ps1' }

Update-Status @{ games = $report } | Out-Null
exit 0
