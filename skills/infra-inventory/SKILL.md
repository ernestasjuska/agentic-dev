---
name: infra-inventory
description: Inventory agent-created infrastructure and cleanup candidates on this machine. Use when asked what containers, development services, apps or devtunnels remain running. Not for baseline VM administration.
---

Run `pwsh ./scripts/Get-InfraInventory.ps1` from this skill's directory.
The collector supports Linux; other operating systems report an incomplete check.

Report Docker containers, detached development apps, custom services and
devtunnels. Include stopped containers separately because they still retain
resources. Distinguish locally hosted tunnels from account registrations.

Exclude Azure VM agents, Tailscale, SSH, Home AI and T3 Code infrastructure,
including tunnels serving T3 Code. Keep tunnels serving development apps.
The script collects candidates, not proof of agent ownership. Classify unknown
services and processes using their executable, working directory and listeners.
Do not classify every descendant of T3 Code as baseline: agents launch apps too.

Use the infrastructure board, when available, to identify owners and purpose.
Live inspection takes precedence over its inventory. Do not infer that an
unknown owner or an idle resource makes it safe to delete.

Show names, state, ports, resource usage where available, and cleanup candidates.
Flag incomplete checks. Do not expose credentials or dump process environments.
The script omits command lines and service environments for that reason.

Inventory does not authorize cleanup. When cleanup is requested, establish the
specific resources and whether their data should survive before removing them.
