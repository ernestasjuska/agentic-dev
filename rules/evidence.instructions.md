---
applyTo: '**'
---

# Evidence

A claim about what code, a CLI, an API or a database does is worth nothing without the
command that produced it. Run the command. Quote the real output.

## Never assert without proof

- Something exists, or does not exist: prove it with an exhaustive search or query, not a
  reading of the code. Grep the whole tree, including dynamic imports, string lookups,
  reflection and tests.
- A tool or CLI cannot do something: read its official docs first, then demonstrate the
  failure. "I could not find a way" is not "it cannot".
- A field or property is absent: sampling is not proof of absence. Say "not present in 3
  of 40 000 sampled", never "does not exist".
- A mapping or migration: use the official script or table when one exists. Deriving your
  own from observed data is a last resort, and say so.

When you cannot test something, write `untested` next to the claim. That is always an
acceptable answer. A confident wrong answer is not.

## Done means verified

Before reporting work complete: run the build, run the full test suite, paste the actual
command and its actual output. Counts, not adjectives. No "should work", no "this fixes
it" unless you watched it fix it.
