# ============================================================================
#  setup-native-core.ps1 - Kompilasi Modul Native XyRDP (C, C++, C#, Rust)
#                          + XyMac OS Launcher (Dock & Top Bar bergaya macOS)
# ----------------------------------------------------------------------------
#  Founder: xykal (Haekal Saputra) · Tim XyVerse · Indonesia
#  Semua langkah best-effort: kegagalan kompiler opsional tidak menghentikan RDP.
# ============================================================================

$XyTag = 'XyRDP:native'
. "$PSScriptRoot/lib-common.ps1"

$u = if ($env:RDP_USER) { $env:RDP_USER.Trim() } else { 'xyadmin' }
$ws = Get-Workspace
$binDir = 'C:\XyRDP\bin'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null

# Tambahkan C:\XyRDP\bin ke PATH mesin supaya CLI native langsung bisa dipanggil
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$binDir*") {
  [Environment]::SetEnvironmentVariable('Path', "$binDir;$machinePath", 'Machine')
  $env:Path = "$binDir;$env:Path"
}

$wantMacAutoStart = $false
if ($env:MAC_LAUNCHER) {
  $wantMacAutoStart = @('ya', '1', 'true', 'yes', 'on') -contains $env:MAC_LAUNCHER.Trim().ToLower()
}

$statusReport = [ordered]@{
  csharp_mac_launcher = 'skip'
  c_booster           = 'skip'
  cpp_grafis_check    = 'skip'
  rust_probe          = 'skip'
  mac_autostart       = $wantMacAutoStart
}

