---
name: take-over
description: Take over a stalled T3 Code thread from a different working thread by leaving claim and completion notes through the T3 orchestration API, then converge back onto the original thread once it unstalls. Use when a thread errored on usage or quota limits, is bound to an unavailable driver, or otherwise cannot continue, and the current thread will do its task instead. Not for normal replies inside the current thread.
---

# Take over a stalled T3 thread

Base directory for this skill: /home/t3admin/.claude/skills/take-over — all
`scripts/takeover.py` paths below are relative to it.

A stalled thread never resumes on its own: its turn sits in `error` and its
session holds the quota or driver error until someone sends a new turn. A
thread is also bound to its driver at creation, so a different driver cannot
continue inside the same thread. The pattern below leaves a visible claim
note, does the work in the current thread, then leaves a completion note and
converges back once the source thread unstalls.

## Prerequisites

- The stalled (source) thread ID and the current thread ID.
- A running T3 Code server on this machine. The script discovers it from the
  T3 data dir (`T3CODE_HOME` env var, else `~/.t3`): file
  `userdata/server-runtime.json` holds `port` and `origin`.
- The `t3` CLI on PATH, Python 3, and the bundled script at
  `scripts/takeover.py` next to this file.

## The script

Every dispatch in this procedure runs through the bundled script; do not
hand-craft command payloads:

```sh
python3 <this-skill-dir>/scripts/takeover.py <subcommand> ...
```

It discovers the server origin and environment ID from the T3 data dir,
mints a 15-minute bearer token on first use (cached at `/tmp/t3-takeover.tok`
and reused for 14 minutes; override with `--token` or `--token-file`), and
prints one JSON object per action. Subcommands: `snapshot`, `link`, `claim`,
`complete`, `title`, `settle`, `wake`, `retire`, `status`, `cleanup`. Run
with `--help` for exact flags. Never paste the token into chat.

## Procedure

### 1. Read the source thread before touching it

```sh
python3 scripts/takeover.py snapshot <sourceThreadId>
python3 scripts/takeover.py link <sourceThreadId>
```

- Note `title`, `latestTurnState`, `lastUserMessage`, and whether
  `takeOverNotes` is non-empty.
- Never start work blind. If the thread already completed or someone else
  already claimed it (`takeOverNotes` non-empty), stop and report instead of
  duplicating the claim.

### 2. Leave the claim note

```sh
python3 scripts/takeover.py claim --source <sourceThreadId> \
  --current <currentThreadId> --task "<one-line task>" \
  --state <latestTurnState> --reason "<why it stalled>"
```

- No `modelSelection` is sent, so the message is recorded without starting a
  turn. A cross-driver `modelSelection` would be rejected with
  `bound to driver ... cannot switch`; the claim note does not need one.
- A `sequence` in the output means the message was recorded, even though no
  turn appears. Accept that: the stalled provider cannot answer by design.

### 3. Set titles, settle the source thread, and link back

```sh
python3 scripts/takeover.py title <currentThreadId> "take-over: <one-line task>"
python3 scripts/takeover.py title <sourceThreadId> "<original title> (stalled, work continued elsewhere)"
python3 scripts/takeover.py settle <sourceThreadId>
```

- Titles are pure metadata. A taking-over thread usually starts as
  `/take-over <sourceThreadId>`, which is unreadable in the thread list.
- Settle the source thread so the thread list shows one real, active thread
  while the work runs elsewhere. Settle is blocked only while the thread has
  a starting/running session, pending user-input requests, or a queued turn
  start; a stalled thread has none of those. If it is still blocked, skip
  settling and say so in the report.
- Make the link visible inside the taking-over thread itself. The claim note
  lands in the source thread, so it does not help readers here. Your next
  reply in this thread must include, on its own line:

  ```text
  Original thread: <link from step 1> (settled during take-over)
  ```

- Do not copy the full source transcript into the taking-over thread and do
  not write transcript files into the project folder; the link is the way
  back to the settled original.

### 4. Verify the note landed

```sh
python3 scripts/takeover.py status <sourceThreadId>
```

`claimNotePresent` must be `true` (the command exits non-zero otherwise).

