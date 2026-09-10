---
name: babysit-pr
description: Keep working on an open pull request until feedback is addressed, required checks pass, review bots report no actionable issues, and the PR is ready to merge. Use when asked to babysit, shepherd, monitor, or finish a PR through review. Not for merely reviewing a PR or merging it.
---

# Babysit a pull request

Own the pull request until it is ready to merge. Do not merge it unless the user also asks you to.

## Establish the target and permissions

1. Identify the pull request from the current branch, repository context, or user-provided URL or number. If several open pull requests are plausible, ask which one.
2. Read the repository instructions before changing code. Inspect the full pull request diff, current checks, reviews, inline threads, conversation comments, and merge state.
3. Treat fixing the pull request branch, pushing those fixes, replying to feedback, and resolving threads after fixes as part of babysitting. Do not make unrelated changes, weaken tests, dismiss findings without evidence, alter branch protection, approve your own work, or merge unless separately authorized.
4. If the pull request comes from a fork or the branch cannot be updated, report the access problem after confirming it. Continue any useful read-only diagnosis.

## Work the feedback loop

Repeat this loop until the readiness conditions below hold:

1. Refresh the pull request state. New comments and check results can arrive while you work.
2. Build one list of unresolved work from all sources:
   - failing, cancelled, timed-out, or stale required checks;
   - unresolved review threads and change requests;
   - actionable pull request conversation comments;
   - review-bot findings, including comments posted by workflow or app accounts;
   - conflicts or mergeability problems caused by the pull request branch.
3. Classify each item before acting:
   - Fix valid findings in the smallest coherent change.
   - For a false positive or already-fixed finding, verify that with code, tests, or check output, then reply with the evidence.
   - Ask the user only when feedback requires a product decision, new authority, secrets, unavailable infrastructure, or a material scope expansion.
4. Reproduce relevant failures locally when practical. Run the narrowest useful tests while editing, then run the repository's required validation before pushing.
5. Review the resulting diff for accidental changes. Commit and push the coherent fix to the pull request branch.
6. Reply to each handled comment with what changed or why no change is needed. Resolve a review thread only after its concern is fixed or answered with evidence. Never resolve a thread merely to make the count reach zero.
7. Wait for checks and bots triggered by the new commit. Poll at a reasonable interval and inspect failures as soon as they complete. A successful build does not supersede unresolved review feedback, and an approving review does not supersede failed checks.
8. If a check appears flaky, retry it only after inspecting its output and finding evidence of a transient failure. Do not repeatedly rerun a deterministic failure.

When checks or bots do not start automatically, use the repository's normal, documented trigger if one exists. Do not invent no-op commits, close and reopen the pull request, or mention bots solely to trigger work unless the repository already uses that convention.

## Decide when it is ready

The pull request is ready only when all of these are true on the current head commit:

- every required check has completed successfully;
- no review is requesting changes;
- no actionable conversation comment or unresolved review thread remains;
- review bots have completed their latest pass and report no actionable findings;
- the branch has no merge conflicts and the hosting service reports it as mergeable;
- the pull request is not a draft;
- local validation required by the repository passes; and
- the final diff still matches the pull request's stated purpose.

Do one final refresh after the last check finishes so late bot comments are not missed. Report the head commit, checks run, feedback handled, and any non-blocking caveat. Say that the pull request is ready to merge, then stop without merging.

## When to stop short

Keep monitoring when checks are pending or reviewers and bots are still working. Stop and explain the blocker when progress needs user input or access, external infrastructure remains unavailable, the same confirmed transient failure survives reasonable retries, or fixing the finding would materially change the requested scope. Do not claim readiness while relying on an expected future result.
