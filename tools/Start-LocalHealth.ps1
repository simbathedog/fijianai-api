param(
  [int]$Port = 3010,
  [string]$ProbeUrl = "http://localhost:3000/"   # root is fine; we accept 404 as reachable
)

Add-Type -AssemblyName System.Net.Http

function Write-JsonResponse {
  param(
    [Parameter(Mandatory)][System.Net.HttpListenerContext]$Ctx,
    [Parameter(Mandatory)][hashtable]$Body,
    [int]$StatusCode = 200
  )
  $json  = ($Body | ConvertTo-Json -Depth 6 -Compress)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Ctx.Response.StatusCode  = $StatusCode
  $Ctx.Response.ContentType = "application/json; charset=utf-8"
  $Ctx.Response.Headers["Access-Control-Allow-Origin"]  = "*"
  $Ctx.Response.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  $Ctx.Response.Headers["Access-Control-Allow-Headers"] = "content-type"
  $Ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Ctx.Response.OutputStream.Close()
}

function Probe-Backend {
  param([string]$Url)

  try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # 5s timeout; GET is more compatible than HEAD
    $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -ErrorAction Stop
    $sw.Stop()
    # 2xx is OK
    return @{ ok = $true; status = [int]$resp.StatusCode; ms = [int]$sw.ElapsedMilliseconds }
  } catch {
    if ($_.Exception.Response) {
      # Any HTTP response (3xx/4xx/5xx) means the process is reachable
      $code = $_.Exception.Response.StatusCode.Value__
      return @{ ok = $true; status = [int]$code; ms = $null; note = "reachable, HTTP $code" }
    }
    # Network errors/timeouts mean down
    return @{ ok = $false; error = ($_.Exception.Message) }
  }
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/healthz/")
$listener.Prefixes.Add("http://localhost:$Port/readyz/")
$listener.Prefixes.Add("http://localhost:$Port/")

try {
  $listener.Start()
  Write-Host "Local Health server listening:" -ForegroundColor Cyan
  Write-Host "  http://localhost:$Port/healthz" -ForegroundColor Green
  Write-Host "  http://localhost:$Port/readyz" -ForegroundColor Green
  Write-Host "Ctrl+C to stop." -ForegroundColor Yellow

  while ($true) {
    $ctx  = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath.ToLowerInvariant()

    if ($ctx.Request.HttpMethod -eq 'OPTIONS') {
      $ctx.Response.Headers["Access-Control-Allow-Origin"]  = "*"
      $ctx.Response.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
      $ctx.Response.Headers["Access-Control-Allow-Headers"] = "content-type"
      $ctx.Response.StatusCode = 204
      $ctx.Response.Close()
      continue
    }

    switch ($path) {
      '/healthz' {
        $probe = Probe-Backend -Url $ProbeUrl
        $body  = @{ ok = $true; service='local-health'; target=$ProbeUrl; backend=$probe; time=(Get-Date).ToString("o") }
        Write-JsonResponse -Ctx $ctx -Body $body -StatusCode 200
      }
      '/readyz' {
        $probe   = Probe-Backend -Url $ProbeUrl
        $isReady = $probe.ok  # now true even for HTTP 404/500 since it's reachable
        $body    = @{ ready=$isReady; service='local-health'; target=$ProbeUrl; backend=$probe; time=(Get-Date).ToString("o") }
        Write-JsonResponse -Ctx $ctx -Body $body -StatusCode ($(if($isReady){200}else{503}))
      }
      default {
        $body = @{ ok=$true; info='Use /healthz or /readyz'; time=(Get-Date).ToString("o"); port=$Port }
        Write-JsonResponse -Ctx $ctx -Body $body -StatusCode 200
      }
    }
  }
} finally {
  if ($listener.IsListening) { $listener.Stop() }
  $listener.Close()
}
