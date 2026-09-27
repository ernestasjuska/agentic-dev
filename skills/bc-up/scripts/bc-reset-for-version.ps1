#Requires -Version 7.0
<#
.SYNOPSIS
    Clear the state that makes the next BC version fail to start.

.DESCRIPTION
    Testing several BC versions in sequence against the one shared SQL Server
    fails twice for reasons that look like product bugs and are not. This
    clears both.

    The database name. The manifest records BC_DATABASE=CRONUS_<name> but the
    generated compose does not pass it through, so every instance uses CRONUS.
    The next version attaches to the previous version's schema and the NST dies
    with "must be converted".

    The artifact staging. SQL Server reads the backup from the shared
    bc-artifacts volume, mounted at /bc/artifacts read-only, while the BC
    container sees the same volume at /bc/shared-artifacts. It holds one
    version at a time, so the next instance restores the previous version's
    BusinessCentral-W1.bak and reports "must be converted" again. Re-stage it
    from the per-version volume. Do not simply empty it: nothing repopulates an
    empty one and the restore then fails with "Cannot open backup device".

.EXAMPLE
    ./bc-reset-for-version.ps1 -ArtifactVolume bc-artifacts-30.0.55227.0
    ./bc-reset-for-version.ps1 -DatabaseOnly
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Per-version volume to copy into the shared staging volume, for example
    # bc-artifacts-30.0.55227.0. Omit with -DatabaseOnly.
    [string]$ArtifactVolume,
    [string]$SharedVolume = 'bc-artifacts',
    [string[]]$Database = @('CRONUS'),
    [switch]$DatabaseOnly,
    [string]$SqlContainer = 'bc-mssql'
)

$ErrorActionPreference = 'Stop'

if (-not $DatabaseOnly -and -not $ArtifactVolume) {
    throw "Pass -ArtifactVolume <per-version volume>, or -DatabaseOnly. Volumes: $((docker volume ls --format '{{.Name}}' | Where-Object { $_ -like 'bc-artifacts-*' }) -join ', ')"
}

$envFile = Join-Path $HOME '.bc-platform/mssql/.env'
if (-not (Test-Path $envFile)) { throw "No shared SQL env at $envFile. Start it with the mssql-up skill." }
$sa = (Get-Content $envFile | Where-Object { $_ -like 'SA_PASSWORD=*' } | Select-Object -First 1) -split '=', 2 | Select-Object -Last 1
if (-not $sa) { throw "SA_PASSWORD not found in $envFile." }

foreach ($db in $Database) {
    if ($PSCmdlet.ShouldProcess($db, 'drop database')) {
        $sql = "IF DB_ID('$db') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END"
        docker exec $SqlContainer /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $sa -C -No -b -Q $sql | Out-Null
        Write-Host "  dropped $db (if it existed)"
    }
}

if ($DatabaseOnly) { return }

if (-not (docker volume ls --format '{{.Name}}' | Where-Object { $_ -eq $ArtifactVolume })) {
    throw "Volume $ArtifactVolume does not exist."
}

if ($PSCmdlet.ShouldProcess($SharedVolume, "re-stage from $ArtifactVolume")) {
    docker run --rm -v "${ArtifactVolume}:/src:ro" -v "${SharedVolume}:/dst" alpine:latest `
        sh -c 'rm -rf /dst/* /dst/.[!.]* 2>/dev/null; cp -a /src/. /dst/' | Out-Null
    $staged = docker run --rm -v "${SharedVolume}:/v:ro" alpine:latest `
        sh -c 'ls -d "/v/platform/ServiceTier/PFiles64/Microsoft Dynamics NAV"/* 2>/dev/null | head -1; ls /v/app/*.bak 2>/dev/null | head -1'
    Write-Host "  staged into ${SharedVolume}:"
    $staged | ForEach-Object { Write-Host "    $_" }
}
