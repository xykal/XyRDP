# ============================================================================
#  setup-grafis.ps1 — "GPU software" untuk sesi RDP di runner TANPA GPU fisik.
#
#  Runner GitHub tidak punya GPU: satu-satunya adapter = Microsoft Basic Render
#  Driver (WARP / Direct3D software). Script ini memasang renderer SOFTWARE
#  supaya aplikasi yang mewajibkan OpenGL/Vulkan/DirectX tetap bisa jalan:
#    - Mesa3D llvmpipe  -> OpenGL 4.5+/4.6 core software (dipasang sistem-wide)
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
# DLL di System32 dimiliki TrustedInstaller -> harus takeown + icacls dulu,
# kalau tidak: "Access to the path 'C:\Windows\System32\opengl32.dll' is denied".
function Install-SysFile([string]$src, [string]$dst) {
  if (-not $src) { return $false }
  if (-not (Test-Path $dst)) { Copy-Item $src $dst -Force -ErrorAction Stop; return $true }
  $company = ''
  try { $company = (Get-Item $dst).VersionInfo.CompanyName } catch {}
  if ($company -like 'Mesa*') { Copy-Item $src $dst -Force -ErrorAction Stop; return $true }
  & takeown.exe /f $dst /a 2>&1 | Out-Null
  & icacls.exe $dst /grant '*S-1-5-32-544:F' 2>&1 | Out-Null
  Copy-Item $src $dst -Force -ErrorAction Stop
  & icacls.exe $dst /setowner 'NT SERVICE\TrustedInstaller' 2>&1 | Out-Null
  return $true
}

