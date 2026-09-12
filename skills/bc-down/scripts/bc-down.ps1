#Requires -Version 7.0
<#
.SYNOPSIS
    Stop one named Business Central instance.

.DESCRIPTION
    Stops only that instance's compose project. The shared SQL Server, the
    shared proxy and every other instance keep running, and the instance's
    databases survive.

    -Remove deletes the containers as well. That costs a re-provision and, for
    an Entra-enabled instance, a fresh sign-in: BC does not persist its
    DataProtection keys, so auth cookies stop validating.

    -Purge additionally deletes the instance's volumes and its manifest, which
    is the only form that discards the instance for good.

.EXAMPLE
    ./bc-down.ps1 bc28
    ./bc-down.ps1 bc28 -Remove
    ./bc-down.ps1 bc28 -Purge
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,
    [switch]$Remove,
    [switch]$Purge,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$platformHome = if ($env:BC_PLATFORM_HOME) { $env:BC_PLATFORM_HOME } else { Join-Path $HOME '.bc-platform' }
$instanceDir  = Join-Path $platformHome "instances/$Name"
$manifest     = Join-Path $platformHome "instances/$Name.env"
$composeFile  = Join-Path $instanceDir 'docker-compose.yml'

if (-not (Test-Path $composeFile)) {
    throw "No instance '$Name' at $instanceDir. Run the bc-ps skill to see what exists."
}

$composeArgs = if ($Purge) { @('down', '-v') } elseif ($Remove) { @('down') } else { @('stop') }
docker compose -f $composeFile --project-directory $instanceDir $composeArgs | Out-Host

if ($Purge) {
    Remove-Item -Recurse -Force $instanceDir -ErrorAction SilentlyContinue
    Remove-Item -Force $manifest -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    instance      = $Name
    action        = ($composeArgs -join ' ')
    databasesKept = -not $Purge.IsPresent
    manifestKept  = (Test-Path $manifest)
}
if ($Json) { $result | ConvertTo-Json } else {
    $result.GetEnumerator() | ForEach-Object { '{0,-14} {1}' -f $_.Key, $_.Value }
}
