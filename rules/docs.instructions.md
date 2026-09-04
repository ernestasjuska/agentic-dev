---
applyTo: '**'
---

# Docs

Always-loaded instruction files (`CLAUDE.md`, `AGENTS.md`, `copilot-instructions.md`,
rules) are charged to every session's context. Every line must earn that.

## Never include

Anything an agent can read for itself: file inventories, directory trees, ID ranges, app
ids, analyzer or ruleset listings, skill listings, dependency lists, exported symbols.
If it lives in `app.json`, a manifest or the filesystem, link to it or leave it out.

## Write

Current state only. Never before/after, never a migration narrative, never "we used to".
The reader has no memory of the old shape and does not need one.

Facts that go stale get a pointer to their source instead of a copy.

Keep it under 200 lines. Prefer pitfalls, conventions that differ from the tool default,
and reasons, over description.

## Before writing

Show me the draft in chat first. Do not create the file and then ask.

Prose rules from the `unslop` skill apply to anything a person reads.
