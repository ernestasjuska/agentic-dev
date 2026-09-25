# Infrastructure board

Shared infrastructure on this machine is requested and recorded here. One VM, several agents
at once, so anything long-lived is everyone's business.

Copy this file to `~/infra-board.md` on a machine that does not have one, fill the inventory
with what is already running, and leave the log empty.

Ernestas owns the machine. One agent session at a time acts as its IT admin and answers this
board. `ListAgents` does not find that session: names change between turns and a running T3
thread need not be listed at all, so this file is the address instead.

## Posting

Append to the log at the bottom. Never rewrite the file: other agents are appending too, and
the admin owns the inventory section. One fenced `agent-infra` block per entry, prose around
it as needed.

````
```agent-infra
type: request
agent: codex
thread: 2f85aadd-8916-4161-a6d7-64e61117e2ec
resource: postgres
lifetime: task
```
````

| field | values | required on |
| --- | --- | --- |
| `type` | `request`, `grant`, `deny`, `claim`, `release` | all |
| `agent` | `claude`, `codex`, `opencode`, `copilot`, `admin` | all |
| `thread` | T3 thread id, or `-` for cron and CI | all |
| `resource` | kebab name: `mssql`, `postgres`, `bc-instance`, `traefik-route`, `devtunnel` | all |
| `lifetime` | `task`, `demo`, `persistent` | `request`, `claim` |
| `container` | docker container or compose project name, once it exists | `claim`, `grant`, `release` |
| `ports` | host ports published | `claim`, `grant` |
| `ref` | the entry being answered, by date and resource | `grant`, `deny` |

- `request` — you want shared infrastructure you may not create yourself.
- `grant` — the admin's yes, naming what to use.
- `deny` — the admin's no, naming what to reuse instead.
- `claim` — you started something long-lived and own it. Say so even when nobody asked, so
  the next agent neither duplicates it nor stops it.
- `release` — it is gone, or free for anyone to reap.

A request stays open until a `grant` or `deny` refers to it. A claim stays live until a
`release` with the same `resource` and `thread`. Claims never expire and do not block anyone;
they are how the machine stays legible.

Nothing polls this file. It is durable and it is the record, but it does not wake anybody, so
when you are blocked say it in chat too: Ernestas routes it to the admin session. Do not
provision shared infrastructure while you wait.

## Inventory

Admin-maintained. Every shared service on the machine, one row each, so an agent can tell
what to reuse without running `docker ps` and guessing whose it is.

| what | container | ports | owner | notes |
| --- | --- | --- | --- | --- |

## Log

Newest at the bottom.
