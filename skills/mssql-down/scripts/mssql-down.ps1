#Requires -Version 7.0
<#
.SYNOPSIS
    Stop the shared SQL Server used by BC instances.

.DESCRIPTION
    Stops the container by default, which keeps the databases. -Remove deletes
    the container but still keeps the data volume; -Purge deletes the data too
    and is the only option that loses every instance's database.

.EXAMPLE
    ./mssql-down.ps1
    ./mssql-down.ps1 -Remove
    ./mssql-down.ps1 -Purge
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Purge,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$platformHome = if ($env:BC_PLATFORM_HOME) { $env:BC_PLATFORM_HOME } else { Join-Path $HOME '.bc-platform' }
$projectDir   = Join-Path $platformHome 'mssql'

if (-not (Test-Path (Join-Path $projectDir 'docker-compose.yml'))) {
    throw "No shared SQL Server found at $projectDir. Run the mssql-up skill first."
}

# Refuse to take the database down from under a running instance unless told
# twice: every BC container on the network would start failing SQL calls.
$running = @(docker ps --filter 'label=com.docker.compose.project' --format '{{.Label "com.docker.compose.project"}}' |
    Where-Object { $_ -like 'bc-*' -and $_ -notin @('bc-mssql', 'bc-traefik') } | Select-Object -Unique)
if ($running.Count -and -not $Purge -and -not $Remove) {
    Write-Warning "BC instances still running: $($running -join ', '). They will lose their database connection."
}

$composeArgs = if ($Purge) { @('down', '-v') } elseif ($Remove) { @('down') } else { @('stop') }
$action = $composeArgs -join ' '
docker compose --project-directory $projectDir $composeArgs | Out-Host

$result = [ordered]@{
    project          = 'bc-mssql'
    action           = $action
    dataKept         = -not $Purge.IsPresent
    instancesRunning = ($running -join ', ')
}
if ($Json) { $result | ConvertTo-Json } else {
    $result.GetEnumerator() | ForEach-Object { '{0,-17} {1}' -f $_.Key, $_.Value }
}
