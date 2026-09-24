# ============================================================================
#  publish-status.ps1 — publikasikan out/rdp-status.json ke branch `status`
#  via git push (GITHUB_TOKEN bawaan Actions, repo sama). Tanpa dependensi gh.
#  Web dashboard membaca: raw.githubusercontent.com/<owner>/<repo>/status/rdp-status.json
#  File TIDAK berisi password. Kegalahan publish TIDAK menggagalkan sesi (exit 0).
# ============================================================================
param([bool]$Active = $true)
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:status] $m" }

$repo = $env:GITHUB_REPOSITORY
$src  = Join-Path $env:GITHUB_WORKSPACE 'out\rdp-status.json'
if (-not (Test-Path $src)) { Log "tidak ada $src — skip"; exit 0 }

$json = Get-Content $src -Raw | ConvertFrom-Json
if (-not $Active) {
  $json | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') -Force
  $json.active = $false
}
$json | ConvertTo-Json | Set-Content -Path $src -Encoding utf8

# push di working copy sementara (biar checkout utama tidak berubah)
$tmp = Join-Path $env:RUNNER_TEMP ("xyrdpstatus-" + (Get-Random -Maximum 999999))
try {
  git init -q -b status $tmp | Out-Null
  Copy-Item $src (Join-Path $tmp 'rdp-status.json') -Force
  Push-Location $tmp
  git config user.name  "github-actions[bot]" | Out-Null
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com" | Out-Null
  git add rdp-status.json
  git -c commit.gpgsign=false commit -q -m "XyRDP status update (active=$($json.active))" | Out-Null
  $auth = "https://x-access-token:${env:GITHUB_TOKEN}@github.com/${repo}.git"
  $out = git push --force $auth "HEAD:status" 2>&1
  $out | ForEach-Object { Log "git: $_" }
  Pop-Location
} catch {
  if ((Get-Location).Path -eq $tmp) { Pop-Location }
  Log "git push error: $($_.Exception.Message)"
}

# verifikasi lewat raw (retry; raw kadang telat beberapa detik)
$ok = $false
for ($i = 0; $i -lt 6 -and -not $ok; $i++) {
  Start-Sleep -Seconds 5
  try {
    $r = Invoke-RestMethod "https://raw.githubusercontent.com/$repo/status/rdp-status.json?t=$((Get-Date).UnixTimeMilliseconds)" -TimeoutSec 10
    if ($r -and ($r.run_id -eq $env:GITHUB_RUN_ID)) { $ok = $true }
  } catch {}
}
if ($ok) {
  Log "OK — rdp-status.json (active=$($json.active)) live di branch status"
} else {
  Log "VERIFIKASI RAW BELUM KETEMU — kemungkinan cache; web dashboard pakai fallback API contents, biasanya tetap kebaca."
}
exit 0
