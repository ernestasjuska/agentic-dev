---
name: line-endings
description: Always use this skill outside agent sandbox so you write files with correct line endings.
---

# Line endings, before the first byte

Find out line correct line ending before writing the file.

## Which ending

Stop at the first answer:

1. Editing a file? Match that file. One file never holds both conventions.
2. Repo has `.gitattributes`? Obey it.
3. Otherwise match a sibling file. `git ls-files --eol` for tracked ones, `file <path>` for
   the rest, which reports "with CRLF line terminators" when they are there.
4. Nothing to go on? LF.

Exceptions to the LF default: `.bat`, `.cmd` and `.sln` take CRLF. `.sh` takes LF always,
including on Windows, because Linux and CI refuse a CRLF script with
`bad interpreter: /bin/bash^M` while Git Bash runs it fine, so passing locally proves
nothing.

## Writing it

The tools disagree on Windows, so pick on purpose.

| want | use |
| ---- | --- |
| LF | a shell heredoc or `printf`. From PowerShell, ``[IO.File]::WriteAllText($p, ($lines -join "`n") + "`n")`` |
| CRLF | PowerShell `Set-Content`, `Out-File`, `Add-Content` or `>` |

Two PowerShell traps. `Set-Content` handed one string containing `` `n `` leaves your LFs
and appends a CRLF, so the file ends up mixed. `[IO.File]::WriteAllLines` follows
`[Environment]::NewLine`, which is CRLF on Windows.

Starting a repo? Commit this first and steps 2 through 4 stop coming up:

```gitattributes
* text=auto eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
```
