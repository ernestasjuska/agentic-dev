---
name: bc-down
description: Stop one named Business Central instance without disturbing the shared SQL Server, the shared proxy or other instances. Use when asked to stop, shut down, remove or delete a BC instance or dev environment. Not for stopping the shared database or proxy, which have their own skills.
---

# Stop a BC instance

```
pwsh ./scripts/bc-down.ps1 <name> [-Remove] [-Purge] [-Json]
```

Three levels, increasing in what they destroy. Pick the mildest that does the
job, and say which one you used.

| Flag | Does | Keeps |
|---|---|---|
| *(none)* | `docker compose stop` | Containers, volumes, databases, manifest |
| `-Remove` | `docker compose down` | Volumes, databases, manifest |
| `-Purge` | `down -v` plus deletes the manifest | Nothing. The instance is gone. |

## Before using -Remove or -Purge

Both are worth confirming with the user first, because neither is free:

- `-Remove` costs a re-provision on the next start and, for an Entra-enabled
  instance, a fresh sign-in. BC does not persist its DataProtection keys, so
  auth cookies stop validating the moment the container is recreated.
- `-Purge` discards the instance's databases and its manifest. Its port
  allocation is released and a future instance of the same name gets a fresh
  one.

The shared SQL Server keeps running in every case, so other instances are
unaffected. Use the `bc-ps` skill to see what else is running before stopping
anything.
