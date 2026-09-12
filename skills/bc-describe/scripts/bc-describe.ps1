#Requires -Version 7.0
<#
.SYNOPSIS
    List every endpoint each Business Central instance exposes.

.DESCRIPTION
    Ports are read from the instance manifest and the BC server instance name
    from the running container's CustomSettings.config, so nothing here is
    guessed. Pass -Probe to also report the status code each endpoint answers
    with, using the instance's credentials.

    Note the API and OData live on different host ports. The HttpSys stub
    cannot bind overlapping path prefixes on one port, so it splits them; the
    "<instance>/dev" style path is preserved on whichever port it lands.

.EXAMPLE
    ./bc-describe.ps1
    ./bc-describe.ps1 bc28 -Probe
    ./bc-describe.ps1 -Json
#>
[CmdletBinding()]
param(
    # Limit to one instance. Omit for all of them.
    [Parameter(Position = 0)]
    [string]$Name,
    [switch]$Probe,
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

$files = Get-ChildItem -Path $instancesDir -Filter '*.env' -ErrorAction SilentlyContinue | Sort-Object Name
if ($Name) { $files = $files | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Name } }
if (-not $files) { throw "No instance manifest found$(if ($Name) { " for '$Name'" }) in $instancesDir." }

$rows = @()
foreach ($file in $files) {
    $inst = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $cfg  = Read-EnvFile $file.FullName
    $container = "bc-$inst"

    # ServerInstance drives every path segment, so read it rather than assume BC.
    $si = (docker exec $container sh -c "grep -o 'key=\`"ServerInstance\`" value=\`"[^\`"]*\`"' /bc/service/CustomSettings.config | sed 's/.*value=\`"//;s/\`"//'" 2>$null)
    if (-not $si) { $si = 'BC' }

    $user = if ($cfg['BC_SERVER_USERNAME']) { $cfg['BC_SERVER_USERNAME'] } else { 'BCRUNNER' }
    $pass = if ($cfg['BC_SERVER_PASSWORD']) { $cfg['BC_SERVER_PASSWORD'] } else { 'Admin123!' }

    $endpoints = @(
        @{ name = 'web client (public)'; url = "$($cfg['BC_WEBCLIENT_PUBLIC_URL'])"; auth = 'Entra or NavUserPassword' }
        @{ name = 'web client (direct)'; url = "https://localhost:$($cfg['BC_WEBCLIENT_HOST_PORT'])/$inst/"; auth = 'same' }
        @{ name = 'dev';                 url = "http://localhost:$($cfg['BC_DEV_PORT'])/$si/dev"; auth = 'basic' }
        @{ name = 'odata v4';            url = "http://localhost:$($cfg['BC_ODATA_PORT'])/$si/ODataV4"; auth = 'basic' }
        @{ name = 'api v2.0';            url = "http://localhost:$($cfg['BC_API_PORT'])/$si/api/v2.0"; auth = 'basic' }
        @{ name = 'management';          url = "http://localhost:$($cfg['BC_MGMT_PORT'])/$si"; auth = 'basic' }
        @{ name = 'client services';     url = "http://localhost:$($cfg['BC_CLIENT_PORT'])/$si"; auth = 'internal' }
    )

    foreach ($e in $endpoints) {
        $status = '-'
        if ($Probe -and $e.url) {
            $probeUrl = if ($e.name -eq 'dev') { "$($e.url)/metadata" }
                        elseif ($e.name -eq 'odata v4') { "$($e.url)/Company" }
                        elseif ($e.name -eq 'api v2.0') { "$($e.url)/companies" }
                        else { $e.url }
            $cred = [pscredential]::new($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
            try {
                $status = "$((Invoke-WebRequest -Uri $probeUrl -Authentication Basic -Credential $cred `
                    -AllowUnencryptedAuthentication -SkipCertificateCheck -SkipHttpErrorCheck `
                    -MaximumRedirection 0 -TimeoutSec 15 -ErrorAction SilentlyContinue).StatusCode)"
            } catch { $status = '000' }
        }
        $rows += [pscustomobject]@{
            instance = $inst
            endpoint = $e.name
            url      = $e.url
            auth     = $e.auth
            status   = $status
        }
    }
}

if ($Json) { $rows | ConvertTo-Json -Depth 5 }
else {
    $props = if ($Probe) { 'instance', 'endpoint', 'url', 'auth', 'status' } else { 'instance', 'endpoint', 'url', 'auth' }
    $rows | Format-Table -AutoSize -Property $props | Out-Host
    Write-Host "SOAP is reachable only inside the container network, on port 7047 of $($files.Count) instance(s)."
}
