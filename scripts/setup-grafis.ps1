# ============================================================================
#  setup-grafis.ps1 — "GPU software" untuk sesi RDP di runner TANPA GPU fisik.
#
#  Runner GitHub tidak punya GPU: satu-satunya adapter = Microsoft Basic Render
#  Driver (WARP / Direct3D software). Script ini memasang renderer SOFTWARE
#  supaya aplikasi yang mewajibkan OpenGL/Vulkan/DirectX tetap bisa jalan:
#    - Mesa3D llvmpipe  -> OpenGL 4.5 software (dipasang sistem-wide)
#    - Mesa3D lavapipe  -> Vulkan (CPU) lewat VK_DRIVER_FILES
#    - WARP (D3D11/D3D12) sudah bawaan Windows
#  Semuanya CPU-based: cukup untuk aplikasi 2D/ringan & tool yang butuh konteks
#  GL/Vulkan; untuk game 3D berat / render video GPU tetap lambat (tidak ada
#  NVENC, tidak ada VRAM). VM ini ephemeral, jadi penggantian opengl32.dll
#  sistem tidak permanen (dan aslinya di-backup ke C:\XyRDP\grafis\orig).
# ============================================================================
$XyTag = 'XyRDP:grafis'
. "$PSScriptRoot/lib-common.ps1"

$root = 'C:\XyRDP\grafis'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$bkp = Join-Path $root 'orig'
New-Item -ItemType Directory -Force -Path $bkp | Out-Null

$gMode = 'software'; $gMesa = ''; $gOpenGL = ''; $gVulkan = ''
$gAdapters = ''; $gNote = ''

# ---- 1) adapter yang ada sekarang (bukti tidak ada GPU fisik) --------------
try {
  $ad = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { "$($_.Name)" })
  $gAdapters = ($ad -join ' | ')
} catch { $gAdapters = '' }
Log "  adapter grafis: $(if ($gAdapters) { $gAdapters } else { '(tidak terbaca)' })"

# ---- 2) unduh Mesa3D (pal1000/mesa-dist-win, build MSVC) -------------------
$asset = Get-GhAssetUrl 'pal1000/mesa-dist-win' 'mesa3d-.*-release-msvc\.7z$'
if (-not $asset) { $asset = Get-GhAssetUrl 'pal1000/mesa-dist-win' 'release-msvc.*\.7z$' }
if (-not $asset) {
  Log '  Mesa: asset rilis tidak ketemu (API/rate-limit) - grafis software dilewati'
  Update-Status @{ grafis = @{ mode = 'gagal'; mesa = ''; adapters = $gAdapters; note = 'unduhan Mesa tidak tersedia' } } | Out-Null
  return
}
$gMesa = ($asset.name -replace '^mesa3d-', '' -replace '-release-msvc\.7z$', '')
Log "  Mesa3D: $($asset.name) (tag $($asset.tag))"

$arc = Join-Path $root $asset.name
if (-not (Get-File $asset.url $arc 300)) {
  Log '  unduh Mesa gagal'
  Update-Status @{ grafis = @{ mode = 'gagal'; mesa = $gMesa; adapters = $gAdapters; note = 'unduhan gagal' } } | Out-Null
  return
}

# ---- 3) ekstrak (runner GitHub punya 7-Zip) --------------------------------
$sevenZip = $null
foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
  if (Test-Path $p) { $sevenZip = $p; break }
}
if (-not $sevenZip) { $c = Get-Command 7z.exe -ErrorAction SilentlyContinue; if ($c) { $sevenZip = $c.Source } }
$ext = Join-Path $root 'mesa'
Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
if ($sevenZip) {
  & $sevenZip x $arc "-o$ext" -y 2>&1 | Out-Null
  Log "  7z: diekstrak ke $ext"
} else {
  Log '  7z.exe tidak ada - coba tar (arsip .7z umumnya gagal)'
  try { tar -xf $arc -C $ext 2>&1 | Out-Null } catch {}
}

