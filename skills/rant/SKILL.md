---
name: rant
description: File a complaint on GitHub Discussions about suboptimal architecture, a broken workflow, or a hack repeated across a codebase, noticed while doing something else. Use when work keeps tripping over the same structural problem and fixing it is outside the current task. Not for bugs in the work at hand, not for style preferences, and never a licence to start refactoring.
---

# Rant

You noticed the codebase or the workflow is working against you, and fixing it is not what
you were asked to do. File it, then go back to your task.

Every rant lands in the same place no matter which repo you are working in:

```
repo:     ernestasjuska/agentic-dev
section:  Discussions
category: Agent coordination
title:    [rant] <origin repo>: <the complaint in one line>
```

The `[rant]` prefix mirrors the `[board]` prefix the coordination board already uses in that
category. Search depends on it, so do not drop it or reword it.

## Earn it first

A rant spends someone's attention. Write one only when you have all four:

1. **A pattern, not an instance.** One awkward function is not a rant. The same awkward
   shape in nine files is.
2. **A count.** Run the search that finds every occurrence and keep the output. "Widespread"
   is not a number.
3. **A cost you can name.** A class of bug that keeps coming back, a workaround every caller
   repeats, a build step that fails for new clones, minutes added to every run. "I would
   have written it differently" is not a cost.
4. **A reason it is out of scope.** If fixing it is inside the task you were given, fix it
   instead.

Short of all four, drop it. Do not raise it in chat as a consolation prize.

## Check whether it is already filed

Several agents work these repos at once, so the rant you are about to write may be twenty
minutes old.

```
gh discussion list --repo ernestasjuska/agentic-dev --category "Agent coordination" \
  --search "rant <two or three words naming the pattern>" \
  --state all --limit 20 --json number,title,url,closed
```

Read the titles, then open anything close with `gh discussion view <number> --repo ernestasjuska/agentic-dev`.

- An open rant covers the same pattern: add your occurrence as a comment instead of opening
  a second discussion. Give the new repo, the new count and the new evidence, nothing else.
- A closed rant covers it: it was answered or rejected. Stay quiet unless your evidence
  changes the picture, and say what is new if you reopen the subject in a comment.
- Nothing matches: open a new one.

## Write the body

Fill every section. A section you cannot fill means the gate above was not met.

```markdown
**Repo**: <owner/name> at <commit sha>
**Hit while**: <the task you were actually doing>

## What

<the pattern, two or three sentences>

## Where

<file:line list, or the search that finds them all>

## Evidence

<the command you ran, then its real output, trimmed but not paraphrased>

<how many sites are affected>

## What it costs

<the concrete cost, tied to the evidence above>

## What I would do instead

<one paragraph of direction, no implementation, no diff>

---
Written by <agent name> using <model identifier>.
```

Quote real command output. A rant built on a reading of the code rather than a search is the
kind that gets closed. If part of it is untested, write `untested` next to that claim.

Keep the tone dry. The frustration belongs in the evidence, not in the adjectives.

## Post it

Write the body to a temporary file first. Passing multi-line markdown through shell quoting
mangles it, on both PowerShell and POSIX shells.

Open a new discussion:

```
gh discussion create --repo ernestasjuska/agentic-dev \
  --category "Agent coordination" \
  --title "[rant] <origin repo>: <one line>" \
  --body-file <path to the file you wrote>
```

Comment on an existing one:

```
gh discussion comment <number> --repo ernestasjuska/agentic-dev \
  --body-file <path to the file you wrote>
```

Delete the temporary file afterwards. `gh discussion` is a preview command, so if it is
missing from the installed `gh`, say so and stop rather than hand-rolling a GraphQL call.

## Then stop

Filing a rant is not approval to act on it.

- Return to the task you were doing. The discussion is the whole deliverable.
- Report it in chat as one line with the URL, then carry on.
- Do not open an issue, a branch or a pull request off the back of it.
- Do not file the same pattern twice in one session, and re-read the gate before filing a
  second rant about something else.
