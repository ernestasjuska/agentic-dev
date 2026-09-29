#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Failures = [Collections.Generic.List[string]]::new()

function Read-Command {
    param([string]$Command, [string[]]$Arguments)
    Write-Host ('> {0} {1}' -f $Command, ($Arguments -join ' '))
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        $script:Failures.Add("$Command unavailable")
        return
    }
    $output = @(& $Command @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $script:Failures.Add("$Command $($Arguments -join ' '): $($output -join ' ')")
        return
    }
    $output | ForEach-Object { "$_" }
}

function Show-Rows {
    param([string]$Title, [object[]]$Rows)
    Write-Host "`n$Title ($($Rows.Count))"
    $Rows | Format-Table -AutoSize -Wrap | Out-String -Width 500 | Write-Host
}

$containers = @(Read-Command docker @('ps', '-a', '--format', '{{json .}}') |
    ForEach-Object { $_ | ConvertFrom-Json })
Show-Rows 'Containers, including stopped' @($containers | Select-Object Names, Image, State, Status, Ports)
Read-Command docker @('stats', '--no-stream', '--format', 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}') | Out-Host

$baseline = '^(azuremonitor.*|azureotelcollector.*|metrics-extension|walinuxagent.*|tailscaled|tailscale-wait-online|ssh|sshd|home-ai|t3code)\.service$'
if ($IsLinux) {
    foreach ($scope in @('system', 'user')) {
        $units = @(Read-Command systemctl @("--$scope", 'list-units', '--type=service', '--state=running', '--no-pager', '--no-legend', '--plain'))
        $names = @($units | ForEach-Object { ($_ -split '\s+')[0] })
        $selected = @($names | Where-Object { $_ -notmatch $baseline })
        Write-Host "$scope services: $($names.Count) -> $($selected.Count); excluded named baseline services. Remaining services include OS services for classification."
        if ($selected.Count -gt 0) {
            Read-Command systemctl (@("--$scope", 'show', '--no-pager', '--property=Id,Description,MainPID,FragmentPath,ActiveState') + $selected) | Out-Host
        }
    }

    # Read executable identities, never print command lines or environments.
    $processes = @(Get-Process)
    $rows = @()
    $excluded = 0
    $unreadable = 0
    foreach ($process in $processes) {
        $procPath = "/proc/$($process.Id)"
        try {
            $exe = (Get-Item "$procPath/exe" -ErrorAction Stop).LinkTarget
            if ([string]::IsNullOrEmpty($exe)) { $excluded++; continue }
            $argv = [IO.File]::ReadAllText("$procPath/cmdline").Split([char]0)
            $status = [IO.File]::ReadAllText("$procPath/status")
            $parent = [regex]::Match($status, '(?m)^PPid:\s+(\d+)').Groups[1].Value
            $uid = [regex]::Match($status, '(?m)^Uid:\s+(\d+)').Groups[1].Value
            $cgroup = [IO.File]::ReadAllText("$procPath/cgroup")
            $identity = @($argv | Where-Object { $_ -match '(^|/)([^/]+\.(dll|csproj|js)|devtunnel|aspire|cloudflared|t3)$' })
            $isBaseline = $exe -match '/\.t3/|/home-ai/|/(tailscaled|sshd)$' -or
                ($identity -join ' ') -match '/home-ai/|/\.t3/'
            $isContainer = $cgroup -match '/docker/|docker-[a-f0-9]+\.scope'
            $isCandidate = ([int]$uid -ge 1000 -and [int]$uid -ne 65534) -or
                $exe -match '^/(opt|usr/local)/' -or
                $process.ProcessName -match 'dotnet|aspire|devtunnel|cloudflared|node|python|java|redis|postgres|sqlservr|traefik|nginx|caddy'
            if ($isBaseline -or $isContainer -or -not $isCandidate -or $process.Id -eq $PID) {
                $excluded++; continue
            }
            $cwd = (Get-Item "$procPath/cwd" -ErrorAction Stop).LinkTarget
            $tunnel = ''
            if ($process.ProcessName -eq 'devtunnel') {
                $hostIndex = [Array]::IndexOf($argv, 'host')
                if ($hostIndex -ge 0 -and $argv.Length -gt ($hostIndex + 1) -and
                    $argv[$hostIndex + 1] -match '^[a-zA-Z0-9][a-zA-Z0-9.-]+$') {
                    $tunnel = $argv[$hostIndex + 1]
                }
            }
            $rows += [pscustomobject]@{
                PID = $process.Id; Parent = $parent; UID = $uid; Name = $process.ProcessName
                Executable = $exe; Application = $identity -join ' '; Directory = $cwd; Tunnel = $tunnel
            }
        } catch {
            if (Test-Path $procPath) { $unreadable++ }
            else { $excluded++ }
        }
    }
    Write-Host "Processes: $($processes.Count) -> $($rows.Count); excluded $excluded baseline, container, collector, kernel/OS or exited processes; unreadable $unreadable."
    if ($unreadable -gt 0) { $script:Failures.Add("$unreadable process identities unreadable; root-owned detached apps may be missing") }
    Show-Rows 'Host process candidates; ownership unclassified' $rows
    Write-Host 'Coverage: current-user services and readable process identities. Service managers for other users and inaccessible executable links require a separate privileged check; this is not an exhaustive host audit.'
    Read-Command ss @('-lntup') | Out-Host
    Write-Host 'Listener output includes baseline ports for attribution; omit those from the report. Process ownership may require elevated inspection.'
} else {
    $script:Failures.Add('Host service, process and listener collection supports Linux only')
}

Read-Command devtunnel @('list', '--json') | Out-Host
Write-Host 'Tunnel registrations belong to the signed-in account, not necessarily this host. Match local devtunnel processes before classifying as locally hosted. Use devtunnel show <id> and devtunnel port list <id> for relevant registrations.'

$board = Join-Path $HOME 'infra-board.md'
if (Test-Path -LiteralPath $board) {
    Write-Host "Infrastructure ownership board: $board (read its current claims and releases separately)."
} else {
    Write-Host "Infrastructure ownership board not found at $board; owners remain unknown without other evidence."
}
if ($script:Failures.Count -gt 0) {
    Show-Rows 'Incomplete checks' @($script:Failures | ForEach-Object { [pscustomobject]@{ Failure = $_ } })
    exit 1
}
