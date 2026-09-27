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
    # Lines of container log to scan back through. BC logs OpenTelemetry at
    # volume, so a healthy instance reaches millions of lines and dumping all of
    # it costs minutes. The default covers a failing boot comfortably; raise it
    # if the current boot started further back.
    [int]$ScanLines = 300000,
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

# The container log holds every boot and runs to millions of lines on a BC
# instance that has been up a while. Do the scanning in grep rather than
# pulling it all into PowerShell, which takes minutes instead of seconds.
$logFile  = New-TemporaryFile
$bootFile = New-TemporaryFile
$bootIsolated = $false
try {
    docker logs --tail $ScanLines $container *>$logFile.FullName
    $startLine = "$(bash -c "grep -n 'Script started at' '$($logFile.FullName)' | tail -1 | cut -d: -f1")".Trim()
    if ($startLine) {
        bash -c "tail -n +$startLine '$($logFile.FullName)' > '$($bootFile.FullName)'"
        $bootIsolated = $true
    } else {
        # The boot marker is older than the scan window, which is normal on an
        # instance that has been healthy for hours. Counts then cover the window
        # rather than one boot, so say so instead of implying otherwise.
        Copy-Item $logFile.FullName $bootFile.FullName -Force
    }

    function Count([string]$pattern) {
        [int](bash -c "grep -c -- '$pattern' '$($bootFile.FullName)' || true").Trim()
    }
    $failedHosts = @(bash -c "grep -o 'API type [A-Za-z]* and address [^ ]*' '$($bootFile.FullName)' | sort -u" ) |
        Where-Object { $_ }
    $bootTail = @(bash -c "tail -n $Tail '$($bootFile.FullName)'")

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
    failedHosts          = $failedHosts
}

if ($Json) { [pscustomobject]$result | ConvertTo-Json -Depth 5; return }

Write-Host ""
Write-Host "  container   $container   health=$health restarts=$restarts"
Write-Host "  listening   $($ports -join ' ')"
if ($missing) { Write-Host "  MISSING     $($missing -join ' ')  <- the NST opened no service port" }
Write-Host ""
$scope = if ($bootIsolated) { "current boot only" } else { "last $ScanLines lines; boot marker is older than the window" }
Write-Host "  $scope" 
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
    $bootTail | ForEach-Object { Write-Host "    $($_.Substring(0, [Math]::Min(140, $_.Length)))" }
}
Write-Host ""
if ($missing) { exit 1 }
} finally {
    Remove-Item $logFile.FullName, $bootFile.FullName -ErrorAction SilentlyContinue
}