# ---------- 1. C# : XyMacLauncher.exe (Dock + Top Bar + Launchpad ala macOS) ----------
try {
  $csDir = Join-Path $ws 'native\XyMacLauncher'
  $csFiles = @(Get-ChildItem -Path $csDir -Filter '*.cs' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $cscCandidates = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
  )
  $cscExe = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

  if ($csFiles.Count -gt 0 -and $cscExe) {
    $macExe = Join-Path $binDir 'XyMacLauncher.exe'
    $cscArgs = @(
      '/nologo',
      '/optimize+',
      '/target:winexe',
      "/out:$macExe",
      '/r:System.dll',
      '/r:System.Core.dll',
      '/r:System.Drawing.dll',
      '/r:System.Windows.Forms.dll'
    ) + $csFiles

    Log 'C# Native: mengompilasi XyMacLauncher.exe (macOS Dock & Top Menu Bar)...'
    $outTxt = & $cscExe @cscArgs 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and (Test-Path $macExe)) {
      $selfOut = & $macExe --self-test 2>&1 | Out-String
      Log "  XyMacLauncher.exe siap: $($selfOut.Trim())"
      $statusReport.csharp_mac_launcher = 'ok'

      # Buat shortcut di semua Desktop supaya user bisa menyalakan/mematikan kapan saja
      foreach ($desk in @("C:\Users\$u\Desktop", 'C:\Users\Public\Desktop', 'C:\Users\Default\Desktop')) {
        New-Item -ItemType Directory -Path $desk -Force -ErrorAction SilentlyContinue | Out-Null
        try {
          $wsh = New-Object -ComObject WScript.Shell
          $lnk = $wsh.CreateShortcut((Join-Path $desk 'XyMac OS Launcher (Mac Style).lnk'))
          $lnk.TargetPath = $macExe
          $lnk.Arguments = '--hide-taskbar'
          $lnk.WorkingDirectory = $binDir
          $lnk.IconLocation = 'shell32.dll,277'
          $lnk.Description = 'Launcher Desktop bergaya macOS (Dock + Top Bar + Launchpad)'
          $lnk.Save()
        } catch {}
      }

      if ($wantMacAutoStart) {
        Open-DefaultHive | Out-Null
        Set-RegBoth 'Software\Microsoft\Windows\CurrentVersion\Run' 'XyMacLauncher' "`"$macExe`" --hide-taskbar" 'String' | Out-Null
        Close-DefaultHive
        Log '  Auto-start XyMacLauncher diaktifkan saat user masuk ke sesi RDP.'
      }
    } else {
      Log "  Kompilasi C# XyMacLauncher gagal: $(Log-Tail $outTxt 4)"
      $statusReport.csharp_mac_launcher = 'gagal'
    }
  }
} catch {
  Log "C# XyMacLauncher warning: $($_.Exception.Message)"
  $statusReport.csharp_mac_launcher = 'gagal'
}

# ---------- 2. C11 : xyrdp-booster.exe (1ms Timer Quantum & RAM Trimmer) ----------
try {
  $cSrc = Join-Path $ws 'native\xyrdp-booster\xyrdp_booster.c'
  $cOut = Join-Path $binDir 'xyrdp-booster.exe'
  $clangC = @(
    'C:\Program Files\LLVM\bin\clang.exe',
    (Get-Command clang.exe -ErrorAction SilentlyContinue).Source,
    (Get-Command gcc.exe -ErrorAction SilentlyContinue).Source
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if ((Test-Path $cSrc) -and $clangC) {
    Log "C11 Native: mengompilasi xyrdp-booster.exe memakai $(Split-Path $clangC -Leaf)..."
    & $clangC -std=c11 -O2 $cSrc -lpsapi -lwinmm -o $cOut 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $cOut)) {
      $boostJson = & $cOut --fps 60 --trim-ram 2>&1 | Out-String
      Log "  xyrdp-booster aktif: $($boostJson.Trim())"
      $statusReport.c_booster = 'ok'
    }
  }
} catch {
  Log "C11 booster warning: $($_.Exception.Message)"
}

# ---------- 3. C++17 : xyrdp-grafis-check.exe (Inspector DirectX & Mesa3D) ----------
try {
  $cppSrc = Join-Path $ws 'native\xyrdp-grafis-check\xyrdp_grafis_check.cpp'
  $cppOut = Join-Path $binDir 'xyrdp-grafis-check.exe'
  $clangCpp = @(
    'C:\Program Files\LLVM\bin\clang++.exe',
    (Get-Command clang++.exe -ErrorAction SilentlyContinue).Source,
    (Get-Command g++.exe -ErrorAction SilentlyContinue).Source
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if ((Test-Path $cppSrc) -and $clangCpp) {
    Log "C++17 Native: mengompilasi xyrdp-grafis-check.exe memakai $(Split-Path $clangCpp -Leaf)..."
    & $clangCpp -std=c++17 -O2 $cppSrc -ladvapi32 -o $cppOut 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $cppOut)) {
      $diagJson = & $cppOut --self-test 2>&1 | Out-String
      Log "  xyrdp-grafis-check siap: $($diagJson.Trim())"
      $statusReport.cpp_grafis_check = 'ok'
    }
  }
} catch {
  Log "C++17 grafis-check warning: $($_.Exception.Message)"
}

# ---------- 4. Rust : xyrdp-probe.exe (RDP X.224 Handshake & Tailscale Probe) ----------
try {
  $manifest = Join-Path $ws 'native\xyrdp-probe\Cargo.toml'
  $cargoExe = @(
    'C:\Cargo\bin\cargo.exe',
    "$env:USERPROFILE\.cargo\bin\cargo.exe",
    (Get-Command cargo.exe -ErrorAction SilentlyContinue).Source
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if ((Test-Path $manifest) -and $cargoExe) {
    Log 'Rust Native: mengompilasi xyrdp-probe.exe (X.224 RDP & Tailscale CGNAT Probe)...'
    $targetDir = Join-Path $env:RUNNER_TEMP 'xyrdp-probe-target'
    $env:CARGO_TARGET_DIR = $targetDir
    & $cargoExe build --release --manifest-path $manifest --quiet 2>&1 | Out-Null
    $builtProbe = Join-Path $targetDir 'release\xyrdp-probe.exe'
    if (Test-Path $builtProbe) {
      $probeOut = Join-Path $binDir 'xyrdp-probe.exe'
      Copy-Item -LiteralPath $builtProbe -Destination $probeOut -Force
      $probeTest = & $probeOut --self-test 2>&1 | Out-String
      Log "  xyrdp-probe siap: $($probeTest.Trim())"
      $statusReport.rust_probe = 'ok'
    }
    Remove-Item $targetDir -Recurse -Force -ErrorAction SilentlyContinue
  }
} catch {
  Log "Rust probe warning: $($_.Exception.Message)"
}

Update-Status @{ native_core = $statusReport } | Out-Null
Log ("SELESAI Native Core - C#={0} | C={1} | C++={2} | Rust={3}" -f `
  $statusReport.csharp_mac_launcher, $statusReport.c_booster, $statusReport.cpp_grafis_check, $statusReport.rust_probe)
exit 0
