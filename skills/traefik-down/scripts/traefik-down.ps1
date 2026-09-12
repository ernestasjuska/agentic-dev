#Requires -Version 7.0
<#
.SYNOPSIS
    Stop the shared Traefik reverse proxy.

.DESCRIPTION
    Stops the container by default; -Remove deletes it. Backends keep running
    either way, they just stop being reachable through the shared port. Nothing
    here has state worth purging: the generated compose and dynamic config are
    rewritten on every traefik-up.

.EXAMPLE
    ./traefik-down.ps1
    ./traefik-down.ps1 -Remove
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$platformHome = if ($env:BC_PLATFORM_HOME) { $env:BC_PLATFORM_HOME } else { Join-Path $HOME '.bc-platform' }
$projectDir   = Join-Path $platformHome 'traefik'

if (-not (Test-Path (Join-Path $projectDir 'docker-compose.yml'))) {
    throw "No shared Traefik found at $projectDir. Run the traefik-up skill first."
}

# Name the backends that are about to go dark, so the caller is not surprised.
$routed = @(docker ps --filter 'label=traefik.enable=true' --format '{{.Names}}')

$action = if ($Remove) { 'down' } else { 'stop' }
docker compose --project-directory $projectDir $action | Out-Host

$result = [ordered]@{
    project         = 'bc-traefik'
    action          = $action
    backendsStillUp = ($routed -join ', ')
}
if ($Json) { $result | ConvertTo-Json } else {
    $result.GetEnumerator() | ForEach-Object { '{0,-16} {1}' -f $_.Key, $_.Value }
}
