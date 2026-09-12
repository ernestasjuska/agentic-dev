---
name: traefik-down
description: Stop the shared Traefik reverse proxy that fronts local web apps, taking them off the shared public port while leaving the apps themselves running. Use when asked to stop the local reverse proxy or ingress, or to free its published port. Not for stopping the apps behind it, which keep running and stay reachable on their own ports.
---

# Stop the shared reverse proxy

```
pwsh ./scripts/traefik-down.ps1 [-Remove] [-Json]
```

Stops the container by default; `-Remove` deletes it. Backends keep running
either way, they just stop being reachable through the shared port and through
any tunnel pointed at it. Each app is still reachable directly on its own
published port, which the `bc-describe` skill lists for BC instances.

The script reports which routed containers are about to go dark, so the effect
is visible before it surprises anyone.

Nothing here has state worth purging: the compose file and the dynamic
configuration are regenerated on every `traefik-up`, so stopping and starting
is safe and loses nothing.
