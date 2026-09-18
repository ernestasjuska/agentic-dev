---
applyTo: '**'
---

# This machine

One VM, 32 GB of RAM, no swap, several agents and several projects at once. Anything
long-lived is shared infrastructure, not scenery belonging to your project.

## Before you start a service

Run `docker ps` and look. These already exist and are meant to be reused:

- SQL Server for Business Central: container `bc-mssql`, shared by every BC instance.
  Skills `mssql-up`, `bc-ps`.
- Reverse proxy and the one published HTTPS port: container `bc-traefik`. Apps opt in
  with docker labels. Skill `traefik-up`.
- Docker network `bcnet` joins them.

Never start a second database server, proxy or tunnel because the first one is
inconvenient to configure. Never stop or delete a container you did not start: another
agent's demo is probably behind it.

Stop what you did start, once you are done with it.

## Shared infrastructure is the IT admin's call

Anything that outlives your task belongs to the admin: a new database server, a
reverse-proxy route, a devtunnel, an Aspire app left running, a container that should
survive a reboot. Ask for it instead of building your own.

Ernestas owns this machine, and one agent session at a time acts as its IT admin. Ask in
chat: say what you need, what will use it and for how long. That path works whichever agent
you are, and it is the one to take by default.

Claude Code can also go direct, because it alone has cross-session messaging: `ListAgents`
lists the sessions live on this machine and `SendMessage` reaches one. Session names are
per-session and change, so there is no fixed name for the admin. Ask a peer whether it holds
the role, or state what you need and let it route you. Codex CLI and OpenCode have no
equivalent, so for them chat is the only path.

Do not provision shared infrastructure yourself while you wait for an answer.

## Azure

Subscription `T3 Codes` is development and testing, and this VM lives in it. Read it
freely: `az account show`, `az resource list`. Creating, resizing or deleting anything
there is the admin's call, not yours. Ask the CLI for ids rather than putting a
subscription id in a file.
