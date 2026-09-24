# ============================================================================
#  publish-status.ps1 — publikasikan out/rdp-status.json ke branch `status`
#  1) GitHub Contents API via Invoke-RestMethod (Bearer GITHUB_TOKEN)  <- utama
#  2) Fallback: git push pakai header "Authorization: Bearer"          <- terbukti jalan
#  Verifikasi via raw.githubusercontent (retry). Publish gagal TIDAK
#  mematikan sesi (exit 0) — web dashboard masih bisa baca IP dari log run.
#  File TIDAK berisi password.
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
$json | ConvertTo-Json -Depth 6 | Set-Content -Path $src -Encoding utf8

function GH([string]$method, [string]$apiPath, $body) {
  $hdrs = @{ Authorization = "Bearer $env:GITHUB_TOKEN"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'XyRDP' }
  try {
    $p = @{ Uri = "https://api.github.com$apiPath"; Method = $method; Headers = $hdrs }
    if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 6); $p.ContentType = 'application/json' }
    Invoke-RestMethod @p
  } catch { Log "GH $method $apiPath -> $($_.Exception.Message)"; $null }
}

# ---- cara 1: Contents API ----
try {
  $ref = GH 'GET' "/repos/$repo/git/ref/heads/status" $null
  if (-not $ref) {
    $db   = (GH 'GET' "/repos/$repo" $null).default_branch
    $sha0 = (GH 'GET' "/repos/$repo/git/ref/heads/$db" $null).object.sha
    if (-not $sha0) { throw "default branch sha tidak diketahui" }
    GH 'POST' "/repos/$repo/git/refs" @{ ref = 'refs/heads/status'; sha = $sha0 } | Out-Null
    Log "branch 'status' dibuat (via API)"
  }
  $b64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
  $body = @{ message = "XyRDP status update (run $($env:GITHUB_RUN_NUMBER))"; content = $b64; branch = 'status' }
  $cur  = GH 'GET' "/repos/$repo/contents/rdp-status.json?ref=status" $null
  if ($cur -and $cur.sha) { $body.sha = $cur.sha }
  $res = GH 'PUT' "/repos/$repo/contents/rdp-status.json" $body
  if ($res -and $res.content) { Log "Contents API OK (commit $($res.commit.sha.Substring(0,7)))" } else { throw "PUT contents tidak mengembalikan hasil" }
} catch { Log "cara-1 gagal ($($_.Exception.Message)) — lanjut fallback git" }

# ---- cara 2 (fallback): git push + Bearer header ----
function Verify-Published {
  for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Seconds 5
    try {
      $r = Invoke-RestMethod "https://raw.githubusercontent.com/$repo/status/rdp-status.json?r=$i$((Get-Date).Minute)" -TimeoutSec 10
      if ($r -and "$($r.run_id)" -eq "$($env:GITHUB_RUN_ID)") { return $true }
    } catch {}
  }
  return $false
}

function Verify-PublishedAPI {
  try {
    $c = GH 'GET' "/repos/$repo/contents/rdp-status.json?ref=status" $null
    if ($c -and $c.content) {
      $t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($c.content)) | ConvertFrom-Json
      return "$($t.run_id)" -eq "$($env:GITHUB_RUN_ID)"
    }
  } catch {}
  return $false
}

if (-not (Verify-PublishedAPI) -and -not (Verify-Published)) {
  Log "verifikasi belum lolos — coba fallback git push..."
  $tmp = Join-Path $env:RUNNER_TEMP ("xyrdpstatus-" + (Get-Random -Maximum 999999))
  try {
    git init -q -b status $tmp | Out-Null
    Copy-Item $src (Join-Path $tmp 'rdp-status.json') -Force
    Push-Location $tmp
    git config user.name  "github-actions[bot]" | Out-Null
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com" | Out-Null
    git add rdp-status.json
    git -c commit.gpgsign=false commit -q -m "XyRDP status update" | Out-Null
    $out = git -c "http.extraHeader=Authorization: Bearer $env:GITHUB_TOKEN" push --force "https://github.com/$repo.git" "HEAD:refs/heads/status" 2>&1
    $out | ForEach-Object { Log "git: $_" }
    Pop-Location
  } catch {
    if ((Get-Location).Path -eq $tmp) { Pop-Location }
    Log "git push error: $($_.Exception.Message)"
  }
}

if (Verify-Published) {
  Log "OK — rdp-status.json (active=$($json.active)) live: https://raw.githubusercontent.com/$repo/status/rdp-status.json"
} else {
  Log "status belum terverifikasi via raw (cache bisa telat s/d 5 menit; web pakai fallback API + parser log). Sesi TETAP jalan."
}
exit 0
