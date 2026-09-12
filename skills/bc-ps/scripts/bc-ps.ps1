#Requires -Version 7.0
<#
.SYNOPSIS
    List the Business Central instances on this machine and the shared services
    they depend on.

.DESCRIPTION
    Shows every instance that has a manifest, not only the running ones, so a
    stopped instance is still visible and can be started again by name. The
    shared SQL Server and proxy are listed separately because they are not
    owned by any instance.

.EXAMPLE
    ./bc-ps.ps1
    ./bc-ps.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$platformHome = if ($env:BC_PLATFORM_HOME) { $env:BC_PLATFORM_HOME } else { Join-Path $HOME '.bc-platform' }
$instancesDir = Join-Path $platformHome 'instances'

function Read-EnvFile([string]$path) {
    $map = [ordered]@{}
    if (Test-Path $path) {
        foreach ($line in Get-Content $path) {
            if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
            $k, $v = $line -split '=', 2
            $map[$k.Trim()] = $v
        }
    }
    $map
}

function Get-ContainerState([string]$name) {
    $state  = (docker inspect $name --format '{{.State.Status}}' 2>$null)
    $health = (docker inspect $name --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' 2>$null)
    if (-not $state) { return [pscustomobject]@{ state = 'absent'; health = '-' } }
    [pscustomobject]@{ state = $state; health = $health }
}

$instances = @()
foreach ($file in (Get-ChildItem -Path $instancesDir -Filter '*.env' -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cfg  = Read-EnvFile $file.FullName
    $st   = Get-ContainerState "bc-$name"
    $instances += [pscustomobject]@{
        instance  = $name
        state     = $st.state
        health    = $st.health
        portBase  = $cfg['BC_PORT_BASE']
        webClient = if ($cfg['BC_WEBCLIENT_PUBLIC_URL']) { $cfg['BC_WEBCLIENT_PUBLIC_URL'] } else { '-' }
        repo      = $cfg['BC_ON_LINUX_DIR']
    }
}

$sqlState     = Get-ContainerState 'bc-mssql'
$traefikState = Get-ContainerState 'bc-traefik'
$sqlCfg       = Read-EnvFile (Join-Path $platformHome 'mssql/.env')
$traefikCfg   = Read-EnvFile (Join-Path $platformHome 'traefik/.env')

$shared = @(
    [pscustomobject]@{ service = 'sql'; container = 'bc-mssql'; state = $sqlState.state; health = $sqlState.health
                       address = "localhost,$($sqlCfg['SQL_PORT'])" }
    [pscustomobject]@{ service = 'traefik'; container = 'bc-traefik'; state = $traefikState.state; health = $traefikState.health
                       address = "http://localhost:$($traefikCfg['TRAEFIK_PORT']) -> $($traefikCfg['PUBLIC_HOST'])" }
)

if ($Json) {
    [ordered]@{ instances = $instances; shared = $shared } | ConvertTo-Json -Depth 6
} else {
    if ($instances.Count) {
        $instances | Format-Table -AutoSize | Out-Host
    } else {
        Write-Host "No BC instances yet. Create one with the bc-up skill.`n"
    }
    Write-Host 'Shared services'
    $shared | Format-Table -AutoSize | Out-Host
}
