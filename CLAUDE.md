# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

A personal library of agent skills and agentic-workflow files, plus a script that copies
handpicked skills into other projects. There is no application here and nothing to build.
The deliverable is the content of `skills/`, the content of `rules/`, and the correctness
of `scripts/sync.ps1`.

The owner uses four agents: Claude Code, Codex CLI, GitHub Copilot, OpenCode.

## Commands

```powershell
./scripts/sync.ps1 -List                                    # list skills + validate frontmatter (exit 1 if any invalid)
./scripts/sync.ps1 -Target C:\proj\foo -Skills a,b           # copy picks into a project, all four agents
./scripts/sync.ps1 -Target C:\proj\foo                       # re-sync whatever that project already has
./scripts/sync.ps1 -Target C:\proj\foo -Check                # report drift/missing/orphans, write nothing (exit 1 on drift)
./scripts/sync.ps1 -Target C:\proj\foo -All -Agents claude    # everything, Claude layout only
./scripts/sync.ps1 -Global -Skills a                          # into ~/.claude/skills etc. instead of a project
./scripts/sync.ps1 -Rules                                     # rules/ -> ~/.codex/AGENTS.md (-Check reports drift)
./scripts/sync.ps1 -AgentOwned -Rules                         # also install optional-rules/ into rules/ on this machine
```

`-List` is the closest thing to a test suite. Run it after touching any `SKILL.md`.
Requires PowerShell 7 (`pwsh`), which also covers Linux/macOS and CI. There is deliberately
no second bash implementation to keep in sync.

## Architecture

**One source, copies on sync.** `skills/<name>/SKILL.md` is the single source of truth.
All four agents read the same `SKILL.md` format (name + description frontmatter, markdown
body), so skills are authored once and stay agent-neutral. `sync.ps1` only decides *where*
to put copies. It never rewrites content. If you find yourself wanting to transform a skill
per agent, that belongs in the skill's own wording instead.

**Per-agent destinations** (`Resolve-AgentDir` in `scripts/sync.ps1`):

| agent    | project                       | user-level                    |
| -------- | ----------------------------- | ----------------------------- |
| claude   | `.claude/skills/<name>/`      | `~/.claude/skills/`           |
| codex    | `.codex/skills/<name>/`       | `~/.codex/skills/`            |
| copilot  | `.github/skills/<name>/`      | repo-scoped only              |
| opencode | reuses the Claude copy        | `~/.config/opencode/skills/`  |

OpenCode also reads `.claude/skills` and `~/.claude/skills`, so when `claude` is in
`-Agents` the script writes no separate OpenCode copy and says so. It only writes
`.opencode/skills` when `opencode` is selected *without* `claude`. Preserve that behaviour
when editing. Duplicate copies of one skill in a project are a drift source, not a feature.

**No manifest. Read the target.** A bare `sync.ps1 -Target X` works out the picks by
looking at what is on disk: skill dirs holding a `SKILL.md` under any agent dir are the
selection, and any agent dir that exists at all means the target uses that agent, even
while empty. So a claude-only project stays claude-only, and `-Check` needs no state file
to run in CI. Targets are still consumers, not sources. Names and directory layout are the
only things read back out of a target, never skill *content*.

**Copy semantics.** A changed skill is deleted and re-copied wholesale so files removed
upstream don't survive, but the script refuses to overwrite a destination directory that
has no `SKILL.md`. That guard is the only thing standing between a typo'd `-Target` and
someone's real directory. Keep it. Orphans (skill dirs in an agent dir that are not in the
current selection) are reported, never deleted.

## Rules

`rules/*.instructions.md` are always-loaded behavioural rules, not skills. Skills load on
demand; these are charged to every session in every repo, so they stay short.

Three of the four agents read `rules/` live and cannot drift: Claude Code through a
`~/.claude/rules` junction, OpenCode through an `instructions` glob in
`~/.config/opencode/opencode.jsonc`, Copilot because VS Code lists the same directory in
`chat.instructionsFilesLocations` by default.

```powershell
New-Item -ItemType Junction -Path ~\.claude\rules -Target <repo>\rules
```

Codex loads exactly one global file, `~/.codex/AGENTS.md`, and a pointer in it to the
directory is not reliably followed, so `sync.ps1 -Rules` writes the rule bodies into that
file. Editing a rule means re-running it; `-Rules -Check` exits 1 when that file is stale.

`optional-rules/` holds rules that suit only a machine where agents are the only ones
writing code, such as committing and opening pull requests unasked. Live reading is what
makes the directory necessary: anything in `rules/` reaches every machine holding the
junction, so these sit outside it and `-AgentOwned` copies them in, which is also how they
reach the Codex file. The installed copies are gitignored. A new optional rule needs its
name added to `.gitignore`, or the next commit turns it into a rule for every machine.

The `.instructions.md` suffix and `applyTo` frontmatter are what Copilot needs to apply a
file automatically. Claude Code reads every `.md` under the directory and loads any rule
without a `paths` key unconditionally. Keep both so one file serves both agents.

A junction needs no elevation on Windows, unlike a symlink. Recreate it per machine; it is
not something the repo can carry.

## Authoring conventions

`skills/skill-authoring/SKILL.md` is the canonical, enforced contract. Read it before
adding or editing a skill rather than re-deriving the rules. The parts `sync.ps1` actually
validates: directory name must equal frontmatter `name`, `name` must match
`^[a-z0-9]+(-[a-z0-9]+)*$`, `description` must be present and at most 1024 chars.

**Copied-in skills.** A skill lifted from a public repo becomes an ordinary skill here.
Edit it like any other, hold it to the same contract, and don't track it against wherever
it came from. There is no provenance file and no upstream to stay in step with. One
exception, in case this repo is ever made public: check whether a copied skill arrived with
a license before publishing, because that question outlives the copy.

The byte-for-byte tracking that does matter runs between this repo and the projects synced
from it. `skills/` is the source for every target, and `-Check` is what proves a target's
copies still match. Never edit a skill inside a target to make `-Check` pass; edit it here
and re-sync.

Everything in `skills/` gets copied into unrelated repos, so no absolute paths, no
machine-specific paths, no secrets, and no agent-specific tool names or frontmatter keys
(`allowed-tools`, `$ARGUMENTS`). At least one of the four agents ignores or chokes on each.

## Instruction files

`CLAUDE.md` is canonical. `AGENTS.md` (read by Codex CLI and OpenCode) and
`.github/copilot-instructions.md` (Copilot) are thin pointers to it. When repo structure or
commands change, update this file and check those two still tell the truth. Those three
files describe this repo. `rules/` is different: it ships behaviour to every repo on the
machine, so nothing repo-specific belongs in it.
