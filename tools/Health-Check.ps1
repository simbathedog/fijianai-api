param(
  [string]$Hostname   = "api.oceansai.org",
  [string]$Origin     = "https://www.oceansai.org",
  [string]$Path       = "/healthz",
  [int]$TimeoutSec    = 12,
  [string]$LogPath    = "C:\Projects\fijianai-api\logs\health-agent.log",
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# ensure log dir
$logDir = Split-Path $LogPath -Parent
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date).ToString("s"), $msg
  Add-Content -Path $LogPath -Value $line
  if (-not $Quiet) { Write-Host $line }
}

$ok  = $true
$why = @()
$Url = "https://$Hostname$Path"

# 1) CORS preflight
try {
  $preHeaders = @{
    'Origin'                        = $Origin
    'Access-Control-Request-Method' = 'GET'
    'Access-Control-Request-Headers'= 'content-type'
  }
  $pre = Invoke-WebRequest $Url -Method Options -Headers $preHeaders -TimeoutSec $TimeoutSec -UseBasicParsing
  $acao = $pre.Headers['Access-Control-Allow-Origin']
  if (-not ($pre.StatusCode -in 200,204)) { $ok = $false; $why += "OPTIONS:$($pre.StatusCode)" }
  if (-not ($acao -eq $Origin -or $acao -eq '*')) { $ok = $false; $why += "OPTIONS:ACAO=$acao" }
} catch {
  $ok = $false; $why += "OPTIONS: $($_.Exception.Message)"
}

# 2) GET with Origin
try {
  $get = Invoke-WebRequest $Url -Headers @{ Origin = $Origin } -TimeoutSec $TimeoutSec -UseBasicParsing
  $acao = $get.Headers['Access-Control-Allow-Origin']
  if ($get.StatusCode -ne 200) { $ok = $false; $why += "GET:$($get.StatusCode)" }
  if (-not ($acao -eq $Origin -or $acao -eq '*')) { $ok = $false; $why += "GET:ACAO=$acao" }
} catch {
  $ok = $false; $why += "GET: $($_.Exception.Message)"
}

if ($ok) {
  Log "OK $Hostname$Path (CORS/200 good)"
  exit 0
} else {
  Log "FAIL $Hostname$Path -> $([string]::Join('; ', $why))"
  exit 2
}