$gGLInstall = 'belum'
if ($opengl) {
  Copy-Item "$sys32\opengl32.dll" (Join-Path $bkp 'opengl32.dll') -Force -ErrorAction SilentlyContinue
  try {
    Install-SysFile $opengl "$sys32\opengl32.dll" | Out-Null
    Install-SysFile $galium "$sys32\libgallium_wgl.dll" | Out-Null
    Install-SysFile $dxil   "$sys32\dxil.dll" | Out-Null
    $vi = (Get-Item "$sys32\opengl32.dll").VersionInfo
    $gGLInstall = "mesa $($vi.FileVersion) [$($vi.CompanyName)]"
    Log "  llvmpipe terpasang: $sys32\opengl32.dll -> $gGLInstall (asli di-backup ke $bkp)"
  } catch {
    $gGLInstall = 'gagal: ' + $_.Exception.Message
    Log "  GAGAL pasang Mesa ke System32: $($_.Exception.Message)"
    $glDir = Join-Path $root 'gl'
    New-Item -ItemType Directory -Force -Path $glDir | Out-Null
    foreach ($f in @($opengl, $galium, $dxil)) { if ($f) { Copy-Item $f $glDir -Force -ErrorAction SilentlyContinue } }
    Log "  fallback: DLL Mesa disalin ke $glDir (perlu disalin ke folder aplikasi)"
  }
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

# ---- 5b) loader Vulkan (vulkan-1.dll): runner tanpa driver GPU belum punya -
# Tanpa loader, aplikasi Vulkan tidak bisa memakai lavapipe. LunarG menyediakan
# paket "Vulkan Runtime Components" (zip kecil, berisi x64/vulkan-1.dll).
$gVkLoader = ''
$loaderDst = "$sys32\vulkan-1.dll"
if (Test-Path $loaderDst) {
  $gVkLoader = 'sudah ada'
  Log "  loader Vulkan sudah ada: $loaderDst"
} else {
  $vkrt = Join-Path $root 'vulkan-runtime.zip'
  if (Get-File 'https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-runtime-components.zip' $vkrt 300) {
    $zvk = Join-Path $root 'vkrt'
    Remove-Item $zvk -Recurse -Force -ErrorAction SilentlyContinue
    try {
      if ($sevenZip) { & $sevenZip x $vkrt "-o$zvk" -y 2>&1 | Out-Null }
      else { Expand-Archive -Path $vkrt -DestinationPath $zvk -Force }
      $dll = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkan-1.dll' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match '\\x64\\' })
      if ($dll.Count -eq 0) { $dll = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkan-1.dll' -ErrorAction SilentlyContinue) }
      if ($dll.Count -gt 0) {
        Copy-Item $dll[0].FullName $loaderDst -Force -ErrorAction Stop
        $vi = (Get-Item $loaderDst).VersionInfo
        $gVkLoader = "vulkan-1.dll $($vi.FileVersion) (LunarG)".Trim()
        $files += 'vulkan-1.dll'
        Log "  loader Vulkan dipasang: $loaderDst -> $gVkLoader"
      } else {
        Log '  vulkan-1.dll tidak ada di paket runtime LunarG'
      }
      $vex = @(Get-ChildItem $zvk -Recurse -File -Filter 'vulkaninfo.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match '\\x64\\' })
      if ($vex.Count -gt 0) { Copy-Item $vex[0].FullName (Join-Path $root 'vulkaninfo.exe') -Force -ErrorAction SilentlyContinue }
    } catch { Log "  pasang loader Vulkan gagal: $($_.Exception.Message)" }
  } else {
    Log '  unduh runtime Vulkan (LunarG) gagal - loader dilewati'
  }
}

# 5c) daftarkan ICD lavapipe ke registry (cara resmi driver GPU) supaya loader
#     dan aplikasi apa pun menemukannya, tanpa bergantung pada env var saja.
if ($icd) {
  try {
    $vkKey = 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers'
    New-Item -Path $vkKey -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $vkKey -Name $icd -PropertyType DWord -Value 0 -Force | Out-Null
    Log "  ICD lavapipe terdaftar di registry: $vkKey"
  } catch { Log "  daftar ICD ke registry gagal: $($_.Exception.Message)" }
}

# ---- 6) uji nyata: versi OpenGL/Vulkan yang benar-benar didapat ------------
$py = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py.exe -ErrorAction SilentlyContinue }
$env:GALLIUM_DRIVER = 'llvmpipe'; $env:LIBGL_ALWAYS_SOFTWARE = '1'
$gVkDbg = ''
if ($icd) {
  $env:VK_DRIVER_FILES = $icd; $env:VK_ADD_DRIVER_FILES = $icd; $env:VK_ICD_FILENAMES = $icd
  $env:VK_LOADER_DEBUG = 'error,warn,driver'
}

if ($py -and $opengl) {
  try { & $py.Source -m pip install --quiet --disable-pip-version-check moderngl 2>&1 | Out-Null } catch {}
  $code = 'import moderngl;c=moderngl.create_standalone_context();i=c.info;print(i.get("GL_VERSION",""),"|",i.get("GL_RENDERER",""),"|",i.get("GL_VENDOR",""))'
  try {
    $out = ((& $py.Source -c $code 2>&1) | Out-String).Trim()
    if ($out -match '\|') { $gOpenGL = ($out -replace '\s+', ' ') } else { Log "  uji OpenGL: $(($out -split "`n" | Select-Object -Last 1))" }
  } catch { Log "  uji OpenGL gagal: $($_.Exception.Message)" }
}

# Vulkan: minta vulkaninfo (paling otoritatif), lalu fallback ctypes ke loader
$vkOk = $false
$vkinfo = Join-Path $root 'vulkaninfo.exe'
if (Test-Path $vkinfo) {
  try {
    $vo = ((& $vkinfo --summary 2>&1) | Out-String)
    $dn = [regex]::Match($vo, 'deviceName\s*=\s*(.+)').Groups[1].Value.Trim()
    $dt = [regex]::Match($vo, 'deviceType\s*=\s*(.+)').Groups[1].Value.Trim()
    if ($dn) {
      $gVulkan = "$dn $(if ($dt) { "($dt)" })".TrimEnd() -replace '^\s+|\s+$', ''
      $vkOk = $true
      Log "  uji Vulkan: $gVulkan"
    } else {
      $gVkDbg = (($vo -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 20) -join ' ; ')
      Log "  vulkaninfo tanpa device; debug: $gVkDbg"
    }
  } catch { Log "  vulkaninfo gagal: $($_.Exception.Message)" }
}
if ($py -and -not $vkOk) {
  $vkCode = @'
import ctypes
try:
    vk = ctypes.CDLL("vulkan-1.dll")
except OSError:
    print("loader-tidak-ada")
    raise SystemExit
class App(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_uint32), ("pNext", ctypes.c_void_p),
                ("pApplicationName", ctypes.c_char_p), ("applicationVersion", ctypes.c_uint32),
                ("pEngineName", ctypes.c_char_p), ("engineVersion", ctypes.c_uint32),
                ("apiVersion", ctypes.c_uint32)]
class ICI(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_uint32), ("pNext", ctypes.c_void_p), ("flags", ctypes.c_uint32),
                ("pApplicationInfo", ctypes.c_void_p), ("enabledLayerCount", ctypes.c_uint32),
                ("ppEnabledLayerNames", ctypes.c_void_p), ("enabledExtensionCount", ctypes.c_uint32),
                ("ppEnabledExtensionNames", ctypes.c_void_p)]
vk.vkCreateInstance.argtypes = [ctypes.POINTER(ICI), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
vk.vkCreateInstance.restype = ctypes.c_int
vk.vkEnumeratePhysicalDevices.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_void_p)]
vk.vkGetPhysicalDeviceProperties.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
app = App(0, None, b"xyrdp", 1, b"xyrdp", 1, (1 << 22))
ici = ICI(1, None, 0, ctypes.cast(ctypes.pointer(app), ctypes.c_void_p), 0, None, 0, None)
inst = ctypes.c_void_p()
rc = vk.vkCreateInstance(ctypes.byref(ici), None, ctypes.byref(inst))
if rc != 0:
    print("create-instance-error-%d" % rc)
    raise SystemExit
n = ctypes.c_uint32()
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), None)
if n.value == 0:
    print("tanpa-device")
    raise SystemExit
arr = (ctypes.c_void_p * n.value)()
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), arr)
buf = ctypes.create_string_buffer(2048)
vk.vkGetPhysicalDeviceProperties(arr[0], buf)
print(buf.raw[20:276].split(b"\x00")[0].decode("utf-8", "replace"))
'@
  $vkf = Join-Path $root 'vk-probe.py'
  Set-Content -Path $vkf -Value $vkCode -Encoding UTF8
  try {
    $vout = ((& $py.Source $vkf 2>&1) | Out-String).Trim()
    if (-not $gVkDbg -and $vout) { $gVkDbg = (($vout -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 20) -join ' ; ') }
    if ($vout -eq 'loader-tidak-ada') { $gVulkan = "$gVulkan / loader vulkan-1.dll tidak ada" }
    elseif ($vout -match 'create-instance-error|tanpa-device') { $gVulkan = "$gVulkan / uji: $([regex]::Match($vout, 'create-instance-error-\d+|tanpa-device').Value)" }
    elseif ($vout) { $gVulkan = $vout; Log "  uji Vulkan: device = $vout" }
  } catch { Log "  uji Vulkan gagal: $($_.Exception.Message)" }
}

if (-not $gOpenGL) { $gOpenGL = "llvmpipe (Mesa $gMesa) - belum terverifikasi" }
$glVer = [regex]::Match($gOpenGL, '^(\d+\.\d+)').Groups[1].Value
if (-not $glVer) { $glVer = '4.5+' }
if ($gGLInstall -like 'mesa*') {
  $gNote = "GPU software (CPU): OpenGL $glVer (llvmpipe) + Vulkan lavapipe + WARP bawaan. Runner GitHub tanpa GPU fisik; 3D berat tetap lambat."
} else {
  $gNote = "Pasang OpenGL software ke System32 gagal ($gGLInstall). Vulkan lavapipe & WARP tetap aktif; DLL Mesa tersedia di $root\gl untuk pemakaian per-aplikasi."
}
Log "  selesai: OpenGL=$gOpenGL | Vulkan=$(if ($gVulkan) { $gVulkan } else { '-' }) | loader=$(if ($gVkLoader) { $gVkLoader } else { '-' }) | install=$gGLInstall"

try {
  Update-Status @{ grafis = @{
    mode = $gMode; mesa = $gMesa; opengl = $gOpenGL; vulkan = $gVulkan; install = $gGLInstall
    loader = $gVkLoader; debug = $gVkDbg; adapters = $gAdapters; files = ($files -join ','); dir = $root; note = $gNote
  } } | Out-Null
  Log '  status grafis ditulis (grafis.*)'
} catch { Log "  tulis status grafis gagal: $($_.Exception.Message)" }
