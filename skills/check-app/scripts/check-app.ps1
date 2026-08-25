#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$AppPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DevOpsRoot = '\\filestorage\Projects\DevOps'
$WipRef = 'refs/heads/WIP'
$SupportedBcVersions = 26..28

function Invoke-ProcessText {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [string]$WorkingDirectory
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Could not start '$FileName'."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Format-ProcessError {
    param(
        [Parameter(Mandatory)]
        $Result
    )

    $message = $Result.StdErr.Trim()
    if (-not $message) {
        $message = $Result.StdOut.Trim()
    }
    if (-not $message) {
        $message = "exit code $($Result.ExitCode)"
    }
    ($message -replace '\s+', ' ').Trim()
}

function Find-Al {
    $command = Get-Command -Name 'al' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $null
}

function Get-JsonProperty {
    param(
        [AllowNull()]
        $Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $Object.PSObject.Properties |
        Where-Object Name -CEQ $Name |
        Select-Object -First 1
}

function ConvertTo-NormalizedGuid {
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$PropertyName is missing or empty."
    }

    try {
        ([Guid]::Parse($text)).ToString('D').ToLowerInvariant()
    }
    catch {
        throw "$PropertyName '$text' is not a valid GUID."
    }
}

function ConvertTo-NormalizedAppVersion {
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$PropertyName is missing or empty."
    }
    if ($text -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "$PropertyName '$text' is not a four-part numeric AL app version."
    }

    try {
        ([Version]::Parse($text)).ToString(4)
    }
    catch {
        throw "$PropertyName '$text' is not a valid AL app version."
    }
}

function Get-NormalizedCommit {
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$PropertyName is missing or empty."
    }
    if ($text -notmatch '^[0-9a-f]{40}$') {
        throw "$PropertyName '$text' is not a 40-character hexadecimal Git commit."
    }

    $text.ToLowerInvariant()
}

function Get-PackageMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $metadata = [ordered]@{
        Loaded = $false
        Error = ''
        Id = '-'
        IdDetail = 'not read'
        Version = '-'
        VersionDetail = 'not read'
        SourceCommit = '-'
        SourceDetail = 'not read'
        SourceValid = $false
    }

    if (-not $AlCommand) {
        $metadata.Error = "AL CLI is unavailable; cannot run 'al GetPackageManifest'."
        return [pscustomobject]$metadata
    }

    try {
        $manifestResult = Invoke-ProcessText -FileName $AlCommand -Arguments @(
            'GetPackageManifest', $Path
        )
        if ($manifestResult.ExitCode -ne 0) {
            throw "al GetPackageManifest failed: $(Format-ProcessError $manifestResult)"
        }
        if ([string]::IsNullOrWhiteSpace($manifestResult.StdOut)) {
            throw 'al GetPackageManifest returned empty output.'
        }

        try {
            $manifest = $manifestResult.StdOut | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "al GetPackageManifest returned malformed JSON: $($_.Exception.Message)"
        }
        if ($null -eq $manifest -or $manifest -is [Array]) {
            throw 'al GetPackageManifest did not return one manifest object.'
        }

        $metadata.Loaded = $true

        $idProperty = Get-JsonProperty -Object $manifest -Name 'id'
        try {
            $metadata.Id = ConvertTo-NormalizedGuid -Value $(if ($idProperty) { $idProperty.Value } else { $null }) -PropertyName 'manifest id'
            $metadata.IdDetail = 'valid GUID (normalized)'
        }
        catch {
            $metadata.IdDetail = $_.Exception.Message
        }

        $versionProperty = Get-JsonProperty -Object $manifest -Name 'version'
        try {
            $metadata.Version = ConvertTo-NormalizedAppVersion -Value $(if ($versionProperty) { $versionProperty.Value } else { $null }) -PropertyName 'manifest version'
            $metadata.VersionDetail = 'valid four-part version (normalized)'
        }
        catch {
            $metadata.VersionDetail = $_.Exception.Message
        }

        $sourceProperty = Get-JsonProperty -Object $manifest -Name 'source'
        $commitProperty = if ($sourceProperty -and $null -ne $sourceProperty.Value) {
            Get-JsonProperty -Object $sourceProperty.Value -Name 'commit'
        }
        else {
            $null
        }
        try {
            $metadata.SourceCommit = Get-NormalizedCommit -Value $(if ($commitProperty) { $commitProperty.Value } else { $null }) -PropertyName 'manifest source.commit'
            $metadata.SourceDetail = 'valid Git commit (normalized)'
            $metadata.SourceValid = $true
        }
        catch {
            $metadata.SourceDetail = $_.Exception.Message
        }
    }
    catch {
        $metadata.Error = $_.Exception.Message
    }

    [pscustomobject]$metadata
}