function Pick-X64([string]$name) {
  $all = @(Get-ChildItem -Path $ext -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
  $x64 = @($all | Where-Object { $_.FullName -match '\\x64\\' })
  if ($x64.Count -gt 0) { return $x64[0].FullName }
  if ($all.Count -gt 0) { return $all[0].FullName }
  return $null
}

$sys32 = "$env:SystemRoot\System32"
$opengl = Pick-X64 'opengl32.dll'
$galium = Pick-X64 'libgallium_wgl.dll'
$dxil   = Pick-X64 'dxil.dll'
$lvpDll = Pick-X64 'vulkan_lvp.dll'
$lvpIcd = Pick-X64 'lvp_icd.x86_64.json'
$files = @()
if ($opengl) { $files += 'opengl32.dll' }
if ($galium) { $files += 'libgallium_wgl.dll' }
if ($lvpDll) { $files += 'vulkan_lvp.dll' }

# ---- 4) pasang llvmpipe (OpenGL) sistem-wide -------------------------------
if ($opengl) {
  Copy-Item "$sys32\opengl32.dll" (Join-Path $bkp 'opengl32.dll') -Force -ErrorAction SilentlyContinue
  Copy-Item $opengl "$sys32\opengl32.dll" -Force
  if ($galium) { Copy-Item $galium "$sys32\libgallium_wgl.dll" -Force }
  if ($dxil)   { Copy-Item $dxil   "$sys32\dxil.dll" -Force }
  Log "  llvmpipe terpasang: $sys32\opengl32.dll (asli di-backup ke $bkp)"
} else {
  Log '  opengl32.dll Mesa tidak ketemu di arsip (OpenGL dilewati)'
}
[Environment]::SetEnvironmentVariable('GALLIUM_DRIVER', 'llvmpipe', 'Machine')
[Environment]::SetEnvironmentVariable('LIBGL_ALWAYS_SOFTWARE', '1', 'Machine')

# ---- 5) pasang lavapipe (Vulkan CPU) --------------------------------------
if ($lvpDll -and $lvpIcd) {
  $vkDir = Join-Path $root 'vulkan'
  New-Item -ItemType Directory -Force -Path $vkDir | Out-Null
  Copy-Item $lvpDll $vkDir -Force
  Copy-Item $lvpIcd $vkDir -Force
  $icd = Join-Path $vkDir (Split-Path $lvpIcd -Leaf)
  [Environment]::SetEnvironmentVariable('VK_DRIVER_FILES', $icd, 'Machine')
  [Environment]::SetEnvironmentVariable('VK_ADD_DRIVER_FILES', $icd, 'Machine')
  $gVulkan = 'lavapipe (CPU)'
  Log "  lavapipe terdaftar: VK_DRIVER_FILES=$icd"
} else {
  Log '  lavapipe tidak ada di arsip (Vulkan dilewati)'
}

# ---- 6) uji cepat: minta versi OpenGL yang benar-benar didapat -------------
$py = Get-Command python.exe -ErrorAction SilentlyContinue
if ($py -and $opengl) {
  $env:GALLIUM_DRIVER = 'llvmpipe'; $env:LIBGL_ALWAYS_SOFTWARE = '1'
  try { & $py.Source -m pip install --quiet --disable-pip-version-check moderngl 2>&1 | Out-Null } catch {}
  $code = 'import moderngl;c=moderngl.create_standalone_context();i=c.info;print(i.get("GL_VERSION",""),"|",i.get("GL_RENDERER",""),"|",i.get("GL_VENDOR",""))'
  try {
    $out = ((& $py.Source -c $code 2>&1) | Out-String).Trim()
    if ($out -match '\|') { $gOpenGL = ($out -replace '\s+', ' ') } else { Log "  uji OpenGL: $out" }
  } catch { Log "  uji OpenGL gagal: $($_.Exception.Message)" }
}

if (-not $gOpenGL) { $gOpenGL = 'llvmpipe (Mesa ' + $gMesa + ')' }
$gNote = 'GPU software (CPU): OpenGL 4.5 (llvmpipe) + Vulkan (lavapipe) + WARP bawaan. Runner GitHub tanpa GPU fisik; 3D berat tetap lambat.'
Log "  selesai: OpenGL=$gOpenGL | Vulkan=$(if ($gVulkan) { $gVulkan } else { '-' }) | adapter=$gAdapters"

try {
  Update-Status @{ grafis = @{
    mode = $gMode; mesa = $gMesa; opengl = $gOpenGL; vulkan = $gVulkan
    adapters = $gAdapters; files = ($files -join ','); dir = $root; note = $gNote
  } } | Out-Null
  Log '  status grafis ditulis (grafis.*)'
} catch { Log "  tulis status grafis gagal: $($_.Exception.Message)" }
