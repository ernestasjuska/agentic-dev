---
name: bc-ps
description: List the Business Central instances on this machine with their state, health and web client URL, plus the shared SQL Server and proxy they depend on. Use when asked what BC instances exist, which are running, what is on a port, or to check the state of the local BC setup before starting or stopping something.
---

# List BC instances

```
pwsh ./scripts/bc-ps.ps1 [-Json]
```

Lists every instance that has a manifest, not only the running ones, so a
stopped instance is still visible and can be restarted by name. Shared
services are listed separately because no instance owns them.

Columns: instance, state, health, port base, web client URL, and the
BcOnLinux checkout the instance was created from.

## When one is unhealthy

```
pwsh ./scripts/bc-diagnose.ps1 <name>
```

An unhealthy BC container almost always means the NST started and opened no
service port, and the container log still holds every previous boot. This
isolates the current boot at the last entrypoint start, reports which ports are
actually listening, and counts the signatures that explain it: two API hosts
wanting one port, a host calling File.Delete on a missing directory, and which
API type failed to bind. Exit code is non-zero when 7048, 7049 or 7085 is
missing. 7045 is forced off by the entrypoint and 7047 is optional, so neither
counts as missing.

## Reading the output

- `state = absent` with a manifest present means the instance is configured
  but its container does not exist. The `bc-up` skill will recreate it.
- `health` comes from the container healthcheck, which gates only the service
  tier. The web client comes up tens of seconds later, so a healthy instance
  whose web client is not answering yet is normal rather than broken.
- The port base is the instance's allocated block. Individual endpoint URLs
  come from the `bc-describe` skill.

Use `-Json` when you need to act on the result rather than show it.
