# ============================================================================
#  setup-fps-boost.ps1 — Boost FPS XyRDP (input: fps_boost, default ya)
# ----------------------------------------------------------------------------
#  Sebelum 1.1.28 "Gaming Boost" hanya berupa toggle di aplikasi yang
#  diteruskan ke setup-xydesk.ps1; tidak ada satupun tweak FPS aktif di level
#  OS/registry. Script ini mengisi kekosongan itu.
#
#  Yang dilakukan (semuanya best-effort, TIDAK pernah menggagalkan sesi):
#    1) Power plan High/Ultimate performance + processor 100% (AC & DC)
#    2) DWMFRAMEINTERVAL 15 -> RDP tidak lagi terkunci ~30 fps
#    3) Game Mode + HAGS bila adapter mendukung
#    4) Matikan animasi Windows / taskbar / background apps
#    5) Prioritas CPU & I/O untuk proses game yang umum dipakai
#    6) Tulis out/fps-boost.json + out/rdp-status.json#fps_boost
#
#  CATATAN JUJUR: tweak ini menaikkan kelancaran rendering RDP, bukan FPS
#  game 3D. Runner GitHub tidak punya GPU fisik; game berat tetap bergantung
#  pada WARP/Mesa3D (setup-grafis.ps1).
# ============================================================================
$XyTag = 'XyRDP:fps'
. "$PSScriptRoot/lib-common.ps1"
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$applied = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$started = Get-Date

function Apply-Tweak([string]$Label, [scriptblock]$Block) {
  try {
    & $Block
    $applied.Add($Label) | Out-Null
    Log "OK   $Label"
  } catch {
    $skipped.Add("$Label -> $($_.Exception.Message)") | Out-Null
    Log "SKIP $Label -> $($_.Exception.Message)"
  }
}

# ---------------------------------------------------------------- 1. Power plan
Apply-Tweak 'Power plan High Performance' {
  $guids = @(
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', # High performance
    'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Ultimate performance
  )
  $picked = $false
  foreach ($g in $guids) {
    $out = & powercfg.exe /setactive $g 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { $picked = $true; Log "  aktif: $g"; break }
  }
  if (-not $picked) { throw 'tidak ada GUID power plan yang tersedia' }
  & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
  & powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
  & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
  & powercfg.exe /setactive SCHEME_CURRENT 2>&1 | Out-Null
}

# ------------------------------------------------- 2. RDP frame interval + DWM
Apply-Tweak 'RDP DWMFRAMEINTERVAL 15 (target 60 fps)' {
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' 'DWMFRAMEINTERVAL' 15 'DWord' | Out-Null
  Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'ForceEffectMode' 2 'DWord' | Out-Null
}

Apply-Tweak 'RDP: matikan wallpaper/full-drag saat remote' {
  # fDisableWallpaper sengaja TIDAK disetel: pemilik ingin wallpaper XyVerse.
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDisableFullWindowDrag' 1 'DWord' | Out-Null
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDisableMenuAnims' 1 'DWord' | Out-Null
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDisableThemes' 0 'DWord' | Out-Null
}

# ----------------------------------------------------------- 3. Game Mode / HAGS
Apply-Tweak 'Game Mode + Game Bar auto' {
  Set-RegBoth 'Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 'DWord'
  Set-RegBoth 'Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 'DWord'
}
Apply-Tweak 'Matikan Xbox Game Bar capture (GameDVR) - hemat CPU saat game jalan' {
  # GameDVR/AppCapture merekam game di latar belakang dan memakan frame.
  # Game Mode tetap AKTIF (scheduling boost); yang dimatikan hanya perekamannya.
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord'
  Set-RegBoth 'System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord'
  Set-RegBoth 'Software\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 'DWord'
  Set-RegBoth 'Software\Microsoft\GameBar' 'ShowStartupPanel' 0 'DWord'
}
Apply-Tweak 'Hardware-Accelerated GPU Scheduling (jika didukung)' {
  # HAGS hanya berguna kalau ada adapter WDDM 2.7+. Kalau tidak ada, registry
  # diabaikan Windows — aman, tidak bikin boot gagal.
  $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($gpu) { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' | Out-Null }
  else { Log '  tidak ada adapter video terdeteksi, HAGS dilewati' }
}

# ---------------------------------------------------------- 4. Animasi & latar
Apply-Tweak 'VisualFXSetting = best performance' {
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 'DWord'
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 'DWord'
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' 0 'DWord'
  Set-RegBoth 'Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
  Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 'DWord'
}

# ------------------------------------------------------- 5. Prioritas proses game
Apply-Tweak 'Prioritas CPU/IO proses game' {
  $exes = @(
    'gta_sa.exe', 'samp.exe', 'gta_sa_224.exe',
    'javaw.exe', 'Minecraft.Windows.exe', 'RobloxPlayerBeta.exe',
    'MuMuPlayer.exe', 'MumuVMM.exe', 'MEmu.exe', 'MEmuConsole.exe',
    'FiveM.exe', 'eurotrucks2.exe', 'blender.exe'
  )
  foreach ($exe in $exes) {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe\PerfOptions"
    New-Item -Path $key -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $key -Name 'CpuPriorityClass' -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $key -Name 'IoPriority' -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
  }
  Log "  prioritas diterapkan untuk $($exes.Count) executable"
}

# --------------------------------------------------------------- 6. Laporan
$report = [ordered]@{
  status       = if ($applied.Count -gt 0) { 'ok' } else { 'failed' }
  applied      = @($applied)
  skipped      = @($skipped)
  applied_count = $applied.Count
  elapsed_sec  = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
  note         = 'Tweak rendering RDP & scheduler OS. Tidak menaikkan FPS game 3D tanpa GPU fisik; Mesa3D/WARP tetap dipakai.'
  updated_at   = (Get-Date).ToUniversalTime().ToString('o')
}
try {
  $outDir = Join-Path (Get-Workspace) 'out'
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  ($report | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $outDir 'fps-boost.json') -Encoding utf8
  Update-Status @{ fps_boost = $report } | Out-Null
} catch { Log "  tulis laporan FPS gagal: $($_.Exception.Message)" }

Log "SELESAI — FPS boost: $($applied.Count) tweak aktif, $($skipped.Count) dilewati."
exit 0
