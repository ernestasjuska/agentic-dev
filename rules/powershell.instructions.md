---
applyTo: '**'
---

# Windows shell

This machine is Windows. PowerShell 7 (`pwsh`) is the shell for real work.

## Traps that fail silently

These produce wrong numbers rather than errors, so they survive to the report:

- `@()` is falsy. An empty array in `if ($x)` takes the else branch. Test `$x.Count -eq 0`.
- `0 -eq ''` is `$true`. So is `0 -eq $null` in the wrong order. Compare with explicit
  casts, and use `-ne $null` rather than truthiness for any numeric.
- A single-element pipeline result is not an array. Wrap in `@()` before `.Count`.
- `$null` on the left of a comparison is the only reliable order: `$null -ne $x`.

## Filters must account for themselves

Print the row count before and after every filter. Rows removed by a filter must not
appear in any later denominator, share or percentage. State which rows were dropped and
why. A share that sums to something other than the whole is a bug, not a rounding artefact.

## Quoting

- Never put a PowerShell here-string inside a Bash command. It mangles git commit messages.
- Multi-line file content goes through the file-writing tool, not shell redirection.
- Backslash path globs get eaten by escape interpretation. Quote them, and verify the
  expansion is non-empty before trusting a command that consumed it.

## Targets

Never point a test config, connection string or script at a live Business Central or
Cosmos endpoint. Local containers or an explicitly named test target only. Confirm which
container and document type a query hits before drawing a conclusion from what it returns.