### 5. Do the work in the current thread

All actual work happens here, not in the stalled thread. Keep the claim
short; put findings, diffs, and verification in the current thread.

### 6. Leave the completion note

```sh
python3 scripts/takeover.py complete --source <sourceThreadId> \
  --current <currentThreadId> --summary "<what was done + how verified>" \
  --task "<one-line original task>"
```

### 7. Converge back onto the source thread once it unstalls

Quota resets and transient driver outages clear. When the source thread's
driver is usable again, collapse the split so one live thread remains:

```sh
python3 scripts/takeover.py wake --source <sourceThreadId> \
  --current <currentThreadId> --done "<what was finished + verification>" \
  --context "<summary of what happened while stalled>" --wait 20
```

- `wake` reads the source snapshot and sends `modelSelection` with the
  source thread's own driver (same-driver is the only accepted case). An
  `error` latestTurn does not block a new turn.
- Unlike the claim note, this must produce a real turn: `turnState` in the
  output must move past `queued` (to `running` and then `completed`). All
  later work on the original task happens in the source thread.
- The turn also un-settles the source thread automatically
  (`thread.unsettled` with reason `activity`), so it becomes the one real,
  active thread again with no extra dispatch.

Then retire the taking-over thread and give the source thread a final title:

```sh
python3 scripts/takeover.py retire <currentThreadId>
python3 scripts/takeover.py title <sourceThreadId> "done: <original task>"
```

`retire` archives (reversible via `thread.unarchive`); add `--hard` to delete
instead. Leave the archived `take-over:` thread title as-is; it is a useful
record of what it was.

Caveat: only the summary text reaches the source thread; the taking-over
thread's tool calls and diffs stay in its snapshot. When the original agent
will need that detail, say so in `--context` and include the taking-over
thread link instead of copying its content over.

### 8. Clean up and report

```sh
python3 scripts/takeover.py cleanup
```

This revokes every bearer session labeled `take-over` and deletes the cached
token file.

Report back: source thread, claim sequence, what was done, verification,
convergence status (source thread resumed and taking-over thread retired, or
the reason convergence was not possible yet, e.g. driver still exhausted),
and the fact that the source thread cannot resume under a different driver
(continuation needs a new linked thread, e.g. via `thread.create` with
history import, not a same-thread provider switch).

## Mistakes to avoid

- Do not write directly to T3 persistence files to fake a message. That
  bypasses projections, idempotency, and remote clients and is unsupported.
- Do not hand-craft dispatch payloads when the script covers the action; the
  script exists to keep command shape, IDs, and timestamps deterministic.
  Only fall back to raw `POST /api/orchestration/dispatch` for actions the
  script lacks, and mirror its command shape exactly.
- Do not expect the stalled thread to answer the claim note. Its provider
  is exhausted or unavailable; the note is a record, not a prompt.
- Do not retarget the source thread with another driver's `modelSelection`
  and treat the rejection as failure. The message still lands; the rejection
  only means no turn runs, which is the point for the claim note. Never use
  a foreign driver's `modelSelection` for the wake-up turn.
- Do not claim a thread that already has a fresh `[take-over]` note without
  checking with the user first.
- Do not archive or delete the taking-over thread before the completion turn
  has landed and completed in the source thread; the summary turn is the
  only record the source thread gets of the work.
- Do not expect the wake-up turn to carry the taking-over thread's tool calls
  and diffs. Only its summary text enters the source thread conversation;
  the rest stays in the retired thread's snapshot.
- Do not leave `/take-over <thread-id>` as the taking-over thread's title.
  Rename it in step 3 and give the source thread a final title in step 7.
- Do not post the take-over link only in the source thread's claim note.
  Readers of the taking-over thread need it too: the next reply there must
  contain the `Original thread: <link>` line (step 3).
- Do not copy the source transcript into the taking-over thread or write
  transcript files into the project folder. Link the settled source thread
  instead (step 3).
- Do not leave the settled source thread settled after convergence. The
  wake-up turn un-settles it on its own; the `wake` output's
  `settledOverride` must no longer be `settled`.
