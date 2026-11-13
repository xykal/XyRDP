# ============================================================================
#  keepalive.ps1 - Penjaga Sesi Hidup (Anti-Disconnect & Auto-Heal)
# ----------------------------------------------------------------------------
#  1. Menjaga TermService, UmRdpService, Audiosrv & listener 3389 tetap hidup
#  2. Memastikan shortcut Desktop memiliki Nama & Ikon Unik (Anti-Tertukar)
#  3. Membuka otomatis XyDeskRemote Dashboard saat user pertama kali masuk RDP
#  4. Menjalankan Auto-Checkpoint lintas sesi setiap 4 menit ke GitHub Release
#     sehingga login Google, file di Downloads, Desktop, dan save game aman
#     meski runner dihentikan paksa kapan saja.
# ============================================================================

$XyTag = 'XyRDP:keepalive'
. "$PSScriptRoot/lib-common.ps1"

$s   = Read-Status
$exp = if ($s -and $s.expires_utc) { [DateTime]::Parse($s.expires_utc).ToUniversalTime() } else { [DateTime]::UtcNow.AddMinutes(335) }
$addr = if ($s -and $s.connect) { $s.connect } else { '(lihat langkah Ringkasan)' }
$rdpUser = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { (Get-Cfg).rdp_user }

Log "SESI AKTIF - alamat: $addr | selesai: $($exp.ToString('HH:mm')) UTC"
$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
$icoDir = Ensure-XyDesktopIcons

