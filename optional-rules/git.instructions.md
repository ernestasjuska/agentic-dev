---
applyTo: '**'
---

# Git

Agents write the code on this machine, so agents run the git workflow. Commit, push and
open the pull request without asking. Handing back a pile of uncommitted changes and
waiting for permission is the failure mode this rule exists to stop.

## The loop

Branch off main before the first edit, one branch per change, named for the change.
Commit whenever the work reaches a state worth getting back. Push the branch. Open the
pull request when the change is reviewable, not at the end of the session.

Never commit to main directly.

## Pull requests

Open ready for review, never draft, so the review bots run. The title says what changed.
The body says why, and how it was verified, with real command output rather than
adjectives. Authorship belongs in the PR description per the `agent-authorship` skill,
not in the commit message.

Merging is Ernestas's call. Leave the PR open and put its URL in the chat reply.

## What stays out

Stage the paths you touched. `git add -A` in a shared checkout sweeps up another agent's
work in progress. Secrets, machine-specific paths and unrelated files never go in.

Never rewrite pushed history, never force-push a branch another agent may have pulled,
and never `git reset --hard` or `git checkout .` over changes you did not make.
