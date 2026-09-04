# agentic-dev

My library of AI agent skills and agentic-workflow files, with a one-command way to drop
handpicked skills into any other project.

Works with Claude Code, Codex CLI, GitHub Copilot and OpenCode. All four read the same
`SKILL.md` format, so each skill is written once.

## Layout

```
skills/<name>/SKILL.md    one skill per directory, the single source of truth
rules/*.instructions.md   always-on agent rules, junctioned into ~/.claude/rules
scripts/sync.ps1          copies handpicked skills into a project or your user profile
CLAUDE.md                 canonical repo guide (AGENTS.md + copilot-instructions point to it)
```

## Rules

Skills load when an agent decides it needs one. `rules/` is the other kind: always-on
behaviour, loaded into every session in every repo.

These are not synced. Point the machine at the repo once:

```powershell
New-Item -ItemType Junction -Path $HOME\.claude\rules `
         -Target C:\My\Git\github.com\ernestasjuska\agentic-dev\rules
```

Claude Code reads `~/.claude/rules` as user-level rules. VS Code lists the same path in
`chat.instructionsFilesLocations` by default, so Copilot reads it too. One folder, one copy,
both agents, no drift. A junction needs no elevation. Run it again on each new machine.

## Use it from another project

Requires PowerShell 7 (`pwsh`), which is cross-platform, so this also works on Linux/macOS
and CI.

```powershell
# see what's available
pwsh C:\My\Git\github.com\ernestasjuska\agentic-dev\scripts\sync.ps1 -List

# copy picks into a project, for all four agents
pwsh C:\My\Git\github.com\ernestasjuska\agentic-dev\scripts\sync.ps1 -Target . -Skills skill-authoring

# later: re-sync whatever that project already has
pwsh C:\My\Git\github.com\ernestasjuska\agentic-dev\scripts\sync.ps1 -Target .

# is the project's copy stale?
pwsh C:\My\Git\github.com\ernestasjuska\agentic-dev\scripts\sync.ps1 -Target . -Check
```

Worth adding to your PowerShell profile:

```powershell
function Sync-Skills {
    pwsh C:\My\Git\github.com\ernestasjuska\agentic-dev\scripts\sync.ps1 @args
}
```

Then it's just `Sync-Skills -Target . -Skills foo,bar`.

## Where skills land

| agent    | project                  | `-Global`                    |
| -------- | ------------------------ | ---------------------------- |
| claude   | `.claude/skills/`        | `~/.claude/skills/`          |
| codex    | `.codex/skills/`         | `~/.codex/skills/`           |
| copilot  | `.github/skills/`        | repo-scoped only             |
| opencode | reuses the Claude copy   | `~/.config/opencode/skills/` |

OpenCode reads `.claude/skills` too, so it shares the Claude copy instead of getting a
duplicate.

No manifest, no state file. A bare `-Target X` reads the target to see what it already has:
the skill directories are the picks, and the agent directories that exist are the agents.
Adding an agent later means naming it once with `-Agents`.

Copies don't update themselves. Run `-Check` (exit code 1 on drift) to find stale ones, or
`-Target X` with no `-Skills` to refresh what is there. Skills you wrote by hand in a target
are reported as `local` and never touched.

## Adding a skill

```
skills/my-skill/SKILL.md
```

with frontmatter:

```yaml
---
name: my-skill
description: What it does, and when the agent should use it.
---
```

Read [skills/skill-authoring/SKILL.md](skills/skill-authoring/SKILL.md) first. It's the
portability contract. Then run `sync.ps1 -List` to validate.
