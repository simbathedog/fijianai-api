param(
  [switch]$PreferGhPages,
  [switch]$OpenUrl,
  [switch]$Stamp,
  [string]$Domain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Fail($m){ Write-Error $m; exit 1 }

# --- Work from the script's repo, not the current directory ---
$scriptDir = Split-Path -Parent $PSCommandPath
$root = (git -C $scriptDir rev-parse --show-toplevel) 2>$null
if (-not $root) { $root = $scriptDir }
Set-Location $root

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git not found in PATH." }

# --- Locate built site output (index.html) ---
$candidates = @(
  "dist\site-english-latest\public",
  "dist\public",
  "build",
  "public"
)
$src = $null
foreach($p in $candidates){
  $full = Join-Path $root $p
  if (Test-Path (Join-Path $full "index.html")) { $src = $full; break }
}
if (-not $src) {
  Write-Host "No site output found (need an index.html)." -ForegroundColor Yellow
  Write-Host "Looked for: $($candidates -join ', ')"
  exit 1
}

# --- Prepare or reuse gh-pages worktree ---
git fetch origin | Out-Null
$worktree = Join-Path $root ".gh-pages"

if (-not (Test-Path $worktree)) {
  git worktree prune | Out-Null
  $attached = $true
  try { git worktree add -B gh-pages $worktree origin/gh-pages | Out-Null } catch { $attached = $false }
  if (-not $attached) { git worktree add -B gh-pages $worktree | Out-Null }
}

Push-Location $worktree

# --- Clean previous files (keep .git) and copy new site ---
Get-ChildItem -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $src "*") -Destination $worktree -Recurse -Force

# --- Pages conveniences ---
New-Item -ItemType File -Path ".nojekyll" -Force | Out-Null
@"
* text=auto
*.html text eol=lf
*.css  text eol=lf
*.js   text eol=lf
*.txt  text eol=lf
"@ | Set-Content -Path ".gitattributes" -Encoding ASCII

# --- Optional custom domain (CNAME) ---
if ($Domain) {
  Set-Content -Path "CNAME" -Value $Domain -Encoding ASCII
} elseif ($env:GH_PAGES_DOMAIN) {
  Set-Content -Path "CNAME" -Value $env:GH_PAGES_DOMAIN -Encoding ASCII
}

# --- Optional stamp to force a commit every publish ---
if ($Stamp) {
  Set-Content -Path ".deploy-stamp.txt" -Value ("Deployed " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding ASCII
}

# --- Commit + push if there are changes ---
git add -A
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  $msg = "Publish site $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  git -c user.name='FijiEd Bot' -c user.email='noreply@example.com' commit -m $msg | Out-Null
  git push -u origin gh-pages
  Write-Host "✔ Published to gh-pages." -ForegroundColor Green
} else {
  Write-Host "Nothing to publish; gh-pages already up to date." -ForegroundColor Cyan
}

# --- Open the Pages URL if requested ---
if ($OpenUrl) {
  $remote = (git config --get remote.origin.url)
  if ($remote -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^\.]+)') {
    $owner = $matches.owner; $repo = $matches.repo
    $url = "https://$owner.github.io/$repo/"
    try { Start-Process $url } catch { Write-Host $url }
    Write-Host "Page: $url"
  }
}

Pop-Location
