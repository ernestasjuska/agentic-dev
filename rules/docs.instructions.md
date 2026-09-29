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

## Chat replies

Say what happened in one line: "I updated the skill and synced it." I own the repo and
know its tools. Skip anything I can see or would already know.

Add more only when it changes what I do next: a failure, a surprise, a decision for me,
something left undone. If I want detail, I will ask.

Don't paste command output for things that worked. A log proves nothing a sentence
doesn't. Paste output for a failure, or when I ask for it.

Headings and `<details>` blocks are not extra room. If a reply needs them, cut it down.

This is about chat only. Code or a diff I asked to see stays visible.