function Get-Timestamp {
    param(
        [Parameter(Mandatory)]
        [IO.FileInfo]$File
    )

    $File.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss zzz')
}

function New-CheckResult {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [bool]$Passed,

        [Parameter(Mandatory)]
        [string]$Detail
    )

    [pscustomobject]@{
        Label = $Label
        Passed = $Passed
        Detail = $Detail
    }
}

function Get-Commit {
    param(
        [Parameter(Mandatory)]
        [string]$Ref,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $result = Invoke-ProcessText -FileName 'git' -Arguments @(
        '-C', $RepoRoot, 'rev-parse', '--verify', '--quiet', "$Ref^{commit}"
    )
    if ($result.ExitCode -ne 0) {
        return $null
    }

    $result.StdOut.Trim().ToLowerInvariant()
}

function Get-AzureDevOpsProjectComponents {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $remote = Invoke-ProcessText -FileName 'git' -Arguments @(
        '-C', $RepoRoot, 'remote', 'get-url', 'origin'
    )
    if ($remote.ExitCode -ne 0) {
        throw "could not read origin URL: $(Format-ProcessError $remote)"
    }

    $url = $remote.StdOut.Trim()
    $components = $null
    if ($url -match '^https?://(?:[^/@]+@)?dev\.azure\.com/(?<Organization>[^/]+)/(?<Project>[^/]+)/_git/(?<Repository>[^/]+)/?$') {
        $components = @($Matches.Organization, $Matches.Project, $Matches.Repository)
    }
    elseif ($url -match '^https?://(?:[^/@]+@)?(?<Organization>[^./]+)\.visualstudio\.com/(?<Project>[^/]+)/_git/(?<Repository>[^/]+)/?$') {
        $components = @($Matches.Organization, $Matches.Project, $Matches.Repository)
    }
    elseif ($url -match '^(?:ssh://)?git@ssh\.dev\.azure\.com(?::|/)v3/(?<Organization>[^/]+)/(?<Project>[^/]+)/(?<Repository>[^/]+)/?$') {
        $components = @($Matches.Organization, $Matches.Project, $Matches.Repository)
    }

    if (-not $components) {
        throw "origin URL '$url' is not a supported Azure DevOps repository URL"
    }

    $decoded = @($components | ForEach-Object { [Uri]::UnescapeDataString($_) })
    foreach ($component in $decoded) {
        if ([string]::IsNullOrWhiteSpace($component) -or
            $component -in '.', '..' -or
            $component.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "origin URL '$url' contains an unsafe project path component"
        }
    }

    [pscustomobject]@{
        OriginUrl = $url
        Components = $decoded
        DisplayName = $decoded -join '\'
    }
}

function Get-GitState {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $results = [Collections.Generic.List[object]]::new()
    $branches = [Collections.Generic.List[object]]::new()
    $wipCommit = $null

    if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
        [void]$results.Add((New-CheckResult 'repository' $false "missing: $RepoRoot"))
        return [pscustomobject]@{ Results = @($results); WipCommit = $null; Branches = @($branches); RepositoryValid = $false }
    }

    try {
        $topLevel = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $RepoRoot, 'rev-parse', '--show-toplevel'
        )
        if ($topLevel.ExitCode -ne 0) {
            [void]$results.Add((New-CheckResult 'repository' $false "not a Git worktree: $(Format-ProcessError $topLevel)"))
            return [pscustomobject]@{ Results = @($results); WipCommit = $null; Branches = @($branches); RepositoryValid = $false }
        }

        $derivedRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
        $actualRoot = [IO.Path]::GetFullPath($topLevel.StdOut.Trim()).TrimEnd('\', '/')
        if (-not [string]::Equals($derivedRoot, $actualRoot, [StringComparison]::OrdinalIgnoreCase)) {
            [void]$results.Add((New-CheckResult 'repository' $false "derived root '$derivedRoot' is inside different Git worktree '$actualRoot'"))
            return [pscustomobject]@{ Results = @($results); WipCommit = $null; Branches = @($branches); RepositoryValid = $false }
        }
        [void]$results.Add((New-CheckResult 'repository' $true $actualRoot))

        $currentBranch = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $RepoRoot, 'symbolic-ref', '--quiet', '--short', 'HEAD'
        )
        if ($currentBranch.ExitCode -eq 0 -and $currentBranch.StdOut.Trim() -ceq 'WIP') {
            [void]$results.Add((New-CheckResult 'checked-out branch' $true 'WIP'))
        }
        else {
            $branchDetail = if ($currentBranch.ExitCode -eq 0) {
                "expected WIP, found '$($currentBranch.StdOut.Trim())'"
            }
            else {
                'expected WIP, but HEAD is detached or the branch could not be read'
            }
            [void]$results.Add((New-CheckResult 'checked-out branch' $false $branchDetail))
        }

        $status = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $RepoRoot, 'status', '--porcelain=v1', '--untracked-files=all'
        )
        if ($status.ExitCode -ne 0) {
            [void]$results.Add((New-CheckResult 'WIP worktree clean' $false (Format-ProcessError $status)))
        }
        else {
            $changes = @($status.StdOut -split '\r?\n' | Where-Object { $_ })
            if ($changes.Count -eq 0) {
                [void]$results.Add((New-CheckResult 'WIP worktree clean' $true 'tracked and untracked files checked'))
            }
            else {
                [void]$results.Add((New-CheckResult 'WIP worktree clean' $false ($changes -join '; ')))
            }
        }

        $wipCommit = Get-Commit -Ref $WipRef -RepoRoot $RepoRoot
        [void]$results.Add((New-CheckResult 'local WIP ref' ([bool]$wipCommit) $(if ($wipCommit) {
            $wipCommit
        }
        else {
            "missing ref $WipRef"
        })))

        $branchList = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $RepoRoot, 'for-each-ref', '--format=%(refname:short)', 'refs/heads'
        )
        if ($branchList.ExitCode -ne 0) {
            [void]$results.Add((New-CheckResult 'local code/bcNN branches' $false (Format-ProcessError $branchList)))
        }
        else {
            foreach ($branchName in @($branchList.StdOut -split '\r?\n' | Where-Object { $_ })) {
                if ($branchName -cmatch '^code/bc(?<Number>\d+)$') {
                    $number = [Numerics.BigInteger]::Parse(
                        $Matches.Number,
                        [Globalization.CultureInfo]::InvariantCulture
                    )
                    $commit = Get-Commit -Ref "refs/heads/$branchName" -RepoRoot $RepoRoot
                    [void]$branches.Add([pscustomobject]@{
                        Name = $branchName
                        Number = $number
                        Commit = $commit
                    })
                }
            }

            if ($branches.Count -eq 0) {
                [void]$results.Add((New-CheckResult 'local code/bcNN branches' $false 'none found under refs/heads'))
            }
            else {
                $branchSummary = @($branches | Sort-Object Number, Name | ForEach-Object {
                    "$($_.Name)=$($_.Commit)"
                }) -join '; '
                [void]$results.Add((New-CheckResult 'local code/bcNN branches' $true $branchSummary))
            }
        }

        $wipRemote = Get-Commit -Ref 'refs/remotes/origin/WIP' -RepoRoot $RepoRoot
        if (-not $wipCommit -or -not $wipRemote) {
            $detail = "local=$(if ($wipCommit) { $wipCommit } else { '<missing>' }); existing origin/WIP=$(if ($wipRemote) { $wipRemote } else { '<missing>' })"
            [void]$results.Add((New-CheckResult 'WIP equals origin/WIP' $false $detail))
        }
        elseif ($wipCommit -ceq $wipRemote) {
            [void]$results.Add((New-CheckResult 'WIP equals origin/WIP' $true $wipCommit))
        }
        else {
            [void]$results.Add((New-CheckResult 'WIP equals origin/WIP' $false "local=$wipCommit; existing origin/WIP=$wipRemote"))
        }

        foreach ($branch in $branches) {
            if ($wipCommit -and $branch.Commit) {
                $ancestor = Invoke-ProcessText -FileName 'git' -Arguments @(
                    '-C', $RepoRoot, 'merge-base', '--is-ancestor', $WipRef, "refs/heads/$($branch.Name)"
                )
                if ($ancestor.ExitCode -eq 0) {
                    [void]$results.Add((New-CheckResult "WIP merged into $($branch.Name)" $true 'WIP is an ancestor'))
                }
                elseif ($ancestor.ExitCode -eq 1) {
                    [void]$results.Add((New-CheckResult "WIP merged into $($branch.Name)" $false 'WIP is not an ancestor'))
                }
                else {
                    [void]$results.Add((New-CheckResult "WIP merged into $($branch.Name)" $false (Format-ProcessError $ancestor)))
                }
            }
            else {
                [void]$results.Add((New-CheckResult "WIP merged into $($branch.Name)" $false 'required local ref is missing'))
            }

            $remoteName = "origin/$($branch.Name)"
            $remoteCommit = Get-Commit -Ref "refs/remotes/$remoteName" -RepoRoot $RepoRoot
            if (-not $branch.Commit -or -not $remoteCommit) {
                $detail = "local=$(if ($branch.Commit) { $branch.Commit } else { '<missing>' }); existing $remoteName=$(if ($remoteCommit) { $remoteCommit } else { '<missing>' })"
                [void]$results.Add((New-CheckResult "$($branch.Name) equals $remoteName" $false $detail))
            }
            elseif ($branch.Commit -ceq $remoteCommit) {
                [void]$results.Add((New-CheckResult "$($branch.Name) equals $remoteName" $true $branch.Commit))
            }
            else {
                [void]$results.Add((New-CheckResult "$($branch.Name) equals $remoteName" $false "local=$($branch.Commit); existing $remoteName=$remoteCommit"))
            }
        }
    }
    catch {
        [void]$results.Add((New-CheckResult 'Git checks' $false $_.Exception.Message))
    }

    [pscustomobject]@{
        Results = @($results)
        WipCommit = $wipCommit
        Branches = @($branches)
        RepositoryValid = $true
    }
}

