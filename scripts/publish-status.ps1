# ============================================================================
#  publish-status.ps1 — push out/rdp-status.json ke branch `status`
#  pakai GITHUB_TOKEN bawaan Actions (contents API, bukan git push).
#  Web dashboard membaca: raw.githubusercontent.com/<owner>/<repo>/status/rdp-status.json
#  File TIDAK berisi password — hanya IP, user, waktu, dsb.
# ============================================================================
param([bool]$Active = $true)
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:status] $m" }

$repo = $env:GITHUB_REPOSITORY
$src  = Join-Path $env:GITHUB_WORKSPACE 'out\rdp-status.json'
if (-not (Test-Path $src)) { Log "tidak ada $src — skip"; exit 0 }

$json = Get-Content $src -Raw | ConvertFrom-Json
if (-not $Active) {
  $json.active = $false
  $json.stopped_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$json | ConvertTo-Json | Set-Content -Path $src -Encoding utf8

# pastikan branch 'status' ada
$sha = $null
try { $sha = ((gh api "repos/$repo/git/refs/heads/status" 2>$null | ConvertFrom-Json).object.sha) } catch {}
if (-not $sha) {
  $def = (gh api "repos/$repo" | ConvertFrom-Json).default_branch
  $defSha = (gh api "repos/$repo/git/ref/heads/$def" | ConvertFrom-Json).object.sha
  gh api "repos/$repo/git/refs" -f ref="refs/heads/status" -f sha=$defSha 2>&1 | Out-Null
  Log "branch 'status' dibuat dari $def"
}

# sha file lama (buat update) — 404 kalau belum ada
$fileSha = $null
try { $fileSha = (gh api "repos/$repo/contents/rdp-status.json?ref=status" 2>$null | ConvertFrom-Json).sha } catch {}

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
$args = @('api', "repos/$repo/contents/rdp-status.json", '-X', 'PUT',
          '-H', 'Accept: application/vnd.github+json',
          '-f', 'message=XyRDP status update',
          '-f', "content=$b64",
          '-f', 'branch=status')
if ($fileSha) { $args += @('-f', "sha=$fileSha") }

& gh @args 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Log "status dipublikasikan (active=$($json.active)) → $repo @ branch status"
  Log "raw: https://raw.githubusercontent.com/$repo/status/rdp-status.json"
} else {
  Log "PUBLISH GAGANG (exit $LASTEXITCODE) — web dashboard tetap bisa baca dari log run"
}
exit 0
