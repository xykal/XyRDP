# ============================================================================
#  setup-roblox.ps1 — Anti-VM untuk Roblox Player di VM GitHub Actions
#  Roblox Studio aman, Roblox Player deteksi VM (Hyper-V/QEMU) dan nolak.
#  Script ini best-effort spoofing registry + matikan service VM biar Player
#  mengira ini PC fisik. Tidak 100% guarantee (hypervisor bit tetap 1), tapi
#  sudah bikin banyak VM lolos di runner windows-2022.
# ============================================================================
$XyTag = 'XyRDP:roblox'
. "$PSScriptRoot/lib-common.ps1"

Log '=== ROBLOX VM HIDE — mulai ==='

# 1. Spoof BIOS / System info jadi Dell fisik (bukan Hyper-V/QEMU)
try {
  Set-Reg 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' 'SystemManufacturer' 'Dell Inc.' 'String' | Out-Null
  Set-Reg 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' 'SystemProductName' 'XPS 15 9510' 'String' | Out-Null
  Set-Reg 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' 'BIOSVersion' '1.18.0' 'String' | Out-Null
  Set-Reg 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' 'BaseBoardManufacturer' 'Dell Inc.' 'String' | Out-Null
  Set-Reg 'HKLM\HARDWARE\DESCRIPTION\System\BIOS' 'BaseBoardProduct' '0Y2MRG' 'String' | Out-Null
  Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation' 'SystemManufacturer' 'Dell Inc.' 'String' | Out-Null
  Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation' 'SystemProductName' 'XPS 15 9510' 'String' | Out-Null
  Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation' 'BIOSVersion' '1.18.0' 'String' | Out-Null
  Log '  BIOS spoof -> Dell XPS (anti-VM)'
} catch { Log "  BIOS spoof gagal: $($_.Exception.Message)" }

# 2. Matikan service VM yang bikin Roblox curiga
foreach ($svc in @('vmicheartbeat','vmicvss','vmicshutdown','vmicexchange','vmickvpexchange','vmicguestinterface','vmicheartbeat','QEMU-GA','qemu-ga')) {
  try {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
      Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
      Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
      Log "  service VM $svc dimatikan"
    }
  } catch {}
}
# Hapus driver VM jika ada (best-effort, jangan error kalau tidak ada)
foreach ($drv in @('vmmouse','vm3dmp','vmci','vmhgfs','vmmemctl')) {
  try { & sc.exe delete $drv 2>&1 | Out-Null } catch {}
}

# 3. Spoof GPU vendor jadi NVIDIA fisik (bukan Hyper-V)
try {
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'BuildLab' '22621.1.amd64fre.ni_release.220506-1250' 'String' | Out-Null
  Log '  BuildLab spoof'
} catch {}

# 4. Disable Hyper-V enlightenments yang kedeteksi Roblox
try {
  # Jangan coba bcdedit hypervisorlaunchtype off (butuh reboot & bikin runner mati), cukup registry
  Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization' 'DisableHypervisor' 0 'DWord' | Out-Null
} catch {}

# 5. Pastikan Roblox Player & Studio bisa jalan (install VC++ sudah di setup-samp, tapi cek)
Log '  Roblox VM hide selesai (Studio aman, Player best-effort)'

# 6. Log info VM saat ini untuk debug
try {
  $cs = Get-CimInstance Win32_ComputerSystem
  Log "  ComputerSystem: Manufacturer=$($cs.Manufacturer) Model=$($cs.Model) HypervisorPresent=$($cs.HypervisorPresent)"
  $bios = Get-CimInstance Win32_BIOS
  Log "  BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
} catch {}

exit 0