function Get-WipAppCatalogue {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [bool]$CanReadWip
    )

    $results = [Collections.Generic.List[object]]::new()
    $definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $ambiguousIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    if (-not $CanReadWip) {
        [void]$results.Add((New-CheckResult 'WIP app.json discovery' $false 'committed WIP tree is unavailable'))
        return [pscustomobject]@{ Results = @($results); Definitions = $definitions; AmbiguousIds = $ambiguousIds }
    }

    try {
        $tree = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $RepoRoot, 'ls-tree', '-r', '--name-only', $WipRef, '--'
        )
        if ($tree.ExitCode -ne 0) {
            throw "could not list committed WIP tree: $(Format-ProcessError $tree)"
        }

        $appJsonPaths = @($tree.StdOut -split '\r?\n' |
            Where-Object { $_ -ceq 'app.json' -or $_ -clike '*/app.json' })
        if ($appJsonPaths.Count -eq 0) {
            [void]$results.Add((New-CheckResult 'WIP app.json discovery' $false 'no app.json files found in committed WIP tree'))
            return [pscustomobject]@{ Results = @($results); Definitions = $definitions; AmbiguousIds = $ambiguousIds }
        }
        [void]$results.Add((New-CheckResult 'WIP app.json discovery' $true "$($appJsonPaths.Count) file(s), read with git show from $WipRef"))

        $definitionsById = @{}
        foreach ($path in $appJsonPaths) {
            try {
                $content = Invoke-ProcessText -FileName 'git' -Arguments @(
                    '-C', $RepoRoot, 'show', "${WipRef}:$path"
                )
                if ($content.ExitCode -ne 0) {
                    throw "git show failed: $(Format-ProcessError $content)"
                }

                try {
                    $appJson = $content.StdOut | ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    throw "malformed JSON: $($_.Exception.Message)"
                }
                if ($null -eq $appJson -or $appJson -is [Array]) {
                    throw 'expected one JSON object'
                }

                $idProperty = Get-JsonProperty -Object $appJson -Name 'id'
                $id = ConvertTo-NormalizedGuid -Value $(if ($idProperty) { $idProperty.Value } else { $null }) -PropertyName 'app.json id'
                $versionProperty = Get-JsonProperty -Object $appJson -Name 'version'
                $version = ConvertTo-NormalizedAppVersion -Value $(if ($versionProperty) { $versionProperty.Value } else { $null }) -PropertyName 'app.json version'
                $definition = [pscustomobject]@{
                    Path = $path
                    Id = $id
                    Version = $version
                }

                if (-not $definitionsById.ContainsKey($id)) {
                    $definitionsById[$id] = [Collections.Generic.List[object]]::new()
                }
                [void]$definitionsById[$id].Add($definition)
                [void]$results.Add((New-CheckResult "WIP $path" $true "id=$id; version=$version"))
            }
            catch {
                [void]$results.Add((New-CheckResult "WIP $path" $false $_.Exception.Message))
            }
        }

        foreach ($id in $definitionsById.Keys) {
            $matches = @($definitionsById[$id])
            if ($matches.Count -eq 1) {
                $definitions.Add($id, $matches[0])
            }
            else {
                [void]$ambiguousIds.Add($id)
                $paths = @($matches.Path) -join ', '
                [void]$results.Add((New-CheckResult "unique WIP app id $id" $false "duplicate app id in: $paths"))
            }
        }
    }
    catch {
        [void]$results.Add((New-CheckResult 'WIP app.json discovery' $false $_.Exception.Message))
    }

    [pscustomobject]@{
        Results = @($results)
        Definitions = $definitions
        AmbiguousIds = $ambiguousIds
    }
}

