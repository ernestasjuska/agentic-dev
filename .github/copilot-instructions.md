# Copilot instructions

Read `CLAUDE.md` in the repository root. It is the canonical guide for this repository.

- This repo stores reusable agent skills. `skills/<name>/SKILL.md` is the single source of
  truth; `scripts/sync.ps1` copies handpicked skills into other projects, including into
  `.github/skills/` for Copilot.
- Nothing to build. `pwsh ./scripts/sync.ps1 -List` validates every skill's frontmatter.
- Before adding or changing a skill, read `skills/skill-authoring/SKILL.md`.
