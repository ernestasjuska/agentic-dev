---
name: skill-authoring
description: Write or revise a SKILL.md that works unchanged in Claude Code, Codex CLI, GitHub Copilot and OpenCode. Use when creating a new skill, fixing one that never triggers, or porting an agent-specific prompt into a portable skill.
---

# Authoring a portable skill

A skill is a directory: `SKILL.md` plus any scripts, references or templates it needs.
All four agents load the same format, so write once and keep it agent-neutral.

## Frontmatter

Only two fields are portable. Anything else is ignored by at least one agent.

```yaml
---
name: kebab-case-name        # 1-64 chars, ^[a-z0-9]+(-[a-z0-9]+)*$, must equal the directory name
description: What it does + when to use it.   # 1-1024 chars
---
```

The `description` is the only thing an agent sees before deciding whether to load
the body, so it carries the whole triggering burden. Write both halves:

- What it does, in the user's vocabulary, not yours.
- When to use it. Name the concrete situations, and the near-misses to skip.

Bad: `description: Helps with database work.`
Good: `description: Write and review EF Core migrations for this repo's SQL Server schema. Use when adding or altering entities, resolving a migration conflict, or when a migration fails on apply. Not for raw ADO.NET queries.`

## Body

The body only loads once the skill fires, so keep it operational rather than
introductory: steps to follow, decisions to make, commands to run, mistakes to
avoid. Ordered procedures beat prose. Aim for under ~500 lines.

Put anything bulky in sibling files and reference them by relative path
(`See references/schema.md`), so they are read only when actually needed.
Executable helpers go in `scripts/`. Describe what they do and when to run them,
and don't assume the agent will read them to figure it out.

## Portability rules

- Refer to files by relative path from the skill directory; the skill is copied
  into different locations per agent, so absolute paths break.
- Don't reference agent-specific tools by name (no "use the Edit tool", no
  `$ARGUMENTS`, no Claude-only frontmatter like `allowed-tools`). Say what to do,
  not which tool to do it with.
- Assume Windows PowerShell 7 *and* POSIX shells may run it; if a step needs a
  shell, give both forms or ship a script per platform.
- Never bake in secrets, machine-specific paths, or a single project's layout.
  These skills get synced into unrelated repos.

## Checklist before committing

1. Directory name equals frontmatter `name`.
2. Description states what *and* when, and would not fire on unrelated work.
3. Body has no agent-specific tool names or absolute paths.
4. `./scripts/sync.ps1 -List` reports the skill as `ok`.
5. Test it: ask the agent something that should trigger it, and something adjacent
   that shouldn't.