function Get-ValidatedInputs {
    $results = [Collections.Generic.List[object]]::new()

    foreach ($suppliedPath in $AppPath) {
        $inputResult = [ordered]@{
            SuppliedPath = $suppliedPath
            FullPath = $null
            RepoRoot = $null
            Passed = $false
            Detail = ''
        }

        if (-not [IO.Path]::IsPathFullyQualified($suppliedPath)) {
            $inputResult.Detail = 'unsupported input: expected a fully qualified local path'
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        try {
            $fullPath = [IO.Path]::GetFullPath($suppliedPath)
        }
        catch {
            $inputResult.Detail = "invalid input path: $($_.Exception.Message)"
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        if ($fullPath.StartsWith('\\', [StringComparison]::Ordinal)) {
            $inputResult.Detail = 'unsupported input: expected a local path, not a UNC or device path'
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }
        if ([IO.Path]::GetExtension($fullPath) -ine '.app') {
            $inputResult.Detail = 'unsupported input: expected a .app file'
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        $outputRoot = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($fullPath))
        if ($outputRoot.Name -cne '.output') {
            $inputResult.Detail = 'unsupported input: app must be directly under a directory named exactly .output'
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        $workspaceRoot = $outputRoot.Parent
        if (-not $workspaceRoot) {
            $inputResult.Detail = 'unsupported input: .output must have a workspace parent directory'
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        $topLevel = Invoke-ProcessText -FileName 'git' -Arguments @(
            '-C', $workspaceRoot.FullName, 'rev-parse', '--show-toplevel'
        )
        if ($topLevel.ExitCode -ne 0) {
            $inputResult.Detail = "unsupported input: .output workspace is not inside a Git worktree: $(Format-ProcessError $topLevel)"
            [void]$results.Add([pscustomobject]$inputResult)
            continue
        }

        $repoRoot = [IO.Path]::GetFullPath($topLevel.StdOut.Trim()).TrimEnd('\', '/')

        $inputResult.FullPath = $fullPath
        $inputResult.RepoRoot = $repoRoot
        $inputResult.Passed = $true
        $inputResult.Detail = 'supported AL workspace .output path inside a Git worktree'
        [void]$results.Add([pscustomobject]$inputResult)
    }

    $repoRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($result in $results) {
        if ($result.Passed) {
            [void]$repoRoots.Add($result.RepoRoot)
        }
    }
    if ($repoRoots.Count -gt 1) {
        foreach ($result in $results) {
            if ($result.Passed) {
                $result.Passed = $false
                $result.Detail = 'unsupported input set: all apps must resolve to the same repository'
            }
        }
    }

    $results
}

function Get-DestinationRoots {
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $project = Get-AzureDevOpsProjectComponents -RepoRoot $RepoRoot
    foreach ($bc in $SupportedBcVersions) {
        [pscustomobject]@{
            Label = "Prereleases BC$bc"
            BC = $bc
            Path = Join-Path $DevOpsRoot "!Prereleases\Latest-BC$bc"
            Project = $project.DisplayName
        }

        $path = $DevOpsRoot
        foreach ($component in $project.Components) {
            $path = Join-Path $path $component
        }
        [pscustomobject]@{
            Label = "$($project.Components[-1]) BC$bc"
            BC = $bc
            Path = Join-Path $path "Latest-BC$bc"
            Project = $project.DisplayName
        }
    }
}

function Get-DestinationMappings {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Branches
    )

    foreach ($bc in $SupportedBcVersions) {
        $compatible = @($Branches |
            Where-Object { $_.Number -le [Numerics.BigInteger]$bc } |
            Sort-Object Number -Descending)
        if ($compatible.Count -eq 0) {
            [pscustomobject]@{
                BC = $bc
                Passed = $false
                Branch = '-'
                Commit = '-'
                Detail = "no local code/bcNN branch has NN <= $bc"
            }
            continue
        }

        $highestNumber = $compatible[0].Number
        $highest = @($compatible | Where-Object { $_.Number -eq $highestNumber })
        if ($highest.Count -gt 1) {
            [pscustomobject]@{
                BC = $bc
                Passed = $false
                Branch = '-'
                Commit = '-'
                Detail = "ambiguous highest compatible NN $highestNumber`: $(@($highest.Name) -join ', ')"
            }
            continue
        }

        $selected = $highest[0]
        [pscustomobject]@{
            BC = $bc
            Passed = [bool]$selected.Commit
            Branch = $selected.Name
            Commit = if ($selected.Commit) { $selected.Commit } else { '-' }
            Detail = if ($selected.Commit) {
                "highest local code/bcNN branch with NN <= $bc"
            }
            else {
                'selected local branch commit is unavailable'
            }
        }
    }
}

function New-ArtifactResult {
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [bool]$IsLocal,

        [Parameter(Mandatory)]
        $Catalogue,

        $Mapping
    )

    $result = [ordered]@{
        Label = $Label
        Path = $Path
        Passed = $false
        Timestamp = '-'
        AppId = '-'
        IdDetail = 'not checked'
        AppDefinitionPath = '-'
        Version = '-'
        ExpectedVersion = '-'
        VersionDetail = 'not checked'
        SourceCommit = '-'
        ExpectedSource = if ($IsLocal) { 'ignored for local package' } elseif ($Mapping -and $Mapping.Passed) { "$($Mapping.Branch) $($Mapping.Commit)" } else { '<unavailable>' }
        SourceDetail = 'not checked'
        Detail = ''
    }
    $failures = [Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [void]$failures.Add('file is missing')
        $result.Detail = $failures -join '; '
        return [pscustomobject]$result
    }

    try {
        $file = Get-Item -LiteralPath $Path
        $result.Timestamp = Get-Timestamp $file
        $metadata = Get-PackageMetadata -Path $file.FullName
        if (-not $metadata.Loaded) {
            [void]$failures.Add($metadata.Error)
        }
        else {
            $result.AppId = $metadata.Id
            $result.IdDetail = $metadata.IdDetail
            $result.Version = $metadata.Version
            $result.VersionDetail = $metadata.VersionDetail
            $result.SourceCommit = $metadata.SourceCommit
            $result.SourceDetail = $metadata.SourceDetail

            if ($metadata.Id -eq '-') {
                [void]$failures.Add($metadata.IdDetail)
            }
            elseif ($Catalogue.AmbiguousIds.Contains($metadata.Id)) {
                $result.IdDetail = 'manifest id is duplicated in committed WIP app.json files'
                [void]$failures.Add($result.IdDetail)
            }
            elseif (-not $Catalogue.Definitions.ContainsKey($metadata.Id)) {
                $result.IdDetail = 'manifest id does not resolve to a committed WIP app.json'
                [void]$failures.Add($result.IdDetail)
            }
            else {
                $definition = $Catalogue.Definitions[$metadata.Id]
                $result.AppDefinitionPath = $definition.Path
                $result.IdDetail = "matches committed WIP $($definition.Path)"
                $result.ExpectedVersion = $definition.Version

                if ($metadata.Version -eq '-') {
                    [void]$failures.Add($metadata.VersionDetail)
                }
                elseif ($metadata.Version -cne $definition.Version) {
                    $result.VersionDetail = "does not equal committed WIP version $($definition.Version)"
                    [void]$failures.Add($result.VersionDetail)
                }
                else {
                    $result.VersionDetail = 'equals committed WIP app.json version'
                }
            }

            if ($metadata.Version -eq '-' -and -not ($failures -contains $metadata.VersionDetail)) {
                [void]$failures.Add($metadata.VersionDetail)
            }

            if ($IsLocal) {
                $result.SourceDetail = if ($metadata.SourceValid) {
                    'present but intentionally ignored for the supplied local package'
                }
                else {
                    "$($metadata.SourceDetail) (allowed and ignored for the supplied local package)"
                }
            }
            else {
                if (-not $Mapping -or -not $Mapping.Passed) {
                    [void]$failures.Add("destination provenance mapping unavailable: $(if ($Mapping) { $Mapping.Detail } else { 'mapping missing' })")
                }
                if (-not $metadata.SourceValid) {
                    [void]$failures.Add($metadata.SourceDetail)
                }
                elseif ($Mapping -and $Mapping.Passed -and $metadata.SourceCommit -cne $Mapping.Commit) {
                    $result.SourceDetail = "does not equal selected local $($Mapping.Branch) head"
                    [void]$failures.Add($result.SourceDetail)
                }
                elseif ($Mapping -and $Mapping.Passed) {
                    $result.SourceDetail = "equals selected local $($Mapping.Branch) head"
                }
            }
        }
    }
    catch {
        [void]$failures.Add($_.Exception.Message)
    }

    $result.Passed = $failures.Count -eq 0
    $result.Detail = if ($result.Passed) {
        if ($IsLocal) {
            'package id/version match committed WIP metadata; source.commit is not required'
        }
        else {
            'package id/version match committed WIP metadata and source.commit matches selected code branch'
        }
    }
    else {
        $failures -join '; '
    }

    [pscustomobject]$result
}

function Get-AppResults {
    param(
        [Parameter(Mandatory)]
        [object[]]$Inputs,

        [Parameter(Mandatory)]
        [object[]]$DestinationRoots,

        [Parameter(Mandatory)]
        [object[]]$Mappings,

        [Parameter(Mandatory)]
        $Catalogue
    )

    $results = [Collections.Generic.List[object]]::new()
    foreach ($input in $Inputs) {
        $appResult = [ordered]@{
            SuppliedPath = $input.SuppliedPath
            Passed = $false
            Detail = $input.Detail
            Artifacts = [Collections.Generic.List[object]]::new()
        }
        if (-not $input.Passed) {
            [void]$results.Add([pscustomobject]$appResult)
            continue
        }

        $local = New-ArtifactResult -Label 'Local' -Path $input.FullPath -IsLocal $true -Catalogue $Catalogue
        [void]$appResult.Artifacts.Add($local)
        foreach ($destination in $DestinationRoots) {
            $destinationPath = Join-Path $destination.Path ([IO.Path]::GetFileName($input.FullPath))
            $mapping = $Mappings | Where-Object BC -EQ $destination.BC | Select-Object -First 1
            $copy = New-ArtifactResult -Label $destination.Label -Path $destinationPath -IsLocal $false -Catalogue $Catalogue -Mapping $mapping
            [void]$appResult.Artifacts.Add($copy)
        }

        $failedArtifacts = @($appResult.Artifacts | Where-Object { -not $_.Passed })
        $appResult.Passed = $DestinationRoots.Count -eq 6 -and $failedArtifacts.Count -eq 0
        $appResult.Detail = if ($appResult.Passed) {
            'local package and all six prerelease copies passed metadata and provenance checks'
        }
        elseif ($DestinationRoots.Count -ne 6) {
            'expected six destination roots; destination checks could not run completely'
        }
        else {
            "$($failedArtifacts.Count) of $($appResult.Artifacts.Count) package check(s) failed"
        }
        [void]$results.Add([pscustomobject]$appResult)
    }

    $results
}

$inputs = @(Get-ValidatedInputs)
$validInputs = @($inputs | Where-Object Passed)
$repoRoots = @($validInputs | ForEach-Object { $_.RepoRoot } | Select-Object -Unique)
$RepoRoot = if ($repoRoots.Count -eq 1) { $repoRoots[0] } else { $null }

$configurationResults = [Collections.Generic.List[object]]::new()
$AlCommand = Find-Al
[void]$configurationResults.Add((New-CheckResult 'AL CLI' ([bool]$AlCommand) $(if ($AlCommand) {
    "$AlCommand (package metadata uses only al GetPackageManifest)"
}
else {
    "unavailable; 'al GetPackageManifest' cannot run"
})))

$DestinationRoots = if ($RepoRoot) {
    try {
        @(Get-DestinationRoots -RepoRoot $RepoRoot)
    }
    catch {
        [void]$configurationResults.Add((New-CheckResult 'Azure DevOps project path' $false $_.Exception.Message))
        @()
    }
}
else {
    @()
}
$gitState = if ($RepoRoot) {
    Get-GitState -RepoRoot $RepoRoot
}
else {
    [pscustomobject]@{
        Results = @((New-CheckResult 'repository' $false 'could not derive one supported repository root from the inputs'))
        WipCommit = $null
        Branches = @()
        RepositoryValid = $false
    }
}
$gitResults = @($gitState.Results)
$catalogue = if ($RepoRoot) {
    Get-WipAppCatalogue -RepoRoot $RepoRoot -CanReadWip ([bool]$gitState.WipCommit)
}
else {
    [pscustomobject]@{
        Results = @((New-CheckResult 'WIP app.json discovery' $false 'repository root is unavailable'))
        Definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        AmbiguousIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
}
$catalogueResults = @($catalogue.Results)
$mappings = @(Get-DestinationMappings -Branches @($gitState.Branches))
$mappingResults = @($mappings | ForEach-Object {
    New-CheckResult "BC$($_.BC) mapping" $_.Passed "$($_.Branch) $($_.Commit) - $($_.Detail)"
})
$appResults = @(Get-AppResults -Inputs $inputs -DestinationRoots $DestinationRoots -Mappings $mappings -Catalogue $catalogue)

$configurationPassed = @($configurationResults | Where-Object { -not $_.Passed }).Count -eq 0
$gitPassed = @($gitResults | Where-Object { -not $_.Passed }).Count -eq 0
$cataloguePassed = @($catalogueResults | Where-Object { -not $_.Passed }).Count -eq 0
$mappingsPassed = @($mappingResults | Where-Object { -not $_.Passed }).Count -eq 0
$appsPassed = $appResults.Count -gt 0 -and @($appResults | Where-Object { -not $_.Passed }).Count -eq 0
$passed = $configurationPassed -and $gitPassed -and $cataloguePassed -and $mappingsPassed -and $appsPassed

Write-Output ''
Write-Output 'CHECK APP'
if ($RepoRoot) {
    Write-Output "Repository: $RepoRoot"
}
Write-Output 'Git comparisons use existing local origin/* refs; git fetch was not run.'
Write-Output 'Last-write times are informational only; metadata and code provenance decide package results.'

Write-Output ''
Write-Output 'Configuration'
foreach ($result in $configurationResults) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "  [$status] $($result.Label): $($result.Detail)"
}

Write-Output ''
Write-Output 'Git status'
foreach ($result in $gitResults) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "  [$status] $($result.Label): $($result.Detail)"
}

Write-Output ''
Write-Output 'Committed WIP app definitions'
foreach ($result in $catalogueResults) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "  [$status] $($result.Label): $($result.Detail)"
}

Write-Output ''
Write-Output 'Destination provenance mapping'
foreach ($result in $mappingResults) {
    $status = if ($result.Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "  [$status] $($result.Label): $($result.Detail)"
}

Write-Output ''
Write-Output 'Packages'
foreach ($app in $appResults) {
    $status = if ($app.Passed) { 'PASS' } else { 'FAIL' }
    Write-Output "  [$status] $($app.SuppliedPath)"
    Write-Output "         $($app.Detail)"
    foreach ($artifact in $app.Artifacts) {
        $artifactStatus = if ($artifact.Passed) { 'PASS' } else { 'FAIL' }
        Write-Output "    [$artifactStatus] $($artifact.Label)"
        Write-Output "           path: $($artifact.Path)"
        Write-Output "           last write (informational): $($artifact.Timestamp)"
        Write-Output "           id: $($artifact.AppId) | $($artifact.IdDetail)"
        Write-Output "           WIP app.json: $($artifact.AppDefinitionPath)"
        Write-Output "           version: $($artifact.Version) | expected: $($artifact.ExpectedVersion) | $($artifact.VersionDetail)"
        Write-Output "           source.commit: $($artifact.SourceCommit) | expected: $($artifact.ExpectedSource) | $($artifact.SourceDetail)"
        Write-Output "           result: $($artifact.Detail)"
    }
}

Write-Output ''
Write-Output "FINAL: $(if ($passed) { 'PASS' } else { 'FAIL' })"
if (-not $passed) {
    exit 1
}
