# ============================================================================
#  setup-studio-3d.ps1 - Studio 3D & Kreator + Utilitas Pendukung
#                        (Blender 3D 4.2 LTS, Roblox Studio, WebView2, FFmpeg)
# ----------------------------------------------------------------------------
#  Catatan Penting:
#  - BUKAN suite game (GTA/SA-MP/Roblox Player/Minecraft/MuMu tetap DIHAPUS).
#  - Hanya memasang aplikasi Studio kreatif & utilitas pendukung yang diminta:
#      1) Microsoft Edge WebView2 Runtime (wajib untuk login & UI Roblox Studio)
#      2) FFmpeg CLI di PATH (dibutuhkan Blender 3D untuk render video MP4/H.264)
#      3) Blender 3D 4.2 LTS + injeksi Mesa3D OpenGL 4.6 (llvmpipe)
#      4) Roblox Studio resmi (WindowsStudio64 - bebas masalah Hyper-V VM)
# ============================================================================

$XyTag = 'XyRDP:studio3d'
. "$PSScriptRoot/lib-common.ps1"

$skip = $false
if ($env:STUDIO_TOOLS) {
  $v = $env:STUDIO_TOOLS.Trim().ToLower()
  if (@('tidak', '0', 'false', 'no', 'off', 'skip', 'none') -contains $v) { $skip = $true }
}
if ($skip) {
  Log 'STUDIO_TOOLS=tidak - pemasangan Blender 3D & Roblox Studio dilewati.'
  Update-Status @{ studio_3d = @{ blender = 'skip'; roblox_studio = 'skip'; webview2 = 'skip'; ffmpeg = 'skip' } } | Out-Null
  exit 0
}

$u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { 'xyadmin' }
$work = Join-Path $env:RUNNER_TEMP 'xyrdp-studio3d'
New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path 'C:\Studio' -Force | Out-Null

$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
if (-not (Test-Path $sevenZip)) { $sevenZip = "${env:ProgramFiles(x86)}\7-Zip\7z.exe" }

function Invoke-StudioDownload([string]$Url, [string]$OutFile, [int]$MinBytes = 4096) {
  Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
  & curl.exe -fL -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 240 -sS $Url -o $OutFile
  if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -ge $MinBytes) {
    return $true
  }
  return (Get-File $Url $OutFile 180)
}

function Add-DesktopShortcut([string]$Name, [string]$Target, [string]$WorkDir, [string]$IconLoc, [string]$Desc) {
  foreach ($desk in @("C:\Users\$u\Desktop", 'C:\Users\Public\Desktop', 'C:\Users\Default\Desktop')) {
    New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
    try {
      $wsh = New-Object -ComObject WScript.Shell
      $lnk = $wsh.CreateShortcut((Join-Path $desk "$Name.lnk"))
      $lnk.TargetPath = $Target
      $lnk.WorkingDirectory = $WorkDir
      if ($IconLoc) { $lnk.IconLocation = $IconLoc }
      $lnk.Description = $Desc
      $lnk.Save()
    } catch {}
  }
}

