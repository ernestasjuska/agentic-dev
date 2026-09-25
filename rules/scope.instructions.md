---
applyTo: '**'
---

# Scope

Build what was asked for. Nothing adjacent, nothing anticipatory.

Do not add, unless I asked for it: abstractions, interfaces or base classes; method
overloads; defensive fallbacks; error swallowing; caches or lookup dictionaries; retry
logic; config files; GitHub issues; new files outside the agreed plan.

If you think something else needs doing, say so in one line and leave it undone. Write it
to a backlog file only if I ask.

## Ask before designing

When the shape of a protocol, interface, schema or data format is not already fixed by
something I gave you, stop and state it before writing code:

1. The types, fields and semantics you intend to implement, numbered.
2. Every assumption, marked as assumption.
3. Every point you are guessing at, marked as a guess.

Then wait. A guess that reaches code costs more to unwind than the question costs to ask.

Refactoring against a passing test suite is not design work. The tests fix the shape, so
run long and autonomously there.

## Editing

Change the lines the task needs. Leave formatting, naming and structure of untouched code
alone, and keep diffs reviewable.
