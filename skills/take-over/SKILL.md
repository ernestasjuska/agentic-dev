---
name: take-over
description: Take over a stalled T3 Code thread from a different working thread by leaving claim and completion notes through the T3 orchestration API. Use when a thread errored on usage or quota limits, is bound to an unavailable driver, or otherwise cannot continue, and the current thread will do its task instead. Not for normal replies inside the current thread.
---

# Take over a stalled T3 thread

A stalled thread never resumes on its own: its turn sits in `error` and its
session holds the quota or driver error until someone sends a new turn. A
thread is also bound to its driver at creation, so a different driver cannot
continue inside the same thread. The pattern below leaves a visible claim
note, does the work in the current thread, then leaves a completion note.

## Prerequisites

- The stalled (source) thread ID and the current thread ID.
- A running T3 Code server on this machine. Find its origin in the T3 data
  dir (`T3CODE_HOME` env var, else `~/.t3`): file `userdata/server-runtime.json`
  holds `port` and `origin` (commonly `http://127.0.0.1:3773`).
- The `t3` CLI on PATH for minting a short-lived bearer token.

## Procedure

### 1. Read the source thread before touching it

Fetch a snapshot so the claim note states the real task and state:

- `GET /api/orchestration/threads/<sourceThreadId>` with a bearer token.
- Note title, project, branch, `latestTurn.state`, and the last user message.

Never start work blind. If the thread already completed or someone else
already claimed it (look for a `[take-over]` / `[assist]` note among its
latest messages), stop and report instead of duplicating the claim.

### 2. Mint a short-lived token

POSIX shell:

```sh
t3 auth session issue --label take-over --ttl 15m --token-only > /tmp/t3-takeover.tok
```

PowerShell:

```powershell
t3 auth session issue --label take-over --ttl 15m --token-only | Set-Content /tmp/t3-takeover.tok
```

Revoke every session listed by `t3 auth session list` that was minted for
this procedure once finished. Never paste the token into chat.

### 3. Leave the claim note

Send one `thread.turn.start` dispatch to the source thread:

```json
{
  "type": "thread.turn.start",
  "commandId": "<new-uuid>",
  "threadId": "<sourceThreadId>",
  "message": {
    "messageId": "<new-uuid>",
    "role": "user",
    "text": "[take-over] Thread <currentThreadId> (<instance>/<model>) has taken over: <one-line task>. Source turn was <state> (<reason>). Work continues in the taking-over thread; no reply needed here.",
    "attachments": []
  },
  "runtimeMode": "full-access",
  "interactionMode": "default",
  "createdAt": "<now-utc-iso>"
}
```

- `POST` it to `/api/orchestration/dispatch` with `Authorization: Bearer <token>`.
- Omit `modelSelection` unless the taking-over driver equals the source
  thread's driver. A cross-driver `modelSelection` is rejected with
  `bound to driver ... cannot switch`, which still records the message but
  creates no turn. That outcome is expected and acceptable for a claim note.
- A `200 {"sequence": N}` means the message was recorded, even when no new
  turn appears. Accept that: the stalled provider cannot answer by design.

Example (Python stdlib, works on any OS with Python 3):

```python
import json, uuid, datetime, urllib.request
origin = "http://127.0.0.1:3773"  # from server-runtime.json
token = open("/tmp/t3-takeover.tok").read().strip()
cmd = {
    "type": "thread.turn.start",
    "commandId": str(uuid.uuid4()),
    "threadId": "<sourceThreadId>",
    "message": {"messageId": str(uuid.uuid4()), "role": "user",
                "text": "[take-over] ...", "attachments": []},
    "runtimeMode": "full-access",
    "interactionMode": "default",
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
req = urllib.request.Request(origin + "/api/orchestration/dispatch",
    data=json.dumps(cmd).encode(),
    headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
print(urllib.request.urlopen(req, timeout=15).read()[:200])
```

### 4. Verify the note landed

Re-fetch the thread snapshot or list its latest messages and confirm the
`[take-over]` text is present. Safe read-only checks that never start a
turn: `threadSnapshot`, or metadata writes such as `thread.pin` /
`thread.unpin` only when a visible marker is wanted (both are reversible).

### 5. Do the work in the current thread

All actual work happens here, not in the stalled thread. Keep the claim
short; put findings, diffs, and verification in the current thread.

### 6. Leave the completion note

Repeat step 3 with a second dispatch:

```text
[take-over] Thread <currentThreadId> finished: <what was done + how verified>.
Original task: <one line>. See the taking-over thread for details.
```

### 7. Clean up and report

1. Revoke the minted sessions (`t3 auth session revoke <session-id>`)
   and delete the token file.
2. Report back: source thread, claim sequence, what was done, verification,
   and the fact that the source thread cannot resume under a different
   driver (continuation needs a new linked thread, e.g. via `thread.create`
   with history import, not a same-thread provider switch).

## Mistakes to avoid

- Do not write directly to T3 persistence files to fake a message. That
  bypasses projections, idempotency, and remote clients and is unsupported.
- Do not expect the stalled thread to answer the claim note. Its provider
  is exhausted or unavailable; the note is a record, not a prompt.
- Do not retarget the source thread with another driver's `modelSelection`
  and treat the rejection as failure. The message still lands; the rejection
  only means no turn runs, which is the point.
- Do not claim a thread that already has a fresh `[take-over]` note without
  checking with the user first.
