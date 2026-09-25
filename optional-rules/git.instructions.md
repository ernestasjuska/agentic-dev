---
applyTo: '**'
---

# Git

Agents write the code on this machine, so agents run git. Commit your own work and push
it. Handing back a pile of uncommitted changes and waiting for permission is the failure
mode this rule exists to stop.

## Main is where work goes

Commit to main, push, and say in the reply what landed. No branch, no pull request, no
waiting for an answer that was always going to be yes.

An unmerged branch is worse than no branch. It leaves a working tree the next agent cannot
tell from abandoned, a pull request nobody reads, and a change that reaches no machine
until someone remembers it.

## When a branch earns itself

Branch and open a pull request when the change is big enough, or hard enough to reverse,
that Ernestas would want it in front of him before it lands, or when he asked for one.
Ready for review, never draft, so the review bots run. Authorship goes in the description
per the `agent-authorship` skill, not in the commit message.

Then stop there. Merging is his call, so leave the PR open and put its URL in the reply.
One branch at a time, finished in the session that opened it.

## What stays out

Stage the paths you touched. `git add -A` in a shared checkout sweeps up another agent's
work in progress. Secrets, machine-specific paths and unrelated files never go in.

Never rewrite pushed history, never force-push a branch another agent may have pulled, and
never `git reset --hard` or `git checkout .` over changes you did not make.
