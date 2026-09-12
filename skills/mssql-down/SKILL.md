---
name: mssql-down
description: Stop the shared SQL Server used by Business Central instances on this machine. Use when asked to stop or remove the shared database server, or to free its resources. Not for stopping a single BC instance, which has its own skill and leaves the database running.
---

# Stop the shared SQL Server

```
pwsh ./scripts/mssql-down.ps1 [-Remove] [-Purge] [-Json]
```

| Flag | Does | Keeps |
|---|---|---|
| *(none)* | stops the container | Databases |
| `-Remove` | deletes the container | Databases, on their volume |
| `-Purge` | `down -v` | Nothing. Every instance's database is gone. |

## Check first

Every running BC instance shares this server, so stopping it makes all of them
start failing SQL calls. The script warns when instances are still running;
list them with the `bc-ps` skill and stop them first with `bc-down` unless the
user wants the abrupt version.

`-Purge` is destructive across every instance at once, not just one. Confirm
with the user before using it, and say plainly what will be lost.
