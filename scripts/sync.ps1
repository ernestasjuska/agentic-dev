#Requires -Version 7.0
<#
.SYNOPSIS
    Copy handpicked skills from this repo into a project (or your user profile),
    in the layout each coding agent expects.

.EXAMPLE
    ./scripts/sync.ps1 -List
    ./scripts/sync.ps1 -Target C:\proj\foo -Skills skill-authoring
    ./scripts/sync.ps1 -Target C:\proj\foo            # re-sync whatever is already there
    ./scripts/sync.ps1 -Target C:\proj\foo -Check
    ./scripts/sync.ps1 -All -Global -Agents claude,codex
    ./scripts/sync.ps1 -Rules                        # rules/ -> ~/.codex/AGENTS.md
#>
[CmdletBinding()]
param(
    # Project to sync into. Ignored when -Global is set.
    [Parameter(Position = 0)]
    [string]$Target = (Get-Location).Path,

    # Skill names (directory names under skills/). Omit to re-sync whatever the
    # target already has.
    [string[]]$Skills,

    # Sync every skill in the repo.
    [switch]$All,

    [ValidateSet('claude', 'codex', 'copilot', 'opencode')]
    [string[]]$Agents = @('claude', 'codex', 'copilot', 'opencode'),

    # Sync into user-level dirs (~/.claude/skills etc.) instead of a project.
    [switch]$Global,

    # Report drift and orphans; write nothing.
    [switch]$Check,

    # List repo skills and validate their frontmatter.
    [switch]$List,

    # Write rules/ into ~/.codex/AGENTS.md, the one global instruction file Codex
    # loads. Combine with -Check to report drift without writing.
    [switch]$Rules
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SkillsRoot = Join-Path $RepoRoot 'skills'
$RulesRoot = Join-Path $RepoRoot 'rules'
$NamePattern = '^[a-z0-9]+(-[a-z0-9]+)*$'

function Write-Status {
    param([string]$Tag, [string]$Message, [string]$Color = 'Gray')
    Write-Host ('  {0,-9} ' -f $Tag) -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

function Get-SkillMeta {
    param([string]$Dir)
    $name = Split-Path $Dir -Leaf
    $file = Join-Path $Dir 'SKILL.md'
    $meta = [ordered]@{ Name = $name; Path = $Dir; Description = ''; Problems = @() }

    if (-not (Test-Path -LiteralPath $file)) {
        $meta.Problems += 'no SKILL.md'
        return [pscustomobject]$meta
    }

    $lines = @(Get-Content -LiteralPath $file)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        $meta.Problems += 'missing YAML frontmatter'
        return [pscustomobject]$meta
    }

    $end = 1
    while ($end -lt $lines.Count -and $lines[$end].Trim() -ne '---') { $end++ }
    if ($end -ge $lines.Count) {
        $meta.Problems += 'unterminated frontmatter'
        return [pscustomobject]$meta
    }

    $declared = ''
    foreach ($line in $lines[1..($end - 1)]) {
        if ($line -match '^\s*name:\s*(.+?)\s*$') { $declared = $Matches[1].Trim('"', "'") }
        elseif ($line -match '^\s*description:\s*(.+?)\s*$') { $meta.Description = $Matches[1].Trim('"', "'") }
    }

    if (-not $declared) { $meta.Problems += 'frontmatter has no name' }
    elseif ($declared -ne $name) { $meta.Problems += "name '$declared' does not match directory '$name'" }
    if ($declared -and $declared -notmatch $NamePattern) { $meta.Problems += 'name must be lowercase-with-hyphens' }
    if (-not $meta.Description) { $meta.Problems += 'frontmatter has no description' }
    elseif ($meta.Description.Length -gt 1024) { $meta.Problems += 'description exceeds 1024 chars' }

    [pscustomobject]$meta
}

function Get-SkillHash {
    param([string]$Dir)
    $root = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $lines = Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        '{0} {1}' -f $rel, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

# Where each agent reads project-level / user-level skills from. Pure lookup, so it is
# also safe to call just to see whether a target already uses an agent.
function Get-AgentSkillDir {
    param([string]$Agent, [string]$TargetPath)
    switch ($Agent) {
        'claude' { if ($Global) { Join-Path $HOME '.claude/skills' } else { Join-Path $TargetPath '.claude/skills' } }
        'codex' { if ($Global) { Join-Path $HOME '.codex/skills' } else { Join-Path $TargetPath '.codex/skills' } }
        'copilot' { if ($Global) { $null } else { Join-Path $TargetPath '.github/skills' } }
        'opencode' { if ($Global) { Join-Path $HOME '.config/opencode/skills' } else { Join-Path $TargetPath '.opencode/skills' } }
    }
}

# Same lookup, plus the two rules about where we decline to write. OpenCode reads
# .claude/skills and ~/.claude/skills, so it piggybacks on the Claude copy whenever
# Claude is selected too - one copy, both tools see it.
function Resolve-AgentDir {
    param([string]$Agent, [string]$TargetPath, [string[]]$Selected)
    $dir = Get-AgentSkillDir -Agent $Agent -TargetPath $TargetPath
    if ($Agent -eq 'copilot' -and $Global) {
        $script:Notes += 'skip|copilot: repo-scoped only (.github/skills); nothing to do for -Global'
        return $null
    }
    if ($Agent -eq 'opencode' -and $Selected -contains 'claude') {
        $script:Notes += 'reuse|opencode: reads the Claude copy; no separate copy written'
        if ($dir -and (Test-Path -LiteralPath $dir)) {
            $script:Notes += ('stale|opencode: {0} is no longer synced and can be deleted by hand' -f $dir)
        }
        return $null
    }
    $dir
}

# Skill dirs already installed under an agent dir. A dir counts only if it holds a
# SKILL.md, so a half-copied directory is not mistaken for a pick. This is the record of
# what a target chose; there is no manifest.
function Get-InstalledSkillNames {
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return @() }
    @(Get-ChildItem -LiteralPath $Dir -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
        ForEach-Object { $_.Name })
}

# ---- rules -> Codex ------------------------------------------------------------

# Claude Code reads ~/.claude/rules, OpenCode globs rules/*.instructions.md through its
# config, and VS Code lists the same directory for Copilot. Codex loads exactly one global
# file, ~/.codex/AGENTS.md, and a pointer in it to the directory is not reliably followed,
# so that one file gets the text. Frontmatter goes; it is Copilot's applyTo key and means
# nothing to Codex.
function Build-CodexAgentsDoc {
    $files = @(Get-ChildItem -LiteralPath $RulesRoot -File -Filter '*.instructions.md' | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No *.instructions.md files in $RulesRoot" }

    $parts = @(
        '<!-- Generated by agentic-dev/scripts/sync.ps1 -Rules. Do not edit here: edit',
        ("     agentic-dev/rules/*.instructions.md and run it again. Sources: {0}. -->" -f (($files.Name) -join ', '))
    )
    foreach ($f in $files) {
        $lines = @(Get-Content -LiteralPath $f.FullName)
        if ($lines.Count -and $lines[0].Trim() -eq '---') {
            $end = 1
            while ($end -lt $lines.Count -and $lines[$end].Trim() -ne '---') { $end++ }
            if ($end -ge $lines.Count) { throw "Unterminated frontmatter in $($f.Name)" }
            $lines = @($lines[($end + 1)..($lines.Count - 1)])
        }
        $parts += ''
        $parts += (($lines -join "`n").Trim())
    }
    ($parts -join "`n") + "`n"
}

if ($Rules) {
    $doc = Build-CodexAgentsDoc
    $dest = Join-Path $HOME '.codex/AGENTS.md'
    $current = if (Test-Path -LiteralPath $dest) { [IO.File]::ReadAllText($dest) } else { $null }

    Write-Host "`nRules -> $dest`n"
    if ($current -eq $doc) { Write-Status 'in-sync' 'AGENTS.md' 'DarkGray'; Write-Host ''; exit 0 }
    if ($Check) {
        Write-Status ($null -eq $current ? 'missing' : 'drift') 'AGENTS.md' 'Yellow'
        Write-Host "`n1 difference(s) found.`n" -ForegroundColor Yellow
        exit 1
    }
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($dest, $doc)
    Write-Status ($null -eq $current ? 'added' : 'updated') 'AGENTS.md' 'Green'
    Write-Host ''
    exit 0
}

# ---- discover repo skills -----------------------------------------------------

if (-not (Test-Path -LiteralPath $SkillsRoot)) { throw "No skills/ directory in $RepoRoot" }
$available = @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | ForEach-Object { Get-SkillMeta $_.FullName })

if ($List) {
    Write-Host "`nSkills in $SkillsRoot`n"
    foreach ($s in $available) {
        $ok = $s.Problems.Count -eq 0
        Write-Status ($ok ? 'ok' : 'invalid') $s.Name ($ok ? 'Green' : 'Red')
        if ($ok) { Write-Host ('            {0}' -f $s.Description) -ForegroundColor DarkGray }
        else { foreach ($p in $s.Problems) { Write-Host ('            - {0}' -f $p) -ForegroundColor Red } }
    }
    $bad = @($available | Where-Object { $_.Problems.Count }).Count
    Write-Host ''
    exit ($bad ? 1 : 0)
}

# ---- resolve the selection ----------------------------------------------------

$TargetPath = if ($Global) { $HOME } else { (Resolve-Path -LiteralPath $Target).Path }

$present = @()
$installed = @()
foreach ($a in @('claude', 'codex', 'copilot', 'opencode')) {
    $dir = Get-AgentSkillDir -Agent $a -TargetPath $TargetPath
    if ($dir -and (Test-Path -LiteralPath $dir)) { $present += $a }
    $installed += Get-InstalledSkillNames $dir
}

# An existing agent dir is the target saying it uses that agent, even if empty right now.
# Only fall back to all four when the target has none, so a claude-only project stays
# claude-only unless -Agents says otherwise.
if (-not $PSBoundParameters.ContainsKey('Agents') -and $present.Count) {
    $Agents = $present
}

if ($All) { $Skills = $available.Name }
elseif (-not $Skills) {
    $found = @($installed | Sort-Object -Unique)
    $Skills = @($found | Where-Object { $_ -in $available.Name })
    if (-not $Skills) {
        $hint = if ($Check) { 'nothing to check' } else { 'pass -Skills <name...> or -All' }
        throw "No skills from this repo are installed in $TargetPath ($hint)."
    }
    Write-Host "Found in target: $($Skills -join ', ')" -ForegroundColor DarkGray
}

$selected = @(foreach ($name in $Skills) {
        $s = $available | Where-Object Name -EQ $name
        if (-not $s) { throw "Unknown skill '$name'. Run with -List to see what is available." }
        if ($s.Problems.Count) { throw "Skill '$name' is invalid: $($s.Problems -join '; ')" }
        $s
    })

$agentDirs = [ordered]@{}
$Notes = @()
foreach ($a in $Agents) {
    $dir = Resolve-AgentDir -Agent $a -TargetPath $TargetPath -Selected $Agents
    if ($dir) { $agentDirs[$a] = $dir }
}

$verb = if ($Check) { 'Checking' } else { 'Syncing' }
Write-Host ("`n{0} {1} skill(s) -> {2}" -f $verb, $selected.Count, $TargetPath)
foreach ($n in $Notes) { Write-Status $n.Split('|')[0] $n.Split('|')[1] 'DarkGray' }

# ---- sync / check -------------------------------------------------------------

$drift = 0
foreach ($agent in $agentDirs.Keys) {
    $dir = $agentDirs[$agent]
    Write-Host ("`n{0}  ({1})" -f $agent, $dir) -ForegroundColor Cyan

    foreach ($skill in $selected) {
        $dest = Join-Path $dir $skill.Name
        $srcHash = Get-SkillHash $skill.Path

        if (Test-Path -LiteralPath $dest) {
            if ((Get-SkillHash $dest) -eq $srcHash) { Write-Status 'in-sync' $skill.Name 'DarkGray'; continue }
            if ($Check) { Write-Status 'drift' $skill.Name 'Yellow'; $drift++; continue }
            # Replace wholesale so files deleted upstream do not survive. Only ever
            # touch a directory that actually looks like a synced skill.
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'SKILL.md'))) {
                Write-Status 'refused' "$($skill.Name): $dest exists but has no SKILL.md - not overwriting" 'Red'
                $drift++
                continue
            }
            Remove-Item -LiteralPath $dest -Recurse -Force
            Copy-Item -LiteralPath $skill.Path -Destination $dest -Recurse -Force
            Write-Status 'updated' $skill.Name 'Yellow'
        }
        elseif ($Check) { Write-Status 'missing' $skill.Name 'Yellow'; $drift++ }
        else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Copy-Item -LiteralPath $skill.Path -Destination $dest -Recurse -Force
            Write-Status 'added' $skill.Name 'Green'
        }
    }

    # Anything else in the agent dir. Never touched: it may be a skill written by hand
    # in the target, which this script has no business overwriting or deleting.
    if (Test-Path -LiteralPath $dir) {
        foreach ($o in @(Get-ChildItem -LiteralPath $dir -Directory).Name) {
            if ($o -in $selected.Name) { continue }
            if ($o -in $available.Name) { Write-Status 'orphan' "$o (in this repo, not in this selection)" 'DarkYellow' }
            else { Write-Status 'local' "$o (not from this repo; left alone)" 'DarkGray' }
        }
    }
}

if ($Check) {
    if ($drift) {
        Write-Host "`n$drift difference(s) found.`n" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "`nEverything in sync.`n" -ForegroundColor Green
    exit 0
}

Write-Host "`nRe-sync later with: pwsh $RepoRoot\scripts\sync.ps1 -Target $TargetPath`n"
