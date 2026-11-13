# ============================================================================
#  setup-devtools.ps1 - Toolchain Developer (C/C++, C#, Rust, editor)
# ----------------------------------------------------------------------------
#  Permintaan pemilik 13 Nov 2026: sesi XyRDP bisa dipakai ngoding —
#  C/C++ (LLVM/Clang), C# (.NET SDK 8), Rust (rustup), dan VS Code.
#  Opt-in lewat input workflow `devtools=ya` (default tidak, supaya run
#  default tetap cepat). Idempoten; tidak pernah menggagalkan job.
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host ("[devtools] " + $m) }
$res = @{}

function Test-Cmd([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---- Git / Python / Node: sudah bawaan runner GitHub ----------------------
foreach ($c in @(@('git', 'Git'), @('python', 'Python'), @('node', 'Node.js'))) {
  if (Test-Cmd $c[0]) { $res[$c[0]] = 'sudah ada'; Log "  $($c[1]) sudah tersedia." }
  else { $res[$c[0]] = 'absen (opsional)'; Log "  $($c[1]) tidak ditemukan — dilewati." }
}

# ---- C/C++ : LLVM (clang + lld + lldb) ------------------------------------
if (Test-Cmd 'clang') {
  $res['llvm'] = 'sudah ada'
} else {
  Log '  Memasang LLVM (C/C++) via winget...'
  try {
    & winget install --id LLVM.LLVM -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    $clangPath = 'C:\Program Files\LLVM\bin\clang.exe'
    if (Test-Path $clangPath) {
      $res['llvm'] = 'ok'
      # Tambahkan ke PATH sesi (machine PATH sudah diset winget untuk sesi berikutnya)
      $env:PATH = "$env:PATH;C:\Program Files\LLVM\bin"
    } else { $res['llvm'] = 'gagal' }
  } catch { $res['llvm'] = "gagal: $($_.Exception.Message)" }
  Log "  LLVM -> $($res['llvm'])"
}

# ---- C# : .NET SDK 8 (skrip resmi Microsoft) ------------------------------
if (Test-Cmd 'dotnet') {
  $res['dotnet'] = 'sudah ada'
} else {
  Log '  Memasang .NET SDK 8 (C#)...'
  try {
    $installer = Join-Path $env:TEMP 'dotnet-install.ps1'
    & curl.exe -fsSL 'https://dot.net/v1/dotnet-install.ps1' -o $installer 2>&1 | Out-Null
    & powershell -ExecutionPolicy Bypass -File $installer -Channel 8.0 -InstallDir 'C:\dotnet' 2>&1 | Out-Null
    if (Test-Path 'C:\dotnet\dotnet.exe') {
      $res['dotnet'] = 'ok'
      $env:PATH = "$env:PATH;C:\dotnet"
      [Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'Machine') | Out-Null
    } else { $res['dotnet'] = 'gagal' }
  } catch { $res['dotnet'] = "gagal: $($_.Exception.Message)" }
  Log "  .NET SDK -> $($res['dotnet'])"
}

# ---- Rust : rustup (toolchain stable minimal) ------------------------------
if (Test-Cmd 'cargo') {
  $res['rust'] = 'sudah ada'
} else {
  Log '  Memasang Rust (rustup, stable)...'
  try {
    $rustup = Join-Path $env:TEMP 'rustup-init.exe'
    & curl.exe -fsSL 'https://win.rustup.rs/x86_64' -o $rustup 2>&1 | Out-Null
    $env:RUSTUP_HOME = 'C:\Rustup'; $env:CARGO_HOME = 'C:\Cargo'
    Start-Process -FilePath $rustup -ArgumentList @('-y', '--default-toolchain', 'stable', '--profile', 'minimal') -Wait -WindowStyle Hidden | Out-Null
    if (Test-Path 'C:\Cargo\bin\cargo.exe') {
      $res['rust'] = 'ok'
      $env:PATH = "$env:PATH;C:\Cargo\bin"
      [Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'Machine') | Out-Null
      [Environment]::SetEnvironmentVariable('CARGO_HOME', 'C:\Cargo', 'Machine') | Out-Null
      [Environment]::SetEnvironmentVariable('RUSTUP_HOME', 'C:\Rustup', 'Machine') | Out-Null
    } else { $res['rust'] = 'gagal' }
  } catch { $res['rust'] = "gagal: $($_.Exception.Message)" }
  Log "  Rust -> $($res['rust'])"
}

# ---- Editor: VS Code ------------------------------------------------------
if (Test-Cmd 'code') {
  $res['vscode'] = 'sudah ada'
} else {
  Log '  Memasang VS Code...'
  try {
    & winget install --id Microsoft.VisualStudioCode -e --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    if (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd") { $res['vscode'] = 'ok' } else { $res['vscode'] = 'gagal' }
  } catch { $res['vscode'] = "gagal: $($_.Exception.Message)" }
  Log "  VS Code -> $($res['vscode'])"
}

Log "SELESAI devtools: $(($res.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
exit 0
