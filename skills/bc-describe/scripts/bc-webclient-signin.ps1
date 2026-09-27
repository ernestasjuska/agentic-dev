#Requires -Version 7.0
<#
.SYNOPSIS
    Sign in to a Business Central web client and report whether a Role Center rendered.

.DESCRIPTION
    A 200 from the web client proves only that Kestrel is up. This signs in for
    real and reports the three things that actually distinguish a working
    instance from a broken one: whether a Role Center rendered, whether the
    /csh WebSocket exchanged frames, and which requests returned 4xx.

    Three traps it handles, each of which has cost an afternoon before:

      - The SPA renders in an iframe, so the outer document's innerText shows
        only the chrome. Every frame is concatenated before deciding.
      - A devtunnel shows an anti-phishing interstitial to browsers once per
        tunnel. curl never sees it, so a curl probe looks healthier than a
        browser. The Continue button is clicked when present.
      - Credentials come from the container rather than being passed on the
        command line, so they stay out of shell history and transcripts.

    Needs playwright-core and a Chromium build. Point -Chrome at one, or let it
    find the Playwright cache.

.EXAMPLE
    ./bc-webclient-signin.ps1 bc30
    ./bc-webclient-signin.ps1 bc30 -Url https://host/bc30/ -Screenshot /tmp/rc.png
    ./bc-webclient-signin.ps1 bc30 -DisableHttp2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,
    # Defaults to the container IP and the instance's path base. Pass the public
    # URL to test the proxy and tunnel path instead of the container directly.
    [string]$Url,
    [string]$Screenshot,
    # BC's /csh upgrade fails with 400 on an HTTPS listener that offers HTTP/2
    # through ALPN. Use this to confirm that is what you are looking at.
    [switch]$DisableHttp2,
    [int]$TimeoutSeconds = 120,
    [string]$Chrome,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$container = "bc-$Name"

if (-not (docker ps --format '{{.Names}}' | Where-Object { $_ -eq $container })) {
    throw "Container $container is not running. Use the bc-ps skill to see what exists."
}

$user = (docker exec $container printenv BC_SERVER_USERNAME).Trim()
$pass = (docker exec $container printenv BC_SERVER_PASSWORD).Trim()
if (-not $user -or -not $pass) { throw "$container exposes no BC_SERVER_USERNAME/BC_SERVER_PASSWORD." }

if (-not $Url) {
    $ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $container).Trim().Split(' ')[0]
    $manifest = Join-Path $HOME ".bc-platform/instances/$Name.env"
    $pathBase = ''
    if (Test-Path $manifest) {
        $line = Get-Content $manifest | Where-Object { $_ -like 'BC_WEBCLIENT_PATHBASE=*' } | Select-Object -First 1
        if ($line) { $pathBase = ($line -split '=', 2)[1] }
    }
    # The listener is https only on branches that ship the cert plumbing; probe.
    $scheme = 'http'
    try {
        $null = Invoke-WebRequest -Uri "https://${ip}:8080$pathBase/" -SkipCertificateCheck -MaximumRedirection 0 -TimeoutSec 8 -ErrorAction Stop
        $scheme = 'https'
    } catch {
        if ($_.Exception.Response) { $scheme = 'https' }
    }
    $Url = "${scheme}://${ip}:8080$pathBase/"
}

if (-not $Chrome) {
    $Chrome = Get-ChildItem -Path (Join-Path $HOME '.cache/ms-playwright') -Filter 'chrome' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*chrome-linux*' } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Chrome -or -not (Test-Path $Chrome)) { throw "No Chromium found. Pass -Chrome <path to chrome>." }

$script = Join-Path $PSScriptRoot 'webclient-signin.mjs'
$pollMs = 8000
$cfg = @{
    url          = $Url
    user         = $user
    password     = $pass
    chrome       = $Chrome
    disableHttp2 = [bool]$DisableHttp2
    screenshot   = $Screenshot
    pollMs       = $pollMs
    pollCount    = [Math]::Max(3, [int]($TimeoutSeconds * 1000 / $pollMs))
} | ConvertTo-Json -Compress

# playwright-core resolves from the script directory; install it once there.
Push-Location $PSScriptRoot
try {
    if (-not (Test-Path (Join-Path $PSScriptRoot 'node_modules/playwright-core'))) {
        Write-Host "[signin] installing playwright-core next to the script"
        npm install playwright-core --no-audit --no-fund --silent 2>&1 | Out-Null
    }
    $raw = node $script $cfg
} finally { Pop-Location }

$result = $raw | ConvertFrom-Json
if ($Json) { $result | ConvertTo-Json -Depth 5; return }

Write-Host ""
Write-Host "  instance   $Name"
Write-Host "  url        $($result.url)"
if ($result.interstitial) { Write-Host "  tunnel     clicked the devtunnel interstitial" }
Write-Host "  verdict    $($result.verdict)"
Write-Host "  websocket  $($result.webSocket)"
Write-Host "  http 4xx   $(if ($result.httpFailures) { $result.httpFailures -join ' | ' } else { 'none' })"
if ($result.screenshot) { Write-Host "  screenshot $($result.screenshot)" }
Write-Host ""

if ($result.verdict -notlike 'ROLE CENTER OK*') { exit 1 }