# ---------- 1. Utilitas WebView2 Runtime (dibutuhkan Roblox Studio) ----------
$resWebView2 = 'skip'
try {
  $wv2Dirs = @(
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application",
    "$env:ProgramFiles\Microsoft\EdgeWebView\Application"
  )
  $hasWv2 = $false
  foreach ($d in $wv2Dirs) {
    if ((Test-Path $d) -and (Get-ChildItem $d -Recurse -Filter 'msedgewebview2.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      $hasWv2 = $true; break
    }
  }
  if ($hasWv2) {
    $resWebView2 = 'sudah ada'
    Log 'WebView2 Runtime: sudah tersedia di sistem.'
  } else {
    $wvExe = Join-Path $work 'MicrosoftEdgeWebview2Setup.exe'
    if (Invoke-StudioDownload 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' $wvExe 500000) {
      $p = Start-Process -FilePath $wvExe -ArgumentList @('/silent', '/install') -PassThru -WindowStyle Hidden
      if ($p) { $p.WaitForExit(120000) | Out-Null }
      $resWebView2 = 'ok'
      Log 'WebView2 Runtime: berhasil dipasang untuk Roblox Studio.'
    }
  }
} catch {
  Log "WebView2 warning: $($_.Exception.Message)"
}

# ---------- 2. Utilitas FFmpeg CLI (dibutuhkan Blender 3D untuk render video/audio) ----------
$resFfmpeg = 'skip'
try {
  $ffCmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
  if ($ffCmd) {
    $resFfmpeg = 'sudah ada'
    Log "FFmpeg CLI: sudah tersedia di $($ffCmd.Source)"
  } else {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
      & $winget.Source install --id Gyan.FFmpeg.Essentials -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
    if (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue) {
      $resFfmpeg = 'ok'
      Log 'FFmpeg CLI: terpasang untuk Blender 3D.'
    }
  }
} catch {
  Log "FFmpeg warning: $($_.Exception.Message)"
}

# ---------- 3. Blender 3D 4.2 LTS + Mesa3D OpenGL 4.6 ----------
$resBlender = 'gagal'
try {
  $blenderDir = 'C:\Studio\Blender'
  New-Item -ItemType Directory -Path $blenderDir -Force | Out-Null
  $foundBlender = Get-ChildItem -Path @($blenderDir, 'C:\Games\Blender', 'C:\Program Files\Blender Foundation') -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

  if (-not $foundBlender) {
    $zipFile = Join-Path $work 'blender-4.2.3-windows-x64.zip'
    Log 'Mengunduh & mengekstrak Blender 3D 4.2 LTS (x64) ke C:\Studio\Blender...'
    foreach ($mirror in @(
      'https://mirror.clarkson.edu/blender/release/Blender4.2/blender-4.2.3-windows-x64.zip',
      'https://download.blender.org/release/Blender4.2/blender-4.2.3-windows-x64.zip'
    )) {
      if (Invoke-StudioDownload $mirror $zipFile 50000000) {
        if (Test-Path $sevenZip) { & $sevenZip x $zipFile "-o$blenderDir" -y 2>&1 | Out-Null }
        else { Expand-Archive -Path $zipFile -DestinationPath $blenderDir -Force }
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        break
      }
    }
    $foundBlender = Get-ChildItem -Path $blenderDir -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  }

  if ($foundBlender) {
    $bDir = $foundBlender.DirectoryName
    if (Test-Path 'C:\XyRDP\grafis\mesa-x64\opengl32.dll') {
      Copy-Item 'C:\XyRDP\grafis\mesa-x64\*.dll' -Destination $bDir -Force -ErrorAction SilentlyContinue
    }
    $launchPs1 = Join-Path $blenderDir 'Launch-Blender.ps1'
    @(
      '$ErrorActionPreference = "Continue"'
      '$env:GALLIUM_DRIVER = "llvmpipe"'
      '$env:LIBGL_ALWAYS_SOFTWARE = "1"'
      '$env:MESA_GL_VERSION_OVERRIDE = "4.6"'
      '$env:MESA_GLSL_VERSION_OVERRIDE = "460"'
      "Start-Process -FilePath `"$($foundBlender.FullName)`" -WorkingDirectory `"$bDir`""
    ) | Set-Content -LiteralPath $launchPs1 -Encoding UTF8 -Force

    Add-DesktopShortcut 'Blender 3D' $foundBlender.FullName $bDir "$($foundBlender.FullName),0" 'Blender 3D Studio 4.2 LTS (Mesa3D OpenGL 4.6 Ready)'
    $resBlender = 'ok'
    Log "Blender 3D siap di $($foundBlender.FullName)"
  }
} catch {
  Log "Blender 3D warning: $($_.Exception.Message)"
}

# ---------- 4. Roblox Studio Resmi (WindowsStudio64 - Murni IDE Kreator) ----------
$resRobloxStudio = 'gagal'
try {
  $studioDir = 'C:\Studio\RobloxStudio'
  $studioExe = Join-Path $studioDir 'RobloxStudioBeta.exe'
  if (-not (Test-Path $studioExe) -and (Test-Path 'C:\Games\Roblox\Studio\RobloxStudioBeta.exe')) {
    $studioDir = 'C:\Games\Roblox\Studio'
    $studioExe = Join-Path $studioDir 'RobloxStudioBeta.exe'
  }

  if (-not (Test-Path $studioExe)) {
    Log 'Mengunduh & menyusun paket resmi Roblox Studio (WindowsStudio64)...'
    $stMeta = Invoke-RestMethod -Uri 'https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64' -TimeoutSec 20 -ErrorAction SilentlyContinue
    if ($stMeta -and $stMeta.clientVersionUpload) {
      $stHash = $stMeta.clientVersionUpload
      New-Item -ItemType Directory -Path $studioDir -Force | Out-Null
      $stPkgs = [ordered]@{
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
        if (Invoke-StudioDownload "https://setup.rbxcdn.com/$stHash-$sp" $sZip 10) {
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
      ) | Set-Content -LiteralPath (Join-Path $studioDir 'AppSettings.xml') -Encoding UTF8 -Force
    }
  }

  if (Test-Path $studioExe) {
    # Konfigurasi Direct3D 11 WARP agar viewport 3D Roblox Studio stabil di RDP tanpa GPU fisik
    $csDir = Join-Path $studioDir 'ClientSettings'
    New-Item -ItemType Directory -Path $csDir -Force | Out-Null
    @{
      FFlagDebugGraphicsPreferD3D11       = $true
      FFlagDebugGraphicsDisableDirect3D11 = $false
      FFlagDebugGraphicsDisableDirect3D12 = $true
      DFIntTaskSchedulerTargetFps         = 60
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $csDir 'ClientAppSettings.json') -Encoding UTF8 -Force

    Add-DesktopShortcut 'Roblox Studio' $studioExe $studioDir "$studioExe,0" 'Roblox Studio IDE (Direct3D 11 Ready untuk RDP)'
    $resRobloxStudio = 'ok'
    Log "Roblox Studio siap di $studioExe"
  }
} catch {
  Log "Roblox Studio warning: $($_.Exception.Message)"
}

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Update-Status @{
  studio_3d = [ordered]@{
    blender       = $resBlender
    roblox_studio = $resRobloxStudio
    webview2      = $resWebView2
    ffmpeg        = $resFfmpeg
  }
} | Out-Null

Log ("SELESAI Studio 3D - Blender={0} | RobloxStudio={1} | WebView2={2} | FFmpeg={3}" -f `
  $resBlender, $resRobloxStudio, $resWebView2, $resFfmpeg)
exit 0
