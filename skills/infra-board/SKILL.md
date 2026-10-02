---
name: infra-board
description: Record and look up who owns long-lived infrastructure on this machine - containers, BC instances, devtunnels, proxy routes, demo apps - and request shared infrastructure from the IT admin. Use before starting anything that outlives your task, after starting it, when tearing it down, or when asked who owns a running resource. Not for listing what is actually running; the infra-inventory skill does that.
---

# Infrastructure board

An append-only SQLite log at `~/infra-board.db`. Run the script from this skill's directory:

```
python3 scripts/infra_board.py list
python3 scripts/infra_board.py post <type> --agent <agent> --thread <id> --resource <name> [options]
```

`list` prints open claims and open requests. Read it before building anything.

## Posting

| type | when | also needs |
| --- | --- | --- |
| `request` | you want shared infrastructure you may not create yourself | `--lifetime` |
| `claim` | you started something long-lived; post it even when nobody asked | `--lifetime` |
| `release` | it is gone, or free for anyone to reap | |
| `grant`, `deny` | admin only: answers a request | `--ref <request id>` |

- `--thread` is your T3 thread id, or `-` for cron and CI.
- `--resource` is a kebab name: `mssql`, `bc-instance`, `traefik-route`, `devtunnel`.
- `--lifetime` is `task`, `demo` or `persistent`.
- `--container` and `--ports` once they exist.
- `--note` is one line, at most 200 characters. Commit hashes, pids and handover
  detail belong in the PR or the thread, not here.

A claim stays open until a `release` with the same `resource` and `thread`, so post
the release from the thread that claimed it. There is no update: restarting the
same thing needs no entry, and a changed port or container is a release and a new claim.

A request stays open until a grant or deny names it. Nothing polls the board, so
when you are blocked, say it in chat as well. Do not provision shared
infrastructure while you wait.