function Sync-And-Heal-DesktopShortcuts {
  try {
    $u = $rdpUser
    New-Item -ItemType Directory -Path 'C:\Persist' -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path 'C:\Games' -Force -ErrorAction SilentlyContinue | Out-Null

    $dashExe      = 'C:\XyRDP\tools\XyDeskDashboard.exe'
    $dashIco      = Join-Path $icoDir 'xydesk-dashboard.ico'
    $persistIco   = Join-Path $icoDir 'persist-folder.ico'
    $cloudSaveIco = Join-Path $icoDir 'cloud-save.ico'
    $persistPs1   = Join-Path $PSScriptRoot 'persist-state.ps1'

    $allDesks = @("C:\Users\$u\Desktop", "C:\Users\Public\Desktop") + @(Get-AllUserProfileDirs $u | ForEach-Object { Join-Path $_ 'Desktop' }) | Select-Object -Unique
    foreach ($desk in $allDesks) {
      if (-not (Test-Path $desk)) {
        New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
      }
      $wsh = New-Object -ComObject WScript.Shell

      # Bersihkan shortcut duplikat/lama atau sampah bawaan image runner
      foreach ($oldItem in @('XyDeskTools.exe', 'XyDesk Gaming & Tools Hub.lnk', 'Simpan Data & Game Sekarang.lnk', 'Minecraft (TLauncher).lnk', 'PrismLauncher (Minecraft).lnk', 'GTA SAMP.lnk', 'SA-MP 0.3.7-R5 Server Browser.lnk', 'Patch GTA SA-MP (SilentPatch).lnk', 'Atasi Banned & Anti-VPN SAMP.lnk', 'Install Roblox Player.exe', 'Epic Games Launcher.lnk', 'R 4.6.1.lnk', 'Unity Hub.lnk')) {
        Remove-Item -LiteralPath (Join-Path $desk $oldItem) -Force -ErrorAction SilentlyContinue
      }

      # 1. Shortcut XyDeskRemote Dashboard (Ikon Biru-Cyan 'XY DASHBOARD')
      if (Test-Path $dashExe) {
        $lnkDash = Join-Path $desk 'XyDeskRemote Dashboard.lnk'
        if (-not (Test-Path $lnkDash)) {
          $sc = $wsh.CreateShortcut($lnkDash)
          $sc.TargetPath = $dashExe
          $sc.WorkingDirectory = 'C:\XyRDP\tools'
          $sc.Description = 'XyDeskRemote Dashboard - Pusat Kelola Sistem, Installer, Anti-VM & Cloud Save'
          if (Test-Path $dashIco) { $sc.IconLocation = "$dashIco,0" }
          $sc.Save()
        }
      }

      # 2. Shortcut Folder Permanen (C:\Persist) (Ikon Emas 'DIR PERSIST')
      $lnkPersist = Join-Path $desk 'Folder Permanen (Anti-Reset).lnk'
      if (-not (Test-Path $lnkPersist)) {
        $sc2 = $wsh.CreateShortcut($lnkPersist)
        $sc2.TargetPath = 'C:\Persist'
        $sc2.Description = 'Semua file di folder ini otomatis disimpan ke sesi RDP berikutnya'
        if (Test-Path $persistIco) { $sc2.IconLocation = "$persistIco,0" }
        else { $sc2.IconLocation = 'shell32.dll,43' }
        $sc2.Save()
      }

      # 3. Shortcut Simpan Data Sesi Sekarang (Cloud Save) (Ikon Biru Langit 'CLD SAVE')
      if (Test-Path $persistPs1) {
        $lnkSave = Join-Path $desk 'Simpan Data Sesi Sekarang (Cloud Save).lnk'
        if (-not (Test-Path $lnkSave)) {
          $sc3 = $wsh.CreateShortcut($lnkSave)
          $sc3.TargetPath = 'powershell.exe'
          $sc3.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$persistPs1`" -Checkpoint"
          $sc3.WorkingDirectory = 'C:\XyRDP\scripts'
          $sc3.Description = 'Backup instan Login Browser (Chrome/Edge), Downloads, Desktop & Save Game ke Cloud'
          if (Test-Path $cloudSaveIco) { $sc3.IconLocation = "$cloudSaveIco,0" }
          else { $sc3.IconLocation = 'shell32.dll,167' }
          $sc3.Save()
        }
      }

      # 4. Shortcut Studio 3D, WinRAR & XyMac OS Launcher (100% Ikon Asli .exe)
      $blenderExe = (Get-ChildItem -Path @('C:\Studio\Blender', 'C:\Games\Blender') -Recurse -File -Filter 'blender.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
      $studioExe  = if (Test-Path 'C:\Studio\RobloxStudio\RobloxStudioBeta.exe') { 'C:\Studio\RobloxStudio\RobloxStudioBeta.exe' } elseif (Test-Path 'C:\Games\Roblox\Studio\RobloxStudioBeta.exe') { 'C:\Games\Roblox\Studio\RobloxStudioBeta.exe' } else { $null }
      $winrarExe  = if (Test-Path 'C:\Program Files\WinRAR\WinRAR.exe') { 'C:\Program Files\WinRAR\WinRAR.exe' } elseif (Test-Path 'C:\Program Files (x86)\WinRAR\WinRAR.exe') { 'C:\Program Files (x86)\WinRAR\WinRAR.exe' } else { $null }
      $macExe     = 'C:\XyRDP\bin\XyMacLauncher.exe'

      if ($blenderExe) {
        $lnkB = Join-Path $desk 'Blender 3D.lnk'
        if (-not (Test-Path $lnkB)) {
          $scB = $wsh.CreateShortcut($lnkB)
          $scB.TargetPath = $blenderExe.FullName
          $scB.WorkingDirectory = $blenderExe.DirectoryName
          $scB.IconLocation = "$($blenderExe.FullName),0"
          $scB.Description = 'Blender 3D Studio 4.2 LTS (Mesa3D OpenGL 4.6 Ready)'
          $scB.Save()
        }
      }

      if ($studioExe) {
        $lnkS = Join-Path $desk 'Roblox Studio.lnk'
        if (-not (Test-Path $lnkS)) {
          $scS = $wsh.CreateShortcut($lnkS)
          $scS.TargetPath = $studioExe
          $scS.WorkingDirectory = (Split-Path $studioExe -Parent)
          $scS.IconLocation = "$studioExe,0"
          $scS.Description = 'Roblox Studio IDE (Direct3D 11 Ready)'
          $scS.Save()
        }
      }

      if ($winrarExe) {
        $lnkR = Join-Path $desk 'WinRAR.lnk'
        if (-not (Test-Path $lnkR)) {
          $scR = $wsh.CreateShortcut($lnkR)
          $scR.TargetPath = $winrarExe
          $scR.WorkingDirectory = (Split-Path $winrarExe -Parent)
          $scR.IconLocation = "$winrarExe,0"
          $scR.Description = 'WinRAR Archiver'
          $scR.Save()
        }
      }

      if (Test-Path $macExe) {
        $lnkMac = Join-Path $desk 'XyMac OS Launcher (Mac Style).lnk'
        if (-not (Test-Path $lnkMac)) {
          $scMac = $wsh.CreateShortcut($lnkMac)
          $scMac.TargetPath = $macExe
          $scMac.Arguments = '--hide-taskbar'
          $scMac.WorkingDirectory = 'C:\XyRDP\bin'
          $scMac.IconLocation = 'shell32.dll,277'
          $scMac.Description = 'Launcher Desktop bergaya macOS (Dock + Top Bar + Launchpad)'
          $scMac.Save()
        }
      }
    }
  } catch {}
}

Sync-And-Heal-DesktopShortcuts

$i = 0
# Set $lastCheckpointUtc mundur 2 menit agar checkpoint pertama berjalan pada menit ke-2 setelah sesi aktif!
$lastCheckpointUtc = [DateTime]::UtcNow.AddMinutes(-2)
$checkpointJob = $null
$dashboardAutoOpened = $false

while ([DateTime]::UtcNow -lt $exp) {
  Start-Sleep -Seconds 60
  $i++
  $now = [DateTime]::UtcNow
  $rem = [int][math]::Max(0, ($exp - $now).TotalMinutes)

  # 1. Pastikan TermService, UmRdpService, & listener :3389 selalu sehat
  try {
    foreach ($svcName in @('TermService', 'UmRdpService')) {
      $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
      if ($svc -and $svc.Status -ne 'Running') {
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
        Log "$svcName di-start ulang otomatis."
      }
    }
    $tsReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    if ((Get-ItemPropertyValue $tsReg 'fDenyTSConnections' -ErrorAction SilentlyContinue) -ne 0) {
      Set-ItemProperty $tsReg 'fDenyTSConnections' 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
  } catch {}

  # 1b. Auto-open XyDeskRemote Dashboard begitu user masuk ke Desktop RDP untuk pertama kalinya!
  if (-not $dashboardAutoOpened -and (Test-Path 'C:\XyRDP\tools\XyDeskDashboard.exe')) {
    try {
      $dashRunning = Get-Process -Name 'XyDeskDashboard' -ErrorAction SilentlyContinue
      if ($dashRunning) {
        $dashboardAutoOpened = $true
      } else {
        # Cek apakah ada explorer.exe yang berjalan di sesi interaktif user RDP
        $expProcs = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ge 1 })
        if ($expProcs.Count -gt 0) {
          & schtasks.exe /Create /TN "XyAutoOpenDashboard" /TR "`"C:\XyRDP\tools\XyDeskDashboard.exe`"" /SC ONCE /ST 00:00 /RU $rdpUser /IT /RL HIGHEST /F 2>&1 | Out-Null
          & schtasks.exe /Run /TN "XyAutoOpenDashboard" 2>&1 | Out-Null
          $dashboardAutoOpened = $true
          Log "XyDeskRemote Dashboard otomatis dibuka di sesi Desktop user '$rdpUser'."
        }
      }
    } catch {}
  }

  # 1c. Auto-heal Tailscale Tunnel setiap menit agar sesi HP tidak tiba-tiba terputus saat relay DERP berganti
  if (Test-Path $tsExe) {
    try {
      $tsSvc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
      if ($tsSvc -and $tsSvc.Status -ne 'Running') {
        Start-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
      }
      $tsRaw = & $tsExe status --json 2>$null | Out-String
      $tsObj = if ($tsRaw) { $tsRaw | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }
      $tsState = if ($tsObj) { [string]$tsObj.BackendState } else { '' }
      if ($tsState -and $tsState -ne 'Running' -and $env:TAILSCALE_AUTH_KEY) {
        Log "Tailscale state '$tsState' terdeteksi - memulihkan koneksi tunnel secara otomatis..."
        $hn = if ($s -and $s.hostname) { [string]$s.hostname } else { "xyrdp-$env:GITHUB_RUN_NUMBER" }
        & $tsExe up --authkey="$($env:TAILSCALE_AUTH_KEY.Trim())" --hostname=$hn --unattended --accept-routes --accept-dns=false --reset 2>&1 | Out-Null
      }
    } catch {}
  }

  # 2. Setiap 2 menit: jika user baru mengunduh runtime Java di .minecraft atau ekstrak GTA SA, suntikkan OpenGL 4.6 & SilentPatch + jaga keutuhan shortcut Desktop
  if (($i % 2) -eq 0) {
    Sync-And-Heal-DesktopShortcuts
    $deployGl = 'C:\XyRDP\grafis\Deploy-OpenGL-To-Java.ps1'
    if (Test-Path $deployGl) {
      try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $deployGl 2>&1 | Out-Null } catch {}
    }
    foreach ($lu in @('xyadmin', 'runneradmin')) {
      $lSet = "C:\Users\$lu\AppData\Local\Lively Wallpaper\Settings.json"
      if (Test-Path $lSet) {
        $rawL = Get-Content -LiteralPath $lSet -Raw -ErrorAction SilentlyContinue
        if ($rawL -and $rawL -match '"RemoteDesktopPause"\s*:\s*0') {
          $rawL = $rawL -replace '"RemoteDesktopPause"\s*:\s*0', '"RemoteDesktopPause": 1'
          $rawL = $rawL -replace '"AppFocusPause"\s*:\s*0', '"AppFocusPause": 1'
          $rawL = $rawL -replace '"AppFullscreenPause"\s*:\s*0', '"AppFullscreenPause": 1'
          Set-Content -LiteralPath $lSet -Value $rawL -Encoding UTF8 -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }

  # 3. Setiap 5 menit: log detak jantung + cek Tailscale
  if (($i % 5) -eq 0) {
    $tsIp = ''
    if (Test-Path $tsExe) {
      try { $tsIp = ((& $tsExe ip -4 2>$null) | Select-Object -First 1).Trim() } catch {}
    }
    $listen = Get-RdpListenerState 3389
    Log "detak #$i | sisa $rem menit | RDP=$listen | tailscale=$tsIp"
  }

  # 4. Setiap 4 menit: jalankan Auto-Checkpoint lintas sesi di background (non-blocking) ke Release 'xyrdp-state-latest'
  if (($now - $lastCheckpointUtc).TotalMinutes -ge 4 -and $rem -gt 2) {
    $canRun = $true
    if ($checkpointJob) {
      if ($checkpointJob.State -eq 'Running') {
        $canRun = $false
      } else {
        Remove-Job -Job $checkpointJob -Force -ErrorAction SilentlyContinue
        $checkpointJob = $null
      }
    }
    if ($canRun) {
      $lastCheckpointUtc = $now
      try {
        Log 'Menjalankan auto-checkpoint 4 menit di background (persist-state.ps1 -Checkpoint)...'
        $persistPath = Join-Path $PSScriptRoot 'persist-state.ps1'
        $checkpointJob = Start-Job -ScriptBlock {
          param($p, $tok, $repo, $usr, $pwd)
          try { [System.Threading.Thread]::CurrentThread.Priority = [System.Threading.ThreadPriority]::Lowest } catch {}
          if ($tok)  { $env:GITHUB_TOKEN      = $tok }
          if ($repo) { $env:GITHUB_REPOSITORY = $repo }
          if ($usr)  { $env:RDP_USER          = $usr }
          if ($pwd)  { $env:RDP_PASSWORD      = $pwd }
          & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -Checkpoint 2>&1 | Out-Null
        } -ArgumentList $persistPath, $env:GITHUB_TOKEN, $env:GITHUB_REPOSITORY, $env:RDP_USER, $env:RDP_PASSWORD
      } catch {
        Log "Auto-checkpoint warning: $($_.Exception.Message)"
      }
    }
  }
}

if ($checkpointJob) {
  try { Wait-Job -Job $checkpointJob -Timeout 25 | Out-Null } catch {}
  Remove-Job -Job $checkpointJob -Force -ErrorAction SilentlyContinue
}

Log 'Waktu sesi selesai dengan aman - lanjut ke penyimpanan akhir & estafet sesi berikutnya.'
exit 0
