param(
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][string]$SiteUrl
)

# Normalize base URL (no trailing slash)
if ($SiteUrl.EndsWith('/')) { $SiteUrl = $SiteUrl.TrimEnd('/') }

# Collect .html files (ignore 404/500-style pages if present)
$root = Resolve-Path $OutDir
$files = Get-ChildItem -Path $root -Recurse -Filter *.html -File | Where-Object {
  $_.Name -notin @('404.html','500.html')
}

# Build URL entries
$entries = @()
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Path.Length).TrimStart('\','/')
  $urlPath = '/' + ($rel -replace '\\','/')

  # Convert /path/index.html -> /path/
  if ($urlPath -match '/index\.html$') {
    $urlPath = $urlPath -replace 'index\.html$', ''
  } elseif ($urlPath -match '\.html$') {
    # Convert /foo.html -> /foo
    $urlPath = $urlPath -replace '\.html$', ''
  }

  # Root case: index at site root -> '/'
  if ($urlPath -eq '') { $urlPath = '/' }

  $loc = "$SiteUrl$urlPath"
  $lastmod = $f.LastWriteTimeUtc.ToString('yyyy-MM-dd')
  $entries += [PSCustomObject]@{
    loc        = $loc
    lastmod    = $lastmod
    changefreq = 'weekly'
    priority   = '0.7'
  }
}

# Deduplicate (in case both / and /index.html got mapped)
$entries = $entries | Sort-Object loc -Unique

# Write sitemap.xml
$sitemapPath = Join-Path $root 'sitemap.xml'
$xmlHeader = '<?xml version="1.0" encoding="UTF-8"?>'
$urlsetOpen = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
$urlsetClose = '</urlset>'

# Simple XML builder
$content = New-Object System.Collections.Generic.List[string]
$content.Add($xmlHeader)
$content.Add($urlsetOpen)
foreach ($e in $entries) {
  $content.Add("  <url>")
  $content.Add("    <loc>$($e.loc)</loc>")
  $content.Add("    <lastmod>$($e.lastmod)</lastmod>")
  $content.Add("    <changefreq>$($e.changefreq)</changefreq>")
  $content.Add("    <priority>$($e.priority)</priority>")
  $content.Add("  </url>")
}
$content.Add($urlsetClose)
[IO.File]::WriteAllLines($sitemapPath, $content, [Text.UTF8Encoding]::new($false))

# Write robots.txt (idempotent; update if present)
$robotsPath = Join-Path $root 'robots.txt'
$robots = @"
User-agent: *
Allow: /

Sitemap: $SiteUrl/sitemap.xml
"@
$robots | Set-Content -Path $robotsPath -Encoding UTF8

Write-Host "Wrote sitemap.xml and robots.txt to $root" -ForegroundColor Green
