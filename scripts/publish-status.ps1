# ============================================================================
#  publish-status.ps1 — push out/rdp-status.json ke branch `status`
#  Cara 1: GitHub contents API via `gh` (pakai GITHUB_TOKEN bawaan Actions)
#  Cara 2 (fallback): git push branch `status`
#  Setelah itu VERIFIKASI file benar-benar terbaca; kalau dua-duanya gagal -> exit 1.
#  Web dashboard membaca: raw.githubusercontent.com/<owner>/<repo>/status/rdp-status.json
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
$json | ConvertTo-Json | Set-Content -Path $src -Encoding utf8

function Verify-Published {
  try {
    $r = (gh api "repos/$repo/contents/rdp-status.json?ref=status" 2>$null | ConvertFrom-Json)
    return ($r -and $r.content)
  } catch { return $false }
}

# ---- Cara 1: contents API ----
try {
  $sha = $null
  $refJson = gh api "repos/$repo/git/refs/heads/status" 2>$null | ConvertFrom-Json
  if ($refJson -and $refJson.object) { $sha = $refJson.object.sha }
  if (-not $sha) {
    $def = (gh api "repos/$repo" 2>$null | ConvertFrom-Json).default_branch
    $defSha = (gh api "repos/$repo/git/ref/heads/$def" 2>$null | ConvertFrom-Json).object.sha
    if (-not $defSha) { throw "gagal ambil sha branch $def" }
    gh api "repos/$repo/git/refs" -f ref="refs/heads/status" -f sha=$defSha 2>&1 | Out-Null
    Log "branch 'status' dibuat dari $def"
  }
  $fileSha = $null
  $fj = gh api "repos/$repo/contents/rdp-status.json?ref=status" 2>$null | ConvertFrom-Json
  if ($fj -and $fj.sha) { $fileSha = $fj.sha }

  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
  $ghArgs = @('api', "repos/$repo/contents/rdp-status.json", '-X', 'PUT',
              '-H', 'Accept: application/vnd.github+json',
              '-f', 'message=XyRDP status update',
              '-f', "content=$b64",
              '-f', 'branch=status')
  if ($fileSha) { $ghArgs += @('-f', "sha=$fileSha") }
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    & gh @ghArgs 2>&1 | ForEach-Object { Log "gh: $_" }
  } else { throw "gh CLI tidak ada di PATH" }
} catch {
  Log "contents API gagal ($($_.Exception.Message)) — fallback ke git push"
}

# ---- Cara 2 (fallback): git push ----
if (-not (Verify-Published)) {
  try {
    Push-Location $env:GITHUB_WORKSPACE
    git config user.name  "github-actions[bot]" | Out-Null
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com" | Out-Null
    git checkout --orphan status 2>&1 | Out-Null
    git rm -r --cached . -q 2>&1 | Out-Null
    Copy-Item $src (Join-Path $env:GITHUB_WORKSPACE 'rdp-status.json') -Force
    git add rdp-status.json
    git commit -m "XyRDP status update" --no-verify 2>&1 | Out-Null
    $auth = "https://x-access-token:${env:GITHUB_TOKEN}@github.com/${repo}.git"
    git -c "http.extraHeader=Authorization: Bearer $env:GITHUB_TOKEN" push --force $auth status:status 2>&1 | ForEach-Object { Log "git: $_" }
    Log "git push branch status selesai"
  } catch { Log "git push juga gagal: $($_.Exception.Message)" }
  finally { Pop-Location }
}

if (Verify-Published) {
  Log "OK — status aktif=$($json.active) terbaca di https://raw.githubusercontent.com/$repo/status/rdp-status.json"
  exit 0
}
Log "GAGAL mempublikasikan status (cek permissions contents:write). Web dashboard masih bisa baca IP dari log run."
exit 1
