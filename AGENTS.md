# AGENTS.md

Read `CLAUDE.md`. It is the canonical guide for this repository and applies to you too.

Quick orientation:

- This repo stores reusable agent skills. `skills/<name>/SKILL.md` is the single source of
  truth; `scripts/sync.ps1` copies handpicked skills into other projects in the layout each
  agent expects (`.claude/skills`, `.codex/skills`, `.github/skills`, `.opencode/skills`).
- Nothing to build. `pwsh ./scripts/sync.ps1 -List` validates every skill's frontmatter and
  is the check to run after editing a `SKILL.md`.
- Before adding or changing a skill, read `skills/skill-authoring/SKILL.md`, the portability
  contract these skills must satisfy.
- `rules/*.instructions.md` are always-on behavioural rules for every repo on this machine,
  reaching the agents through a `~/.claude/rules` junction rather than through `sync.ps1`.
  Nothing repo-specific goes in them.
