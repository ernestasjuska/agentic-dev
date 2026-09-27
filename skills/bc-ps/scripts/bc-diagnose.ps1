#Requires -Version 7.0
<#
.SYNOPSIS
    Say why a Business Central container is unhealthy, from the current boot only.

.DESCRIPTION
    An unhealthy BC container almost always means the NST started but opened no
    service port. The log does not say so at the top: it says it near the
    bottom, hundreds of thousands of OpenTelemetry lines in, and the container
    log still holds every previous boot.

    This reads the ports actually listening, then counts the failure signatures
    in the current boot only, isolated at the last entrypoint start.

      no 7048/7049/7085              the NST opened nothing, look below.
                                     7045 is forced off by the entrypoint and
                                     7047 is optional, so ignore those two
      AddressInUseException          two API hosts wanted one port; BC separates
                                     endpoints by URL path on a shared port and
                                     Kestrel cannot bind a port twice
      DirectoryNotFoundException     an API host called File.Delete on a socket
                                     path whose parent directory is missing
      "failed to start service"      names the API type and address that failed

    Ports are read from /proc/net/tcp and tcp6 because the container has no ss
    or netstat, and awk there has no strtonum.

.EXAMPLE
    ./bc-diagnose.ps1 bc30
    ./bc-diagnose.ps1 bc30 -Tail 40
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,
    # Lines of the current boot to show when something failed.
    [int]$Tail = 20,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$container = if ($Name -like 'bc-*') { $Name } else { "bc-$Name" }

if (-not (docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $container })) {
    throw "No container $container. Use the bc-ps skill to see what exists."
}

$health   = docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $container
$restarts = docker inspect -f '{{.RestartCount}}' $container
$started  = docker inspect -f '{{.State.StartedAt}}' $container

# Hex port fields, decoded here: the container's awk has no strtonum.
$hex = docker exec $container sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk ''$4=="0A"{split($2,a,":"); print a[2]}'' | sort -u' 2>$null
$ports = @($hex | Where-Object { $_ } | ForEach-Object { [Convert]::ToInt32($_, 16) } | Sort-Object -Unique)

# Only the ports that must be up. 7045 ManagementServices is forced off by the
# entrypoint, and 7047 SOAP is optional, so neither absence means anything.
$expected = 7048, 7049, 7085
$missing  = @($expected | Where-Object { $_ -notin $ports })

$log = docker logs $container 2>&1
$starts = @($log | Select-String -SimpleMatch 'Script started at')
$boot = if ($starts) { $log | Select-Object -Skip ($starts[-1].LineNumber - 1) } else { $log }

function Count([string]$pattern) { @($boot | Select-String -SimpleMatch $pattern).Count }

$result = [ordered]@{
    container            = $container
    health               = $health
    restarts             = [int]$restarts
    startedAt            = $started
    listening            = $ports
    missingServicePorts  = $missing
    addressInUse         = Count 'AddressInUseException'
    directoryNotFound    = Count 'DirectoryNotFoundException'
    hostStartFailures    = Count 'Failed to start service with CLR type'
    serviceStartFailed   = Count 'MicrosoftDynamicsNavServer failed to start'
    failedHosts          = @($boot | Select-String -Pattern 'API type \w+ and address \S+' -AllMatches |
                             ForEach-Object { $_.Matches.Value } | Sort-Object -Unique)
}

if ($Json) { [pscustomobject]$result | ConvertTo-Json -Depth 5; return }

Write-Host ""
Write-Host "  container   $container   health=$health restarts=$restarts"
Write-Host "  listening   $($ports -join ' ')"
if ($missing) { Write-Host "  MISSING     $($missing -join ' ')  <- the NST opened no service port" }
Write-Host ""
Write-Host "  current boot only:"
foreach ($k in 'addressInUse','directoryNotFound','hostStartFailures','serviceStartFailed') {
    Write-Host ("    {0,-20} {1}" -f $k, $result[$k])
}
if ($result.failedHosts) {
    Write-Host ""
    Write-Host "  hosts that failed to bind:"
    $result.failedHosts | ForEach-Object { Write-Host "    $_" }
}
if ($missing -and $Tail -gt 0) {
    Write-Host ""
    Write-Host "  last $Tail lines of this boot:"
    $boot | Select-Object -Last $Tail | ForEach-Object { Write-Host "    $($_.ToString().Substring(0, [Math]::Min(140, $_.ToString().Length)))" }
}
Write-Host ""
if ($missing) { exit 1 }
